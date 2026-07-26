extends GutTest
## tests/boot/test_exploration_pathfinding.gd — FEAT-007 (US-007 / FR-009).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's exploration-mode controller (`instance._exploration`, a
## presentation/exploration_mode_controller.gd ExplorationModeController --
## wired at boot by MainScene._boot_exploration_mode(), unchanged by this
## feature) now drives a live hover path preview on the REAL, booted
## `instance.hex_grid_view`:
##
##   - hovering a hex (hex_grid_view.hex_hovered, genuinely connected at
##     boot -- not a hand-wired double) while a party member is selected
##     computes a path via HexPathfinder.find_path() using the controller's
##     cached passability/cost Callables, and displays it via
##     hex_grid_view.set_path_overlay().
##   - the overlay clears on mouse-leave (hex_grid_view.notify_mouse_exited(),
##     which real callers reach via NOTIFICATION_WM_MOUSE_EXIT -- see that
##     method's own doc).
##   - the overlay clears when exploration mode is switched off. MainScene.gd
##     itself is NOT modified by this feature (out of this feature's own
##     file scope, see presentation/exploration_mode_controller.gd's own
##     header doc) -- so, mirroring tests/boot/test_exploration_click_to_
##     move.gd's established "call the handler directly" convention, this
##     suite drives the mode-switch notification via
##     `instance._exploration.notify_game_mode_changed(false)` directly
##     rather than depending on a real `_on_combat_triggered()` handoff.
##   - the cached passability/cost Callables are built EXACTLY ONCE per
##     controller lifetime (boot()), never rebuilt per hover event
##     (ADR-006).
##
## Mirrors tests/boot/test_boot_exploration_mode.gd's/test_exploration_
## click_to_move.gd's established `_boot_main_scene()` convention (real
## MainScene.tscn, never a hand-wired double).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# hex_hovered is genuinely wired to the real ExplorationModeController.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_grid_view_hex_hovered_is_connected_to_the_real_exploration_controller() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(
		instance.hex_grid_view.hex_hovered.is_connected(instance._exploration._on_hex_hovered),
		"hex_grid_view.hex_hovered must be genuinely connected to ExplorationModeController._on_hex_hovered at boot"
	)


# ══════════════════════════════════════════════════════════════════════════
# Hovering an adjacent/reachable hex displays a live path preview from
# Titus' (player_0, the default-selected party member) current hex.
# ══════════════════════════════════════════════════════════════════════════

func test_hovering_a_reachable_hex_displays_a_path_from_titus_to_the_hovered_hex() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: boot must default to EXPLORATION mode")
	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: boot must default the hover-preview selection to Titus (player_0)")

	# (1, 0) is hex-distance 1 from Titus' authored start hex (0, 0) and is
	# NOT one of the prologue scenario's authored proximity-trigger hexes,
	# mirroring test_exploration_click_to_move.gd's own fixture assumption
	# for the identical reason (never confound this assertion with a
	# combat handoff).
	var target := HexCoordClass.new(1, 0)
	instance.hex_grid_view.hex_hovered.emit(target)

	var path: Array = instance.hex_grid_view.get_path_overlay()
	assert_false(path.is_empty(), "hovering a reachable hex must display a non-empty path overlay")
	assert_true(path[0].equals(HexCoordClass.new(0, 0)), "the displayed path must start at Titus' current hex")
	assert_true(path[path.size() - 1].equals(target), "the displayed path must end at the hovered hex")


# ══════════════════════════════════════════════════════════════════════════
# The overlay clears on mouse-leave.
# ══════════════════════════════════════════════════════════════════════════

func test_the_overlay_clears_on_mouse_leave() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, 0))
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: a path must be displayed before the mouse-leave assertion")

	instance.hex_grid_view.notify_mouse_exited()

	assert_eq(instance.hex_grid_view.get_path_overlay(), [], "the mouse leaving the grid must clear the hover-preview path overlay")


# ══════════════════════════════════════════════════════════════════════════
# The overlay clears when the game mode switches away from EXPLORATION.
# ══════════════════════════════════════════════════════════════════════════

func test_the_overlay_clears_when_game_mode_switches_away_from_exploration() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, 0))
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: a path must be displayed before the mode-switch assertion")

	# MainScene.gd is not modified by this feature (see this file's own
	# header doc) -- drive the mode-switch notification directly, mirroring
	# tests/boot/test_exploration_click_to_move.gd's established "call the
	# handler directly" convention for exercising a real, booted composition
	# root's collaborators without simulating the full combat-trigger signal
	# chain.
	instance._exploration.notify_game_mode_changed(false)

	assert_eq(
		instance.hex_grid_view.get_path_overlay(), [],
		"switching exploration mode off must clear the hover-preview path overlay"
	)

	# A subsequent hover, while still switched off, must not redisplay it.
	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(-1, 0))
	assert_eq(
		instance.hex_grid_view.get_path_overlay(), [],
		"a hover received while exploration mode is switched off must not redisplay a path overlay"
	)


# ══════════════════════════════════════════════════════════════════════════
# The passability/cost Callables are constructed once per controller
# lifetime, never rebuilt per hover event (ADR-006 call-count assertion).
# ══════════════════════════════════════════════════════════════════════════

func test_passability_and_cost_callables_are_constructed_once_not_per_hover_event() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var is_passable_fn_at_boot: Callable = instance._exploration.get_is_passable_fn()
	var move_cost_fn_at_boot: Callable = instance._exploration.get_move_cost_fn()
	assert_true(is_passable_fn_at_boot.is_valid(), "boot() must build a valid is_passable Callable")
	assert_true(move_cost_fn_at_boot.is_valid(), "boot() must build a valid move_cost Callable")

	for target in [HexCoordClass.new(1, 0), HexCoordClass.new(0, -1), HexCoordClass.new(1, -1), HexCoordClass.new(-1, 0)]:
		instance.hex_grid_view.hex_hovered.emit(target)

	assert_eq(
		instance._exploration.get_is_passable_fn(), is_passable_fn_at_boot,
		"the is_passable Callable must remain the SAME object across many hover events (constructed once per controller lifetime, ADR-006)"
	)
	assert_eq(
		instance._exploration.get_move_cost_fn(), move_cost_fn_at_boot,
		"the move_cost Callable must remain the SAME object across many hover events (constructed once per controller lifetime, ADR-006)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Regression: hovering while in COMBAT mode is a no-op (never touches the
# EXPLORATION-only hover-preview state), mirroring test_exploration_click_
# to_move.gd's own mode-gating convention.
# ══════════════════════════════════════════════════════════════════════════

func test_hovering_in_combat_mode_produces_no_path_overlay() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._exploration.notify_game_mode_changed(false)
	instance._game_mode = MainSceneClass.GameMode.COMBAT

	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, 0))

	assert_eq(
		instance.hex_grid_view.get_path_overlay(), [],
		"hovering while _game_mode == COMBAT (and exploration hover notified inactive) must produce no path overlay"
	)
