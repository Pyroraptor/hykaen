## core/controllers/stride_action_controller.gd — StrideActionController
## (FEAT-006, Iteration O "Combine Selection UX"; US-006; FR-005; ADR-006).
##
## Adapter layer (Clean Architecture, ADR-001): this project's "API" boundary
## for verb controllers is the enter_selection()/execute() contract
## (core/application/combine/verb_controller_port.gd's VerbControllerPort),
## so this file — like core/controllers/combine_action_controller.gd — lives
## under the adapters/infrastructure side of the dependency arrow even
## though it sits physically under core/. Depends on the APPLICATION port
## (VerbControllerPort, extended below) and the DOMAIN movement rule
## (core/rules/movement.gd's Movement.get_stride_destinations() — a pure,
## engine-free function), never the other way around.
##
## THIS FEATURE'S SCOPE (US-006; FR-005; ADR-006): the multi-phase-targeting
## seam's own STRIDE-side half of "post-move-aware targeting for chained
## sub-actions" — enter_selection() offers the actor's legal Stride
## destinations (Movement.get_stride_destinations(), the SAME pure domain
## rule presentation/movement_input_controller.gd's own
## get_selectable_stride_hexes() already delegates to — no second/forked
## adjacency-or-range rule is authored here) and, when a caller supplies an
## already-resolved `selected_hex` in its context Dictionary (the seam a
## later UI-wiring feature will drive via SelectionOverlay's
## selection_resolved signal — see
## core/application/combine/multi_phase_targeting_controller.gd's own
## file-level doc), threads that resolved hex onto the returned
## SelectionDescriptor's `meta.chosen_hex` — the SOLE field
## core/controllers/strike_action_controller.gd's own enter_selection()
## reads back out of accumulated['STRIDE'] to compute its post-move
## candidate_targets (ADR-006). This file's own execute() is NOT overridden
## — VerbControllerPort's abstract default (fail-safe, NOT_IMPLEMENTED)
## covers the ADR-002 "registered controllers expose both enter_selection
## and execute" contract check; real sub-action resolution/execute() wiring
## for this NEW core/controllers/ seam is a later feature layered on top,
## exactly like presentation/combine_action_controller.gd's own
## execute()-side orchestration already resolves STRIDE/STRIKE through the
## PRE-EXISTING presentation/ controllers, unaffected by this file.
##
## Never mutates the actor: Movement.get_stride_destinations() is a pure,
## read-only query and this file never calls Movement.stride() (the
## MUTATING call) — an actor's real hex_coord is left completely untouched
## by any enter_selection() call this controller ever makes (design notes'
## test_criteria: "Actor's real position is NOT mutated during
## enter_selection() calls").
##
## Domain purity boundary (ADR-001): extends VerbControllerPort (itself
## RefCounted-only) — no Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage:
##   var controller := StrideActionController.new({
##       "other_combatants_fn": Callable(self, "_other_living_combatants"),
##   })
##   var offer: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
##   # offer.candidate_hexes -- every legal Stride destination right now
##
##   var resolved: Object = controller.enter_selection({
##       "actor_id": actor, "order_index": 0, "selected_hex": chosen_hex,
##   })
##   # resolved.meta["chosen_hex"] == chosen_hex -- the value
##   # StrikeActionController.enter_selection() later reads back out of
##   # accumulated['STRIDE'].

class_name StrideActionController
extends "res://core/application/combine/verb_controller_port.gd"

const MovementClass = preload("res://core/rules/movement.gd")
const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")

## other_combatants_fn — Callable() -> Array of every OTHER live combatant
## (Combatant instances or duck-typed {"hex_coord": ...} Dictionaries, per
## Movement.get_stride_destinations()'s own accepted shapes), consulted for
## destination occupancy. Defaults to an invalid Callable, in which case
## every candidate hex is treated as unoccupied (an empty other_combatants
## list — mirrors Movement.get_stride_destinations()'s own degrade path).
var _other_combatants_fn: Callable

## speed — the mover's Stride range in hexes. Defaults to
## Movement.DEFAULT_SPEED, mirroring every other caller of
## Movement.get_stride_destinations().
var _speed: int


func _init(deps: Dictionary = {}) -> void:
	_other_combatants_fn = deps.get("other_combatants_fn", Callable())
	_speed = deps.get("speed", MovementClass.DEFAULT_SPEED)


## enter_selection(context) -> SelectionDescriptor
##
## context — {actor_id: <Combatant>, order_index: int, selected_hex:
##            <HexCoord|null>, ...} (extra keys, e.g. "accumulated", are
##            accepted and ignored — STRIDE is always order_index 0 in the
##            v0 Charge queue and has no prior phase to read from).
##
## Returns:
##   {ok:true, candidate_hexes: <every legal Stride destination>,
##    meta: {"chosen_hex": selected_hex}} — when `context.selected_hex` was
##    supplied (a caller/future-UI-seam-resolved pick).
##   {ok:true, candidate_hexes: <every legal Stride destination>, meta: {}}
##    — the OFFER shape, when no selection has been resolved yet and at
##    least one legal destination exists.
##   {ok:false, error_code:"NO_LEGAL_OPTIONS"} — no live actor, or the actor
##    has zero legal Stride destinations right now.
func enter_selection(context: Dictionary) -> Object:
	var actor = context.get("actor_id")
	var order_index: int = context.get("order_index", 0)
	if actor == null:
		return _failure(order_index)

	var other_combatants: Array = _other_combatants_fn.call() if _other_combatants_fn.is_valid() else []
	var destinations: Array = MovementClass.get_stride_destinations(actor, other_combatants, _speed)

	var selected_hex = context.get("selected_hex")
	if selected_hex != null:
		return SelectionDescriptorClass.new(true, [], destinations, [], order_index, {"chosen_hex": selected_hex})

	if destinations.is_empty():
		return _failure(order_index)

	return SelectionDescriptorClass.new(true, [], destinations, [], order_index, {})


## _failure(order_index) -> SelectionDescriptor — the SOLE failure-shape
## constructor this file uses (mirrors
## core/application/combine/build_verb_queue_use_case.gd's own
## {"error_code": "NO_LEGAL_OPTIONS"}-on-meta convention, which
## core/application/combine/multi_phase_targeting_controller.gd's own
## _error_code_of() already reads).
func _failure(order_index: int) -> Object:
	return SelectionDescriptorClass.new(false, [], [], [], order_index, {"error_code": "NO_LEGAL_OPTIONS"})
