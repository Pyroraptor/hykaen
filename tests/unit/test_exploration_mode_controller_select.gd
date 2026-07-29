extends GutTest
## tests/unit/test_exploration_mode_controller_select.gd — FEAT-005
## (US-005 / FR-005, ADR-003, mitigates RISK-003).
##
## GUT suite for presentation/exploration_mode_controller.gd's
## `_select_party_member(id)` helper — the SelectPartyMemberUseCase
## (design notes: "given a candidate id, sets SelectionState, calls
## ISelectionRenderer.set_selected_combatant ... This use case is the
## SINGLE writer of selected_party_member_id."). FEAT-002 already
## introduced this helper and routed boot()'s own auto-select through it;
## this feature's own, NEW contribution is test_criteria #3 below — a
## permanent, static-analysis-style source-scan regression guard proving
## there is exactly ONE write site to `selected_party_member_id` in the
## whole file (inside the helper itself), so RISK-003 (the two backing
## selection caches silently desyncing via a future direct assignment
## slipping in at some other call site) can never regress unnoticed. The
## other three test_criteria are re-asserted here too (this feature's own
## files_to_create entry is a *new* file, not an edit to FEAT-002's
## tests/unit/test_exploration_mode_controller_selection.gd), so this
## suite is fully self-contained.
##
## test_criteria covered:
##   1. _select_party_member(id) updates selected_party_member_id and
##      calls hex_grid_view.set_selected_combatant(id) EXACTLY ONCE.
##   2. Boot-time auto-select of the first party member routes through
##      _select_party_member (verified via a call-count spy on the
##      helper — the same "extends <real script path>, override, call
##      super." spy convention this codebase already established, see
##      tests/unit/test_dodge_reaction.gd's own SpyActionEconomy).
##   3. Source-scan test (regex over exploration_mode_controller.gd)
##      asserts ZERO direct assignments to selected_party_member_id
##      outside `_select_party_member` (the new, permanent RISK-003
##      guard this feature exists to add).
##   4. _select_party_member is a no-op-safe call when hex_grid_view is
##      null (no exception).

const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const CONTROLLER_SOURCE_PATH: String = "res://presentation/exploration_mode_controller.gd"

## Whole-token assignment pattern: `selected_party_member_id` followed by
## optional whitespace then a single `=` NOT itself followed by another
## `=` (which would make it a `==` comparison, not an assignment) and NOT
## preceded by `!`/`<`/`>` (handled naturally below, since those operators
## put a non-whitespace character directly before the `=`, which this
## pattern doesn't scan for at all — it only cares what's captured
## starting at the identifier itself). A word boundary (`\b`) before the
## identifier ensures a longer identifier that merely shares the suffix
## can never false-positive-match (mirrors tests/unit/
## test_core_purity_source_scan.gd's own established word-boundary
## convention).
const _ASSIGNMENT_PATTERN: String = "\\bselected_party_member_id\\b\\s*=\\s*[^=]"

const _FUNC_NAME_PATTERN: String = "^[ \\t]*func[ \\t]+([A-Za-z_][A-Za-z0-9_]*)"

const _HELPER_FUNC_NAME: String = "_select_party_member"


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## _FakeHexGridView — a hand-written fake exposing the `hex_clicked`/
## `hex_hovered` signals boot() connects to (mirrors tests/gut/
## test_exploration_mode_controller.gd's own _FakeHexGridView convention),
## plus a real, stateful set_selected_combatant()/get_selected_combatant()
## round-trip so this suite can assert the SelectionRenderPort contract
## directly, and a call-count list so "exactly once" is provable.
class _FakeHexGridView:
	extends RefCounted
	signal hex_clicked(hex_coord)
	signal hex_hovered(hex_coord)

	var _selected_combatant_id: String = ""
	var set_selected_combatant_calls: Array = []

	func set_path_overlay(_path: Array, _color: Color) -> void:
		pass

	func clear_overlays() -> void:
		pass

	func set_selected_combatant(id: String) -> void:
		set_selected_combatant_calls.append(id)
		_selected_combatant_id = id

	func get_selected_combatant() -> String:
		return _selected_combatant_id


## _FakeHexCombatant — minimal duck-typed stand-in for boot()'s
## `hex_combatants` entries (`combatant_id`/`hex_coord`).
class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord


