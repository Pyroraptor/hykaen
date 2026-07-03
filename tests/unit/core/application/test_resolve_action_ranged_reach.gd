extends GutTest
## tests/unit/core/application/test_resolve_action_ranged_reach.gd
##
## GUT test suite for FEAT-140 (DEF-007 / FR-014, US-007): ranged-weapon
## reach gating for Strike.
##
## core/application/resolve_action_use_case.gd is REUSED (not forked) —
## this suite adds coverage for the new HexMath.hex_distance()-based ranged
## reach precondition, layered on top of the pre-existing melee adjacency
## precondition already covered by
## tests/unit/core/application/test_resolve_action_reach.gd (which must
## keep passing UNCHANGED).
##
## A weapon Dictionary now MAY carry a "range_hexes" key (mirroring
## core/model/weapon_resource.gd's new range_hexes field, FEAT-140). When
## the acting combatant's weapon carries this key AND both combatant and
## target carry "hex_coord" data, the target must be within
## HexMath.hex_distance() <= weapon.range_hexes of the combatant, or the
## use case rejects the action with ERR_TARGET_OUT_OF_REACH and performs no
## side effects (no action-budget spend, no AttackEvent, no round-history
## entry) — exactly mirroring the melee ERR_TARGET_NOT_ADJACENT contract.
##
## Validates:
##   1. A ranged Strike against a target within range_hexes resolves
##      successfully and emits an AttackEvent.
##   2. A ranged Strike against a target beyond range_hexes is rejected
##      with ERR_TARGET_OUT_OF_REACH, no side effects.
##   3. A real ranged WeaponResource fixture (data/weapons/shortbow.tres)
##      wires its range_hexes field through to this same reach gate,
##      demonstrating the feature works end-to-end and not just against a
##      hand-built test Dictionary.
##   4. Existing melee reach behavior (weapon Dictionaries without
##      "range_hexes") is completely unaffected.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")
const WeaponResourceClass       = preload("res://core/model/weapon_resource.gd")


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


# ── Shared fixtures ──────────────────────────────────────────────────────────

const RANGED_RANGE_HEXES: int = 8  # mirrors shortbow's 40 ft. short range (5 ft. == 1 hex)


func _ranged_attacker(hex_coord, range_hexes: int = RANGED_RANGE_HEXES) -> Dictionary:
	return {
		"name":      "Archer",
		"dexterity": 3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": "dexterity",
			"proficiency_bonus": 2,
			"damage_die": 6,
			"range_hexes": range_hexes
		}
	}


func _target(hex_coord, hp: int = 50, ac: int = 10) -> Dictionary:
	return {"name": "Target", "hp_current": hp, "ac": ac, "hex_coord": hex_coord}


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: target within range_hexes — ranged Strike resolves successfully.
# ══════════════════════════════════════════════════════════════════════════════

func test_ranged_strike_against_target_within_range_resolves_and_returns_attack_event() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=12 -> roll_total = 12 + dexterity(3) + proficiency(2) = 17 vs ac=10 -> hit.
	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _ranged_attacker(HexCoordClass.new(0, 0))
	var target: Dictionary = _target(HexCoordClass.new(RANGED_RANGE_HEXES, 0))  # hex_distance == range_hexes

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "Ranged Strike within range_hexes must report ok:true")
	assert_true(result.get("resolved", false), "Ranged Strike within range_hexes must report resolved:true")
	assert_true(
		result.get("event", null) is RoundEventsClass.AttackEvent,
		"ActionResult must carry the emitted AttackEvent under the 'event' key"
	)
	assert_eq(rig["event_sink"].events.size(), 1, "Exactly one AttackEvent must be emitted")
	assert_true(rig["event_sink"].events[0] is RoundEventsClass.AttackEvent)


func test_ranged_strike_against_a_nearby_but_non_adjacent_target_resolves_successfully() -> void:
	# Distance 3 -- would fail melee adjacency, but is well within an 8-hex ranged weapon.
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _ranged_attacker(HexCoordClass.new(0, 0))
	var target: Dictionary = _target(HexCoordClass.new(3, 0))

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "A non-adjacent but in-range ranged Strike must succeed")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: target beyond range_hexes — rejected with ERR_TARGET_OUT_OF_REACH.
# ══════════════════════════════════════════════════════════════════════════════

