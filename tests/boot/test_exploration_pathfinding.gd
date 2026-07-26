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
##
## FEAT-008 (US-008 / FR-010, ADR-005): this suite ALSO covers
## ExplorationModeController._on_exploration_hex_clicked()/
## _execute_exploration_path() -- the click-to-navigate counterpart to the
## hover preview above, driven directly (`await instance._exploration.
## _on_exploration_hex_clicked(...)`, mirroring this codebase's established
## "call the handler directly" convention) since MainScene.gd's own
## hex_grid_view.hex_clicked wiring is unchanged by this feature (still
## reaches MainScene's pre-existing single-step handler -- see
## exploration_mode_controller.gd's own header doc). Target hexes below are
## deliberately chosen OUTSIDE data/scenarios/prologue_scenario.tres's
## authored proximity-trigger hexes (see that .tres's `trigger_hexes` list)
## so a click-to-navigate walk in these tests never also confounds itself
## with a combat handoff.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexPathfinderClass = preload("res://core/geometry/hex_pathfinder.gd")

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


# ══════════════════════════════════════════════════════════════════════════
# FEAT-008 (US-008 / FR-010, ADR-005): click-to-navigate walks the full path.
# ══════════════════════════════════════════════════════════════════════════

## _OrderTrackingExplorationControllerSpy — a hand-written spy (this
## codebase's established convention, see test_exploration_click_to_move.gd's
## `_ExplorationControllerSpy`) wrapping the REAL exploration_controller so
## every `move_party_member()` call is forwarded (state genuinely mutates)
## while ALSO recording the rendered token's pixel `position` at the instant
## each call begins. Because ExplorationModeController._execute_exploration_
## path() only issues a step's move_party_member() call once the PREVIOUS
## step's `await hex_grid_view.animate_token_to(...)` has genuinely resolved,
## this log directly proves the ADR-005 sequential ordering: log[i] (recorded
## just before the step-(i+1) move) must equal the pixel position of
## path[i], i.e. the PREVIOUS step's animation had already fully completed --
## never a batch of moves issued upfront followed by animations after.
class _OrderTrackingExplorationControllerSpy:
	var _real
	var _hex_grid_view
	var _selected_id: String
	var token_position_log: Array = []

	func _init(real, hex_grid_view, selected_id: String) -> void:
		_real = real
		_hex_grid_view = hex_grid_view
		_selected_id = selected_id

	func move_party_member(combatant_id: String, target_hex) -> bool:
		var token = _hex_grid_view.get_token(_selected_id)
		token_position_log.append(token.position)
		return _real.move_party_member(combatant_id, target_hex)


## Titus' (player_0) authored start hex (0, 0) reaches (2, 0) via a clean
## 2-hex walk -- (1, 0) and (2, 0) are neither of them one of the prologue
## scenario's authored proximity-trigger hexes (see this file's own header
## doc), so this walk can never also confound itself with a combat handoff.
func test_clicking_a_reachable_distant_hex_walks_the_full_path_to_the_destination() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: the default hover/click-to-navigate selection must be Titus (player_0)")

	# A stale overlay (from a prior hover) must be cleared exactly once by
	# the click-to-navigate walk below.
	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, 0))
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: a hover-preview overlay must be visible before the click below")

	var target := HexCoordClass.new(2, 0)
	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 2, "the full path must be walked, ending with party_hex_positions at the destination")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "the full path must be walked, ending with party_hex_positions at the destination")

	var token = instance.hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel_with_offset(target),
		"the rendered token's pixel position must end at the destination hex's pixel center"
	)

	assert_eq(
		instance.hex_grid_view.get_path_overlay(), [],
		"the walk must have cleared the pre-existing hover-preview overlay exactly once, before stepping"
	)


## Clicking an unreachable/impassable hex (empty path from HexPathfinder) is
## a net no-op: zero movement, zero overlay mutation. `_is_passable_fn` is
## reassigned directly (this codebase's established "reach into a
## presentation controller's underscore-prefixed collaborator/field for a
## test double" convention, e.g. test_exploration_click_to_move.gd's
## `instance.exploration_controller = spy`) to an always-false Callable so
## HexPathfinder.find_path()'s own "goal impassable -> []" contract fires
## deterministically, without depending on any authored impassable tile data
## (data/encounters/prologue_encounter.tres authors no tiles at all -- every
## hex defaults passable).
func test_clicking_an_impassable_hex_produces_no_movement_and_leaves_the_overlay_untouched() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var target := HexCoordClass.new(1, 0)

	# Establish a real, non-empty overlay (via the genuine hover path) BEFORE
	# the passability Callable is overridden below, so the assertion after
	# the click below can prove clear_overlays() was never reached.
	instance.hex_grid_view.hex_hovered.emit(target)
	var overlay_before_click: Array = instance.hex_grid_view.get_path_overlay()
	assert_false(overlay_before_click.is_empty(), "fixture assumption: hovering the target hex must display a non-empty overlay before it is made impassable")

	instance._exploration._is_passable_fn = func(_hex_coord): return false

	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 0, "an impassable click target must produce zero party_hex_positions mutation")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "an impassable click target must produce zero party_hex_positions mutation")

	var token = instance.hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel_with_offset(HexCoordClass.new(0, 0)),
		"an impassable click target must produce zero animate_token_to-driven token movement"
	)

	assert_eq(
		instance.hex_grid_view.get_path_overlay(), overlay_before_click,
		"an impassable click target's empty path must never call clear_overlays() -- the pre-existing overlay must be left exactly as it was"
	)


## A 3+ hex path (Marigold/player_1's authored start (-1, 0) to (-4, 0), all
## of q in {-4, -3, -2} being outside the prologue scenario's authored
## proximity-trigger hexes) executes sequentially: each step's domain
## finalization (move_party_member(), forwarded through the spy below)
## begins only once the PREVIOUS step's animate_token_to() tween has
## genuinely finished (ADR-005) -- never a batch of moves issued upfront
## followed by animations after.
func test_a_three_hex_path_executes_sequentially_each_step_waits_for_the_previous_animation() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._exploration.selected_party_member_id = "player_1"
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -1, "fixture assumption: Marigold (player_1) starts at (-1, 0)")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "fixture assumption: Marigold (player_1) starts at (-1, 0)")

	var start := HexCoordClass.new(-1, 0)
	var target := HexCoordClass.new(-4, 0)
	var path: Array = HexPathfinderClass.find_path(
		start, target,
		instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(path.size(), 4, "fixture assumption: (-1, 0) -> (-4, 0) must be a 3-hex walk (a 4-element inclusive path)")

	var real_exploration_controller = instance._exploration.exploration_controller
	var spy := _OrderTrackingExplorationControllerSpy.new(real_exploration_controller, instance.hex_grid_view, "player_1")
	instance._exploration.exploration_controller = spy

	await instance._exploration._on_exploration_hex_clicked(target)

	assert_eq(spy.token_position_log.size(), 3, "all 3 steps' move_party_member() must have been invoked exactly once each")

	for i in range(path.size() - 1):
		assert_eq(
			spy.token_position_log[i], instance.hex_grid_view.axial_to_pixel_with_offset(path[i]),
			"before step %d's move_party_member() call, the token must already be at the PREVIOUS step's pixel position (its animation must have already fully completed, ADR-005)" % [i + 1]
		)

	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -4, "the full path must be walked to completion")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "the full path must be walked to completion")

	var final_token = instance.hex_grid_view.get_token("player_1")
	assert_eq(
		final_token.position, instance.hex_grid_view.axial_to_pixel_with_offset(target),
		"the rendered token must visually end at the destination hex's pixel center"
	)
