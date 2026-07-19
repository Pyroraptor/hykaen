extends GutTest
## tests/regression/test_strike_end_to_end_unchanged.gd — FEAT-244 (US-013).
##
## Capstone automated end-to-end regression test for the steel thread's core
## exit criterion for Strike: after ALL of this iteration's additive
## selection/execute generalization (FEAT-006 event-emission generalization,
## FEAT-007/FEAT-008 SelectionDescriptor candidate_options/AREA_SET fields,
## FEAT-009 action_controller.gd's additive OPTION_TARGET/TARGET_SET
## execute() shape dispatch, FEAT-010 SelectionOverlay's Layer-2a option
## step, FEAT-242 SelectionOverlay's Layer-2b AREA_SET origin-pick/preview/
## confirm step, FEAT-243 END_TURN's direct-execute regression guard), the
## Strike verb -> target pick -> execute() flow remains functionally
## UNCHANGED: byte-identical hp/AttackEvent/combat-log outcome, and its
## execute() call is still handed a bare scalar target_id -- never the
## additive {"option":...,"target":...} Dictionary or target-set/Array
## shapes those features introduced for OTHER (future) verbs.
##
## Depends on FEAT-004 (Strike's damage retrofit through the EffectsApplier
## seam -- the resolution math this suite pins) and FEAT-010 (the first of
## this iteration's Layer 2 UI generalizations, so this suite runs against a
## SelectionOverlay that genuinely HAS the additive Layer-2a machinery to
## prove Strike bypasses).
##
## NO mocked/stubbed doubles anywhere in this file: every suite below drives
## the REAL, shipped res://MainScene.tscn composition root -- the real
## VerbBarView, the real SelectionOverlay, the real HexGridView, the real
## StrikeActionController (action_controller.gd's concrete Strike
## subclass), and the real resolve_action_use_case -- exactly the objects a
## real player drives (mirrors tests/gut/test_strike_layer2_integration.gd's/
## tests/integration/test_strike_effects_applier_retrofit.gd's established
## "boot-real" convention).
##
## test_criteria covered:
##   1. "automated e2e regression test: Strike verb -> target pick ->
##      execute() produces hp/AttackEvent/log outcome identical to
##      pre-change baseline" -- Section B below boots TWO real MainScene
##      instances at the SAME pinned seed. One ("baseline") drives Strike
##      through a bare direct `_verb_registry.execute("STRIKE", target_id)`
##      call -- the exact single-scalar verb->target->execute() call shape
##      that existed before SelectionOverlay's Layer-2a/2b generalization
##      work ever began, and which this iteration's additive machinery must
##      never disturb. The other ("current") drives the SAME Strike through
##      the FULL current real UI path: VerbBarView.press("STRIKE") ->
##      HexGridView.hex_clicked -> SelectionOverlay's Layer 2 resolution ->
##      that exact same `_verb_registry.execute()` call. Both instances,
##      booted from the identical seed with nothing else touched before the
##      Strike, must produce byte-identical hp/AttackEvent/combat-log
##      outcomes -- proving the additive Layer 2 UI machinery is a pure,
##      inert pass-through for Strike.
##   2. "test drives the real selection_overlay/action_controller path (no
##      mocked doubles)" -- the "current" arm above explicitly drives
##      SelectionOverlay's real Layer 2 flow (asserted via
##      selection_resolved/is_active()), and BOTH arms resolve through the
##      real StrikeActionController.execute() (action_controller.gd's
##      concrete Strike subclass) -- no test double stands in for either.
##
## Section A is a structural complement: a static source check proving
## StrikeActionController.execute() itself contains no reference to the
## additive base-class shape-dispatch machinery (_classify_selection(),
## SelectionShape, expected_shape(), super.execute()) that FEAT-009 added to
## presentation/action_controller.gd for a FUTURE OPTION_TARGET/TARGET_SET
## verb -- Strike's own resolution path is untouched by that generalization
## at the source level, not merely "happens to produce the same numbers".

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const STRIKE_ACTION_CONTROLLER_PATH: String = "res://presentation/strike_action_controller.gd"

const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/integration/test_strike_effects_applier_retrofit.gd's/
## tests/gut/test_strike_layer2_integration.gd's identically-valued
## constant): Titus acts first and the sole enemy (Skeleton) starts adjacent
## to him, so Strike's Layer 2 has at least one in-reach target at boot with
## zero setup needed.
const PROLOGUE_SEED: int = 42


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func _sole_attack_event(instance):
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved on this instance")
	return attack_events[0]


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _extract_function_body(content, func_signature_prefix) -> String — mirrors
## tests/integration/test_strike_effects_applier_retrofit.gd's identically-
## named helper: pulls the text of one function (from its `func <name>(`
## line up to, but not including, the next top-level `\nfunc `) out of a
## whole-file source string.
func _extract_function_body(content: String, func_signature_prefix: String) -> String:
	var start: int = content.find(func_signature_prefix)
	assert_true(start >= 0, "expected to find '%s' in the source file" % func_signature_prefix)
	if start < 0:
		return ""
	var next_func: int = content.find("\nfunc ", start + func_signature_prefix.length())
	if next_func < 0:
		return content.substr(start)
	return content.substr(start, next_func - start)


