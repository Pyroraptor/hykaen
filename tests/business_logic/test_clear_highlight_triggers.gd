extends GutTest
## tests/business_logic/test_clear_highlight_triggers.gd — FEAT-008 (US-008 /
## FR-003)
##
## GUT test suite proving HexGridView's selectable-hex highlight is cleared
## (set_selectable_hexes([])) at every one of the three points US-008/FR-003
## requires:
##   1. On turn change AWAY from the active player -- already produced by
##      MainScene.gd's _on_active_actor_changed()/_highlight_legal_moves()
##      wiring (FEAT-006 / US-006), which this suite re-verifies directly
##      against the composition root (mirroring
##      tests/business_logic/test_highlight_legal_moves.gd's fixture) as this
##      feature's own regression guard, independent of that suite ever being
##      edited or removed.
##   2. IMMEDIATELY after a successful Step/Stride move -- MainScene.gd's
##      _on_hex_grid_view_hex_clicked() handler (FEAT-013/FEAT-014) now
##      explicitly pushes an empty selectable-hex set to hex_grid_view the
##      moment movement_input_controller.step_to()/stride_to() reports
##      success, BEFORE re-deriving/re-pushing the new post-move legal-move
##      set via _on_active_actor_changed() -- design notes' API contract #4
##      ("HexGridView.set_selectable_hexes([]) called immediately after").
##   3. Post-resolution -- reusing the SAME sticky lock mechanism FEAT-005
##      wired into presentation/result_screen_view.gd's lock_all_controls()
##      (via MovementInputController.lock(), which itself clears any
##      injected HexGridView's highlight and rejects every subsequent
##      configure()-driven re-highlight attempt, FEAT-162/DEF-001): once
##      EncounterResolved fires, the highlight stays empty even if
##      MainScene's turn_started handler (_on_active_actor_changed) fires
##      again afterward (e.g. a stray/leftover TurnController signal).
##
## This suite drives MainScene.gd's handlers directly against a freshly
## `.new()`-constructed (NOT scene-tree-booted) MainScene instance, with a
## SpyHexGridView collaborator standing in for the real
## presentation/hex_grid_view.gd (mirroring tests/business_logic/
## test_highlight_legal_moves.gd's and tests/business_logic/
## test_result_screen_lock.gd's identically-named fixture) and a
## FakeRoundSession standing in for core/application/round_session.gd -- this
## avoids reaching into presentation/hex_grid_view.gd's private
## `_selectable_hexes` field, which has no dedicated public getter.

const MainSceneClass        = preload("res://MainScene.gd")
const HexCoordClass         = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass    = preload("res://core/rules/action_economy.gd")
const ResultScreenViewScene = preload("res://presentation/result_screen_view.tscn")


## SpyHexGridView -- a minimal stand-in for presentation/hex_grid_view.gd that
## records every set_selectable_hexes() call, mirroring tests/business_logic/
## test_highlight_legal_moves.gd's and tests/business_logic/
## test_result_screen_lock.gd's identically-named fixture.
class SpyHexGridView:
	var set_selectable_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func move_token(_combatant_id: String, _hex_coord) -> void:
		pass


## FakeRoundSession -- minimal stand-in for core/application/round_session.gd,
## exposing only what _on_active_actor_changed()/_on_hex_grid_view_hex_clicked()
## read (current_action_economy() / current_actor()). `current_actor()`
## returns the SAME live Dictionary handed to _init() -- Dictionaries are
## reference types in GDScript, so a successful Step/Stride's in-place
## "hex_coord" mutation (core/rules/movement.gd Movement._set_hex()) is
## observed immediately, exactly like the real RoundSession/live-combatant
## relationship this mirrors.
class FakeRoundSession:
	var _actor: Dictionary
	var _action_economy

	func _init(actor: Dictionary, action_economy) -> void:
		_actor = actor
		_action_economy = action_economy

	func current_actor() -> Dictionary:
		return _actor

	func current_action_economy():
		return _action_economy


