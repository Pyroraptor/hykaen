## infrastructure/static_check.gd — StaticCheck (FEAT-009 / US-009, ADR-001)
##
## Infrastructure/tooling adapter (Clean Architecture): a GDScript-native
## static-analysis utility asserting core/ domain-purity — zero BARE
## (non-string) `extends Node` / `extends Control` clauses anywhere under a
## given directory tree, which would smuggle a Godot scene-tree dependency
## into the domain+application layer (ADR-001). A quoted
## `extends "res://...gd"` script-inheritance chain (this project's
## established adapter pattern — e.g. every concrete port implementation
## in this codebase) is intentionally NEVER flagged.
##
## Complements the standalone shell-invokable ci/check_domain_purity.sh gate
## with an in-engine, GDScript-callable equivalent, so a GUT suite (this
## feature's own tests/unit/test_reaction_window.gd, test_criteria #5) can
## assert domain purity directly, without shelling out to bash.
##
## This file lives in infrastructure/ (an adapter/tooling layer) and is
## NEVER imported by core/ itself — core/ has zero knowledge this checker
## exists, a one-way, outward-only dependency matching every other adapter
## in this project.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance (this tool practices what it checks).
##
## Usage example:
##   var checker := StaticCheck.new()
##   var violations: Array = checker.scan_for_engine_imports("res://core")
##   # violations -> [] when core/ is clean; else one Dictionary per
##   # offending line: {"file": String, "line_number": int, "line": String}

class_name StaticCheck
extends RefCounted

## Regex matching a bare `extends Node`/`extends Control` clause at the
## start of a line (leading whitespace ignored). Deliberately does NOT
## match a quoted `extends "res://...gd"` chain.
const _FORBIDDEN_PATTERN: String = "^[ \\t]*extends[ \\t]+(Node|Control)\\b"


## scan_for_engine_imports(root_path) -> Array[Dictionary]
##
## Recursively scans every *.gd file under `root_path` (a res://-style or
## absolute filesystem directory path) for a bare `extends Node`/
## `extends Control` clause. Returns an Array of
## {"file": String, "line_number": int, "line": String} entries — one per
## violation, in traversal order — empty when the tree is clean.
func scan_for_engine_imports(root_path: String) -> Array:
	var violations: Array = []
	var regex := RegEx.new()
	var compile_error: int = regex.compile(_FORBIDDEN_PATTERN)
	if compile_error != OK:
		push_error("StaticCheck: failed to compile forbidden-pattern regex")
		return violations
	_scan_dir(root_path, regex, violations)
	return violations


## _scan_dir(dir_path, regex, violations) -> void — recurses into every
## subdirectory of dir_path, delegating each *.gd file to _scan_file().
## Silently no-ops (no violations added) when dir_path cannot be opened —
## matching this project's established best-effort filesystem-access
## convention (see tests/ci/test_static_checks.gd's _make_temp_dir()).
func _scan_dir(dir_path: String, regex: RegEx, violations: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_scan_dir(full_path, regex, violations)
			elif entry.ends_with(".gd"):
				_scan_file(full_path, regex, violations)
		entry = dir.get_next()
	dir.list_dir_end()


## _scan_file(file_path, regex, violations) -> void — appends one violation
## entry per matching line found in `file_path`.
func _scan_file(file_path: String, regex: RegEx, violations: Array) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return

	var line_number: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		line_number += 1
		if regex.search(line) != null:
			violations.append({"file": file_path, "line_number": line_number, "line": line})
	f.close()
