extends GutTest
## tests/gut/test_combine_queue_build_session.gd — FEAT-004 (US-003; FR-003;
## ADR-005).
##
## GUT suite for presentation/combine_queue_build_session.gd's
## CombineQueueBuildSession — the extracted interactive Combine
## QUEUE-BUILD pick-loop state machine (formerly MainScene.gd's own
## `_combine_build_*` fields / `_start_combine_queue_build()` /
## `_enter_combine_build_pick()` / `_on_combine_build_option_chosen()` /
## `_advance_combine_build()` / `_abort_combine_build()` /
## `_reset_combine_build_state()`).
##
## Drives the session purely through its own public setup(deps)/start(actor)/
## abort()/advance() surface plus a REAL presentation/selection_overlay.gd
## instance (UNCHANGED, exactly like the production wiring MainScene.gd
## performs) — no MainScene.tscn boot is required for this suite, mirroring
## tests/gut/test_presentation_adapters.gd's own "construct the real
## collaborator + a fake port, no scene boot" convention.
##
## test_criteria covered:
##   1. test_start_while_already_building_emits_aborted_and_does_not_overwrite_state()
##   2. test_successful_build_emits_queue_built_with_correct_entries()
##   3. test_main_scene_no_longer_declares_combine_build_state_or_functions()
##   4. (full-suite regression is verified by running the whole GUT suite,
##      not scoped to this file)

const CombineQueueBuildSessionClass = preload("res://presentation/combine_queue_build_session.gd")
const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeDescriptor — duck-typed SelectionDescriptor stand-in (ok/
## candidate_options/candidate_hexes/candidate_targets), mirroring
## core/application/selection_descriptor.gd's shape without constructing a
## real one.
class FakeDescriptor:
	extends RefCounted

	var ok: bool
	var candidate_options: Array
	var candidate_hexes: Array = []
	var candidate_targets: Array = []

	func _init(p_ok: bool, p_candidate_options: Array) -> void:
		ok = p_ok
		candidate_options = p_candidate_options

	# Deliberately no custom get(key) override here: selection_overlay.gd's
	# own _extract()/_extract_options() call `selection.get(key)` on any
	# non-Dictionary descriptor, which resolves through Object's BUILT-IN
	# get(property: StringName) -> Variant (reading this class's own
	# candidate_options/candidate_hexes/candidate_targets vars by name) --
	# overriding it here would collide with that built-in virtual's parent
	# signature (Godot 4.3 parse error: "signature doesn't match the
	# parent").


## FakeCombineActionController — duck-typed
## `enter_selection(payload) -> descriptor` collaborator, mirroring
## core/controllers/combine_action_controller.gd's BuildVerbQueueUseCase-
## backed contract: offers STRIDE/STRIKE always, Confirm once
## CombineQueue.meets_confirm_minimum() is met, Cancel once at least one
## verb is already queued. `fail_at_queue_size`, when >= 0, makes the NEXT
## call at that queue size return a failed (ok:false) descriptor instead —
## used to exercise the abort-on-failed-descriptor path.
class FakeCombineActionController:
	extends RefCounted

	var enter_selection_calls: Array = []
	var fail_at_queue_size: int = -1

	func enter_selection(payload: Dictionary):
		enter_selection_calls.append(payload)
		var queue_size: int = payload.get("queue", []).size()
		if fail_at_queue_size >= 0 and queue_size == fail_at_queue_size:
			return FakeDescriptor.new(false, [])
		var options: Array = [
			{"id": "STRIDE", "label": "Stride", "kind": "VERB"},
			{"id": "STRIKE", "label": "Strike", "kind": "VERB"},
		]
		if CombineQueueClass.meets_confirm_minimum(CombineQueueClass.Context.TURN, queue_size):
			options.append({"id": BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID, "label": "Confirm", "kind": "CONFIRM"})
		if queue_size > 0:
			options.append({"id": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID, "label": "Cancel", "kind": "CANCEL"})
		return FakeDescriptor.new(true, options)


## FakeActor — minimal duck-typed Combatant stand-in (display_id() only,
## the sole member CombineQueueBuildSession.start() reads off it).
class FakeActor:
	extends RefCounted

	var _id: String

	func _init(id: String) -> void:
		_id = id

	func display_id() -> String:
		return _id


# ══════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════

func _find_option(options: Array, id: String):
	for option in options:
		if option.get("id") == id:
			return option
	return null


## _make_session(combine_action_controller) -> Dictionary — wires a fresh
## CombineQueueBuildSession over a REAL SelectionOverlay instance (no
## hex_grid_view -- every path this suite drives is Layer-2a option-only,
## which never dereferences hex_grid_view) plus a standalone `_verb_registry`
## stand-in selection_overlay is switched back to on every terminal path
## (mirrors MainScene.gd's own `_reset_combine_build_state()` guarantee).
##
## Deliberately does NOT connect selection_overlay.selection_resolved to
## session.advance() itself -- MainScene.gd (a Node, immune to RefCounted
## reference cycles) owns that wiring in production
## (`_on_selection_overlay_resolved()`); a persistent closure connected here
## would capture `session` inside `overlay`'s own signal connection list
## while `session` itself holds `overlay` (`_selection_overlay`) as a field
## -- a reference cycle neither GUT's test teardown nor Godot's refcounting
## can ever collect. `_pick()` below instead calls session.advance()
## explicitly, immediately after choose_option() -- the exact same
## synchronous ordering `_on_selection_overlay_resolved()` produces in
## production (selection_resolved fires synchronously from inside
## choose_option()'s own _resolve() call, before choose_option() returns).
func _make_session(combine_action_controller) -> Dictionary:
	var overlay := SelectionOverlayClass.new()
	var standalone_registry = RefCounted.new()
	var session := CombineQueueBuildSessionClass.new()
	session.setup({
		"combine_action_controller": combine_action_controller,
		"selection_overlay": overlay,
		"hex_grid_view": null,
		"verb_registry": standalone_registry,
	})
	return {"session": session, "overlay": overlay, "verb_registry": standalone_registry}


func _pick(session, overlay, option_id: String) -> void:
	var option = _find_option(overlay.get_candidate_options(), option_id)
	assert_not_null(option, "fixture assumption: option '%s' must be legally offered at this pick" % option_id)
	overlay.choose_option(option)
	if session.is_active():
		session.advance()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- start(actor) called while already building emits aborted()
# rather than overwriting state (per API contract).
# ══════════════════════════════════════════════════════════════════════════

func test_start_while_already_building_emits_aborted_and_does_not_overwrite_state() -> void:
	var rig := _make_session(FakeCombineActionController.new())
	var session = rig["session"]

	var first_actor := FakeActor.new("titus")
	session.start(first_actor)
	assert_true(session.is_active(), "fixture assumption: the first start() call must engage the build loop")
	var in_progress_queue = session.get_queue()
	assert_not_null(in_progress_queue, "fixture assumption: an active build must carry a real in-progress CombineQueue")

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))
	session.queue_built.connect(func(_q): fail_test("queue_built must never fire for an illegal re-entrant start() call"))

	var second_actor := FakeActor.new("someone_else")
	session.start(second_actor)

	assert_eq(abort_signals.size(), 1, "a start() call while already building must emit aborted() exactly once")
	assert_true(session.is_active(), "the ORIGINAL in-progress build must remain active -- illegal start() must never tear it down")
	assert_eq(session.get_queue(), in_progress_queue, "the ORIGINAL in-progress CombineQueue instance must be untouched (same identity)")
	assert_eq(session.get_actor(), first_actor, "the ORIGINAL actor must remain recorded -- the second start() call's actor must never overwrite it")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- a successful build emits queue_built(queue) with correct
