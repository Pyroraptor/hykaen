extends GutTest
## tests/unit/test_core_purity_source_scan.gd
##
## Architecture fitness-function tests for FEAT-002 (US-003 / NFR-002,
## NFR-003; addresses RISK-003 / RISK-007):
##   - core/application/new_game_factory.gd (this feature's own file) must
##     never extend a Godot scene-tree type (Node/Control/CanvasItem) and
##     must never reference the CurrentGameState identifier (the
##     infrastructure/adapter-layer autoload a LATER feature introduces).
##   - EVERY *.gd file under core/ (domain + application layers) must never
##     reference the CurrentGameState identifier at all -- core/ has zero
##     knowledge that CurrentGameState exists; it is an outward-only,
##     infrastructure-layer concern (see NewGameFactory's own file-level
##     doc and the design notes' dependency diagram).
##
## RISK-003/RISK-007 mitigation: a blind substring search for
## "CurrentGameState" would both (a) false-positive on an unrelated
## identifier that merely CONTAINS the substring (e.g. a hypothetical
## "CurrentGameStateSnapshotBuilder") and (b) is easy to reason about
## informally as "good enough" while still missing the fact that what
## actually matters is whether the WHOLE identifier token
## "CurrentGameState" appears, not a fragment of a longer one. This suite
## instead parses real GDScript syntax:
##   - `extends <Identifier>` / `extends "quoted/path.gd"` clauses are
##     matched via the SAME bare (non-string) extends regex this project's
##     other purity gates already establish (ci/check_domain_purity.sh,
##     infrastructure/static_check.gd), so a quoted extends chain (this
##     project's script-inheritance convention) is never mistaken for an
##     engine dependency.
##   - `class_name <Identifier>` declarations are parsed the same way.
##   - "does this file reference the CurrentGameState identifier" is
##     answered with a WORD-BOUNDARY regex (`\bCurrentGameState\b`), which
##     matches the identifier as a whole token -- including inside a
##     `preload("res://autoload/current_game_state.gd")` line, a
##     `class_name`/type annotation, a doc comment, or any bare
##     `CurrentGameState.foo()` call -- while correctly NOT matching a
##     longer identifier that merely starts with the same characters (e.g.
##     "CurrentGameStateSnapshotBuilder" would NOT trigger a false
##     positive), since a word boundary requires a non-identifier character
##     (or start/end of string) immediately after "State".

const NEW_GAME_FACTORY_PATH: String = "res://core/application/new_game_factory.gd"
const CORE_DIR: String = "res://core"

## Same bare (non-string) `extends Node|Control|CanvasItem` pattern already
## established by infrastructure/static_check.gd / ci/check_domain_purity.sh
## -- a quoted `extends "res://...gd"` script-inheritance chain never
## matches this pattern.
const _FORBIDDEN_EXTENDS_PATTERN: String = "^[ \\t]*extends[ \\t]+(Node|Control|CanvasItem)\\b"

## `extends <BareIdentifier>` (unquoted) -- used to extract WHATEVER type
## new_game_factory.gd actually extends, so it can be asserted equal to
## "RefCounted" positively (not merely "not one of the forbidden 3").
const _EXTENDS_IDENTIFIER_PATTERN: String = "^[ \\t]*extends[ \\t]+([A-Za-z_][A-Za-z0-9_]*)\\b"

## `class_name <Identifier>` -- parsed the same way, so a future accidental
## rename to "CurrentGameState" itself would be caught by the identifier
## scan below rather than silently passing a bare substring check.
const _CLASS_NAME_PATTERN: String = "^[ \\t]*class_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)\\b"

## Word-boundary identifier-token match for the banned CurrentGameState
## reference -- matches the whole token wherever it appears (extends,
## class_name, preload(), a bare expression, or a comment), but never a
## longer identifier that merely starts with the same characters.
const _CURRENT_GAME_STATE_TOKEN_PATTERN: String = "\\bCurrentGameState\\b"


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the source-scan fitness test" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _compiled(pattern: String) -> RegEx:
	var regex := RegEx.new()
	var compile_err := regex.compile(pattern)
	assert_eq(compile_err, OK, "pattern must compile: %s" % pattern)
	return regex


