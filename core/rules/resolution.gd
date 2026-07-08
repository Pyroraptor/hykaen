## core/rules/resolution.gd — Strike Resolution Pipeline (Passive + Active Defense)
##
## Domain layer (ADR-001): no Node/Control inheritance — pure game logic only.
## Constructor accepts an RNG instance (ADR-002 injection).
##
## FEAT-059: Implements four active defense reactions per Combat.pdf:
##   Dodge  — Mobility check replaces AC/Reflex; defender Steps on success.
##   Block  — Hit damage reduced by 1[W]+block_value (scales by tier).
##   Parry  — Parry roll vs attacker's roll_total; success → 0 damage.
##   Steel  — Determination check replaces Fortitude/Will; resist → +2 next check.
##
## FEAT-007 (US-007 / FR-008, ADR-015): Dodge's Mobility check and Steel's
## Determination check are computed from the target's REAL skills —
## skills['mobility'] and skills['determination'] respectively — rather
## than the earlier target.dexterity/target.willpower attribute proxies.
## Both default to 0 when the target Dictionary carries no "skills" key or
## the specific skill key is absent (missing-key-defaults-to-0, matching
## the accessor pattern used everywhere else skills are read).
##
## All active defenses are REACTIONS (Stamina 0) that spend one action from
## the actor's 7-action round budget via ActionEconomy.spend_reaction() when
## an action_economy is provided in defense_context.
##
## FEAT-015 (US-015 / FR-016): Off-Guard positional condition. When the
## target Dictionary's "conditions" list carries core/rules/flanking.gd's
## Flanking.OFF_GUARD_CONDITION ("Off-Guard" — set by a caller after
## detecting an attacker+ally on directly-opposite adjacent hexes around the
## target via Flanking.is_off_guard(), typically the composition root/
## infrastructure layer, not this file), the target's effective defense
## value for the attack being resolved is reduced by
## Flanking.OFF_GUARD_BONUS (a flat 2), equivalent to a +2 attack bonus for
## the purposes of both the hit check and the crit-by-10-or-more check. This
## is a BLANKET bonus: it applies to EVERY attack resolved against the
## target while Off-Guard, regardless of which combatant is attacking —
## resolve_weapon_attack()/resolve_spell_attack() never inspect attacker
## identity against a flanking pair (v0 is explicitly NOT flankers-only; see
## core/rules/flanking.gd's file-level doc).
##
## Satisfies: US-008, US-015, ADR-001, ADR-002, FEAT-059, FEAT-015, DEF-NEW-003
##
## Usage example:
##   var rng = RNG.new(12345)
##   var resolution = Resolution.new(rng)
##   # Passive defense only (v0 path):
##   var result = resolution.resolve_weapon_attack(attacker, target, weapon, "ac")
##   # Active defense (Dodge):
##   var ctx = {"action_economy": ae, "open_space_available": true}
##   var result = resolution.resolve_weapon_attack(attacker, target, weapon, "ac", "dodge", ctx)
##   # result → {hit, crit, roll_total, damage_raw, active_defense_applied,
##   #            damage_final, defender_stepped, next_check_bonus, on_hit_suppressed}

class_name Resolution

const FlankingClass = preload("res://core/rules/flanking.gd")

## Valid passive defense types (ADR-011).
const VALID_DEFENSE_TYPES: Array = ["ac", "reflex", "fortitude", "will"]

## Valid active defense choices (FEAT-059).
const VALID_ACTIVE_DEFENSES: Array = ["none", "dodge", "block", "parry", "steel"]

var _rng  # RNG — injected at construction; never instantiated here (ADR-002)


## Constructor.
## rng — an RNG instance (core/rules/rng.gd) injected from outside.
func _init(rng) -> void:
	_rng = rng


