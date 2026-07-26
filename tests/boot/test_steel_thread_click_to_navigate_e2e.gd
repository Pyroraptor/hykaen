extends GutTest
## tests/boot/test_steel_thread_click_to_navigate_e2e.gd — FEAT-010, updated
## by FEAT-327 (US-001..US-008 / FR-001, FR-004, FR-005, FR-007, FR-008,
## FR-009, FR-010, FR-011). E2E smoke test for the complete click-to-navigate
## steel thread, driven exclusively through REAL signal emission.
##
## Boot-real proof (DEF-005 naming convention: "steel thread" filenames are
## reserved for suites that genuinely instantiate/boot res://MainScene.tscn,
## see tests/integration/test_test_suite_naming_hygiene.gd) that the REAL
## presentation/exploration_mode_controller.gd ExplorationModeController,
## presentation/hex_grid_view.gd HexGridView, core/application/
## exploration_controller.gd ExplorationController,
## core/geometry/hex_pathfinder.gd HexPathfinder, and
## core/geometry/encounter_tile_adapter.gd EncounterTileAdapter drive the
## complete click-to-navigate steel thread together -- no mocked Callables
## anywhere: every PassabilityQuery/MoveCostQuery Callable exercised below
## is built by the REAL EncounterTileAdapter.make_is_passable()/
## make_move_cost() against a REAL EncounterResource loaded from disk
## (tests/fixtures/hex_grid/e2e_exploration_encounter.tres), authoring
## normal, difficult, AND impassable HexTileDataResource tiles. The trigger
## hex (FR-007/FR-008's proximity-trigger halt) is authored as a real,
## in-memory ProximityTriggerResource (a genuine Resource instance, never a
## test double) wired into a real ScenarioEncounterEntryResource /
## ScenarioResource -- ExplorationController._evaluate_triggers() reads
## these through ScenarioSession.get_active_encounter_entries() exactly as
## it would for any disk-loaded scenario.
##
## Composition note: this suite boots the REAL res://MainScene.tscn
## composition root first (mirroring every other allow-listed steel-thread
## suite's `_boot_main_scene()` convention), so the naming-hygiene guard's
## "actually references/boots MainScene" check holds genuinely, not just
## textually. MainScene's default boot seeds its `_exploration` controller
## (presentation/exploration_mode_controller.gd) against
## data/scenarios/prologue_scenario.tres -- this feature's own
## files_to_create list authorizes exactly ONE new fixture file (the
## EncounterResource .tres above), not a second, full ScenarioResource
## fixture, so `_swap_in_fixture_scenario()` below REPLACES the booted
## instance's `scenario_session`/`exploration_controller` (both genuine,
## public/settable MainScene proxies -- see MainScene.gd's own
## `scenario_session`/`exploration_controller` property definitions) and
## rebuilds the cached PassabilityQuery/MoveCostQuery Callables via the
## real EncounterTileAdapter against this feature's fixture, exactly
## mirroring what ExplorationModeController.boot() itself does internally.
## `selected_party_member_id` is left at boot()'s own default ("player_0",
## Titus) since the fresh scenario_session below seeds that SAME id at the
## SAME (0, 0) start hex the real, booted HexGridView already rendered
## Titus' token at -- so no new token needs to be instantiated.
##
## FEAT-327 (final verification that DEF-001 is fully closed, resolves
## DEF-002/DEF-003 as passive regressions): FIX-001 (see
## tests/boot/test_exploration_click_wiring.gd's own proof) rewired
## hex_grid_view.hex_clicked to a REAL, genuine, single connection targeting
## `_exploration._on_exploration_hex_clicked` -- MainScene's own dead,
## adjacency-only shadow handler no longer exists at all. This suite's
## previous workaround (`await instance._exploration.
## _on_exploration_hex_clicked(...)`, a direct internal method call bypassing
## the signal entirely) is therefore no longer necessary and is REMOVED
## below: every click-to-navigate assertion in this file now drives the
## steel thread's entry point exclusively via
## `instance.hex_grid_view.emit_signal("hex_clicked", hex_coord)` -- the
## REAL, booted signal a real mouse click would fire.
##
## Because Godot signal emission never itself awaits a connected coroutine
## handler to completion (`_on_exploration_hex_clicked` is a coroutine --
## it awaits `_execute_exploration_path()`, which awaits each step's
## `animate_token_to()` Tween), this suite cannot simply `await
## hex_grid_view.emit_signal(...)`. Instead, `_CapturingHexGridViewSpy` /
## `_drain_click_to_navigate_walk()` below intercept every animate_token_to()
## call the REAL controller issues and await each one's own genuine Tween
## `finished` Signal, in order, until the walk halts or completes -- never a
## fixed sleep/frame-count guess (RISK-008). Hover remains driven via the
## already-genuine `hex_grid_view.hex_hovered.emit(...)` signal, unchanged.
##
## FIX-002 (DEF-002 closure: halt the walk loop on a failed
## move_party_member() step) and FIX-003 (DEF-003 closure: pin
## HexPathfinder's `_SEARCH_RADIUS_MARGIN` boundary behavior) are NOT given
## new dedicated scenarios here -- both already have direct unit/boot
## coverage of their own (tests/boot/test_exploration_pathfinding.gd's
## mid-path-rejection suite; tests/unit/core/geometry/
## test_hex_pathfinder.gd's boundary-margin suite). This file's own
## impassable-ring and mid-path-trigger scenarios below simply continue to
## pass with the walk now driven through the real signal chain, which is
## this feature's own explicit "passive regression check" scope for those
## two fixes.
##
## Traces FR-001 (HexPathfinder), FR-004 (EncounterTileAdapter),
## FR-005 (path overlay rendering), FR-007 (tile passability),
## FR-008 (multi-hex navigate), FR-009 (hover preview), FR-010
## (click-to-navigate execution), and FR-011 (token animation) together in
## one running scenario, per this feature's own scope.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")
const ProximityTriggerResourceClass = preload("res://data/triggers/proximity_trigger_resource.gd")
const PartyResourceClass = preload("res://data/characters/party_resource.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexPathfinderClass = preload("res://core/geometry/hex_pathfinder.gd")
const EncounterTileAdapterClass = preload("res://core/geometry/encounter_tile_adapter.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42

const FIXTURE_ENCOUNTER_PATH: String = "res://tests/fixtures/hex_grid/e2e_exploration_encounter.tres"

## The party member the booted MainScene.tscn already renders at (0, 0)
## (Titus) -- reused verbatim as this suite's hero, so no second token needs
## to be instantiated on the real, booted hex_grid_view.
const HERO_ID: String = "player_0"

## The trigger hex authored in this suite's in-memory ProximityTriggerResource
## -- matches the fixture's normal (non-impassable, non-difficult) tile at
## (3, 0), one hop past the difficult tile at (2, 0), one hop before the
## eventual (never-reached) destination (4, 0). See the fixture .tres's own
## header comment for the full corridor layout.
const TRIGGER_HEX_Q: int = 3
const TRIGGER_HEX_R: int = 0

## The hex fully walled off by the fixture's 6-tile impassable ring --
## unreachable no matter the route (mirrors
## tests/unit/core/geometry/test_hex_pathfinder.gd's own "fully-surrounded
## goal" criterion, exercised here through the real EncounterTileAdapter
## Callables instead of a hand-written lambda).
const WALLED_TARGET_Q: int = -3
const WALLED_TARGET_R: int = 5


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _swap_in_fixture_scenario(instance) -> Dictionary — replaces the booted
## MainScene's `scenario_session`/`exploration_controller` (both genuine
## MainScene proxy properties onto its real `_exploration` controller, see
## this file's own header doc) with a fresh ScenarioSession/
## ExplorationController composed against this feature's fixture
## EncounterResource, and rebuilds `_exploration`'s cached
## PassabilityQuery/MoveCostQuery Callables via the real EncounterTileAdapter
## against that SAME fixture -- exactly mirroring what
## ExplorationModeController.boot() itself does internally (see
## presentation/exploration_mode_controller.gd's own boot() doc). Returns
## {"encounter": EncounterResource} for fixture-derived assertions.
func _swap_in_fixture_scenario(instance) -> Dictionary:
	var fixture_encounter = ResourceLoader.load(FIXTURE_ENCOUNTER_PATH)
	assert_not_null(fixture_encounter, "the FEAT-010 fixture EncounterResource must load from disk")

	var trigger := ProximityTriggerResourceClass.new()
	trigger.trigger_hexes = [{"q": TRIGGER_HEX_Q, "r": TRIGGER_HEX_R}]

	var entry := ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = "e2e_steel_thread_encounter"
	entry.encounter = fixture_encounter
	entry.trigger = trigger

	var party := PartyResourceClass.new()
	party.character_resource_paths = ["res://data/characters/titus.tres"]

	var scenario := ScenarioResourceClass.new()
	scenario.scenario_id = "e2e_steel_thread_scenario"
	scenario.display_name = "FEAT-010 Steel Thread E2E Fixture"
	scenario.party = party
	scenario.encounter_entries = [entry]

	var fresh_session := ScenarioSessionClass.new()
	fresh_session.scenario = scenario
	fresh_session.party_hex_positions[HERO_ID] = HexCoordClass.new(0, 0)

	instance.scenario_session = fresh_session
	instance.exploration_controller = ExplorationControllerClass.new(fresh_session)

	# FEAT-009's own dedicated cooperative-polling connection (see
	# ExplorationModeController.boot()'s own doc) was made against the
	# ORIGINAL (now-discarded) exploration_controller instance boot() built
	# at MainScene._ready() time -- a brand new ExplorationController
	# instance's combat_triggered signal starts with zero connections, so it
	# must be reconnected here for the mid-path trigger-halt criterion below
	# to have any effect on `_exploration.is_exploration_active()`.
	instance.exploration_controller.combat_triggered.connect(instance._exploration._on_domain_combat_triggered)

	instance._exploration._is_passable_fn = EncounterTileAdapterClass.make_is_passable(fixture_encounter)
	instance._exploration._move_cost_fn = EncounterTileAdapterClass.make_move_cost(fixture_encounter)

	return {"encounter": fixture_encounter}


## _CapturingHexGridViewSpy — FEAT-327. Wraps the REAL, booted hex_grid_view
## (the SAME node instance `hex_clicked` is emitted on below), forwarding
## every call ExplorationModeController issues against its own
## `_hex_grid_view` field while ALSO recording each animate_token_to()
## call's own real Tween `finished` Signal, in call order. This is this
## suite's sole mechanism for detecting genuine completion of a
## REAL-signal-driven click-to-navigate walk (test_criteria: "no test...
## calls _on_exploration_hex_clicked directly; all steel-thread assertions
## are driven exclusively through real signal emission") -- see
## _drain_click_to_navigate_walk()'s own doc for why a spy is necessary at
## all instead of simply awaiting the emit_signal() call.
class _CapturingHexGridViewSpy:
	var _real
	var animate_calls: Array = []

	func _init(real) -> void:
		_real = real

	func animate_token_to(combatant_id: String, target_hex) -> Signal:
		var finished_signal: Signal = _real.animate_token_to(combatant_id, target_hex)
		animate_calls.append(finished_signal)
		return finished_signal

	func clear_overlays() -> void:
		_real.clear_overlays()

	func set_path_overlay(path: Array, color: Color) -> void:
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
## once no further step is issued (full completion, an impassable-halt, or a
## mid-path trigger-mode-switch halt). Never a fixed sleep/frame-count guess
## (RISK-008).
func _drain_click_to_navigate_walk(spy: _CapturingHexGridViewSpy) -> void:
	var i := 0
	while i < spy.animate_calls.size():
		await spy.animate_calls[i]
		i += 1


## _emit_hex_clicked_and_await(instance, target_hex) -> _CapturingHexGridViewSpy
## — FEAT-327. Installs a _CapturingHexGridViewSpy in place of
## `instance._exploration._hex_grid_view` (the presentation-layer
## collaborator ExplorationModeController actually calls animate_token_to()/
## clear_overlays()/set_path_overlay() on -- a genuine reference to the SAME
## booted `instance.hex_grid_view` node the "hex_clicked" signal below is
## emitted on), emits the REAL hex_clicked signal (never an internal method
## call), and drains the resulting walk to genuine completion before
## returning the spy for any further call-count/order assertions the caller
## needs.
func _emit_hex_clicked_and_await(instance, target_hex) -> _CapturingHexGridViewSpy:
	var spy := _CapturingHexGridViewSpy.new(instance._exploration._hex_grid_view)
	instance._exploration._hex_grid_view = spy
	instance.hex_grid_view.emit_signal("hex_clicked", target_hex)
	await _drain_click_to_navigate_walk(spy)
	return spy


# ══════════════════════════════════════════════════════════════════════════
# ENTRY POINT: headless boot of the real exploration wiring, with a party
# member selected, succeeds with no engine errors.
# ══════════════════════════════════════════════════════════════════════════

func test_headless_boot_of_the_real_exploration_wiring_succeeds_with_no_engine_errors() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame
	_swap_in_fixture_scenario(instance)

	assert_eq(get_logger().get_errors().size(), 0, "booting MainScene.tscn and swapping in the fixture-driven exploration wiring must produce zero engine errors")

	assert_not_null(instance.exploration_controller, "a real ExplorationController must be constructed")
	assert_not_null(instance.scenario_session, "a real ScenarioSession must be constructed")
	assert_eq(instance._exploration.selected_party_member_id, HERO_ID, "a party member must be selected")
	assert_true(instance._exploration.get_is_passable_fn().is_valid(), "the real EncounterTileAdapter-built is_passable Callable must be valid")
	assert_true(instance._exploration.get_move_cost_fn().is_valid(), "the real EncounterTileAdapter-built move_cost Callable must be valid")

	assert_true(
		instance.hex_grid_view.hex_hovered.is_connected(instance._exploration._on_hex_hovered),
		"hex_grid_view.hex_hovered must be genuinely connected to the controller's hover handler"
	)

	var hero_token = instance.hex_grid_view.get_token(HERO_ID)
	assert_not_null(hero_token, "the selected party member's token must be rendered on the real, booted HexGridView")
	assert_eq(hero_token.hex_coord.q, 0, "the hero token must start at the authored start hex")
	assert_eq(hero_token.hex_coord.r, 0, "the hero token must start at the authored start hex")


# ══════════════════════════════════════════════════════════════════════════
# ADR-006 parity: hovering a distant reachable hex renders a live path
# overlay identical to the path subsequently executed on click.
# ══════════════════════════════════════════════════════════════════════════

func test_hover_preview_matches_the_path_subsequently_executed_on_click() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame
	_swap_in_fixture_scenario(instance)

	# (2, 0) is 2 hexes from the hero's start (0, 0), routed straight through
	# the fixture's authored difficult tile at (1, 0)->(2, 0) -- the unique
	# shortest (and cheapest) route on this otherwise-open grid.
	var target := HexCoordClass.new(2, 0)

	instance.hex_grid_view.hex_hovered.emit(target)
	var preview_path: Array = instance.hex_grid_view.get_path_overlay()

	assert_eq(preview_path.size(), 3, "fixture assumption: (0,0) -> (2,0) must be a 2-hex walk (a 3-element inclusive path)")
	assert_true(preview_path[0].equals(HexCoordClass.new(0, 0)), "the preview path must start at the hero's current hex")
	assert_true(preview_path[preview_path.size() - 1].equals(target), "the preview path must end at the hovered hex")

	# Independently recompute the path via the SAME real HexPathfinder +
	# cached Callables the controller itself uses -- the ADR-006 guarantee
	# is that preview and execution can never disagree, so this recomputed
	# path (from the SAME unmoved start hex) must equal the preview exactly.
	var expected_path: Array = HexPathfinderClass.find_path(
		HexCoordClass.new(0, 0), target, instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(preview_path.size(), expected_path.size(), "the hover preview must match the real pathfinder's own output length")
	for i in range(expected_path.size()):
		assert_true(preview_path[i].equals(expected_path[i]), "preview_path[%d] must equal the real find_path() result" % i)

	await _emit_hex_clicked_and_await(instance, target)

	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].q, target.q, "the executed click must walk the SAME path the preview displayed, ending at the destination")
	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].r, target.r, "the executed click must walk the SAME path the preview displayed, ending at the destination")

	var hero_token = instance.hex_grid_view.get_token(HERO_ID)
	assert_eq(
		hero_token.position, instance.hex_grid_view.axial_to_pixel_with_offset(target),
		"the rendered token must visually end at the destination hex's pixel center, matching the previewed path's endpoint"
	)
	assert_eq(instance.hex_grid_view.get_path_overlay(), [], "the click-to-navigate walk must clear the hover-preview overlay")