var _instance = null
var _hex_grid_view: SpyHexGridView = null


func before_each() -> void:
	_instance = MainSceneClass.new()
	_hex_grid_view = SpyHexGridView.new()
	_instance.hex_grid_view = _hex_grid_view


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null
	_hex_grid_view = null


func _origin_actor(combatant_id: String, is_enemy: bool, hex_coord = null) -> Dictionary:
	return {
		"name":         combatant_id,
		"combatant_id": combatant_id,
		"hex_coord":    hex_coord if hex_coord != null else HexCoordClass.new(0, 0),
		"_is_enemy":    is_enemy,
	}


func _last_call() -> Array:
	return _hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1]


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_selectable_hexes([]) is called when turn_started fires for
# a non-active-player combatant (turn change AWAY from the player).
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_cleared_when_turn_started_fires_for_a_non_active_player_combatant() -> void:
	var player_actor: Dictionary = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(player_actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(player_actor)

	assert_true(
		_last_call().size() > 0,
		"sanity check: the player's own turn_started event highlights a non-empty selectable-hex set"
	)

	var enemy_actor: Dictionary = _origin_actor("skeleton", true)
	_instance._on_active_actor_changed(enemy_actor)

	assert_eq(
		_last_call(), [],
		"set_selectable_hexes([]) must be called once turn_started fires for a non-active-player (enemy) combatant"
	)


func test_highlight_cleared_directly_on_a_non_active_player_turn_started_event() -> void:
	var enemy_actor: Dictionary = _origin_actor("skeleton", true)
	_instance.round_session = FakeRoundSession.new(enemy_actor, ActionEconomyClass.new())

	_instance._on_active_actor_changed(enemy_actor)

	assert_true(
		_hex_grid_view.set_selectable_calls.size() > 0,
		"HexGridView.set_selectable_hexes() must be invoked even for a non-player turn_started event, to explicitly clear any stale highlight"
	)
	assert_eq(_last_call(), [], "no highlight may be shown for a non-active-player (enemy) turn_started event")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: set_selectable_hexes([]) is called immediately after a
# successful step_to/stride_to call.
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_cleared_immediately_after_a_successful_step() -> void:
	var actor: Dictionary = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	var destination := HexCoordClass.new(1, 0)
	_instance._on_hex_grid_view_hex_clicked(destination)

	assert_true(actor["hex_coord"].equals(destination), "sanity check: the Step actually moved the actor to the clicked hex")
	# movement_input_controller.step_to() itself pushes one (non-empty)
	# selectable set as part of re-deriving its own internal destination
	# cache from the actor's new position (presentation/
	# movement_input_controller.gd's _recompute_selectable_destinations()) --
	# that push happens BEFORE step_to() returns control to MainScene, so it
	# is calls_before + 0. The explicit clear MainScene itself pushes the
	# moment step_to() reports success -- BEFORE re-deriving/re-pushing the
	# new post-move legal-move set -- is therefore calls_before + 1.
	assert_true(
		_hex_grid_view.set_selectable_calls.size() > calls_before + 1,
		"sanity check: a successful Step produces at least two more set_selectable_hexes() calls (movement_input_controller's own internal push, then MainScene's explicit clear)"
	)
	assert_eq(
		_hex_grid_view.set_selectable_calls[calls_before + 1], [],
		"the set_selectable_hexes() call MainScene makes immediately after a successful step_to() must be an explicit clear ([])"
	)


func test_highlight_cleared_immediately_after_a_successful_stride() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var actor: Dictionary = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, action_economy)
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	# Two hexes away -- not a legal Step (adjacent-only), but within Stride's
	# default Speed (4), so _on_hex_grid_view_hex_clicked() falls through to
	# stride_to() after step_to() rejects it locally with
	# ERR_DESTINATION_NOT_SELECTABLE (see MainScene.gd's
	# _on_hex_grid_view_hex_clicked() doc).
	var destination := HexCoordClass.new(2, 0)
	_instance._on_hex_grid_view_hex_clicked(destination)

	assert_true(actor["hex_coord"].equals(destination), "sanity check: the Stride actually moved the actor to the clicked hex")
	# step_to() rejects this hex locally (not adjacent) WITHOUT pushing
	# anything to hex_grid_view (see MovementInputController.step_to()'s
	# doc: a non-selectable destination is rejected before Movement.step()
	# is ever invoked), so stride_to()'s own internal push (non-empty) is
	# calls_before + 0, and MainScene's explicit clear is calls_before + 1 --
	# mirroring the Step case above exactly.
	assert_true(
		_hex_grid_view.set_selectable_calls.size() > calls_before + 1,
		"sanity check: a successful Stride produces at least two more set_selectable_hexes() calls (movement_input_controller's own internal push, then MainScene's explicit clear)"
	)
	assert_eq(
		_hex_grid_view.set_selectable_calls[calls_before + 1], [],
		"the set_selectable_hexes() call MainScene makes immediately after a successful stride_to() must be an explicit clear ([])"
	)


