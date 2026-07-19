## core/domain/combatant.gd — Combatant domain entity (FEAT-001 / US-001)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. Extends
## RefCounted only, matching the existing value-object convention.
##
## Represents one combatant's identity, battlefield position, AND combat state
## within an Encounter. FEAT-001 originally established only the identity +
## hex-position layer while the resolution pipeline passed a parallel Dictionary
## carrying every stat. The Combatant-entity migration
## (docs/refactors/combatant-entity-migration.org) folds that stat bag onto this
## entity so combat data + behaviour live in one typed place with methods.
##
## MIGRATION PHASE A (this change): ENRICH the entity with combat fields +
## behaviour + to_dict()/from_dict() interop, WITHOUT re-wiring the pipeline —
## resolution still passes Dictionaries; to_dict()/from_dict() bridge the
## boundary one seam at a time in later phases (B: swap the source; C: flip
## signatures inward; D: delete this interop).
##
## Shape note: the historical combatant dicts were ASYMMETRIC and lifecycle-
## accreting — CombatantFactory's party build omitted fortitude/reflex/will,
## and conditions[]/_is_enemy/_initiative_roll were added later by
## encounter.gd/flanking.gd. Every consumer reads via .get(key, default).
## to_dict() therefore emits a NORMALISED canonical shape (all four defenses +
## conditions[]); Phase B verifies that normalisation is behaviour-preserving
## precisely because the pipeline reads with .get() defaults.
##
## Fields:
##   Identity/position — combatant_id, name, team, hex_coord
##   Vitals            — hp_current, hp_max, stamina
##   Defenses          — ac, fortitude, reflex, will  (passive target numbers)
##   Attributes        — strength, dexterity, intuition
##   Loadout/skills    — weapon (Dictionary), skills (Dictionary)
##   Runtime state     — conditions (Array), initiative_roll, is_enemy,
##                       casting_state (reserved for Cast-a-Spell)
##
## Usage:
##   var c := Combatant.new("player_0", "Titus", "Player", HexCoord.new(0, 0))
##   c.hex_coord.q            # 0
##   var attacked := Combatant.from_dict(enemy_spec)  # bridge from a dict
##   attacked.defense("reflex")

class_name Combatant
extends RefCounted

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## CastingStateClass — FEAT-005 (US-005; FR-004): preloaded ONLY to
## construct the CastingState value object begin_cast() (below) projects
## onto `casting_state`'s plain-Dictionary field — see core/domain/
## casting_state.gd's own file-level "compatibility note" for why the field
## itself stays a Dictionary rather than a typed CastingState instance
## (every pre-existing caller/test, e.g. tests/unit/core/domain/
## test_combatant_combat_state.gd's test_casting_hooks_default_and_cancel(),
## already assigns/reads it as a raw Dictionary).
const CastingStateClass = preload("res://core/domain/casting_state.gd")

# ── Identity & position (FEAT-001) ──────────────────────────────────────────

## Unique identifier for this combatant within its Encounter.
var combatant_id: String

## Display name (e.g. "Titus", "Skeleton").
var name: String

## "Player" or "Enemy". Kept consistent with `is_enemy` (below).
var team: String

## This combatant's current position — a HexCoord instance
## (core/geometry/hex_coord.gd). Defaults to HexCoord(0, 0) when not supplied.
##
## NOTE: typed against the preloaded HexCoordClass constant (not the bare global
## `HexCoord` class_name) — a bare global class_name as a static type annotation
## needs Godot's global script-class cache to already know a brand-new script,
## which is not guaranteed headless/CI. Preload-based typing has no such dep.
var hex_coord: HexCoordClass

# ── Vitals ──────────────────────────────────────────────────────────────────
var hp_current: int = 0
var hp_max: int = 0
var stamina: int = 0

## Explicit consciousness flag — the Steel-trigger / reaction gate
## (resolution.gd reads it as target.get("conscious", true) pre-migration).
## Defaults true and is INDEPENDENT of hp: nothing in prod sets it false, but
## some tests do to exercise the "an unconscious combatant can't react" gate, so
## it must be a real stored flag (NOT derived). Distinct from is_conscious()
## below, which is the hp>0 alive-check.
var conscious: bool = true

# ── Passive defenses (spec §Defenses) — d20 attack rolls target these ───────
var ac: int = 0
var fortitude: int = 0
var reflex: int = 0
var will: int = 0

