## core/controllers/strike_action_controller.gd — StrikeActionController
## (FEAT-006, Iteration O "Combine Selection UX"; US-006; FR-005; ADR-006).
##
## Adapter layer (Clean Architecture, ADR-001): mirrors this file's sibling
## core/controllers/stride_action_controller.gd's own file-level doc — the
## "API" boundary for verb controllers is enter_selection()/execute()
## (core/application/combine/verb_controller_port.gd's VerbControllerPort),
## so this class lives under the adapters/infrastructure side of the
## dependency arrow despite sitting physically under core/. Depends on the
## APPLICATION port (VerbControllerPort, extended below) and the DOMAIN hex
## math utility (core/geometry/hex_math.gd — pure, engine-free), never the
## other way around.
##
## THIS FEATURE'S SCOPE (US-006; FR-005; ADR-006) — "post-move-aware
## targeting for chained sub-actions": enter_selection() computes
## candidate_targets from the HYPOTHETICAL Stride destination hex threaded
## through `context['accumulated']['STRIDE'].meta['chosen_hex']` (the SAME
## field core/controllers/stride_action_controller.gd's own enter_selection()
## writes when a Stride selection has been resolved — see that file's own
## doc) rather than the actor's CURRENT REAL position, whenever a prior
## chained STRIDE phase resolved one. Falls back to the actor's own live
## `hex_coord` when no such accumulated selection exists (e.g. a standalone
## Strike, or a Strike that is the FIRST entry of its own queue) — so this
## controller's targeting is unaffected when it is not chained after a
## Stride, exactly the same reach computation
## presentation/strike_action_controller.gd's own reachable_target_ids()
## already performs, just parameterized on an origin hex instead of always
## reading `actor.hex_coord` directly.
##
## Never mutates the actor: this file reads `accumulated['STRIDE']`'s
## already-resolved `meta['chosen_hex']` purely as a HYPOTHETICAL origin for
## its own reach computation — it never writes back to the actor's real
## `hex_coord`, and never calls any Movement mutator. The actor's real
## position is therefore NOT mutated by any enter_selection() call this
## controller makes (design notes' test_criteria: "Actor's real position is
## NOT mutated during enter_selection() calls (only inside execute()'s
## resolution_log processing)").
##
## This file's own execute() is NOT overridden here — mirrors
## stride_action_controller.gd's own file-level doc: VerbControllerPort's
## abstract default already satisfies the ADR-002 "registered controllers
## expose both enter_selection and execute" contract check; real
## sub-action resolution/execute() wiring for this NEW core/controllers/
## seam is a later feature layered on top of this same seam.
##
## Domain purity boundary (ADR-001): extends VerbControllerPort (itself
## RefCounted-only) — no Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage:
##   var controller := StrikeActionController.new({
##       "candidate_targets_fn": Callable(self, "_living_enemy_reactors"),
##   })
##   # Standalone (no prior Stride in this queue) -- reach from the actor's
##   # OWN current position:
##   var offer: Object = controller.enter_selection({"actor_id": actor, "order_index": 0})
##
##   # Chained after a resolved Stride -- reach from the HYPOTHETICAL
##   # post-move hex, actor.hex_coord untouched:
##   var chained: Object = controller.enter_selection({
##       "actor_id": actor, "order_index": 1,
##       "accumulated": {"STRIDE": stride_descriptor},
##   })

class_name StrikeActionController
extends "res://core/application/combine/verb_controller_port.gd"

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")

## candidate_targets_fn — Callable() -> Array of every currently-living
## potential target (Combatant instances exposing hex_coord/display_id(),
## mirroring presentation/strike_action_controller.gd's own
## `_living_enemies_fn` convention). Defaults to an invalid Callable, in
## which case no candidates are offered (a fail-safe NO_LEGAL_OPTIONS
## response, never a crash).
var _candidate_targets_fn: Callable


func _init(deps: Dictionary = {}) -> void:
	_candidate_targets_fn = deps.get("candidate_targets_fn", Callable())


