extends GutTest
## tests/unit/test_action_controller_execute_shapes.gd
##
## GUT suite for FEAT-009 (US-009): presentation/action_controller.gd's
## execute() contract is additively widened to accept a scalar (existing), an
## (option, target) tuple (a Dictionary carrying "option"/"target" keys — the
## same pairing core/application/resolved_selection.gd's
## ResolvedSelection.option_then_target() produces), or a target-set/list (a
## plain Array — mirrors ResolvedSelection.area_set()'s target_set), via
## optional/variant dispatch machinery in the BASE class — never a signature
## break for existing single-scalar callers like Strike.
##
## Strike/Step/Stride/End Turn each override execute() ENTIRELY (never call
## super.execute()), so the new base dispatch machinery is unreachable from
## them — this suite exercises it directly through minimal fake subclasses
## (mirroring tests/gut/test_reaction_error_handling_and_observability.gd's
## established "nested fake class" convention), plus a reflection-based
## regression proof that StrikeActionController.execute()'s own signature
## (the "Strike-style" bare-scalar caller) was left completely untouched.
##
## test_criteria covered:
##   1. execute() called with a bare scalar (Strike-style) dispatches
##      identically to pre-change behavior.
##   2. execute() called with an (option, target) tuple routes to the
##      correct handler.
##   3. execute() called with a target-set/list routes to the correct
##      handler.
##   4. an unrecognized verb_id still fails via the existing VERB_TABLE
##      lookup behavior, unchanged (MainScene.VERB_TABLE, the sole verb_id
##      registry -- this feature touches only action_controller.gd and adds
##      no verb_id-aware branching of its own).
##   5. shape-mismatch (verb expects SCALAR but receives a set) triggers
##      assert() in a test/debug build (mirrors core/domain/
##      effects_applier.gd's identical assert()+push_error()+fail-soft-
##      return convention for a contract violation -- this project's Godot
##      4.3 engine cannot reliably capture assert()/push_error() output from
##      GUT directly, so the FAIL-SOFT RETURN VALUE is the observable proxy,
##      the same convention core/application/tests/test_reaction_budget_gate.gd
##      already establishes).

const ActionControllerPath: String = "res://presentation/action_controller.gd"
const ActionControllerClass = preload(ActionControllerPath)
const StrikeActionControllerClass = preload("res://presentation/strike_action_controller.gd")
const RoundSessionHolderClass = preload("res://infrastructure/round_session_holder.gd")
const MainSceneClass = preload("res://MainScene.gd")


# ── Fake subclasses: minimal ActionControllers that opt INTO the base
#    execute() shape-dispatch machinery by overriding only expected_shape()
#    plus the matching _execute_*() handler -- never execute() itself. This
#    is deliberately the ONLY way to reach the new dispatch code, proving it
#    never intrudes on a subclass (Strike/Step/Stride/End Turn) that
#    overrides execute() directly. ──────────────────────────────────────────

class ScalarVerbController:
	extends "res://presentation/action_controller.gd"

	var received_selection = "UNSET"

	func expected_shape() -> int:
		return SelectionShape.SCALAR

	func _execute_scalar(selection) -> Dictionary:
		received_selection = selection
		return {"ok": true, "shape": "SCALAR", "selection": selection}


class OptionTargetVerbController:
	extends "res://presentation/action_controller.gd"

	var received_option = "UNSET"
	var received_target = "UNSET"

	func expected_shape() -> int:
		return SelectionShape.OPTION_TARGET

	func _execute_option_target(option, target) -> Dictionary:
		received_option = option
		received_target = target
		return {"ok": true, "shape": "OPTION_TARGET", "option": option, "target": target}


class TargetSetVerbController:
	extends "res://presentation/action_controller.gd"

	var received_targets = "UNSET"

	func expected_shape() -> int:
		return SelectionShape.TARGET_SET

	func _execute_target_set(targets: Array) -> Dictionary:
		received_targets = targets
		return {"ok": true, "shape": "TARGET_SET", "targets": targets}


func _deps() -> Dictionary:
	return {"session_holder": RoundSessionHolderClass.new()}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: bare scalar (Strike-style) dispatches identically to
# pre-change behavior
# ══════════════════════════════════════════════════════════════════════════

