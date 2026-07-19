extends GutTest
## tests/boot/test_lethal_os_cancels_cast.gd — FEAT-280 (US-015; FR-017)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely CANCELS Marigold's
## in-progress Cast-a-Spell action when a GENUINELY lethal Opportunistic
## Strike is provoked mid-cast — closing the gap tests/boot/
## test_cast_provokes_opportunistic_strike.gd (FEAT-279) deliberately left
## open (that suite pins the caster's hp to a SURVIVABLE value specifically
## so the reaction never downs her; this suite pins it BELOW the reactor's
## own minimum possible damage roll instead, mirroring tests/integration/
## test_opportunistic_strike_lethal_cancels_stride_boot_real.gd's (FEAT-238)
## own established LETHAL_HP technique for Stride).
##
## Drives the SAME real, composition-root-bound CAST_SPELL entry point a
## live player click resolves through (`_verb_bar_cast_spell_execute()`),
## routed through presentation/verbs/spell_action_controller.gd's
## `_maybe_cancel_cast()` (this feature's new helper) ->
## core/application/use_cases/cancel_cast_use_case.gd's CancelCastUseCase —
## never a hand-rolled fake of either collaborator.
##
## A second, narrower suite drives CancelCastUseCase directly against a
## live, composition-root-booted Combatant + RoundSession energy pool to
## prove the ADR-003 "no refund" contract precisely (a Fire Bolt/Channel
## cast alone can never exercise a nonzero committed_energy this iteration,
## since both cost 0 energy — see that test's own doc for how it
## constructs a meaningful nonzero reservation).
##
## Verifies (test_criteria):
##   1. "Boot-real test confirms a mid-cast lethal Opportunistic Strike
##      cancels the cast end-to-end: casting_state cleared, no spell
##      resolves, no effects applied."
##   2. "Unit test confirms committed_energy is not refunded to the round
##      pool on cancellation."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass            = preload("res://core/rules/round_events.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")
const CancelCastUseCaseClass      = preload("res://core/application/use_cases/cancel_cast_use_case.gd")
const RoundEnergyPoolPortClass    = preload("res://core/application/ports/round_energy_pool_port.gd")
const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT — mirrors this project's established
## AC_GUARANTEED_HIT convention: an absurdly low AC guarantees a hit with
## no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## LETHAL_HP — mirrors tests/integration/
## test_opportunistic_strike_lethal_cancels_stride_boot_real.gd's own
## identically-named/valued constant, pinned BELOW the lowest possible real
## damage roll the Skeleton's real Arming Sword can ever produce
## (damage_die=6, min roll 1, + strength(2) = 3) — so ANY real, seeded
## hit-and-damage roll against a combatant pinned to LETHAL_HP is genuinely
## lethal, never a fabricated/forced target_defeated flag.
const LETHAL_HP: int = 1


## ScriptedTargetingPort — always returns the same pre-picked target,
## mirroring tests/boot/test_fire_bolt_full_cast_e2e_log.gd's identically-
## shaped test double. Wired into this suite's own resolve_spell_controller
## solely so a REAL CombatLogPanelAdapter can be consulted to prove NO
## CAST_RESOLVE entry is ever emitted for the cancelled cast (see
## `_wire_real_cast_spell_controller()` below) — this double's own
## request_single_target() is never actually CALLED anywhere in this
## suite's own test bodies, since the cast is cancelled before resolution
## is ever reached.
class ScriptedTargetingPort:
	extends TargetingPortClass
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


## _advance_to_marigolds_turn(instance) -> void -- Titus acts first in the
## prologue's turn order (seed=42); pass turns (EndTurnControl is ALWAYS
## available, regardless of whether an action was spent) until it is
## Marigold's live turn (mirrors every other Cast-a-Spell boot-real suite's
## identically-named helper).
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void --
## mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
## identically-named helper exactly: forces Marigold's OWN live hex_coord
## adjacent to the Skeleton's, since the prologue fixture's own boot
## positions leave her two hexes away.
func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


