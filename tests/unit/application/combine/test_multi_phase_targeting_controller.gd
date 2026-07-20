extends GutTest
## tests/unit/application/combine/test_multi_phase_targeting_controller.gd
##
## GUT suite for FEAT-005 (Iteration O "Combine Selection UX"; US-005;
## FR-004/FR-013; NFR-002/NFR-003; ADR-002): core/application/combine/
## multi_phase_targeting_controller.gd's MultiPhaseTargetingController.
##
## Runs entirely against INJECTED FAKES (FakeVerbController,
## FakeFailingVerbController, FakeCombineActionController, all defined
## below) — this suite never touches MainScene, SelectionOverlay, or any
## other engine/presentation type, satisfying this feature's own
## test_criteria: "MultiPhaseTargetingController unit tests run in
## isolation from MainScene using injected fakes."
##
## Verifies (test_criteria):
##   1. A 2-entry queue [STRIDE, STRIKE] drives exactly two
##      enter_selection() calls, in order_index order.
##   2. A 3-entry queue drives exactly three enter_selection() calls, via
##      the SAME code path a 2-entry queue takes (parameterized test over
##      queue length 2 and 3 — no hard-coded phase-count branching).
##   3. The accumulated map is populated keyed by verb_id after each phase
##      resolves.
##   4. On exhaustion of the loop, the controller invokes
##      CombineActionController.execute() exactly once — and NEVER when a
##      phase aborts mid-loop.
##   5. ADR-002 contract check: every registered fake controller exposes
##      both enter_selection() and execute().
##   6. FEAT-008 (US-008; FR-006): a resolved_selections entry equal to
##      CancelCombineUseCase.CANCEL_SENTINEL_ID at ANY phase (order_index 0
##      or order_index 1) aborts the WHOLE Combine -- that phase's own
##      enter_selection() is never called, no later phase is reached,
##      CombineActionController.execute() is never invoked, an injected
##      CombineQueue aggregate's status is transitioned to CANCELLED, and
##      `accumulated` is always returned wholesale-empty.

