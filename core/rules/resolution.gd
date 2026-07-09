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
## FEAT-010 (US-010 / FR-010, ADR-016): this file's Dodge branch below is now
## reachable from LIVE play, not just direct/isolated calls — see
## core/application/reaction_window.gd's ReactionWindow.open_and_resolve_attack(),
## which asks an injected ReactionChooserPort (e.g. a headless
## AutoReactionChooser, or a future player-facing pop-up) for a decision and
## then delegates the entire attack — including this pre-hit Mobility check
## and its ActionEconomy.spend_reaction() spend — to
## resolve_weapon_attack() below. No math or reaction-spend logic moved:
## this remains the SOLE place either happens.
##
## FEAT-205 (US-011 / FR-011, ADR-016): the SAME open_and_resolve_attack()
## seam wires this file's post-hit Parry branch below into LIVE play — the
## SECOND player-triggerable reaction on the steel thread's pop-up surface.
## A hit by a weapon attack vs AC, when the reactor's own weapon (forwarded
## by the caller as defense_context["parrying_weapon"], typically via
## trigger["attack_context"]) carries parry_bonus > 0, rolls d20 +
## parry_bonus and STRICTLY exceeds the attacker's roll_total to suppress
## damage_final to 0 and set on_hit_suppressed=true — spent via
## ActionEconomy.spend_reaction(), never spend_action(). No new math or
## reaction-spend logic was needed here: this file's Parry branch (FEAT-059)
## and reaction_window.gd's generic trigger/attack_context hand-off
## (FEAT-009) already composed correctly; see tests/unit/
## test_parry_reaction.gd for the end-to-end, headless
## (AutoReactionChooser-driven) proof.
##
## FEAT-206 (US-012 / FR-012, ADR-016): the SAME open_and_resolve_attack()
## seam wires this file's post-hit Block branch below into LIVE play — the
## THIRD player-triggerable reaction on the steel thread's pop-up surface. A
## hit by a weapon attack vs AC, when the reactor's own weapon (forwarded by
## the caller as defense_context["blocking_weapon"], typically via
## trigger["attack_context"]) carries block_value > 0, reduces damage_final
## by roll(block_die|damage_die, tier) + block_value, floored at 0, and sets
## on_hit_suppressed=true — spent via ActionEconomy.spend_reaction(), never
## spend_action(). No new math or reaction-spend logic was needed here: this
## file's Block branch (FEAT-059) and reaction_window.gd's generic
## trigger/attack_context hand-off (FEAT-009) already composed correctly;
## see tests/unit/test_block_reaction.gd for the end-to-end, headless
## (AutoReactionChooser-driven) proof.
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
##   "defense_value"          — int: the EFFECTIVE defense value the attack roll
##                                    was actually compared against (the passive
##                                    target[defense_type], substituted by a
##                                    successful Dodge/Steel check, and reduced
##                                    by the Off-Guard bonus when applicable) —
##                                    consumed by core/application/
##                                    resolve_action_use_case.gd (FEAT-008/
##                                    US-008, CR-001) to populate
##                                    RoundEvents.AttackEvent.defense_value
##                                    without recomputing it a second time.
##   "error"                  — String: present ONLY when defense_type is invalid
##
## RNG consumption order (for pinned-seed test reproducibility):
##   1. [Dodge/Steel only] _rng.d20() — Mobility or Determination check
##   2. _rng.d20()                    — attacker's attack roll
##   3. [Hit only] _rng.roll(...)     — damage roll(s)
##   4. [Block only] _rng.roll(...)   — block-reduction roll
##   5. [Parry only] _rng.d20()       — parry attack roll
##
## FEAT-001 (US-001 / FR-004, Iteration J Part A): this function is now a THIN
## COMPOSING WRAPPER over resolve_to_hit() (phase 1: pre-hit Dodge/Steel check
## + attack roll + damage roll) and apply_on_hit_defense() (phase 2: post-hit
## Block/Parry mitigation). It performs ZERO resolution math of its own —
## every formula above still lives in exactly one place (resolve_to_hit or
## apply_on_hit_defense), never duplicated here. This split exists so
## core/application callers (e.g. the two-phase reaction window
## re-architecture) can learn the hit/miss result BEFORE deciding whether to
## open a post-hit Block/Parry window, instead of committing to an
## active_defense choice up front. The default/"none" path (and every other
## active_defense value, since only one is ever passed per call) is
## byte-for-byte identical to the pre-split implementation — see
## tests/characterization/test_strike_characterization.gd, the pinned
## regression oracle for this contract.
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

	# A single resolve_weapon_attack() call only ever carries ONE
	# active_defense choice, so pre-hit (Dodge/Steel) and on-hit
	# (Block/Parry) are mutually exclusive by construction here — no budget
	# arbitration needed at this layer (that lives in the two-phase caller).
	var pre_hit_defense: String = active_defense if (active_defense == "dodge" or active_defense == "steel") else "none"

	var partial: Dictionary = resolve_to_hit(attacker, target, weapon, defense_type, pre_hit_defense, defense_context)

	var damage_final: int = partial["damage_raw"]
	var active_defense_applied: String = partial.get("active_defense_applied", "none")
	var on_hit_suppressed: bool = false

	if partial["hit"]:
		var on_hit_defense: String = active_defense if (active_defense == "block" or active_defense == "parry") else "none"
		var post: Dictionary = apply_on_hit_defense(partial, on_hit_defense, defense_context)
		damage_final = post["damage_final"]
		active_defense_applied = post["active_defense_applied"]
		on_hit_suppressed = post["on_hit_suppressed"]

	return {
		"hit":                    partial["hit"],
		"crit":                   partial["crit"],
		"roll_total":             partial["roll_total"],
		"damage_raw":             partial["damage_raw"],
		"active_defense_applied": active_defense_applied,
		"damage_final":           damage_final,
		"defender_stepped":       partial["defender_stepped"],
		"next_check_bonus":       partial.get("next_check_bonus", 0),
		"on_hit_suppressed":      on_hit_suppressed,
		"defense_value":          partial["defense_value"]
	}