## _wire_real_cast_spell_controller(instance, skeleton) -> CombatLogPanelAdapter
## -- mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's identically-
## named helper: swaps a REAL SpellActionController (built from the booted
## composition root's OWN `_verb_deps()` dict, byte-for-byte unchanged)
## carrying a resolve_spell_controller wired with a REAL CombatLogPanelAdapter
## into `instance._controllers["CAST_SPELL"]`, the SAME memoized slot
## MainScene.gd's own `_controller("CAST_SPELL")` reads -- so this suite can
## assert the combat log NEVER receives a CAST_RESOLVE entry for the
## cancelled cast (proof "no spell resolves"), through the SAME production
## `_verb_bar_cast_spell_execute()` shim every other boot-real Cast-a-Spell
## suite drives, never a bespoke path this test invents on its own.
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
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a mid-cast lethal Opportunistic Strike cancels the cast
# end-to-end, through the REAL, composition-root-wired CAST_SPELL verb.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_opportunistic_strike_cancels_mid_cast_end_to_end() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("fire_bolt"), "fixture assumption: Marigold must know Fire Bolt")

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
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast before this test's own cast begins")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)

	# Force a GENUINELY lethal Opportunistic Strike against Marigold (the
	# caster) — guaranteed hit, hp pinned strictly below the Skeleton's real
	# minimum-possible damage roll — never a fabricated target_defeated flag.
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = LETHAL_HP
	marigold.hp_max = LETHAL_HP

	var skeleton_ae = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_ae, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	# ── Drive the SAME real, composition-root-bound CAST_SPELL entry point a
	# live player click resolves through -- a FIRST-cast action, so this
	# exercises BeginCastUseCase's own success branch immediately followed
	# by the lethal reaction/cancellation (Fire Bolt's 2-action cost leaves
	# the cast genuinely "in progress" -- remaining_actions == 1 -- the
	# instant BEFORE the lethal Opportunistic Strike cancels it). ──────────
	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no pop-up is open before this cast is driven")
	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")

	# The enemy reactor's own OpportunisticStrike decision routes
	# synchronously through the REAL AIReactionPolicy -- never a pop-up.
	assert_false(instance.reaction_prompt_ui.is_open(), "the enemy reactor's own OpportunisticStrike decision is resolved synchronously via AIReactionPolicy -- no pop-up may ever open for it")

	# ── Criterion: the reaction itself genuinely, lethally resolved. ──────
	var reaction_result: Dictionary = begin_result.get("reaction_result", {})
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

	# ── Criterion: casting_state is cleared end-to-end. ────────────────────
	assert_false(marigold.is_casting(), "a lethal Opportunistic Strike must cancel the in-progress cast -- casting_state must be cleared")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty")
	assert_null(begin_result.get("casting_state"), "the ExecuteResult's own casting_state must be null once the cast is cancelled")
	assert_eq(begin_result.get("error"), ErrorCodeClass.ERR_CAST_CANCELLED, "the ExecuteResult must report ERR_CAST_CANCELLED")

	# ── Criterion: no spell resolves. ──────────────────────────────────────
	assert_false(begin_result.has("resolve_spell_result"), "ResolveSpellController must NEVER be reached once the cast is cancelled -- _maybe_resolve_cast()'s own is_casting() gate must fail")
	assert_eq(combat_log_panel.get_entry_count(), 0, "no CAST_RESOLVE combat-log entry must ever be emitted -- Fire Bolt's own resolution must never have run")

	# ── Criterion: no effects applied. ─────────────────────────────────────
	assert_eq(skeleton.hp_current, skeleton_hp_before, "the Skeleton must take NO damage -- Fire Bolt's own attack roll must never have been attempted")

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's lethal Opportunistic Strike) must have resolved -- Fire Bolt's own attack roll must never occur")
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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — committed_energy is NOT refunded to the round pool on
# cancellation (ADR-003).
# ══════════════════════════════════════════════════════════════════════════

