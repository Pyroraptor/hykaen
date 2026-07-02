## presentation/movement_input_controller.gd — MovementInputController
## (FEAT-013 / US-013 / FR-012; Stride: FEAT-014 / US-014 / FR-013)
##
## Presentation layer (Clean Architecture): the player-facing controller that
## lets the active combatant perform a Step -- a FREE, no-action-economy-cost
## move of exactly 1 hex to an adjacent UNOCCUPIED hex -- and a Stride -- a
## move of UP TO Speed hexes that spends exactly ONE action via the existing
## action economy -- mirroring the existing StrikeInputController
## (scenes/battlefield/StrikeInputController.gd, FEAT-007) / StrikeActionControl
## (presentation/strike_action_control.gd, FEAT-109) division of
## responsibility:
##
##   1. Selectable-destination affordance: configure() computes the set of
##      currently legal Step destinations by calling the SAME domain function
##      the rule itself is defined in terms of (core/rules/movement.gd
##      Movement.get_step_destinations()) -- this controller never
##      re-derives the adjacency/occupancy rule, it only reads/derives from
##      the domain (ADR-001).
##   2. Invocation: step_to(destination_hex) forwards directly to the SAME
##      domain function used to validate the move (core/rules/movement.gd
##      Movement.step(), ADR-002 -- no duplicate/forked movement rule exists
##      here). A destination this controller never offered as selectable is
##      rejected HERE, before Movement.step() is ever called (defense in
##      depth mirroring StrikeInputController's ERR_TARGET_NOT_SELECTABLE
##      pattern) -- but Movement.step() re-validates independently regardless
##      (it is the actual source of truth, callable directly by any other
##      caller).
##   3. Stride affordance (FEAT-014 / US-014): get_selectable_stride_hexes()
##      mirrors Movement.get_stride_destinations() the SAME way
##      get_selectable_step_hexes() mirrors get_step_destinations(), and
##      stride_to(destination_hex) forwards directly to Movement.stride()
##      (ADR-002) -- passing through the `action_economy` collaborator
##      configure() was handed, since a Stride (unlike a Step) spends one
##      action from it. A destination never offered as a selectable Stride is
##      rejected HERE first, exactly like step_to()'s own defense-in-depth
##      pattern.
##
## MovementInputController performs NO movement RULE computation of its own
## -- it only (a) mirrors Movement.get_step_destinations()/
## get_stride_destinations() for UX and (b) forwards the player's choice to
## Movement.step()/Movement.stride(). No new port or use case is introduced
## (this is domain-layer core/rules/movement.gd, not an Application-layer use
## case -- Step has no action-economy/event-emission side effects to route
## through one; Stride's action-economy spend is handled entirely inside
## Movement.stride() itself, via the SAME injected ActionEconomy instance
## StrikeActionControl/StrikeInputController already share for this actor).
##
## When a `hex_grid_view` (presentation/hex_grid_view.gd) collaborator is
## supplied, a successful Step also repositions that combatant's already-
## instantiated token via HexGridView.move_token() -- the SAME
## CombatantTokenView.reposition() hook that view already exposed for this
## exact purpose (see combatant_token_view.gd's file-level doc) -- so the
## battlefield visibly reflects the move; this is purely a rendering
## side-effect, never a source of domain truth.

class_name MovementInputController
extends RefCounted

const MovementClass = preload("res://core/rules/movement.gd")

## Local rejection code returned by step_to() when destination_hex does not
## name one of the currently selectable Step destinations -- rejected HERE,
## before Movement.step() is ever invoked.
const ERR_DESTINATION_NOT_SELECTABLE: String = "ERR_DESTINATION_NOT_SELECTABLE"

## Local rejection code returned by stride_to() when destination_hex does not
## name one of the currently selectable Stride destinations -- rejected HERE,
## before Movement.stride() is ever invoked (FEAT-014 / US-014).
const ERR_STRIDE_DESTINATION_NOT_SELECTABLE: String = "ERR_STRIDE_DESTINATION_NOT_SELECTABLE"

## Local rejection code returned by stride_to() when this controller was
## configure()d without an `action_economy` collaborator -- a Stride cannot
## be resolved at all without one to spend the action from (FEAT-014 /
## US-014). Rejected HERE, before Movement.stride() is ever invoked.
const ERR_ACTION_ECONOMY_MISSING: String = "ERR_ACTION_ECONOMY_MISSING"