const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const VerbControllerPortClass = preload("res://core/application/combine/verb_controller_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const ConfirmQueueUseCaseClass = preload("res://core/application/combine/confirm_queue_use_case.gd")


## FakeVerbController — a minimal VerbControllerPort implementation
## (extends the real port, satisfying ADR-002's contract by construction)
## that records every enter_selection() call it receives (both on its own
## `calls` Array and, when given one, on a `shared_log` Array common to
## every fake in a test — the sole mechanism this suite uses to assert
## cross-controller call ORDER) and returns an already-"resolved" canned
## SelectionDescriptor carrying `chosen_value` in its `meta`.
class FakeVerbController:
	extends "res://core/application/combine/verb_controller_port.gd"

	var verb_id: String
	var chosen_value
	var calls: Array = []
	var shared_log: Array

	func _init(p_verb_id: String, p_chosen_value = null, p_shared_log: Array = []) -> void:
		verb_id = p_verb_id
		chosen_value = p_chosen_value
		shared_log = p_shared_log

	func enter_selection(context: Dictionary) -> Object:
		calls.append(context)
		shared_log.append(verb_id)
		return SelectionDescriptorScript.new(true, [], [], [], context.get("order_index", 0), {"chosen_value": chosen_value})

	func execute(_payload: Dictionary) -> Dictionary:
		return {"ok": true, "error_code": "", "actions_spent": 0, "stamina_spent": 0, "resolution_log": []}


## FakeFailingVerbController — a VerbControllerPort whose enter_selection()
## always reports failure (ok:false, NO_LEGAL_OPTIONS), exercising this
## controller's mid-loop abort path (design notes' error_handling: "a
## failed targeting phase leaves zero committed game-state changes").
class FakeFailingVerbController:
	extends "res://core/application/combine/verb_controller_port.gd"

	var calls: int = 0

	func enter_selection(_context: Dictionary) -> Object:
		calls += 1
		return SelectionDescriptorScript.new(false, [], [], [], 0, {"error_code": "NO_LEGAL_OPTIONS"})

	func execute(_payload: Dictionary) -> Dictionary:
		return {"ok": false, "error_code": "NO_LEGAL_OPTIONS", "actions_spent": 0, "stamina_spent": 0, "resolution_log": []}


## FakeCombineActionController — records every execute() call (payload
## included) it receives, standing in for core/controllers/
## combine_action_controller.gd's CombineActionController per this
## feature's own test_criteria #4 ("invokes CombineActionController.execute()
## exactly once").
class FakeCombineActionController:
	var execute_calls: Array = []

	func execute(payload: Dictionary) -> Dictionary:
		execute_calls.append(payload)
		return {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}


func _entries(verb_ids: Array) -> Array:
	var entries: Array = []
	for i in range(verb_ids.size()):
		entries.append(VerbQueueEntryClass.new("q1", i, verb_ids[i]))
	return entries


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a 2-entry queue drives exactly two enter_selection() calls,
# in order_index order.
# ══════════════════════════════════════════════════════════════════════════

func test_two_entry_queue_drives_two_enter_selection_calls_in_order() -> void:
	var log: Array = []
	var stride := FakeVerbController.new("STRIDE", "hex_1", log)
	var strike := FakeVerbController.new("STRIKE", "target_1", log)
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	assert_true(result.get("ok", false), "a fully-resolved 2-entry queue must report ok:true")
	assert_eq(stride.calls.size(), 1, "STRIDE's enter_selection() must be called exactly once")
	assert_eq(strike.calls.size(), 1, "STRIKE's enter_selection() must be called exactly once")
	assert_eq(log, ["STRIDE", "STRIKE"], "phases must be driven in order_index order (STRIDE=0 before STRIKE=1)")
	assert_eq(stride.calls[0].get("order_index"), 0)
	assert_eq(strike.calls[0].get("order_index"), 1)


func test_two_entry_queue_out_of_insertion_order_still_drives_in_order_index_order() -> void:
	# Entries appended in REVERSE order_index order — sorted_entries()-style
	# ordering (order_index, never array position) must still win.
	var log: Array = []
	var stride := FakeVerbController.new("STRIDE", "hex_1", log)
	var strike := FakeVerbController.new("STRIKE", "target_1", log)
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var entries: Array = [VerbQueueEntryClass.new("q1", 1, "STRIKE"), VerbQueueEntryClass.new("q1", 0, "STRIDE")]

	controller.execute(entries, "actor_0")

	assert_eq(log, ["STRIDE", "STRIKE"], "order_index, not insertion order, must be authoritative")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a 3-entry queue drives exactly three enter_selection()
# calls, via the SAME code path a 2-entry queue takes (parameterized,
# proving there is no hard-coded phase-count branching).
# ══════════════════════════════════════════════════════════════════════════

func test_queue_of_n_entries_drives_exactly_n_enter_selection_calls(entry_count = use_parameters([2, 3])) -> void:
	var verb_ids: Array = []
	for i in range(entry_count):
		verb_ids.append("VERB_%d" % i)

	var log: Array = []
	var registry: Dictionary = {}
	for verb_id in verb_ids:
		registry[verb_id] = FakeVerbController.new(verb_id, "%s_value" % verb_id, log)
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": registry,
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(_entries(verb_ids), "actor_0")

	assert_true(result.get("ok", false))
	assert_eq(log.size(), entry_count, "exactly one enter_selection() call per queued entry, regardless of queue length")
	assert_eq(log, verb_ids, "call order must match order_index order for ANY queue length")
	assert_eq(combine_action_controller.execute_calls.size(), 1, "loop exhaustion must invoke execute() exactly once, at any queue length")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — accumulated map is populated keyed by verb_id after each
# phase resolves.
# ══════════════════════════════════════════════════════════════════════════

func test_accumulated_map_populated_keyed_by_verb_id() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})

	var result: Dictionary = controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	var accumulated: Dictionary = result.get("accumulated", {})
	assert_true(accumulated.has("STRIDE"), "accumulated must be keyed by verb_id")
	assert_true(accumulated.has("STRIKE"), "accumulated must be keyed by verb_id")
	assert_eq(accumulated["STRIDE"].meta.get("chosen_value"), "hex_1", "accumulated[verb_id] must carry that phase's own resolved SelectionDescriptor")
	assert_eq(accumulated["STRIKE"].meta.get("chosen_value"), "target_1")


func test_later_phase_receives_earlier_phases_accumulated_selections() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})

	controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	var strike_context: Dictionary = strike.calls[0]
	var accumulated_seen_by_strike: Dictionary = strike_context.get("accumulated", {})
	assert_true(accumulated_seen_by_strike.has("STRIDE"), "STRIKE's own enter_selection() must see STRIDE's already-resolved accumulated entry")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — on exhaustion, CombineActionController.execute() is invoked
# exactly once; a mid-loop failure must NEVER reach it.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_invoked_exactly_once_on_exhaustion() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	assert_eq(combine_action_controller.execute_calls.size(), 1, "loop exhaustion must invoke CombineActionController.execute() exactly once")
	assert_eq(result.get("execution_result", {}).get("ok"), true)


func test_execute_never_invoked_when_a_phase_fails() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var failing_strike := FakeFailingVerbController.new()
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": failing_strike},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	assert_false(result.get("ok", true), "a mid-loop failure must report ok:false")
	assert_eq(result.get("error_code", ""), "NO_LEGAL_OPTIONS")
	assert_eq(failing_strike.calls, 1, "the failing phase's own enter_selection() must still be called exactly once")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "a failed phase must abort BEFORE CombineActionController.execute() is ever reached")
	assert_true(result.get("accumulated", {}).has("STRIDE"), "phases that resolved before the failure must still be accumulated")
	assert_false(result.get("accumulated", {}).has("STRIKE"), "the failed phase itself must NOT be accumulated")


