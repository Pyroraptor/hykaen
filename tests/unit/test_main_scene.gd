extends GutTest
## tests/unit/test_main_scene.gd
##
## GUT test suite for FEAT-041: game/main.tscn Validated Minimal Entry-Point Scene.
## Validates all test criteria for US-003 / DEF-003.


# ── Criterion 1: game/main.tscn is text-format (.tscn not .scn) ──────────────

func test_main_tscn_first_line_begins_with_gd_scene() -> void:
	var file := FileAccess.open("res://game/main.tscn", FileAccess.READ)
	assert_not_null(file, "game/main.tscn must be readable")
	if file == null:
		return
	var first_line := file.get_line()
	file.close()
	assert_true(
		first_line.begins_with("[gd_scene"),
		"game/main.tscn first line must begin with '[gd_scene' — text-format required (FEAT-041)"
	)


# ── Criterion 2: game/main.gd contains 'extends Node' ───────────────────────

func test_main_gd_extends_node() -> void:
	var file := FileAccess.open("res://game/main.gd", FileAccess.READ)
	assert_not_null(file, "game/main.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("extends Node"),
		"game/main.gd must contain 'extends Node' (FEAT-041)"
	)


# ── Criterion 2: game/main.gd defines _ready() ───────────────────────────────

func test_main_gd_defines_ready_method() -> void:
	var file := FileAccess.open("res://game/main.gd", FileAccess.READ)
	assert_not_null(file, "game/main.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("func _ready()"),
		"game/main.gd must define func _ready() (FEAT-041)"
	)


# ── Criterion 2: game/main.gd has no DisplayServer calls ─────────────────────

func test_main_gd_no_display_server_calls() -> void:
	var file := FileAccess.open("res://game/main.gd", FileAccess.READ)
	assert_not_null(file, "game/main.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("DisplayServer"),
		"game/main.gd must not call DisplayServer — unsafe in --headless mode (FEAT-041)"
	)


# ── Criterion 2: game/main.gd has no Input calls ─────────────────────────────

func test_main_gd_no_input_calls() -> void:
	var file := FileAccess.open("res://game/main.gd", FileAccess.READ)
	assert_not_null(file, "game/main.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("Input."),
		"game/main.gd must not call Input methods — unsafe in --headless mode (FEAT-041)"
	)


# ── Criterion 3: ResourceLoader.load('res://game/main.tscn') returns non-null ─

func test_main_tscn_loads_as_packed_scene() -> void:
	var res = ResourceLoader.load("res://game/main.tscn")
	assert_not_null(res, "ResourceLoader.load('res://game/main.tscn') must return non-null (FEAT-041)")
	if res == null:
		return
	assert_is(res, PackedScene, "game/main.tscn must load as a PackedScene instance (FEAT-041)")


# ── Criterion 4: load('res://game/main.gd').new() instantiates without error ──

func test_main_gd_can_be_instantiated() -> void:
	var MainScript = load("res://game/main.gd")
	assert_not_null(MainScript, "load('res://game/main.gd') must return non-null (FEAT-041)")
	if MainScript == null:
		return
	var instance = MainScript.new()
	assert_not_null(instance, "game/main.gd .new() must return a non-null Node instance (FEAT-041)")
	if instance != null:
		instance.free()


# ── Criterion 6: game/main.gd lives under game/ not core/ ────────────────────
# Domain-purity linter scope is core/ only — game/ is NOT checked.
# This test verifies the linter would NOT flag game/main.gd for 'extends Node'
# because the linter only scans core/.

func test_main_gd_is_under_game_not_core() -> void:
	var file_in_core := FileAccess.open("res://core/main.gd", FileAccess.READ)
	assert_null(
		file_in_core,
		"main.gd must NOT exist in core/ — it belongs under game/ (ADR-001 scope: core/ only)"
	)
	var file_in_game := FileAccess.open("res://game/main.gd", FileAccess.READ)
	assert_not_null(
		file_in_game,
		"game/main.gd must exist under game/ (FEAT-041)"
	)
	if file_in_game != null:
		file_in_game.close()