## resolve_weapon_attack(attacker, target, weapon, defense_type,
##                       active_defense, defense_context) → Dictionary
##
## Resolves a weapon attack roll against a passive or active defense target.
##
## Parameters:
##   attacker         — Dictionary with attribute scores
##                        e.g. {"strength": 3, "dexterity": 2, ...}
##   target           — Dictionary with passive defense values AND optional
##                        attributes for active checks:
##                        {"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
##                         "skills": {"mobility": 1,       ← Mobility check (Dodge)
##                                    "determination": 1}, ← Determination check (Steel)
##                         "conscious":  true, ← Steel trigger gate
##                         "conditions": []}   ← "Immobilized" blocks Dodge
##   weapon           — Dictionary with weapon statistics:
##                        "damage_modifier_attribute": String
##                        "proficiency_bonus":         int
##                        "damage_die":                int
##   defense_type     — String, one of: "ac", "reflex", "fortitude", "will"
##   active_defense   — String (optional, default "none"):
##                        "none" | "dodge" | "block" | "parry" | "steel"
##   defense_context  — Dictionary (optional, default {}):
##                        "action_economy"       — ActionEconomy instance; if provided,
##                                                  spend_reaction() is called when the
##                                                  defense triggers.
##                        --- Dodge ---
##                        "open_space_available" — bool (default true); false → auto-fail
##                        --- Block ---
##                        "blocking_weapon"      — {"damage_die":int,"block_value":int,
##                                                   "block_die":int (optional, for shields)}
##                        "blocking_weapon_tier" — int (default 1); 1→1[W], 2→2[W], 3→3[W]
##                        --- Parry ---
##                        "parrying_weapon"      — {"parry_bonus":int}
##
## Returns Dictionary (all keys always present):
##   "hit"                    — bool
##   "crit"                   — bool
##   "roll_total"             — int: attacker's total attack roll
##   "damage_raw"             — int: damage before active defense
##   "active_defense_applied" — String: which defense was applied ("none" if none triggered)
##   "damage_final"           — int: damage after active defense
##   "defender_stepped"       — bool: true after a SUCCESSFUL Dodge (miss)
##   "next_check_bonus"       — int: +2 after a SUCCESSFUL Steel resist; else 0
##   "on_hit_suppressed"      — bool: true after Block or successful Parry
##   "error"                  — String: present ONLY when defense_type is invalid
##
## RNG consumption order (for pinned-seed test reproducibility):
##   1. [Dodge/Steel only] _rng.d20() — Mobility or Determination check
##   2. _rng.d20()                    — attacker's attack roll
##   3. [Hit only] _rng.roll(...)     — damage roll(s)
##   4. [Block only] _rng.roll(...)   — block-reduction roll
##   5. [Parry only] _rng.d20()       — parry attack roll
func resolve_weapon_attack(
	attacker: Dictionary,
	target: Dictionary,
	weapon: Dictionary,
	defense_type: String,
	active_defense: String = "none",
	defense_context: Dictionary = {}
) -> Dictionary:

	# Guard: validate defense_type before consuming any RNG state
	if not (defense_type in VALID_DEFENSE_TYPES):
		return {
			"hit": false,
			"crit": false,
			"roll_total": 0,
			"damage_raw": 0,
			"active_defense_applied": "none",
			"damage_final": 0,
			"defender_stepped": false,
			"next_check_bonus": 0,
			"on_hit_suppressed": false,
			"error": "Invalid defense type: '%s' — must be one of %s" % [defense_type, str(VALID_DEFENSE_TYPES)]
		}

	# Sanitize active_defense — unknown values fall back to "none"
	if not (active_defense in VALID_ACTIVE_DEFENSES):
		active_defense = "none"

	# ── Pre-attack phase: Dodge and Steel roll BEFORE the attack roll ──────────
	# Both are reactions triggered when TARGETED, so their checks precede the
	# attacker's roll (ADR-002 RNG sequence, position 1).

	var mobility_check: int = -1       # >= 0 when Dodge was successfully activated
	var determination_check: int = -1  # >= 0 when Steel was successfully activated

	# DODGE — trigger: defense_type in ["ac","reflex"] AND NOT Immobilized AND open space
	if active_defense == "dodge":
		var is_dodge_trigger: bool = (defense_type == "ac" or defense_type == "reflex")
		var is_immobilized: bool = ("Immobilized" in target.get("conditions", []))
		var open_space: bool = defense_context.get("open_space_available", true)

		if is_dodge_trigger and not is_immobilized and open_space:
			# Attempt to spend one reaction from the action economy (if provided)
			var reaction_ok: bool = _try_spend_reaction(defense_context)
			if reaction_ok:
				# Roll Mobility check: d20 + Mobility skill (FEAT-007 / US-007 /
				# FR-008 / ADR-015 — real skills['mobility'], not the former
				# target.dexterity attribute proxy).
				var mob_roll: int = _rng.d20()
				mobility_check = mob_roll + target.get("skills", {}).get("mobility", 0)

	# STEEL — trigger: defense_type in ["fortitude","will"] AND conscious
	if active_defense == "steel":
		var is_steel_trigger: bool = (defense_type == "fortitude" or defense_type == "will")
		var is_conscious: bool = target.get("conscious", true)

		if is_steel_trigger and is_conscious:
			var reaction_ok: bool = _try_spend_reaction(defense_context)
			if reaction_ok:
				# Roll Determination check: d20 + Determination skill (FEAT-007 /
				# US-007 / FR-008 / ADR-015 — real skills['determination'], not
				# the former target.willpower attribute proxy).
				var det_roll: int = _rng.d20()
				determination_check = det_roll + target.get("skills", {}).get("determination", 0)

	# ── Attack roll (ADR-002 RNG position 2) ─────────────────────────────────
	var raw: int = _rng.d20()
	var attribute_mod: int = attacker.get(weapon["damage_modifier_attribute"], 0)
	var roll_total: int = raw + attribute_mod + weapon["proficiency_bonus"]

	# ── Effective defense value ───────────────────────────────────────────────
	# Dodge and Steel substitute their check result for the passive defense.
	var defense_value: int
	if mobility_check >= 0:
		defense_value = mobility_check
	elif determination_check >= 0:
		defense_value = determination_check
	else:
		defense_value = target[defense_type]

	# Off-Guard (FEAT-015 / US-015 / FR-016): blanket +2 to ALL attacks
	# against this target, applied as an equivalent flat reduction of its
	# effective defense value — see file-level doc above.
	defense_value -= _off_guard_defense_reduction(target)

	var hit: bool = roll_total >= defense_value
	var crit: bool = hit and (roll_total - defense_value) >= 10

	# ── Damage calculation (ADR-002 RNG position 3) ───────────────────────────
	var damage_raw: int = 0
	if hit:
		if crit:
			# Critical hit: roll 2 dice + double the attribute modifier
			damage_raw = _rng.roll(weapon["damage_die"], 2) + attribute_mod * 2
		else:
			# Normal hit: roll 1 die + attribute modifier
			damage_raw = _rng.roll(weapon["damage_die"], 1) + attribute_mod

	# ── Post-resolution: finalize active defense outcomes ─────────────────────
	var damage_final: int = damage_raw
	var active_defense_applied: String = "none"
	var defender_stepped: bool = false
	var next_check_bonus: int = 0
	var on_hit_suppressed: bool = false

	# Dodge outcome: if mobility_check was rolled, the defense was applied
	if mobility_check >= 0:
		active_defense_applied = "dodge"
		if not hit:
			# Dodge SUCCEEDED — attacker failed to beat the Mobility check
			# Defender steps 5 ft as per Combat.pdf Dodge action text
			defender_stepped = true
		# If hit is still true, the attacker beat the mobility check; Dodge applied
		# but did not protect. Reaction was still spent.

	# Steel outcome: if determination_check was rolled, the defense was applied
	elif determination_check >= 0:
		active_defense_applied = "steel"
		if not hit:
			# Attack was RESISTED — grant +2 to the next check made this round
			next_check_bonus = 2

	# BLOCK — post-hit reaction; trigger: hit AND defense_type == "ac"
	elif active_defense == "block" and hit and defense_type == "ac":
		var reaction_ok: bool = _try_spend_reaction(defense_context)
		if reaction_ok:
			var bw: Dictionary = defense_context.get("blocking_weapon", {})
			var tier: int = defense_context.get("blocking_weapon_tier", 1)
			# Shields use a dedicated block_die; other weapons use their damage_die
			var block_die_size: int = bw.get("block_die", bw.get("damage_die", weapon.get("damage_die", 6)))
			var block_value_mod: int = bw.get("block_value", 0)
			# 1[W] at tier 1, 2[W] at tier 2, 3[W] at tier 3 (ADR-002 RNG position 4)
			var block_reduction: int = _rng.roll(block_die_size, tier) + block_value_mod
			damage_final = max(0, damage_raw - block_reduction)
			on_hit_suppressed = true
			active_defense_applied = "block"

	# PARRY — post-hit reaction; trigger: hit AND defense_type == "ac"
	elif active_defense == "parry" and hit and defense_type == "ac":
		var reaction_ok: bool = _try_spend_reaction(defense_context)
		if reaction_ok:
			var pw: Dictionary = defense_context.get("parrying_weapon", {})
			var parry_bonus_val: int = pw.get("parry_bonus", 0)
			# Parry attack roll: d20 + parry_bonus (ADR-002 RNG position 5)
			var parry_roll: int = _rng.d20() + parry_bonus_val
			# Parry succeeds ONLY if it STRICTLY EXCEEDS the attacker's roll_total
			if parry_roll > roll_total:
				damage_final = 0
				on_hit_suppressed = true
			active_defense_applied = "parry"

	return {
		"hit":                    hit,
		"crit":                   crit,
		"roll_total":             roll_total,
		"damage_raw":             damage_raw,
		"active_defense_applied": active_defense_applied,
		"damage_final":           damage_final,
		"defender_stepped":       defender_stepped,
		"next_check_bonus":       next_check_bonus,
		"on_hit_suppressed":      on_hit_suppressed
	}


