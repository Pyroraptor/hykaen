extends GutTest
## tests/unit/test_combine_target_invalidated_strike.gd — FEAT-010 (US-010;
## FR-009; ADR-006)
##
## Iteration N (Combinations): proves the graceful-skip half of FEAT-010's
## abort-safe execution invariant — when a Combine's queued STRIDE
## sub-action has ALREADY committed but the subsequent queued STRIKE's own
## target has become invalid (no longer selectable) by the time STRIKE's own
## resolution step runs, the Combine does NOT abort/throw: it reaches a
## defined terminal ExecutionResult (ok==true, with the Strike sub-result
## tagged skipped/TARGET_INVALIDATED), and its ONE action-economy + Stamina
## charge is still committed (since an effect — the Stride's own move —
## genuinely applied, so charging is not an orphaned spend).
##
## Mirrors tests/unit/test_combine_movement_lockout.gd's "real fake session +
## real ActionEconomy, no MainScene.tscn boot required" convention, plus
## tests/unit/test_combine_single_charge.gd's "boot the REAL res://MainScene.tscn
## composition root" convention for a genuine end-to-end proof against the
## REAL StrikeActionController's own ERR_TARGET_NOT_SELECTABLE contract.
##
## test_criteria covered:
##   2. Strike target invalidated after Stride resolves: execute() reaches a
##      defined terminal ExecutionResult (ok==true with skipped Strike
##      effect / explicit TARGET_INVALIDATED-tagged sub-result), and the
##      ledger charge IS committed (Stride itself already committed).
##   3. State-consistency assertion: count(effects applied) ==
##      count(ledger charges committed) -- exactly one effect (the Stride
##      move) applied, exactly one ledger charge (action + Stamina)
##      committed; the skipped Strike contributes neither an effect nor a
##      second charge.

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")


## FakeSession — mirrors tests/unit/test_combine_movement_lockout.gd's
## established minimal double.
class FakeSession:
	var _actor
	var _economy

	func _init(actor, economy) -> void:
		_actor = actor
		_economy = economy

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return _economy


## FakeCommittingStrideController — a Stride sub-controller stand-in whose
## execute() genuinely applies its own effect (mirrors the REAL
## StrideActionController's contract of moving the actor's live hex_coord)
## and reports ok=true, exactly as a Stride that resolved BEFORE its
## target's own invalidation would.
class FakeCommittingStrideController:
	var _actor
	var _destination
	var execute_call_count: int = 0

	func _init(actor, destination) -> void:
		_actor = actor
		_destination = destination

	func execute(_payload = null, _no_self_spend_execution: bool = false) -> Dictionary:
		execute_call_count += 1
		_actor.hex_coord = _destination
		return {"ok": true, "resolved": true, "hex_coord": _destination}


## FakeTargetInvalidatedStrikeController — a Strike sub-controller stand-in
## whose target has become invalid by the time its own resolution step
## runs, mirroring presentation/strike_action_controller.gd's own REAL
## ERR_TARGET_NOT_SELECTABLE contract exactly (same "ok"/"error" keys, and
## crucially applies NO effect -- no damage, no mutation of any kind).
class FakeTargetInvalidatedStrikeController:
	var execute_call_count: int = 0
	var effect_applied: bool = false

	func execute(_payload = null, _no_self_spend_execution: bool = false) -> Dictionary:
		execute_call_count += 1
		return {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}


func _deps(actor, economy, stride_controller, strike_controller) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, economy))
	var controllers := {"STRIDE": stride_controller, "STRIKE": strike_controller}
	var controller_for := func(verb_id: String):
		return controllers.get(verb_id, null)
	return {"session_holder": holder, "controller_for": controller_for}


func _make_actor(stamina: int = 3) -> CombatantClass:
	var actor := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = stamina
	actor.actions_this_turn = ["MOVEMENT", "PRIMARY"]
	return actor


func _make_economy() -> ActionEconomyClass:
	var economy := ActionEconomyClass.new()
	economy.start_of_turn()
	return economy


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a Strike target invalidated after Stride resolves reaches a
# defined terminal ok==true ExecutionResult (graceful skip, never a crash).
# ══════════════════════════════════════════════════════════════════════════

func test_target_invalidated_strike_reaches_defined_ok_true_terminal_result() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var destination := HexCoordClass.new(2, 0)
	var stride_controller := FakeCommittingStrideController.new(actor, destination)
	var strike_controller := FakeTargetInvalidatedStrikeController.new()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	var result: Dictionary = await controller.execute(null)

	assert_true(
		result.get("ok", false),
		"a Combine whose Strike target is invalidated AFTER its Stride already committed must still reach a defined ok=true terminal state (a graceful skip, not an abort)"
	)
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the resolved Stride and the gracefully-skipped Strike are both reported as resolved (no abort)")
	assert_eq(
		result.get("skipped_verb_ids", []), ["STRIKE"],
		"the Strike entry must be tagged as skipped -- an explicit TARGET_INVALIDATED-tagged sub-result, not silently indistinguishable from a genuine hit"
	)


