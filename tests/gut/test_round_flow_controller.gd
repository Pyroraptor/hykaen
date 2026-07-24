extends GutTest
## tests/gut/test_round_flow_controller.gd — FEAT-006 (US-006 / FR-007).
##
## GUT suite for presentation/round_flow_controller.gd's RoundFlowController
## — the extracted, independently-testable turn-order / round-lifecycle
## controller (see that file's own extensive doc for why MainScene.gd's OWN
## pre-existing, pinned `rewire_session()`/`_on_round_over()` pair is left
## byte-for-byte unchanged rather than deleted/replaced by this feature).
##
## Drives the controller purely through its own public setup(deps)/
## rewire_session()/notify_round_concluded() surface plus a FAKE
## run_round_use_case/turn_controller (this feature's own test_criteria
## wording: "given a fake round_session/run_round_use_case") — no
## MainScene.tscn boot is required for this suite, mirroring
## tests/gut/test_combine_targeting_session.gd's own "construct the real
## collaborator + fakes, no scene boot" convention.
##
## test_criteria covered:
##   1. round_over() fires exactly once per resolved round given a fake
##      round_session/run_round_use_case (single round, and across a
##      multi-round undecided-then-decided continuation).
##   2. rewire_session() called before setup() triggers assert(false) in
##      debug / push_error in release (ADR-005) and becomes a no-op.
##   3. MainScene connects to round_over() for UI cleanup only (no
##      game-state mutation) — static source assertion.
##   4. (full-suite regression is verified by running the whole GUT suite,
##      not scoped to this file).

const RoundFlowControllerClass = preload("res://presentation/round_flow_controller.gd")

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"
const ROUND_FLOW_CONTROLLER_SCRIPT_PATH: String = "res://presentation/round_flow_controller.gd"


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeRoundSession — duck-typed RoundSession stand-in exposing only the
## surface RoundFlowController itself ever calls (finish()/outcome()) so this
## suite can pin the round-flow ALGORITHM without depending on the real,
## much heavier core/application/round_session.gd.
class FakeRoundSession:
	extends RefCounted

	var round_number: int
	var outcome_value: String
	var finish_call_count: int = 0

	func _init(p_round_number: int, p_outcome_value: String) -> void:
		round_number = p_round_number
		outcome_value = p_outcome_value

	func finish() -> void:
		finish_call_count += 1

	func outcome() -> String:
		return outcome_value


## FakeRunRoundUseCase — spy standing in for RunRoundUseCase. Hands back
## pre-configured FakeRoundSession instances in FIFO order, one per
## begin_round() call, and records every call verbatim so this suite can
## assert the delegation contract (round_number/party/enemies) directly.
class FakeRunRoundUseCase:
	extends RefCounted

	var sessions_to_return: Array = []
	var begin_round_calls: Array = []

	func begin_round(round_number: int, party: Array, enemies: Array):
		begin_round_calls.append({"round_number": round_number, "party": party, "enemies": enemies})
		if sessions_to_return.is_empty():
			return null
		return sessions_to_return.pop_front()


## FakeTurnController — duck-typed TurnController stand-in exposing only the
## surface RoundFlowController itself ever touches: a `round_over` signal it
## connects to in setup(), and a `set_session()` coroutine it awaits from
## rewire_session(). Never actually auto-drives anything itself -- this
## suite's own test bodies decide exactly when a round "concludes" by
## emitting `round_over` directly, mirroring presentation/turn_controller.gd's
## real contract (its OWN `round_over` fires once its held RoundSession
## reports is_round_over()) without depending on that much heavier real class.
class FakeTurnController:
	extends RefCounted

	signal round_over()

	var set_session_calls: Array = []

	func set_session(round_session, end_turn_control = null, strike_action_control = null, verb_bar_view = null) -> void:
		set_session_calls.append({
			"round_session": round_session,
			"end_turn_control": end_turn_control,
			"verb_bar_view": verb_bar_view,
		})


# ══════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════

func _make_controller(run_round_use_case, turn_controller):
	var controller := RoundFlowControllerClass.new()
	controller.setup({
		"run_round_use_case": run_round_use_case,
		"turn_controller": turn_controller,
		"party_fn": func(): return ["hero"],
		"enemies_fn": func(): return ["golem"],
		"round_number": 1,
	})
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a — a single round that concludes UNDECIDED continues into the
# next round, and round_over() fires exactly once for that one conclusion.
# ══════════════════════════════════════════════════════════════════════════

