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
##
## FEAT-009 (US-008 / FR-010, ADR-004, mitigates RISK-002): this suite ALSO
## covers the mid-path combat-interruption/cooperative-polling abort
## mechanism -- the counterpart deliberately using a target hex BEYOND one of
## prologue_scenario.tres's authored proximity-trigger hexes ((3, 0), also in
## Titus/player_0's own r=0 row), so a straight-line click-to-navigate walk
## genuinely passes THROUGH the trigger hex mid-path rather than merely
## landing on it as the final destination. Because MainScene.gd itself is not
## modified by this feature (see presentation/exploration_mode_controller.gd's
## own file-level doc for why the fix lives entirely inside
## ExplorationModeController's own boot()/`_on_domain_combat_triggered()`),
## these tests exercise the REAL exploration_controller.combat_triggered
## signal firing synchronously out of a real move_party_member() call --
## never a hand-simulated notify_game_mode_changed() call -- proving the
## whole ADR-004 cooperative-polling contract actually fires end-to-end
## through the real, booted composition root.

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
	await _emit_hex_clicked_and_await(instance, target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 2, "the full path must be walked, ending with party_hex_positions at the destination")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "the full path must be walked, ending with party_hex_positions at the destination")

	var token = instance.hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel(target),
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

	await _emit_hex_clicked_and_await(instance, target)

	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 0, "an impassable click target must produce zero party_hex_positions mutation")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "an impassable click target must produce zero party_hex_positions mutation")

	var token = instance.hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, instance.hex_grid_view.axial_to_pixel(HexCoordClass.new(0, 0)),
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

	await _emit_hex_clicked_and_await(instance, target)

	assert_eq(spy.token_position_log.size(), 3, "all 3 steps' move_party_member() must have been invoked exactly once each")

	for i in range(path.size() - 1):
		assert_eq(
			spy.token_position_log[i], instance.hex_grid_view.axial_to_pixel(path[i]),
			"before step %d's move_party_member() call, the token must already be at the PREVIOUS step's pixel position (its animation must have already fully completed, ADR-005)" % [i + 1]
		)

	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -4, "the full path must be walked to completion")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "the full path must be walked to completion")

	var final_token = instance.hex_grid_view.get_token("player_1")
	assert_eq(
		final_token.position, instance.hex_grid_view.axial_to_pixel(target),
		"the rendered token must visually end at the destination hex's pixel center"
	)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-009 (US-008 / FR-010, ADR-004, mitigates RISK-002): mid-path combat
# interruption / cooperative-polling abort mechanism.
# ══════════════════════════════════════════════════════════════════════════

## _CallCountingExplorationControllerSpy — mirrors this file's own
## _OrderTrackingExplorationControllerSpy convention (wrap the REAL
## exploration_controller, forward every call so state genuinely mutates)
## but records only a plain call COUNT for move_party_member(), so these
## tests can assert exactly how many steps' domain finalization actually ran
## -- never more than the steps up to and including the triggering hex.
class _CallCountingExplorationControllerSpy:
	var _real
	var move_party_member_call_count: int = 0

	func _init(real) -> void:
		_real = real

	func move_party_member(combatant_id: String, target_hex) -> bool:
		move_party_member_call_count += 1
		return _real.move_party_member(combatant_id, target_hex)


## _CallCountingHexGridViewSpy — wraps the REAL, booted hex_grid_view,
## forwarding every call ExplorationModeController issues against its own
## `_hex_grid_view` field (animate_token_to()/clear_overlays()/
## set_path_overlay()) while recording call COUNTS for each -- this suite's
## own "no further animate_token_to calls past the trigger",
## "clear_overlays() called exactly once, pre-loop", and "no further
## hover-preview overlay drawn once mode has switched away" assertions.
## animate_token_to() itself stays synchronous (mirrors HexGridView's own
## animate_token_to() contract of returning a Signal for the CALLER to
## await, never awaiting internally) so the count increments at the exact
## instant the controller issues the call, not once the tween finishes.
##
## FEAT-327: ALSO records each animate_token_to() call's own real Tween
## `finished` Signal, in call order, in `animate_calls` -- this is this
## suite's sole mechanism for detecting genuine completion of a
## REAL-signal-driven click-to-navigate walk (see
## _drain_click_to_navigate_walk()'s own doc below for why a spy is
## necessary at all instead of simply awaiting the emit_signal() call).
class _CallCountingHexGridViewSpy:
	var _real
	var animate_token_to_call_count: int = 0
	var clear_overlays_call_count: int = 0
	var set_path_overlay_call_count: int = 0
	var animate_calls: Array = []

	func _init(real) -> void:
		_real = real

	func animate_token_to(combatant_id: String, target_hex) -> Signal:
		animate_token_to_call_count += 1
		var finished_signal: Signal = _real.animate_token_to(combatant_id, target_hex)
		animate_calls.append(finished_signal)
		return finished_signal

	func clear_overlays() -> void:
		clear_overlays_call_count += 1
		_real.clear_overlays()

	func set_path_overlay(path: Array, color: Color) -> void:
		set_path_overlay_call_count += 1
		_real.set_path_overlay(path, color)


