extends GutTest
## tests/gut/test_round_session_reaction_resolver_injection.gd
##
## GUT test suite for FEAT-002 (US-002 / FR-002, ADR-002): the
## reaction-resolver injection seam on core/application/round_session.gd.
##
## This feature adds set_reaction_resolver_fn(fn: Callable) to RoundSession,
## mirroring the existing set_token_reposition_fn() Dependency-Inversion
## pattern (FEAT-008): a typed-Callable seam matching the ReactionResolverPort
## contract `async func(trigger: Dictionary) -> Dictionary`, established
## WITHOUT RoundSession ever importing/referencing any concrete Presentation
## class (e.g. presentation/turn_controller.gd's TurnController) by type.
## No call site wires this Callable into advance_ai_turn()'s Strike path yet
## -- that is separate, later work -- so this suite instead proves the seam
## itself: the Callable is stored/retrievable, RoundSession's own internal
## invocation helper (_resolve_reaction()) correctly awaits/returns an
## injected resolver's result, defaults safely to a synchronous 'none'/PASS
## result when nothing was injected, and every existing headless/sim-facing
## RoundSession behavior (advance_ai_turn(), run_autonomous_to_completion())
## remains byte-for-byte unchanged when no resolver is ever injected.
##
## Verifies (test_criteria):
##   1. set_reaction_resolver_fn(fn) stores the Callable and is
##      retrievable/invokable by RoundSession internals.
##   2. When no resolver is injected, RoundSession behavior for
##      headless/sim callers is byte-for-byte unchanged from the pre-change
##      baseline.
##   3. RoundSession never references TurnController or any presentation
##      class by type (static source inspection).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double port implementations (mirrors tests/unit/core/application/test_round_session_ai_turn.gd) ──

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


## BrokenAIDecisionPort — always returns an empty/invalid decision, used to
## exercise advance_ai_turn()'s pre-existing CWE-835 defensive-advance
## fallback (mirrors tests/unit/core/application/test_round_session_ai_turn.gd),
## proving that fallback is completely untouched by this feature.
class BrokenAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:
		return {}


## RecordingReactionResolver — a scripted ReactionResolverPort double: records
## the trigger Dictionary it was called with and returns a fixed choice. Used
## to prove criterion 1 (stored/invokable) without depending on any
## presentation-layer class.
class RecordingReactionResolver:
	extends RefCounted

	var calls: Array = []
	var choice_to_return: String = "dodge"

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": choice_to_return}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


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


## Builds a fully-wired, REAL RunRoundUseCase plus its fake ports (mirrors
## tests/unit/core/application/test_round_session_ai_turn.gd's identically-
## named helper).
func _make_use_case(entries: Array, ai_port, random_number_port, event_sink_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_reaction_resolver_fn(fn) stores the Callable and is
# retrievable/invokable by RoundSession internals.
# ══════════════════════════════════════════════════════════════════════════

func test_set_reaction_resolver_fn_stores_the_callable_and_is_retrievable() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var resolver := RecordingReactionResolver.new()
	var fn := Callable(resolver, "resolve")

	session.set_reaction_resolver_fn(fn)

	assert_true(session._reaction_resolver_fn.is_valid(), "the injected Callable must be stored and retrievable off RoundSession")
	assert_eq(session._reaction_resolver_fn.get_object(), resolver, "the stored Callable must target the exact injected object")
	assert_eq(session._reaction_resolver_fn.get_method(), &"resolve", "the stored Callable must target the exact injected method")


func test_set_reaction_resolver_fn_is_invokable_by_round_session_internals() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var resolver := RecordingReactionResolver.new()
	resolver.choice_to_return = "parry"
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var trigger: Dictionary = {"attacker_id": "bravo", "target_id": "alpha", "defense_type": "ac"}
	var result: Dictionary = await session._resolve_reaction(trigger)

	assert_eq(resolver.calls.size(), 1, "RoundSession's internal reaction-resolution seam must invoke the injected Callable exactly once")
	assert_eq(resolver.calls[0], trigger, "the injected Callable must be invoked with the exact trigger Dictionary passed in")
	assert_eq(result, {"choice": "parry"}, "RoundSession must return the injected resolver's result verbatim")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: when no resolver is injected, RoundSession behavior for
# headless/sim callers is byte-for-byte unchanged from the pre-change
# baseline -- both the new internal seam's own default-safety fallback, and
# every pre-existing public behavior (advance_ai_turn()/
# run_autonomous_to_completion()) that never touches this seam at all.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_reaction_defaults_to_synchronous_none_pass_when_unset() -> void:
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_false(session._reaction_resolver_fn.is_valid(), "fixture assumption: no resolver has been injected on a fresh session")

	var result: Dictionary = await session._resolve_reaction({"attacker_id": "bravo", "target_id": "alpha"})

	assert_eq(result, {"choice": "none"}, "an un-injected resolver must fall back to a synchronous 'none' (PASS) result -- the pre-change baseline")


func test_advance_ai_turn_behavior_is_unchanged_when_no_resolver_is_injected() -> void:
	# Mirrors tests/unit/core/application/test_round_session_ai_turn.gd's
	# criterion-1 scenario exactly (same fixture, same seed) -- proving
	# advance_ai_turn() resolves identically whether or not this feature
	# exists, since it never calls the new seam.
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(42)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_eq(session.current_actor().get("name", ""), "Bravo", "the Enemy must be the current actor")
	var hp_before: int = alpha.get("hp_current", 0)

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		rig["history"].entries.size(), 1,
		"advance_ai_turn() must resolve exactly one action via resolve_action_use_case, unchanged by this feature"
	)
	assert_true(alpha.get("hp_current", 0) <= hp_before, "the AI's resolved Strike must still be able to damage its target")
	assert_eq(session.current_actor().get("name", ""), "Alpha", "advance_ai_turn() must still advance the cursor to the next living, un-Spent actor")