# ── Attributes ──────────────────────────────────────────────────────────────
var strength: int = 0
var dexterity: int = 0
var intuition: int = 0

# ── Loadout / skills ────────────────────────────────────────────────────────
var weapon: Dictionary = {}
var skills: Dictionary = {}

## Casting-related authored data (FEAT-002, Iteration M P0-0). Zero-value/
## empty for a non-caster combatant (e.g. Titus).
##
## spellcasting_attribute_score — this combatant's score in whichever
## attribute governs its spellcasting (e.g. willpower for a Divine Warrior),
## resolved ONCE at construction time by CombatantFactory from
## CharacterResource.class_ref.spellcasting_attribute + attributes. Not
## re-derived here (Combatant carries data, not the class_ref/attribute
## lookup rule).
var spellcasting_attribute_score: int = 0

## known_spell_ids — Array of spell_id Strings this combatant knows how to
## cast (mirrors CharacterResource.known_spell_ids, threaded through
## CombatantFactory). Empty for a non-caster combatant.
var known_spell_ids: Array = []

# ── Runtime state ───────────────────────────────────────────────────────────

## Active condition tags (e.g. "Off-Guard", "Immobilized"). Drives Off-Guard
## attack bonuses (flanking.gd) and Dodge-gating (resolution.gd).
var conditions: Array = []

## Rolled initiative (dict key "_initiative_roll", set by encounter.gd at
## start-of-encounter).
var initiative_roll: int = 0

## Team partition flag (dict key "_is_enemy"). Should agree with `team`.
var is_enemy: bool = false

## Reserved for the Cast-a-Spell multi-turn casting state machine. Empty when
## not casting; the spell feature fills {spell_id, remaining_actions,
## committed_energy}. Lives on the entity (not the round-scoped session) so an
## in-progress cast survives round boundaries, per the spec.
var casting_state: Dictionary = {}



func _init(
	p_combatant_id: String = "",
	p_name: String = "",
	p_team: String = "",
	p_hex_coord: HexCoordClass = null
) -> void:
	combatant_id = p_combatant_id
	name = p_name
	team = p_team
	hex_coord = p_hex_coord if p_hex_coord != null else HexCoordClass.new(0, 0)


## move_to(new_hex_coord) → void — FEAT-013 (US-013): the sole mutator of
## hex_coord. core/rules/movement.gd (the rule layer) is the only caller, after
## validating the move. Performs NO validation itself (Combatant is a data
## entity, not the rule-enforcing layer).
func move_to(new_hex_coord: HexCoordClass) -> void:
	hex_coord = new_hex_coord


# ── Combat accessors & behaviour (migration Phase A) ────────────────────────

## defense(kind) → int — the passive target number a d20 attack rolls against.
## kind ∈ {"ac","reflex","fortitude","will"} (spec: weapon Strikes target AC,
## spells target the defense named by the spell — see resolution.resolve_spell_
## attack). push_error + 0 on an unknown kind (fail-loud, matching the codebase's
## typed-error habit).
func defense(kind: String) -> int:
	match kind:
		"ac": return ac
		"reflex": return reflex
		"fortitude": return fortitude
		"will": return will
	push_error("Combatant.defense(): unknown defense kind '%s'" % kind)
	return 0

## is_conscious() → bool — a combatant at 0 HP is down (the Steel-trigger /
## living-target gate in resolution.gd). Derived from hp_current, not stored.
func is_conscious() -> bool:
	return hp_current > 0

## display_id() → String — the stable identity string the pipeline uses to key
## a combatant: its combatant_id when set, otherwise its name. Collapses the
## `x.get("combatant_id", x.get("name", ""))` idiom threaded through
## round_session.gd / resolve_action_use_case.gd (migration Phase C.3). A
## combatant built without an explicit id (e.g. the balance simulator's
## dict-sourced combatants) falls back to name exactly as that idiom did.
func display_id() -> String:
	return combatant_id if combatant_id != "" else name

## take_damage(amount) — reduce HP by `amount`. NOT clamped, mirroring the raw
## `hp_current -= damage` mutation the resolution pipeline performs today (Phase
## C swaps those sites to this method; keeping identical arithmetic preserves
## parity). Non-positive amounts are a safe subtraction.
func take_damage(amount: int) -> void:
	hp_current -= amount

## heal(amount) — restore HP, capped at hp_max (the Heal spell regains HP; no
## overheal).
func heal(amount: int) -> void:
	hp_current = mini(hp_max, hp_current + amount)