## _drain_click_to_navigate_walk(spy) -> void — FEAT-327. Godot signal
## emission never itself awaits a connected coroutine handler to completion,
## so `hex_grid_view.emit_signal("hex_clicked", ...)` below returns the
## instant ExplorationModeController._on_exploration_hex_clicked's own
## coroutine first suspends (at its own `await
## _hex_grid_view.animate_token_to(...)`, registered against the SAME Signal
## instance `spy.animate_calls` already recorded by then, since a GDScript
## coroutine runs synchronously up to its first genuine suspension point).
## This helper awaits each recorded Signal in order: when a step's Tween
## fires, EVERY slot connected to it runs synchronously within that single
## emit -- including the controller's own suspended coroutine's resumption,
## which registered strictly BEFORE this helper's own subsequent await on
## the same signal -- so the controller has already run through to its own
## next suspension (or fully finished, halted, or completed) by the time
## this loop's condition is next evaluated. The loop naturally terminates
## once no further step is issued (full completion, an impassable-halt, a
## rejected-step halt, or a mid-path trigger-mode-switch halt). Never a
## fixed sleep/frame-count guess (RISK-008).
func _drain_click_to_navigate_walk(spy: _CallCountingHexGridViewSpy) -> void:
	var i := 0
	while i < spy.animate_calls.size():
		await spy.animate_calls[i]
		i += 1


## _emit_hex_clicked_and_await(instance, target_hex) -> _CallCountingHexGridViewSpy
## — FEAT-327. Installs a _CallCountingHexGridViewSpy in place of
## `instance._exploration._hex_grid_view` (the presentation-layer
## collaborator ExplorationModeController actually calls animate_token_to()/
## clear_overlays()/set_path_overlay() on -- a genuine reference to the SAME
## booted `instance.hex_grid_view` node the "hex_clicked" signal below is
## emitted on), emits the REAL hex_clicked signal (never an internal method
## call), and drains the resulting walk to genuine completion before
## returning the spy for any further call-count/order assertions the caller
## needs.
func _emit_hex_clicked_and_await(instance, target_hex) -> _CallCountingHexGridViewSpy:
	var spy := _CallCountingHexGridViewSpy.new(instance._exploration._hex_grid_view)
	instance._exploration._hex_grid_view = spy
	instance.hex_grid_view.emit_signal("hex_clicked", target_hex)
	await _drain_click_to_navigate_walk(spy)
	return spy


