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
##
## Stride (FR-013, US-014): move UP TO Speed (DEFAULT_SPEED = 4) hexes along
## adjacent hexes, consuming exactly ONE action from the mover's per-ROUND
## ActionEconomy budget (core/rules/action_economy.gd) via the "Movement"
## trait (the SAME per-turn movement gate action_economy.gd already
## documents — "only one movement action permitted per turn" — so a Stride
## and a subsequent Stride/other Movement-trait action in the same turn are
## mutually exclusive, exactly like any other Movement-trait action):
##   - "up to Speed"  — the hex_distance (core/geometry/hex_math.gd
##                      HexMath.hex_distance(), the same cube-coordinate
##                      distance metric used everywhere else in this
##                      codebase — there is no diagonal-cost concept on a hex
##                      grid) between the mover's current position and
##                      destination_hex must not exceed `speed` (defaults to
##                      DEFAULT_SPEED). Exceeding it is rejected with
##                      ERR_DESTINATION_EXCEEDS_SPEED.
##   - "one action"   — stride() spends exactly one action via the injected
##                      ActionEconomy's documented spend_action() Result
##                      contract, tagged with the "Movement" trait. A failed
##                      spend (budget exhausted OR a Movement-trait action
##                      already used this turn) is rejected with
##                      ERR_ACTION_UNAVAILABLE and NO positional mutation —
##                      the combatant is not moved at all if the action can't
##                      be paid for.
##   - "unoccupied"   — destination_hex must not be occupied by any entry of
##                      `other_combatants` (identical occupancy rule to
##                      step()).
##
## Strike reach re-gates after a successful Stride for the identical reason
## documented for Step above — melee reach is always recomputed from the
## CURRENT hex_coord, never cached in the domain.
##
## Usage:
##   var result := Movement.stride(combatant, destination_hex, action_economy, other_combatants)
##   # result -> {ok: true, resolved: true, hex_coord: destination_hex,
##   #            distance: int, budget_remaining: int}
##   #        or {ok: false, resolved: false, error: "ERR_...", ...}

class_name Movement

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## Typed error code returned by step() when `combatant` carries no
## hex_coord data at all (positional data is required to compute adjacency).
const ERR_ORIGIN_MISSING: String = "ERR_ORIGIN_MISSING"

## Typed error code returned by step() when `destination_hex` is not one of
## the mover's 6 flat-top axial neighbors (HexMath.hex_neighbors()).
const ERR_DESTINATION_NOT_ADJACENT: String = "ERR_DESTINATION_NOT_ADJACENT"

## Typed error code returned by step() when `destination_hex` is already
## occupied by another (living) combatant in `other_combatants`.
const ERR_DESTINATION_OCCUPIED: String = "ERR_DESTINATION_OCCUPIED"

## Default Stride distance (FR-013 / US-014): the maximum number of hexes a
## Stride may move in a single action, absent a per-combatant Speed
## attribute (not yet modeled as its own domain field — Speed is currently a
## fixed ruleset constant, matching the v0-release-2 spec's baseline Speed
## value of 4). Callers MAY override this via stride()'s `speed` parameter.
const DEFAULT_SPEED: int = 4

## Typed error code returned by stride() when destination_hex's
## HexMath.hex_distance() from the mover's current position exceeds `speed`
## (DEFAULT_SPEED absent an override) — a Stride may move UP TO Speed hexes,
## never more.
const ERR_DESTINATION_EXCEEDS_SPEED: String = "ERR_DESTINATION_EXCEEDS_SPEED"

## Typed error code returned by stride() when the injected ActionEconomy
## (core/rules/action_economy.gd) rejects the one-action Movement-trait spend
## a Stride requires — either the combatant's per-round budget is already
## exhausted (ALREADY_SPENT) or a Movement-trait action was already used this
## turn (MOVEMENT_ALREADY_USED). The underlying spend_action() Result's
## "reason" is echoed back verbatim under stride()'s own "reason" key.
const ERR_ACTION_UNAVAILABLE: String = "ERR_ACTION_UNAVAILABLE"


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


