extends GutTest
## tests/gut/test_reaction_error_handling_and_observability.gd
##
## GUT suite for FEAT-007 (US-003/US-007, ADR-007): defensive error handling
## and debug observability for the async reaction chain established by
## FEAT-002..FEAT-006 (core/application/round_session.gd's
## set_reaction_resolver_fn()/advance_ai_turn(), presentation/
## turn_controller.gd's resolve_reaction(), core/application/
## resolve_action_use_case.gd's resolve()).
##
## Verifies (this feature's test_criteria):
##   1. A resolver returning a Dictionary missing 'choice' falls back safely
##      (to the "none"/PASS-equivalent active_defense) without crashing or
##      hanging the round loop.
##   2. A chooser returning a choice outside legal_reactions is coerced to
##      'pass' by TurnController.resolve_reaction(), and
##      reaction_window.resume() still performs the canonical legality check
##      (never bypassed by the new defensive layer).
##   3. An unknown active_defense string reaching ResolveActionUseCase.resolve()
##      is coerced to 'none' at the use-case boundary, with no damage-number
##      corruption (identical output/RNG consumption to an explicit 'none').
##   4. A freed/tree-exiting Node mid-await (TurnController.resolve_reaction())
##      aborts the coroutine cleanly instead of resuming into freed memory.
##   5. Debug-gated trace log lines are emitted for trigger-built/
##      awaiting-resolver-start/resolver-resolved (RoundSession) and for the
##      ReactionResolvedEvent fields (TurnController) when the debug flag is
##      enabled, and completely suppressed when disabled (the default).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")


# ── Fake/double port implementations (mirrors tests/gut/
#    test_async_reaction_propagation.gd's identically-named doubles) ────────

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


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var calls: Array = []

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		calls.append(dice_spec)
		var v = _values[_index]
		_index += 1
		return v


## MalformedReactionResolver — a ReactionResolverPort double
## (`async func(trigger: Dictionary) -> Dictionary`) that always answers
## with a Dictionary MISSING the 'choice' key entirely — the exact
## malformed-adapter-response shape criterion 1 exercises.
class MalformedReactionResolver:
	extends RefCounted

	var calls: Array = []

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"not_choice": "bogus"}


## RecordingReactionResolver — a well-formed ReactionResolverPort double,
## reused here purely as a harmless collaborator for the debug-trace tests
## (criterion 5), which only care about the trace lines emitted around it.
class RecordingReactionResolver:
	extends RefCounted

	var calls: Array = []
	var choice_to_return: String = "none"

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": choice_to_return}


## FixedChoiceReactionChooser — a ReactionChooserPort test double that
## always answers with a caller-supplied choice, regardless of
## legal_reactions (used to exercise both a legal answer and a deliberately
## illegal one).
class FixedChoiceReactionChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var _fixed_choice: String

	func _init(fixed_choice: String) -> void:
		_fixed_choice = fixed_choice

	func choose(_legal_reactions: Array, _context: Dictionary) -> String:
		return _fixed_choice


## TreeExitingReactionChooser — a ReactionChooserPort test double that
## detaches a caller-supplied Node from its parent (synchronously, via
## remove_child()) the moment it is asked to choose, simulating scene
## teardown happening WHILE TurnController.resolve_reaction() is suspended
## on `await _reaction_chooser.choose(...)`. Deliberately uses remove_child()
## rather than free()/queue_free(): it exercises the exact "tree-exiting"
## scenario this feature's design notes describe (a Node leaving the
## SceneTree mid-await) without ever touching freed memory, so this test can
## assert on the aborted coroutine's return value safely.
class TreeExitingReactionChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var _parent: Node
	var _node_to_detach: Node
	var _choice_to_return: String

	func _init(parent: Node, node_to_detach: Node, choice_to_return: String) -> void:
		_parent = parent
		_node_to_detach = node_to_detach
		_choice_to_return = choice_to_return

	func choose(_legal_reactions: Array, _context: Dictionary) -> String:
		_parent.remove_child(_node_to_detach)
		return _choice_to_return


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
## tests/gut/test_async_reaction_propagation.gd's identically-named helper).
func _make_session(entries: Array, party: Array, enemies: Array, seed: int) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()
	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var session = run_round_use_case.begin_round(1, party, enemies)
	return {"session": session, "history": round_history_port, "event_sink": event_sink_port}


