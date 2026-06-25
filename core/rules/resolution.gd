## core/rules/resolution.gd — Passive-Defense Strike Resolution Pipeline
##
## Domain layer (ADR-001): no Node/Control inheritance — pure game logic only.
## Constructor accepts an RNG instance (ADR-002 injection).
##
## ADR-011 (passive-defense always-on): active defenses are stubbed for Iteration 2.
## Active defense resolution returns 'none' always in this iteration.
##
## Satisfies: US-008, ADR-011
##
## Usage example:
##   var rng = RNG.new(12345)
##   var resolution = Resolution.new(rng)
##   var result = resolution.resolve_weapon_attack(attacker, target, weapon, "ac")
##   # result → {hit: bool, crit: bool, damage_raw: int,
##   #            active_defense_applied: "none", damage_final: int}

class_name Resolution

## Valid passive defense types (ADR-011).
const VALID_DEFENSE_TYPES: Array = ["ac", "reflex", "fortitude", "will"]

var _rng  # RNG — injected at construction; never instantiated here (ADR-002)


## Constructor.
## rng — an RNG instance (core/rules/rng.gd) injected from outside.
func _init(rng) -> void:
	_rng = rng


## resolve_weapon_attack(attacker, target, weapon, defense_type) → Dictionary
##
## Resolves a weapon attack roll against a passive defense target.
##
## Parameters:
##   attacker     — Dictionary with attribute scores
##                    e.g. {"strength": 3, "dexterity": 2, ...}
##   target       — Dictionary with passive defense values
##                    e.g. {"ac": 13, "reflex": 12, "fortitude": 14, "will": 11}
##   weapon       — Dictionary with weapon statistics:
##                    "damage_modifier_attribute": String — which attacker attribute
##                        adds to the attack roll and damage (e.g. "strength")
##                    "proficiency_bonus": int — added to the attack roll
##                    "damage_die": int — die size for damage (e.g. 6 for d6)
##   defense_type — String, one of: "ac", "reflex", "fortitude", "will"
##
## Returns Dictionary:
##   "hit"                    — bool: true if roll_total >= target[defense_type]
##   "crit"                   — bool: true if hit AND (roll_total - defense) >= 10
##   "damage_raw"             — int: damage before any active defense modifiers
##   "active_defense_applied" — String: always "none" in v0 (stubbed for Iteration 2)
##   "damage_final"           — int: equals damage_raw in v0 (no active defense)
##   "error"                  — String: present only when defense_type is invalid
##
## Roll formula: d20() + attacker[weapon.damage_modifier_attribute] + weapon.proficiency_bonus
## Crit formula: damage = roll(damage_die, 2) + attribute_mod * 2
## Hit  formula: damage = roll(damage_die, 1) + attribute_mod
## Miss formula: damage = 0
func resolve_weapon_attack(attacker: Dictionary, target: Dictionary, weapon: Dictionary, defense_type: String) -> Dictionary:
	# Guard: validate defense_type before consuming any RNG state
	if not (defense_type in VALID_DEFENSE_TYPES):
		return {
			"hit": false,
			"crit": false,
			"roll_total": 0,
			"damage_raw": 0,
			"active_defense_applied": "none",
			"damage_final": 0,
			"error": "Invalid defense type: '%s' — must be one of %s" % [defense_type, str(VALID_DEFENSE_TYPES)]
		}

	# Roll: d20 + attribute modifier + proficiency bonus
	var raw: int = _rng.d20()
	var attribute_mod: int = attacker.get(weapon["damage_modifier_attribute"], 0)
	var roll_total: int = raw + attribute_mod + weapon["proficiency_bonus"]

	# Compare against the requested passive defense value
	var defense_value: int = target[defense_type]
	var hit: bool = roll_total >= defense_value

	# Crit: hit AND exceeded defense threshold by 10 or more
	var crit: bool = hit and (roll_total - defense_value) >= 10

	# Damage calculation
	var damage_raw: int = 0
	if hit:
		if crit:
			# Critical hit: roll 2 dice + double the attribute modifier
			damage_raw = _rng.roll(weapon["damage_die"], 2) + attribute_mod * 2
		else:
			# Normal hit: roll 1 die + attribute modifier
			damage_raw = _rng.roll(weapon["damage_die"], 1) + attribute_mod

	# Active defenses stubbed for Iteration 2 — always passthrough in v0
	var active_defense_applied: String = "none"
	var damage_final: int = damage_raw

	return {
		"hit": hit,
		"crit": crit,
		"roll_total": roll_total,
		"damage_raw": damage_raw,
		"active_defense_applied": active_defense_applied,
		"damage_final": damage_final
	}
