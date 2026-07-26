extends GutTest
## tests/unit/core/geometry/test_architecture_purity.gd
##
## GUT test suite for FEAT-001 / US-001 (extended by FEAT-002 / US-002) — a
## lightweight, mechanical architecture-purity check for
## core/geometry/hex_pathfinder.gd AND core/geometry/encounter_tile_adapter.gd
## (RISK-006, NFR-002).
##
## RISK-006 identifies "pathfinder architecture drifts out of the domain
## layer" (e.g. a future edit accidentally imports a Node/Resource type, or
## adds instance state that could accumulate an engine dependency) as a
## risk for this feature. This suite mitigates it exactly like the
## existing source-inspection checks in test_hex_coord.gd/test_hex_math.gd
## (ADR-001), plus one additional check specific to this feature's design:
## both files must expose a STATIC-ONLY API (no instance methods, no
## `_init`), since a purely static namespace can never accumulate
## per-instance state that could later smuggle in an engine/Node reference.
##
## FEAT-002 (US-002 / FR-004) extends this suite to
## core/geometry/encounter_tile_adapter.gd, the new EncounterTileAdapter
## infrastructure adapter that bridges HexTileDataResource's authored data
## to HexPathfinder's PassabilityQuery/MoveCostQuery Callable port shape.
## Both files are checked identically (RISK-006 covers this new file too)
## by iterating the SAME criteria over both paths, rather than duplicating
## each test function per file.
##
## Verifies, for EACH of hex_pathfinder.gd and encounter_tile_adapter.gd:
##   1. contains no Node/Control/CanvasItem inheritance.
##   2. defines no engine lifecycle callbacks (_ready/_process/_physics_process).
##   3. its public entry point(s) are declared `static func` (the static-only
##      API RISK-006 mitigation) -- find_path() for hex_pathfinder.gd,
##      make_is_passable()/make_move_cost() for encounter_tile_adapter.gd.
##   4. every `func` declared in the file is a `static func` -- no instance
##      methods (and therefore no instance state) exist at all.

const HEX_PATHFINDER_PATH: String = "res://core/geometry/hex_pathfinder.gd"
const ENCOUNTER_TILE_ADAPTER_PATH: String = "res://core/geometry/encounter_tile_adapter.gd"

## Every source file this suite checks, paired with the `static func`
## entry-point signature(s) each one is expected to expose (criterion 3).
const _CHECKED_FILES: Array = [
	{"path": "res://core/geometry/hex_pathfinder.gd", "entry_points": ["static func find_path("]},
	{
		"path": "res://core/geometry/encounter_tile_adapter.gd",
		"entry_points": ["static func make_is_passable(", "static func make_move_cost("],
	},
]


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
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue
		assert_false(content.contains("extends Node"), "%s must not extend Node (ADR-001, RISK-006)" % path)
		assert_false(content.contains("extends Control"), "%s must not extend Control (ADR-001, RISK-006)" % path)
		assert_false(
			content.contains("extends CanvasItem"),
			"%s must not extend CanvasItem (ADR-001, RISK-006)" % path
		)


func test_source_has_no_other_engine_type_references() -> void:
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue
		# Zero Node/engine imports (per this feature's description): no
		# reference to Resource-backed data types or scene-tree APIs should
		# ever appear in the pure domain pathfinder or its infrastructure adapter.
		assert_false(content.contains("Node2D"), "%s must not reference Node2D (RISK-006)" % path)
		assert_false(content.contains("get_tree("), "%s must not reference the scene tree (RISK-006)" % path)
		assert_false(content.contains("add_child("), "%s must not manipulate the scene tree (RISK-006)" % path)


# ── Criterion 2: no engine lifecycle callbacks (ADR-001) ────────────────────

func test_source_has_no_engine_lifecycle_callbacks() -> void:
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue
		assert_false(content.contains("func _ready("), "%s must not define _ready() (ADR-001)" % path)
		assert_false(content.contains("func _process("), "%s must not define _process() (ADR-001)" % path)
		assert_false(
			content.contains("func _physics_process("),
			"%s must not define _physics_process() (ADR-001)" % path
		)


# ── Criterion 3: public entry point(s) are static ───────────────────────────

func test_public_entry_points_are_declared_static() -> void:
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue
		for entry_point in entry["entry_points"]:
			assert_true(
				content.contains(entry_point),
				"%s must declare '%s' (RISK-006 static-only API)" % [path, entry_point]
			)


# ── Criterion 4: every func in the file is static (static-only API) ────────

func test_every_function_in_file_is_static() -> void:
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue

		var offending_lines: Array = []
		for line in content.split("\n"):
			var trimmed: String = line.strip_edges()
			if trimmed.begins_with("func ") and not trimmed.begins_with("static func "):
				offending_lines.append(trimmed)

		assert_true(
			offending_lines.is_empty(),
			"%s must expose ONLY static methods (RISK-006); found non-static: %s" % [path, offending_lines]
		)


func test_file_defines_no_init_and_therefore_no_instance_state() -> void:
	for entry in _CHECKED_FILES:
		var path: String = entry["path"]
		var content: String = _read_source(path)
		if content.is_empty():
			continue
		assert_false(
			content.contains("func _init("),
			"%s must not define _init() -- static-only API must have no instance state (RISK-006)" % path
		)
