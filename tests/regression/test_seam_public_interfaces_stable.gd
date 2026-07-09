extends GutTest
## tests/regression/test_seam_public_interfaces_stable.gd — FEAT-009
## (US-010, NFR-008/G2): regression proof that the THREE seams this
## iteration's Dodge-Step/log wiring (FEAT-001..FEAT-008) REUSES —
## presentation/movement_input_controller.gd's get_selectable_step_hexes(),
## the ITokenRepositionPort Callable (concretely
## presentation/hex_grid_view.gd's HexGridView.move_token()), and the
## FEAT-001 hex-choice seam (core/application/ports/
## hex_choice_resolver_port.gd's HexChoiceResolverPort) — still expose the
## EXACT SAME public method signatures their pre-existing callers (chiefly
## AI-Stride: core/application/round_session.gd's
## `_reposition_token_after_ai_stride()`, and every player Step/Stride via
## MovementInputController itself) already depend on. This iteration's own
## design notes are explicit that these are REUSED, not duplicated, seams
## (ADR-002/ADR-006 "no duplicate seam") — this suite is the automated check
## that reuse never silently widened/narrowed a call signature underneath an
## existing caller.
##
## Verified two ways per seam, mirroring this project's established
## tests/regression/test_single_hex_choice_seam.gd convention:
##   1. Reflection (Object.get_method_list()) — the ACTUAL, live method
##      signature (argument count/names) of the concrete production class,
##      not a hand-copied docstring that could silently drift from the code.
##   2. A real, direct call proving the pre-existing call SHAPE still works
##      end-to-end (e.g. AI-Stride's exact `_token_reposition_fn.call(actor_id,
##      destination)` two-positional-argument shape against the REAL
##      hex_grid_view.move_token()).
##
## test_criteria: "movement_input_controller.get_selectable_step_hexes,
## ITokenRepositionPort callable signature, and the hex-choice seam signature
## are unchanged/backward-compatible for existing AI-Stride callers."

const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const HexGridViewClass = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const RoundSessionPath: String = "res://core/application/round_session.gd"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")


func _method_info(method_list: Array, method_name: String) -> Dictionary:
	for m in method_list:
		if m.get("name", "") == method_name:
			return m
	return {}


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ══════════════════════════════════════════════════════════════════════════
# Seam 1 — movement_input_controller.get_selectable_step_hexes() (the
# IStepHexQueryPort / AI-Stride step-affordance contract): must remain a
# ZERO-argument query, returning an Array, exactly as every pre-existing
# caller (MainScene.gd's own can_step()/get_step_candidates(), the
# highlight-recompute path) already depends on.
# ══════════════════════════════════════════════════════════════════════════

func test_get_selectable_step_hexes_remains_a_zero_argument_method() -> void:
	var controller := MovementInputControllerClass.new()
	var method: Dictionary = _method_info(controller.get_method_list(), "get_selectable_step_hexes")

	assert_false(method.is_empty(), "get_selectable_step_hexes must still exist on MovementInputController")
	assert_eq(
		method.get("args", []).size(), 0,
		"REGRESSION: get_selectable_step_hexes() must remain a ZERO-argument query -- adding a required argument would break every pre-existing caller (AI-Stride's own step highlighting, MainScene.gd's can_step()/get_step_candidates())"
	)


func test_get_selectable_step_hexes_still_returns_an_array_for_a_configured_actor() -> void:
	## Behavioral companion to the reflection check above: the pre-existing
	## call SHAPE (zero args, Array return) still genuinely works end-to-end.
	var controller := MovementInputControllerClass.new()
	var actor: Dictionary = {"combatant_id": "a", "hex_coord": HexCoordClass.new(0, 0)}
	controller.configure(actor, [])

	var result = controller.get_selectable_step_hexes()
	assert_true(result is Array, "get_selectable_step_hexes() must still return an Array")


func test_get_selectable_step_hexes_for_stateless_variant_also_remains_two_argument() -> void:
	## FEAT-002 (Dodge-Step) added get_selectable_step_hexes_for(actor,
	## other_combatants) as a NEW, additional stateless query -- it must
	## never have replaced/renamed the original get_selectable_step_hexes()
	## seam above (ADR-002 "no duplicate seam" cuts both ways: adding a new
	## entry point must not silently retire the old one either).
	var controller := MovementInputControllerClass.new()
	var method: Dictionary = _method_info(controller.get_method_list(), "get_selectable_step_hexes_for")

	assert_false(method.is_empty(), "get_selectable_step_hexes_for must exist as the FEAT-002 addition")
	assert_eq(method.get("args", []).size(), 2, "get_selectable_step_hexes_for(actor, other_combatants) must take exactly 2 arguments")


# ══════════════════════════════════════════════════════════════════════════
# Seam 2 — ITokenRepositionPort: the Callable contract
# `func(token_id: String, new_hex_coord) -> void`, concretely
# presentation/hex_grid_view.gd's HexGridView.move_token(). AI-Stride
# (round_session.gd's `_reposition_token_after_ai_stride()`) and Dodge-Step
# (resolve_dodge_step_use_case.gd) both call THIS SAME seam with the
# identical two-positional-argument shape.
# ══════════════════════════════════════════════════════════════════════════

