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
##      _after_successful_move() helper (FEAT-013/FEAT-014's original
##      behavior, now invoked from _verb_bar_step_execute()/
##      _verb_bar_stride_execute() -- FEAT-007, this iteration's US-007/
##      FR-010, deleted the earlier hex_grid_view.hex_clicked auto-resolve
##      handler that used to invoke this same logic) explicitly pushes an
##      empty selectable-hex set to hex_grid_view the moment
##      movement_input_controller.step_to()/stride_to() reports success,
##      BEFORE re-deriving/re-pushing the new post-move legal-move set via
##      _on_active_actor_changed() -- design notes' API contract #4
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

const MainSceneClass          = preload("res://MainScene.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass      = preload("res://core/rules/action_economy.gd")
const ResultScreenViewScene   = preload("res://presentation/result_screen_view.tscn")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const CombatQueryServiceClass = preload("res://presentation/combat_query_service.gd")
const ReactionControllerClass = preload("res://presentation/reaction_controller.gd")


## FEAT-004 (US-004/FR-004, RISK-001 mitigation): named static fallback used
## to build the stub CombatQueryService's two Callables below. MainScene's
## real `_combat_query_service` (presentation/combat_query_service.gd) is only
## constructed inside `_ready()`'s composition-root boot sequence, which a
## `.new()`-constructed (not scene-tree-booted) MainScene instance -- as this
## suite's before_each() builds -- never runs, leaving
## `_instance._combat_query_service` null. MainScene._turn_presentation()
## then builds an invalid `Callable(null, "other_living_combatants")`, which
## GDScript treats as an inert Callable rather than raising an error --
## surfacing only as cascading "highlights a non-empty set" assertion
## failures further down the call chain. A named static helper (rather than
## an inline `func(_x): return []` lambda passed straight into `Callable()`)
## is used for Godot 4.3 compatibility, per this feature's documented
## fallback contract.
static func _empty_array(_x = null) -> Array:
	return []


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

	## animate_token_to() -- FEAT-007 (US-007): StepActionController/
	## StrideActionController now duck-type this method on any injected
	## hex_grid_view (MainScene now always wires one via _verb_deps()). This
	## double resolves synchronously (no real Signal/Tween) so this suite's
	## existing call-count/ordering assertions stay exactly as they were
	## before hex_grid_view was wired into this fixture.
	func animate_token_to(_combatant_id: String, _target_hex):
		return null


## FakeRoundSession -- minimal stand-in for core/application/round_session.gd,
## exposing only what _on_active_actor_changed()/_after_successful_move() read
## (current_action_economy() / current_actor() / current_actor_entity()).
## `current_actor()`/`current_actor_entity()` return the SAME live Combatant
## handed to _init() -- Combatant is a reference type in GDScript, so a
## successful Step/Stride's in-place "hex_coord" mutation (core/rules/
## movement.gd Movement._set_hex()) is observed immediately, exactly like the
## real RoundSession/live-combatant relationship this mirrors.
class FakeRoundSession:
	var _actor
	var _action_economy

	func _init(actor, action_economy) -> void:
		_actor = actor
		_action_economy = action_economy

	func current_actor():
		return _actor

	## current_actor_entity() -- MainScene.gd's _after_successful_move() (invoked
	## by StepActionController/StrideActionController.execute() on a successful
	## move) reads this to re-derive the post-move highlight via
	## _on_active_actor_changed(). Returns the SAME live Combatant instance as
	## current_actor(), mirroring RoundSession's own documented contract.
	func current_actor_entity():
		return _actor

	func current_action_economy():
		return _action_economy


var _instance = null
var _hex_grid_view: SpyHexGridView = null
var _combat_query_service_party_fn: Callable
var _combat_query_service_enemies_fn: Callable
var _combat_query_service = null


func before_each() -> void:
	_instance = MainSceneClass.new()
	_hex_grid_view = SpyHexGridView.new()
	_instance.hex_grid_view = _hex_grid_view

	# FEAT-004 (US-004/FR-004, ADR-009): stub CombatQueryService constructed
	# and assigned BEFORE any behavior is exercised, so
	# MainScene._turn_presentation() always builds a valid
	# Callable(CombatQueryService, "other_living_combatants") instead of an
	# invalid Callable(null, ...), and MovementInputController.configure()
	# always receives a real (possibly empty) Array rather than null.
	_combat_query_service_party_fn = Callable(self, "_empty_array")
	_combat_query_service_enemies_fn = Callable(self, "_empty_array")
	_combat_query_service = CombatQueryServiceClass.new(
		_combat_query_service_party_fn,
		_combat_query_service_enemies_fn
	)
	_instance._combat_query_service = _combat_query_service

	# FEAT-007 regression repair (this suite drives a `.new()`-constructed --
	# not scene-tree-booted -- MainScene instance, so _ready()'s own
	# `verb_dispatch_controller.setup({...})` / `_reaction_instance = ...`
	# composition-root wiring never runs): Criterion 2's Step/Stride sanity
	# checks call `_instance.verb_dispatch_controller._verb_bar_step_execute()`/
	# `_verb_bar_stride_execute()` directly, which require `_controller_fn` to
	# be a REAL bound Callable (MainScene's own `_controller()` -- unchanged by
	# FEAT-007's extraction, still the sole VERB_TABLE[verb_id].new(_verb_deps())
	# resolver) rather than the default unbound Callable() `verb_dispatch_
	# controller.gd`'s own vars default to. Only STEP/STRIDE/END_TURN's own
	# collaborators are exercised by this suite; combine/spell-picker
	# collaborators are irrelevant to Criterion 1-3 and are left null.
	_instance._reaction_instance = ReactionControllerClass.new(
		Callable(_instance, "_action_economy_for"),
		Callable(_instance, "_current_round_number"),
		null,
		null,
		null,
		_hex_grid_view
	)
	_instance.verb_dispatch_controller.setup({
		"controller_fn": Callable(_instance, "_controller"),
		"round_session_fn": func(): return _instance.round_session,
		"combine_queue_build_session": null,
		"combine_targeting_session": null,
		"selection_overlay": null,
		"spell_picker": null,
		"verb_bar_view": null,
		"status_panel_view": null,
		"party_fn": func(): return [],
		"enemies_fn": func(): return [],
		"turn_presentation_fn": Callable(_instance, "_turn_presentation"),
	})


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null
	_hex_grid_view = null
	_combat_query_service_party_fn = Callable()
	_combat_query_service_enemies_fn = Callable()
	_combat_query_service = null


func _origin_actor(combatant_id: String, is_enemy: bool, hex_coord = null):
	return CombatantClass.from_dict({
		"name":         combatant_id,
		"combatant_id": combatant_id,
		"hex_coord":    hex_coord if hex_coord != null else HexCoordClass.new(0, 0),
		"_is_enemy":    is_enemy,
	})


func _last_call() -> Array:
	return _hex_grid_view.set_selectable_calls[_hex_grid_view.set_selectable_calls.size() - 1]


# ══════════════════════════════════════════════════════════════════════════
# FEAT-004 (US-004/FR-004) smoke test: fail fast on lambda/Callable
# incompatibility BEFORE the behavioral (Criterion 1-3) tests below run, by
# directly invoking both Callables the stub CombatQueryService was
# constructed with in before_each() and asserting each returns a typed empty
# Array (never null).
# ══════════════════════════════════════════════════════════════════════════

func test_stub_combat_query_service_callables_return_typed_empty_arrays() -> void:
	assert_true(_instance._combat_query_service != null, "before_each() must construct a stub CombatQueryService and assign it to _instance._combat_query_service before any behavior is exercised")

	var party_result = _combat_query_service_party_fn.call()
	var enemies_result = _combat_query_service_enemies_fn.call()

	assert_eq(typeof(party_result), TYPE_ARRAY, "the stub CombatQueryService's party Callable must return a typed Array, never null")
	assert_eq(typeof(enemies_result), TYPE_ARRAY, "the stub CombatQueryService's enemies Callable must return a typed Array, never null")
	assert_eq(party_result, [], "the stub CombatQueryService's party Callable must return an empty Array")
	assert_eq(enemies_result, [], "the stub CombatQueryService's enemies Callable must return an empty Array")

	# Also confirm the same fallback helper is directly reachable and returns
	# a typed empty Array on its own, independent of the Callable wrapping.
	var direct_result: Array = _empty_array()
	assert_eq(typeof(direct_result), TYPE_ARRAY, "the named static _empty_array fallback helper must itself return a typed Array")
	assert_eq(direct_result, [], "the named static _empty_array fallback helper must return an empty Array")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_selectable_hexes([]) is called when turn_started fires for
# a non-active-player combatant (turn change AWAY from the player).
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_cleared_when_turn_started_fires_for_a_non_active_player_combatant() -> void:
	var player_actor = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(player_actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(player_actor)

	assert_true(
		_last_call().size() > 0,
		"sanity check: the player's own turn_started event highlights a non-empty selectable-hex set"
	)

	var enemy_actor = _origin_actor("skeleton", true)
	_instance._on_active_actor_changed(enemy_actor)

	assert_eq(
		_last_call(), [],
		"set_selectable_hexes([]) must be called once turn_started fires for a non-active-player (enemy) combatant"
	)


func test_highlight_cleared_directly_on_a_non_active_player_turn_started_event() -> void:
	var enemy_actor = _origin_actor("skeleton", true)
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

## FEAT-007 (this iteration's US-007/FR-010): drives MainScene's
## _verb_bar_step_execute() directly -- the SOLE Step entry point now that the
## legacy hex_grid_view.hex_clicked auto-resolve handler has been deleted.
func test_highlight_cleared_immediately_after_a_successful_step() -> void:
	var actor = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	var destination := HexCoordClass.new(1, 0)
	var result: Dictionary = _instance.verb_dispatch_controller._verb_bar_step_execute(destination)

	assert_true(result.get("ok", false), "sanity check: the Step verb execute() must succeed for a legal adjacent destination")
	assert_true(actor["hex_coord"].equals(destination), "sanity check: the Step actually moved the actor to the destination hex")
	# movement_input_controller.step_to() itself pushes one (non-empty)
	# selectable set as part of re-deriving its own internal destination
	# cache from the actor's new position (presentation/
	# movement_input_controller.gd's _recompute_selectable_destinations()) --
	# that push happens BEFORE step_to() returns control to MainScene, so it
	# is calls_before + 0. The explicit clear MainScene's
	# _after_successful_move() pushes the moment step_to() reports success --
	# BEFORE re-deriving/re-pushing the new post-move legal-move set -- is
	# therefore calls_before + 1.
	assert_true(
		_hex_grid_view.set_selectable_calls.size() > calls_before + 1,
		"sanity check: a successful Step produces at least two more set_selectable_hexes() calls (movement_input_controller's own internal push, then MainScene's explicit clear)"
	)
	assert_eq(
		_hex_grid_view.set_selectable_calls[calls_before + 1], [],
		"the set_selectable_hexes() call MainScene makes immediately after a successful Step verb execute() must be an explicit clear ([])"
	)


## FEAT-007 (this iteration's US-007/FR-010): drives MainScene's
## _verb_bar_stride_execute() directly -- the SOLE Stride entry point now
## that the legacy hex_grid_view.hex_clicked auto-resolve handler (which used
## to try step_to() first, falling back to stride_to()) has been deleted.
func test_highlight_cleared_immediately_after_a_successful_stride() -> void:
	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var actor = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, action_economy)
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	# Two hexes away -- not a legal Step (adjacent-only), but within Stride's
	# default Speed (4).
	var destination := HexCoordClass.new(2, 0)
	var result: Dictionary = _instance.verb_dispatch_controller._verb_bar_stride_execute(destination)

	assert_true(result.get("ok", false), "sanity check: the Stride verb execute() must succeed for a legal Stride-only destination")
	assert_true(actor["hex_coord"].equals(destination), "sanity check: the Stride actually moved the actor to the destination hex")
	# stride_to()'s own internal push (non-empty) is calls_before + 0, and
	# MainScene's explicit clear is calls_before + 1 -- mirroring the Step
	# case above exactly.
	assert_true(
		_hex_grid_view.set_selectable_calls.size() > calls_before + 1,
		"sanity check: a successful Stride produces at least two more set_selectable_hexes() calls (movement_input_controller's own internal push, then MainScene's explicit clear)"
	)
	assert_eq(
		_hex_grid_view.set_selectable_calls[calls_before + 1], [],
		"the set_selectable_hexes() call MainScene makes immediately after a successful Stride verb execute() must be an explicit clear ([])"
	)


## FEAT-007 (this iteration's US-007/FR-010): an out-of-range destination is
## rejected by BOTH the Step and Stride verb closures with no effect, exactly
## as the deleted hex_grid_view.hex_clicked auto-resolve handler used to
## reject a doubly-out-of-range click.
func test_highlight_not_cleared_by_a_verb_execute_that_resolves_to_neither_step_nor_stride() -> void:
	var actor = _origin_actor("titus", false)
	_instance.round_session = FakeRoundSession.new(actor, ActionEconomyClass.new())
	_instance._on_active_actor_changed(actor)

	var calls_before: int = _hex_grid_view.set_selectable_calls.size()

	# Farther than both Step (1 hex) and the default Stride Speed (4 hexes) --
	# rejected by both verb closures with no effect at all, so no
	# additional set_selectable_hexes() call is made.
	var far_hex := HexCoordClass.new(10, 0)
	var step_result: Dictionary = _instance.verb_dispatch_controller._verb_bar_step_execute(far_hex)
	var stride_result: Dictionary = _instance.verb_dispatch_controller._verb_bar_stride_execute(far_hex)

	assert_false(step_result.get("ok", false), "sanity check: an out-of-range hex must be rejected by the Step verb")
	assert_false(stride_result.get("ok", false), "sanity check: an out-of-range hex must be rejected by the Stride verb")
	assert_eq(
		_hex_grid_view.set_selectable_calls.size(), calls_before,
		"a verb execute() call that resolves to neither a legal Step nor a legal Stride destination must not push any additional highlight state"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the highlight remains empty and cannot be re-populated after
# EncounterResolved fires -- reusing FEAT-005's post-resolution lock
# mechanism (ResultScreenView.lock_all_controls() -> MovementInputController
# .lock()).
# ══════════════════════════════════════════════════════════════════════════

func test_highlight_stays_empty_and_cannot_be_repopulated_after_encounter_resolved() -> void:
	var actor = _origin_actor("titus", false)
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

	# A stray post-resolution Step/Stride verb execute() must likewise never
	# re-populate the highlight (step_to()/stride_to() both stay rejected once
	# locked) -- FEAT-007 (this iteration): there is no longer a
	# hex_grid_view.hex_clicked handler to drive this through, so this suite
	# drives _verb_bar_step_execute() directly, the SAME entry point a stray
	# post-resolution VerbBarView press would use.
	var calls_before_click: int = _hex_grid_view.set_selectable_calls.size()
	var stray_result: Dictionary = _instance.verb_dispatch_controller._verb_bar_step_execute(HexCoordClass.new(1, 0))

	assert_false(stray_result.get("ok", false), "a stray post-resolution Step verb execute() must be rejected")
	for i in range(calls_before_click, _hex_grid_view.set_selectable_calls.size()):
		assert_eq(
			_hex_grid_view.set_selectable_calls[i], [],
			"every set_selectable_hexes() call made after EncounterResolved must still report an empty set"
		)
	assert_false(actor["hex_coord"].equals(HexCoordClass.new(1, 0)), "a stray post-resolution verb execute() must never move the actor")
