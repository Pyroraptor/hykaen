extends GutTest
## tests/infrastructure/test_mainscene_no_battlefield_refs.gd — FEAT-001
## (US-001 / FR-005, iteration D "UI Consolidation + Movement UX").
##
## Static, grep-style regression guard: proves MainScene.tscn/.gd no longer
## reference ANY node/script/scene from the removed duplicate
## scenes/battlefield/* UI stack (HexBattlefield, its nested
## CombatantReadout/TurnOrderWidget children, ResultScreen,
## StrikeInputController, EndTurnController/end_turn_controller) -- the
## duplication iteration-D's P0-2 removes in favor of the single kept
## presentation/* stack (ADR-002: one composition root).
##
## Deliberately text-based (not a runtime/scene-tree check -- see
## tests/infrastructure/test_mainscene_headless_boot.gd for the runtime
## complement) so it also catches a reintroduced reference sitting only in a
## doc comment or an as-yet-uninstantiated preload, not merely a live node.
##
## Care is taken so this does not false-positive on the KEPT
## presentation/result_screen_view.gd stack: "ResultScreen" is a literal
## prefix of "ResultScreenView" (and "result_screen" of
## "result_screen_view"), so the checks below explicitly exclude the "View"/
## "_view" suffixed kept identifiers rather than banning the bare substring.

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"
const MAIN_SCENE_TSCN_PATH: String = "res://MainScene.tscn"

## Removed-stack identifiers with no overlap against any KEPT presentation/*
## identifier -- a plain substring search is unambiguous for all of these.
const _UNAMBIGUOUS_BANNED_TERMS: Array = [
	"scenes/battlefield",
	"HexBattlefield",
	"CombatantReadout",
	"TurnOrderWidget",
	"StrikeInputController",
	"EndTurnController",
	"end_turn_controller",
	"strike_input_controller",
	"hex_battlefield",
	"turn_order_widget",
]

## "ResultScreen"/"result_screen" are also banned, but as a PREFIX of the
## KEPT "ResultScreenView"/"result_screen_view" identifiers -- checked
## separately below via a negated-suffix regex rather than a bare
## `.contains()` call, so a live `result_screen_view` reference is never
## mistaken for the removed `result_screen`/`ResultScreen`.
const _RESULT_SCREEN_NOT_VIEW_PATTERN: String = "[Rr]esult_?[Ss]creen(?!_?[Vv]iew)"


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# MainScene.gd — no unambiguous banned identifier/path may appear anywhere
# in the script source, including doc comments (a comment-only reference is
# still stale documentation of a removed stack and is exactly the kind of
# drift this regression guard exists to catch).
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_gd_has_no_unambiguous_battlefield_references() -> void:
	var content: String = _read_file(MAIN_SCENE_SCRIPT_PATH)
	for term in _UNAMBIGUOUS_BANNED_TERMS:
		assert_false(
			content.contains(term),
			"MainScene.gd must not reference '%s' -- the duplicate scenes/battlefield/* UI stack was removed (FEAT-001 / US-001)" % term
		)


func test_mainscene_gd_has_no_result_screen_references_that_are_not_result_screen_view() -> void:
	var content: String = _read_file(MAIN_SCENE_SCRIPT_PATH)
	var regex := RegEx.new()
	var compile_err := regex.compile(_RESULT_SCREEN_NOT_VIEW_PATTERN)
	assert_eq(compile_err, OK, "the ResultScreen-not-View regex must compile")
	var matches: Array = regex.search_all(content)
	var offending: Array = []
	for m in matches:
		offending.append(m.get_string())
	assert_eq(
		offending.size(), 0,
		"MainScene.gd must not reference the removed scenes/battlefield/ResultScreen.gd (only the kept "
		+ "presentation/result_screen_view.gd's ResultScreenView/result_screen_view identifiers may remain); found: %s" % [offending]
	)


# ══════════════════════════════════════════════════════════════════════════
# MainScene.tscn — same guard over the scene file's text (ext_resource
# declarations + node instances).
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_tscn_has_no_unambiguous_battlefield_references() -> void:
	var content: String = _read_file(MAIN_SCENE_TSCN_PATH)
	for term in _UNAMBIGUOUS_BANNED_TERMS:
		assert_false(
			content.contains(term),
			"MainScene.tscn must not reference '%s' -- the duplicate scenes/battlefield/* UI stack was removed (FEAT-001 / US-001)" % term
		)


func test_mainscene_tscn_has_no_result_screen_references_that_are_not_result_screen_view() -> void:
	var content: String = _read_file(MAIN_SCENE_TSCN_PATH)
	var regex := RegEx.new()
	var compile_err := regex.compile(_RESULT_SCREEN_NOT_VIEW_PATTERN)
	assert_eq(compile_err, OK, "the ResultScreen-not-View regex must compile")
	var matches: Array = regex.search_all(content)
	var offending: Array = []
	for m in matches:
		offending.append(m.get_string())
	assert_eq(
		offending.size(), 0,
		"MainScene.tscn must not instance the removed scenes/battlefield/ResultScreen.tscn (only the kept "
		+ "presentation/result_screen_view.tscn's ResultScreenView node may remain); found: %s" % [offending]
	)


# ══════════════════════════════════════════════════════════════════════════
# Sanity check that this suite's regex is well-formed (proves the negative
# lookahead genuinely distinguishes "ResultScreen" from "ResultScreenView"
# rather than accidentally banning every occurrence).
# ══════════════════════════════════════════════════════════════════════════

func test_result_screen_not_view_pattern_matches_bare_result_screen_only() -> void:
	var regex := RegEx.new()
	regex.compile(_RESULT_SCREEN_NOT_VIEW_PATTERN)

	assert_not_null(regex.search("res://scenes/battlefield/ResultScreen.gd"), "the pattern must match the bare, removed 'ResultScreen' identifier")
	assert_not_null(regex.search("var result_screen = $ResultScreen"), "the pattern must match the bare, removed 'result_screen' identifier")
	assert_null(regex.search("res://presentation/result_screen_view.gd"), "the pattern must NOT match the kept 'result_screen_view' identifier")
	assert_null(regex.search("@onready var result_screen_view = $ResultScreenView"), "the pattern must NOT match the kept 'ResultScreenView'/'result_screen_view' identifiers")


# ══════════════════════════════════════════════════════════════════════════
# Positive control: the kept presentation/* identifiers this composition
# root DOES still wire remain present, so a future accidental over-deletion
# (e.g. stripping ResultScreenView instead of ResultScreen) is also caught.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_gd_still_wires_the_kept_presentation_stack() -> void:
	var content: String = _read_file(MAIN_SCENE_SCRIPT_PATH)
	for kept_term in ["hex_grid_view", "status_panel_view", "initiative_view", "event_log_view", "end_turn_control", "result_screen_view", "movement_input_controller", "turn_controller"]:
		assert_true(
			content.contains(kept_term),
			"MainScene.gd must still wire the kept presentation/* identifier '%s' -- this feature only removes the duplicate stack, not the surviving one" % kept_term
		)


func test_mainscene_tscn_still_instances_the_kept_presentation_stack() -> void:
	var content: String = _read_file(MAIN_SCENE_TSCN_PATH)
	for kept_term in ["HexGridView", "StatusPanelView", "InitiativeView", "EventLogView", "TurnController", "EndTurnControl", "ResultScreenView"]:
		assert_true(
			content.contains(kept_term),
			"MainScene.tscn must still instance the kept presentation/* node '%s' -- this feature only removes the duplicate stack, not the surviving one" % kept_term
		)
