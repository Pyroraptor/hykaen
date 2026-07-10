extends GutTest
## tests/business_logic/test_highlight_legal_moves.gd — FEAT-006 (US-006 /
## FR-001, ADR-004)
##
## GUT test suite for the turn_started highlight reaction (this codebase realizes
## the design notes' API contract #1 "turn_started" as
## TurnController.active_actor_changed): on every settled active actor, the
## presentation layer must compute
## union(movement_input_controller.get_selectable_step_hexes(),
## get_selectable_stride_hexes()) and push it to
## HexGridView.set_selectable_hexes() -- fixing the P0-1 bug where that call was
## never made at all (previously only movement_input_controller's own internal
## Step-only push happened, so a legal Stride destination beyond 1 hex away was
## never visibly highlighted).
##
## Composition-root de-bloat (2026-07-10): that reaction was extracted from
## MainScene.gd into presentation/turn_presentation_controller.gd
## (TurnPresentationController). This suite now drives the controller DIRECTLY --
## constructed with its injected collaborators (a stable RoundSessionHolder, a
## SpyHexGridView standing in for presentation/hex_grid_view.gd, a real
## MovementInputController, and a no-op roster Callable) -- rather than through a
## `.new()`-ed MainScene. MainScene's thin _on_active_actor_changed() delegation
## to this controller is covered by the booted integration suites
## (tests/regression/test_ranged_reach_targeting.gd,
## tests/gut/test_round_continuation_and_enemy_budget_display.gd).
##
## Verifies (test_criteria):
##   1. The highlighted hex set passed to HexGridView.set_selectable_hexes()
##      exactly equals union(get_selectable_step_hexes(),
##      get_selectable_stride_hexes()) for the active combatant.
##   2. No highlight is shown before the player's turn begins -- an empty set
##      is pushed for a non-player (enemy) turn_started event.
##   3. A debug log line is emitted on invocation, including combatant_id and
##      the Step/Stride hex counts (observability requirement) -- recorded on
##      TurnPresentationController.last_highlight_debug_log since stdout itself
##      is not readily interceptable from a headless GUT test.

const TurnPresentationControllerClass = preload("res://presentation/turn_presentation_controller.gd")
const RoundSessionHolderClass         = preload("res://infrastructure/round_session_holder.gd")
const MovementInputControllerClass    = preload("res://presentation/movement_input_controller.gd")
const HexCoordClass                   = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass              = preload("res://core/rules/action_economy.gd")


## SpyHexGridView -- a minimal stand-in for presentation/hex_grid_view.gd that
## records every set_selectable_hexes() call, mirroring tests/business_logic/
## test_result_screen_lock.gd's identically-named fixture.
class SpyHexGridView:
	var set_selectable_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func move_token(_combatant_id: String, _hex_coord) -> void:
		pass


## FakeRoundSession -- minimal stand-in for core/application/round_session.gd,
## exposing only what TurnPresentationController.on_active_actor_changed() reads
## (current_action_economy()).
class FakeRoundSession:
	var _action_economy

	func _init(action_economy) -> void:
		_action_economy = action_economy

	func current_action_economy():
		return _action_economy


var _controller = null
var _hex_grid_view: SpyHexGridView = null
var _movement_input_controller = null


func before_each() -> void:
	_hex_grid_view = SpyHexGridView.new()
	_movement_input_controller = MovementInputControllerClass.new()
	var holder = RoundSessionHolderClass.new()
	holder.set_current(FakeRoundSession.new(ActionEconomyClass.new()))
	_controller = TurnPresentationControllerClass.new(
		holder,
		_movement_input_controller,
		_hex_grid_view,
		null,                                  # verb_bar_view — not under test here
		null,                                  # status_panel_view — not under test here
		Callable(self, "_no_other_combatants")
	)


func after_each() -> void:
	_controller = null
	_hex_grid_view = null
	_movement_input_controller = null


## Stand-in for MainScene._other_living_combatants(): with no other combatants in
## these fixtures, the roster query returns an empty Array (matching a `.new()`
## MainScene with empty _party/_enemies, as the prior version of this suite used).
func _no_other_combatants(_combatant: Dictionary) -> Array:
	return []


func _origin_actor(combatant_id: String, is_enemy: bool) -> Dictionary:
	return {
		"name":         combatant_id,
		"combatant_id": combatant_id,
		"hex_coord":    HexCoordClass.new(0, 0),
		"_is_enemy":    is_enemy,
	}


