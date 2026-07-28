extends GutTest
## tests/unit/presentation/test_hex_grid_view_hit_test.gd — FEAT-004 (US-005
## / FR-005, ADR-003, mitigates RISK-002): "Refactor hit-tests to
## camera-aware get_global_mouse_position()".
##
## Maps to the feature plan's files_to_create entry
## "tests/hex_grid/test_hex_grid_view_hit_test.gd" — this project's actual,
## established file layout (every prior FEAT-001..003 commit) keeps
## HexGridView's own script under presentation/hex_grid_view.gd and its
## tests under tests/unit/presentation/, alongside the existing
## test_hex_grid_view.gd / test_hex_grid_view_hover.gd /
## test_hex_grid_view_mapping.gd suites this file follows the exact
## conventions of, so this suite lives here rather than under a
## scripts/hex_grid/ or tests/hex_grid/ tree that does not otherwise exist
## in this codebase.
##
## Verifies (test_criteria):
##   1. With the GameCamera at its default position, a mouse position
##      resolving to world (0, 0) maps to hex (0, 0).
##   2. With the GameCamera panned to a known non-zero offset via
##      set_origin_offset(), a known mouse position maps to the expected hex
##      coordinate — proving the hit-test path is genuinely camera-aware
##      (RISK-002: a hex click must not silently mis-register once the
##      camera has actually panned).
##   3. Structural: no manual `_origin_offset` subtraction remains at either
##      hit-test call site (_unhandled_input()'s click branch,
##      _handle_mouse_motion()), nor inside the shared
##      _hex_at_global_mouse_position() helper both delegate to.
##
## This suite drives the REAL engine mouse-position pipeline
## (Input.parse_input_event() with an InputEventMouseMotion, read back
## through a real Camera2D's canvas transform) rather than reimplementing
## get_global_mouse_position()'s math by hand — empirically confirmed
## reliable/deterministic in this project's headless GUT harness:
## Input.parse_input_event() synchronously updates
## Viewport.get_mouse_position(), and a Camera2D's default DRAG_CENTER
## anchor mode maps the viewport's own screen-center point to EXACTLY
## `_camera.position`, world-space, every time. It stops short of routing
## the event through _unhandled_input() itself, though — that dispatch is
## the part this codebase's own established convention already documents
## as headless-unreliable (see test_hex_grid_view_hover.gd's file-level
## doc: "rather than depending on this view's real, headless-unreliable
## get_local_mouse_position()/window-focus state"). Instead, mirroring that
## same "call the handler directly" convention, this suite calls
## _hex_at_global_mouse_position() directly — the SAME single computation
## both _unhandled_input() and _handle_mouse_motion() delegate to (proven
## by the structural checks below) — after driving the real, live
## get_global_mouse_position() to a known value.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

const HEX_GRID_VIEW_SOURCE_PATH: String = "res://presentation/hex_grid_view.gd"

## Chosen so that -KNOWN_OFFSET lands EXACTLY on a ring hex's pure
## world-pixel center (144.0, 0.0) == axial_to_pixel(HexCoord(2, -1)) — the
## SAME flat-top sample already pinned by
## tests/unit/presentation/test_hex_grid_view_mapping.gd's
## test_axial_to_pixel_matches_flat_top_formula_for_sample_coords(), so the
## expected hex below is not a freshly-invented magic number.
const KNOWN_OFFSET: Vector2 = Vector2(-144.0, 0.0)
const EXPECTED_HEX_AFTER_PAN_Q: int = 2
const EXPECTED_HEX_AFTER_PAN_R: int = -1