# ══════════════════════════════════════════════════════════════════════════
# EXIT POINT: clicking animates the token hex-by-hex (each step's finished
# Signal genuinely awaited) to the destination.
# ══════════════════════════════════════════════════════════════════════════

## _OrderTrackingSpy — wraps the REAL ExplorationController so every
## move_party_member() call is forwarded (state genuinely mutates) while
## recording the rendered token's pixel position at the instant each call
## begins. Mirrors tests/boot/test_exploration_pathfinding.gd's own
## `_OrderTrackingExplorationControllerSpy` convention.
class _OrderTrackingSpy:
	var _real
	var _hex_grid_view
	var _combatant_id: String
	var token_position_log: Array = []

	func _init(real, hex_grid_view, combatant_id: String) -> void:
		_real = real
		_hex_grid_view = hex_grid_view
		_combatant_id = combatant_id

	func move_party_member(combatant_id: String, target_hex) -> bool:
		var token = _hex_grid_view.get_token(_combatant_id)
		token_position_log.append(token.position)
		return _real.move_party_member(combatant_id, target_hex)


func test_click_animates_the_token_hex_by_hex_each_step_awaiting_the_previous_animation() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame
	_swap_in_fixture_scenario(instance)

	var target := HexCoordClass.new(2, 0)
	var expected_path: Array = HexPathfinderClass.find_path(
		HexCoordClass.new(0, 0), target, instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(expected_path.size(), 3, "fixture assumption: (0,0) -> (2,0) must be a 2-hex walk")

	var real_exploration_controller = instance._exploration.exploration_controller
	var spy := _OrderTrackingSpy.new(real_exploration_controller, instance.hex_grid_view, HERO_ID)
	instance._exploration.exploration_controller = spy

	await _emit_hex_clicked_and_await(instance, target)

	assert_eq(spy.token_position_log.size(), 2, "both of the walk's 2 steps must invoke move_party_member() exactly once each")
	for i in range(expected_path.size() - 1):
		assert_eq(
			spy.token_position_log[i], instance.hex_grid_view.axial_to_pixel_with_offset(expected_path[i]),
			"before step %d's move_party_member() call, the token must already be at the PREVIOUS step's pixel position -- its animate_token_to() Signal must have already been awaited to completion" % [i + 1]
		)

	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].q, target.q, "party_hex_positions[combatant_id] must equal the destination HexCoord upon completion")
	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].r, target.r, "party_hex_positions[combatant_id] must equal the destination HexCoord upon completion")

	var hero_token = instance.hex_grid_view.get_token(HERO_ID)
	assert_eq(hero_token.position, instance.hex_grid_view.axial_to_pixel_with_offset(target), "the token must be visibly animated all the way to the destination hex's pixel center")