## resolve_to_hit(attacker, target, weapon, defense_type, pre_hit_defense,
##                ctx) → Dictionary
##
## FEAT-001 (US-001 / FR-004, Iteration J Part A): PHASE 1 of the two-phase
## split — resolves everything that happens BEFORE the hit/miss result is
## known: the pre-hit Dodge/Steel check (if `pre_hit_defense` requests one
## and its trigger conditions hold), the attacker's attack roll, and — on a
## hit — the damage roll. This is the ENTIRE contents of the RNG-consumption
## positions 1–3 documented above; resolve_weapon_attack() and
## apply_on_hit_defense() never re-derive any of this math.
##
## Parameters:
##   attacker, target, weapon, defense_type — identical to
##     resolve_weapon_attack()'s parameters of the same name.
##   pre_hit_defense — String, one of "none" | "dodge" | "steel" — the
##     ON-ATTACKED reaction to attempt (Block/Parry are ON-HIT and are never
##     passed here; see apply_on_hit_defense()).
##   ctx — Dictionary, defaults to {} — same shape as resolve_weapon_attack()'s
##     defense_context ("action_economy", "open_space_available", …).
##
## Returns Dictionary — the pinned two-phase contract (test_criteria #1)
## ALWAYS carries these keys:
##   "hit"              — bool
##   "crit"             — bool
##   "roll_total"        — int: attacker's total attack roll
##   "damage_raw"        — int: damage before any on-hit mitigation
##   "defender_stepped"  — bool: true after a SUCCESSFUL Dodge (miss)
## Plus bookkeeping fields threaded through ONLY for
## resolve_weapon_attack()'s thin-wrapper recomposition (never re-derived by
## a caller — apply_on_hit_defense() reads "defense_type"/"weapon" back out
## of this same Dictionary rather than being passed them separately):
##   "active_defense_applied" — "dodge" | "steel" | "none" (pre-hit outcome only)
##   "next_check_bonus"       — int: +2 after a successful Steel resist, else 0
##   "defense_value"          — int: effective defense value the roll was compared to
##   "defense_type"           — String: echoed back for apply_on_hit_defense()
##   "weapon"                 — Dictionary: echoed back (block_die fallback needs it)
func resolve_to_hit(
	attacker: Dictionary,
	target: Dictionary,
	weapon: Dictionary,
	defense_type: String,
	pre_hit_defense: String = "none",
	ctx: Dictionary = {}
) -> Dictionary:

	# ── Pre-attack phase: Dodge and Steel roll BEFORE the attack roll ──────────
	# Both are reactions triggered when TARGETED, so their checks precede the
	# attacker's roll (ADR-002 RNG sequence, position 1).

	var mobility_check: int = -1       # >= 0 when Dodge was successfully activated
	var determination_check: int = -1  # >= 0 when Steel was successfully activated

	# DODGE — trigger: defense_type in ["ac","reflex"] AND NOT Immobilized AND open space
	if pre_hit_defense == "dodge":
		var is_dodge_trigger: bool = (defense_type == "ac" or defense_type == "reflex")
		var is_immobilized: bool = ("Immobilized" in target.get("conditions", []))
		var open_space: bool = ctx.get("open_space_available", true)

		if is_dodge_trigger and not is_immobilized and open_space:
			# Attempt to spend one reaction from the action economy (if provided)
			var reaction_ok: bool = _try_spend_reaction(ctx)
			if reaction_ok:
				# Roll Mobility check: d20 + Mobility skill (FEAT-007 / US-007 /
				# FR-008 / ADR-015 — real skills['mobility'], not the former
				# target.dexterity attribute proxy).
				var mob_roll: int = _rng.d20()
				mobility_check = mob_roll + target.get("skills", {}).get("mobility", 0)

	# STEEL — trigger: defense_type in ["fortitude","will"] AND conscious
	if pre_hit_defense == "steel":
		var is_steel_trigger: bool = (defense_type == "fortitude" or defense_type == "will")
		var is_conscious: bool = target.get("conscious", true)

		if is_steel_trigger and is_conscious:
			var reaction_ok: bool = _try_spend_reaction(ctx)
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

	# ── Pre-hit outcome bookkeeping (Dodge/Steel only; Block/Parry are
	#    resolved later, in apply_on_hit_defense()) ────────────────────────────
	var active_defense_applied: String = "none"
	var defender_stepped: bool = false
	var next_check_bonus: int = 0

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

	return {
		"hit":                    hit,
		"crit":                   crit,
		"roll_total":             roll_total,
		"damage_raw":             damage_raw,
		"defender_stepped":       defender_stepped,
		"active_defense_applied": active_defense_applied,
		"next_check_bonus":       next_check_bonus,
		"defense_value":          defense_value,
		"defense_type":           defense_type,
		"weapon":                 weapon
	}


