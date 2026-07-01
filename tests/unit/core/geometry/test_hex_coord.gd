extends GutTest
## tests/unit/core/geometry/test_hex_coord.gd
##
## GUT test suite for FEAT-001 / US-001 — HexCoord value object
## (core/geometry/hex_coord.gd).
##
## Verifies:
##   1. HexCoord(q, r) stores the axial coordinates as constructed.
##   2. The derived cube coordinate s = -q - r is computed correctly (and
##      the cube-coordinate invariant q + r + s == 0 always holds).
##   3. equals() provides value equality by (q, r).
##   4. Static source-inspection check (ADR-001): hex_coord.gd contains no
##      Node/Control/CanvasItem inheritance and no engine lifecycle
##      callbacks (_ready/_process/_physics_process).

const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const HEX_COORD_PATH: String = "res://core/geometry/hex_coord.gd"


# ── Criterion 1: stores axial (q, r) as constructed ──────────────────────────

func test_stores_axial_q_and_r() -> void:
	var h = HexCoordClass.new(3, -2)
	assert_eq(h.q, 3, "HexCoord.q must equal the constructor argument")
	assert_eq(h.r, -2, "HexCoord.r must equal the constructor argument")


func test_default_constructor_is_origin() -> void:
	var h = HexCoordClass.new()
	assert_eq(h.q, 0, "Default HexCoord.q must be 0")
	assert_eq(h.r, 0, "Default HexCoord.r must be 0")


# ── Criterion 2: derives cube coordinate s = -q - r ──────────────────────────

func test_derives_cube_s_correctly() -> void:
	var h = HexCoordClass.new(3, -2)
	assert_eq(h.get_s(), -1, "s must equal -q - r; -3 - (-2) = -1")


func test_derives_cube_s_for_origin() -> void:
	var h = HexCoordClass.new(0, 0)
	assert_eq(h.get_s(), 0, "s must be 0 at the origin")


func test_cube_coordinates_always_sum_to_zero() -> void:
	for pair in [[0, 0], [5, -3], [-4, 7], [10, 10], [-6, -1]]:
		var h = HexCoordClass.new(pair[0], pair[1])
		assert_eq(
			h.q + h.r + h.get_s(), 0,
			"Cube coordinate invariant q + r + s == 0 must hold for q=%d, r=%d" % [pair[0], pair[1]]
		)


func test_get_s_recomputes_after_field_mutation() -> void:
	var h = HexCoordClass.new(1, 1)
	assert_eq(h.get_s(), -2, "Initial s must be -2")
	h.q = 5
	assert_eq(h.get_s(), -6, "s must be recomputed from the current q/r, never stored stale")


# ── Criterion 3: value equality ───────────────────────────────────────────────

func test_equals_true_for_same_coords() -> void:
	var a = HexCoordClass.new(1, 2)
	var b = HexCoordClass.new(1, 2)
	assert_true(a.equals(b), "HexCoords with identical q/r must be equal")


func test_equals_false_for_different_coords() -> void:
	var a = HexCoordClass.new(1, 2)
	var b = HexCoordClass.new(2, 1)
	assert_false(a.equals(b), "HexCoords with different q/r must not be equal")


func test_equals_false_for_null() -> void:
	var a = HexCoordClass.new(1, 2)
	assert_false(a.equals(null), "equals(null) must return false, not crash")


# ── Criterion 4: static check — no Node/Control/engine-lifecycle (ADR-001) ───

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the ADR-001 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_control_inheritance() -> void:
	var content: String = _read_source(HEX_COORD_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "hex_coord.gd must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "hex_coord.gd must not extend Control (ADR-001)")
	assert_false(content.contains("extends CanvasItem"), "hex_coord.gd must not extend CanvasItem (ADR-001)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(HEX_COORD_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "hex_coord.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "hex_coord.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"hex_coord.gd must not define _physics_process() (ADR-001)"
	)
