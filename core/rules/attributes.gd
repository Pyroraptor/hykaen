## core/rules/attributes.gd — Attribute and Derived-Stat Computation Module
##
## Domain layer (ADR-001): no Node/Control inheritance — pure game logic only.
## Constructor accepts a ClassResource and an RNG instance (ADR-002 injection).
##
## ADR-010 (point-buy only), ADR-011 (passive defense always-on),
## ADR-012 (Tier 1 / Level 1 fixed formulas):
##   All derived-stat formulas are deterministic given attribute scores and class data.
##   Random output (roll_initiative) routes through the injected _rng, never
##   through a locally-created RandomNumberGenerator.
##
## Attribute score keys used throughout (Dictionary):
##   strength, constitution, dexterity, willpower, intellect, intuition, social
##
## Usage example:
##   var attrs = Attributes.new(rng)
##   var validation = attrs.point_buy_validate(my_scores)
##   var hp = attrs.compute_hp(my_scores, fighter_class_data)

class_name Attributes

## Point-buy cost table — score value maps to spend cost (ADR-010).
const COST_TABLE: Dictionary = {1: 1, 2: 2, 3: 4, 4: 6, 5: 9, 6: 12}

## Maximum total point-buy budget (ADR-010).
const MAX_BUY: int = 27


var _rng  # RNG — injected at construction; never instantiated here (ADR-002)


## Constructor.
## rng — an RNG instance (core/rules/rng.gd) injected from outside.
func _init(rng) -> void:
	_rng = rng


# ── Point-Buy Validation ────────────────────────────────────────────────────

## point_buy_validate(scores: Dictionary) → Dictionary
##
## Validates a complete attribute score allocation against the point-buy rules.
##
## All seven scores (strength, constitution, dexterity, willpower, intellect,
## intuition, social) must be integers in [1, 6].  The sum of their costs
## (from COST_TABLE) must not exceed MAX_BUY (27).
##
## Returns:
##   {valid: bool, cost: int, error: String}
##     valid — true iff all scores are in range and total cost ≤ 27
##     cost  — total spend computed from COST_TABLE (0 on range error)
##     error — human-readable failure reason; empty string on success
func point_buy_validate(scores: Dictionary) -> Dictionary:
	var total_cost: int = 0
	for key in scores:
		var score: int = scores[key]
		if score < 1 or score > 6:
			return {
				"valid": false,
				"cost": 0,
				"error": "Score '%s' is %d — all scores must be in range [1, 6]" % [key, score]
			}
		total_cost += COST_TABLE[score]

	if total_cost > MAX_BUY:
		return {
			"valid": false,
			"cost": total_cost,
			"error": "Point-buy cost %d exceeds maximum of 27" % total_cost
		}

	return {"valid": true, "cost": total_cost, "error": ""}


# ── Derived-Stat Formulas (ADR-011, ADR-012, Tier 1 / Level 1) ─────────────

## compute_hp(scores: Dictionary, class_data: ClassResource) → int
##
## Formula: 8 + class_data.class_hp + scores.constitution
## Example (Fighter, constitution 4): 8 + 6 + 4 = 18
func compute_hp(scores: Dictionary, class_data) -> int:
	return 8 + class_data.class_hp + scores["constitution"]


## compute_stamina(scores: Dictionary, class_data: ClassResource) → int
##
## Formula: class_data.stamina_base + scores.willpower + scores.constitution
## Example (Fighter, willpower 2, constitution 4): 4 + 2 + 4 = 10
func compute_stamina(scores: Dictionary, class_data) -> int:
	return class_data.stamina_base + scores["willpower"] + scores["constitution"]


## compute_ac(scores: Dictionary, armor_base: int, armor_category: String) → int
##
## Formula: 10 + armor_base + (dexterity if armor_category in ['light','none'] else 0)
## DEX bonus applies only for light and unarmored (none) categories.
## Examples:
##   medium armor, base 4, dex 3: 10 + 4 + 0 = 14
##   light  armor, base 2, dex 3: 10 + 2 + 3 = 15
##   none        , base 0, dex 3: 10 + 0 + 3 = 13
func compute_ac(scores: Dictionary, armor_base: int, armor_category: String) -> int:
	var dex_bonus: int = 0
	if armor_category in ["light", "none"]:
		dex_bonus = scores["dexterity"]
	return 10 + armor_base + dex_bonus


## compute_reflex(scores: Dictionary) → int
##
## Formula: 10 + scores.dexterity + scores.intuition
## Example (dex 2, intuition 2): 10 + 2 + 2 = 14
func compute_reflex(scores: Dictionary) -> int:
	return 10 + scores["dexterity"] + scores["intuition"]


## compute_fortitude(scores: Dictionary) → int
##
## Formula: 10 + scores.constitution + scores.strength
## Example (constitution 4, strength 5): 10 + 4 + 5 = 19
func compute_fortitude(scores: Dictionary) -> int:
	return 10 + scores["constitution"] + scores["strength"]


## compute_will(scores: Dictionary) → int
##
## Formula: 10 + scores.willpower + scores.social
## Example (willpower 2, social 1): 10 + 2 + 1 = 13
func compute_will(scores: Dictionary) -> int:
	return 10 + scores["willpower"] + scores["social"]


## compute_skills_known(scores: Dictionary, class_data: ClassResource) → int
##
## Formula: class_data.skills_base + scores.intellect
## Example (Fighter skills_base 1, intellect 1): 1 + 1 = 2
func compute_skills_known(scores: Dictionary, class_data) -> int:
	return class_data.skills_base + scores["intellect"]


## roll_initiative(scores: Dictionary) → int
##
## Formula: _rng.d20() + scores.intuition + scores.dexterity
## Pinned test: seed 12345 → d20()=17; with dex=2 intuition=2 → 17+2+2 = 21
## The RNG state advances — call exactly once per combatant per encounter start.
func roll_initiative(scores: Dictionary) -> int:
	return _rng.d20() + scores["intuition"] + scores["dexterity"]
