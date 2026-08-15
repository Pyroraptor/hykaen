## core/combat/hex_scorer.gd — HexScorer (FEAT-004 / US-004 / FR-011 / ADR-005)
##
## Domain layer (Clean Architecture): a pure, stateless scoring UTILITY —
## no Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O, no orchestration, no persistence. A stateless namespace of
## `static func`s (matching the existing pure-function convention already
## established by core/rules/movement.gd and core/geometry/hex_math.gd),
## exposing score_hex(hex, actor, context) -> float as a STABLE extension
## point for future tactical AI (RISK-008 mitigation): the signature is
## fixed and tested now, well ahead of any cover/terrain system actually
## being wired up.
##
## Per NFR-005 (scope exclusion for this iteration), NO cover system and NO
## terrain system exist yet. score_hex() therefore always returns 0.0 for
## any input — there is nothing yet to differentiate one hex's tactical
## value from another's. The two named hooks below,
## cover_bonus_hook()/terrain_bonus_hook(), exist purely so a future
## iteration can wire in real cover/terrain scoring by editing ONLY those
## two functions' bodies, without ever needing to change score_hex()'s
## signature or any caller of it — they are EXPLICITLY zero-weighted
## placeholders today (each always contributes exactly 0.0 to the total),
## not a hidden/undocumented stub.
##
## `hex` / `actor` / `context` are all deliberately duck-typed and
## unconstrained by this feature:
##   - hex     — expected to be a core/geometry/hex_coord.gd HexCoord (or
##               any HexCoord-shaped value); NOT dereferenced by this
##               feature's zero-weighted implementation, so any value
##               (including null) is accepted without error.
##   - actor   — expected to be a combatant (Combatant instance or
##               Dictionary, the same duck-typed shape already used
##               throughout core/combat/, e.g. core/combat/mindless_ai.gd);
##               NOT dereferenced by this feature's implementation.
##   - context — expected to be a world-context Dictionary (the same shape
##               core/application/round_session.gd's future
##               _build_ai_world_context() DTO will supply — party/
##               enemies/action_economy); NOT dereferenced by this
##               feature's implementation.
## Because none of the three parameters are dereferenced yet, score_hex()
## (and both hooks) never push_error()s and never raises for ANY input,
## including null — this is deliberate: a stable, always-safe extension
## point that future callers (planners) can start wiring calls to before
## the scoring logic itself exists, without risking a crash.
##
## Usage:
##   var score: float = HexScorer.score_hex(candidate_hex, combatant, world_context)
##   # score == 0.0 today, always (no cover/terrain system wired yet)

class_name HexScorer


## score_hex(hex, actor, context) -> float — the stable scoring entry point
## future tactical AI planners will call to rank candidate hexes. Returns
## the sum of every scoring contribution; today that is exactly
## cover_bonus_hook() + terrain_bonus_hook(), both explicitly zero-weighted,
## so score_hex() always returns 0.0 (see file-level doc / NFR-005).
static func score_hex(hex, actor, context) -> float:
	var total: float = 0.0
	total += cover_bonus_hook(hex, actor, context)
	total += terrain_bonus_hook(hex, actor, context)
	return total


## cover_bonus_hook(hex, actor, context) -> float — placeholder extension
## point for a future cover system (e.g. line-of-sight/partial-cover
## scoring). Explicitly zero-weighted: ALWAYS returns 0.0 in this feature,
## by design (no cover system exists yet — NFR-005 scope exclusion). Exists
## now, with this exact signature, so score_hex()'s callers and this
## function's own call site never need to change when cover scoring is
## eventually implemented — only this function's body will.
static func cover_bonus_hook(_hex, _actor, _context) -> float:
	return 0.0


## terrain_bonus_hook(hex, actor, context) -> float — placeholder extension
## point for a future terrain system (e.g. elevation/difficult-terrain
## scoring). Explicitly zero-weighted: ALWAYS returns 0.0 in this feature,
## by design (no terrain system exists yet — NFR-005 scope exclusion). See
## cover_bonus_hook() above for the identical stability rationale.
static func terrain_bonus_hook(_hex, _actor, _context) -> float:
	return 0.0
