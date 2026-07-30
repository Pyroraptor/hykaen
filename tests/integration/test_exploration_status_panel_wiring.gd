extends GutTest
## tests/integration/test_exploration_status_panel_wiring.gd — FEAT-007
## (US-007, ADR-004).
##
## Adds `on_selection_changed: Callable` to
## presentation/exploration_mode_controller.gd's ExplorationModeController.
## setup() (design notes' api_contracts #6) — the "internal API" contract
## boundary this steel thread establishes between exploration-mode
## selection and the status panel: `_select_party_member(id)` now invokes
## `on_selection_changed.call(id)` AFTER updating `selected_party_member_id`
## and hex_grid_view (api_contracts #7), degrading gracefully (no throw,
## selection state still updates) whenever the Callable is unbound.
## MainScene.gd (the composition root) supplies
## `Callable(status_panel_view, "set_selected_combatant")` at boot and also
## explicitly calls `status_panel_view.set_selected_combatant(...)` once
## boot()'s own initial auto-selection has resolved, so the status panel's
## highlight starts in lock-step with ExplorationModeController's own
## `selected_party_member_id` from the very first frame.
##
## test_criteria covered:
##   1. setup() accepts and stores an on_selection_changed Callable
##      dependency.
##   2. _select_party_member(id) invokes on_selection_changed.call(id)
##      AFTER updating local state and hex_grid_view.
##   3. When on_selection_changed is unbound/null, _select_party_member
##      still completes without throwing (graceful degradation).
##   4. Integration test against the REAL, booted res://MainScene.tscn:
##      boot, enter combat, end turn once, assert
##      status_panel_view.get_selected_combatant_id() is non-empty. NOTE
##      (FEAT-008 / US-008, FR-008, ADR-005 supersedes this criterion's
##      original "still matches the exploration selection" expectation):
##      MainScene's AutoSelectActiveActorUseCase now re-mirrors BOTH
##      hex_grid_view and status_panel_view onto whichever PARTY actor's
##      turn is active in combat every time active_actor_changed fires --
##      including the settle that follows an END_TURN press -- so the
##      status panel's highlight is expected to track the new active actor
##      (round_session.current_actor_entity()), not the stale
##      exploration-mode selection, once combat has driven at least one
##      turn forward.
##   5. MainScene correctly wires
##      Callable(status_panel_view, "set_selected_combatant") at boot and
##      the status panel's highlight matches the initial auto-selected
##      party member immediately after boot.

const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")
const MainSceneClass = preload("res://MainScene.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"
const END_TURN: String = "END_TURN"


# ══════════════════════════════════════════════════════════════════════════
# Test doubles (unit-level section)
# ══════════════════════════════════════════════════════════════════════════

## _FakeHexGridView — mirrors tests/unit/test_exploration_mode_controller_select.gd's
## own _FakeHexGridView convention: exposes the hex_clicked/hex_hovered
## signals boot() connects to, plus a real, stateful
## set_selected_combatant()/get_selected_combatant() round-trip.
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


## _SelectionChangedSpy — a hand-written Object exposing a single method
## (`on_selection_changed`) so a real, bound Callable
## (Callable(spy, "on_selection_changed")) can be supplied to setup()'s
## "on_selection_changed" key, recording every invocation's argument and
## call order (mirrors this codebase's established "call-count/argument
## spy" convention, e.g. tests/integration/test_exploration_click_disambiguation.gd's
## _CallCountingExplorationControllerSpy).
class _SelectionChangedSpy:
	extends RefCounted
	var calls: Array = []

	func on_selection_changed(id: String) -> void:
		calls.append(id)


func _make_controller(hex_grid_view, on_selection_changed: Callable = Callable()) -> ExplorationModeControllerClass:
	var controller := ExplorationModeControllerClass.new()
	var deps: Dictionary = {
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	}
	if on_selection_changed.is_valid():
		deps["on_selection_changed"] = on_selection_changed
	controller.setup(deps)
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — setup() accepts and stores an on_selection_changed Callable.
# ══════════════════════════════════════════════════════════════════════════

func test_setup_stores_the_on_selection_changed_callable() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var spy := _SelectionChangedSpy.new()
	var controller := _make_controller(hex_grid_view, Callable(spy, "on_selection_changed"))

	assert_eq(
		controller._on_selection_changed_target, Callable(spy, "on_selection_changed"),
		"setup() must store the on_selection_changed Callable exactly as supplied"
	)


func test_setup_defaults_on_selection_changed_to_an_invalid_callable_when_absent() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	assert_false(
		controller._on_selection_changed_target.is_valid(),
		"setup() must default on_selection_changed to an invalid/unbound Callable when the key is absent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — _select_party_member(id) invokes on_selection_changed.call(id)
# AFTER updating local state and hex_grid_view.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_invokes_on_selection_changed_with_id() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var spy := _SelectionChangedSpy.new()
	var controller := _make_controller(hex_grid_view, Callable(spy, "on_selection_changed"))

	controller._select_party_member("hero_a")

	assert_eq(
		spy.calls, ["hero_a"],
		"_select_party_member(id) must invoke on_selection_changed.call(id) exactly once with id"
	)


func test_select_party_member_invokes_on_selection_changed_after_updating_state_and_hex_grid_view() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	# A spy whose on_selection_changed() closure captures the controller and
	# hex_grid_view so it can assert BOTH have already been updated by the
	# time the callback fires — proving the ordering, not just that the call
	# eventually happens. `observed` is a 2-element Array (a reference type,
	# GDScript lambda captures of local PRIMITIVES are read-only snapshots —
	# an assignment to a captured String/int inside the lambda body would
	# rebind the closure's own copy, never the outer scope's variable — so
	# the two observed values are stored as Array ELEMENTS, whose mutation
	# is visible through the shared Array reference both this test function
	# and the closure hold).
	var observed: Array = ["", ""]

	var controller := ExplorationModeControllerClass.new()
	var probe := func(_id: String):
		observed[0] = controller.selected_party_member_id
		observed[1] = hex_grid_view.get_selected_combatant()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
		"on_selection_changed": probe,
	})

	controller._select_party_member("hero_a")

	assert_eq(
		observed[0], "hero_a",
		"selected_party_member_id must already be updated by the time on_selection_changed fires"
	)
	assert_eq(
		observed[1], "hero_a",
		"hex_grid_view.set_selected_combatant() must already have been called by the time on_selection_changed fires"
	)