# ══════════════════════════════════════════════════════════════════════════
# Impassable hexes: a click whose ONLY possible routes are walled off halts
# with zero movement -- token and party_hex_positions remain at the last
# (and, here, only) passable hex the hero ever occupied.
# ══════════════════════════════════════════════════════════════════════════

func test_impassable_ring_makes_the_target_unreachable_halting_with_no_movement() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame
	_swap_in_fixture_scenario(instance)

	var walled_target := HexCoordClass.new(WALLED_TARGET_Q, WALLED_TARGET_R)

	# Fixture assumption: the target hex is itself authored passable, but
	# every one of its 6 neighbors is authored impassable -- so it is
	# unreachable, never merely "the click target itself is a wall".
	var direct_is_passable: bool = instance._exploration.get_is_passable_fn().call(walled_target)
	assert_true(direct_is_passable, "fixture assumption: the walled-off target hex itself must be authored passable")

	var path: Array = HexPathfinderClass.find_path(
		HexCoordClass.new(0, 0), walled_target, instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_true(path.is_empty(), "fixture assumption: the impassable ring must make the target fully unreachable")

	await _emit_hex_clicked_and_await(instance, walled_target)

	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].q, 0, "an unreachable (walled-off) click target must produce zero party_hex_positions mutation")
	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].r, 0, "an unreachable (walled-off) click target must produce zero party_hex_positions mutation")

	var hero_token = instance.hex_grid_view.get_token(HERO_ID)
	assert_eq(
		hero_token.position, instance.hex_grid_view.axial_to_pixel_with_offset(HexCoordClass.new(0, 0)),
		"an unreachable (walled-off) click target must produce zero animate_token_to-driven token movement"
	)
	assert_eq(get_logger().get_errors().size(), 0, "an unreachable click target is a silent no-op, never an engine error")