func test_highlight_not_cleared_by_a_click_that_resolves_to_neither_step_nor_stride() -> void:
	var actor: Dictionary = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	# Farther than both Step (1 hex) and the default Stride Speed (4 hexes) --
	# rejected by both controllers with no effect at all, so no
	# additional set_selectable_hexes() call is made.
	_instance._on_hex_grid_view_hex_clicked(HexCoordClass.new(10, 0))

	assert_eq(
		_hex_grid_view.set_selectable_calls.size(), calls_before,
		"a click that resolves to neither a legal Step nor a legal Stride destination must not push any additional highlight state"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the highlight remains empty and cannot be re-populated after
# EncounterResolved fires -- reusing FEAT-005's post-resolution lock
# mechanism (ResultScreenView.lock_all_controls() -> MovementInputController
# .lock()).
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_stays_empty_and_cannot_be_repopulated_after_encounter_resolved() -> void:
	var actor: Dictionary = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(actor)

	assert_true(
		_last_call().size() > 0,
		"sanity check: the player's turn_started event highlights a non-empty selectable-hex set before resolution"
	)

	var result_screen_view = ResultScreenViewScene.instantiate()
	add_child_autofree(result_screen_view)
	result_screen_view.configure(null, null, _instance.movement_input_controller)

	result_screen_view.on_round_event({"round": 1, "outcome": "won"})

	assert_eq(
		_last_call(), [],
		"HexGridView's highlight must be cleared the moment EncounterResolved fires (FEAT-005's lock_all_controls(), reused unmodified by this feature)"
	)

	# Simulate turn_started (active_actor_changed) re-firing after resolution
	# -- e.g. a leftover TurnController signal -- MainScene would normally
	# respond by re-invoking movement_input_controller.configure() and
	# re-highlighting for whoever the (now-concluded) session still sits on.
	_instance._on_active_actor_changed(actor)

	assert_eq(
		_last_call(), [],
		"a stray turn_started/active_actor_changed re-fire after EncounterResolved must never re-populate the highlight"
	)

	# A stray hex click after resolution must likewise never re-populate the
	# highlight (step_to()/stride_to() both stay rejected once locked).
	var calls_before_click: int = _hex_grid_view.set_selectable_calls.size()
	_instance._on_hex_grid_view_hex_clicked(HexCoordClass.new(1, 0))

	for i in range(calls_before_click, _hex_grid_view.set_selectable_calls.size()):
		assert_eq(
			_hex_grid_view.set_selectable_calls[i], [],
			"every set_selectable_hexes() call made after EncounterResolved must still report an empty set"
		)
	assert_false(actor["hex_coord"].equals(HexCoordClass.new(1, 0)), "a stray click after resolution must never move the actor")