## enter_selection(context) -> SelectionDescriptor
##
## context — {actor_id: <Combatant>, order_index: int,
##            accumulated: {"STRIDE": <SelectionDescriptor, optional>}, ...}.
##
## Returns:
##   {ok:true, candidate_targets: <target_ids reachable from the post-move
##    hex when accumulated['STRIDE'].meta['chosen_hex'] is set, else from
##    the actor's own current hex_coord>, meta: {"origin_hex": <the hex this
##    descriptor's reach was computed from>}}
##   {ok:false, error_code:"NO_LEGAL_OPTIONS"} — no live actor, no resolvable
##    origin hex, or zero targets in reach from that origin.
func enter_selection(context: Dictionary) -> Object:
	var actor = context.get("actor_id")
	var order_index: int = context.get("order_index", 0)
	if actor == null:
		return _failure(order_index)

	var origin_hex = _post_move_hex(context, actor)
	if origin_hex == null:
		return _failure(order_index)

	var candidates: Array = _candidate_targets_fn.call() if _candidate_targets_fn.is_valid() else []
	var reachable: Array = _reachable_from(origin_hex, actor, candidates)
	if reachable.is_empty():
		return _failure(order_index)

	var target_ids: Array = []
	for target in reachable:
		target_ids.append(_target_id(target))

	return SelectionDescriptorClass.new(true, [], [], target_ids, order_index, {"origin_hex": origin_hex})


## _post_move_hex(context, actor) -> HexCoord or null — ADR-006: the
## HYPOTHETICAL origin this phase's reach is computed from. Reads
## `context['accumulated']['STRIDE']`'s already-resolved
## `meta['chosen_hex']` when present (a prior chained Stride phase in the
## SAME Combine queue) — falling back to the actor's own LIVE, real
## `hex_coord` otherwise (standalone Strike / no chained Stride). Never
## mutates `actor` — purely reads.
func _post_move_hex(context: Dictionary, actor):
	var accumulated: Dictionary = context.get("accumulated", {})
	var stride_selection = accumulated.get("STRIDE")
	if stride_selection != null:
		var chosen_hex = stride_selection.meta.get("chosen_hex")
		if chosen_hex != null:
			return chosen_hex
	return actor.hex_coord


## _reachable_from(origin_hex, actor, candidates) -> Array — the SAME
## melee-adjacency/ranged-distance reach rule
## presentation/strike_action_controller.gd's own _reachable_targets()
## already enforces (HexMath.hex_neighbors() for melee,
## HexMath.hex_distance() <= actor.weapon.range_hexes for ranged) —
## parameterized on `origin_hex` instead of always reading `actor.hex_coord`
## directly, so this is the SAME rule, not a forked one.
func _reachable_from(origin_hex, actor, candidates: Array) -> Array:
	var in_reach: Array = []

	if _actor_is_ranged(actor):
		var range_hexes: int = actor.weapon.get("range_hexes", 1)
		for target in candidates:
			var target_hex = target.hex_coord
			if target_hex != null and HexMathClass.hex_distance(origin_hex, target_hex) <= range_hexes:
				in_reach.append(target)
		return in_reach

	var neighbors: Array = HexMathClass.hex_neighbors(origin_hex)
	for target in candidates:
		var target_hex = target.hex_coord
		if target_hex == null:
			continue
		for neighbor in neighbors:
			if neighbor.equals(target_hex):
				in_reach.append(target)
				break
	return in_reach


func _actor_is_ranged(actor) -> bool:
	return actor.weapon.has("range_hexes")


func _target_id(target) -> String:
	return target.display_id()


## _failure(order_index) -> SelectionDescriptor — the SOLE failure-shape
## constructor this file uses, mirroring
## stride_action_controller.gd's own `_failure()` convention.
func _failure(order_index: int) -> Object:
	return SelectionDescriptorClass.new(false, [], [], [], order_index, {"error_code": "NO_LEGAL_OPTIONS"})