## step_resolved(result) -- emitted after step_to() successfully invokes
## Movement.step(), carrying that call's full result Dictionary.
signal step_resolved(result: Dictionary)

## step_rejected(message) -- emitted whenever step_to() is rejected, whether
## locally (a non-selectable destination) or by Movement.step() itself.
signal step_rejected(message: String)

## stride_resolved(result) -- emitted after stride_to() successfully invokes
## Movement.stride(), carrying that call's full result Dictionary (FEAT-014).
signal stride_resolved(result: Dictionary)

## stride_rejected(message) -- emitted whenever stride_to() is rejected,
## whether locally (a non-selectable destination, no action_economy
## configured) or by Movement.stride() itself (FEAT-014).
signal stride_rejected(message: String)

const _ERROR_MESSAGES: Dictionary = {
	MovementClass.ERR_ORIGIN_MISSING: "This combatant has no position on the battlefield -- Step is unavailable.",
	MovementClass.ERR_DESTINATION_NOT_ADJACENT: "That hex is too far away -- Step only reaches an adjacent hex.",
	MovementClass.ERR_DESTINATION_OCCUPIED: "That hex is occupied -- choose an empty adjacent hex.",
	ERR_DESTINATION_NOT_SELECTABLE: "That hex is not a legal Step destination.",
	MovementClass.ERR_DESTINATION_EXCEEDS_SPEED: "That hex is too far away -- Stride only reaches up to Speed hexes.",
	MovementClass.ERR_ACTION_UNAVAILABLE: "No action remains to Stride with this turn.",
	ERR_STRIDE_DESTINATION_NOT_SELECTABLE: "That hex is not a legal Stride destination.",
	ERR_ACTION_ECONOMY_MISSING: "No action economy is configured -- Stride is unavailable.",
}
const _DEFAULT_ERROR_MESSAGE: String = "That move could not be completed."

## The acting combatant (a core/domain/combatant.gd Combatant instance, or a
## "hex_coord"-carrying Dictionary -- see core/rules/movement.gd's file-level
## doc for the accepted shapes), as passed to configure().
var _actor = null

## Every OTHER combatant on the battlefield (same duck-typed shapes as
## `_actor`), used for the occupancy check -- NEVER includes `_actor` itself.
var _other_combatants: Array = []

## The optional HexGridView collaborator (presentation/hex_grid_view.gd) this
## controller repositions the mover's token on after a successful Step.
var _hex_grid_view = null

## The identifier used to look up `_actor`'s token on `_hex_grid_view`
## (HexGridView.move_token()'s combatant_id argument).
var _actor_id: String = ""

## The legal Step destinations as of the last configure()/step_to() call --
## exactly Movement.get_step_destinations(_actor, _other_combatants).
var _selectable_destinations: Array = []

## The legal Stride destinations as of the last configure()/stride_to() call
## -- exactly Movement.get_stride_destinations(_actor, _other_combatants)
## (FEAT-014 / US-014).
var _selectable_stride_destinations: Array = []

## The acting combatant's core/rules/action_economy.gd ActionEconomy
## instance, as passed to configure() -- Stride spends one action from it
## (FEAT-014 / US-014). Step never uses this (see core/rules/movement.gd's
## file-level doc: Step is structurally incapable of touching an
## ActionEconomy). May be null -- stride_to() then rejects with
## ERR_ACTION_ECONOMY_MISSING rather than calling Movement.stride() with a
## null collaborator.
var _action_economy = null

var _last_error_code: String = ""
var _last_error_message: String = ""


