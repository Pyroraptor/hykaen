extends GutTest
## tests/e2e/test_steel_thread_cast_a_spell.gd — FEAT-282 (US-018; NFR-002,
## NFR-003)
##
## Boots the REAL, shipped res://MainScene.tscn composition root (never a
## hand-wired double) and the real prologue encounter
## (data/encounters/prologue_encounter.tres), and drives the full "Cast a
## Spell" steel thread end-to-end, entry point to exit point:
##
##   entry point — the player selects the Cast-a-Spell verb on the caster's
##   (Marigold's) own turn, through the SAME production
##   `_verb_bar_cast_spell_execute()` shim a live player click resolves
##   through (presentation/verbs/spell_action_controller.gd's
##   SpellActionController).
##
##   through Fire Bolt (2 actions, spans a TURN boundary) and Channel
##   (1 action, cast after crossing a ROUND boundary) —
##
##   to exit point — the combat log (presentation/ui/
##   combat_log_panel_adapter.gd's CombatLogPanelAdapter, subscribed to
##   core/application/ports/combat_log_port.gd's CombatLogPort) shows the
##   resolved outcome, casting_state is cleared, and the target's hp/the
##   caster's energy pool reflect the applied effect — PLUS an
##   Opportunistic Strike exposure window (US-014/US-015) that, when
##   lethal, cancels an in-progress cast with no resolution/log-of-outcome
##   and no energy refund (ADR-003).
##
## This file recombines, in one continuous suite driven through the ONE
## real composition root, the individually-shipped Cast-a-Spell features'
## own established boot-real conventions (never a bespoke path this suite
## invents on its own):
##   tests/boot/test_main_scene_cast_spell_verb_registered.gd (FEAT-004),
##   tests/boot/test_fire_bolt_full_cast_e2e_log.gd (FEAT-276),
##   tests/boot/test_channel_cast_e2e.gd (FEAT-277),
##   tests/boot/test_cast_provokes_opportunistic_strike.gd (FEAT-279),
##   tests/boot/test_lethal_os_cancels_cast.gd (FEAT-280).
## No production code is modified by this feature (files_to_modify is
## empty) — every collaborator driven below is the exact, unmodified,
## REUSED production class already covered by its own suite; this file's
## job is proving they ALL still compose correctly, together, end-to-end.
##
## test_criteria satisfied:
##   "E2E test drives entry point -> Fire Bolt cast across 2 actions/turn
##   boundary -> targeting -> resolution -> combat log entry ->
##   casting_state cleared -> target hp reduced on hit"
##   "E2E test drives Channel cast -> resolution -> combat log entry ->
##   caster energy pool +1"
##   "E2E test confirms an in-range enemy's Opportunistic Strike fires
##   during the cast window and, when lethal, cancels the cast with no
##   resolution/log-of-outcome and no energy refund"
##   "Headless boot confirms MainScene + prologue encounter load cleanly
##   with the caster and CAST_SPELL verb registered"

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")

