extends GutTest
## tests/unit/test_dead_placeholder_removed_feat126.gd
##
## GUT test suite for FEAT-126 (US-004): Remove dead placeholder entry-point
## script. Verifies the superseded game/main.gd placeholder script (and its
## game/main.tscn scene) — which predates MainScene.gd/MainScene.tscn as the
## real, project.godot-wired composition root (FEAT-005/US-004) — has been
## deleted, and that no remaining file in the project references it.
## Resolves FIND-122.

# Files/paths that are allowed to mention "game/main.gd" or "game/main.tscn"
# textually without that being a real code reference: this test file itself
# (its own doc comment above), and any file under .godot/ (Godot's
# gitignored editor cache, regenerated locally and never committed).
const ALLOWED_SELF_PATH: String = "res://tests/unit/test_dead_placeholder_removed_feat126.gd"


# ── Criterion 1: game/main.gd no longer exists on disk ───────────────────────

func test_game_main_gd_no_longer_exists() -> void:
	assert_false(
		FileAccess.file_exists("res://game/main.gd"),
		"game/main.gd must be deleted — it is superseded by MainScene.gd as the composition root (FEAT-126 / FIND-122)"
	)


# ── Criterion 1: game/main.tscn no longer exists on disk ─────────────────────

func test_game_main_tscn_no_longer_exists() -> void:
	assert_false(
		FileAccess.file_exists("res://game/main.tscn"),
		"game/main.tscn must be deleted — it is superseded by MainScene.tscn as the composition root (FEAT-126 / FIND-122)"
	)


# ── Criterion 1: ResourceLoader can no longer resolve the deleted scene ──────

func test_game_main_tscn_no_longer_loadable() -> void:
	assert_false(
		ResourceLoader.exists("res://game/main.tscn"),
		"res://game/main.tscn must not be resolvable by ResourceLoader after removal (FEAT-126)"
	)


# ── Criterion 2: project.godot no longer references game/main.gd/tscn ───────

func test_project_godot_has_no_reference_to_deleted_placeholder() -> void:
	var content: String = _read_text("res://project.godot")
	assert_false(content.contains("game/main.gd"), "project.godot must not reference game/main.gd (FEAT-126)")
	assert_false(content.contains("game/main.tscn"), "project.godot must not reference game/main.tscn (FEAT-126)")


# ── Criterion 2: MainScene.tscn no longer references game/main.gd/tscn ──────

func test_main_scene_tscn_has_no_reference_to_deleted_placeholder() -> void:
	var content: String = _read_text("res://MainScene.tscn")
	assert_false(content.contains("game/main.gd"), "MainScene.tscn must not reference game/main.gd (FEAT-126)")
	assert_false(content.contains("game/main.tscn"), "MainScene.tscn must not reference game/main.tscn (FEAT-126)")


# ── Criterion 2: no other tracked .gd/.tscn file references the deleted path ─
## Walks the project directory tree (skipping .git/, .godot/, and addons/ —
## third-party GUT plugin code) looking for any remaining textual reference
## to "game/main.gd" or "game/main.tscn" in a .gd or .tscn file. This is the
## static-grep-equivalent regression guard, expressed as a GUT test so it
## runs as part of the normal `--gut-run-all` gate (test_criteria #1).

func test_no_remaining_gd_or_tscn_file_references_deleted_placeholder() -> void:
	var offending_paths: Array = []
	_scan_dir_for_references("res://", offending_paths)
	assert_eq(
		offending_paths,
		[],
		"no .gd/.tscn file should reference the deleted game/main.gd or game/main.tscn (FEAT-126): found in %s" % [offending_paths]
	)


func _scan_dir_for_references(path: String, offending_paths: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", "..", ".git", ".godot", "addons"]:
			entry = dir.get_next()
			continue
		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir_for_references(full_path, offending_paths)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			if full_path == ALLOWED_SELF_PATH:
				entry = dir.get_next()
				continue
			var content: String = _read_text(full_path)
			if content.contains("game/main.gd") or content.contains("game/main.tscn"):
				offending_paths.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content