func test_select_party_member_called_twice_invokes_on_selection_changed_twice_in_order() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var spy := _SelectionChangedSpy.new()
	var controller := _make_controller(hex_grid_view, Callable(spy, "on_selection_changed"))

	controller._select_party_member("hero_a")
	controller._select_party_member("hero_b")

	assert_eq(spy.calls, ["hero_a", "hero_b"], "each selection change must produce its own on_selection_changed call, in order")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — an unbound/null on_selection_changed degrades gracefully:
# _select_party_member still completes without throwing.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_is_safe_when_on_selection_changed_is_unbound() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"selection state must still update when on_selection_changed is unbound"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"hex_grid_view must still be updated when on_selection_changed is unbound"
	)
	assert_eq(get_logger().get_errors().size(), 0, "an unbound on_selection_changed must never raise/log an error")


func test_select_party_member_is_safe_with_no_hex_grid_view_and_no_on_selection_changed() -> void:
	var controller := ExplorationModeControllerClass.new()

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"selection state must still update when both hex_grid_view and on_selection_changed are absent"
	)
	assert_eq(get_logger().get_errors().size(), 0, "must never raise/log an error with no collaborators wired at all")


# ══════════════════════════════════════════════════════════════════════════
# Integration section — against the REAL, booted res://MainScene.tscn.
# ══════════════════════════════════════════════════════════════════════════

## before_each()/after_each() — reseed CurrentGameState.data with a fresh
## GameStateDataClass instance so no test in this file (or any test that
## runs before/after it in the full suite) can leak scenario_path/session
## state across test boundaries (mirrors tests/boot/test_exploration_to_combat_handoff.gd's
## established ADR-008 convention). This guarantees _boot_main_scene() ->
## MainScene._ready() always takes the same prologue-fallback boot path
## regardless of suite ordering.
func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — MainScene wires Callable(status_panel_view,
# "set_selected_combatant") at boot; the status panel's highlight matches
# the initial auto-selected party member immediately after boot.
# ══════════════════════════════════════════════════════════════════════════

func test_status_panel_matches_the_initial_auto_selected_party_member_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.status_panel_view, "fixture assumption: MainScene must wire a real status_panel_view")
	assert_false(
		instance._exploration.selected_party_member_id.is_empty(),
		"fixture assumption: ExplorationModeController must have auto-selected a party member by boot"
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), instance._exploration.selected_party_member_id,
		"MainScene must call status_panel_view.set_selected_combatant() with the initial auto-selected party member once boot() resolves it"
	)


func test_status_panel_highlight_reflects_the_selected_row_gold_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var selected_id: String = instance._exploration.selected_party_member_id
	assert_eq(
		instance.status_panel_view.get_row_modulate(selected_id), Color(1.0, 0.9, 0.4),
		"the initially-selected party member's status panel row must be highlighted gold"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — boot, enter combat, end turn once: status_panel_view's
# selection mirror stays non-empty and, per FEAT-008's
# AutoSelectActiveActorUseCase (which supersedes this criterion's original
# "still matches the exploration selection" expectation — see this file's
# header doc), now tracks whichever PARTY actor's turn is active in combat.
# ══════════════════════════════════════════════════════════════════════════

func test_status_panel_selection_matches_controller_after_entering_combat_and_ending_turn_once() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the handoff into combat must have succeeded")

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))

	instance.verb_bar_view.press(END_TURN)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(
		instance._exploration.selected_party_member_id.is_empty(),
		"ExplorationModeController.selected_party_member_id must still be non-empty after entering combat and ending a turn"
	)

	var active_actor = instance.round_session.current_actor_entity()
	assert_not_null(active_actor, "fixture assumption: a live current actor must be seated after ending the first turn")
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), active_actor.combatant_id,
		"status_panel_view's selection mirror must track the active actor's combatant_id in combat (FEAT-008 AutoSelectActiveActorUseCase)"
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), instance.status_panel_view.get_selected_combatant_id(),
		"selection consistency invariant: hex_grid_view and status_panel_view selections must be equal (FEAT-008)"
	)
	assert_false(
		instance.status_panel_view.get_selected_combatant_id().is_empty(),
		"status_panel_view.get_selected_combatant_id() must be non-empty after entering combat and ending a turn once"
	)