const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const RoundEnergyPoolPortClass    = preload("res://core/application/ports/round_energy_pool_port.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")
const RoundEventsClass            = preload("res://core/rules/round_events.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors every prior Cast-a-Spell boot-real suite's identically-named/
## valued constant), also used to seed this suite's own injected
## ResolutionPort so every attack roll is deterministic/replayable
## (NFR-002).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT -- an absurdly low defense value; assigning it to
## whichever combatant must be guaranteed HIT (either the Skeleton's
## reflex, for Marigold's own Fire Bolt, or Marigold's ac, for the
## Skeleton's Opportunistic Strike) removes all hit/miss branching from
## this suite's assertions with no RNG/seed edits (established convention,
## e.g. tests/boot/test_cast_provokes_opportunistic_strike.gd).
const AC_GUARANTEED_HIT: int = -1000

## LETHAL_HP -- mirrors tests/boot/test_lethal_os_cancels_cast.gd's own
## identically-named/valued constant, pinned BELOW the Skeleton's real
## Arming Sword's lowest possible damage roll, so a real, seeded
## hit-and-damage roll against a combatant pinned to LETHAL_HP is
## genuinely lethal, never a fabricated target_defeated flag.
const LETHAL_HP: int = 1


## ScriptedTargetingPort -- always returns the same pre-picked target,
## mirroring every prior boot-real Cast-a-Spell suite's identically-shaped
## test double.
class ScriptedTargetingPort:
	extends TargetingPortClass
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives Cast-a-Spell verbs
## directly against `round_session`, so `_boot_main_scene()` now also drives
## the SAME real handoff, landing the instance in GameMode.COMBAT with a live
## round_session before returning.
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
## Marigold's live turn (mirrors every prior Cast-a-Spell boot-real
## suite's identically-named helper).
## At seed=42 the initiative order is Titus → Skeleton → Marigold →
## Gram Marx. After Titus's END_TURN the Skeleton auto-drives and opens
## reaction prompt windows (PreHitAvoidance and OnHitMitigation) -- these
## must be drained after each press so the turn-controller's coroutine can
## fully settle before the while-condition is re-evaluated.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")
		# Drain any reaction pop-ups opened by the Skeleton's AI turn so the
		# coroutine fully settles before the loop re-evaluates the condition.
		var guard: int = 0
		while instance.reaction_prompt_ui.is_open() and guard < 10:
			var options: Array = instance.reaction_prompt_ui.get_displayed_options()
			if "none" in options:
				instance.reaction_prompt_ui.press_option("none")
			elif options.size() > 0:
				instance.reaction_prompt_ui.press_option(options[0])
			guard += 1


## _force_all_spent(instance) -- drives every combatant's ActionEconomy to
## Spent via spend_reaction() (mirrors tests/boot/
## test_cast_persists_across_round_boundary.gd's identically-named,
## established helper exactly), so this suite can deterministically drive
## a ROUND boundary crossing without waiting on the full turn-order cycle.
## Deliberately does NOT touch casting_state.
func _force_all_spent(instance) -> void:
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		var action_economy = instance.encounter.get_action_economy(i)
		while not action_economy.is_spent():
			action_economy.spend_reaction()


## _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void --
## mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named helper exactly.
func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


## _wire_real_cast_spell_controller(instance, skeleton) -> CombatLogPanelAdapter
## -- mirrors every prior Cast-a-Spell boot-real suite's identically-named
## helper exactly: swaps a REAL SpellActionController (built from the
## booted composition root's OWN `_verb_deps()` dict, byte-for-byte
## unchanged) carrying a REAL ResolveSpellController wired with a scripted
## TargetingPort (targeting `skeleton`), a REAL, seeded ResolutionPort, a
## REAL CombatLogPanelAdapter, and a REAL `energy_pool_fn` reading the
## booted RoundSession's own energy pool, into
## `instance._controllers["CAST_SPELL"]`, the SAME memoized slot
## MainScene.gd's own `_controller("CAST_SPELL")` reads -- so the
## production `_verb_bar_cast_spell_execute()` shim itself drives the full
## flow end-to-end for BOTH Fire Bolt (attack) and Channel (self/
## ADD_ENERGY), never a bespoke path this suite invents on its own.
func _wire_real_cast_spell_controller(instance, skeleton):
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = skeleton

	var combat_log_panel := CombatLogPanelAdapterClass.new()
	var resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))

	var deps: Dictionary = instance._verb_deps().duplicate()
	deps["resolve_spell_controller"] = ResolveSpellControllerClass.new({
		"targeting_port": targeting,
		"candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": combat_log_panel,
		"energy_pool_fn": func(caster): return instance.round_session.get_energy_pool(caster),
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- headless boot confirms MainScene + prologue encounter load
# cleanly with the caster and CAST_SPELL verb registered (NFR-003).
# ══════════════════════════════════════════════════════════════════════════

func test_headless_boot_loads_cleanly_with_caster_and_cast_spell_verb_registered() -> void:
	assert_true(MainSceneClass.VERB_TABLE.has("CAST_SPELL"), "MainScene.VERB_TABLE must register a CAST_SPELL entry")
	assert_eq(
		MainSceneClass.VERB_TABLE.get("CAST_SPELL"), SpellActionControllerClass,
		"VERB_TABLE['CAST_SPELL'] must point at presentation/verbs/spell_action_controller.gd's SpellActionController"
	)

	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance, "MainScene.tscn must instantiate")
	assert_not_null(instance.round_session, "a real RoundSession must be live after first frame -- the prologue encounter loaded cleanly")

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "the caster (Marigold) must be present in the live party")
	assert_true(marigold.known_spell_ids.has("fire_bolt"), "the caster must know Fire Bolt")
	assert_true(marigold.known_spell_ids.has("channel"), "the caster must know Channel")

	assert_not_null(instance._verb_registry, "MainScene must wire a real VerbBarRegistry after first frame")
	var registered_verb_ids: Array = []
	for descriptor in instance._verb_registry.list_verbs():
		registered_verb_ids.append(descriptor.get("verb_id"))
	assert_true(registered_verb_ids.has("CAST_SPELL"), "the real, booted VerbBarRegistry must have CAST_SPELL registered")

	var available: bool = instance._verb_registry.is_available("CAST_SPELL")
	assert_typeof(available, TYPE_BOOL, "CAST_SPELL availability must resolve to a real bool through the live VerbBarRegistry, without crashing")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- Fire Bolt cast across a 2-action/turn boundary -> targeting