## configure(actor, other_combatants, hex_grid_view, actor_id, action_economy) -> void
##
## actor             -- the acting combatant (Combatant instance or
##                       "hex_coord"-carrying Dictionary).
## other_combatants  -- every OTHER combatant on the battlefield (same
##                       duck-typed shapes), used for the occupancy check.
##                       `actor` must NOT be included.
## hex_grid_view     -- OPTIONAL presentation/hex_grid_view.gd collaborator;
##                       when supplied, a successful Step/Stride repositions
##                       `actor_id`'s token via move_token().
## actor_id          -- OPTIONAL identifier used to resolve `actor`'s token
##                       on `hex_grid_view` (combatant_id, falling back to
##                       "name" when omitted and `actor` carries one).
## action_economy    -- OPTIONAL (FEAT-014 / US-014) `actor`'s
##                       core/rules/action_economy.gd ActionEconomy instance
##                       for this round; required for stride_to() to succeed
##                       (Stride spends one action from it). Appended as the
##                       LAST parameter, after `actor_id`, so pre-existing
##                       callers that only ever configure() Step (and never
##                       pass this argument) are completely unaffected.
func configure(actor, other_combatants: Array, hex_grid_view = null, actor_id: String = "", action_economy = null) -> void:
	_actor = actor
	_other_combatants = other_combatants
	_hex_grid_view = hex_grid_view
	_actor_id = actor_id if actor_id != "" else _identifier_of(actor)
	_action_economy = action_economy
	_last_error_code = ""
	_last_error_message = ""
	_recompute_selectable_destinations()


## get_selectable_step_hexes() -> Array[HexCoord] -- the legal Step
## destinations for the currently configured actor right now, in the same
## order Movement.get_step_destinations() returned them.
func get_selectable_step_hexes() -> Array:
	return _selectable_destinations.duplicate()


## is_hex_selectable(hex_coord) -> bool -- true iff hex_coord names one of
## the currently selectable Step destinations.
func is_hex_selectable(hex_coord) -> bool:
	return _find_selectable(hex_coord) != null


## get_selectable_stride_hexes() -> Array[HexCoord] -- the legal Stride
## destinations for the currently configured actor right now, in the same
## order Movement.get_stride_destinations() returned them (FEAT-014 /
## US-014). Reflects only the distance/occupancy preconditions -- NOT
## whether `_action_economy` currently has an action available to spend (see
## core/rules/movement.gd's get_stride_destinations() doc); stride_to()
## still re-validates that via Movement.stride() itself.
func get_selectable_stride_hexes() -> Array:
	return _selectable_stride_destinations.duplicate()


## is_stride_hex_selectable(hex_coord) -> bool -- true iff hex_coord names
## one of the currently selectable Stride destinations (FEAT-014 / US-014).
func is_stride_hex_selectable(hex_coord) -> bool:
	return _find_selectable_stride(hex_coord) != null


## has_error() -> bool -- true iff the most recent step_to() call was
## rejected and its inline message has not yet been cleared by a subsequent
## successful Step.
func has_error() -> bool:
	return _last_error_code != ""


## get_last_error_message() -> String -- the non-blocking, human-readable
## inline message for the most recent rejected step_to() call, or "" if
## none/cleared.
func get_last_error_message() -> String:
	return _last_error_message


## step_to(destination_hex) -> Dictionary -- the player's chosen Step
## destination.
##
## When destination_hex names a currently selectable destination, forwards
## directly to core/rules/movement.gd Movement.step() (ADR-002: no duplicate
## movement path) and returns its result Dictionary verbatim.
##   - On success: repositions the actor's token on `_hex_grid_view` (if
##     supplied), re-derives `_selectable_destinations` from the actor's NEW
##     position (a Step can be followed by an immediate Strike whose reach
##     re-gates from the new hex -- this controller's own destination cache
##     must never go stale either), clears any prior inline error, emits
##     step_resolved, and returns the result.
##   - On rejection by Movement.step() itself (defense in depth -- should be
##     unreachable via normal input since this controller only offers
##     already-legal destinations): records a non-blocking inline message,
##     emits step_rejected, and returns the result verbatim.
##
## When destination_hex does NOT name a currently selectable destination
## (out of range, occupied, or unknown) -- including a stale/spoofed hex
## never offered as selectable -- this is rejected HERE, before
## Movement.step() is ever invoked: no positional mutation, no token
## reposition, no domain call at all. Returns
## {"ok": false, "resolved": false, "error": ERR_DESTINATION_NOT_SELECTABLE}.
func step_to(destination_hex) -> Dictionary:
	if _find_selectable(destination_hex) == null:
		return _fail(ERR_DESTINATION_NOT_SELECTABLE)

	var result: Dictionary = MovementClass.step(_actor, destination_hex, _other_combatants)

	if not result.get("ok", false):
		return _fail(result.get("error", ""))

	_last_error_code = ""
	_last_error_message = ""

	if _hex_grid_view != null and _actor_id != "":
		_hex_grid_view.move_token(_actor_id, destination_hex)

	_recompute_selectable_destinations()

	step_resolved.emit(result)
	return result