func _as_key_set(hexes: Array) -> Dictionary:
	var set: Dictionary = {}
	for hex_coord in hexes:
		set["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return set


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: the highlighted hex set exactly equals
# union(get_selectable_step_hexes(), get_selectable_stride_hexes()).
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_equals_union_of_step_and_stride_hexes_for_active_combatant() -> void:
	var actor: Dictionary = _origin_actor("titus", false)

	_controller.on_active_actor_changed(actor)

	var step_hexes: Array = _movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = _movement_input_controller.get_selectable_stride_hexes()

	assert_true(step_hexes.size() > 0, "sanity check: the origin actor has at least one legal Step destination")
	assert_true(
		stride_hexes.size() > step_hexes.size(),
		"sanity check: Stride (up to Speed hexes) must legally reach strictly more hexes than Step (1 hex) here, so this test can distinguish the union fix from the old Step-only push"
	)

	assert_true(_hex_grid_view.set_selectable_calls.size() > 0, "HexGridView.set_selectable_hexes() must be invoked on turn_started (fixing the P0-1 never-called bug)")

	var highlighted: Array = _hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1]
	var highlighted_keys: Dictionary = _as_key_set(highlighted)

	var expected_keys: Dictionary = _as_key_set(step_hexes)
	for key in _as_key_set(stride_hexes).keys():
		expected_keys[key] = true

	assert_eq(
		highlighted_keys.keys().size(), expected_keys.keys().size(),
		"highlighted hex count must exactly equal the union(Step, Stride) hex count -- no extra hexes, no missing hexes"
	)
	for key in expected_keys.keys():
		assert_true(highlighted_keys.has(key), "expected union hex %s to be highlighted" % key)
	for key in highlighted_keys.keys():
		assert_true(expected_keys.has(key), "highlighted hex %s must be present in union(Step, Stride) -- no extra/filtered hex" % key)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: no highlight is shown before the player's turn begins -- an
# empty set is pushed for a non-player (enemy) turn_started event.
# ══════════════════════════════════════════════════════════════════════════

func test_no_highlight_is_pushed_for_a_non_player_turn_started_event() -> void:
	var enemy_actor: Dictionary = _origin_actor("skeleton", true)

	_controller.on_active_actor_changed(enemy_actor)

	assert_true(
		_hex_grid_view.set_selectable_calls.size() > 0,
		"HexGridView.set_selectable_hexes() must still be invoked for a non-player turn_started event, to explicitly clear any stale highlight"
	)
	assert_eq(
		_hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1], [],
		"no highlight may be shown before the player's turn begins -- an empty set must be pushed for a non-player (enemy) turn_started event"
	)


func test_highlight_clears_when_turn_passes_from_player_to_enemy() -> void:
	var player_actor: Dictionary = _origin_actor("titus", false)
	_controller.on_active_actor_changed(player_actor)
	assert_true(
		_hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1].size() > 0,
		"sanity check: the player's turn_started event highlights a non-empty set"
	)

	var enemy_actor: Dictionary = _origin_actor("skeleton", true)
	_controller.on_active_actor_changed(enemy_actor)

	assert_eq(
		_hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1], [],
		"the highlight must be cleared once turn_started fires for the (non-player) enemy"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a debug log line is emitted on invocation, including
# combatant_id and the Step/Stride hex counts (observability requirement).
# ══════════════════════════════════════════════════════════════════════════

func test_debug_log_line_includes_combatant_id_and_step_stride_hex_counts() -> void:
	var actor: Dictionary = _origin_actor("titus", false)

	_controller.on_active_actor_changed(actor)

	var step_count: int = _movement_input_controller.get_selectable_step_hexes().size()
	var stride_count: int = _movement_input_controller.get_selectable_stride_hexes().size()

	var log_line: String = _controller.last_highlight_debug_log
	assert_true(log_line != "", "a debug log line must be recorded on every on_active_actor_changed() invocation")
	assert_true(log_line.contains("titus"), "the debug log line must include the combatant_id ('titus'): %s" % log_line)
	assert_true(
		log_line.contains("step_hex_count=%d" % step_count),
		"the debug log line must include the Step hex count (%d): %s" % [step_count, log_line]
	)
	assert_true(
		log_line.contains("stride_hex_count=%d" % stride_count),
		"the debug log line must include the Stride hex count (%d): %s" % [stride_count, log_line]
	)


func test_debug_log_line_is_emitted_for_a_non_player_turn_too() -> void:
	var enemy_actor: Dictionary = _origin_actor("skeleton", true)

	_controller.on_active_actor_changed(enemy_actor)

	var log_line: String = _controller.last_highlight_debug_log
	assert_true(log_line != "", "a debug log line must be recorded even for a non-player (enemy) turn_started event")
	assert_true(log_line.contains("skeleton"), "the debug log line must include the enemy's combatant_id ('skeleton'): %s" % log_line)
