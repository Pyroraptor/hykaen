extends GutTest
## tests/gut/test_combine_targeting_session.gd — FEAT-005 (US-004; FR-004;
## ADR-003).
##
## GUT suite for presentation/combine_targeting_session.gd's
## CombineTargetingSession — the extracted interactive Combine sub-action
## TARGETING pick-loop state machine (formerly MainScene.gd's own
## `_combine_targeting_*` fields / `start_combine_targeting()` /
## `_enter_combine_targeting_phase()` / `_on_combine_targeting_value_chosen()`
## / `_advance_combine_targeting_phase()` / `_finish_combine_targeting()` /
## `_abort_combine_targeting()` / `_reset_combine_targeting_state()` /
## `_combine_verb_id_of()` / `_combine_order_index_of()`).
##
## Drives the session purely through its own public setup(deps)/
## start(queue_entries, actor, context, combine_queue)/abort()/
## try_advance(verb_id) surface plus a REAL presentation/selection_overlay.gd
## instance (UNCHANGED, exactly like the production wiring MainScene.gd
## performs) — no MainScene.tscn boot is required for this suite, mirroring
## tests/gut/test_combine_queue_build_session.gd's own "construct the real
## collaborator + fakes, no scene boot" convention. The wrapped
## MultiPhaseTargetingController is ALSO injected as a fake (spy) here, so
## this suite can assert precisely on the delegation contract (test_criteria
## #3) without depending on the real controller's own internals (those are
## covered by tests/unit/application/combine/test_multi_phase_targeting_controller.gd).
##
## test_criteria covered:
##   1. Diff/hash check confirms
##      core/application/combine/multi_phase_targeting_controller.gd is
##      byte-for-byte unchanged after extraction (RISK-002).
##   2. targeting_complete(result) emitted on successful N-phase resolution;
##      aborted() emitted on cancel, invalid phase count, or no valid
##      candidates from the wrapped controller.
##   3. No domain/phase-evaluation logic is duplicated inside
##      CombineTargetingSession — only delegation calls to the injected
##      MultiPhaseTargetingController (and to the injected per-verb
##      VerbControllerPort collaborators, exactly like the wrapped
##      controller's own registry).
##   4. (verified in the MainScene.gd suite context, restated here via
##      static scan): `_combine_targeting_*` vars/functions no longer
##      present in MainScene.gd.