# -> resolution -> combat log entry -> casting_state cleared -> target hp
# reduced on hit.
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_cast_spans_turn_boundary_resolves_hit_logs_and_clears_casting_state() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]
	var skeleton_hp_before: int = skeleton.hp_current

	# Guarantee a hit against the Skeleton's Reflex (fire_bolt.tres'
	# defense=REFLEX) so "target hp reduced on hit" is a deterministic
	# assertion, not a conditional branch.
	skeleton.reflex = AC_GUARANTEED_HIT

	var combat_log_panel = _wire_real_cast_spell_controller(instance, skeleton)

	# ── entry point: the player selects the Cast-a-Spell verb on the
	# caster's own turn -- the first action pays energy (0 for Fire Bolt)
	# and leaves remaining_actions == 1 (2-action cost). ────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	var begin_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first CAST_SPELL action (select verb + pay energy) must succeed")
	assert_true(marigold.is_casting())
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)
	assert_eq(combat_log_panel.get_entry_count(), 0, "no CAST_RESOLVE entry yet -- the cast has not reached resolution")

	# ── cross a TURN boundary: end Marigold's own turn, cycle the
	# Skeleton's + Titus's turns, and return to Marigold's NEXT turn. ──────
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	assert_true(marigold.is_casting(), "the in-progress cast must survive every intervening turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)

	# ── continuing action -> targeting -> resolution (no re-selection). ────
	var continue_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "the continuing CAST_SPELL action must succeed")

	# ── exit point: casting_state cleared, combat log shows the resolved
	# outcome, target hp reduced on hit. ────────────────────────────────────
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after resolution")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty")

	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.target_ids, [skeleton.display_id()])
	assert_true(entry.hit, "the guaranteed-hit Reflex defense must actually produce a hit")
	assert_gt(entry.damage_amount, 0, "a hit must carry a positive damage_amount")
	assert_lt(skeleton.hp_current, skeleton_hp_before, "a hit must have genuinely reduced the Skeleton's hp through the live EffectsApplier seam")
	assert_eq(skeleton_hp_before - skeleton.hp_current, entry.damage_amount, "the hp reduction must equal exactly the logged damage_amount")

	var rendered_text: String = combat_log_panel.get_entry_text(0)
	assert_true(rendered_text.contains("fire_bolt"), "the rendered line must name the spell")
	assert_true(rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")
	assert_true(rendered_text.contains(skeleton.display_id()), "the rendered line must name the target")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- Channel cast, driven after crossing a ROUND boundary ->
# resolution -> combat log entry -> caster energy pool +1.
# ══════════════════════════════════════════════════════════════════════════

func test_channel_cast_after_round_boundary_resolves_and_adds_energy_to_caster_pool() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("channel"), "fixture assumption: Marigold must know Channel")
	assert_eq(instance.ROUND_NUMBER, 1, "fixture assumption: the encounter opens in round 1")

	var combat_log_panel = _wire_real_cast_spell_controller(instance, instance._enemies[0])

	# ── cross a ROUND boundary (mirrors tests/boot/
	# test_cast_persists_across_round_boundary.gd's established
	# "_force_all_spent() -> End Turn -> round rolls over" pattern) BEFORE
	# Marigold ever casts anything this round. ──────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn in round 1")

	_force_all_spent(instance)
	assert_false(instance.round_session.is_round_over(), "the round is not over until the cursor is actually advanced off the last actor")
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed to end Marigold's turn and drive the round over")
	await get_tree().process_frame
	assert_eq(instance.ROUND_NUMBER, 2, "forcing every actor Spent and ending the turn must roll the encounter into round 2")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn in round 2")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	var pool_before = instance.round_session.get_energy_pool(marigold)
	var energy_before: int = pool_before.current
	assert_eq(energy_before, 0, "fixture assumption: round 2's freshly-created energy pool must start empty")

	# ── entry point -> resolution, all in ONE action (Channel's 1-action
	# cost drives remaining_actions to 0 on the FIRST cast). ────────────────
	var cast_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("channel")
	assert_true(cast_result.get("success", false), "the single Channel CAST_SPELL action (select verb + pay energy + resolve) must succeed")

	# ── exit point: casting_state cleared, caster energy pool +1, combat
	# log shows the resolved outcome. ───────────────────────────────────────
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after Channel resolves")
	assert_true(marigold.casting_state.is_empty())

	var pool_after = instance.round_session.get_energy_pool(marigold)
	assert_same(pool_after, pool_before, "get_energy_pool() must return the SAME live EnergyPool instance across calls")
	assert_eq(pool_after.current, energy_before + 1, "Channel's resolution must add exactly +1 to the caster's own round energy pool")

	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "channel")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.target_ids, [], "Channel's ADD_ENERGY effect has no target -- target_ids must be empty")
	assert_null(entry.hit, "Channel is not an attack -- hit must be null")
	assert_null(entry.damage_amount, "Channel deals no damage -- damage_amount must be null")
	assert_eq(entry.energy_delta, 1, "energy_delta must equal the +1 actually applied to the caster's own round energy pool")

	var rendered_text: String = combat_log_panel.get_entry_text(0)
	assert_true(rendered_text.contains("channel"), "the rendered line must name the spell")
	assert_true(rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- an in-range enemy's Opportunistic Strike fires during the
# cast window and, when lethal, cancels the cast with no resolution/
# log-of-outcome and no energy refund (US-014/US-015, ADR-003).
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_opportunistic_strike_fires_during_cast_window_and_cancels_with_no_resolution_log_or_energy_refund() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]
	assert_true(
		not skeleton.weapon.has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach (no 'range_hexes' key)"
	)
	var skeleton_hp_before: int = skeleton.hp_current

	var combat_log_panel = _wire_real_cast_spell_controller(instance, skeleton)

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	# ── Bank + reserve a MEANINGFUL nonzero committed_energy up front (Fire
	# Bolt/Channel both cost 0 energy this iteration, so a genuine cast
	# alone could never exercise ADR-003's "no refund" contract -- mirrors
	# tests/boot/test_lethal_os_cancels_cast.gd's own established
	# reservation technique, via the SAME RoundEnergyPoolPort adapter
	# BeginCastUseCase uses in real play). ──────────────────────────────────
	var pool = instance.round_session.get_energy_pool(marigold)
	assert_gt(pool.capacity, 0, "fixture assumption: Marigold's resolved spellcasting_attribute_score must be positive so a reservation is meaningful")
	pool.add(pool.capacity)
	var energy_port = RoundEnergyPoolPortClass.SessionEnergyPoolAdapter.new(instance.round_session, marigold)
	var committed_energy: int = pool.capacity
	assert_true(energy_port.reserve(marigold.display_id(), committed_energy), "fixture assumption: reserving the full banked balance must succeed")
	var balance_after_reserve: int = pool.current
	assert_eq(balance_after_reserve, 0, "reserve() must have decremented the pool by the full committed amount, leaving it drained")

	# Force Marigold into an in-progress cast carrying that committed_energy
	# (mirrors the established "force casting_state directly, a plain
	# public Dictionary field" convention) with ONE action remaining, so
	# the NEXT CAST_SPELL action is a CONTINUING-cast action -- proving the
	# reaction window also fires on that branch, not only on a first cast.
	marigold.casting_state = {
		"spell_id": "fire_bolt",
		"remaining_actions": 1,
		"committed_energy": committed_energy,
		"caster_id": marigold.display_id(),
	}
	assert_true(marigold.is_casting(), "fixture assumption: Marigold must now be mid-cast, carrying the reserved committed_energy")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)

	# Force a GENUINELY lethal Opportunistic Strike against Marigold (the
	# caster) -- guaranteed hit, hp pinned strictly below the Skeleton's
	# real minimum-possible damage roll -- never a fabricated
	# target_defeated flag.
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = LETHAL_HP
	marigold.hp_max = LETHAL_HP

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	# ── Drive the SAME real, composition-root-bound CAST_SPELL entry point
	# a live player click resolves through -- the continuing-cast action
	# (no selection argument at all, US-006). ───────────────────────────────
	# Snapshot the attack event count before this cast executes: the Skeleton
	# auto-drove and struck Titus in _advance_to_marigolds_turn() above,
	# so there may already be 1 attack event in the log (the Skeleton→Titus
	# strike from its AI turn). We must slice from here so the assertions
	# below only see the Opportunistic Strike that fires DURING this cast.
	var attack_events_before_cast: int = _attack_events(instance).size()
	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no pop-up is open before this cast is driven")
	var continue_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute()

	# The enemy reactor's own OpportunisticStrike decision routes
	# synchronously through the REAL AIReactionPolicy -- never a pop-up.
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	# ── Criterion: the Opportunistic Strike genuinely FIRES during the cast
	# window. ────────────────────────────────────────────────────────────────
	var reaction_result: Dictionary = continue_result.get("reaction_result", {})
	var reactions: Array = reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "exactly one reactor (the adjacent Skeleton) must have been offered a window")
	assert_eq(reactions[0].get("choice", ""), "opportunistic_strike", "the REAL AIReactionPolicy must genuinely choose opportunistic_strike when melee-legal and the RESERVE gate is open")
	var strike_result: Dictionary = reactions[0].get("strike_result", {})
	assert_true(strike_result.get("resolved", false), "the reactor's opportunistic_strike choice must FULLY resolve a real Strike")
	assert_true(strike_result.get("ok", false), "the resolved Strike must succeed")
	assert_true(strike_result.get("target_defeated", false), "Marigold's forced LETHAL_HP floor must be genuinely defeated by the Skeleton's real, minimum-possible damage roll")
	assert_true(reaction_result.get("mover_downed", false), "a lethal Opportunistic Strike must set mover_downed true")
	assert_false(reaction_result.get("stride_should_commit", true), "a lethal Opportunistic Strike must set stride_should_commit false")
	assert_true(marigold.hp_current <= 0, "Marigold's hp_current must reflect the Skeleton's real, lethal Opportunistic Strike damage")

	# ── Criterion: LETHAL cancels the cast end-to-end. ──────────────────────
	assert_false(marigold.is_casting(), "a lethal Opportunistic Strike must cancel the in-progress cast -- casting_state must be cleared")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty")
	assert_null(continue_result.get("casting_state"), "the ExecuteResult's own casting_state must be null once the cast is cancelled")
	assert_eq(continue_result.get("error"), ErrorCodeClass.ERR_CAST_CANCELLED, "the ExecuteResult must report ERR_CAST_CANCELLED")

	# ── Criterion: NO resolution / no log-of-outcome. ───────────────────────
	assert_false(continue_result.has("resolve_spell_result"), "ResolveSpellController must NEVER be reached once the cast is cancelled")
	assert_eq(combat_log_panel.get_entry_count(), 0, "no CAST_RESOLVE combat-log entry must ever be emitted for the cancelled cast -- Fire Bolt's own resolution must never have run")
	assert_eq(skeleton.hp_current, skeleton_hp_before, "the Skeleton must take NO damage -- Fire Bolt's own attack roll must never have been attempted")

	# ── Criterion: NO energy refund (ADR-003). ──────────────────────────────
	assert_eq(pool.current, balance_after_reserve, "committed_energy must NOT be refunded to the round energy pool on cancellation")
	assert_eq(pool.current, 0, "the pool must remain fully drained after cancellation -- no refund path exists (ADR-003)")

	# Slice to only the attack events that fired DURING this cast execution
	# (the Skeleton may have already attacked Titus during _advance_to_marigolds_turn).
	var all_attack_events: Array = _attack_events(instance)
	var attack_events: Array = all_attack_events.slice(attack_events_before_cast)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's lethal Opportunistic Strike) must have resolved during this cast -- Fire Bolt's own attack roll must never occur")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton", "the resolved Strike must be attributed to the Skeleton (the reactor), not Marigold (the caster)")
	assert_eq(attack_event.target_name, "Marigold", "the resolved Strike's target must be Marigold (the caster)")
	assert_true(attack_event.hit, "the guaranteed-hit AC must actually produce a hit")
	assert_true(attack_event.damage_final > 0, "the resolved, lethal Opportunistic Strike must apply real, positive damage")

	# The reactor paid via spend_reaction(), never a second spend_action().
	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Skeleton's own live ActionEconomy budget must drop by EXACTLY 1 -- paid via spend_reaction(), never spend_action()"
	)