func test_unregistered_verb_id_aborts_before_dispatch_and_before_execute() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(_entries(["STRIDE", "STRIKE"]), "actor_0")

	assert_false(result.get("ok", true))
	assert_eq(result.get("error_code", ""), "UNREGISTERED_VERB")
	assert_eq(combine_action_controller.execute_calls.size(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — ADR-002 contract check: registered controllers expose both
# enter_selection and execute.
# ══════════════════════════════════════════════════════════════════════════

func test_fake_controllers_satisfy_adr002_contract() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var failing := FakeFailingVerbController.new()

	assert_true(stride.has_method("enter_selection"), "ADR-002: a registered controller must expose enter_selection()")
	assert_true(stride.has_method("execute"), "ADR-002: a registered controller must expose execute()")
	assert_true(failing.has_method("enter_selection"), "ADR-002: a registered controller must expose enter_selection()")
	assert_true(failing.has_method("execute"), "ADR-002: a registered controller must expose execute()")
	assert_true(stride is VerbControllerPortClass, "FakeVerbController must satisfy the VerbControllerPort contract")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 (FEAT-008; US-008; FR-006) — CANCEL_SENTINEL_ID at any phase
# aborts the WHOLE Combine, not just the current phase.
# ══════════════════════════════════════════════════════════════════════════

func _queue_with_entries(entry_count: int) -> CombineQueueClass:
	var queue := CombineQueueClass.new("q1", "player_0", CombineQueueClass.Context.TURN)
	for i in range(entry_count):
		queue.add_entry(VerbQueueEntryClass.new("q1", i, ["STRIDE", "STRIKE"][i]))
	return queue


func test_cancel_at_order_index_0_aborts_before_any_phase_is_dispatched() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(
		_entries(["STRIDE", "STRIKE"]), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}
	)

	assert_false(result.get("ok", true), "a CANCEL_SENTINEL_ID at order_index 0 must report ok:false")
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(stride.calls.size(), 0, "the cancelled phase's own enter_selection() must never be called")
	assert_eq(strike.calls.size(), 0, "a LATER phase must never be reached once cancellation short-circuits the loop")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "cancellation must abort BEFORE CombineActionController.execute() is ever reached")
	assert_eq(result.get("accumulated", {}), {}, "accumulated must be wholesale-empty on cancellation")


func test_cancel_at_order_index_1_aborts_the_whole_combine_after_stride_already_resolved() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var combine_action_controller := FakeCombineActionController.new()
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": combine_action_controller,
	})

	var result: Dictionary = controller.execute(
		_entries(["STRIDE", "STRIKE"]), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}
	)

	assert_false(result.get("ok", true), "a CANCEL_SENTINEL_ID at order_index 1 must report ok:false")
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(stride.calls.size(), 1, "an EARLIER phase must still resolve normally before the cancelled phase is reached")
	assert_eq(strike.calls.size(), 0, "the cancelled phase's own enter_selection() must never be called")
	assert_eq(combine_action_controller.execute_calls.size(), 0, "cancellation must abort BEFORE CombineActionController.execute() is ever reached")
	assert_eq(result.get("accumulated", {}), {}, "accumulated must be wholesale-discarded, even though STRIDE had already resolved")


func test_cancel_transitions_an_injected_combine_queue_to_cancelled() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var strike := FakeVerbController.new("STRIKE", "target_1")
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride, "STRIKE": strike},
		"combine_action_controller": FakeCombineActionController.new(),
	})
	var queue := _queue_with_entries(2)
	queue.status = CombineQueueClass.Status.CONFIRMED

	controller.execute(
		_entries(["STRIDE", "STRIKE"]), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, queue
	)

	assert_eq(queue.status, CombineQueueClass.Status.CANCELLED, "an injected CombineQueue aggregate must be transitioned to CANCELLED on cancellation")

	var confirm_result: Dictionary = ConfirmQueueUseCaseClass.new().execute(queue)
	assert_false(confirm_result.get("ok", true), "a cancelled CombineQueue must never be reusable by a later ConfirmQueueUseCase call")
	assert_eq(confirm_result.get("error_code", ""), "INVALID_QUEUE_STATE")


func test_cancel_with_no_injected_combine_queue_still_aborts_safely() -> void:
	var stride := FakeVerbController.new("STRIDE", "hex_1")
	var controller := MultiPhaseTargetingControllerClass.new({
		"controller_registry": {"STRIDE": stride},
		"combine_action_controller": FakeCombineActionController.new(),
	})

	var result: Dictionary = controller.execute(
		_entries(["STRIDE"]), "actor_0", CombineQueueClass.Context.TURN,
		{"STRIDE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}
	)

	assert_false(result.get("ok", true), "cancellation with no injected CombineQueue must still degrade safely, never crash")
	assert_eq(result.get("error_code", ""), "CANCELLED")