func test_ranged_strike_against_target_beyond_range_is_rejected_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _ranged_attacker(HexCoordClass.new(0, 0))
	var target: Dictionary = _target(HexCoordClass.new(RANGED_RANGE_HEXES + 1, 0))  # 1 hex beyond range

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "Ranged Strike beyond range_hexes must report ok:false")
	assert_false(result.get("resolved", true), "Ranged Strike beyond range_hexes must report resolved:false")
	assert_eq(
		result.get("error", ""), "ERR_TARGET_OUT_OF_REACH",
		"rejection must carry error code ERR_TARGET_OUT_OF_REACH"
	)

	assert_eq(rig["event_sink"].events.size(), 0, "No AttackEvent may be emitted for a rejected out-of-range ranged Strike")
	assert_eq(rig["history"].entries.size(), 0, "No round-history entry may be appended for a rejected ranged Strike")
	assert_eq(target.get("hp_current", -1), 50, "Target HP must be untouched when the ranged Strike is rejected")
	assert_eq(
		ae.get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"The actor's action budget must remain UNSPENT when the ranged reach precondition rejects the Strike"
	)


func test_ranged_strike_far_beyond_range_is_still_rejected() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _ranged_attacker(HexCoordClass.new(0, 0), 2)  # tiny 2-hex range weapon
	var target: Dictionary = _target(HexCoordClass.new(10, 0))

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("ok", true))
	assert_eq(result.get("error", ""), "ERR_TARGET_OUT_OF_REACH")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: real ranged WeaponResource fixture wired end-to-end.
# ══════════════════════════════════════════════════════════════════════════════

func test_shortbow_resource_range_hexes_gates_the_ranged_reach_check() -> void:
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(shortbow, "data/weapons/shortbow.tres must load")
	if shortbow == null:
		return
	assert_is(shortbow, WeaponResourceClass, "shortbow.tres must be a WeaponResource")
	assert_true(shortbow.range_hexes > 1, "shortbow.range_hexes must exceed melee's default of 1")

	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = {
		"name": "Archer", "dexterity": 3, "hex_coord": HexCoordClass.new(0, 0),
		"weapon": {
			"damage_modifier_attribute": shortbow.damage_modifier_attribute,
			"proficiency_bonus": shortbow.proficiency_bonus,
			"damage_die": shortbow.damage_die,
			"range_hexes": shortbow.range_hexes
		}
	}

	var in_range_target: Dictionary = _target(HexCoordClass.new(shortbow.range_hexes, 0))
	var in_range_result: Dictionary = rig["use_case"].resolve(attacker, ae, in_range_target, "Strike", 1, 0)
	assert_true(in_range_result.get("ok", false), "Target at shortbow.range_hexes must be in range")

	var ae2 = ActionEconomyClass.new()
	ae2.start_of_round()
	var rig2: Dictionary = _make_use_case([12, 4])
	var out_of_range_target: Dictionary = _target(HexCoordClass.new(shortbow.range_hexes + 5, 0))
	var out_of_range_result: Dictionary = rig2["use_case"].resolve(attacker, ae2, out_of_range_target, "Strike", 1, 0)
	assert_false(out_of_range_result.get("ok", true), "Target well beyond shortbow.range_hexes must be rejected")
	assert_eq(out_of_range_result.get("error", ""), "ERR_TARGET_OUT_OF_REACH")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: existing melee weapons (no "range_hexes" key) are unaffected.
# ══════════════════════════════════════════════════════════════════════════════

func test_melee_weapon_without_range_hexes_key_still_uses_adjacency_check() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = {
		"name": "Attacker", "strength": 3, "hex_coord": HexCoordClass.new(0, 0),
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}
	}
	# hex_distance 3 -- would be in range for an 8-hex ranged weapon, but this
	# weapon Dictionary carries no "range_hexes" key, so it must still be
	# treated as melee and rejected as not-adjacent.
	var target: Dictionary = _target(HexCoordClass.new(3, 0))

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "A melee weapon Dictionary without range_hexes must remain adjacency-gated")
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_ADJACENT")