## apply_on_hit_defense(partial, on_hit_defense, ctx) → Dictionary
##
## FEAT-001 (US-001 / FR-004, Iteration J Part A): PHASE 2 of the two-phase
## split — resolves the POST-HIT Block/Parry mitigation, given the partial
## result already produced by resolve_to_hit(). This is the ENTIRE contents
## of RNG-consumption positions 4–5 documented above (block-reduction roll /
## parry roll); resolve_weapon_attack() and resolve_to_hit() never re-derive
## any of this math.
##
## PRECONDITION: must NEVER be called when partial.hit == false (US-004 task
## 5 — Block/Parry only exist as ON-HIT reactions; a miss never opens that
## window). Contract violation: push_error()'d and a safe no-op Dictionary is
## returned rather than corrupting damage math — this project's established
## pattern for programmer-error guards (mirrors core/rules/action_economy.gd's
## null-combatant guards), since GUT's push_error capture is unavailable on
## this project's Godot 4.3 engine (see tests/unit/test_action_economy.gd's
## documented note) and callers must not crash/hang in a release build.
##
## Parameters:
##   partial — the Dictionary returned by resolve_to_hit() (or an equivalent
##     Dictionary carrying at least "hit", "damage_raw", "roll_total",
##     "defense_type", "weapon", "active_defense_applied").
##   on_hit_defense — String, one of "none" | "block" | "parry" — the ON-HIT
##     reaction to attempt (Dodge/Steel are ON-ATTACKED and are never passed
##     here; see resolve_to_hit()).
##   ctx — Dictionary, defaults to {} — same shape as resolve_weapon_attack()'s
##     defense_context ("action_economy", "blocking_weapon",
##     "blocking_weapon_tier", "parrying_weapon", …).
##
## Returns Dictionary — ALWAYS carries these keys:
##   "damage_final"           — int, ALWAYS >= 0
##   "active_defense_applied" — String: "block" | "parry" | whatever pre-hit
##                               phase 1 already recorded (e.g. "dodge"/
##                               "steel"/"none") when on_hit_defense is "none"
##   "on_hit_suppressed"      — bool
func apply_on_hit_defense(partial: Dictionary, on_hit_defense: String = "none", ctx: Dictionary = {}) -> Dictionary:
	if not partial.get("hit", false):
		push_error("Resolution.apply_on_hit_defense() called with partial.hit == false — Block/Parry are ON-HIT-only reactions (US-004 task 5); no-op returned")
		return {
			"damage_final": 0,
			"active_defense_applied": partial.get("active_defense_applied", "none"),
			"on_hit_suppressed": false
		}

	var damage_raw: int = partial.get("damage_raw", 0)
	var defense_type: String = partial.get("defense_type", "")
	var roll_total: int = partial.get("roll_total", 0)
	var weapon: Dictionary = partial.get("weapon", {})

	var damage_final: int = damage_raw
	var active_defense_applied: String = partial.get("active_defense_applied", "none")
	var on_hit_suppressed: bool = false

	# BLOCK — post-hit reaction; trigger: hit (guaranteed above) AND defense_type == "ac"
	if on_hit_defense == "block" and defense_type == "ac":
		var reaction_ok: bool = _try_spend_reaction(ctx)
		if reaction_ok:
			var bw: Dictionary = ctx.get("blocking_weapon", {})
			var tier: int = ctx.get("blocking_weapon_tier", 1)
			# Shields use a dedicated block_die; other weapons use their damage_die
			var block_die_size: int = bw.get("block_die", bw.get("damage_die", weapon.get("damage_die", 6)))
			var block_value_mod: int = bw.get("block_value", 0)
			# 1[W] at tier 1, 2[W] at tier 2, 3[W] at tier 3 (ADR-002 RNG position 4)
			var block_reduction: int = _rng.roll(block_die_size, tier) + block_value_mod
			damage_final = max(0, damage_raw - block_reduction)
			on_hit_suppressed = true
			active_defense_applied = "block"

	# PARRY — post-hit reaction; trigger: hit (guaranteed above) AND defense_type == "ac"
	elif on_hit_defense == "parry" and defense_type == "ac":
		var reaction_ok: bool = _try_spend_reaction(ctx)
		if reaction_ok:
			var pw: Dictionary = ctx.get("parrying_weapon", {})
			var parry_bonus_val: int = pw.get("parry_bonus", 0)
			# Parry attack roll: d20 + parry_bonus (ADR-002 RNG position 5)
			var parry_roll: int = _rng.d20() + parry_bonus_val
			# Parry succeeds ONLY if it STRICTLY EXCEEDS the attacker's roll_total
			if parry_roll > roll_total:
				damage_final = 0
				on_hit_suppressed = true
			active_defense_applied = "parry"

	# Invariant: damage_final is NEVER negative, regardless of path taken above.
	damage_final = max(0, damage_final)

	return {
		"damage_final": damage_final,
		"active_defense_applied": active_defense_applied,
		"on_hit_suppressed": on_hit_suppressed
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


## is_dodge_eligible(defense_type, target, defense_context) -> bool —
## FEAT-009 (US-009 / FR-005, ADR-014): the SAME "is Dodge a legal reaction
## right now" predicate resolve_weapon_attack() evaluates inline above
## (defense_type in ["ac","reflex"] AND NOT Immobilized AND open space
## available), extracted as a pure, side-effect-free, static-callable
## function so core/application/reaction_window.gd's legal_reactions
## computation reuses this SAME eligibility rule rather than re-deriving
## it — avoiding a second, drifting copy of the predicate (CR-001-style
## hygiene). Never rolls RNG, never mutates defense_context/target.
static func is_dodge_eligible(defense_type: String, target: Dictionary, defense_context: Dictionary = {}) -> bool:
	var is_dodge_trigger: bool = (defense_type == "ac" or defense_type == "reflex")
	var is_immobilized: bool = ("Immobilized" in target.get("conditions", []))
	var open_space: bool = defense_context.get("open_space_available", true)
	return is_dodge_trigger and not is_immobilized and open_space


## is_steel_eligible(defense_type, target) -> bool — FEAT-009: the SAME
## "is Steel a legal reaction right now" predicate resolve_weapon_attack()
## evaluates inline above (defense_type in ["fortitude","will"] AND the
## target is conscious), extracted as a pure function for
## reaction_window.gd's reuse — see is_dodge_eligible()'s doc above.
static func is_steel_eligible(defense_type: String, target: Dictionary) -> bool:
	var is_steel_trigger: bool = (defense_type == "fortitude" or defense_type == "will")
	var is_conscious: bool = target.get("conscious", true)
	return is_steel_trigger and is_conscious


## is_parry_eligible(weapon) -> bool — FEAT-009: true iff `weapon` (the
## reactor's own parrying weapon Dictionary) carries a positive
## "parry_bonus" — mirrors the Parry post-hit branch's implicit
## precondition above (a parrying_weapon with parry_bonus 0 can still
## technically roll, but a reaction window should never OFFER Parry as a
## legal choice when the reactor's weapon cannot parry at all).
static func is_parry_eligible(weapon: Dictionary) -> bool:
	return weapon.get("parry_bonus", 0) > 0


## is_block_eligible(weapon) -> bool — FEAT-009: true iff `weapon` (the
## reactor's own blocking weapon/shield Dictionary) carries a positive
## "block_value" — mirrors is_parry_eligible()'s role for Block.
static func is_block_eligible(weapon: Dictionary) -> bool:
	return weapon.get("block_value", 0) > 0


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
