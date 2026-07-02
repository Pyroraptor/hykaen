## core/rules/movement.gd — Movement (FEAT-013 / US-013 / FR-012)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. A stateless
## namespace of `static func`s (matching the existing pure-function
## convention established by core/geometry/hex_math.gd), operating on
## flat-top axial HexCoord (q, r) values (core/geometry/hex_coord.gd) via
## the existing hex adjacency utility (core/geometry/hex_math.gd
## HexMath.hex_neighbors()) — no new geometry is invented here.
##
## Step (FR-012, US-013): a FREE, no-action-economy-cost, no-reaction move of
## exactly 1 hex to an adjacent UNOCCUPIED hex:
##   - "free"        — step() never touches an ActionEconomy instance
##                      (core/rules/action_economy.gd) at all. Callers do NOT
##                      pass one in, and step() has no parameter for one — it
##                      is structurally impossible for a Step to decrement a
##                      combatant's action budget or mark it Spent.
##   - "no reaction"  — for the identical reason: step() never calls
##                      ActionEconomy.spend_reaction() (or anything else) —
##                      no code path exists here that could provoke one.
##   - "1 hex"        — the destination must be one of the mover's 6 flat-top
##                      axial neighbors (HexMath.hex_neighbors()), exactly the
##                      same adjacency rule melee Strike reach already uses
##                      (core/application/resolve_action_use_case.gd), so a
##                      Step and a melee neighbor are always the same set.
##   - "unoccupied"   — the destination must not be any OTHER living
##                      combatant's current hex_coord (self is naturally
##                      excluded — `other_combatants` is the caller-supplied
##                      list of every combatant EXCEPT the mover).
##
## `combatant`/entries of `other_combatants` are duck-typed to accept either
## shape already used across this codebase for a combatant's positional
## data:
##   - a core/domain/combatant.gd Combatant instance (hex_coord field,
##     move_to() mutator) — the FEAT-001 domain entity, or
##   - a Dictionary carrying a "hex_coord" key (the shape
##     core/application/resolve_action_use_case.gd's `combatant`/`target`
##     parameters already use) — so this same Movement rule can drive both
##     the pure-domain Combatant model AND the interactive Dictionary-based
##     combat pipeline MainScene.gd wires today, without either side
##     duplicating the adjacency/occupancy rule.
##
## After a successful Step, Strike reach is automatically re-gated: melee
## reach (core/application/resolve_action_use_case.gd) always recomputes
## HexMath.hex_neighbors() from the combatant's CURRENT hex_coord at the
## moment a Strike is attempted — there is no separately cached reach set in
## the domain to go stale. (Presentation-layer caches, e.g.
## presentation/strike_action_control.gd's _selectable_targets, are
## re-derived by their own configure() call — a Presentation-layer
## responsibility, not this file's.)
##
## Usage:
##   var result := Movement.step(combatant, destination_hex, other_combatants)
##   # result -> {ok: true, resolved: true, hex_coord: destination_hex}
##   #        or {ok: false, resolved: false, error: "ERR_..."}

class_name Movement

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## Typed error code returned by step() when `combatant` carries no
## hex_coord data at all (positional data is required to compute adjacency).
const ERR_ORIGIN_MISSING: String = "ERR_ORIGIN_MISSING"

## Typed error code returned by step() when `destination_hex` is not one of
## the mover's 6 flat-top axial neighbors (HexMath.hex_neighbors()).
const ERR_DESTINATION_NOT_ADJACENT: String = "ERR_DESTINATION_NOT_ADJACENT"

## Typed error code returned by step() when `destination_hex` is already
## occupied by another (living) combatant in `other_combatants`.
const ERR_DESTINATION_OCCUPIED: String = "ERR_DESTINATION_OCCUPIED"