func test_advance_ai_turn_defensive_fallback_unchanged_when_no_resolver_is_injected() -> void:
	# Mirrors tests/unit/core/application/test_round_session_ai_turn.gd's
	# criterion-2 CWE-835 fallback scenario exactly.
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var entries: Array = [_entry(bravo), _entry(alpha)]
	var bravo_action_economy = entries[0]["action_economy"]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var rig: Dictionary = _make_use_case(entries, BrokenAIDecisionPort.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])
	var budget_before: int = bravo_action_economy.get_remaining()

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "a broken AI decision must not stall/deadlock the session (CWE-835 guard), unchanged by this feature")
	assert_eq(rig["history"].entries.size(), 0, "no action-resolution history entry may be recorded for a WAIT resolution")
	assert_eq(
		bravo_action_economy.get_remaining(), budget_before - 1,
		"the null-action AI sentinel must still resolve as an explicit WAIT, spending exactly one action"
	)

	var turn_events: Array = event_sink_port.events.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_eq(turn_events.size(), 1, "the WAIT-driven cursor advance must still be logged via event_sink_port (TurnAdvancedEvent)")


func test_run_autonomous_to_completion_unchanged_when_no_resolver_is_injected() -> void:
	# Mirrors the autonomous (sim) path's pre-existing behavior -- the
	# balance-sim entry point never calls set_reaction_resolver_fn(), so
	# this must complete the round exactly as before with a decided outcome.
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(7)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	assert_false(session._reaction_resolver_fn.is_valid(), "fixture assumption: the autonomous/sim path never injects a resolver")

	session.run_autonomous_to_completion()

	assert_true(session.is_round_over(), "run_autonomous_to_completion() must still end the round when no resolver is injected")
	assert_true(
		session.outcome() in ["won", "lost", ""],
		"run_autonomous_to_completion() must still report one of its pre-existing outcome values"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: RoundSession never references TurnController or any
# presentation class by type (static source inspection).
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_never_references_turn_controller_or_any_presentation_class_by_type() -> void:
	var round_session_source: String = _read_file("res://core/application/round_session.gd")

	assert_false(
		round_session_source.contains("TurnController"),
		"RoundSession must never reference TurnController by type -- the reaction-resolver seam is a Callable signature only (ADR-002)"
	)
	assert_false(
		round_session_source.contains("res://presentation"),
		"RoundSession must never preload/reference anything under presentation/ (ADR-001/ADR-002 -- no inward layer imports Presentation)"
	)
	assert_false(
		round_session_source.contains("extends Node") or round_session_source.contains("extends Control"),
		"RoundSession must remain a pure RefCounted -- no Node/Control scene-tree inheritance (ADR-001 domain/application purity)"
	)