## Strips full-line `##`/`#` doc-comment lines out of a source snippet before
## scanning for a call pattern (mirrors ci/check_no_duplicate_seams.sh's own
## convention) -- a comment merely NAMING a pattern in this file-level doc
## must never be mistaken for a live call site.
func _strip_comment_lines(body: String) -> String:
	var kept: Array = []
	for line in body.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ══════════════════════════════════════════════════════════════════════════
# Section A — structural complement: StrikeActionController.execute() itself
# contains no reference to the additive base-class shape-dispatch machinery
# introduced by FEAT-009 for a FUTURE OPTION_TARGET/TARGET_SET verb.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_action_controller_execute_is_a_full_override_untouched_by_shape_dispatch_generalization() -> void:
	# FEAT-008 (US-008; FR-007; ADR-003) additively threaded a second,
	# defaulted `no_self_spend_execution: bool = false` parameter into this
	# signature (see strike_action_controller.gd's own FEAT-008 doc) -- every
	# PRE-EXISTING caller omits it, so this is a pure signature-level addition,
	# not a behavior change this static scan needs to guard against; the
	# search prefix below is updated to match the current signature verbatim
	# so the function-body extraction still locates the right span.
	var content: String = _read_file(STRIKE_ACTION_CONTROLLER_PATH)
	var body: String = _extract_function_body(content, "func execute(selection = null, no_self_spend_execution: bool = false) -> Dictionary:")
	var live_code: String = _strip_comment_lines(body)

	assert_false(
		live_code.contains("super.execute("),
		"StrikeActionController.execute() must remain a FULL override -- it must never delegate into action_controller.gd's additive base execute() shape dispatch"
	)
	assert_false(
		live_code.contains("_classify_selection("),
		"StrikeActionController.execute() must never call the additive _classify_selection() helper -- Strike's own single-scalar resolution path is untouched by the OPTION_TARGET/TARGET_SET generalization"
	)
	assert_false(
		live_code.contains("SelectionShape"),
		"StrikeActionController.execute() must never reference the additive SelectionShape enum -- Strike is unaffected by that generalization"
	)
	assert_false(
		live_code.contains("expected_shape("),
		"StrikeActionController.execute() must never call expected_shape() -- Strike never opts into the additive shape-dispatch contract"
	)


