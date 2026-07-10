## core/domain/defense_mitigation_calculator.gd — DefenseMitigationCalculator
## (FEAT-002 / US-002)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/SceneTree inheritance, no engine I/O, and zero RNG
## consumption. Two static, side-effect-free predicates implementing this
## feature's design notes' pinned OnHitMitigation "governing constants":
##
##   PARRY worthwhile when (parry_attack_bonus + parry_bonus) >=
##         roll_total - 9
##         — a closed-form ">50% success" proxy: a d20 parry roll needs to
##           reach roll_total - modifier at least half the time, which
##           reduces to modifier >= roll_total - 9 (9 being the midpoint of
##           a d20's [1,18] "at least half the rolls succeed" band without
##           re-deriving probability at runtime).
##   BLOCK worthwhile when damage_raw > hp_current / 4
##         — a quarter-current-hp threshold below which spending a reaction
##           to mitigate isn't worth it.
##
## Consumed by infrastructure/ai_reaction_policy.gd's AIReactionPolicy (the
## enemy AI's ReactionChooserPort implementation) to decide whether Parry or
## Block is worth taking once an attack has already hit. Isolated here
## (rather than inlined into that infrastructure adapter) so a future
## balance pass touches only this domain service, never the AI wiring
## itself (per this feature's design notes' extension_points #3).
##
## Deliberately independent of core/rules/resolution.gd's own Parry/Block
## RESOLUTION math (which still owns the actual seeded dice rolls and
## reaction-spend side effects, e.g. the real d20 parry roll or block-die
## damage reduction) — this file only ever answers "would Parry/Block be
## worth attempting", never rolls dice and never mutates anything.
##
## Usage:
##   DefenseMitigationCalculator.parry_worthwhile(4, 4, 17)  # 8 >= 8  -> true
##   DefenseMitigationCalculator.block_worthwhile(6, 20)     # 6 > 5   -> true

class_name DefenseMitigationCalculator
extends RefCounted


## parry_worthwhile(parry_attack_bonus, parry_bonus, roll_total) -> bool
##
## Returns true iff `parry_attack_bonus + parry_bonus` is greater than or
## equal to `roll_total - 9` (the closed-form >50%-success threshold — see
## file-level doc). At-threshold (equal) counts as worthwhile.
##
## parry_attack_bonus — the reactor's own attack-roll bonus (attribute
##                        modifier + weapon proficiency), mirroring
##                        core/rules/resolution.gd's
##                        defense_context["parry_attack_bonus"].
## parry_bonus         — the reactor's weapon's parry_bonus.
## roll_total          — the attacker's already-rolled attack total (the
##                        value the parry roll must beat).
static func parry_worthwhile(parry_attack_bonus: int, parry_bonus: int, roll_total: int) -> bool:
	return (parry_attack_bonus + parry_bonus) >= (roll_total - 9)


## block_worthwhile(damage_raw, hp_current) -> bool
##
## Returns true iff `damage_raw` STRICTLY exceeds `hp_current / 4` — an
## exact quarter-hp match is NOT worthwhile (mirrors this file's/
## MobilityDodgeRule's established "strict exceed" convention). Uses true
## (float) division rather than integer-floored division so the threshold
## is exact even when hp_current is not a multiple of 4 (e.g. hp_current=21
## -> threshold 5.25, not floored to 5).
##
## damage_raw  — the already-rolled raw damage about to be applied.
## hp_current  — the reactor's current hit points.
static func block_worthwhile(damage_raw: int, hp_current: int) -> bool:
	return float(damage_raw) > (float(hp_current) / 4.0)
