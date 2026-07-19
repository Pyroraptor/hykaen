extends GutTest
## tests/unit/test_combine_action_controller_registration.gd — FEAT-001
## (US-001; FR-003; ADR-001)
##
## Iteration N (Combinations) kickoff: proves the infrastructure seam that
## lets the COMBINE meta-verb be resolved WITHOUT any hard-coded reference to
## its eventual sub-action controllers (StrideActionController /
## StrikeActionController) — those are only ever reached later, by TABLE
## LOOKUP through the SAME data-driven VERB_TABLE + _controller(verb_id)
## seam every other verb already uses (see MainScene.gd's own
## `_controller(verb_id)` doc).
##
## This feature scaffolds ONLY the entry-point plumbing: VERB_TABLE
## registration + a CombineActionController stub implementing the
## three-method verb contract (availability/enter_selection/execute) inertly
## (fail-closed / no-op). Real Stamina/Dazed/Repeat gating and N-length
## sub-action queue orchestration land in later Iteration N features.
##
## test_criteria covered:
##   1. MainScene._controller("COMBINE") resolves to a CombineActionController
##      instance.
##   2. CombineActionController extends presentation/action_controller.gd
##      and implements availability()/enter_selection()/execute() stubs.
##   3. Static/text scan: presentation/combine_action_controller.gd contains
##      no hard-coded class reference (preload/class_name) to the Stride or
##      Strike controllers.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const ActionControllerClass = preload("res://presentation/action_controller.gd")
const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass = preload("res://infrastructure/round_session_holder.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_caster_loads_in_prologue.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _deps() -> Dictionary:
	return {"session_holder": RoundSessionHolderClass.new()}


# ══════════════════════════════════════════════════════════════════════════
# Criterion — COMBINE is registered in the data-driven VERB_TABLE, pointing
# at the concrete CombineActionController class -- statically, no boot
# required (mirrors tests/boot/test_main_scene_cast_spell_verb_registered.gd's
# established convention for CAST_SPELL).
# ══════════════════════════════════════════════════════════════════════════

func test_verb_table_registers_combine_pointing_at_combine_action_controller() -> void:
	assert_true(MainSceneClass.VERB_TABLE.has("COMBINE"), "MainScene.VERB_TABLE must register a COMBINE entry")
	assert_eq(
		MainSceneClass.VERB_TABLE.get("COMBINE"), CombineActionControllerClass,
		"VERB_TABLE['COMBINE'] must point at presentation/combine_action_controller.gd's CombineActionController"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — _controller("COMBINE") resolves to a real
# CombineActionController instance, exactly the same lazy-memoized way every
# other verb is resolved.
# ══════════════════════════════════════════════════════════════════════════

func test_controller_combine_resolves_to_a_combine_action_controller_instance() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var controller = instance._controller("COMBINE")
	assert_true(controller is CombineActionControllerClass, "_controller(\"COMBINE\") must return a real CombineActionController")
	assert_same(
		controller, instance._controllers.get("COMBINE"),
		"_controller() must memoize the SAME instance into _controllers, exactly as it does for every other verb"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — CombineActionController extends action_controller.gd and
# implements the three-method verb contract as inert stubs (fail-closed).
# ══════════════════════════════════════════════════════════════════════════

func test_combine_action_controller_extends_action_controller() -> void:
	var controller := CombineActionControllerClass.new(_deps())
	assert_true(controller is ActionControllerClass, "CombineActionController must extend presentation/action_controller.gd")


func test_combine_action_controller_availability_stub_is_fail_closed() -> void:
	var controller := CombineActionControllerClass.new(_deps())
	assert_false(controller.availability(), "an un-gated COMBINE stub must be fail-closed (unavailable) until real gating lands")


func test_combine_action_controller_enter_selection_stub_does_not_throw() -> void:
	var controller := CombineActionControllerClass.new(_deps())
	var result = controller.enter_selection()
	assert_true(result is Dictionary, "enter_selection() stub must return a Dictionary without throwing")


func test_combine_action_controller_execute_stub_returns_not_ok() -> void:
	var controller := CombineActionControllerClass.new(_deps())
	# execute() is a coroutine (it internally awaits sub-action queue
	# resolution as of FEAT-007/FEAT-008) so callers must await it, exactly
	# like every other verb controller's execute() in this suite (see e.g.
	# tests/unit/test_combine_single_charge.gd). With no `_controller_for_fn`
	# resolver injected via `_deps()`, this exercises the "no
	# sub-action-controller resolver wired" degrade path, which still yields
	# a controlled Dictionary result -- not a crash -- but since `_deps()`
	# supplies no actor here, execute() short-circuits ok=false before that.
	var result: Dictionary = await controller.execute(null)
	assert_false(result.get("ok", true), "an un-implemented COMBINE execute() stub must report ok=false, never a crash or a false success")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — static/text scan: no hard-coded class reference
# (preload/class_name) to Stride or Strike controllers exists in the new
# file. CombineActionController must resolve its future sub-action
# controllers exclusively through the data-driven _controller(verb_id)
# lookup (table-based), never a direct preload/class_name reference.
# ══════════════════════════════════════════════════════════════════════════

func _read_combine_controller_text() -> String:
	var f := FileAccess.open("res://presentation/combine_action_controller.gd", FileAccess.READ)
	assert_not_null(f, "presentation/combine_action_controller.gd must exist and be readable")
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _non_comment_code_text(contents) -> String -- strips every full-line
## comment (a line whose first non-whitespace characters are "#") before
## scanning. Explanatory PROSE that merely NAMES StrideActionController/
## StrikeActionController (e.g. this very file's own doc comment explaining
## that Combine resolves them via `_controller(verb_id)` instead of a hard
## reference) is legitimate documentation, not a code-level dependency, so
## it must never trip this check -- only an actual `preload(...)`/
## `class_name`/bare-identifier reference living in CODE would.
func _non_comment_code_text(contents: String) -> String:
	var code_lines: PackedStringArray = []
	for line in contents.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	return "\n".join(code_lines)


func test_combine_action_controller_source_has_no_hard_coded_stride_or_strike_reference() -> void:
	var code: String = _non_comment_code_text(_read_combine_controller_text())
	assert_false(
		code.contains("StrideActionController"),
		"presentation/combine_action_controller.gd must not hard-reference StrideActionController in code (preload/class_name) -- resolve it via _controller(\"STRIDE\") instead"
	)
	assert_false(
		code.contains("StrikeActionController"),
		"presentation/combine_action_controller.gd must not hard-reference StrikeActionController in code (preload/class_name) -- resolve it via _controller(\"STRIKE\") instead"
	)


func test_combine_action_controller_source_has_no_preload_of_stride_or_strike_controller_paths() -> void:
	var contents: String = _read_combine_controller_text()
	assert_false(
		contents.contains("stride_action_controller.gd"),
		"presentation/combine_action_controller.gd must not preload stride_action_controller.gd by path"
	)
	assert_false(
		contents.contains("strike_action_controller.gd"),
		"presentation/combine_action_controller.gd must not preload strike_action_controller.gd by path"
	)