func test_strike_action_controller_does_not_override_expected_shape() -> void:
	# Strike never overrides expected_shape() -- it overrides execute()
	# directly instead (see the file-level doc's Section A rationale), so the
	# base class's SCALAR default is simply never consulted for this verb.
	var content: String = _read_file(STRIKE_ACTION_CONTROLLER_PATH)
	assert_false(
		content.contains("func expected_shape("),
		"StrikeActionController must not override expected_shape() -- it overrides execute() entirely instead, bypassing the additive shape-dispatch machinery altogether"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section B — the core exit criterion: TWO real, same-seed MainScene
# instances, one driving Strike through a bare direct execute() call (the
# pre-generalization call shape) and the other through the FULL current
# Layer 1/Layer 2 UI path, must produce a byte-identical hp/AttackEvent/log
# outcome.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_via_direct_execute_and_via_real_selection_overlay_ui_produce_byte_identical_outcome() -> void:
	# ── Arm 1: "baseline" -- a bare, direct verb->target->execute() call,
	# bypassing VerbBarView/SelectionOverlay's Layer 2 UI entirely. This is
	# EXACTLY the single-scalar call shape presentation/action_controller.gd's
	# `_verb_registry.execute(verb_id, selection)` seam has always accepted,
	# predating every additive Layer 2 generalization this iteration made. ──
	var baseline = _boot_main_scene_with_seed(PROLOGUE_SEED)
	await get_tree().process_frame

	var baseline_skeleton = _skeleton(baseline)
	var baseline_skeleton_id: String = baseline_skeleton.combatant_id
	var baseline_hp_before: int = baseline_skeleton.hp_current

	assert_true(
		baseline._verb_registry.is_available("STRIKE"),
		"fixture assumption: the prologue's first actor has at least one in-reach target at seed=%d" % PROLOGUE_SEED
	)
	watch_signals(baseline.selection_overlay)

	var baseline_result: Dictionary = baseline._verb_registry.execute("STRIKE", baseline_skeleton_id)
	assert_true(baseline_result.get("resolved", false), "the direct-call arm's Strike must resolve")

	# The direct call never touches SelectionOverlay's Layer 2 machinery at
	# all -- proving the "baseline" arm is genuinely a bypass, not merely a
	# faster route through the same UI.
	assert_false(baseline.selection_overlay.is_active(), "the direct-call arm must never activate SelectionOverlay")
	assert_signal_not_emitted(baseline.selection_overlay, "selection_resolved", "the direct-call arm must never resolve anything through SelectionOverlay")

	var baseline_attack_event = _sole_attack_event(baseline)
	var baseline_hp_after: int = baseline_skeleton.hp_current
	var baseline_history: Array = baseline.round_history_port.get_history()
	assert_true(baseline_history.size() > 0, "at least one combat-log entry must be appended for the direct-call arm's resolved Strike")
	var baseline_last_entry: Dictionary = baseline_history[baseline_history.size() - 1]


	# ── Arm 2: "current" -- the FULL current real UI path: pressing the
	# Layer 1 STRIKE verb, then a real HexGridView.hex_clicked emission
	# landing on the highlighted target's own hex, resolved through
	# SelectionOverlay's real Layer 2 flow (presentation/selection_overlay.gd,
	# wired by MainScene.gd -- no mocked/stubbed double anywhere). ──
	var current = _boot_main_scene_with_seed(PROLOGUE_SEED)
	await get_tree().process_frame

	var current_skeleton = _skeleton(current)
	var current_skeleton_id: String = current_skeleton.combatant_id
	var current_hp_before: int = current_skeleton.hp_current
	assert_eq(current_hp_before, baseline_hp_before, "sanity check: both same-seed instances must start with identical Skeleton hp")

	assert_true(
		is_instance_of(current.selection_overlay, load("res://presentation/selection_overlay.gd")),
		"MainScene must wire the REAL SelectionOverlay -- no stub/mock"
	)
	watch_signals(current.selection_overlay)

	var selection: Dictionary = current.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(current_skeleton_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	assert_true(current.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STRIKE")
	assert_eq(current.selection_overlay.get_active_verb_id(), "STRIKE")
	# STRIKE names no candidate_options -- SelectionOverlay's additive
	# Layer-2a option step (FEAT-010) must never engage for it.
	assert_false(current.selection_overlay.is_awaiting_option(), "STRIKE must never enter SelectionOverlay's additive Layer-2a option step")

	var target_token = current.hex_grid_view.get_token(current_skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")

	# The real player interaction: a click landing on the highlighted
	# target's own hex, via the REAL HexGridView.hex_clicked signal
	# SelectionOverlay subscribes to -- never a direct `_verb_registry.
	# execute()` call from this test.
	current.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_signal_emitted(current.selection_overlay, "selection_resolved", "a click landing on the highlighted target's hex must resolve through SelectionOverlay")
	var resolved_params: Array = get_signal_parameters(current.selection_overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIKE", "selection_resolved must carry the STRIKE verb_id")
	assert_true(resolved_params[1] is Dictionary, "selection_resolved's result must be the registry.execute() return Dictionary verbatim")
	assert_true(resolved_params[1].get("resolved", false), "the real-UI arm's Strike must resolve")
	assert_false(current.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the real click resolves the Strike")

	var current_attack_event = _sole_attack_event(current)
	var current_hp_after: int = current_skeleton.hp_current
	var current_history: Array = current.round_history_port.get_history()
	assert_true(current_history.size() > 0, "at least one combat-log entry must be appended for the real-UI arm's resolved Strike")
	var current_last_entry: Dictionary = current_history[current_history.size() - 1]


	# ── The criterion itself: byte-identical hp/AttackEvent/log outcome
	# between the two arms, proving the additive Layer 2 UI generalization is
	# a pure, inert pass-through for Strike. ──────────────────────────────────
	assert_eq(
		current_hp_after, baseline_hp_after,
		"the Skeleton's post-Strike hp_current must be IDENTICAL whether Strike was driven through a direct execute() call or through the real SelectionOverlay UI"
	)
	assert_eq(
		baseline_hp_before - baseline_hp_after, current_hp_before - current_hp_after,
		"the damage dealt must be IDENTICAL between both arms"
	)

	assert_eq(
		current_attack_event.to_dict(), baseline_attack_event.to_dict(),
		"the emitted AttackEvent must be field-for-field IDENTICAL between the direct-execute arm and the real-SelectionOverlay-UI arm"
	)

	assert_eq(
		current_last_entry.get("damage_final", -1), baseline_last_entry.get("damage_final", -2),
		"the combat log's damage_final must be IDENTICAL between both arms"
	)
	assert_eq(
		current_last_entry.get("target", {}).get("hp_current", -1), baseline_last_entry.get("target", {}).get("hp_current", -2),
		"the combat log's snapshotted target hp_current must be IDENTICAL between both arms"
	)
	assert_eq(
		current_last_entry.get("roll", -1), baseline_last_entry.get("roll", -2),
		"the combat log's roll must be IDENTICAL between both arms"
	)
