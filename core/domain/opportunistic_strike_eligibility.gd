## core/domain/opportunistic_strike_eligibility.gd — OpportunisticStrikeEligibility
## (iteration K FEAT-006 / US-006)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/SceneTree inheritance, no engine I/O, and zero RNG
## consumption. A single static, side-effect-free predicate implementing this
## feature's design notes' pinned "Opportunistic Strike eligibility"
## governing constant:
##
##   eligible = adjacent (to the mover's START hex) && hostile && !Spent &&
##              melee reach
##
## Consumed by core/application/use_cases/resolve_stride_use_case.gd's
## ResolveStrideUseCase to filter the candidate reactor pool BEFORE any
## OpportunisticStrike reaction window is opened for a Stride — this is the
## seam that guarantees a window is only ever offered to a combatant who
## could genuinely take the strike, mirroring core/domain/
## mobility_dodge_rule.gd's / core/domain/defense_mitigation_calculator.gd's
## own "isolated here so a future balance pass touches only this domain
## service" rationale (design notes' extension_points #3).
##
## `reactor`/`mover` are plain Dictionaries, matching this codebase's
## established combatant-dict shape (core/combat/ai.gd, core/rules/
## movement.gd, core/application/resolve_action_use_case.gd) rather than the
## FEAT-001 core/domain/combatant.gd Combatant entity — every live
## composition-root call site (core/combat/ai.gd, MainScene.gd) already
## operates on this Dictionary shape, never the Combatant class.
##
## Fields consulted (all default-safe — a missing key never crashes, it just
## fails the corresponding check):
##   "hex_coord"  — a core/geometry/hex_coord.gd HexCoord (adjacency).
##   "_is_enemy"  — bool, the SAME faction tag core/combat/encounter.gd's
##                  initialize() stamps on every combatant Dictionary this
##                  codebase resolves a turn order from (hostility).
##   "weapon"     — Dictionary; carries "range_hexes" for a RANGED weapon
##                  (mirrors core/combat/ai.gd's _is_ranged_weapon() /
##                  core/application/resolve_action_use_case.gd's
##                  identically-behaved helper) — melee reach.
##
## `reactor_spent` is a plain bool rather than an injected ActionEconomy
## instance — this file stays pure domain (no core/rules/action_economy.gd
## import); the caller is responsible for resolving "is this reactor's
## reaction already spent" (e.g. via ActionEconomy.is_spent()) and passing
## the answer in.
##
## Usage:
##   OpportunisticStrikeEligibility.eligible(reactor, mover, mover_start_hex)
##   # true iff reactor is adjacent to mover_start_hex, hostile to mover, has
##   # a melee weapon, and reactor_spent (default false) is false.

class_name OpportunisticStrikeEligibility
extends RefCounted

const HexMathClass = preload("res://core/geometry/hex_math.gd")


## eligible(reactor, mover, mover_start_hex, reactor_spent) -> bool — see
## class-level doc for the full contract. Checks are short-circuited in this
## order (matching this feature's test_criteria: "correctly filters
## non-adjacent, non-hostile, Spent, and non-melee-reach candidates"):
##   1. reactor_spent — a Spent reactor has no reaction left to spend.
##   2. hostile        — reactor._is_enemy must differ from mover._is_enemy.
##   3. adjacent        — reactor.hex_coord must be one of mover_start_hex's
##                        6 flat-top axial neighbors.
##   4. melee reach     — reactor's weapon must NOT carry "range_hexes" (a
##                        ranged weapon has no opportunistic MELEE strike to
##                        make).
static func eligible(reactor: Dictionary, mover: Dictionary, mover_start_hex, reactor_spent: bool = false) -> bool:
	if reactor_spent:
		return false
	if not _is_hostile(reactor, mover):
		return false
	if not _is_adjacent(reactor, mover_start_hex):
		return false
	if not _has_melee_reach(reactor):
		return false
	return true


## _is_hostile(reactor, mover) -> bool — true iff the two combatants carry
## opposite "_is_enemy" tags (core/combat/encounter.gd's initialize()). Both
## missing/defaulting to false (an untagged fixture) reads as "not hostile" —
## the safe default (never offers an opportunistic strike against an
## unrecognized/ambiguous faction).
static func _is_hostile(reactor: Dictionary, mover: Dictionary) -> bool:
	return reactor.get("_is_enemy", false) != mover.get("_is_enemy", false)


## _is_adjacent(reactor, mover_start_hex) -> bool — true iff reactor.hex_coord
## is one of mover_start_hex's 6 flat-top axial neighbors
## (core/geometry/hex_math.gd HexMath.hex_neighbors()) — the SAME adjacency
## rule melee Strike reach/Step already use (ADR-001: one shared domain rule,
## never re-derived).
static func _is_adjacent(reactor: Dictionary, mover_start_hex) -> bool:
	var reactor_hex = reactor.get("hex_coord", null)
	if reactor_hex == null or mover_start_hex == null:
		return false
	for neighbor in HexMathClass.hex_neighbors(mover_start_hex):
		if neighbor.equals(reactor_hex):
			return true
	return false


## _has_melee_reach(reactor) -> bool — true iff reactor's weapon Dictionary
## does NOT carry a "range_hexes" key — mirrors core/combat/ai.gd's
## _is_ranged_weapon()/core/application/resolve_action_use_case.gd's
## identically-behaved helper exactly (never a re-derived notion of "melee").
static func _has_melee_reach(reactor: Dictionary) -> bool:
	var weapon: Dictionary = reactor.get("weapon", {})
	return not weapon.has("range_hexes")