## Fire Bolt/Channel both cost 0 energy this iteration (design notes'
## data_model: "0 for Fire Bolt/Channel"), so an actual lethal-OS-during-a-
## real-cast scenario (Criterion 1 above) can never exercise a nonzero
## committed_energy. This suite instead constructs the scenario directly
## against the live, composition-root-booted RoundSession's own energy pool
## (core/application/ports/round_energy_pool_port.gd's
## SessionEnergyPoolAdapter, the SAME adapter presentation/verbs/
## spell_action_controller.gd's `_round_energy_pool_port()` builds in real
## play) + core/domain/combatant.gd's Combatant (forcing casting_state the
## SAME direct-assignment way tests/boot/
## test_cast_provokes_opportunistic_strike.gd's own continuing-cast
## criterion already does) — then drives CancelCastUseCase directly (the
## SOLE collaborator presentation/verbs/spell_action_controller.gd's
## `_maybe_cancel_cast()` calls once a lethal outcome is detected — see
## that method's own doc), and asserts the pool's balance is unchanged by
## the cancellation.
func test_cancel_cast_does_not_refund_committed_energy_to_round_pool() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")

	# Bank Marigold's round energy pool to its full resolved capacity
	# (spellcasting_attribute_score = her willpower, 4 -- data/characters/
	# marigold.tres + data/classes/divine_warrior.tres) so a nonzero
	# reservation is meaningful. EnergyPool.add()/RoundSession.get_energy_pool()
	# are the SAME live domain collaborators production code uses -- no
	# double stands in for either.
	var pool = instance.round_session.get_energy_pool(marigold)
	assert_gt(pool.capacity, 0, "fixture assumption: Marigold's resolved spellcasting_attribute_score must be positive so a reservation is meaningful")
	pool.add(pool.capacity)
	assert_eq(pool.current, pool.capacity, "fixture assumption: the pool must now be banked to its full capacity")

	# Reserve committed_energy via the SAME RoundEnergyPoolPort adapter
	# BeginCastUseCase uses in real play (core/application/ports/
	# round_energy_pool_port.gd's SessionEnergyPoolAdapter) -- the atomic
	# check-then-decrement this feature's ADR-003 "no refund" contract is
	# scoped against.
	var energy_port = RoundEnergyPoolPortClass.SessionEnergyPoolAdapter.new(instance.round_session, marigold)
	var committed_energy: int = pool.capacity
	assert_true(energy_port.reserve(marigold.display_id(), committed_energy), "fixture assumption: reserving the full banked balance must succeed")

	var balance_after_reserve: int = pool.current
	assert_eq(balance_after_reserve, 0, "reserve() must have decremented the pool by the full committed amount, leaving it drained")

	# Force Marigold into a mid-cast state carrying that committed_energy --
	# mirrors tests/boot/test_cast_provokes_opportunistic_strike.gd's own
	# established "force casting_state directly, a plain public Dictionary
	# field" convention.
	marigold.casting_state = {
		"spell_id": "fire_bolt",
		"remaining_actions": 1,
		"committed_energy": committed_energy,
		"caster_id": marigold.display_id(),
	}
	assert_true(marigold.is_casting(), "fixture assumption: Marigold must now be mid-cast, carrying the reserved committed_energy")

	var cancel_result: Dictionary = CancelCastUseCaseClass.new().execute(marigold)

	assert_true(cancel_result.get("success", false), "CancelCastUseCase.execute() must succeed for a genuinely mid-cast actor")
	assert_eq(cancel_result.get("error"), ErrorCodeClass.ERR_CAST_CANCELLED, "a successful cancellation must report ERR_CAST_CANCELLED")
	assert_false(marigold.is_casting(), "cancellation must clear casting_state")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty after cancellation")

	# ── The criterion itself: the round energy pool balance is UNCHANGED by
	# the cancellation -- committed_energy is never refunded. ─────────────
	assert_eq(pool.current, balance_after_reserve, "committed_energy must NOT be refunded to the round energy pool on cancellation -- the pool balance must remain exactly as it was after the up-front reservation")
	assert_eq(pool.current, 0, "the pool must remain fully drained after cancellation -- no refund path exists (ADR-003, RoundEnergyPoolPort exposes no refund())")