## _SelectPartyMemberSpy — a REAL ExplorationModeController that records
## every _select_party_member() invocation via GDScript's normal virtual
## dispatch (boot() calls `_select_party_member(...)` as a plain
## unqualified method call, so it resolves against this subclass's
## override, not the base script's own definition) — proving boot()'s
## auto-select genuinely routes through the helper rather than merely
## producing the same end state via a coincidental direct assignment.
class _SelectPartyMemberSpy:
	extends "res://presentation/exploration_mode_controller.gd"

	var select_party_member_call_count: int = 0
	var select_party_member_call_ids: Array = []

	func _select_party_member(id: String) -> void:
		select_party_member_call_count += 1
		select_party_member_call_ids.append(id)
		super._select_party_member(id)


func _make_controller(hex_grid_view) -> ExplorationModeControllerClass:
	var controller := ExplorationModeControllerClass.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — _select_party_member(id) updates state and calls
# hex_grid_view.set_selected_combatant(id) EXACTLY ONCE.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_updates_state_and_calls_render_port_exactly_once() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"_select_party_member(id) must set selected_party_member_id to id"
	)
	assert_eq(
		hex_grid_view.set_selected_combatant_calls.size(), 1,
		"_select_party_member(id) must call hex_grid_view.set_selected_combatant(id) EXACTLY ONCE"
	)
	assert_eq(
		hex_grid_view.set_selected_combatant_calls, ["hero_a"],
		"the single set_selected_combatant() call must be invoked with id"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"hex_grid_view.get_selected_combatant() must reflect id immediately after _select_party_member(id)"
	)


func test_select_party_member_called_twice_calls_render_port_exactly_twice_total() -> void:
	# Sanity complement to "exactly once": two DISTINCT selections must
	# produce two DISTINCT set_selected_combatant() calls, never a single
	# coalesced/skipped call.
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller._select_party_member("hero_a")
	controller._select_party_member("hero_b")

	assert_eq(
		hex_grid_view.set_selected_combatant_calls, ["hero_a", "hero_b"],
		"each _select_party_member(id) call must produce its own set_selected_combatant(id) call, in order"
	)
	assert_eq(controller.selected_party_member_id, "hero_b")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — boot-time auto-select routes through _select_party_member().
# ══════════════════════════════════════════════════════════════════════════

func test_boot_time_auto_select_invokes_select_party_member_helper() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _SelectPartyMemberSpy.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})

	controller.boot([
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0)),
		_FakeHexCombatant.new("hero_b", HexCoordClass.new(1, 0)),
	])

	assert_eq(
		controller.select_party_member_call_count, 1,
		"boot()'s initial auto-select must invoke _select_party_member() exactly once (only for the first seeded party member)"
	)
	assert_eq(
		controller.select_party_member_call_ids, ["hero_a"],
		"boot()'s auto-select must call _select_party_member() with the FIRST seeded hex_combatants entry's id"
	)
	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"boot() must still default selected_party_member_id to the first seeded party member"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"boot()'s auto-select, routed through the helper, must also update the HexGridView selection-render cache"
	)


func test_boot_time_auto_select_never_calls_helper_when_already_selected() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _SelectPartyMemberSpy.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})
	controller.selected_party_member_id = "hero_b"

	controller.boot([
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0)),
		_FakeHexCombatant.new("hero_b", HexCoordClass.new(1, 0)),
	])

	assert_eq(
		controller.select_party_member_call_count, 0,
		"boot() must never invoke _select_party_member() when selected_party_member_id was already assigned"
	)
	assert_eq(controller.selected_party_member_id, "hero_b")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (NEW for this feature) — source-scan: zero direct assignments
# to selected_party_member_id anywhere outside _select_party_member().
# ══════════════════════════════════════════════════════════════════════════

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


## Scans `content` line-by-line, tracking which `func` body each line falls
## inside (reset on every `^func <name>` line), skipping comment lines
## entirely (so this feature's own doc-comments that literally quote
## `selected_party_member_id = id` as prose are never mistaken for a real
## assignment), and collecting every line matching `_ASSIGNMENT_PATTERN`
## whose enclosing function is NOT `_select_party_member` (module-level/
## no enclosing function, e.g. the `var selected_party_member_id: String =
## ""` declaration itself, is also allowed through unflagged: the
## assignment pattern requires `=` to directly follow the identifier
## (modulo whitespace), which a typed `var` declaration's `: String =`
## never satisfies — proven by test_assignment_pattern_ignores_the_typed_
## var_declaration below).
func _find_violations_outside_helper(content: String) -> Array:
	var regex := _compiled(_ASSIGNMENT_PATTERN)
	var func_name_regex := _compiled(_FUNC_NAME_PATTERN)

	var violations: Array = []
	var current_func: String = ""
	var line_number: int = 0

	for line in content.split("\n"):
		line_number += 1
		var trimmed: String = line.strip_edges()

		var func_match := func_name_regex.search(line)
		if func_match != null:
			current_func = func_match.get_string(1)

		if trimmed.begins_with("#"):
			continue

		if current_func == _HELPER_FUNC_NAME:
			continue

		if regex.search(line) != null:
			violations.append("%s:%d (func '%s'): %s" % [CONTROLLER_SOURCE_PATH, line_number, current_func, trimmed])

	return violations