func test_round_over_fires_exactly_once_when_a_round_concludes_undecided_and_continues() -> void:
	var round_1 := FakeRoundSession.new(1, "")
	var round_2 := FakeRoundSession.new(2, "")
	var use_case := FakeRunRoundUseCase.new()
	use_case.sessions_to_return = [round_1, round_2]
	var turn_controller := FakeTurnController.new()
	var controller = _make_controller(use_case, turn_controller)

	var round_over_signals: Array = []
	controller.round_over.connect(func(): round_over_signals.append(true))

	await controller.rewire_session()
	assert_eq(controller.get_round_session(), round_1, "the first rewire_session() call must obtain round 1")

	turn_controller.round_over.emit()
	await get_tree().process_frame

	assert_eq(round_over_signals.size(), 1, "round_over() must fire exactly once for this one resolved round")
	assert_eq(round_1.finish_call_count, 1, "the concluded round's own RoundSession must be finish()ed exactly once")
	assert_eq(controller.get_round_number(), 2, "an undecided outcome must increment the round number and continue")
	assert_eq(controller.get_round_session(), round_2, "continuation must obtain a fresh RoundSession for the next round")
	assert_eq(use_case.begin_round_calls.size(), 2, "exactly two begin_round() calls: the initial round plus the one continuation")
	assert_eq(use_case.begin_round_calls[1]["round_number"], 2)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b — across a 3-round undecided/undecided/decided continuation,
# round_over() fires exactly once PER resolved round (three explicit
# conclusion events -> three signal emissions, never more, never fewer).
# ══════════════════════════════════════════════════════════════════════════

func test_round_over_fires_exactly_once_per_round_across_a_multi_round_continuation() -> void:
	var round_1 := FakeRoundSession.new(1, "")
	var round_2 := FakeRoundSession.new(2, "")
	var round_3 := FakeRoundSession.new(3, "won")
	var use_case := FakeRunRoundUseCase.new()
	use_case.sessions_to_return = [round_1, round_2, round_3]
	var turn_controller := FakeTurnController.new()
	var controller = _make_controller(use_case, turn_controller)

	var round_over_signals: Array = []
	controller.round_over.connect(func(): round_over_signals.append(true))

	await controller.rewire_session()

	# Round 1 concludes (undecided) -- continues automatically into round 2.
	turn_controller.round_over.emit()
	await get_tree().process_frame
	assert_eq(round_over_signals.size(), 1, "round 1's own conclusion must fire round_over() exactly once")
	assert_eq(controller.get_round_number(), 2)

	# Round 2 concludes (undecided) -- continues automatically into round 3.
	turn_controller.round_over.emit()
	await get_tree().process_frame
	assert_eq(round_over_signals.size(), 2, "round 2's own conclusion must fire round_over() exactly once more (total 2)")
	assert_eq(controller.get_round_number(), 3)

	# Round 3 concludes (decided, 'won') -- terminal, no further round begins.
	turn_controller.round_over.emit()
	await get_tree().process_frame
	assert_eq(round_over_signals.size(), 3, "round 3's own conclusion must fire round_over() exactly once more (total 3)")
	assert_eq(controller.get_round_number(), 3, "a decided outcome must NOT increment the round number / start a further round")
	assert_eq(controller.get_outcome(), "won")
	assert_eq(use_case.begin_round_calls.size(), 3, "exactly three begin_round() calls total: rounds 1, 2, and 3 -- never a fourth")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1c — a round that concludes already DECIDED never continues, and
# still fires round_over() exactly once.
# ══════════════════════════════════════════════════════════════════════════

func test_round_over_fires_exactly_once_when_the_first_round_is_immediately_decided() -> void:
	var round_1 := FakeRoundSession.new(1, "lost")
	var use_case := FakeRunRoundUseCase.new()
	use_case.sessions_to_return = [round_1]
	var turn_controller := FakeTurnController.new()
	var controller = _make_controller(use_case, turn_controller)

	var round_over_signals: Array = []
	controller.round_over.connect(func(): round_over_signals.append(true))

	await controller.rewire_session()
	turn_controller.round_over.emit()
	await get_tree().process_frame

	assert_eq(round_over_signals.size(), 1)
	assert_eq(controller.get_round_number(), 1, "a decided first round must never increment the round number")
	assert_eq(use_case.begin_round_calls.size(), 1, "a decided outcome must never trigger a second begin_round() call")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — rewire_session() called before setup() is a programmer error:
# assert(false)/push_error (ADR-005) fire, and the call becomes a no-op.
# ══════════════════════════════════════════════════════════════════════════

func test_rewire_session_before_setup_is_a_no_op() -> void:
	var controller := RoundFlowControllerClass.new()

	assert_false(controller.is_setup(), "a freshly constructed controller must not report itself as setup")

	await controller.rewire_session()

	assert_null(controller.get_round_session(), "rewire_session() called before setup() must never create a RoundSession")
	assert_eq(controller.get_round_number(), 1, "rewire_session() called before setup() must never mutate the round number")


func test_notify_round_concluded_before_setup_is_a_no_op() -> void:
	var controller := RoundFlowControllerClass.new()

	var round_over_signals: Array = []
	controller.round_over.connect(func(): round_over_signals.append(true))

	controller.notify_round_concluded()

	assert_eq(round_over_signals.size(), 0, "notify_round_concluded() called before setup() must never emit round_over()")


