## presentation/title_screen.gd — TitleScreen (FEAT-008 / US-006; FR-006,
## NFR-005, NFR-006; ADR-002)
##
## PRESENTATION layer (Clean Architecture / ADR-001): the user-facing entry
## point of the steel thread. Wires three button contracts, each of which
## seeds/loads CurrentGameState.data and then transitions to
## res://MainScene.tscn:
##
##   - New Game — NewGameFactory.create_prologue_state() -> assigned onto
##     CurrentGameState.data -> transition. No error path reaches the
##     player: NewGameFactory never returns null (see its own file doc's
##     fail-loud contract).
##   - Continue — enabled iff CurrentGameState.has_save(0); press calls
##     CurrentGameState.load_from_slot(0). A load_from_slot(0) failure here
##     is necessarily a RACE CONDITION (the button was enabled a moment
##     ago, so a save existed then) — e.g. the save file was deleted or
##     corrupted between the enable-check and this press. That failure is
##     logged via push_warning() and BLOCKS the transition (fail-closed);
##     CurrentGameState.data is left untouched by load_from_slot()'s own
##     contract, so MainScene never boots from a half-loaded state.
##   - Dev: Pick Scenario — guarded behind OS.is_debug_build() (NFR-006,
##     mitigates RISK-010: this surface must never ship in a release
##     export). Enumerates res://data/scenarios/*.tres via DirAccess (no
##     ResourceLoader.load() of each candidate — see NFR-005 note below) and
##     renders one disabled placeholder row when the directory is empty (or
##     missing) rather than crashing. Selecting a row calls
##     NewGameFactory.create_state_for_scenario(path) -> assigned onto
##     CurrentGameState.data -> transition.
##
## Test seams (this file has no other collaborators to inject, unlike most
## of this codebase's other presentation controls — CurrentGameState is
## always referenced as the bare global autoload identifier directly,
## matching MainScene.gd's own established convention for that singleton):
##   - transition_override: Callable — when valid, called INSTEAD OF
##     get_tree().change_scene_to_file() so a test can observe/record the
##     requested transition without ever tearing down the live GUT test
##     tree (which a real change_scene_to_file() would do, since it
##     replaces the SceneTree's current scene out from under the running
##     test runner).
##   - debug_build_override — when non-null (a bool), overrides
##     OS.is_debug_build() for _is_debug_build_context(), so a test can
##     simulate both a debug and a release build context deterministically.
##   - scenarios_dir_override — when non-empty, overrides
##     DEFAULT_SCENARIOS_DIR for scenario enumeration, so a test can
##     simulate an empty/missing scenarios directory without touching the
##     real res://data/scenarios/ contents.
##
## NFR-005 (title screen loads in under one second, must not preload
## MainScene.tscn at startup): _ready() only wires button/list signals and
## calls refresh() — has_save() (a disk stat) and the DirAccess-based
## scenario-filename enumeration below. Neither MainScene.tscn nor any
## individual scenario *.tres candidate is ever load()/preload()'d here;
## MAIN_SCENE_PATH is resolved lazily, only inside _transition_to_main_scene(),
## only once a button is actually pressed — see
## tests/boot/test_title_screen_boot_performance.gd's source-scan assertion.
##
## Usage:
##   var screen := preload("res://scenes/TitleScreen.tscn").instantiate()
##   add_child(screen)
##   screen.press_new_game()       # New Game
##   screen.press_continue()       # Continue (if enabled)
##   screen.press_dev_scenario(0)  # Dev: Pick Scenario, row 0

class_name TitleScreen
extends Control

const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")

## res:// path to the composition-root scene every button contract
## transitions to. Deliberately a plain String constant, NOT a preload —
## see file-level NFR-005 note.
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## Default directory scanned for Dev: Pick Scenario candidates. Overridable
## per-instance via scenarios_dir_override (test seam).
const DEFAULT_SCENARIOS_DIR: String = "res://data/scenarios"

## v1 uses save slot 0 only (ADR-004).
const SAVE_SLOT: int = 0

## Test seam — see file-level doc. Defaults to an invalid Callable, which
## _transition_to_main_scene() treats as "use the real engine call".
var transition_override: Callable = Callable()

## Test seam — see file-level doc. null (default) means "read the real
## OS.is_debug_build() value"; a bool overrides it.
var debug_build_override = null

## Test seam — see file-level doc. Empty string (default) means "use
## DEFAULT_SCENARIOS_DIR".
var scenarios_dir_override: String = ""

## The res:// paths currently backing the Dev: Pick Scenario list, in the
## SAME order as the rendered rows — empty whenever the list shows only the
## disabled placeholder row. Indexed directly by press_dev_scenario()/
## _on_dev_scenario_item_selected().
var _dev_scenario_paths: Array[String] = []

@onready var _new_game_button: Button = $NewGameButton
@onready var _continue_button: Button = $ContinueButton
@onready var _dev_scenario_label: Label = $DevScenarioLabel
@onready var _dev_scenario_list: ItemList = $DevScenarioList


func _ready() -> void:
	if _new_game_button != null:
		_new_game_button.pressed.connect(_on_new_game_button_pressed)
	if _continue_button != null:
		_continue_button.pressed.connect(_on_continue_button_pressed)
	if _dev_scenario_list != null:
		_dev_scenario_list.item_selected.connect(_on_dev_scenario_item_selected)
	refresh()


## refresh() -> void — recomputes every button/list's visible/enabled state
## from current engine + CurrentGameState conditions. Called once from
## _ready(); also exposed publicly so a test may call it again after
## mutating save-file state or a *_override seam post-construction.
func refresh() -> void:
	_refresh_continue_enabled()
	_refresh_dev_panel()


