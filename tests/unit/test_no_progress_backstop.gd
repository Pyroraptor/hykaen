extends GutTest
## tests/unit/test_no_progress_backstop.gd
##
## GUT test suite for FEAT-005 (US-003 / FR-003, ADR-011): the interactive
## no-progress backstop for round termination.
##
## core/application/round_session.gd's AUTONOMOUS API
## (run_autonomous_to_completion(), used only by RunRoundUseCase.execute())
## already carries the FEAT-097/CWE-835/FIND-095 backstop: when a full cycle
## pass over the turn order resolves ZERO actions, the round force-terminates
## with a safe DRAW rather than spinning forever. The INTERACTIVE, one-
## turn-at-a-time API (current_actor/advance_ai_turn/end_current_turn) that
## presentation/turn_controller.gd drives had NO equivalent guarantee of its
## own — the only thing standing between a genuinely stalled interactive
## round and an infinite loop was turn_controller.gd's `_MAX_AI_TURNS_PER_DRIVE`
## (1000) circuit breaker, which per this steel thread's exit criterion must
## never actually be the thing that terminates a round; tripping it is a bug
## signal, not a safety net.
##
## A genuine interactive stall is straightforward to construct: WAIT
## (core/rules/actions.gd Actions.resolve_wait()) is ONLY ever resolved by
## advance_ai_turn() for an Enemy current_actor() -- a Player's
## end_current_turn() free-pass (US-002 / FR-002, ADR-010) deliberately never
## spends an action, by design, so that choosing not to act never costs the
## player anything. A round made ENTIRELY of Player-side combatants who all
## just free-pass therefore has NO mechanism (WAIT is never reached/"disabled"
## for this scenario) that would ever spend a single action -- every living
## combatant's ActionEconomy stays un-Spent forever, so the pre-existing
## "every living combatant is Spent" termination condition alone could never
## fire. Only a full-cycle-zero-progress backstop, ported into the
## interactive cursor path itself (round_session.gd's _advance_cursor()),
## can terminate such a round safely.
##
## Verifies (test_criteria):
##   1. A constructed stall scenario (an all-Player turn order, WAIT never
##      reached/"disabled") resolves to a DRAW via the backstop -- in a
##      handful of end_current_turn() calls, nowhere near turn_controller.gd's
##      1000-turn last-resort guard.
##   2. A full zero-progress pass over the actionable combatants forces
##      outcome=draw via finish()'s RoundResult ("outcome": "DRAW",
##      "encounter_outcome": "").
##   3. Regression: the pre-existing AUTONOMOUS sim backstop
##      (run_autonomous_to_completion(), exercised end-to-end via
##      RunRoundUseCase.execute()) is completely unchanged by this feature --
##      same BrokenAIDecisionPort-stalled fixture as
##      tests/test_run_round_use_case.gd's test_stalled_cycle_backstop_terminates_with_draw,
##      still resolving to DRAW after Alpha exhausts its own 7-action budget.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")

## Defensive test-side bound only -- proves the backstop fires WAY before
## turn_controller.gd's own 1000-turn last-resort guard would ever be
## reached, without actually depending on that Presentation-layer constant
## (this suite exercises RoundSession directly, in isolation).
const _TEST_ITERATION_BOUND: int = 50


# ── Fake/double port implementations (mirrors tests/unit/core/application/test_round_session.gd) ──

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## FakeAIDecisionPort — "Strike the first living target" (unused by the
## all-Player stall scenario below, but required to construct the shared rig
## / used directly by the autonomous regression scenario for Alpha's side).
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, targets: Array) -> Dictionary:
		for t in targets:
			if t.get("hp_current", 0) > 0:
				return {"action_type": "Strike", "target": t}
		return {"action_type": "", "target": {}}