## spend_stamina(amount) — FEAT-002 (US-002; FR-001): the SOLE mutator that
## decrements Stamina from its live, in-place value on this entity. Combine
## (and every later Stamina-consuming verb) drains through THIS one method,
## so Stamina has exactly one source of truth and exactly one code path
## that changes it -- mirrors move_to()/take_damage()'s own "sole mutator"
## convention above. NOT clamped at 0 and performs no validation of its
## own (mirrors take_damage()'s unclamped arithmetic) -- a caller checks
## stamina against the required cost BEFORE calling this; that gating is a
## later Iteration N feature layered on top of this single mutator.
func spend_stamina(amount: int = 1) -> void:
	stamina -= amount

## Condition tags (String). has_/add_/remove_ keep the conditions[] list in one
## place; Off-Guard and Immobilized are read through has_condition().
func has_condition(condition: String) -> bool:
	return conditions.has(condition)

func add_condition(condition: String) -> void:
	if not conditions.has(condition):
		conditions.append(condition)

func remove_condition(condition: String) -> void:
	conditions.erase(condition)

## skill(name) → int — a skill rank (e.g. "mobility" for Dodge-worthiness),
## defaulting 0 for an unauthored skill (matches _build_defense_context.gd's
## .get("skills", {}).get(name, 0) reads).
func skill(skill_name: String) -> int:
	return int(skills.get(skill_name, 0))

## attribute(name) → int — dynamic attribute lookup by String name (e.g. a
## weapon's damage_modifier_attribute "strength"/"dexterity", or a defender's
## parry attribute). Replaces the dict's =attacker.get(name, 0)= — the 2-arg
## .get() form does NOT work on an instance (Object.get is 1-arg). Returns 0 for
## an unknown/absent attribute.
func attribute(attr_name: String) -> int:
	var v = get(attr_name)
	return int(v) if v != null else 0

## Cast-a-Spell hooks. begin_cast() (below) initializes casting_state for a
## first cast (FEAT-005). cancel_cast() is the SOLE mutator that clears
## casting_state — used both by ResolveCastUseCase's unconditional cleanup
## step on a completed resolution (FEAT-276) AND by core/application/
## use_cases/cancel_cast_use_case.gd's CancelCastUseCase (FEAT-280 / US-015;
## FR-017) when a lethal Opportunistic Strike interrupts an in-progress cast
## (mirroring iteration K FEAT-238's lethal-OS-cancels-Stride machinery) —
## in EITHER case it performs ONLY `casting_state = {}`, never touching a
## caster's round energy pool, so a cancellation never refunds
## committed_energy (ADR-003) simply because this method has no reference to
## that collaborator at all.
func is_casting() -> bool:
	return not casting_state.is_empty()

func cancel_cast() -> void:
	casting_state = {}


## begin_cast(spell_id, actions_cost, committed_energy) -> void — FEAT-005
## (US-005; FR-004): the SOLE mutator that initializes `casting_state` for a
## first cast (mirrors move_to()'s "sole mutator" convention above).
## BeginCastUseCase (core/application/use_cases/begin_cast_use_case.gd) is
## the ONE caller, and calls it ONLY after RoundEnergyPoolPort.reserve() has
## already succeeded -- this method itself performs no validation, matching
## Combatant's own "data entity, not the rule-enforcing layer" discipline
## (see move_to()'s doc).
##
## Builds a core/domain/casting_state.gd CastingState value object with
## `remaining_actions = actions_cost - 1` -- design notes' api_contracts #1:
## "sets casting_state{spell_id, remaining_actions=spell.actions_cost,
## committed_energy}, spends the turn action, remaining_actions -= 1" is
## folded into ONE atomic assignment here rather than two separate steps, so
## `casting_state` is never observably set at the pre-decrement value. A
## 2-action spell (e.g. Fire Bolt) begun this turn therefore shows
## remaining_actions == 1 immediately after this call returns.
func begin_cast(spell_id: String, actions_cost: int, committed_energy: int) -> void:
	var state := CastingStateClass.new(spell_id, actions_cost - 1, committed_energy, display_id())
	casting_state = state.to_dict()


# ── Dictionary interop (migration bridge; removed in Phase D) ────────────────

