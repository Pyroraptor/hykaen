extends GutTest
## tests/boot/test_cast_a_spell_real_composition_root.gd — FEAT-285
## (resolves PR-002/PR-004; US-005..US-012)
##
## Peer-review BLOCKER fix: tests/e2e/test_steel_thread_cast_a_spell.gd's/
## tests/e2e/test_determinism_pinned_seed_cast_a_spell.gd's own
## "_wire_real_cast_spell_controller()" helper `instance._verb_deps().duplicate()`s
## the REAL composition root's deps dict and then MANUALLY OVERWRITES its
## "resolve_spell_controller" entry with a hand-wired ResolveSpellController
## (carrying a scripted TargetingPort, a second/parallel ResolutionPort, and a
## second/parallel CombatLogPanelAdapter) before ever installing it into
## `instance._controllers["CAST_SPELL"]`. That override proves only that the
## CODE compiles against a test double — it can never prove FEAT-283's real
## `_verb_deps()` wiring (`targeting_port`/`resolution_port`/`combat_log_port`/
## `energy_pool_fn`, MainScene.gd's `spell_targeting_port`/`spell_resolution_port`/
## `spell_combat_log_port` fields) is itself correct, because the override
## REPLACES exactly the collaborator that would expose a wiring bug (PR-002/
## PR-004's finding). tests/boot/test_cast_spell_verb_deps_composition_root_wiring.gd
## (FEAT-283) already closed this gap for Channel alone; this suite is the
## Fire-Bolt-carrying, Opportunistic-Strike-carrying companion that closes it
## for the full steel thread.
##
## This suite drives the SAME "Cast a Spell" steel thread
## tests/e2e/test_steel_thread_cast_a_spell.gd exercises — entry point
## (`instance._controller("CAST_SPELL")` / `instance._verb_bar_cast_spell_execute()`)
## through Fire Bolt (2 actions, spanning a TURN boundary, provoking a
## non-lethal Opportunistic Strike) and Channel (1 action, self-resolving) —
## to the SAME exit points (combat log, hp, energy pool) — with ONE
## structural difference that is this feature's entire point: NO file in
## this suite EVER reads `instance._verb_deps()`, `.duplicate()`s it, or
## writes to `instance._controllers["CAST_SPELL"]`. Every collaborator
## (TargetingPort, ResolutionPort, CombatLogPort, RoundEnergyPoolPort,
## SpellCatalogPort, ReactionWindowPort) is whatever the real, booted
## MainScene.gd wired at `_ready()` — including the real single-enemy-picking
## `_FirstLegalTargetingPort` default (MainScene.gd, FEAT-283) that makes a
## scripted TargetingPort double unnecessary in the prologue's one-enemy
## fixture. Fixture-state overrides (hex_coord/ac/hp_current/reflex — plain
## public Combatant fields, never a port) remain, mirroring every prior
## boot-real Cast-a-Spell suite's own established "force deterministic
## fixture state, never fabricate an outcome" convention (e.g. tests/boot/
## test_cast_provokes_opportunistic_strike.gd) — those are domain-entity
## fixture setup, not dependency substitution of any port.
##
## test_criteria satisfied:
##   1. Obtains the CAST_SPELL controller via `instance._controller("CAST_SPELL")`
##      with zero manual dependency substitution/duplicate() of any port.
##   2. Drives a full Fire Bolt cast (2 actions) spanning a turn boundary,
##      asserting remaining_actions decrements correctly using only the real
##      `_verb_deps()` wiring.
##   3. An in-range enemy's Opportunistic Strike reaction fires during the
##      casting action via the real ReactionWindowPort adapter (non-lethal
##      path — continues, does not cancel).
##   4. Final targeted resolution produces a real ResolutionPort roll,
##      applies a DAMAGE effect via the real EffectsApplierPort reducing
##      target hp, clears casting_state, and emits a real CombatLogPort
##      entry visible in the log.
##   5. Casts Channel through the SAME real composition root and asserts the
##      caster's round EnergyPool.current increases by 1 with a
##      corresponding combat-log entry.
##   6. Running twice at the pinned seed produces identical roll/damage/
##      reaction outcomes (determinism check for this new test).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const CombatLogEntryClass        = preload("res://core/domain/combat_log_entry.gd")
const RoundEventsClass           = preload("res://core/rules/round_events.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const ErrorCodeClass             = preload("res://core/application/ports/errors.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/e2e/test_steel_thread_cast_a_spell.gd's identically-named/
## valued constant), pinned via `seed_override` (ADR-004's top-precedence
## contract) so every real, unwired ResolutionPort roll this suite drives is
## deterministic/replayable (NFR-002).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT / SURVIVABLE_HP -- mirror tests/boot/
## test_cast_provokes_opportunistic_strike.gd's identically-named/valued
## constants: an absurdly low AC guarantees a real, unscripted resolved hit
## with no RNG/seed edits, and a comfortably-high hp keeps the target alive
## so this suite can assert on post-hit state (never a fabricated outcome).
const AC_GUARANTEED_HIT: int = -1000
const SURVIVABLE_HP: int = 500

## _ENEMY_HP_HANDICAP -- mirrors tests/e2e/
## test_determinism_pinned_seed_cast_a_spell.gd's identically-motivated
## fixture: the real prologue Skeleton (8 hp) is one-shot-killable by a
## guaranteed-hit Fire Bolt, which would end the encounter (outcome "won")
## before this suite's own later Channel leg ever runs. Bumping its real,
## live hp keeps it alive through the whole scenario with no change to any
## other stat/behavior.
const _ENEMY_HP_HANDICAP: int = 200

## _MAX_TURN_EXCHANGES -- safety bound on the bounded turn-advancing loop
## below (CWE-835 "never loop unbounded" guard, mirroring tests/e2e/
## test_determinism_pinned_seed_cast_a_spell.gd's identically-motivated
## constant).
const _MAX_TURN_EXCHANGES: int = 30


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives Cast-a-Spell verbs
## directly against `round_session`/the verb registry, so `_boot_main_scene()`
## now also drives the SAME real handoff, landing the instance in
## GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


## _advance_to_marigolds_turn(instance) -> void -- Titus acts first in the
## prologue's turn order (seed=42); pass turns (EndTurnControl is ALWAYS
## available, regardless of whether an action was spent) until it is
## Marigold's live turn (mirrors every prior Cast-a-Spell boot-real suite's
## identically-named helper), bounded by _MAX_TURN_EXCHANGES (CWE-835).
func _advance_to_marigolds_turn(instance) -> void:
	var exchanges: int = 0
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold" and exchanges < _MAX_TURN_EXCHANGES:
		exchanges += 1
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")
	assert_lt(exchanges, _MAX_TURN_EXCHANGES, "must reach Marigold's turn within the bounded exchange budget")


## _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void --
## mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named helper exactly: forces Marigold's OWN live hex_coord
## (a plain public Combatant field, never a port) adjacent to the Skeleton's
## so its melee-only weapon can legally provoke an Opportunistic Strike
## window. Casting never relocates the caster, so this forced position
## stays valid for every action driven against it.
func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- obtains the CAST_SPELL controller via
# instance._controller("CAST_SPELL") with ZERO manual dependency
# substitution/duplicate() of any port; every port `_controller()` resolves
# through is the SAME real adapter MainScene.gd's own _ready() constructed.
# ══════════════════════════════════════════════════════════════════════════

func test_controller_cast_spell_is_real_spell_action_controller_from_unmodified_verb_deps() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	# No `instance._verb_deps().duplicate()` / `instance._controllers[...] = ...`
	# ANYWHERE in this file -- `_controller()` is called exactly as production
	# code (`_verb_bar_cast_spell_execute()`) calls it.
	var controller = instance._controller("CAST_SPELL")
	assert_true(controller is SpellActionControllerClass, "_controller(\"CAST_SPELL\") must return a real SpellActionController")
	assert_same(controller, instance._controllers.get("CAST_SPELL"), "_controller() must memoize the SAME instance into _controllers")

	var deps: Dictionary = instance._verb_deps()
	assert_same(deps.get("targeting_port"), instance.spell_targeting_port, "the real _verb_deps() targeting_port must be the SAME adapter MainScene._ready() constructed -- never a test-only override")
	assert_same(deps.get("resolution_port"), instance.spell_resolution_port, "the real _verb_deps() resolution_port must be the SAME adapter MainScene._ready() constructed -- never a test-only override")
	assert_same(deps.get("combat_log_port"), instance.spell_combat_log_port, "the real _verb_deps() combat_log_port must be the SAME adapter MainScene._ready() constructed -- never a test-only override")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2-5 -- Fire Bolt across a turn boundary (remaining_actions decrements
# correctly), a non-lethal Opportunistic Strike fired via the real
# ReactionWindowPort adapter during the casting action, final resolution via
# the real ResolutionPort/EffectsApplierPort/CombatLogPort, and Channel
# self-resolution (+1 energy) through the SAME real composition root -- with
# NO dependency override anywhere in this test.
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_and_channel_cast_end_to_end_through_real_composition_root_zero_overrides() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("fire_bolt"), "fixture assumption: Marigold must know Fire Bolt")
	assert_true(marigold.known_spell_ids.has("channel"), "fixture assumption: Marigold must know Channel")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]
	assert_true(
		not skeleton.weapon.has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach (no 'range_hexes' key)"
	)

	# Handicap the Skeleton's hp so the guaranteed-hit Fire Bolt below cannot
	# end the encounter before the Channel leg of this scenario runs (mirrors
	# tests/e2e/test_determinism_pinned_seed_cast_a_spell.gd's own
	# identically-motivated fixture). Guarantee Fire Bolt hits (Reflex) so
	# "target hp reduced on hit" is deterministic, never a conditional branch.
	skeleton.hp_current = _ENEMY_HP_HANDICAP
	skeleton.hp_max = _ENEMY_HP_HANDICAP
	skeleton.reflex = AC_GUARANTEED_HIT
	var skeleton_hp_before_fire_bolt: int = skeleton.hp_current

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	# Adjacent so the melee-only Skeleton can legally provoke Opportunistic
	# Strike; guaranteed-hit-but-survivable so the reaction's own resolved
	# outcome (hit + damage) is captured deterministically without
	# terminating the scenario in a lethal cancellation (that path is already
	# covered by tests/e2e/test_steel_thread_cast_a_spell.gd's own dedicated
	# suite).
	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	# ── Criterion 1 (re-asserted in this scenario's own context): the entry
	# point is the real, memoized CAST_SPELL controller. ────────────────────
	var controller = instance._controller("CAST_SPELL")
	assert_true(controller is SpellActionControllerClass, "_controller(\"CAST_SPELL\") must return a real SpellActionController")
	assert_same(controller, instance._controllers.get("CAST_SPELL"), "_controller() must memoize the SAME instance into _controllers")

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()
	var marigold_hp_before_os: int = marigold.hp_current

	# ── entry point: the FIRST CAST_SPELL action (select verb + pay energy),
	# driven through the SAME production `_verb_bar_cast_spell_execute()`
	# shim a live player click resolves through -- `instance._controllers`
	# is NEVER written to anywhere in this file. ────────────────────────────
	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first CAST_SPELL action (select verb + pay energy) must succeed")
	assert_true(marigold.is_casting(), "Fire Bolt costs 2 actions -- Marigold must now be mid-cast")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "the first action must decrement remaining_actions from 2 to 1")

	# ── Criterion 3: an in-range enemy's Opportunistic Strike reaction fires
	# during the casting action via the REAL ReactionWindowPort adapter
	# (`reaction` in _verb_deps(), the SAME ReactionController Strike/Stride
	# already share) -- non-lethal, so the cast continues rather than being
	# cancelled. ──────────────────────────────────────────────────────────────
	var reaction_result: Dictionary = begin_result.get("reaction_result", {})
	var reactions: Array = reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "exactly one reactor (the adjacent Skeleton) must have been offered a window by the real ReactionWindowPort adapter")
	assert_eq(reactions[0].get("choice", ""), "opportunistic_strike", "the real AIReactionPolicy must genuinely choose opportunistic_strike when melee-legal and the RESERVE gate is open")
	assert_false(reaction_result.get("mover_downed", true), "a non-lethal Opportunistic Strike must NOT report mover_downed")
	assert_true(reaction_result.get("stride_should_commit", false), "a non-lethal Opportunistic Strike must leave stride_should_commit true -- the cast must continue, not cancel")
	assert_true(marigold.is_casting(), "the non-lethal path must leave the cast in progress -- casting_state must NOT be cleared")
	assert_ne(begin_result.get("error"), ErrorCodeClass.ERR_CAST_CANCELLED, "a non-lethal reaction must not report ERR_CAST_CANCELLED")

	var marigold_hp_after_os: int = marigold.hp_current
	assert_lt(marigold_hp_after_os, marigold_hp_before_os, "Marigold (the caster) must show real, positive damage from the Skeleton's resolved Opportunistic Strike")
	assert_gt(marigold_hp_after_os, 0, "fixture assumption: the forced SURVIVABLE_HP must keep Marigold alive through the non-lethal strike")
	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)

	var os_attack_events: Array = _attack_events(instance)
	assert_eq(os_attack_events.size(), 1, "exactly one Strike (the Skeleton's Opportunistic Strike) must have resolved so far")
	var os_attack_event = os_attack_events[0]
	assert_eq(os_attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Marigold (the caster)")
	assert_eq(os_attack_event.target_name, "Marigold", "the resolved Strike's target must be Marigold (the caster)")
	assert_true(os_attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_eq(marigold_hp_before_os - marigold_hp_after_os, os_attack_event.damage_final, "Marigold's hp_current must drop by EXACTLY the resolved Strike's damage_final")

	# ── Criterion 2: cross a TURN boundary -- end Marigold's own turn, cycle
	# the Skeleton's + Titus's turns, and return to Marigold's NEXT turn.
	# casting_state must survive every intervening turn unchanged. ──────────
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	assert_true(marigold.is_casting(), "the in-progress cast must survive every intervening turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1, "remaining_actions must still read 1 -- unchanged by merely crossing the turn boundary")

	var skeleton_hp_before_resolve: int = skeleton.hp_current

	# ── continuing action -> real TargetingPort (player picks Skeleton hex)
	# -> real ResolutionPort roll -> real EffectsApplierPort DAMAGE application
	# -> real CombatLogPort emission -> casting_state cleared. ──
	var _captured_continue := {"done": false, "result": null}
	var _runner_continue := func():
		var r = await instance._verb_bar_cast_spell_execute()
		_captured_continue["done"] = true
		_captured_continue["result"] = r
	_runner_continue.call()
	instance.hex_grid_view.hex_clicked.emit(skeleton.hex_coord)
	await get_tree().process_frame
	var continue_result: Dictionary = _captured_continue["result"]
	assert_true(continue_result.get("success", false), "the continuing CAST_SPELL action must succeed")

	# ── Criterion 2 (continued): remaining_actions correctly reaches 0 and
	# the cast resolves/clears. ──────────────────────────────────────────────
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after resolution")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty")

	# ── Criterion 4: the real ResolutionPort/EffectsApplierPort/CombatLogPort
	# pipeline, read directly off the real, unmodified _verb_deps() dict
	# (never a second/parallel instance this test constructs). ──────────────
	assert_true(continue_result.has("resolve_spell_result"), "ResolveSpellController must have been reached once remaining_actions hit 0")
	var combat_log_panel = instance.spell_combat_log_port
	assert_same(combat_log_panel, instance._verb_deps().get("combat_log_port"), "the combat log read by this test must be the SAME real adapter _verb_deps() itself carries")
	assert_eq(combat_log_panel.get_resolve_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for the Fire Bolt cast")
	var fire_bolt_entry = combat_log_panel.get_resolve_entry(0)
	assert_true(fire_bolt_entry is CombatLogEntryClass)
	assert_eq(fire_bolt_entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(fire_bolt_entry.spell_id, "fire_bolt")
	assert_eq(fire_bolt_entry.actor_id, marigold.display_id())
	assert_eq(fire_bolt_entry.target_ids, [skeleton.display_id()])
	assert_true(fire_bolt_entry.hit, "the guaranteed-hit Reflex defense must actually produce a hit via the real ResolutionPort")
	assert_gt(fire_bolt_entry.damage_amount, 0, "a hit must carry a positive damage_amount applied via the real EffectsApplierPort")
	assert_lt(skeleton.hp_current, skeleton_hp_before_resolve, "a hit must have genuinely reduced the Skeleton's hp through the live EffectsApplier seam")
	assert_eq(skeleton_hp_before_resolve - skeleton.hp_current, fire_bolt_entry.damage_amount, "the hp reduction must equal exactly the logged damage_amount")
	assert_lt(skeleton.hp_current, skeleton_hp_before_fire_bolt, "the Skeleton's final hp must be strictly below its pre-Fire-Bolt hp")

	var rendered_text: String = combat_log_panel.get_resolve_entry_text(0)
	assert_true(rendered_text.contains("fire_bolt"), "the rendered line must name the spell")
	assert_true(rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")
	assert_true(rendered_text.contains(skeleton.display_id()), "the rendered line must name the target")

	# ── Criterion 5: cast Channel through the SAME real composition root
	# (same booted `instance`, same `_controllers["CAST_SPELL"]`, same
	# `_verb_deps()`) -- self-resolution, +1 energy to the caster's own round
	# pool, a corresponding combat-log entry. Channel costs its own action
	# (FR-002's "exactly one action per turn" rule), so this requires
	# crossing one more turn boundary first. ────────────────────────────────
	var post_fire_bolt_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(post_fire_bolt_turn_result.get("ok", false), "EndTurnControl.press() must succeed to end Marigold's Fire-Bolt-resolving turn")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn for the Channel leg")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before the Channel leg begins")

	var pool_before = instance.round_session.get_energy_pool(marigold)
	var energy_before: int = pool_before.current

	var channel_result: Dictionary = instance._verb_bar_cast_spell_execute("channel")
	assert_true(channel_result.get("success", false), "the Channel CAST_SPELL action (select verb + pay energy + resolve, all in ONE action) must succeed")
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after Channel resolves")
	assert_true(marigold.casting_state.is_empty())

	var pool_after = instance.round_session.get_energy_pool(marigold)
	assert_same(pool_after, pool_before, "get_energy_pool() must return the SAME live EnergyPool instance across calls")
	assert_eq(pool_after.current, energy_before + 1, "Channel's resolution must add exactly +1 to the caster's own round energy pool via the real energy_pool_fn")

	assert_eq(combat_log_panel.get_resolve_entry_count(), 2, "exactly one ADDITIONAL CAST_RESOLVE entry must be emitted for the Channel cast")
	var channel_entry = combat_log_panel.get_resolve_entry(1)
	assert_true(channel_entry is CombatLogEntryClass)
	assert_eq(channel_entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(channel_entry.spell_id, "channel")
	assert_eq(channel_entry.actor_id, marigold.display_id())
	assert_eq(channel_entry.target_ids, [], "Channel's ADD_ENERGY effect has no target -- target_ids must be empty")
	assert_null(channel_entry.hit, "Channel is not an attack -- hit must be null")
	assert_null(channel_entry.damage_amount, "Channel deals no damage -- damage_amount must be null")
	assert_eq(channel_entry.energy_delta, 1, "energy_delta must equal the +1 actually applied to the caster's own round energy pool")

	var channel_rendered_text: String = combat_log_panel.get_resolve_entry_text(1)
	assert_true(channel_rendered_text.contains("channel"), "the rendered line must name the spell")
	assert_true(channel_rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 -- running the full scenario above twice, independently, at
# the SAME pinned seed, through TWO independent real, zero-override boots,
# produces byte-identical rolls, damage, and reaction outcomes (NFR-002).
# ══════════════════════════════════════════════════════════════════════════

## _run_full_scenario() -> Dictionary -- boots a FRESH, independent MainScene
## instance pinned to PROLOGUE_SEED and drives the IDENTICAL Fire-Bolt (with
## a non-lethal Opportunistic Strike) + Channel sequence
## test_fire_bolt_and_channel_cast_end_to_end_through_real_composition_root_zero_overrides()
## drives above, through the SAME real, zero-override composition root, and
## records every RNG-derived outcome into a plain-value snapshot Dictionary
## (no Node/Combatant references) so two independent snapshots can be
## directly diffed via assert_eq (mirrors tests/e2e/
## test_determinism_pinned_seed_cast_a_spell.gd's own established
## "_run_full_scenario()" convention, with zero dependency overrides).
func _run_full_scenario() -> Dictionary:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]

	skeleton.hp_current = _ENEMY_HP_HANDICAP
	skeleton.hp_max = _ENEMY_HP_HANDICAP
	skeleton.reflex = AC_GUARANTEED_HIT

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first Fire Bolt CAST_SPELL action must succeed")
	var reaction_result: Dictionary = begin_result.get("reaction_result", {})
	var reactions: Array = reaction_result.get("reactions", [])
	var reaction_choice: String = reactions[0].get("choice", "") if reactions.size() > 0 else ""

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")

	var _captured_c := {"done": false, "result": null}
	var _runner_c := func():
		var r = await instance._verb_bar_cast_spell_execute()
		_captured_c["done"] = true
		_captured_c["result"] = r
	_runner_c.call()
	instance.hex_grid_view.hex_clicked.emit(skeleton.hex_coord)
	await get_tree().process_frame
	var continue_result: Dictionary = _captured_c["result"]
	assert_true(continue_result.get("success", false), "the continuing Fire Bolt CAST_SPELL action must succeed")
	assert_false(marigold.is_casting(), "Fire Bolt must have resolved and cleared casting_state")

	var post_fire_bolt_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(post_fire_bolt_turn_result.get("ok", false), "EndTurnControl.press() must succeed to end Marigold's Fire-Bolt-resolving turn")
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn for the Channel leg")

	var channel_result: Dictionary = instance._verb_bar_cast_spell_execute("channel")
	assert_true(channel_result.get("success", false), "the Channel CAST_SPELL action must succeed")
	assert_false(marigold.is_casting(), "Channel must have resolved and cleared casting_state")

	var combat_log_panel = instance.spell_combat_log_port
	var log_entries: Array = []
	for i in range(combat_log_panel.get_resolve_entry_count()):
		log_entries.append(combat_log_panel.get_resolve_entry(i).to_dict())

	var attack_event_dicts: Array = []
	for attack_event in _attack_events(instance):
		attack_event_dicts.append(attack_event.to_dict())

	return {
		"resolved_seed": instance.resolved_seed,
		"log_entries": log_entries,
		"attack_events": attack_event_dicts,
		"skeleton_hp_final": skeleton.hp_current,
		"marigold_hp_final": marigold.hp_current,
		"marigold_energy_pool_final": instance.round_session.get_energy_pool(marigold).current,
		"reaction_choice": reaction_choice,
	}


func test_running_full_scenario_twice_at_pinned_seed_produces_identical_outcomes() -> void:
	var run_1: Dictionary = await _run_full_scenario()
	var run_2: Dictionary = await _run_full_scenario()

	assert_eq(run_1.get("resolved_seed"), PROLOGUE_SEED, "run 1 must have honored seed_override=PROLOGUE_SEED")
	assert_eq(run_2.get("resolved_seed"), PROLOGUE_SEED, "run 2 must have honored seed_override=PROLOGUE_SEED")

	# Non-vacuous sanity: real work actually happened in both runs (a bug
	# that silently no-ops the whole scenario would otherwise make this
	# suite trivially/vacuously pass).
	assert_eq(run_1.get("log_entries").size(), 2, "fixture assumption: exactly the Fire Bolt + Channel CAST_RESOLVE entries must have been recorded")
	# Fire Bolt (2 actions: begin + continue) AND Channel all author
	# traits=["Concentrate"] (data/spells/fire_bolt.tres,
	# data/spells/channel.tres) -- the adjacent Skeleton is offered (and, at
	# AC_GUARANTEED_HIT, always takes) an Opportunistic Strike window on
	# EVERY one of the three CAST_SPELL actions this scenario drives, so
	# three AttackBroadcasts (never a fabricated single one) are the real,
	# deterministic outcome.
	assert_eq(run_1.get("attack_events").size(), 3, "fixture assumption: the Opportunistic Strike's AttackBroadcast must have been recorded for all three Concentrate-trait CAST_SPELL actions (2 Fire Bolt + 1 Channel)")
	assert_eq(run_1.get("reaction_choice"), "opportunistic_strike", "fixture assumption: the reaction window must have genuinely resolved to opportunistic_strike")

	# ── rolls, damage, and reaction outcomes -- byte-identical across the two
	# independent, zero-override boots. ──────────────────────────────────────
	assert_eq(run_2.get("log_entries"), run_1.get("log_entries"), "the recorded CAST_RESOLVE combat-log entries (spell/target/hit/damage/energy) must be identical across two independent boots of the same pinned seed")
	assert_eq(run_2.get("attack_events"), run_1.get("attack_events"), "the recorded AttackBroadcast (Opportunistic Strike roll/damage) must be identical across two independent boots of the same pinned seed")
	assert_eq(run_2.get("skeleton_hp_final"), run_1.get("skeleton_hp_final"), "the Skeleton's final hp (Fire Bolt's applied damage) must be identical")
	assert_eq(run_2.get("marigold_hp_final"), run_1.get("marigold_hp_final"), "Marigold's final hp (the Opportunistic Strike's applied damage) must be identical")
	assert_eq(run_2.get("marigold_energy_pool_final"), run_1.get("marigold_energy_pool_final"), "Marigold's final round energy pool balance (Channel's +1) must be identical")
	assert_eq(run_2.get("reaction_choice"), run_1.get("reaction_choice"), "the reactor's chosen reaction must be identical")

	# Whole-snapshot deep-equality sanity check (belt-and-suspenders): the
	# ENTIRE recorded snapshot of two independent boots at the same pinned
	# seed must be byte-identical.
	assert_eq(run_2, run_1, "the entire recorded snapshot of two independent boots at the same pinned seed must be byte-identical")