## Recursively collects every *.gd file path under `dir_path` (res://-style),
## mirroring infrastructure/static_check.gd's own _scan_dir() traversal.
func _collect_gd_files(dir_path: String, out_paths: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_gd_files(full_path, out_paths)
			elif entry.ends_with(".gd"):
				out_paths.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


# ══════════════════════════════════════════════════════════════════════════
# new_game_factory.gd — no Node/Control/CanvasItem extends (NFR-003)
# ══════════════════════════════════════════════════════════════════════════

func test_new_game_factory_has_no_forbidden_scene_tree_extends() -> void:
	var content: String = _read_source(NEW_GAME_FACTORY_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_FORBIDDEN_EXTENDS_PATTERN)
	var violations: Array = []
	var line_number: int = 0
	for line in content.split("\n"):
		line_number += 1
		if regex.search(line) != null:
			violations.append("%s:%d: %s" % [NEW_GAME_FACTORY_PATH, line_number, line.strip_edges()])

	assert_true(
		violations.is_empty(),
		"new_game_factory.gd must not extend Node/Control/CanvasItem (NFR-003, RISK-003); found: %s" % [violations]
	)


func test_new_game_factory_extends_ref_counted_positively() -> void:
	var content: String = _read_source(NEW_GAME_FACTORY_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_EXTENDS_IDENTIFIER_PATTERN)
	var matched_identifier: String = ""
	for line in content.split("\n"):
		var result := regex.search(line)
		if result != null:
			matched_identifier = result.get_string(1)
			break

	assert_eq(
		matched_identifier, "RefCounted",
		"new_game_factory.gd's parsed extends clause must be exactly 'RefCounted' (NFR-003 static-service purity)"
	)


func test_new_game_factory_class_name_is_new_game_factory() -> void:
	var content: String = _read_source(NEW_GAME_FACTORY_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_CLASS_NAME_PATTERN)
	var matched_identifier: String = ""
	for line in content.split("\n"):
		var result := regex.search(line)
		if result != null:
			matched_identifier = result.get_string(1)
			break

	assert_eq(
		matched_identifier, "NewGameFactory",
		"new_game_factory.gd's parsed class_name declaration must be exactly 'NewGameFactory'"
	)


# ══════════════════════════════════════════════════════════════════════════
# new_game_factory.gd — no CurrentGameState identifier reference (NFR-002)
# ══════════════════════════════════════════════════════════════════════════

func test_new_game_factory_has_no_current_game_state_identifier_reference() -> void:
	var content: String = _read_source(NEW_GAME_FACTORY_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_CURRENT_GAME_STATE_TOKEN_PATTERN)
	var matches: Array = regex.search_all(content)
	var offending_tokens: Array = []
	for m in matches:
		offending_tokens.append(m.get_string())

	assert_true(
		offending_tokens.is_empty(),
		(
			"new_game_factory.gd must not reference the CurrentGameState identifier anywhere "
			+ "(NFR-002, RISK-007) -- it is an infrastructure-layer concern introduced by a LATER "
			+ "feature; found %d occurrence(s)"
		) % offending_tokens.size()
	)


# ══════════════════════════════════════════════════════════════════════════
# ALL core/*.gd files — no CurrentGameState identifier reference anywhere
# under the domain+application layer (NFR-002)
# ══════════════════════════════════════════════════════════════════════════

func test_no_core_gd_file_references_current_game_state_identifier() -> void:
	var gd_files: Array = []
	_collect_gd_files(CORE_DIR, gd_files)
	assert_false(gd_files.is_empty(), "core/ must contain at least one *.gd file for this scan to be meaningful")

	var regex := _compiled(_CURRENT_GAME_STATE_TOKEN_PATTERN)
	var violations: Array = []

	for file_path in gd_files:
		var content: String = _read_source(file_path)
		if content.is_empty():
			continue
		var matches: Array = regex.search_all(content)
		if not matches.is_empty():
			violations.append("%s (%d occurrence(s))" % [file_path, matches.size()])

	assert_true(
		violations.is_empty(),
		(
			"no core/*.gd file may reference the CurrentGameState identifier (NFR-002) -- "
			+ "core/ is the domain+application layer and must never depend on the "
			+ "infrastructure-layer CurrentGameState autoload; offending files: %s"
		) % [violations]
	)


# ══════════════════════════════════════════════════════════════════════════
# Sanity checks proving the word-boundary pattern actually discriminates a
# whole-token match from a longer identifier that merely shares a prefix
# (the exact false-positive/false-negative distinction RISK-003/RISK-007
# call out) -- guards against this suite's own regex silently degrading
# back into an unintentional blind substring match.
# ══════════════════════════════════════════════════════════════════════════

func test_current_game_state_token_pattern_matches_bare_identifier_only() -> void:
	var regex := _compiled(_CURRENT_GAME_STATE_TOKEN_PATTERN)

	assert_not_null(regex.search("CurrentGameState.data"), "must match a bare CurrentGameState identifier")
	assert_not_null(
		regex.search("var x = CurrentGameState"),
		"must match a bare CurrentGameState identifier at end-of-line (word boundary against EOL)"
	)
	assert_null(
		regex.search("CurrentGameStateSnapshotBuilder"),
		"must NOT match a longer identifier that merely starts with the same characters (RISK-003)"
	)
	assert_null(
		regex.search("MyCurrentGameStateHolder"),
		"must NOT match a longer identifier that merely contains the token as a non-boundary substring"
	)


func test_forbidden_extends_pattern_ignores_quoted_extends_chains() -> void:
	var regex := _compiled(_FORBIDDEN_EXTENDS_PATTERN)

	assert_null(
		regex.search("extends \"res://core/rules/random_port.gd\""),
		"a quoted extends \"res://...gd\" script-inheritance chain must never be flagged"
	)
	assert_not_null(regex.search("extends Node"), "a bare 'extends Node' clause must be flagged")
	assert_not_null(regex.search("extends Control"), "a bare 'extends Control' clause must be flagged")
	assert_not_null(regex.search("extends CanvasItem"), "a bare 'extends CanvasItem' clause must be flagged")