func test_target_invalidated_strike_applies_no_effect_of_its_own() -> void:
	var actor := _make_actor()
	var economy := _make_economy()
	var destination := HexCoordClass.new(2, 0)
	var stride_controller := FakeCommittingStrideController.new(actor, destination)
	var strike_controller := FakeTargetInvalidatedStrikeController.new()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	await controller.execute(null)

	assert_eq(stride_controller.execute_call_count, 1, "the Stride sub-action must be attempted exactly once")
	assert_eq(strike_controller.execute_call_count, 1, "the Strike sub-action must still be attempted exactly once (its own targeting/legality check runs at its own resolution step)")
	assert_false(strike_controller.effect_applied, "the invalidated-target Strike must apply NO effect of its own -- it is skipped, not resolved")
	assert_true(actor.hex_coord.equals(destination), "the Stride's own effect (the move) must have genuinely committed")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 3 — the ledger charge IS committed (Stride already
# committed), and it is committed exactly once -- one effect (Stride's
# move), one ledger charge (action + Stamina), never zero and never two.
# ══════════════════════════════════════════════════════════════════════════

func test_target_invalidated_strike_still_commits_exactly_one_ledger_charge() -> void:
	var actor := _make_actor(3)
	var economy := _make_economy()
	var destination := HexCoordClass.new(2, 0)
	var stride_controller := FakeCommittingStrideController.new(actor, destination)
	var strike_controller := FakeTargetInvalidatedStrikeController.new()
	var budget_before: int = economy.get_remaining()

	var controller := CombineActionControllerClass.new(_deps(actor, economy, stride_controller, strike_controller))
	var result: Dictionary = await controller.execute(null)

	assert_true(result.get("ok", false), "fixture: the Combine must resolve ok=true for this scenario")

	# ── State-consistency: count(effects applied) == count(ledger charges
	# committed). Exactly one effect (the Stride's move) applied; exactly
	# one ledger charge (action-economy + Stamina) committed. ─────────────
	assert_eq(
		economy.get_remaining(), budget_before - 1,
		"a Combine whose Stride committed (even with a subsequently-skipped Strike) must still spend exactly ONE action -- never zero (orphaned effect with no charge) and never two"
	)
	assert_false(economy.can_take_action(), "the actor's one action for the turn must now be spent, via the Combine's own single charge")
	assert_eq(actor.stamina, 2, "a Combine whose Stride committed must still spend exactly ONE Stamina, even though the queued Strike was gracefully skipped")
	assert_false(
		economy.can_take_movement_action(),
		"the Movement-trait lockout must still trip -- the queue contained a STRIDE that genuinely committed"
	)
	assert_false(economy.is_self_spend_suppressed(), "the suppression flag must never leak past execute()")


# ══════════════════════════════════════════════════════════════════════════
# Boot-real complement — drives the REAL, live StrideActionController +
# StrikeActionController (resolved via the SAME `_controller(verb_id)`
# table lookup every other verb uses). Titus Strides AWAY from a Skeleton
# that starts in melee reach, so the Skeleton is genuinely reachable BEFORE
# the Stride but genuinely unreachable (target invalidated) by the time the
# queued Strike's own resolution step runs -- reproducing the "target
# becomes invalid before its resolution step" scenario against real
# production code, not a re-implemented mock of its contract.
# ══════════════════════════════════════════════════════════════════════════

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"


## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into EXPLORATION
## mode with the legacy combat pipeline (round_session, verb bar/selection
## overlay configuration, turn_controller signal wiring) gated behind a real
## _on_combat_triggered() handoff -- see MainScene.gd's own FEAT-316 doc.
## This suite drives `_controller("STRIKE")`/`_controller("COMBINE")` and
## `round_session` directly, so `_boot_main_scene()` now also drives that
## SAME real handoff (mirroring tests/boot/test_first_cast_firebolt.gd's
## established convention), landing the instance in GameMode.COMBAT with a
## live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _titus(instance):
	assert_true(instance._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var titus = instance._party[0]
	assert_eq(titus.name, "Titus", "fixture assumption: the first party member is Titus")
	return titus


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func test_boot_real_strike_target_invalidated_after_stride_gracefully_skips_but_still_charges() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	assert_eq([titus_start_hex.q, titus_start_hex.r], [0, 0], "fixture assumption: Titus starts at (0,0) per the prologue encounter resource")
	assert_eq([skeleton.hex_coord.q, skeleton.hex_coord.r], [1, 0], "fixture assumption: the Skeleton starts at (1,0), adjacent to Titus")

	var strike_controller_before = instance._controller("STRIKE")
	assert_true(
		strike_controller_before.reachable_target_ids().has(skeleton.display_id()),
		"fixture assumption: the Skeleton must be a reachable Strike target from Titus's START hex"
	)

	# Stride AWAY from the Skeleton -- (-2,0) is within Titus's real Speed
	# (distance 2 <= Movement.DEFAULT_SPEED = 4) and unoccupied, but leaves
	# the Skeleton (1,0) at hex_distance 3 -- no longer reachable once
	# Strike's own resolution step (which always reads the actor's LIVE,
	# POST-Stride position) runs.
	var stride_destination := HexCoordClass.new(-2, 0)

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var budget_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	var skeleton_hp_before: int = skeleton.hp_current

	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")

	var result: Dictionary = await combine_controller.execute({
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	})

	assert_true(result.get("ok", false), "a Combine whose Strike target is invalidated by the real, booted Strike controller must still reach ok=true (graceful skip)")
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"])
	assert_eq(result.get("skipped_verb_ids", []), ["STRIKE"], "the real, booted Strike must be tagged skipped once its target is out of reach")

	assert_true(titus.hex_coord.equals(stride_destination), "Titus's Stride must have genuinely committed (the move applied)")
	assert_eq(skeleton.hp_current, skeleton_hp_before, "the Skeleton must take NO damage -- the invalidated-target Strike applies no effect")

	# ── State-consistency: exactly one effect (the Stride) applied, exactly
	# one ledger charge (action + Stamina) committed. ──────────────────────
	assert_eq(economy.get_remaining(), budget_before - 1, "exactly one action-economy charge must be committed -- the Stride's own effect genuinely applied")
	assert_eq(titus.stamina, stamina_before - 1, "exactly one Stamina must be spent -- matching the single committed effect")