## step(combatant, destination_hex, other_combatants) -> Dictionary
##
## combatant         — the mover; a Combatant instance or a Dictionary
##                      carrying "hex_coord" (see file-level doc).
## destination_hex    — a core/geometry/hex_coord.gd HexCoord: the single hex
##                      being stepped into.
## other_combatants   — Array of every OTHER combatant on the battlefield
##                      (Combatant instances and/or "hex_coord"-carrying
##                      Dictionaries, may be mixed) used for the occupancy
##                      check. The mover itself must NOT be included.
##
## Preconditions are checked in this order, with NO side effects on failure
## (combatant.hex_coord is left completely untouched):
##   1. combatant must carry hex_coord data (else ERR_ORIGIN_MISSING)
##   2. destination_hex must be one of combatant's 6 flat-top axial
##      neighbors (else ERR_DESTINATION_NOT_ADJACENT)
##   3. destination_hex must not be occupied by any entry of
##      other_combatants (else ERR_DESTINATION_OCCUPIED)
##
## On success, mutates `combatant`'s position in place (via move_to() for a
## Combatant instance, or the "hex_coord" key for a Dictionary — Dictionaries
## are reference types in GDScript, so every other holder of the SAME
## Dictionary instance observes the update immediately) and returns
## {ok: true, resolved: true, hex_coord: destination_hex}.
##
## step() NEVER reads or writes an ActionEconomy instance and NEVER calls
## spend_reaction() — see the "free"/"no reaction" file-level doc above.
static func step(combatant, destination_hex, other_combatants: Array) -> Dictionary:
	var origin = _hex_of(combatant)
	if origin == null:
		return {"ok": false, "resolved": false, "error": ERR_ORIGIN_MISSING}

	if not _is_adjacent(origin, destination_hex):
		return {"ok": false, "resolved": false, "error": ERR_DESTINATION_NOT_ADJACENT}

	if _is_occupied(destination_hex, other_combatants):
		return {"ok": false, "resolved": false, "error": ERR_DESTINATION_OCCUPIED}

	_set_hex(combatant, destination_hex)
	return {"ok": true, "resolved": true, "hex_coord": destination_hex}


## get_step_destinations(combatant, other_combatants) -> Array[HexCoord]
##
## The full set of legal Step destinations for `combatant` right now: exactly
## the subset of its 6 flat-top axial neighbors (HexMath.hex_neighbors())
## that are NOT occupied by any entry of `other_combatants`. Pure/read-only —
## computes nothing that step() doesn't already enforce, so a Presentation
## controller (e.g. presentation/movement_input_controller.gd) can render
## selectable destinations by calling this SAME domain function rather than
## re-deriving the adjacency/occupancy rule itself (ADR-001: UI only reads/
## derives from domain logic).
static func get_step_destinations(combatant, other_combatants: Array) -> Array:
	var origin = _hex_of(combatant)
	if origin == null:
		return []

	var destinations: Array = []
	for neighbor in HexMathClass.hex_neighbors(origin):
		if not _is_occupied(neighbor, other_combatants):
			destinations.append(neighbor)
	return destinations


# ── Internal helpers ─────────────────────────────────────────────────────

## _hex_of(entity) -> HexCoord or null — reads positional data from either a
## Combatant instance (hex_coord field) or a Dictionary ("hex_coord" key).
static func _hex_of(entity):
	if entity is Dictionary:
		return entity.get("hex_coord", null)
	return entity.hex_coord


## _set_hex(entity, hex_coord) -> void — the sole mutation point: a
## Combatant instance is updated via its own move_to() mutator
## (core/domain/combatant.gd); a Dictionary has its "hex_coord" key replaced
## directly (Dictionaries have no move_to() method of their own).
static func _set_hex(entity, hex_coord) -> void:
	if entity is Dictionary:
		entity["hex_coord"] = hex_coord
	else:
		entity.move_to(hex_coord)


## _is_adjacent(origin, destination_hex) -> bool — true iff destination_hex
## is one of origin's 6 flat-top axial neighbors (HexMath.hex_neighbors()).
static func _is_adjacent(origin, destination_hex) -> bool:
	for neighbor in HexMathClass.hex_neighbors(origin):
		if neighbor.equals(destination_hex):
			return true
	return false


## _is_occupied(hex_coord, other_combatants) -> bool — true iff any entry of
## other_combatants currently occupies hex_coord.
static func _is_occupied(hex_coord, other_combatants: Array) -> bool:
	for other in other_combatants:
		var other_hex = _hex_of(other)
		if other_hex != null and other_hex.equals(hex_coord):
			return true
	return false
