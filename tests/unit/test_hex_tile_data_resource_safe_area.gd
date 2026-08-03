extends GutTest
## tests/unit/test_hex_tile_data_resource_safe_area.gd
##
## GUT unit tests for FEAT-002 (US-002 / FR-007, NFR-006; ADR-004):
## data/tiles/hex_tile_data_resource.gd — HexTileDataResource gains an
## `is_safe_area: bool = true` stub field.
##
## Scope note: this feature authors the field now (avoiding a future schema
## migration for the rest-mechanics steel thread's extension point) but
## intentionally leaves it UNENFORCED this iteration. No use case, guard, or
## controller anywhere in the codebase should read/branch on it yet.
##
## Test criteria covered:
##   1. HexTileDataResource.is_safe_area defaults to true on a new instance.
##   2. Existing HexTileDataResource tests pass unmodified (verified by
##      running the full suite; this file adds coverage without touching
##      tests/unit/data/tiles/test_hex_tile_data_resource.gd).
##   3. No enforcement/guard logic references is_safe_area anywhere in the
##      codebase this feature — asserted here via a source-scan of the
##      non-test tree.

const HexTileDataResource = preload("res://data/tiles/hex_tile_data_resource.gd")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: default-construction value
# ══════════════════════════════════════════════════════════════════════════════

func test_is_safe_area_defaults_to_true() -> void:
	var res := HexTileDataResource.new()
	assert_eq(res.is_safe_area, true, "HexTileDataResource.is_safe_area must default to true")


func test_is_safe_area_is_typed_bool() -> void:
	var res := HexTileDataResource.new()
	assert_eq(typeof(res.is_safe_area), TYPE_BOOL, "is_safe_area must be typed as bool")


func test_is_safe_area_can_be_set_false() -> void:
	var res := HexTileDataResource.new()
	res.is_safe_area = false
	assert_eq(res.is_safe_area, false, "is_safe_area must be settable to false")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: no enforcement/guard logic reads is_safe_area yet (ADR-004)
# ══════════════════════════════════════════════════════════════════════════════

func test_no_enforcement_logic_references_is_safe_area_outside_this_stub() -> void:
	# Scan the non-test source tree for any reference to is_safe_area other
	# than its own declaration in hex_tile_data_resource.gd. This feature is
	# an authored-but-unread stub (ADR-004) -- any other hit means a future
	# feature jumped ahead of scope.
	var allowed_path := "res://data/tiles/hex_tile_data_resource.gd"
	var roots := ["res://core", "res://application", "res://infrastructure", "res://presentation", "res://autoload"]
	var offending_files: Array = []

	for root in roots:
		_scan_dir_for_is_safe_area(root, allowed_path, offending_files)

	assert_eq(
		offending_files.size(), 0,
		"is_safe_area must not be referenced by any enforcement/guard logic yet (ADR-004); found in: %s" % [offending_files]
	)


func _scan_dir_for_is_safe_area(dir_path: String, allowed_path: String, offending_files: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir_for_is_safe_area(full_path, allowed_path, offending_files)
		elif entry.ends_with(".gd") and full_path != allowed_path:
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file != null:
				var content: String = file.get_as_text()
				file.close()
				if content.contains("is_safe_area"):
					offending_files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