# ══════════════════════════════════════════════════════════════════════════
# RISK-002 end-to-end convergence: a trigger hex mid-path halts the token
# and party_hex_positions exactly at the trigger hex, flips the controller's
# own game-mode mirror to "not exploration" (COMBAT), and clears overlays.
# ══════════════════════════════════════════════════════════════════════════

func test_a_trigger_hex_mid_path_halts_the_walk_flips_mode_and_clears_overlays() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame
	_swap_in_fixture_scenario(instance)

	assert_true(instance._exploration.is_exploration_active(), "fixture assumption: exploration must start out active")

	var trigger_hex := HexCoordClass.new(TRIGGER_HEX_Q, TRIGGER_HEX_R)
	var beyond_trigger := HexCoordClass.new(4, 0)

	var full_path: Array = HexPathfinderClass.find_path(
		HexCoordClass.new(0, 0), beyond_trigger, instance._exploration.get_is_passable_fn(), instance._exploration.get_move_cost_fn()
	)
	assert_eq(full_path.size(), 5, "fixture assumption: (0,0) -> (4,0) must be a straight 4-hex walk passing through the trigger hex (3,0) at index 3")
	assert_true(full_path[3].equals(trigger_hex), "fixture assumption: the trigger hex (3,0) must be the second-to-last step, not the final destination")

	# Establish a live overlay first (the genuine hover path), so the
	# assertion below proves the overlay was genuinely cleared by the
	# mid-path abort, not merely "never drawn".
	instance.hex_grid_view.hex_hovered.emit(beyond_trigger)
	assert_false(instance.hex_grid_view.get_path_overlay().is_empty(), "fixture assumption: hovering the eventual target must display a non-empty overlay before the click below")

	await _emit_hex_clicked_and_await(instance, beyond_trigger)

	# ── Criterion: party_hex_positions and the rendered token both converge
	#    on exactly the trigger hex, never the eventual destination.
	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].q, trigger_hex.q, "party_hex_positions must halt at exactly the trigger hex, not the eventual destination")
	assert_eq(instance.scenario_session.party_hex_positions[HERO_ID].r, trigger_hex.r, "party_hex_positions must halt at exactly the trigger hex, not the eventual destination")

	var hero_token = instance.hex_grid_view.get_token(HERO_ID)
	assert_eq(
		hero_token.position, instance.hex_grid_view.axial_to_pixel_with_offset(trigger_hex),
		"the rendered token's pixel position must halt at exactly the trigger hex's pixel center, matching party_hex_positions (RISK-002)"
	)

	# ── Criterion: the walk never reached (nor animated toward) the step
	#    past the trigger hex.
	assert_false(
		instance.scenario_session.party_hex_positions[HERO_ID].equals(beyond_trigger),
		"the walk must never have reached the eventual destination past the trigger hex"
	)

	# ── Criterion: game mode flips to COMBAT -- ExplorationModeController's
	#    own local game-mode mirror (see its file-level doc: "this
	#    controller's own local mirror of MainScene.gd's `_game_mode`") is
	#    the correct, in-scope proxy for this assertion, since the FEAT-010
	#    fixture's synthetic encounter_id ("e2e_steel_thread_encounter") is
	#    deliberately never wired to MainScene's own real combat-handoff
	#    pipeline (see this file's own header doc -- MainScene's own
	#    `_on_combat_triggered` stays connected only to the now-discarded
	#    original exploration_controller instance, never this suite's
	#    fixture-driven replacement).
	assert_false(instance._exploration.is_exploration_active(), "a mid-path trigger must flip the controller's own game-mode mirror away from EXPLORATION (i.e. to COMBAT), ADR-004")

	# ── Criterion: overlays are cleared -- both the pre-loop click-clear AND
	#    the mode-switch hover-clear fire for this aborted walk, so no stale
	#    overlay of any kind survives the trigger.
	assert_eq(instance.hex_grid_view.get_path_overlay(), [], "a mid-path trigger abort must leave no path overlay rendered")

	# ── Criterion: a hover received after the abort is a silent no-op (the
	#    guard clause in _on_hex_hovered() must return before ever touching
	#    hex_grid_view again).
	instance.hex_grid_view.hex_hovered.emit(HexCoordClass.new(1, -1))
	assert_eq(instance.hex_grid_view.get_path_overlay(), [], "no hover-preview overlay must be drawn once mode has switched away from EXPLORATION")

	assert_eq(get_logger().get_errors().size(), 0, "a mid-path trigger halt must never itself produce an engine error")