func _make_resolve_action_use_case_rig(scripted_values: Array) -> Dictionary:
	var rng_port    = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


func _fresh_ae():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _sanitize_attacker() -> Dictionary:
	return {
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	}


func _sanitize_target() -> Dictionary:
	return {"name": "Target", "hp_current": 50, "ac": 5, "conditions": []}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a resolver returning a Dictionary missing 'choice' falls back
# safely without crashing or hanging the round loop.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_choice_to_active_defense_missing_choice_key_falls_back_to_none() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]

	var coerced: String = session._reaction_choice_to_active_defense({"not_choice": "bogus"})

	assert_eq(
		coerced, "none",
		"a malformed reaction-resolver Dictionary missing 'choice' must be coerced to the 'none' (PASS-equivalent) active_defense"
	)


func test_advance_ai_turn_with_resolver_missing_choice_key_falls_back_without_crash_or_hang() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]
	assert_eq(session.current_actor().get("name", ""), "Bravo", "fixture assumption: the Enemy is the current actor")

	var resolver := MalformedReactionResolver.new()
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	# The test itself completing (rather than hanging forever) is part of
	# this criterion's "never hang the round loop" proof.
	var result: Dictionary = await session.advance_ai_turn()

	assert_eq(resolver.calls.size(), 1, "the malformed resolver must still be invoked exactly once")
	assert_true(result.get("ok", false), "a malformed resolver response must never crash advance_ai_turn()")
	assert_eq(
		rig["history"].entries.size(), 1,
		"the Strike must still resolve exactly once despite the malformed resolver response"
	)
	assert_eq(
		session.current_actor().get("name", ""), "Alpha",
		"the cursor must still advance normally -- the round loop is never stalled by a malformed resolver"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a chooser returning an illegal choice is coerced to 'pass' by
# TurnController, and reaction_window.resume() still performs the canonical
# legality check.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_coerces_illegal_chooser_choice_to_pass_and_resume_still_enforces_legality() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	# "not_a_real_choice" is deliberately neither PASS ("none") nor a member
	# of the Block trigger's legal_reactions (["block"]) -- resume()'s own
	# ERR_ILLEGAL_CHOICE gate (the canonical legality check, unchanged by
	# this feature) is what actually rejects it.
	var chooser := FixedChoiceReactionChooser.new("not_a_real_choice")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	var ae := _fresh_ae()
	var trigger: Dictionary = {
		"trigger_type":           "Block",
		"reactor":                {"name": "Reactor"},
		"reactor_action_economy": ae,
		"weapon":                 {"block_value": 3, "damage_die": 8, "parry_bonus": 0},
		"defense_type":           "ac",
		"attack_context":         {},
		"round_number":           4,
	}

	var result: Dictionary = await turn_controller.resolve_reaction(trigger, "player")

	assert_true(result.get("ok", false), "an illegal chooser answer must never propagate an errored Dictionary upstream")
	assert_eq(result.get("choice", ""), "none", "an illegal choice outside legal_reactions must be coerced to 'pass' ('none')")
	assert_false(ae.is_spent(), "a coerced-to-pass reaction must never spend the reactor's reaction budget")
	assert_eq(ae.get_remaining(), 7, "the reactor's budget must be completely untouched by a rejected/coerced illegal choice")


func test_reaction_window_resume_still_rejects_an_illegal_choice_directly() -> void:
	# Companion, lower-level proof that resume() itself (the SINGLE
	# canonical legality check, per ADR-007) is untouched by this feature --
	# TurnController's defensive coercion above is a defense-in-depth LAYER
	# on top of this, never a replacement for it.
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var ae := _fresh_ae()
	var trigger: Dictionary = {
		"trigger_type":           "Block",
		"reactor":                {"name": "Reactor"},
		"reactor_action_economy": ae,
		"weapon":                 {"block_value": 3, "damage_die": 8, "parry_bonus": 0},
		"defense_type":           "ac",
		"attack_context":         {},
		"round_number":           4,
	}

	var opened: Dictionary = window.open(trigger)
	assert_eq(opened.get("legal_reactions", []), ["block"], "fixture assumption: only 'block' is legal for this trigger")

	var result: Dictionary = window.resume(opened["window_id"], "not_a_real_choice", "player")

	assert_false(result.get("ok", true), "resume() must still reject a choice outside legal_reactions")
	assert_eq(result.get("error", ""), "ILLEGAL_CHOICE")
	assert_false(ae.is_spent(), "a rejected illegal choice must never spend the reactor's reaction")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: an unknown active_defense string is coerced to 'none' at the
# ResolveActionUseCase boundary, with no damage-number corruption.
# ══════════════════════════════════════════════════════════════════════════

func test_unknown_active_defense_is_coerced_to_none_with_no_damage_corruption() -> void:
	var rig_none: Dictionary = _make_resolve_action_use_case_rig([10, 4])
	var target_none: Dictionary = _sanitize_target()
	var result_none: Dictionary = rig_none["use_case"].resolve(
		_sanitize_attacker(), _fresh_ae(), target_none, "Strike", 1, 0, "", "none", {}
	)

	var rig_bogus: Dictionary = _make_resolve_action_use_case_rig([10, 4])
	var target_bogus: Dictionary = _sanitize_target()
	var result_bogus: Dictionary = rig_bogus["use_case"].resolve(
		_sanitize_attacker(), _fresh_ae(), target_bogus, "Strike", 1, 0, "", "definitely_not_a_real_defense", {}
	)

	assert_true(result_none.get("ok", false), "fixture assumption: the explicit 'none' baseline Strike must resolve")
	assert_true(
		result_bogus.get("ok", false),
		"an unrecognized active_defense must never crash/reject the Strike -- it is coerced, not rejected"
	)
	assert_eq(
		result_bogus.get("damage_final", -1), result_none.get("damage_final", -2),
		"an unknown active_defense must coerce to 'none' -- identical damage_final to the explicit 'none' baseline (no corruption)"
	)
	assert_eq(result_bogus["event"].hit, result_none["event"].hit, "hit outcome must be identical to the 'none' baseline")
	assert_eq(result_bogus["event"].crit, result_none["event"].crit, "crit outcome must be identical to the 'none' baseline")
	assert_eq(result_bogus["event"].defense_value, result_none["event"].defense_value, "defense_value must be identical to the 'none' baseline")
	assert_eq(
		target_bogus.get("hp_current", 0), target_none.get("hp_current", 0),
		"target hp_current must land identically -- no damage-number corruption from the malformed active_defense"
	)
	assert_eq(
		rig_bogus["rng_port"].calls, rig_none["rng_port"].calls,
		"an unrecognized active_defense must consume the identical RNG call sequence as 'none' -- proving the coercion happens BEFORE any resolution.gd math runs, not via an extra/parallel roll"
	)


func test_recognized_active_defense_values_pass_through_unmodified() -> void:
	# Companion check: every value ResolveActionUseCase's own recognized set
	# accepts must NOT be coerced -- only genuinely unrecognized Strings are.
	for recognized in ["none", "dodge", "block", "parry", "steel"]:
		var rig: Dictionary = _make_resolve_action_use_case_rig([1, 4])
		var target: Dictionary = _sanitize_target()
		var result: Dictionary = rig["use_case"].resolve(
			_sanitize_attacker(), _fresh_ae(), target, "Strike", 1, 0, "", recognized, {}
		)
		assert_true(result.get("ok", false), "a recognized active_defense ('%s') must resolve normally" % recognized)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: a freed/tree-exiting Node mid-await aborts the coroutine
# cleanly instead of resuming into freed memory.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_aborts_cleanly_when_owning_node_exits_tree_mid_await() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)

	var parent := Node.new()
	add_child_autofree(parent)

	var turn_controller := TurnControllerClass.new()
	autofree(turn_controller)
	parent.add_child(turn_controller)
	assert_true(turn_controller.is_inside_tree(), "fixture assumption: the node starts inside the SceneTree")

	var chooser := TreeExitingReactionChooser.new(parent, turn_controller, "block")
	turn_controller.configure_reactions(window, chooser)

	var ae := _fresh_ae()
	var trigger: Dictionary = {
		"trigger_type":           "Block",
		"reactor":                {"name": "Reactor"},
		"reactor_action_economy": ae,
		"weapon":                 {"block_value": 3, "damage_die": 8, "parry_bonus": 0},
		"defense_type":           "ac",
		"attack_context":         {},
		"round_number":           2,
	}

	var result: Dictionary = await turn_controller.resolve_reaction(trigger, "player")

	assert_false(turn_controller.is_inside_tree(), "fixture assumption: the chooser double detached the node mid-await")
	assert_false(result.get("ok", false), "resolve_reaction() must abort rather than resume as if nothing happened")
	assert_eq(result.get("error", ""), "ERR_NODE_FREED_MID_AWAIT")
	assert_false(
		ae.is_spent(),
		"an aborted mid-await coroutine must never reach reaction_window.resume() -- the reaction must never be spent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: debug-gated trace log lines are emitted when the debug flag
# is enabled, and completely suppressed when disabled (the default).
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_debug_trace_is_suppressed_by_default() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]

	var resolver := RecordingReactionResolver.new()
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	assert_eq(session.get_debug_trace_log(), [], "fixture assumption: debug tracing is disabled by default")
	await session.advance_ai_turn()
	assert_eq(
		session.get_debug_trace_log(), [],
		"no trace lines may be emitted while debug tracing is disabled (NFR-004/NFR-005 default-safety)"
	)


func test_round_session_debug_trace_emits_all_three_points_when_enabled() -> void:
	var bravo: Dictionary = _durable_combatant("Bravo", true, "bravo")
	var alpha: Dictionary = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]
	session.set_debug_trace_enabled(true)

	var resolver := RecordingReactionResolver.new()
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	await session.advance_ai_turn()

	var log: Array = session.get_debug_trace_log()
	assert_eq(log.size(), 3, "exactly three trace points must be emitted: trigger-built, awaiting-resolver-start, resolver-resolved")
	assert_true(String(log[0]).contains("reaction_trigger_built"), "trace point 1 must be the trigger-built line")
	assert_true(String(log[1]).contains("awaiting_resolver_start"), "trace point 2 must be the awaiting-resolver-start line")
	assert_true(String(log[2]).contains("resolver_resolved"), "trace point 3 must be the resolver-resolved line")
	assert_true(String(log[2]).contains("choice=none"), "the resolver-resolved trace line must carry the actual resolved choice")