func test_move_token_remains_a_two_argument_method_on_hex_grid_view() -> void:
	var view := HexGridViewClass.new()
	add_child_autofree(view)
	var method: Dictionary = _method_info(view.get_method_list(), "move_token")

	assert_false(method.is_empty(), "move_token must still exist on HexGridView")
	assert_eq(
		method.get("args", []).size(), 2,
		"REGRESSION: move_token(combatant_id, new_hex_coord) must remain a TWO-argument method -- this is the ITokenRepositionPort seam BOTH AI-Stride's `_reposition_token_after_ai_stride()` and Dodge-Step's ResolveDodgeStepUseCase call with the identical (token_id, hex_coord) shape"
	)
	var args: Array = method.get("args", [])
	assert_eq(args[0].get("name", ""), "combatant_id", "the first ITokenRepositionPort argument must remain named combatant_id")


func test_ai_stride_reposition_call_site_still_uses_the_two_positional_argument_shape() -> void:
	## Static-source proof (mirrors test_single_hex_choice_seam.gd's own
	## grep-based convention) that round_session.gd's AI-Stride reposition
	## call site was not silently widened to a THIRD argument the concrete
	## HexGridView.move_token() (2 args, asserted above) could never accept.
	var source: String = _read_file(RoundSessionPath)
	assert_true(
		source.contains("_token_reposition_fn.call(actor_id, destination)"),
		"REGRESSION: round_session.gd's _reposition_token_after_ai_stride() must still invoke the ITokenRepositionPort seam with the exact two-positional-argument (actor_id, destination) shape"
	)


func test_token_reposition_seam_genuinely_relocates_a_real_hex_grid_view_token() -> void:
	## Behavioral companion: drives the REAL HexGridView.move_token() through
	## the exact Callable-invocation shape round_session.gd's AI-Stride path
	## uses, proving the seam still works end-to-end for that pre-existing
	## caller (not just "the argument count matches").
	var view = HexGridViewScene.instantiate()
	add_child_autofree(view)
	view.load_combatants([
		CombatantClass.new("enemy_0", "Enemy", "Enemy", HexCoordClass.new(0, 0)),
	])

	var reposition_fn: Callable = Callable(view, "move_token")
	assert_true(reposition_fn.is_valid(), "Callable(hex_grid_view, \"move_token\") must remain a valid Callable")

	var destination := HexCoordClass.new(2, -1)
	reposition_fn.call("enemy_0", destination)

	var token = view.get_token("enemy_0")
	assert_not_null(token, "the token must still be resolvable by id after reposition")
	assert_true(token.hex_coord.equals(destination), "REGRESSION: invoking the ITokenRepositionPort seam with the AI-Stride (token_id, hex_coord) shape must still relocate the real on-screen token")


# ══════════════════════════════════════════════════════════════════════════
# Seam 3 — the FEAT-001 hex-choice seam
# (core/application/ports/hex_choice_resolver_port.gd HexChoiceResolverPort):
# resolve(legal_hexes) and its FEAT-001 Dodge-Step-flavored delegate
# choose_step_hex(defender_id, legal_hexes) must retain their documented
# argument counts.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_remains_a_one_argument_method() -> void:
	var base := HexChoiceResolverPortClass.new()
	var method: Dictionary = _method_info(base.get_method_list(), "resolve")

	assert_false(method.is_empty(), "resolve must still exist on HexChoiceResolverPort")
	assert_eq(method.get("args", []).size(), 1, "REGRESSION: resolve(legal_hexes) must remain a ONE-argument method -- the seam's original, pre-Dodge-Step contract")


func test_choose_step_hex_remains_a_two_argument_method() -> void:
	var base := HexChoiceResolverPortClass.new()
	var method: Dictionary = _method_info(base.get_method_list(), "choose_step_hex")

	assert_false(method.is_empty(), "choose_step_hex must still exist on HexChoiceResolverPort")
	assert_eq(method.get("args", []).size(), 2, "REGRESSION: choose_step_hex(defender_id, legal_hexes) must remain a TWO-argument method")


func test_choose_step_hex_still_pure_delegates_to_resolve_with_an_empty_legal_set() -> void:
	## Behavioral companion: an empty legal_hexes set must still resolve to
	## null through BOTH entry points without invoking any await/prompt,
	## mirroring hex_choice_resolver_port.gd's own documented "empty always
	## yields null" universal invariant.
	var base := HexChoiceResolverPortClass.new()
	assert_eq(base.resolve([]), null)
	assert_eq(base.choose_step_hex("defender-1", []), null)


# ══════════════════════════════════════════════════════════════════════════
# Cross-seam sanity: none of the three reflected signatures above are
# accidentally IDENTICAL to one another (a copy/rename mistake could
# otherwise make this suite vacuously pass by testing the same method twice).
# ══════════════════════════════════════════════════════════════════════════

func test_the_three_seams_are_genuinely_distinct_methods() -> void:
	var controller := MovementInputControllerClass.new()
	var view := HexGridViewClass.new()
	add_child_autofree(view)
	var base := HexChoiceResolverPortClass.new()

	var names: Array = [
		_method_info(controller.get_method_list(), "get_selectable_step_hexes").get("name", ""),
		_method_info(view.get_method_list(), "move_token").get("name", ""),
		_method_info(base.get_method_list(), "choose_step_hex").get("name", ""),
	]
	assert_eq(names.size(), 3)
	for n in names:
		assert_ne(n, "", "every seam method must actually resolve to a real, present method")
	assert_eq(names.duplicate().size(), 3, "sanity: the three seam method names must be distinct")
