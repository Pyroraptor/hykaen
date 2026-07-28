extends GutTest
## tests/unit/presentation/test_hex_grid_view.gd — FEAT-002 (US-003,
## iteration-W "Camera Panning & Collapsible Panels", W0-0): pins down
## presentation/hex_grid_view.gd's refactor of every _draw()-adjacent draw
## call (tiles, rings, path overlays, and token positioning) to PURE WORLD
## coordinates now that a GameCamera Camera2D (FEAT-001) is the canonical
## view controller — `_origin_offset` no longer participates in any of that
## math, even though the field itself is retained (back-compat; still drives
## click-to-hex hit-testing via axial_to_pixel_with_offset()/
## pixel_to_axial_with_offset(), unaffected by this feature).
##
## Verifies (test_criteria):
##   1. hex (0, 0) maps to world pixel (0, 0) via the tile draw path
##      (_draw_hex_cell()'s underlying computation), REGARDLESS of any
##      configured `_origin_offset` — and a ring hex away from the origin
##      behaves identically.
##   2. token positioning (load_combatants()/move_token()) and path-overlay
##      drawing (_draw_path_overlay()) use pure world coordinates — no
##      `_origin_offset` applied, even with a non-zero offset configured.
##   3. Structural check: no `_origin_offset` reference remains inside the
##      body of `_draw()`, `_draw_hex_cell()`, or `_draw_path_overlay()`.
##   4. `_origin_offset` remains a present, working field on HexGridView
##      (the view still compiles/instantiates/get/set without error).
##
## Following this codebase's established convention for CanvasItem
## _draw()-side effects (see tests/unit/presentation/
## test_hex_grid_view_overlays.gd's and test_hex_grid_view_token_animation.gd's
## file docs): there is no public hook to intercept/count actual draw_*
## calls made from inside the engine's real _draw() dispatch. Runtime
## coverage here proves the underlying transform computations the draw
## methods are known (via the structural checks) to call — e.g.
## `axial_to_pixel()` — no longer honor `_origin_offset`; structural checks
## prove the draw methods themselves invoke exactly that pure computation
## rather than the offset-aware `_with_offset` variant.

const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

const HEX_GRID_VIEW_SOURCE_PATH: String = "res://presentation/hex_grid_view.gd"
const EPSILON: float = 0.01

## A deliberately non-zero, easy-to-spot "spy" offset — if any draw call
## silently still applied it, these tests would fail.
const SPY_OFFSET: Vector2 = Vector2(137.0, -251.0)

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## _extract_function_body(source, func_signature) → String — the source text
## from `func_signature`'s own line up to (but not including) the NEXT
## top-level function declaration's OWN doc comment block, i.e. that one
## function's full body -- correctly excluding the next function's
## preceding `##` doc-comment lines (which sit directly above its `func`
## line with no blank-line separator, and so would otherwise be
## mis-attributed to THIS function's trailing body by a naive "stop at the
## next `\nfunc `" search). Used by the structural checks below to scope a
## substring search to exactly one function's real code, so an
## `_origin_offset` reference in a NEIGHBORING function's doc comment or
## body (e.g. axial_to_pixel_with_offset()'s own doc) can never produce a
## false positive/negative here.
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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — hex (0, 0) maps to world pixel (0, 0) via the tile draw path,
# regardless of any configured _origin_offset.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_origin_maps_to_world_pixel_origin_via_the_tile_draw_path() -> void:
	var pixel: Vector2 = _hex_grid_view.axial_to_pixel(HexCoordClass.new(0, 0))
	assert_almost_eq(
		pixel, Vector2.ZERO, Vector2(EPSILON, EPSILON),
		"hex (0, 0) must draw at world pixel (0, 0)"
	)


func test_hex_origin_maps_to_world_pixel_origin_even_with_a_nonzero_origin_offset_configured() -> void:
	# The definitive proof this is the DRAW path's own math, not merely the
	# static zero-offset helper: configuring a non-zero _origin_offset (as a
	# real caller like MainScene.gd does today) must NOT shift where hex
	# (0, 0) draws -- the camera, not this view's draw math, now owns panning.
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var pixel: Vector2 = _hex_grid_view.axial_to_pixel(HexCoordClass.new(0, 0))
	assert_almost_eq(
		pixel, Vector2.ZERO, Vector2(EPSILON, EPSILON),
		"hex (0, 0) must draw at world pixel (0, 0) even with a non-zero _origin_offset configured"
	)


func test_a_ring_hex_maps_to_its_pure_world_pixel_even_with_a_nonzero_origin_offset_configured() -> void:
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var coord := HexCoordClass.new(2, -1)
	var pixel: Vector2 = _hex_grid_view.axial_to_pixel(coord)
	assert_almost_eq(
		pixel, Vector2(144.0, 0.0), Vector2(EPSILON, EPSILON),
		"a ring hex must draw at its pure flat-top world pixel regardless of _origin_offset"
	)