func test_turn_controller_debug_trace_is_suppressed_by_default() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var chooser := FixedChoiceReactionChooser.new("block")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	var ae := _fresh_ae()
	var trigger: Dictionary = {
		"trigger_type":           "Block",
		"reactor":                {"name": "Reactor"},
		"reactor_action_economy": ae,
		"weapon":                 {"block_value": 3, "damage_die": 8, "parry_bonus": 0},
		"defense_type":           "ac",
		"attack_context":         {},
		"round_number":           9,
	}

	assert_eq(turn_controller.get_debug_trace_log(), [], "fixture assumption: debug tracing is disabled by default")
	await turn_controller.resolve_reaction(trigger, "player")
	assert_eq(
		turn_controller.get_debug_trace_log(), [],
		"no trace lines may be emitted while debug tracing is disabled (NFR-004/NFR-005 default-safety)"
	)


func test_turn_controller_debug_trace_emits_reaction_resolved_line_when_enabled() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var chooser := FixedChoiceReactionChooser.new("block")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)
	turn_controller.set_debug_trace_enabled(true)

	var ae := _fresh_ae()
	var trigger: Dictionary = {
		"trigger_type":           "Block",
		"reactor":                {"name": "Reactor"},
		"reactor_action_economy": ae,
		"weapon":                 {"block_value": 3, "damage_die": 8, "parry_bonus": 0},
		"defense_type":           "ac",
		"attack_context":         {},
		"round_number":           9,
	}

	var result: Dictionary = await turn_controller.resolve_reaction(trigger, "enemy")
	assert_eq(result.get("choice", ""), "block", "fixture assumption: the legal 'block' choice resolves normally")

	var log: Array = turn_controller.get_debug_trace_log()
	assert_eq(log.size(), 1, "exactly one reaction_resolved trace line must be emitted per resolve_reaction() call")
	var line: String = String(log[0])
	assert_true(line.contains("reaction_resolved"), "the trace line must be the reaction_resolved observability line")
	assert_true(line.contains("choice=block"), "the trace line must carry the resolved choice")
	assert_true(line.contains("resolved_by=enemy"), "the trace line must carry resolved_by")
	assert_true(line.contains("round_number=9"), "the trace line must carry the round_number")
