## core/domain/mobility_dodge_rule.gd — MobilityDodgeRule (FEAT-002 / US-002)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/SceneTree inheritance, no engine I/O, and zero RNG
## consumption. A single static, side-effect-free predicate implementing the
## Dodge-worthwhile rule this feature's design notes pin (PreHitAvoidance
## window, "governing constants"):
##
##   DODGE if 10 + mobility_skill > targeted_defense_value, else Pass.
##
## Consumed by infrastructure/ai_reaction_policy.gd's AIReactionPolicy (the
## enemy AI's ReactionChooserPort implementation) to decide whether Dodge is
## worth taking, given the reactor's Mobility skill and the attack's
## effective targeted defense value. Isolated here (rather than inlined
## directly into that infrastructure adapter) so a future balance pass — new
## enemy archetypes, a higher Mobility skill cap — touches only this domain
## service, never the AI wiring itself (per this feature's design notes'
## extension_points #3).
##
## Deliberately independent of core/rules/resolution.gd's own Dodge
## trigger/roll math (which still owns the actual seeded d20 roll and
## reaction-spend side effects) — this file only ever answers "would Dodge
## be worth attempting", never rolls dice and never mutates anything.
##
## Usage:
##   MobilityDodgeRule.dodge_worthwhile(1, 10)   # 10+1=11 > 10  -> true
##   MobilityDodgeRule.dodge_worthwhile(0, 10)   # 10+0=10 == 10 -> false

class_name MobilityDodgeRule
extends RefCounted


## dodge_worthwhile(mobility, targeted_defense_value) -> bool
##
## Returns true iff `10 + mobility` STRICTLY exceeds
## `targeted_defense_value` — an exact tie is NOT worthwhile (mirrors this
## project's established "strict exceed" convention for opposed checks, see
## core/rules/resolution.gd's Parry branch: `parry_roll > roll_total`, never
## `>=`).
##
## mobility               — the reactor's Mobility skill (may be negative).
## targeted_defense_value — the passive defense value (AC/Reflex) the
##                            incoming attack is being resolved against.
static func dodge_worthwhile(mobility: int, targeted_defense_value: int) -> bool:
	return (10 + mobility) > targeted_defense_value