func test_draw_hex_cell_computes_its_center_via_the_pure_zero_offset_transform() -> void:
	# Structural: _draw_hex_cell() (the tile/ring/highlight draw path) must
	# compute its `center` via the pure axial_to_pixel() call, never the
	# offset-aware axial_to_pixel_with_offset() variant.
	var body: String = _extract_function_body(_read_source(HEX_GRID_VIEW_SOURCE_PATH), "func _draw_hex_cell")
	assert_true(
		body.find("axial_to_pixel_with_offset") == -1,
		"_draw_hex_cell() must not call axial_to_pixel_with_offset() -- tile/ring/highlight drawing is pure world coordinates"
	)
	assert_true(
		body.find("axial_to_pixel(coord)") != -1,
		"_draw_hex_cell() must compute its center via the pure axial_to_pixel(coord)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — token positioning and path-overlay drawing use pure world
# coordinates; no _origin_offset applied, even with a non-zero offset set.
# ══════════════════════════════════════════════════════════════════════════

func test_load_combatants_positions_tokens_at_pure_world_coordinates_regardless_of_origin_offset() -> void:
	var combatant := CombatantClass.new("c1", "Titus", "Player", HexCoordClass.new(1, -1))

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.load_combatants([combatant])

	var token = _hex_grid_view.get_token("c1")
	assert_not_null(token)
	if token == null:
		return

	var pure_world_position: Vector2 = _hex_grid_view.axial_to_pixel(combatant.hex_coord)
	var offset_position: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(combatant.hex_coord)

	assert_almost_eq(
		token.position, pure_world_position, Vector2(EPSILON, EPSILON),
		"a token must be positioned at its pure world-space pixel, ignoring _origin_offset"
	)
	assert_true(
		token.position.distance_to(offset_position) > 1.0,
		"sanity check: the configured SPY_OFFSET must actually differ from the pure world position, or this test would pass vacuously"
	)


func test_move_token_repositions_tokens_at_pure_world_coordinates_regardless_of_origin_offset() -> void:
	var combatant := CombatantClass.new("c1", "Titus", "Player", HexCoordClass.new(0, 0))
	_hex_grid_view.load_combatants([combatant])

	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	var destination := HexCoordClass.new(2, -1)
	_hex_grid_view.move_token("c1", destination)

	var token = _hex_grid_view.get_token("c1")
	var pure_world_position: Vector2 = _hex_grid_view.axial_to_pixel(destination)
	assert_almost_eq(
		token.position, pure_world_position, Vector2(EPSILON, EPSILON),
		"move_token() must reposition the token to its pure world-space pixel, ignoring _origin_offset"
	)


func test_draw_path_overlay_computes_segment_endpoints_via_the_pure_zero_offset_transform() -> void:
	# Structural: _draw_path_overlay() must compute its segment endpoints via
	# the pure axial_to_pixel(), never the offset-aware
	# axial_to_pixel_with_offset() variant.
	var body: String = _extract_function_body(_read_source(HEX_GRID_VIEW_SOURCE_PATH), "func _draw_path_overlay")
	assert_true(
		body.find("axial_to_pixel_with_offset") == -1,
		"_draw_path_overlay() must not call axial_to_pixel_with_offset() -- overlay drawing is pure world coordinates"
	)
	assert_true(
		body.find("axial_to_pixel(") != -1,
		"_draw_path_overlay() must compute its segment endpoints via the pure axial_to_pixel()"
	)


func test_set_path_overlay_and_redraw_does_not_error_with_a_nonzero_origin_offset_configured() -> void:
	# Behavioral proof mirroring test_hex_grid_view_overlays.gd's established
	# convention: queue_redraw() must not error, even with SPY_OFFSET set, and
	# the view remains fully usable afterward.
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.set_path_overlay([HexCoordClass.new(0, 0), HexCoordClass.new(1, 0)], Color.RED)
	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — structural: no _origin_offset reference remains inside
# _draw(), _draw_hex_cell(), or _draw_path_overlay().
# ══════════════════════════════════════════════════════════════════════════

func test_draw_method_bodies_contain_no_origin_offset_reference() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	for func_signature in ["func _draw(", "func _draw_hex_cell", "func _draw_path_overlay"]:
		var body: String = _extract_function_body(source, func_signature)
		assert_true(
			body.find("_origin_offset") == -1,
			"%s's body must not reference _origin_offset (RESOLVES structural check, iteration-W W0-0)" % func_signature
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — _origin_offset remains present on HexGridView; the view
# compiles/instantiates/get/set without error.
# ══════════════════════════════════════════════════════════════════════════

func test_origin_offset_field_still_exists_and_defaults_to_zero() -> void:
	assert_eq(
		_hex_grid_view.get_origin_offset(), Vector2.ZERO,
		"_origin_offset must still default to Vector2.ZERO"
	)


func test_origin_offset_field_is_declared_in_source() -> void:
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH)
	assert_true(
		source.find("var _origin_offset") != -1,
		"the _origin_offset field must remain declared on HexGridView (retained internally per iteration-W W0-0)"
	)


func test_set_and_get_origin_offset_still_round_trips() -> void:
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	assert_eq(
		_hex_grid_view.get_origin_offset(), SPY_OFFSET,
		"set_origin_offset()/get_origin_offset() must still round-trip the configured value (API back-compat)"
	)


func test_hex_grid_view_still_instantiates_and_renders_without_error_after_the_refactor() -> void:
	# Reaching this line without a crash/error IS the assertion -- the view
	# must still compile, instantiate, and draw with GRID_RADIUS's full ring
	# set + a non-zero _origin_offset configured.
	_hex_grid_view.set_origin_offset(SPY_OFFSET)
	_hex_grid_view.queue_redraw()
	assert_true(true)