## _try_spend_reaction(defense_context) → bool
##
## Internal helper: attempts to spend one reaction from the ActionEconomy in
## defense_context (if present). Returns true if the reaction was spent or if
## no action economy was provided (i.e., spending is not tracked).
## Returns false if the action economy is Spent (budget exhausted).
##
## This implements the "reactions cost one action from the 7-action round budget"
## rule per Combat.pdf and FEAT-059 criterion 7.
func _try_spend_reaction(defense_context: Dictionary) -> bool:
	var ae = defense_context.get("action_economy", null)
	if ae == null:
		return true  # No AE provided → spending not tracked → always allowed
	var result = ae.spend_reaction()
	return result["success"]


## _off_guard_defense_reduction(target) -> int — FEAT-015 (US-015 / FR-016):
## returns Flanking.OFF_GUARD_BONUS (2) when `target`'s "conditions" list
## carries Flanking.OFF_GUARD_CONDITION ("Off-Guard"), else 0. Read-only —
## this file never sets/clears the condition itself (that is the flanking
## detector's caller's responsibility, e.g. the composition root recomputing
## positions after a Step/Stride); resolution.gd only ever consumes it.
func _off_guard_defense_reduction(target: Dictionary) -> int:
	if FlankingClass.OFF_GUARD_CONDITION in target.get("conditions", []):
		return FlankingClass.OFF_GUARD_BONUS
	return 0


