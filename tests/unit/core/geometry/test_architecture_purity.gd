extends GutTest
## tests/unit/core/geometry/test_architecture_purity.gd
##
## GUT test suite for FEAT-001 / US-001 — a lightweight, mechanical
## architecture-purity check for core/geometry/hex_pathfinder.gd
## (RISK-006, NFR-002).
##
## RISK-006 identifies "pathfinder architecture drifts out of the domain
## layer" (e.g. a future edit accidentally imports a Node/Resource type, or
## adds instance state that could accumulate an engine dependency) as a
## risk for this feature. This suite mitigates it exactly like the
## existing source-inspection checks in test_hex_coord.gd/test_hex_math.gd
## (ADR-001), plus one additional check specific to this feature's design:
## HexPathfinder must expose a STATIC-ONLY API (no instance methods, no
## `_init`), since a purely static namespace can never accumulate
## per-instance state that could later smuggle in an engine/Node reference.
##
## Verifies:
##   1. hex_pathfinder.gd contains no Node/Control/CanvasItem inheritance.
##   2. hex_pathfinder.gd defines no engine lifecycle callbacks
##      (_ready/_process/_physics_process).
##   3. hex_pathfinder.gd's public entry point, find_path(), is declared
##      `static func` (the static-only API RISK-006 mitigation).
##   4. Every `func` declared in hex_pathfinder.gd is a `static func` --
##      no instance methods (and therefore no instance state) exist at all.

const HEX_PATHFINDER_PATH: String = "res://core/geometry/hex_pathfinder.gd"


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the architecture-purity check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ── Criterion 1: no Node/Control/CanvasItem inheritance (ADR-001) ───────────

func test_source_has_no_node_control_inheritance() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "hex_pathfinder.gd must not extend Node (ADR-001, RISK-006)")
	assert_false(content.contains("extends Control"), "hex_pathfinder.gd must not extend Control (ADR-001, RISK-006)")
	assert_false(
		content.contains("extends CanvasItem"),
		"hex_pathfinder.gd must not extend CanvasItem (ADR-001, RISK-006)"
	)


func test_source_has_no_other_engine_type_references() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return
	# Zero Node/engine imports (per this feature's description): no
	# reference to Resource-backed data types or scene-tree APIs should
	# ever appear in the pure domain pathfinder.
	assert_false(content.contains("Node2D"), "hex_pathfinder.gd must not reference Node2D (RISK-006)")
	assert_false(content.contains("get_tree("), "hex_pathfinder.gd must not reference the scene tree (RISK-006)")
	assert_false(content.contains("add_child("), "hex_pathfinder.gd must not manipulate the scene tree (RISK-006)")


# ── Criterion 2: no engine lifecycle callbacks (ADR-001) ────────────────────

func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "hex_pathfinder.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "hex_pathfinder.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"hex_pathfinder.gd must not define _physics_process() (ADR-001)"
	)


# ── Criterion 3: public entry point is static ───────────────────────────────

func test_find_path_is_declared_static() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return
	assert_true(
		content.contains("static func find_path("),
		"HexPathfinder.find_path() must be declared 'static func' (RISK-006 static-only API)"
	)


# ── Criterion 4: every func in the file is static (static-only API) ────────

func test_every_function_in_file_is_static() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return

	var offending_lines: Array = []
	for line in content.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("func ") and not trimmed.begins_with("static func "):
			offending_lines.append(trimmed)

	assert_true(
		offending_lines.is_empty(),
		"hex_pathfinder.gd must expose ONLY static methods (RISK-006); found non-static: %s" % [offending_lines]
	)


func test_file_defines_no_init_and_therefore_no_instance_state() -> void:
	var content: String = _read_source(HEX_PATHFINDER_PATH)
	if content.is_empty():
		return
	assert_false(
		content.contains("func _init("),
		"hex_pathfinder.gd must not define _init() -- static-only API must have no instance state (RISK-006)"
	)