func test_no_direct_assignment_to_selected_party_member_id_outside_helper() -> void:
	var content: String = _read_source(CONTROLLER_SOURCE_PATH)
	if content.is_empty():
		return

	var violations: Array = _find_violations_outside_helper(content)

	assert_true(
		violations.is_empty(),
		(
			"selected_party_member_id must be assigned ONLY inside _select_party_member() (US-005 / FR-005, "
			+ "ADR-003, mitigates RISK-003) -- found direct assignment(s) outside the helper: %s"
		) % [violations]
	)


func test_helper_itself_does_assign_selected_party_member_id() -> void:
	# Sanity complement: the scan above trivially passes on a file that
	# assigns selected_party_member_id NOWHERE at all. Prove the helper
	# function's body is actually reached and DOES contain the (allowed)
	# assignment, so an empty violations list is meaningful evidence the
	# write path exists and is centralized -- not evidence it was deleted.
	var content: String = _read_source(CONTROLLER_SOURCE_PATH)
	if content.is_empty():
		return

	var regex := _compiled(_ASSIGNMENT_PATTERN)
	var func_name_regex := _compiled(_FUNC_NAME_PATTERN)

	var current_func: String = ""
	var found_assignment_in_helper: bool = false

	for line in content.split("\n"):
		var func_match := func_name_regex.search(line)
		if func_match != null:
			current_func = func_match.get_string(1)

		if current_func == _HELPER_FUNC_NAME and regex.search(line) != null:
			found_assignment_in_helper = true
			break

	assert_true(
		found_assignment_in_helper,
		"_select_party_member() must itself contain the (sole, allowed) assignment to selected_party_member_id"
	)


# ── Regex-discrimination sanity checks (mirrors tests/unit/
#    test_core_purity_source_scan.gd's own established convention) ─────────

func test_assignment_pattern_matches_a_bare_direct_assignment() -> void:
	var regex := _compiled(_ASSIGNMENT_PATTERN)

	assert_not_null(
		regex.search("\tselected_party_member_id = id"),
		"must match a bare direct assignment"
	)
	assert_not_null(
		regex.search('selected_party_member_id = "hero_a"'),
		"must match a bare direct assignment to a string literal"
	)


func test_assignment_pattern_ignores_equality_comparisons() -> void:
	var regex := _compiled(_ASSIGNMENT_PATTERN)

	assert_null(
		regex.search('if selected_party_member_id == "" or scenario_session == null:'),
		"must NOT match an == equality comparison (not an assignment)"
	)


func test_assignment_pattern_ignores_the_typed_var_declaration() -> void:
	var regex := _compiled(_ASSIGNMENT_PATTERN)

	assert_null(
		regex.search('var selected_party_member_id: String = ""'),
		"must NOT match the module-level typed `var name: Type = default` declaration itself " +
		"(': Type' sits between the identifier and '=', so the pattern's directly-adjacent '=' never matches)"
	)


func test_assignment_pattern_ignores_read_only_usages() -> void:
	var regex := _compiled(_ASSIGNMENT_PATTERN)

	assert_null(
		regex.search("if not scenario_session.party_hex_positions.has(selected_party_member_id):"),
		"must NOT match a read-only usage as a function argument"
	)
	assert_null(
		regex.search("var start_hex = scenario_session.party_hex_positions[selected_party_member_id]"),
		"must NOT match a read-only usage as a subscript key (the '=' belongs to a DIFFERENT identifier, start_hex)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — _select_party_member is a no-op-safe call when
# hex_grid_view is null (no exception).
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_is_a_safe_no_op_state_update_without_a_hex_grid_view() -> void:
	var controller := ExplorationModeControllerClass.new()

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"_select_party_member(id) must still update selected_party_member_id when _hex_grid_view is null"
	)
