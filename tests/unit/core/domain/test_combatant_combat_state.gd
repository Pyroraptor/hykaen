extends GutTest
## tests/unit/core/domain/test_combatant_combat_state.gd
##
## Combatant-entity migration — PHASE A. Covers the combat fields, behaviour
## methods, and to_dict()/from_dict() interop bridge added to
## core/domain/combatant.gd. The pipeline is NOT yet re-wired (Phase B+), so
## these assert the entity in isolation: accessors, mutators, tolerance to the
## asymmetric/lifecycle-accreting historical dict shape, and dict round-trip.

const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass   = preload("res://core/geometry/hex_coord.gd")


func _enemy_spec() -> Dictionary:
	# Canonical FULL (enemy-shaped) combatant dict — every key to_dict() emits,
	# so from_dict(spec).to_dict() must round-trip it exactly.
	return {
		"combatant_id":     "enemy_0",
		"name":             "Skeleton",
		"team":             "Enemy",
		"hp_current":       14,
		"hp_max":           14,
		"stamina":          0,
		"conscious":        true,
		"ac":               14,
		"fortitude":        13,
		"reflex":           12,
		"will":             12,
		"strength":         2,
		"dexterity":        1,
		"intuition":        0,
		"weapon":           {"damage_die": 6, "proficiency_bonus": 1, "parry_bonus": 0, "block_value": 0, "block_die": 0},
		"skills":           {"mobility": 1, "determination": 0},
		"conditions":       ["Off-Guard"],
		"_initiative_roll": 17,
		"_is_enemy":        true,
		"hex_coord":        HexCoordClass.new(2, -1),
	}


# ── defense() ───────────────────────────────────────────────────────────────

func test_defense_returns_the_named_passive_defense() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	assert_eq(c.defense("ac"), 14, "defense('ac') must return ac")
	assert_eq(c.defense("reflex"), 12, "defense('reflex') must return reflex")
	assert_eq(c.defense("fortitude"), 13, "defense('fortitude') must return fortitude")
	assert_eq(c.defense("will"), 12, "defense('will') must return will")

func test_defense_unknown_kind_returns_zero() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	assert_eq(c.defense("dodge"), 0, "an unknown defense kind must fail-loud to 0, not silently mis-read")


# ── vitals / conditions / skills ────────────────────────────────────────────

func test_take_damage_subtracts_unclamped() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	c.take_damage(5)
	assert_eq(c.hp_current, 9, "take_damage() must subtract raw (parity with hp_current -= damage)")
	assert_true(c.is_conscious(), "9 HP is still conscious")
	c.take_damage(20)
	assert_eq(c.hp_current, -11, "take_damage() is NOT clamped — mirrors the current dict mutation")
	assert_false(c.is_conscious(), "<= 0 HP is not conscious")

func test_heal_caps_at_hp_max() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	c.take_damage(10)          # 14 -> 4
	c.heal(3)                  # 4 -> 7
	assert_eq(c.hp_current, 7, "heal() restores HP")
	c.heal(100)                # 7 -> capped at 14
	assert_eq(c.hp_current, 14, "heal() must cap at hp_max (no overheal)")

func test_condition_add_has_remove() -> void:
	var c := CombatantClass.new()
	assert_false(c.has_condition("Immobilized"), "fresh combatant has no conditions")
	c.add_condition("Immobilized")
	c.add_condition("Immobilized")  # idempotent
	assert_true(c.has_condition("Immobilized"))
	assert_eq(c.conditions.size(), 1, "add_condition() must not duplicate")
	c.remove_condition("Immobilized")
	assert_false(c.has_condition("Immobilized"))

func test_skill_defaults_zero_for_unauthored() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	assert_eq(c.skill("mobility"), 1, "skill() reads an authored rank")
	assert_eq(c.skill("stealth"), 0, "skill() defaults 0 for an unauthored skill")


# ── casting hooks (reserved) ────────────────────────────────────────────────

func test_casting_hooks_default_and_cancel() -> void:
	var c := CombatantClass.new()
	assert_false(c.is_casting(), "a fresh combatant is not casting")
	c.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1}
	assert_true(c.is_casting(), "a non-empty casting_state means casting")
	c.cancel_cast()
	assert_false(c.is_casting(), "cancel_cast() clears the casting state")


# ── from_dict tolerance + to_dict round-trip ────────────────────────────────

func test_from_dict_populates_all_fields() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	assert_eq(c.combatant_id, "enemy_0")
	assert_eq(c.name, "Skeleton")
	assert_eq(c.hp_max, 14)
	assert_eq(c.reflex, 12)
	assert_eq(c.initiative_roll, 17, "reads dict key '_initiative_roll'")
	assert_true(c.is_enemy, "reads dict key '_is_enemy'")
	assert_eq(c.hex_coord.q, 2)
	assert_eq(c.hex_coord.r, -1)

func test_from_dict_tolerates_party_shape_without_the_three_saves() -> void:
	# Party builds historically omit fortitude/reflex/will — from_dict must
	# default them rather than error, and derive team/is_enemy sensibly.
	var party_spec := {
		"name": "Titus", "hp_current": 20, "hp_max": 20, "ac": 17,
		"strength": 3, "dexterity": 2, "intuition": 1,
		"weapon": {"damage_die": 8}, "skills": {},
	}
	var c := CombatantClass.from_dict(party_spec)
	assert_eq(c.ac, 17, "present keys are read")
	assert_eq(c.fortitude, 0, "missing fortitude defaults to 0 (party shape tolerated)")
	assert_eq(c.reflex, 0, "missing reflex defaults to 0")
	assert_eq(c.will, 0, "missing will defaults to 0")
	assert_false(c.is_enemy, "no _is_enemy and non-Enemy team → not an enemy")
	assert_eq(c.team, "Player", "team derived to Player when not an enemy")

func test_to_dict_round_trips_the_canonical_shape() -> void:
	var spec := _enemy_spec()
	var round_tripped := CombatantClass.from_dict(spec).to_dict()
	assert_eq(round_tripped, spec,
		"from_dict(spec).to_dict() must reproduce the canonical combatant dict exactly")

func test_to_dict_duplicates_containers() -> void:
	var c := CombatantClass.from_dict(_enemy_spec())
	var d := c.to_dict()
	d["weapon"]["damage_die"] = 999
	d["conditions"].append("Prone")
	assert_eq(c.weapon["damage_die"], 6, "mutating the to_dict() weapon must not alias the entity")
	assert_eq(c.conditions.size(), 1, "mutating the to_dict() conditions must not alias the entity")

func test_from_dict_duplicates_containers() -> void:
	var spec := _enemy_spec()
	var c := CombatantClass.from_dict(spec)
	c.weapon["damage_die"] = 999
	c.add_condition("Prone")
	assert_eq(spec["weapon"]["damage_die"], 6, "mutating the entity must not alias the source spec's weapon")
	assert_eq((spec["conditions"] as Array).size(), 1, "mutating the entity must not alias the source spec's conditions")