## stride_to(destination_hex) -> Dictionary -- the player's chosen Stride
## destination (FEAT-014 / US-014).
##
## When `_action_economy` was never configured, rejected HERE with
## ERR_ACTION_ECONOMY_MISSING -- Movement.stride() requires one to spend the
## action from and this controller never calls it with a null collaborator.
##
## When destination_hex names a currently selectable Stride destination,
## forwards directly to core/rules/movement.gd Movement.stride() (ADR-002:
## no duplicate movement path) and returns its result Dictionary verbatim.
##   - On success: repositions the actor's token on `_hex_grid_view` (if
##     supplied), re-derives BOTH `_selectable_destinations` and
##     `_selectable_stride_destinations` from the actor's NEW position (a
##     Stride can be followed by an immediate Strike whose reach re-gates
##     from the new hex, exactly like Step), clears any prior inline error,
##     emits stride_resolved, and returns the result.
##   - On rejection by Movement.stride() itself (defense in depth -- should
##     be unreachable via normal input since this controller only offers
##     already-legal destinations, though the action-economy budget can
##     still be exhausted or Movement-already-used by the time the player
##     acts): records a non-blocking inline message, emits stride_rejected,
##     and returns the result verbatim.
##
## When destination_hex does NOT name a currently selectable Stride
## destination (too far, occupied, or unknown) -- including a stale/spoofed
## hex never offered as selectable -- this is rejected HERE, before
## Movement.stride() is ever invoked: no positional mutation, no
## action-economy spend, no token reposition, no domain call at all. Returns
## {"ok": false, "resolved": false, "error": ERR_STRIDE_DESTINATION_NOT_SELECTABLE}.
func stride_to(destination_hex) -> Dictionary:
	if _action_economy == null:
		return _fail_stride(ERR_ACTION_ECONOMY_MISSING)

	if _find_selectable_stride(destination_hex) == null:
		return _fail_stride(ERR_STRIDE_DESTINATION_NOT_SELECTABLE)

	var result: Dictionary = MovementClass.stride(_actor, destination_hex, _action_economy, _other_combatants)

	if not result.get("ok", false):
		return _fail_stride(result.get("error", ""))

	_last_error_code = ""
	_last_error_message = ""

	if _hex_grid_view != null and _actor_id != "":
		_hex_grid_view.move_token(_actor_id, destination_hex)

	_recompute_selectable_destinations()

	stride_resolved.emit(result)
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

func _fail(error_code: String) -> Dictionary:
	_last_error_code = error_code
	_last_error_message = _ERROR_MESSAGES.get(error_code, _DEFAULT_ERROR_MESSAGE)
	step_rejected.emit(_last_error_message)
	return {"ok": false, "resolved": false, "error": error_code}


func _fail_stride(error_code: String) -> Dictionary:
	_last_error_code = error_code
	_last_error_message = _ERROR_MESSAGES.get(error_code, _DEFAULT_ERROR_MESSAGE)
	stride_rejected.emit(_last_error_message)
	return {"ok": false, "resolved": false, "error": error_code}


func _recompute_selectable_destinations() -> void:
	if _actor == null:
		_selectable_destinations = []
		_selectable_stride_destinations = []
		return
	_selectable_destinations = MovementClass.get_step_destinations(_actor, _other_combatants)
	_selectable_stride_destinations = MovementClass.get_stride_destinations(_actor, _other_combatants)
	if _hex_grid_view != null:
		_hex_grid_view.set_selectable_hexes(_selectable_destinations)


func _find_selectable(hex_coord):
	for candidate in _selectable_destinations:
		if candidate.equals(hex_coord):
			return candidate
	return null


func _find_selectable_stride(hex_coord):
	for candidate in _selectable_stride_destinations:
		if candidate.equals(hex_coord):
			return candidate
	return null


## _identifier_of(entity) -> String -- the same "combatant_id", falling back
## to "name" convention used by presentation/strike_action_control.gd's
## _target_id(), applied to either a Combatant instance or a Dictionary.
func _identifier_of(entity) -> String:
	if entity == null:
		return ""
	if entity is Dictionary:
		return entity.get("combatant_id", entity.get("name", ""))
	if "combatant_id" in entity and entity.combatant_id != "":
		return entity.combatant_id
	if "name" in entity:
		return entity.name
	return ""