## from_dict(spec) → Combatant — build an entity from a combatant-shaped
## Dictionary (as CombatantFactory / test fixtures author today). Tolerant:
## missing keys take sensible defaults, so BOTH the enemy shape (with
## fortitude/reflex/will) and the party shape (without) round-trip. `is_enemy`
## derives from "_is_enemy" or, failing that, team == "Enemy"; `team` derives
## from "_is_enemy" when absent. Containers are duplicated to avoid aliasing the
## caller's mutable Dictionaries/Arrays (mirrors CombatantFactory's convention).
static func from_dict(spec: Dictionary) -> Combatant:
	var is_enemy_flag: bool = bool(spec.get("_is_enemy", spec.get("team", "") == "Enemy"))
	var c := Combatant.new(
		String(spec.get("combatant_id", "")),
		String(spec.get("name", "")),
		String(spec.get("team", "Enemy" if is_enemy_flag else "Player"))
	)
	# Phase C.3 parity: PRESERVE an ABSENT position as null rather than the
	# _init (0,0) default. Historically the pipeline passed positionless
	# combatant DICTS (no "hex_coord" key — e.g. core/sim/simulator.gd, many unit
	# fixtures); reach-gating (resolve_action_use_case / ai) skips a combatant
	# whose hex_coord is null. Defaulting an absent position to (0,0) here would
	# make two positionless combatants co-located and reach-REJECT every Strike
	# (a positionless sim battle would then never deal damage → never terminate).
	# A combatant built via new() (not from_dict) still defaults to (0,0).
	c.hex_coord = spec.get("hex_coord", null)
	c.hp_current      = int(spec.get("hp_current", 0))
	c.hp_max          = int(spec.get("hp_max", 0))
	c.stamina         = int(spec.get("stamina", 0))
	c.conscious       = bool(spec.get("conscious", true))
	c.ac              = int(spec.get("ac", 0))
	c.fortitude       = int(spec.get("fortitude", 0))
	c.reflex          = int(spec.get("reflex", 0))
	c.will            = int(spec.get("will", 0))
	c.strength        = int(spec.get("strength", 0))
	c.dexterity       = int(spec.get("dexterity", 0))
	c.intuition       = int(spec.get("intuition", 0))
	c.weapon          = (spec.get("weapon", {}) as Dictionary).duplicate(true)
	c.skills          = (spec.get("skills", {}) as Dictionary).duplicate(true)
	c.conditions      = (spec.get("conditions", []) as Array).duplicate()
	c.spellcasting_attribute_score = int(spec.get("spellcasting_attribute_score", 0))
	c.known_spell_ids = (spec.get("known_spell_ids", []) as Array).duplicate()
	c.initiative_roll = int(spec.get("_initiative_roll", 0))
	c.is_enemy        = is_enemy_flag
	c.casting_state   = (spec.get("casting_state", {}) as Dictionary).duplicate(true)
	return c

## to_dict() → Dictionary — emit the CANONICAL combatant shape (all four
## defenses + conditions[]; see the header shape-note on normalisation).
## Optional identity keys (combatant_id) and casting_state are included only
## when set, mirroring CombatantFactory's conditional emit. Containers are
## duplicated so callers can't mutate this entity's internals through the dict.
func to_dict() -> Dictionary:
	var d: Dictionary = {
		"name":             name,
		"team":             team,
		"hp_current":       hp_current,
		"hp_max":           hp_max,
		"stamina":          stamina,
		"conscious":        conscious,
		"ac":               ac,
		"fortitude":        fortitude,
		"reflex":           reflex,
		"will":             will,
		"strength":         strength,
		"dexterity":        dexterity,
		"intuition":        intuition,
		"weapon":           weapon.duplicate(true),
		"skills":           skills.duplicate(true),
		"conditions":       conditions.duplicate(),
		"_initiative_roll": initiative_roll,
		"_is_enemy":        is_enemy,
		"hex_coord":        hex_coord,
	}
	if combatant_id != "":
		d["combatant_id"] = combatant_id
	if not casting_state.is_empty():
		d["casting_state"] = casting_state.duplicate(true)
	# FEAT-002 (Iteration M P0-0): part of the NORMALISED canonical shape
	# (like "skills" above) — ALWAYS emitted, 0 / [] for a non-caster
	# combatant, so every consumer can read it via .get(key, default) with no
	# special-casing (mirrors this file's own "skills"/"weapon" convention,
	# NOT the optional combatant_id/casting_state convention immediately
	# above, since this is a permanent trait, not transient in-progress state).
	d["spellcasting_attribute_score"] = spellcasting_attribute_score
	d["known_spell_ids"] = known_spell_ids.duplicate()
	return d