# ── New Game ───────────────────────────────────────────────────────────────

## press_new_game() -> void — New Game button contract (FR-006): see
## file-level doc.
func press_new_game() -> void:
	CurrentGameState.data = NewGameFactoryClass.create_prologue_state()
	_transition_to_main_scene()


func _on_new_game_button_pressed() -> void:
	press_new_game()


# ── Continue ────────────────────────────────────────────────────────────────

func _refresh_continue_enabled() -> void:
	if _continue_button != null:
		_continue_button.disabled = not CurrentGameState.has_save(SAVE_SLOT)


## is_continue_enabled() -> bool — true iff CurrentGameState.has_save(0).
## For test inspection, mirroring this codebase's other controls'
## is_enabled() getters (e.g. presentation/end_turn_control.gd).
func is_continue_enabled() -> bool:
	if _continue_button != null:
		return not _continue_button.disabled
	return CurrentGameState.has_save(SAVE_SLOT)


## press_continue() -> void — Continue button contract (FR-006): see
## file-level doc. Guards against being invoked while disabled (defense in
## depth alongside the button's own `disabled` flag) by re-checking
## has_save() first; the race-condition failure path is
## load_from_slot(0) itself unexpectedly returning false (the save
## vanished/corrupted between the enable-check and this press).
func press_continue() -> void:
	if not CurrentGameState.has_save(SAVE_SLOT):
		return

	var ok: bool = CurrentGameState.load_from_slot(SAVE_SLOT)
	if not ok:
		push_warning(
			"TitleScreen: Continue pressed but load_from_slot(%d) unexpectedly failed (race condition) -- blocking transition to MainScene" % SAVE_SLOT
		)
		_refresh_continue_enabled()
		return

	_transition_to_main_scene()


func _on_continue_button_pressed() -> void:
	press_continue()


# ── Dev: Pick Scenario ───────────────────────────────────────────────────────

func _refresh_dev_panel() -> void:
	var is_visible_now: bool = _is_debug_build_context()
	if _dev_scenario_label != null:
		_dev_scenario_label.visible = is_visible_now
	if _dev_scenario_list != null:
		_dev_scenario_list.visible = is_visible_now
	if is_visible_now:
		_populate_dev_scenario_list()


## is_dev_scenario_panel_visible() -> bool — true iff the Dev: Pick Scenario
## label + list are currently visible (i.e. a debug-build context, real or
## simulated via debug_build_override).
func is_dev_scenario_panel_visible() -> bool:
	if _dev_scenario_list != null:
		return _dev_scenario_list.visible
	return _is_debug_build_context()


func _is_debug_build_context() -> bool:
	if debug_build_override != null:
		return debug_build_override
	return OS.is_debug_build()


func _populate_dev_scenario_list() -> void:
	if _dev_scenario_list == null:
		return

	_dev_scenario_list.clear()

	var dir_path: String = DEFAULT_SCENARIOS_DIR
	if not scenarios_dir_override.is_empty():
		dir_path = scenarios_dir_override

	_dev_scenario_paths = _enumerate_scenario_paths(dir_path)

	if _dev_scenario_paths.is_empty():
		var placeholder_index: int = _dev_scenario_list.add_item("No scenarios available")
		_dev_scenario_list.set_item_disabled(placeholder_index, true)
		return

	for scenario_path in _dev_scenario_paths:
		_dev_scenario_list.add_item(scenario_path.get_file())


## get_dev_scenario_paths() -> Array[String] — the res:// paths currently
## backing the Dev: Pick Scenario list, in the SAME order as the rendered
## rows (empty when the list shows only the disabled placeholder row). For
## test inspection.
func get_dev_scenario_paths() -> Array[String]:
	return _dev_scenario_paths.duplicate()


## _enumerate_scenario_paths(dir_path) -> Array[String] — every *.tres file
## directly under dir_path (no recursion, no ResourceLoader.load() of any
## candidate — see file-level NFR-005 note), sorted for deterministic
## ordering, as full res:// paths. Never crashes: returns an empty array
## when dir_path does not exist or is not readable (DirAccess.open()
## returning null).
static func _enumerate_scenario_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	paths.sort()
	return paths


## press_dev_scenario(index) -> void — selecting a row in the Dev: Pick
## Scenario list, where `index` indexes get_dev_scenario_paths() (NOT
## necessarily the ItemList's own row index, though they coincide whenever
## no disabled placeholder is showing). Out-of-range indices (including
## whenever only the disabled placeholder row exists, since
## _dev_scenario_paths is empty in that case) are a defensive no-op —
## Godot itself never emits item_selected for a disabled row, but this
## guard makes press_dev_scenario() safe to call directly from a test too.
func press_dev_scenario(index: int) -> void:
	if index < 0 or index >= _dev_scenario_paths.size():
		return

	var scenario_path: String = _dev_scenario_paths[index]
	CurrentGameState.data = NewGameFactoryClass.create_state_for_scenario(scenario_path)
	_transition_to_main_scene()


func _on_dev_scenario_item_selected(index: int) -> void:
	press_dev_scenario(index)


# ── Scene transition ─────────────────────────────────────────────────────────

## _transition_to_main_scene() -> void — the SINGLE seam every button
## contract above funnels through. In production, calls
## get_tree().change_scene_to_file(MAIN_SCENE_PATH) — a runtime load, never
## a preload/eager load (NFR-005). Tests inject transition_override (a
## Callable(String)->void) to observe/record the requested transition
## without ever tearing down the live GUT test tree (a real
## change_scene_to_file() call replaces the SceneTree's current scene out
## from under the running test runner).
func _transition_to_main_scene() -> void:
	if transition_override.is_valid():
		transition_override.call(MAIN_SCENE_PATH)
		return
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