## resolve_spell_attack(attacker, target, spell, defense_type) → Dictionary
##
## Resolves a spell attack roll against a passive defense target.
## Satisfies: FEAT-047, US-008, DEF-006.
##
## Parameters:
##   attacker     — Dictionary with:
##                    "spellcasting_attribute": String — key name of the casting attribute
##                        (e.g. "intellect" for Wizard, "social" for Divine Channeler)
##                    [spellcasting_attribute]: int — the numeric score for that attribute
##                    "spell_attack_bonus": int — added to the attack roll
##   target       — Dictionary with passive defense values
##                    e.g. {"ac": 13, "will": 11, ...}
##   spell        — Dictionary with spell statistics:
##                    "damage_die": int — die size for damage (e.g. 6 for d6)
##   defense_type — String, one of: "ac", "reflex", "fortitude", "will"
##
## Returns Dictionary:
##   "hit"                    — bool: true if roll_total >= target[defense_type]
##   "crit"                   — bool: true if hit AND (roll_total - defense) >= 10
##   "roll_total"             — int: total attack roll (d20 + attribute + bonus)
##   "damage_raw"             — int: damage before any active defense modifiers
##   "active_defense_applied" — String: always "none" (spell attacks v0 — no active defenses)
##   "damage_final"           — int: equals damage_raw in v0 (no active defense)
##   "error"                  — String: present only when defense_type is invalid
##
## Roll formula: d20() + attacker[attacker.spellcasting_attribute] + attacker.spell_attack_bonus
## Crit formula: damage = roll(damage_die, 2) + modifier * 2
## Hit  formula: damage = roll(damage_die, 1) + modifier
## Miss formula: damage = 0
func resolve_spell_attack(attacker: Dictionary, target: Dictionary, spell: Dictionary, defense_type: String) -> Dictionary:
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

	# Roll: d20 + spellcasting attribute score + spell attack bonus
	var raw: int = _rng.d20()
	var modifier: int = attacker.get(attacker["spellcasting_attribute"], 0)
	var roll_total: int = raw + modifier + attacker["spell_attack_bonus"]

	# Compare against the requested passive defense value
	var defense_value: int = target[defense_type]

	# Off-Guard (FEAT-015 / US-015 / FR-016): blanket +2 to ALL attacks
	# against this target — spell attacks included, see file-level doc above.
	defense_value -= _off_guard_defense_reduction(target)

	var hit: bool = roll_total >= defense_value

	# Crit: hit AND exceeded defense threshold by 10 or more
	var crit: bool = hit and (roll_total - defense_value) >= 10

	# Damage calculation
	var damage_raw: int = 0
	if hit:
		if crit:
			# Critical hit: roll 2 dice + double the spellcasting attribute modifier
			damage_raw = _rng.roll(spell["damage_die"], 2) + modifier * 2
		else:
			# Normal hit: roll 1 die + spellcasting attribute modifier
			damage_raw = _rng.roll(spell["damage_die"], 1) + modifier

	# Active defenses not yet implemented for spell attacks (v0 — passive-only)
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