## stride(combatant, destination_hex, action_economy, other_combatants, speed) -> Dictionary
##
## combatant         — the mover; a Combatant instance or a Dictionary
##                      carrying "hex_coord" (see file-level doc).
## destination_hex    — a core/geometry/hex_coord.gd HexCoord: the hex being
##                      strode into. May be up to `speed` hexes away (in
##                      HexMath.hex_distance() terms) from the mover's
##                      current position — not limited to a single adjacent
##                      hex the way step() is.
## action_economy     — the mover's core/rules/action_economy.gd ActionEconomy
##                      instance for this round; stride() spends exactly ONE
##                      action from it, tagged with the "Movement" trait.
## other_combatants   — Array of every OTHER combatant on the battlefield
##                      (same duck-typed shapes as step()), used for the
##                      destination-occupancy check. The mover itself must
##                      NOT be included.
## speed              — OPTIONAL maximum hex_distance this Stride may cover;
##                      defaults to DEFAULT_SPEED (4).
##
## Preconditions are checked in this order, with NO side effects on failure
## (neither combatant.hex_coord NOR action_economy is touched):
##   1. combatant must carry hex_coord data (else ERR_ORIGIN_MISSING)
##   2. destination_hex must not be occupied by any entry of
##      other_combatants (else ERR_DESTINATION_OCCUPIED)
##   3. destination_hex's hex_distance from the mover's current position must
##      not exceed `speed` (else ERR_DESTINATION_EXCEEDS_SPEED)
##   4. action_economy.spend_action() (tagged "Movement") must succeed (else
##      ERR_ACTION_UNAVAILABLE, with the underlying Result's "reason" echoed
##      back)
##
## On success, mutates `combatant`'s position in place (identical mutation
## point to step(), _set_hex()) and returns {ok: true, resolved: true,
## hex_coord: destination_hex, distance: int, budget_remaining: int}.
static func stride(
	combatant,
	destination_hex,
	action_economy,
	other_combatants: Array,
	speed: int = DEFAULT_SPEED
) -> Dictionary:
	var origin = _hex_of(combatant)
	if origin == null:
		return {"ok": false, "resolved": false, "error": ERR_ORIGIN_MISSING}

	if _is_occupied(destination_hex, other_combatants):
		return {"ok": false, "resolved": false, "error": ERR_DESTINATION_OCCUPIED}

	var distance: int = HexMathClass.hex_distance(origin, destination_hex)
	if distance > speed:
		return {"ok": false, "resolved": false, "error": ERR_DESTINATION_EXCEEDS_SPEED}

	var spend_result: Dictionary = action_economy.spend_action({"name": "Stride", "traits": ["Movement"]})
	if not spend_result.get("success", false):
		return {
			"ok": false,
			"resolved": false,
			"error": ERR_ACTION_UNAVAILABLE,
			"reason": spend_result.get("reason", ""),
		}

	_set_hex(combatant, destination_hex)
	return {
		"ok": true,
		"resolved": true,
		"hex_coord": destination_hex,
		"distance": distance,
		"budget_remaining": spend_result.get("remaining", -1),
	}


## get_stride_destinations(combatant, other_combatants, speed) -> Array[HexCoord]
##
## The full set of legal Stride destinations for `combatant` right now: every
## hex within `speed` hex_distance (inclusive, excluding the mover's own
## current hex) of its current position that is NOT occupied by any entry of
## `other_combatants`. Pure/read-only — computes nothing that stride()
## doesn't already enforce for the distance/occupancy preconditions
## (ActionEconomy availability is NOT reflected here — a Presentation
## controller should separately gate offering Stride at all when the actor
## has no action budget left, mirroring how it already gates Strike), so a
## Presentation controller (e.g. presentation/movement_input_controller.gd)
## can render selectable destinations by calling this SAME domain function
## rather than re-deriving the distance/occupancy rule itself (ADR-001).
static func get_stride_destinations(combatant, other_combatants: Array, speed: int = DEFAULT_SPEED) -> Array:
	var origin = _hex_of(combatant)
	if origin == null:
		return []

	var destinations: Array = []
	for candidate in _hex_range(origin, speed):
		if not _is_occupied(candidate, other_combatants):
			destinations.append(candidate)
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


## _hex_range(origin, radius) -> Array[HexCoord] — every HexCoord within
## `radius` hex_distance of `origin` (inclusive), EXCLUDING `origin` itself.
## Standard cube-coordinate range enumeration (identical result to filtering
## every candidate by HexMath.hex_distance() <= radius, just without the
## O(radius^2) distance recomputation per candidate) — used by
## get_stride_destinations() so a Stride's "up to Speed hexes" affordance
## reuses the SAME distance semantics stride() itself enforces via
## HexMath.hex_distance(), never a re-derived/forked notion of range.
static func _hex_range(origin, radius: int) -> Array:
	var results: Array = []
	for dq in range(-radius, radius + 1):
		var r_min: int = max(-radius, -dq - radius)
		var r_max: int = min(radius, -dq + radius)
		for dr in range(r_min, r_max + 1):
			if dq == 0 and dr == 0:
				continue
			results.append(HexCoordClass.new(origin.q + dq, origin.r + dr))
	return results
