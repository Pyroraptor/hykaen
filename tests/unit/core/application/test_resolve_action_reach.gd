extends GutTest
## tests/unit/core/application/test_resolve_action_reach.gd
##
## GUT test suite for FEAT-003 (US-003): melee reach gating for Strike.
##
## core/application/resolve_action_use_case.gd is REUSED (not forked, per
## ADR-002) — this suite adds coverage for the new hex_neighbors-based
## adjacency precondition on melee Strike resolution, layered on top of the
## pre-existing spend/damage/event/history behavior already covered by
## tests/test_resolve_action_use_case.gd (which must keep passing UNCHANGED).
##
## Combatant/target Dictionaries now MAY carry a "hex_coord" key (a
## core/geometry/hex_coord.gd HexCoord instance). When BOTH the acting
## combatant and the target carry a hex_coord, a melee Strike is gated by
## core/geometry/hex_math.gd's HexMath.hex_neighbors(): the target must be
## one of the actor's 6 flat-top axial neighbors, or the use case rejects the
## action with ERR_TARGET_NOT_ADJACENT and performs no side effects (no
## action-budget spend, no AttackEvent, no round-history entry) — mirroring
## the defense-in-depth precondition documented in api_contracts for
## resolve_action_use_case.execute().
##
## Validates:
##   1. Strike against an adjacent target resolves successfully — returns
##      ok:true (resolved:true) plus an "event" key holding the emitted
##      RoundEvents.AttackEvent.
##   2. Strike against a non-adjacent target is rejected —
##      ok:false (resolved:false), error:"ERR_TARGET_NOT_ADJACENT", no
##      AttackEvent emitted, no round-history entry appended, and the
##      actor's action budget is left UNSPENT (defense-in-depth must not
##      burn the actor's turn on a rejected precondition).

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")


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

func _attacker(hex_coord):
	# Phase C.3: the resolution pipeline consumes Combatant INSTANCES; from_dict()
	# lifts the authored spec so this fixture keeps authoring as a dict.
	return CombatantClass.from_dict({
		"name":      "Attacker",
		"strength":  3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


func _target(hex_coord, hp: int = 50, ac: int = 10):
	return CombatantClass.from_dict({"name": "Target", "hp_current": hp, "ac": ac, "hex_coord": hex_coord})


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: adjacent target — Strike resolves successfully.
# ══════════════════════════════════════════════════════════════════════════════

func test_strike_against_adjacent_target_resolves_and_returns_attack_event() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17 vs ac=10 -> hit.
	var rig: Dictionary = _make_use_case([12, 4])
	var attacker = _attacker(HexCoordClass.new(0, 0))
	var target = _target(HexCoordClass.new(1, 0))  # one of the 6 neighbors of (0,0)

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "Strike against an adjacent target must report ok:true")
	assert_true(result.get("resolved", false), "Strike against an adjacent target must report resolved:true")
	assert_true(
		result.get("event", null) is RoundEventsClass.AttackEvent,
		"ActionResult must carry the emitted AttackEvent under the 'event' key"
	)
	assert_eq(rig["event_sink"].events.size(), 1, "Exactly one AttackEvent must be emitted")
	assert_true(rig["event_sink"].events[0] is RoundEventsClass.AttackEvent)


func test_strike_against_each_of_the_six_neighbors_resolves_successfully() -> void:
	var origin := HexCoordClass.new(0, 0)
	var neighbor_offsets: Array = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]

	for offset in neighbor_offsets:
		var ae = ActionEconomyClass.new()
		ae.start_of_round()

		var rig: Dictionary = _make_use_case([12, 4])
		var attacker = _attacker(origin)
		var target = _target(HexCoordClass.new(offset[0], offset[1]))

		var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

		assert_true(
			result.get("ok", false),
			"Neighbor offset (%d,%d) must be treated as adjacent" % [offset[0], offset[1]]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: non-adjacent target — Strike rejected with ERR_TARGET_NOT_ADJACENT.
# ══════════════════════════════════════════════════════════════════════════════

func test_strike_against_non_adjacent_target_is_rejected_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker = _attacker(HexCoordClass.new(0, 0))
	var target = _target(HexCoordClass.new(3, 0))  # hex_distance 3 — not adjacent

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "Strike against a non-adjacent target must report ok:false")
	assert_false(result.get("resolved", true), "Strike against a non-adjacent target must report resolved:false")
	assert_eq(
		result.get("error", ""), "ERR_TARGET_NOT_ADJACENT",
		"rejection must carry error code ERR_TARGET_NOT_ADJACENT"
	)

	assert_eq(rig["event_sink"].events.size(), 0, "No AttackEvent may be emitted for a rejected non-adjacent Strike")
	assert_eq(rig["history"].entries.size(), 0, "No round-history entry may be appended for a rejected Strike")
	assert_eq(target.hp_current, 50, "Target HP must be untouched when the Strike is rejected")
	assert_eq(
		ae.get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"The actor's action budget must remain UNSPENT when the precondition rejects the Strike"
	)


func test_strike_at_hex_distance_two_is_still_rejected() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker = _attacker(HexCoordClass.new(0, 0))
	var target = _target(HexCoordClass.new(2, -1))  # hex_distance 2

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "A target at hex_distance 2 must not be treated as adjacent")
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_ADJACENT")


# ══════════════════════════════════════════════════════════════════════════════
# Backward compatibility: combatants without hex_coord are never reach-gated
# (pre-existing callers — e.g. core/combat/encounter.gd — do not yet populate
# hex_coord on their Dictionaries; the precondition must be a no-op for them).
# ══════════════════════════════════════════════════════════════════════════════

func test_strike_without_hex_coord_data_is_not_reach_gated() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker = CombatantClass.from_dict({
		"name": "Attacker", "strength": 3,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}
	})
	var target = CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 10})

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "Legacy callers without hex_coord data must not be reach-gated")