## Titus' (player_0) authored start hex (0, 0) reaches (4, 0) via a
## straight-line 4-hex walk that genuinely passes THROUGH (3, 0) -- one of
## prologue_scenario.tres's authored proximity-trigger hexes (see this
## file's own header doc) -- before (4, 0), a plain non-trigger hex one step
## further. This is deliberately NOT the click target itself, so the walk's
## halt at (3, 0) is a genuine MID-PATH abort, not merely "the destination
## happened to be a trigger hex".
func test_a_trigger_hex_mid_path_halts_the_walk_leaving_token_and_domain_state_at_the_trigger_hex() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: the default click-to-navigate selection must be Titus (player_0)")
	assert_true(instance._exploration.is_exploration_active(), "fixture assumption: exploration must start out active")

	var start := HexCoordClass.new(0, 0)
	var trigger_hex := HexCoordClass.new(3, 0)
	var target := HexCoordClass.new(4, 0)
	var path: Array = HexPathfinderClass.find_path(
		start, target,
		instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(path.size(), 5, "fixture assumption: (0, 0) -> (4, 0) must be a straight 4-hex walk passing through the trigger hex (3, 0) at index 3")
	assert_true(path[3].equals(trigger_hex), "fixture assumption: the trigger hex (3, 0) must be the SECOND-TO-LAST step, not the final destination")

	var real_exploration_controller = instance._exploration.exploration_controller
	var controller_spy := _CallCountingExplorationControllerSpy.new(real_exploration_controller)
	instance._exploration.exploration_controller = controller_spy

	var real_hex_grid_view = instance._exploration._hex_grid_view
	var hex_grid_view_spy := await _emit_hex_clicked_and_await(instance, target)

	# ── Criterion: clear_overlays() called exactly once, pre-loop, per
	#    click -- NOT once per step. This walk has 3 steps (to (1, 0),
	#    (2, 0), and the triggering (3, 0)), so "once per step" would read
	#    3; the actual count is 2 -- ONE from _on_exploration_hex_clicked()'s
	#    own single pre-loop clear (US-008/FEAT-008), plus exactly ONE more
	#    from _on_domain_combat_triggered()'s notify_game_mode_changed(false)
	#    -> _clear_hover_preview() call (a DIFFERENT, already-covered FEAT-007
	#    call site, fired once for the whole mode-switch, not per step). See
	#    test_clear_overlays_is_called_exactly_once_before_the_walk_starts_
	#    not_once_per_step below for this same criterion proven in isolation,
	#    on an uninterrupted walk where the mode-switch call site never fires
	#    at all.
	assert_eq(hex_grid_view_spy.clear_overlays_call_count, 2, "clear_overlays() must be called exactly twice for this aborted click -- the single pre-loop click-clear plus the single mode-switch hover-clear -- never once per step")

	# ── Criterion: no further move_party_member()/animate_token_to() calls
	#    are issued once the mode has switched -- only the 3 steps up to and
	#    including the triggering hex (3, 0) ever ran; the 4th step to the
	#    eventual destination (4, 0) never did.
	assert_eq(controller_spy.move_party_member_call_count, 3, "only the steps up to and including the triggering hex must invoke move_party_member() -- the step past it must never be issued")
	assert_eq(hex_grid_view_spy.animate_token_to_call_count, 3, "only the steps up to and including the triggering hex must invoke animate_token_to() -- the step past it must never be issued")

	# ── Criterion: token pixel position and party_hex_positions both
	#    converge on exactly the trigger hex (RISK-002).
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 3, "party_hex_positions must halt at exactly the trigger hex, not the eventual destination")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "party_hex_positions must halt at exactly the trigger hex, not the eventual destination")

	var token = real_hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, real_hex_grid_view.axial_to_pixel(trigger_hex),
		"the rendered token's pixel position must halt at exactly the trigger hex's pixel center, matching party_hex_positions (RISK-002)"
	)

	# ── Criterion: once mode has switched to COMBAT mid-loop, the
	#    cooperative-polling flag has genuinely flipped.
	assert_false(instance._exploration.is_exploration_active(), "a mid-path trigger must flip this controller's own is_exploration_active() to false, ADR-004")

	# ── Criterion: no further hover-preview overlay is drawn once mode has
	#    switched away from EXPLORATION -- a hover received after the abort
	#    must be a silent no-op (the guard clause in _on_hex_hovered() must
	#    return before ever touching `_hex_grid_view` again).
	real_hex_grid_view.hex_hovered.emit(HexCoordClass.new(2, 0))
	assert_eq(hex_grid_view_spy.set_path_overlay_call_count, 0, "no hover-preview overlay must be drawn once mode has switched away from EXPLORATION")

	# Let MainScene's own real _on_combat_triggered()/rewire_session() handoff
	# (independently wired via boot()'s caller-supplied `on_combat_triggered`
	# target, see exploration_mode_controller.gd's own header doc) settle
	# before this instance is freed at test teardown, mirroring
	# tests/gut/test_steel_thread_e2e.gd's own `_boot_main_scene_with_seed()`
	# convention for driving a real combat handoff.
	await get_tree().process_frame
	await get_tree().process_frame


## Regression proof that clear_overlays() being called exactly once, pre-loop,
## is NOT specific to the mid-path-trigger scenario above -- an ordinary,
## uninterrupted multi-step walk (Marigold/player_1's own established 3-hex
## fixture, reused verbatim from
## test_a_three_hex_path_executes_sequentially_each_step_waits_for_the_
## previous_animation above) must ALSO only ever clear the overlay once, no
## matter how many steps the path has.
func test_clear_overlays_is_called_exactly_once_before_the_walk_starts_not_once_per_step() -> void:
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

	# A stale hover-preview overlay from before the click, so clear_overlays()
	# actually has non-trivial state to clear.
	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(-2, 0))
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: a hover-preview overlay must be visible before the click below")

	var hex_grid_view_spy := await _emit_hex_clicked_and_await(instance, target)

	assert_eq(hex_grid_view_spy.clear_overlays_call_count, 1, "clear_overlays() must be called exactly once for a 3-step walk, not once per step")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -4, "fixture assumption: the full uninterrupted path must still be walked to completion")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-325 (DEF-002 closure): a mid-path move_party_member() rejection halts