func test_source_uses_the_assert_then_push_error_contract_violation_convention() -> void:
	var source: String = FileAccess.get_file_as_string(ROUND_FLOW_CONTROLLER_SCRIPT_PATH)

	assert_true(
		source.find("assert(false, message)") != -1,
		"rewire_session()/notify_round_concluded()'s before-setup() guard must assert(false, ...) in test/debug builds, mirroring the project's established contract-violation convention"
	)
	assert_true(
		source.count("push_error(message)") >= 2,
		"both before-setup() guards must also push_error() as release-build defense-in-depth"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — MainScene.gd wires a real RoundFlowController and connects
# to its round_over() signal for UI cleanup ONLY: no game-state mutation
# (ROUND_NUMBER/round_session/rewire_session()/_game_mode/_active_encounter_id
# assignment) inside the connected handler's own body. Static source scan --
## no MainScene.tscn boot required.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_wires_round_flow_controller_and_connects_round_over_for_ui_cleanup_only() -> void:
	var source: String = FileAccess.get_file_as_string(MAIN_SCENE_SCRIPT_PATH)

	assert_true(
		source.contains("RoundFlowControllerClass") or source.contains("round_flow_controller.gd"),
		"MainScene.gd must construct/wire the extracted RoundFlowController"
	)
	assert_true(
		source.contains("round_flow_controller.setup("),
		"MainScene.gd must call round_flow_controller.setup(deps) as part of composition-root wiring"
	)

	var connect_marker: String = "round_flow_controller.round_over.connect("
	var connect_at: int = source.find(connect_marker)
	assert_true(connect_at >= 0, "MainScene.gd must connect a handler to round_flow_controller's own round_over() signal")

	# Extract the connected handler's own name out of `...connect(_on_xyz)`.
	var args_start: int = connect_at + connect_marker.length()
	var args_end: int = source.find(")", args_start)
	var handler_name: String = source.substr(args_start, args_end - args_start).strip_edges()

	var handler_decl: String = "func %s(" % handler_name
	var handler_start: int = source.find(handler_decl)
	assert_true(handler_start >= 0, "the handler connected to round_flow_controller.round_over ('%s') must be a real, defined function on MainScene" % handler_name)

	var handler_end: int = source.find("\nfunc ", handler_start + 1)
	if handler_end < 0:
		handler_end = source.length()
	var handler_body: String = source.substr(handler_start, handler_end - handler_start)

	# Trim any trailing blank lines + "##" doc-comment block belonging to the
	# NEXT function (source.find("\nfunc ") above stops at the next real
	# `func` keyword, but this project's convention documents every function
	# with a multi-line "##" doc block immediately ABOVE it -- that doc block
	# would otherwise be swept into THIS handler's own body and could
	# false-positive against the forbidden markers below via unrelated prose).
	var body_lines: PackedStringArray = handler_body.split("\n")
	var last_code_line_index: int = 0
	for i in range(body_lines.size()):
		var stripped: String = body_lines[i].strip_edges()
		if stripped != "" and not stripped.begins_with("#"):
			last_code_line_index = i
	var trimmed_lines: PackedStringArray = []
	for i in range(last_code_line_index + 1):
		trimmed_lines.append(body_lines[i])
	handler_body = "\n".join(trimmed_lines)

	var forbidden_game_state_mutations: Array = [
		"ROUND_NUMBER",
		"round_session =",
		"run_round_use_case.begin_round(",
		"rewire_session()",
		"_game_mode =",
		"_active_encounter_id =",
		"scenario_session",
	]
	for marker in forbidden_game_state_mutations:
		assert_false(
			handler_body.contains(marker),
			"the handler connected to round_flow_controller.round_over ('%s') must perform UI cleanup ONLY -- it must never reference '%s' (game-state mutation belongs solely to MainScene's own pinned rewire_session()/_on_round_over())" % [handler_name, marker]
		)


func test_main_scenes_own_on_round_over_notifies_round_flow_controller_for_live_parity() -> void:
	var source: String = FileAccess.get_file_as_string(MAIN_SCENE_SCRIPT_PATH)

	var on_round_over_start: int = source.find("func _on_round_over(")
	assert_true(on_round_over_start >= 0, "MainScene must still define its own pre-existing, pinned _on_round_over()")
	var on_round_over_end: int = source.find("\nfunc ", on_round_over_start + 1)
	var on_round_over_body: String = source.substr(on_round_over_start, on_round_over_end - on_round_over_start)

	assert_true(
		on_round_over_body.contains("round_flow_controller.notify_round_concluded("),
		"MainScene's own _on_round_over() must relay round conclusions to round_flow_controller via the safe notify_round_concluded() helper, so round_over() fires for real gameplay too"
	)