## BrokenAIDecisionPort — always returns an empty/invalid decision. Used by
## the AUTONOMOUS regression scenario ONLY, exactly mirroring
## tests/test_run_round_use_case.gd's own BrokenAIDecisionPort double, to
## force the pre-existing any_action_resolved_this_cycle backstop.
class BrokenAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:
		return {}


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String = "") -> Dictionary:
	return {
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase (mirrors
## tests/unit/core/application/test_round_session.gd's rig) plus its fake
## ports.
func _make_use_case(entries: Array, ai_port, seed: int) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var event_sink_port     = FakeEventSinkPort.new()
	var round_history_port  = FakeRoundHistoryPort.new()
	var random_number_port  = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {
		"use_case":                run_round_use_case,
		"event_sink":              event_sink_port,
		"history":                 round_history_port,
		"resolve_action_use_case": resolve_action_use_case
	}


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 & 2: constructed interactive stall scenario (WAIT never
# reached/"disabled" -- an all-Player turn order) resolves to a DRAW via the
# backstop, not the 1000-turn last-resort guard; a full zero-progress pass
# forces outcome=draw via finish().
# ══════════════════════════════════════════════════════════════════════════

func test_interactive_all_player_stall_terminates_via_backstop_not_1000_turn_guard() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	# Both sides have a living combatant (so DetermineOutcomeUseCase never
	# shortcuts to an immediate won/lost/DRAW verdict BEFORE any turn is
	# driven) -- only a genuine full-cycle-zero-progress backstop can
	# terminate this round. WAIT (only ever resolved by advance_ai_turn())
	# is deliberately never reached/"disabled" for this scenario -- every
	# turn (whichever actor's) is driven purely via end_current_turn()'s
	# free-pass path, which never spends an action.
	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 1)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Alpha")
	assert_false(session.is_round_over())

	var iterations: int = 0
	while not session.is_round_over() and iterations < _TEST_ITERATION_BOUND:
		session.end_current_turn()
		iterations += 1

	assert_true(
		session.is_round_over(),
		"a full zero-progress pass over an all-Player, always-free-passing turn order must terminate the round via the backstop"
	)
	assert_true(
		iterations < _TEST_ITERATION_BOUND,
		"the backstop must fire within a handful of turns, nowhere near a 1000-turn last-resort guard"
	)

	# Neither combatant ever became Spent -- proves the round ended via the
	# no-progress backstop, NOT the pre-existing "every living combatant is
	# Spent" termination condition.
	assert_false(entries[0]["action_economy"].is_spent(), "Alpha must never have spent an action in this scenario")
	assert_false(entries[1]["action_economy"].is_spent(), "Bravo must never have spent an action in this scenario")

	var result: Dictionary = session.finish()
	assert_eq(result.get("outcome", "MISSING"), "DRAW", "a full zero-progress pass must force outcome=DRAW via finish()")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "a backstop DRAW must never set encounter_outcome")


func test_interactive_stall_backstop_fires_after_exactly_one_full_cycle_pass() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", false)
	var charlie: Dictionary = _durable_combatant("Charlie", true)
	var entries: Array = [_entry(alpha), _entry(bravo), _entry(charlie)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 2)
	var session = rig["use_case"].begin_round(1, [alpha, bravo], [charlie])

	# One full cycle pass over 3 actionable, always-free-passing combatants:
	# Alpha -> Bravo -> Charlie -> (wrap back to Alpha triggers the backstop).
	session.end_current_turn()
	assert_false(session.is_round_over(), "round must not be over after only 1 of 3 turns")
	session.end_current_turn()
	assert_false(session.is_round_over(), "round must not be over after only 2 of 3 turns")
	session.end_current_turn()
	assert_true(session.is_round_over(), "the backstop must fire exactly once the full cycle pass (all 3) completes with zero progress")

	assert_eq(session.finish().get("outcome", "MISSING"), "DRAW")


func test_interactive_backstop_does_not_fire_when_a_combatant_actually_acts() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, FakeAIDecisionPort.new(), 3)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	# Alpha resolves a real Strike against Bravo BEFORE free-passing (mirrors
	# StrikeActionControl resolving directly via resolve_action_use_case,
	# exactly as documented on end_current_turn()) -- genuine progress.
	var resolve_result: Dictionary = rig["resolve_action_use_case"].resolve(
		alpha, entries[0]["action_economy"], bravo, "Strike", 1, 0
	)
	assert_true(resolve_result.get("resolved", false))

	session.end_current_turn()  # Alpha (acted) -> Bravo
	assert_false(session.is_round_over())
	session.end_current_turn()  # Bravo (free-pass) -> wraps to Alpha
	# The cycle just completed included Alpha's real Strike -- progress was
	# made, so the backstop must NOT fire, even though Bravo itself free-passed.
	assert_false(
		session.is_round_over(),
		"a cycle containing at least one real action must not trigger the no-progress backstop"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (regression): the pre-existing AUTONOMOUS sim backstop
# (run_autonomous_to_completion(), exercised via RunRoundUseCase.execute())
# is completely unchanged -- mirrors
# tests/test_run_round_use_case.gd's test_stalled_cycle_backstop_terminates_with_draw.
# ══════════════════════════════════════════════════════════════════════════

func test_autonomous_sim_backstop_regression_unchanged_behavior() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	# Bravo's AIDecisionPort never returns a usable decision -- in the
	# AUTONOMOUS path (unlike the interactive advance_ai_turn() path), a
	# null AI decision is simply skipped for the cycle (no WAIT resolution),
	# so only the any_action_resolved_this_cycle backstop can prevent this
	# from hanging -- exactly the pre-existing, byte-for-byte-preserved
	# contract of run_autonomous_to_completion().
	var rig: Dictionary = _make_use_case(entries, BrokenAIDecisionPort.new(), 42)
	var result: Dictionary = rig["use_case"].execute(1, [alpha], [bravo])

	assert_eq(result.get("outcome", ""), "DRAW", "the autonomous stalled-cycle backstop must still terminate with a safe DRAW")
	assert_eq(result.get("encounter_outcome", "MISSING"), "", "a backstop DRAW must never set encounter_outcome")

	# Alpha must still resolve its own full 7-action budget against Bravo
	# before the backstop fires (Alpha always finds Bravo, a living target).
	var history: Array = result.get("history", [])
	var alpha_entries: Array = history.filter(func(e): return e.get("attacker", {}).get("name", "") == "Alpha")
	assert_eq(alpha_entries.size(), 7, "Alpha must still resolve all 7 of its own actions before the backstop fires (unchanged autonomous behavior)")