# _execute_exploration_path() BEFORE that step's animate_token_to() is ever
# called, leaving the token/domain state at the last successfully completed
# hex. This is currently unreachable via real terrain (static during a walk)
# so it is exercised via an injectable move_party_member() stub, mirroring
# this file's own established spy conventions.
# ══════════════════════════════════════════════════════════════════════════

## _RejectStepExplorationControllerSpy — wraps the REAL exploration_controller
## (forwarding every non-rejected call so state genuinely mutates, mirroring
## this file's own _CallCountingExplorationControllerSpy/_OrderTracking
## ExplorationControllerSpy convention) but returns false WITHOUT forwarding
## to the real controller whenever `target_hex` matches the injected
## `_reject_hex` -- simulating a mid-path passability rejection (e.g. a
## future dynamic-hazard feature) without depending on any authored
## impassable tile data.
class _RejectStepExplorationControllerSpy:
	var _real
	var _reject_hex
	var move_party_member_call_count: int = 0

	func _init(real, reject_hex) -> void:
		_real = real
		_reject_hex = reject_hex

	func move_party_member(combatant_id: String, target_hex) -> bool:
		move_party_member_call_count += 1
		if target_hex.equals(_reject_hex):
			return false
		return _real.move_party_member(combatant_id, target_hex)


## Titus' (player_0) authored start hex (0, 0) reaches (2, 0) via a clean
## 2-hex walk -- (1, 0) and (2, 0) are neither of them one of the prologue
## scenario's authored proximity-trigger hexes (reusing this file's own
## established fixture from test_clicking_a_reachable_distant_hex_walks_the_
## full_path_to_the_destination above). The SECOND step, to (2, 0), is
## rejected by the spy above, so the walk must halt after the FIRST step
## completes -- never calling animate_token_to() for the rejected (2, 0) step.
func test_a_mid_path_move_party_member_rejection_halts_before_that_steps_animate_token_to() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._exploration.selected_party_member_id, "player_0", "fixture assumption: the default click-to-navigate selection must be Titus (player_0)")

	var start := HexCoordClass.new(0, 0)
	var rejected_step := HexCoordClass.new(2, 0)
	var target := HexCoordClass.new(2, 0)
	var path: Array = HexPathfinderClass.find_path(
		start, target,
		instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(path.size(), 3, "fixture assumption: (0, 0) -> (2, 0) must be a 2-hex walk (a 3-element inclusive path)")

	var real_exploration_controller = instance._exploration.exploration_controller
	var controller_spy := _RejectStepExplorationControllerSpy.new(real_exploration_controller, rejected_step)
	instance._exploration.exploration_controller = controller_spy

	var real_hex_grid_view = instance._exploration._hex_grid_view
	var hex_grid_view_spy := _CallCountingHexGridViewSpy.new(real_hex_grid_view)
	instance._exploration._hex_grid_view = hex_grid_view_spy

	await instance._exploration._on_exploration_hex_clicked(target)

	# ── Criterion: the halt happens BEFORE animate_token_to() is called for
	#    the rejected step -- only the first (successful) step's animation
	#    was ever issued.
	assert_eq(hex_grid_view_spy.animate_token_to_call_count, 1, "animate_token_to() must be called for the first (successful) step only -- never for the rejected second step")

	# ── Criterion: token pixel position matches axial_to_pixel() of the last
	#    successfully completed hex, not the rejected step.
	var token = real_hex_grid_view.get_token("player_0")
	assert_eq(
		token.position, real_hex_grid_view.axial_to_pixel(HexCoordClass.new(1, 0)),
		"the rendered token's pixel position must halt at the last successfully completed hex (1, 0), not the rejected step (2, 0)"
	)

	# ── Criterion: party_hex_positions reflects exactly the completed steps,
	#    with no entry for the rejected step.
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].q, 1, "party_hex_positions must halt at exactly the last successfully completed hex, not the rejected step")
	assert_eq(instance.scenario_session.party_hex_positions["player_0"].r, 0, "party_hex_positions must halt at exactly the last successfully completed hex, not the rejected step")