const CombineTargetingSessionClass = preload("res://presentation/combine_targeting_session.gd")
const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const VerbControllerPortClass = preload("res://core/application/combine/verb_controller_port.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"
const COMBINE_TARGETING_SESSION_SCRIPT_PATH: String = "res://presentation/combine_targeting_session.gd"
const MULTI_PHASE_TARGETING_CONTROLLER_PATH: String = "res://core/application/combine/multi_phase_targeting_controller.gd"

## PINNED_MULTI_PHASE_TARGETING_CONTROLLER_SHA256 — RISK-002's own explicit
## mitigation (this feature's test_criteria): a SHA-256 digest of
## core/application/combine/multi_phase_targeting_controller.gd's own file
## content, computed from the file exactly as it stood immediately before
## this feature's work began (this feature's files_to_create/files_to_modify
## list names ONLY presentation/combine_targeting_session.gd, this test
## file, and MainScene.gd — never the wrapped controller itself). A future
## change that edits multi_phase_targeting_controller.gd for ANY reason will
## flip this file's live hash away from this pinned value, failing
## test_wrapped_multi_phase_targeting_controller_source_has_zero_diff_from_pinned_baseline
## below — mirrors tests/regression/combine/test_selection_overlay_unmodified.gd's
## own established "pin a known-good snapshot, diff the live artifact
## against it" convention.
const PINNED_MULTI_PHASE_TARGETING_CONTROLLER_SHA256: String = "2405ca21c9c5b2956847a3397abb81971a236faeb543ebf614e40f5aa52c9fd3"


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeInteractiveVerbController — a VerbControllerPort implementation
## (extends the real port, ADR-002) mirroring core/controllers/
## stride_action_controller.gd's/strike_action_controller.gd's own
## two-call-shape contract: an OFFER call (no `selected_hex` in context)
## returns a Layer-2a option descriptor naming ITS OWN `option_id`; a
## RESOLUTION call (context carries `selected_hex`, threaded on by
## CombineTargetingSession's own `_on_combine_targeting_value_chosen()`)
## returns a resolved descriptor carrying the chosen value in `meta`.
class FakeInteractiveVerbController:
	extends "res://core/application/combine/verb_controller_port.gd"

	var verb_id: String
	var option_id: String
	var fail_offer: bool = false
	var offer_calls: Array = []
	var resolve_calls: Array = []

	func _init(p_verb_id: String, p_option_id: String) -> void:
		verb_id = p_verb_id
		option_id = p_option_id

	func enter_selection(context: Dictionary) -> Object:
		if context.has("selected_hex"):
			resolve_calls.append(context)
			return SelectionDescriptorScript.new(true, [], [], [], context.get("order_index", 0), {"chosen_value": context["selected_hex"]})
		offer_calls.append(context)
		if fail_offer:
			return SelectionDescriptorScript.new(false, [], [], [], context.get("order_index", 0), {"error_code": "NO_LEGAL_OPTIONS"})
		return SelectionDescriptorScript.new(
			true, [{"id": option_id, "label": option_id, "kind": "TARGET"}], [], [], context.get("order_index", 0), {}
		)

	func execute(_payload: Dictionary) -> Dictionary:
		return {"ok": true, "error_code": "", "actions_spent": 0, "stamina_spent": 0, "resolution_log": []}


## FakeTargetingController — spy standing in for the wrapped, UNCHANGED
## MultiPhaseTargetingController (RISK-002). Records every execute() call
## verbatim (this suite's OWN mechanism for asserting the delegation
## contract — test_criteria #3) and hands back a pre-configured canned
## result, so CombineTargetingSession's own `get_result()`/
## `targeting_complete` payload can be asserted to be THAT EXACT object,
## proving this session never reinterprets/recomputes it.
class FakeTargetingController:
	extends RefCounted

	var execute_calls: Array = []
	var result_to_return: Dictionary = {
		"ok": true, "error_code": "", "accumulated": {}, "execution_result": {"ok": true, "resolution_log": []}
	}

	func execute(queue_entries: Array, actor, context: int, resolved_selections: Dictionary, combine_queue = null) -> Dictionary:
		execute_calls.append({
			"queue_entries": queue_entries,
			"actor": actor,
			"context": context,
			"resolved_selections": resolved_selections,
			"combine_queue": combine_queue,
		})
		return result_to_return


## FakeActor — minimal duck-typed Combatant stand-in.
class FakeActor:
	extends RefCounted

	var _id: String

	func _init(id: String) -> void:
		_id = id

	func display_id() -> String:
		return _id


## _SpellPickerTracker — records show_spell_picker_fn invocations.
class _SpellPickerTracker:
	extends RefCounted

	var calls: Array = []

	func show(options: Array) -> void:
		calls.append(options)


# ══════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════

func _find_option(options: Array, id: String):
	for option in options:
		if option.get("id") == id:
			return option
	return null


## _make_session(controller_registry, targeting_controller) -> Dictionary —
## wires a fresh CombineTargetingSession over a REAL SelectionOverlay
## instance (no hex_grid_view -- every path this suite drives is Layer-2a
## option-only, mirroring test_combine_queue_build_session.gd's identical
## rationale) plus a standalone `_verb_registry` stand-in selection_overlay
## is switched back to on every terminal path.
func _make_session(controller_registry: Dictionary, targeting_controller) -> Dictionary:
	var overlay := SelectionOverlayClass.new()
	var standalone_registry = RefCounted.new()
	var tracker := _SpellPickerTracker.new()
	var session := CombineTargetingSessionClass.new()
	session.setup({
		"controller_registry": controller_registry,
		"targeting_controller": targeting_controller,
		"selection_overlay": overlay,
		"hex_grid_view": null,
		"verb_registry": standalone_registry,
		"show_spell_picker_fn": Callable(tracker, "show"),
	})
	return {"session": session, "overlay": overlay, "verb_registry": standalone_registry, "tracker": tracker}


## _pick(session, overlay, verb_id, option_id) -> void — resolves the
## CURRENT phase's Layer-2a option pick (a real choose_option() call, the
## SAME call _on_spell_option_pressed() makes for a real click) and then
## drives try_advance() explicitly -- mirroring
## _on_selection_overlay_resolved()'s own production wiring. Deliberately
## does NOT connect selection_overlay.selection_resolved to
## session.try_advance() itself, for the SAME reference-cycle reason
## test_combine_queue_build_session.gd's own `_pick()` helper documents.
func _pick(session, overlay, verb_id: String, option_id: String) -> void:
	var option = _find_option(overlay.get_candidate_options(), option_id)
	assert_not_null(option, "fixture assumption: option '%s' must be legally offered at this phase" % option_id)
	overlay.choose_option(option)
	session.try_advance(verb_id)


func _entries(pairs: Array) -> Array:
	# pairs: Array of [order_index, verb_id]
	var entries: Array = []
	for pair in pairs:
		entries.append(VerbQueueEntryClass.new("q1", pair[0], pair[1]))
	return entries


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (RISK-002) — the wrapped MultiPhaseTargetingController source
# is byte-for-byte unchanged by this extraction.
# ══════════════════════════════════════════════════════════════════════════

func test_wrapped_multi_phase_targeting_controller_source_has_zero_diff_from_pinned_baseline() -> void:
	var file := FileAccess.open(MULTI_PHASE_TARGETING_CONTROLLER_PATH, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % MULTI_PHASE_TARGETING_CONTROLLER_PATH)
	var content: String = file.get_as_text()
	file.close()

	assert_eq(
		content.sha256_text(), PINNED_MULTI_PHASE_TARGETING_CONTROLLER_SHA256,
		"REGRESSION: core/application/combine/multi_phase_targeting_controller.gd must have ZERO diff relative to its pre-extraction pinned baseline -- any hash mismatch means this file was modified, violating RISK-002's 'wrap, never re-implement' guarantee"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2a — a successful 2-phase (STRIDE-then-STRIKE) run emits
# targeting_complete(result) with the wrapped controller's own result
# passed straight through, and delegates exactly once.
# ══════════════════════════════════════════════════════════════════════════

func test_two_phase_run_emits_targeting_complete_with_the_wrapped_controllers_own_result() -> void:
	var stride := FakeInteractiveVerbController.new("STRIDE", "hex_a")
	var strike := FakeInteractiveVerbController.new("STRIKE", "target_a")
	var targeting_controller := FakeTargetingController.new()
	var rig := _make_session({"STRIDE": stride, "STRIKE": strike}, targeting_controller)
	var session = rig["session"]
	var overlay = rig["overlay"]
	var tracker = rig["tracker"]

	var completed: Array = []
	session.targeting_complete.connect(func(result): completed.append(result))
	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	var actor := FakeActor.new("titus")
	var entries: Array = _entries([[0, "STRIDE"], [1, "STRIKE"]])
	var combine_queue = CombineQueueClass.new("q1", "titus", CombineQueueClass.Context.TURN)

	session.start(entries, actor, CombineQueueClass.Context.TURN, combine_queue)

	assert_true(session.is_active(), "the loop must engage after start()")
	assert_eq(overlay.get_active_verb_id(), "STRIDE", "the first phase (order_index 0) must be STRIDE")
	assert_true(overlay.is_awaiting_option())
	assert_eq(tracker.calls.size(), 1, "show_spell_picker_fn must be invoked for the first Layer-2a phase")

	_pick(session, overlay, "STRIDE", "hex_a")

	assert_true(session.is_active(), "the loop must still be active -- STRIKE's own phase has not resolved yet")
	assert_eq(overlay.get_active_verb_id(), "STRIKE", "the loop must advance into the STRIKE phase")
	assert_eq(session.get_resolved().keys(), ["STRIDE"], "only the STRIDE phase's chosen value must be recorded so far")
	assert_true(session.get_accumulated().has("STRIDE"), "the STRIDE phase's resolved descriptor must be accumulated")

	_pick(session, overlay, "STRIKE", "target_a")

	assert_false(session.is_active(), "the loop must have finished once both phases resolve")
	assert_false(overlay.is_active(), "selection_overlay must return to Layer 1 once Combine targeting completes")
	assert_eq(abort_signals.size(), 0, "a successful run must never emit aborted()")
	assert_eq(completed.size(), 1, "a successful run must emit targeting_complete() exactly once")
	assert_eq(completed[0], targeting_controller.result_to_return, "targeting_complete's payload must be the wrapped controller's own result, passed straight through")
	assert_eq(session.get_result(), targeting_controller.result_to_return, "get_result() must likewise be the wrapped controller's own result, unmodified")

	# ── Delegation contract (test_criteria #3): exactly ONE execute() call
	# on the wrapped controller, carrying the sorted entries / actor /
	# context / fully-populated resolved map / combine_queue verbatim. ──────
	assert_eq(targeting_controller.execute_calls.size(), 1, "the wrapped controller's execute() must be invoked exactly once, on loop exhaustion")
	var call: Dictionary = targeting_controller.execute_calls[0]
	assert_eq(call["actor"], actor)
	assert_eq(call["context"], CombineQueueClass.Context.TURN)
	assert_eq(call["combine_queue"], combine_queue)
	assert_eq(call["queue_entries"].size(), 2)
	assert_eq(call["queue_entries"][0].verb_id, "STRIDE")
	assert_eq(call["queue_entries"][1].verb_id, "STRIKE")
	assert_true(call["resolved_selections"].has("STRIDE") and call["resolved_selections"].has("STRIKE"), "both phases' chosen values must reach the wrapped controller")

	# The interactive loop's own state is fully torn down after finishing.
	assert_eq(session.get_resolved(), {}, "resolved-state must be cleared once the run finishes")
	assert_eq(session.get_accumulated(), {}, "accumulated-state must be cleared once the run finishes")
	assert_null(session.get_actor())
	assert_null(session.get_queue())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2b — entries handed to start() out of insertion order still
# drive phases in order_index order (authoritative, never array position).
# ══════════════════════════════════════════════════════════════════════════

func test_entries_out_of_insertion_order_still_drive_phases_in_order_index_order() -> void:
	var stride := FakeInteractiveVerbController.new("STRIDE", "hex_a")
	var strike := FakeInteractiveVerbController.new("STRIKE", "target_a")
	var rig := _make_session({"STRIDE": stride, "STRIKE": strike}, FakeTargetingController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	# STRIKE (order_index 1) appended BEFORE STRIDE (order_index 0).
	var entries: Array = _entries([[1, "STRIKE"], [0, "STRIDE"]])
	session.start(entries, FakeActor.new("titus"), CombineQueueClass.Context.TURN)

	assert_eq(overlay.get_active_verb_id(), "STRIDE", "order_index (not insertion order) must determine which phase is offered first")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2c — aborted() on cancel (explicit abort()), invalid phase
# count (empty queue_entries), and no valid candidates from the wrapped
# controller's own registry (unregistered verb_id / failed offer).
# ══════════════════════════════════════════════════════════════════════════

func test_explicit_abort_tears_down_an_in_progress_run_and_emits_aborted() -> void:
	var stride := FakeInteractiveVerbController.new("STRIDE", "hex_a")
	var strike := FakeInteractiveVerbController.new("STRIKE", "target_a")
	var rig := _make_session({"STRIDE": stride, "STRIKE": strike}, FakeTargetingController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start(_entries([[0, "STRIDE"], [1, "STRIKE"]]), FakeActor.new("titus"), CombineQueueClass.Context.TURN)
	assert_true(session.is_active())

	session.abort()

	assert_eq(abort_signals.size(), 1)
	assert_false(session.is_active())
	assert_false(overlay.is_active(), "abort() must return selection_overlay to Layer 1")
	assert_null(session.get_actor())


func test_empty_queue_entries_is_invalid_phase_count_and_emits_aborted() -> void:
	var rig := _make_session({}, FakeTargetingController.new())
	var session = rig["session"]
	var overlay = rig["overlay"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start([], FakeActor.new("titus"), CombineQueueClass.Context.TURN)

	assert_eq(abort_signals.size(), 1, "an empty queue_entries ('invalid phase count') must emit aborted()")
	assert_false(session.is_active(), "an empty queue must never engage the interactive targeting loop")
	assert_false(overlay.is_active(), "an empty queue must never activate selection_overlay")


func test_unregistered_verb_id_aborts_with_no_valid_candidates() -> void:
	var rig := _make_session({}, FakeTargetingController.new())
	var session = rig["session"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))
	session.targeting_complete.connect(func(_r): fail_test("targeting_complete must never fire when the first phase's verb_id is unregistered"))

	session.start(_entries([[0, "STRIDE"]]), FakeActor.new("titus"), CombineQueueClass.Context.TURN)

	assert_eq(abort_signals.size(), 1, "an unregistered verb_id must abort immediately")
	assert_false(session.is_active())
	assert_eq(session.get_result().get("error_code"), "UNREGISTERED_VERB")


func test_failed_offer_descriptor_aborts_with_no_valid_candidates() -> void:
	var stride := FakeInteractiveVerbController.new("STRIDE", "hex_a")
	stride.fail_offer = true
	var rig := _make_session({"STRIDE": stride}, FakeTargetingController.new())
	var session = rig["session"]

	var abort_signals: Array = []
	session.aborted.connect(func(): abort_signals.append(true))

	session.start(_entries([[0, "STRIDE"]]), FakeActor.new("titus"), CombineQueueClass.Context.TURN)

	assert_eq(abort_signals.size(), 1, "a failed (ok:false) offer descriptor must abort immediately -- 'no valid candidates from the wrapped controller'")
	assert_false(session.is_active())
	assert_eq(session.get_result().get("error_code"), "NO_LEGAL_OPTIONS")
	assert_eq(stride.resolve_calls.size(), 0, "a failed offer must never reach the resolution call")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — try_advance(verb_id) mirrors the former inline guard: false
# when inactive or the verb_id does not match the CURRENT phase, true (and
# advances) only when it does.
# ══════════════════════════════════════════════════════════════════════════

func test_try_advance_is_a_no_op_when_inactive_or_verb_id_mismatched() -> void:
	var stride := FakeInteractiveVerbController.new("STRIDE", "hex_a")
	var strike := FakeInteractiveVerbController.new("STRIKE", "target_a")
	var rig := _make_session({"STRIDE": stride, "STRIKE": strike}, FakeTargetingController.new())
	var session = rig["session"]

	assert_false(session.try_advance("STRIDE"), "try_advance() must be a no-op when no run is active")

	session.start(_entries([[0, "STRIDE"], [1, "STRIKE"]]), FakeActor.new("titus"), CombineQueueClass.Context.TURN)

	assert_false(session.try_advance("STRIKE"), "try_advance() must ignore a verb_id that is not the CURRENT phase's own")
	assert_true(session.is_active(), "a mismatched try_advance() must never tear the loop down")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (delegation-only, structural) — CombineTargetingSession never
# independently re-implements sub-action dispatch/validation/cancellation;
# it ONLY ever calls `.enter_selection()` on its injected per-verb
# collaborators and `.execute()` on its injected targeting_controller.
# ══════════════════════════════════════════════════════════════════════════

func test_source_never_references_combine_action_dispatch_or_use_case_classes_directly() -> void:
	var file := FileAccess.open(COMBINE_TARGETING_SESSION_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "%s must be readable as plain source text for this static scan" % COMBINE_TARGETING_SESSION_SCRIPT_PATH)
	var source: String = file.get_as_text()
	file.close()

	var forbidden_markers: Array = [
		"CombineActionController",
		"ConfirmQueueUseCase",
		"CancelCombineUseCase",
		"ValidateCombineQueueUseCase",
		"BuildVerbQueueUseCase",
	]
	for marker in forbidden_markers:
		assert_false(
			source.contains(marker),
			"CombineTargetingSession must never reference '%s' directly -- every domain decision must be delegated to the injected controller_registry's enter_selection() calls or to the injected targeting_controller's execute(), never re-implemented or invoked independently" % marker
		)

	assert_true(
		source.contains("_targeting_controller.execute("),
		"CombineTargetingSession must delegate the final authoritative resolution to its injected targeting_controller's execute() call"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — static source scan: MainScene.gd no longer declares any
# `_combine_targeting_*` var/function (this feature's own test_criteria).
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_no_longer_declares_combine_targeting_state_or_functions() -> void:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable as plain source text for this static scan")
	var source: String = file.get_as_text()
	file.close()

	var forbidden_markers: Array = [
		"_combine_targeting_active",
		"_combine_targeting_entries",
		"_combine_targeting_index",
		"_combine_targeting_actor",
		"_combine_targeting_context",
		"_combine_targeting_accumulated",
		"_combine_targeting_resolved",
		"_combine_targeting_result",
		"_combine_targeting_queue",
		"_combine_targeting_registry_proxy",
		"func start_combine_targeting(",
		"func _enter_combine_targeting_phase(",
		"func _on_combine_targeting_value_chosen(",
		"func _advance_combine_targeting_phase(",
		"func _finish_combine_targeting(",
		"func _abort_combine_targeting(",
		"func _reset_combine_targeting_state(",
		"func _combine_verb_id_of(",
		"func _combine_order_index_of(",
	]
	for marker in forbidden_markers:
		assert_false(
			source.contains(marker),
			"MainScene.gd must no longer reference '%s' -- the interactive Combine sub-action targeting loop now lives entirely in presentation/combine_targeting_session.gd (FEAT-005)" % marker
		)

	assert_true(
		source.contains("CombineTargetingSession") or source.contains("combine_targeting_session.gd"),
		"MainScene.gd must wire the extracted CombineTargetingSession class"
	)