func test_bare_scalar_selection_routes_to_the_scalar_handler() -> void:
	var controller := ScalarVerbController.new(_deps())

	var result: Dictionary = controller.execute("enemy_0")

	assert_eq(controller.received_selection, "enemy_0", "a bare scalar selection must reach _execute_scalar() unchanged")
	assert_true(result.get("ok"), "a matching-shape scalar dispatch must succeed")
	assert_eq(result.get("shape"), "SCALAR", "the scalar handler, and only the scalar handler, must have run")


func test_default_expected_shape_is_scalar_for_an_unoverridden_verb() -> void:
	# A verb that overrides nothing at all (the base class itself) must keep
	# defaulting to the legacy SCALAR contract -- the same default every
	# pre-existing verb (Strike/Step/Stride/End Turn) already relies on.
	var base := ActionControllerClass.new(_deps())

	assert_eq(base.expected_shape(), ActionControllerClass.SelectionShape.SCALAR, "expected_shape() must default to SCALAR")
	assert_eq(base.execute("whatever"), {"ok": false}, "the base class's own execute() default must stay the pre-existing inert {\"ok\": false} for a scalar call")


func test_strike_action_controller_execute_signature_is_unchanged_by_the_shape_dispatch_widening() -> void:
	# Reflection-based regression proof (mirrors tests/regression/
	# test_seam_public_interfaces_stable.gd's established convention): the
	# ACTUAL, live execute() signature StrikeActionController exposes is
	# untouched by THIS (FEAT-009) feature's additive base-class shape-
	# dispatch widening -- Strike overrides execute() entirely and never
	# reaches the new base dispatch machinery at all.
	#
	# FEAT-008 (US-008; FR-007; ADR-003, Iteration N Combinations) later
	# additively widened Strike's OWN execute() signature with a second
	# optional positional argument, `no_self_spend_execution: bool = false`
	# (presentation/strike_action_controller.gd's own FEAT-008 doc) -- an
	# unrelated, later, sanctioned change, not a regression of THIS feature's
	# "untouched by shape-dispatch" invariant, which this test still pins:
	# neither argument is named/shaped like the OPTION_TARGET/TARGET_SET
	# machinery this feature introduced, and `selection` remains the first
	# positional argument with its pre-existing default.
	var strike := StrikeActionControllerClass.new(_deps())
	var method_info: Dictionary = {}
	for m in strike.get_method_list():
		if m.get("name", "") == "execute":
			method_info = m
			break

	assert_false(method_info.is_empty(), "StrikeActionController must still declare its own execute() override")
	var args: Array = method_info.get("args", [])
	assert_eq(args.size(), 2, "StrikeActionController.execute() must take exactly two (optional) positional arguments: selection, no_self_spend_execution (FEAT-008)")
	assert_eq(args[0].get("name", ""), "selection", "StrikeActionController.execute()'s first argument must still be named 'selection', unchanged by the FEAT-009 shape-dispatch widening")
	assert_eq(args[1].get("name", ""), "no_self_spend_execution", "StrikeActionController.execute()'s second argument (FEAT-008) must be named 'no_self_spend_execution'")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: an (option, target) tuple routes to the correct handler
# ══════════════════════════════════════════════════════════════════════════

func test_option_target_tuple_routes_to_the_option_target_handler() -> void:
	var controller := OptionTargetVerbController.new(_deps())

	var result: Dictionary = controller.execute({"option": "fireball", "target": "enemy_0"})

	assert_eq(controller.received_option, "fireball", "the (option, target) tuple's option must reach _execute_option_target()")
	assert_eq(controller.received_target, "enemy_0", "the (option, target) tuple's target must reach _execute_option_target()")
	assert_true(result.get("ok"), "a matching-shape option/target dispatch must succeed")
	assert_eq(result.get("shape"), "OPTION_TARGET", "the option/target handler, and only the option/target handler, must have run")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a target-set/list routes to the correct handler
# ══════════════════════════════════════════════════════════════════════════

func test_target_set_list_routes_to_the_target_set_handler() -> void:
	var controller := TargetSetVerbController.new(_deps())
	var hex_set: Array = ["enemy_0", "enemy_1", "enemy_2"]

	var result: Dictionary = controller.execute(hex_set)

	assert_eq(controller.received_targets, hex_set, "the target-set Array must reach _execute_target_set() verbatim")
	assert_true(result.get("ok"), "a matching-shape target-set dispatch must succeed")
	assert_eq(result.get("shape"), "TARGET_SET", "the target-set handler, and only the target-set handler, must have run")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: an unrecognized verb_id still fails via the existing