# CombineQueueEntry (VerbQueueEntry) contents.
# ══════════════════════════════════════════════════════════════════════════

func test_successful_build_emits_queue_built_with_correct_entries() -> void:
	var rig := _make_session(FakeCombineActionController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	var built_queues: Array = []
	session.queue_built.connect(func(q): built_queues.append(q))
	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	var actor := FakeActor.new("titus")
	session.start(actor)

	assert_true(overlay.is_awaiting_option(), "the first pick must be a Layer-2a option pick")
	_pick(session, overlay, "STRIDE")
	assert_true(session.is_active(), "the loop must still be active after one pick (queue length 1 < TURN minimum)")

	_pick(session, overlay, "STRIKE")
	assert_true(session.is_active(), "the loop must still be active -- the player has not yet confirmed")

	_pick(session, overlay, BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID)

	assert_eq(abort_signals.size(), 0, "a successful Confirm must never emit aborted()")
	assert_eq(built_queues.size(), 1, "a successful Confirm must emit queue_built() exactly once")
	assert_false(session.is_active(), "the build loop must be torn down once Confirm succeeds")
	assert_null(session.get_queue(), "the terminal state must not retain the confirmed queue as the in-progress one")

	var queue = built_queues[0]
	assert_eq(queue.status, CombineQueueClass.Status.CONFIRMED, "the emitted queue must be CONFIRMED")
	assert_eq(queue.actor_id, "titus")
	assert_eq(queue.context, CombineQueueClass.Context.TURN)

	var entries: Array = queue.sorted_entries()
	assert_eq(entries.size(), 2, "exactly the two picked verbs (STRIDE, STRIKE) must be recorded, never the sentinel picks")
	assert_eq(entries[0].verb_id, "STRIDE")
	assert_eq(entries[0].order_index, 0)
	assert_eq(entries[0].queue_id, queue.queue_id)
	assert_eq(entries[1].verb_id, "STRIKE")
	assert_eq(entries[1].order_index, 1)
	assert_eq(entries[1].queue_id, queue.queue_id)

	# selection_overlay must be switched back to the standalone verb_registry
	# stand-in -- the SAME "reset back to Layer 1" guarantee
	# _reset_combine_build_state() previously provided.
	assert_false(overlay.is_active(), "selection_overlay must have returned to Layer 1 (no Layer 2 selection active)")


# ══════════════════════════════════════════════════════════════════════════
# Supporting regression coverage -- mirrors the pre-extraction behavior this
# feature must preserve byte-for-byte (Cancel sentinel, failed descriptor,
# null combine_action_controller, explicit abort()).
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_sentinel_tears_down_the_loop_and_emits_aborted_with_no_partial_state() -> void:
	var rig := _make_session(FakeCombineActionController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))
	session.queue_built.connect(func(_q): fail_test("queue_built must never fire on a cancelled build"))

	session.start(FakeActor.new("titus"))
	_pick(session, overlay, "STRIDE")

	var mid_build_ids: Array = []
	for option in overlay.get_candidate_options():
		mid_build_ids.append(option.get("id"))
	assert_true(mid_build_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress build must offer the Cancel sentinel")

	_pick(session, overlay, CancelCombineUseCaseClass.CANCEL_SENTINEL_ID)

	assert_eq(abort_signals.size(), 1)
	assert_false(session.is_active(), "cancelling must tear down the build loop")
	assert_null(session.get_queue(), "cancelling must discard the in-progress CombineQueue -- no partial-state leak")
	assert_eq(session.get_pending_option(), {}, "cancelling must clear any pending option")
	assert_false(overlay.is_active(), "cancelling must return selection_overlay to Layer 1")


func test_failed_descriptor_aborts_the_build() -> void:
	var controller := FakeCombineActionController.new()
	controller.fail_at_queue_size = 0
	var rig := _make_session(controller)
	var session = rig["session"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start(FakeActor.new("titus"))

	assert_eq(abort_signals.size(), 1, "a failed/ok:false first descriptor must abort the build immediately")
	assert_false(session.is_active())
	assert_null(session.get_queue())


func test_null_combine_action_controller_aborts_the_build_without_crashing() -> void:
	var rig := _make_session(null)
	var session = rig["session"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start(FakeActor.new("titus"))

	assert_eq(abort_signals.size(), 1, "a null combine_action_controller must degrade safely to aborted(), never a crash")
	assert_false(session.is_active())


func test_explicit_abort_tears_down_an_in_progress_build() -> void:
	var rig := _make_session(FakeCombineActionController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start(FakeActor.new("titus"))
	assert_true(session.is_active())

	session.abort()

	assert_eq(abort_signals.size(), 1)
	assert_false(session.is_active())
	assert_null(session.get_queue())
	assert_false(overlay.is_active(), "abort() must return selection_overlay to Layer 1")


func test_stride_remains_offered_after_being_picked_once_repeat_true() -> void:
	# Regression: STRIDE (Repeat=true) must remain a legal next pick after
	# being chosen once, enabling STRIDE+STRIDE combinations -- the fake
	# controller always offers it, but this pins down that the session never
	# filters it out itself (that is BuildVerbQueueUseCase's job alone).
	var rig := _make_session(FakeCombineActionController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	session.start(FakeActor.new("titus"))
	_pick(session, overlay, "STRIDE")

	var ids: Array = []
	for option in overlay.get_candidate_options():
		ids.append(option.get("id"))
	assert_true(ids.has("STRIDE"), "STRIDE must remain offered after being picked once")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- static source scan: MainScene.gd no longer declares any
# `_combine_build_*` var/function (this feature's own test_criteria).
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_no_longer_declares_combine_build_state_or_functions() -> void:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable as plain source text for this static scan")
	var source: String = file.get_as_text()
	file.close()

	var forbidden_markers: Array = [
		"_combine_build_active",
		"_combine_build_queue",
		"_combine_build_actor",
		"_combine_build_context",
		"_combine_build_pending_option",
		"_combine_build_registry_proxy",
		"_start_combine_queue_build",
		"_enter_combine_build_pick",
		"_on_combine_build_option_chosen",
		"_advance_combine_build",
		"_abort_combine_build",
		"_reset_combine_build_state",
	]
	for marker in forbidden_markers:
		assert_false(
			source.contains(marker),
			"MainScene.gd must no longer reference '%s' -- the interactive queue-build loop now lives entirely in presentation/combine_queue_build_session.gd (FEAT-004)" % marker
		)

	assert_true(source.contains("CombineQueueBuildSession") or source.contains("combine_queue_build_session.gd"), "MainScene.gd must wire the extracted CombineQueueBuildSession class")