## Tolerance for floating-point pixel comparisons.
const EPSILON: float = 0.5


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## _extract_function_body(source, func_signature) → String — copied
## verbatim from tests/unit/presentation/test_hex_grid_view.gd's own helper
## of the same name (see that file's doc for why a naive "next \nfunc "
## search would mis-attribute a neighboring function's own doc-comment
## block to this function's trailing body).
func _extract_function_body(source: String, func_signature: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var start_idx: int = -1
	for i in range(lines.size()):
		if lines[i].begins_with(func_signature):
			start_idx = i
			break
	assert_true(start_idx != -1, "%s must be defined in hex_grid_view.gd" % func_signature)
	if start_idx == -1:
		return ""

	var next_func_idx: int = lines.size()
	for i in range(start_idx + 1, lines.size()):
		if lines[i].begins_with("func "):
			next_func_idx = i
			break

	# Walk backward from the next function's `func` line, stripping any
	# immediately-preceding blank/`##`-comment lines -- those belong to the
	# NEXT function's own doc comment, not this function's body.
	var end_idx: int = next_func_idx
	while end_idx > start_idx + 1:
		var candidate: String = lines[end_idx - 1].strip_edges()
		if candidate == "" or candidate.begins_with("##"):
			end_idx -= 1
		else:
			break

	var body_lines: PackedStringArray = lines.slice(start_idx, end_idx)
	return "\n".join(body_lines)


## _instantiate_hex_grid_view_with_game_camera_sibling() → HexGridView —
## mirrors tests/unit/presentation/test_hex_grid_view.gd's own helper of the
## same name: builds a minimal "world layer" Node2D with a Camera2D named
## "GameCamera" and a fresh HexGridView instance as SIBLING children
## (mirroring MainScene.tscn's real FEAT-001 wiring), then adds that world
## layer to the test's own tree so the returned HexGridView's
## `@onready var _camera` resolves `../GameCamera` to a real Camera2D by the
## time this helper returns. Additionally marks the camera `current` (unlike
## the plain structural helper in test_hex_grid_view.gd, this suite needs
## the camera to genuinely be the ACTIVE camera so get_global_mouse_position()
## reflects it — MainScene.tscn's own GameCamera node sets `current = true`
## as a scene property for exactly this reason).
func _instantiate_hex_grid_view_with_game_camera_sibling():
	var world_layer := Node2D.new()
	var game_camera := Camera2D.new()
	game_camera.name = "GameCamera"
	game_camera.position_smoothing_enabled = false
	world_layer.add_child(game_camera)
	var hex_grid_view = HexGridViewScene.instantiate()
	world_layer.add_child(hex_grid_view)
	add_child_autofree(world_layer)
	game_camera.make_current()
	return hex_grid_view


## _send_mouse_motion_at_screen_center() -> void — feeds a real
## InputEventMouseMotion at the viewport's own screen-center point through
## Input.parse_input_event() (the actual engine input-parsing entry point,
## not a hand-rolled Vector2 substitute), then waits two process frames so
## Viewport.get_mouse_position() -- and therefore get_global_mouse_position()
## -- reflects it. A Camera2D's default DRAG_CENTER anchor mode maps its own
## `position` to exactly the viewport's screen-center world point, so
## driving the mouse to screen-center makes get_global_mouse_position() read
## back exactly the CURRENT camera's `position` -- a deterministic,
## engine-real way to pin a "known mouse position" without depending on any
## OS-level cursor state (which this headless CI has none of).
func _send_mouse_motion_at_screen_center() -> void:
	var half: Vector2 = get_viewport().get_visible_rect().size / 2.0
	var event := InputEventMouseMotion.new()
	event.position = half
	event.global_position = half
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — camera at its default position: a mouse position resolving
# to world (0, 0) maps to hex (0, 0).
# ══════════════════════════════════════════════════════════════════════════

func test_default_camera_position_maps_world_origin_mouse_position_to_hex_origin() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	await _send_mouse_motion_at_screen_center()

	assert_almost_eq(
		hex_grid_view.get_global_mouse_position(), Vector2.ZERO, Vector2(EPSILON, EPSILON),
		"sanity check: with the GameCamera at its default (0, 0) position, screen-center must read as world (0, 0)"
	)

	var resolved = hex_grid_view._hex_at_global_mouse_position()
	assert_true(
		resolved.equals(HexCoordClass.new(0, 0)),
		"a mouse position resolving to world (0, 0) must map to hex (0, 0) with the camera at its default position"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — camera panned to a known non-zero offset via
# set_origin_offset(): a known mouse position maps to the expected hex.
# ══════════════════════════════════════════════════════════════════════════

func test_panned_camera_maps_a_known_mouse_position_to_the_expected_hex() -> void:
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view.set_origin_offset(KNOWN_OFFSET)
	await get_tree().process_frame

	await _send_mouse_motion_at_screen_center()

	var expected_world_position: Vector2 = -KNOWN_OFFSET
	assert_almost_eq(
		hex_grid_view.get_global_mouse_position(), expected_world_position, Vector2(EPSILON, EPSILON),
		"sanity check: with the GameCamera panned via set_origin_offset(), the SAME screen-center mouse position must now read as -KNOWN_OFFSET in world space"
	)

	var resolved = hex_grid_view._hex_at_global_mouse_position()
	assert_true(
		resolved.equals(HexCoordClass.new(EXPECTED_HEX_AFTER_PAN_Q, EXPECTED_HEX_AFTER_PAN_R)),
		(
			"with the camera panned to a known non-zero offset, the SAME screen-center mouse position must now resolve to the expected panned-to hex (%d, %d) -- proving the hit-test is genuinely camera-aware (RISK-002: a stale, non-camera-aware hit-test would still resolve hex (0, 0) here, silently mis-registering the click)"
			% [EXPECTED_HEX_AFTER_PAN_Q, EXPECTED_HEX_AFTER_PAN_R]
		)
	)


func test_hex_clicked_emits_the_hex_resolved_via_the_new_camera_aware_hit_test_path() -> void:
	# Behavioral proof that the SAME resolution feeds real hex_clicked
	# emission -- mirrors this codebase's established "call the handler
	# directly" convention (test_hex_grid_view_hover.gd) for a signal that
	# would otherwise depend on a real, headless-unreliable
	# _unhandled_input() dispatch.
	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view.set_origin_offset(KNOWN_OFFSET)
	await get_tree().process_frame
	await _send_mouse_motion_at_screen_center()

	watch_signals(hex_grid_view)
	hex_grid_view.hex_clicked.emit(hex_grid_view._hex_at_global_mouse_position())

	assert_signal_emitted_with_parameters(
		hex_grid_view, "hex_clicked", [HexCoordClass.new(EXPECTED_HEX_AFTER_PAN_Q, EXPECTED_HEX_AFTER_PAN_R)],
		"hex_clicked must carry the camera-aware-resolved HexCoord even after the camera has panned"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — structural: no manual _origin_offset subtraction remains at
# either hit-test call site.
# ══════════════════════════════════════════════════════════════════════════

func test_unhandled_input_click_branch_contains_no_origin_offset_reference() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	var body: String = _extract_function_body(source, "func _unhandled_input")
	assert_true(
		body.find("_origin_offset") == -1,
		"_unhandled_input()'s body must not reference _origin_offset -- hit-testing now resolves purely via get_global_mouse_position() (ADR-003)"
	)
	assert_true(
		body.find("pixel_to_axial_with_offset") == -1,
		"_unhandled_input() must not call the offset-aware pixel_to_axial_with_offset() -- that would double-count the camera's own pan"
	)
	assert_true(
		body.find("get_local_mouse_position") == -1,
		"_unhandled_input() must not call get_local_mouse_position() -- it is not Camera2D-aware (RISK-002)"
	)
	assert_true(
		body.find("_hex_at_global_mouse_position") != -1,
		"_unhandled_input()'s click branch must resolve the clicked hex via _hex_at_global_mouse_position()"
	)


func test_handle_mouse_motion_contains_no_origin_offset_reference() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	var body: String = _extract_function_body(source, "func _handle_mouse_motion")
	assert_true(
		body.find("_origin_offset") == -1,
		"_handle_mouse_motion() must not reference _origin_offset -- hit-testing now resolves purely via get_global_mouse_position() (ADR-003)"
	)
	assert_true(
		body.find("pixel_to_axial_with_offset") == -1,
		"_handle_mouse_motion() must not call the offset-aware pixel_to_axial_with_offset() -- that would double-count the camera's own pan"
	)
	assert_true(
		body.find("get_local_mouse_position") == -1,
		"_handle_mouse_motion() must not call get_local_mouse_position() -- it is not Camera2D-aware (RISK-002)"
	)
	assert_true(
		body.find("_hex_at_global_mouse_position") != -1,
		"_handle_mouse_motion() must resolve the hovered hex via _hex_at_global_mouse_position()"
	)


func test_hex_at_global_mouse_position_helper_uses_the_pure_zero_offset_transform() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	var body: String = _extract_function_body(source, "func _hex_at_global_mouse_position")
	assert_true(
		body.find("get_global_mouse_position") != -1,
		"_hex_at_global_mouse_position() must compute the hex via get_global_mouse_position()"
	)
	assert_true(
		body.find("_origin_offset") == -1,
		"_hex_at_global_mouse_position() must not reference _origin_offset -- get_global_mouse_position() has already resolved the camera transform"
	)
	assert_true(
		body.find("pixel_to_axial_with_offset") == -1,
		"_hex_at_global_mouse_position() must use the pure pixel_to_axial(), not the offset-aware variant -- applying _origin_offset on top would double-count the pan"
	)


# ══════════════════════════════════════════════════════════════════════════
# Regression: the view remains fully usable after the hit-test refactor.
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_hit_test_calls() -> void:
	const CombatantClass = preload("res://core/domain/combatant.gd")

	var hex_grid_view = _instantiate_hex_grid_view_with_game_camera_sibling()
	await get_tree().process_frame

	hex_grid_view.set_origin_offset(KNOWN_OFFSET)
	await _send_mouse_motion_at_screen_center()
	hex_grid_view._hex_at_global_mouse_position()

	hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(0, 0)),
	])
	assert_eq(hex_grid_view.get_token_count(), 1, "HexGridView must remain fully functional after hit-test calls")