# VERB_TABLE lookup behavior, unchanged
# ══════════════════════════════════════════════════════════════════════════

func test_unrecognized_verb_id_is_still_absent_from_verb_table() -> void:
	# This feature touches ONLY presentation/action_controller.gd and adds no
	# verb_id-aware branching of its own (each ActionController instance is
	# already bound to exactly one verb by MainScene.VERB_TABLE's lookup --
	# see action_controller.gd's file-level doc). MainScene.VERB_TABLE
	# remains the SOLE place a verb_id is registered; an unrecognized
	# verb_id must still be simply absent, exactly as before this feature.
	assert_false(MainSceneClass.VERB_TABLE.has("NOT_A_REAL_VERB"), "an unrecognized verb_id must still be absent from VERB_TABLE -- this feature must not add a catch-all/fallback entry")


func test_verb_table_membership_is_unchanged_by_this_feature() -> void:
	# Static regression proof that widening action_controller.gd's execute()
	# shape contract did not touch the verb_id registry itself: exactly the
	# same four pre-FEAT-009 verbs, plus CAST_SPELL (FEAT-004 / US-004,
	# FR-003) and COMBINE (FEAT-001, Iteration N kickoff, US-001/FR-003) —
	# the two intentional, documented additions since this suite was
	# written.
	var verb_ids: Array = MainSceneClass.VERB_TABLE.keys()
	verb_ids.sort()

	assert_eq(verb_ids, ["CAST_SPELL", "COMBINE", "END_TURN", "STEP", "STRIDE", "STRIKE"], "VERB_TABLE must still register exactly the same four pre-existing verbs plus CAST_SPELL (FEAT-004) and COMBINE (FEAT-001)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: shape-mismatch (verb expects SCALAR but receives a set)
# triggers assert() in a test build
# ══════════════════════════════════════════════════════════════════════════

func test_shape_mismatch_scalar_verb_given_a_set_fails_soft_without_dispatching() -> void:
	var controller := ScalarVerbController.new(_deps())

	# ScalarVerbController.expected_shape() == SCALAR, but it is handed a
	# target-set (Array) -- a verb/resolution-shape wiring bug (design
	# notes' error_handling policy #5). assert(false, ...) fires -- and, in
	# THIS engine/test-runner combination, a failed assert() aborts the
	# current function immediately (mirroring core/domain/
	# effects_applier.gd's missing-target_id branch, where the SAME pairing
	# leaves _apply_one() a no-op past the assert -- see that file's suite,
	# which for this exact reason asserts the BEHAVIORAL side effect, e.g.
	# "does not abort the batch", rather than a literal return value). This
	# suite follows the identical, already-established convention: assert
	# the handler never ran and that no shape silently "succeeded", not the
	# literal Dictionary contents of an aborted call.
	var result: Dictionary = controller.execute(["enemy_0", "enemy_1"])

	assert_false(result.get("ok", false), "a shape mismatch must never report ok == true")
	assert_eq(controller.received_selection, "UNSET", "_execute_scalar() must NEVER run when the received shape does not match expected_shape()")


func test_shape_mismatch_option_target_verb_given_a_scalar_fails_soft_without_dispatching() -> void:
	var controller := OptionTargetVerbController.new(_deps())

	var result: Dictionary = controller.execute("enemy_0")

	assert_false(result.get("ok", false), "a scalar handed to an OPTION_TARGET-only verb must never report ok == true")
	assert_eq(controller.received_option, "UNSET", "_execute_option_target() must NEVER run on a shape mismatch")


func test_action_controller_source_uses_the_assert_then_push_error_contract_violation_convention() -> void:
	# Confirms the shape-mismatch branch actually uses this project's
	# established fail-fast-in-dev/fail-soft-in-release convention (the
	# exact assert(false, ...) + push_error(...) pairing core/domain/
	# effects_applier.gd's missing-target_id branch and core/application/
	# reaction_window.gd's budget-delta-invariant branch both already use),
	# rather than e.g. a bare push_error with no debug-build signal at all.
	var source: String = FileAccess.get_file_as_string(ActionControllerPath)

	assert_true(source.find("assert(false, message)") != -1, "the shape-mismatch branch must assert(false, ...) in test/debug builds, mirroring the project's established contract-violation convention")
	assert_true(source.find("ERR_SHAPE_MISMATCH") != -1, "the shape-mismatch branch must fail soft with a named, greppable error code")
