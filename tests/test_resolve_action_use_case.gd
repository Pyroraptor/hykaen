extends GutTest
## tests/test_resolve_action_use_case.gd
##
## GUT test suite for FEAT-098 (FIND-096): core/application/resolve_action_use_case.gd
## — single Strike/reaction resolution extracted out of
## core/combat/encounter.gd's run_round() into the Application layer.
##
## Exercises ResolveActionUseCase IN ISOLATION using:
##   - a real core/rules/action_economy.gd ActionEconomy (domain) for
##     spend_action() Result handling,
##   - a scripted fake RandomNumberPort (controls exactly which die values
##     are "rolled", for fully deterministic hit/crit/miss/damage assertions),
##   - a stubbed EventSinkPort and RoundHistoryPort (capture emitted
##     events/appended entries for inspection).
##
## Validates:
##   1. spend_action() success -> Strike resolves; spend_action() failure
##      (ALREADY_SPENT) -> {"resolved": false}, no events/history recorded.
##   2. Damage application: hit/miss/crit math driven entirely by the
##      injected RandomNumberPort, target.hp_current mutated by the correct
##      damage_final.
##   3. Event emission: 'attack' always emitted; 'combatant_defeated'
##      emitted iff the target's HP transitions to <= 0.
##   4. RoundHistoryPort.append() receives the correct
##      budget_remaining/round/cycle_index/action fields.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")

## NOTE (FEAT-100 regression fix / FIND-096): FEAT-099 switched
## EventSinkPort.emit() to receive TYPED RefCounted value objects
## (RoundEvents.AttackBroadcast / CombatantDefeatedEvent / EncounterResultEvent)
## instead of raw Dictionaries — see core/rules/round_events.gd and
## core/application/event_sink_port.gd. This suite's doubles/assertions are
## updated accordingly: FakeEventSinkPort.emit() must NOT type-hint its
## parameter as Dictionary (a typed value object is not a Dictionary and the
## static type check would reject it at runtime), and event introspection
## below uses `is RoundEventsClass.XEvent` + direct field access rather than
## Dictionary-style `.get(key, default)` (Object.get() has no 2-arg/default
## overload and errors at runtime when called with one).


## ScriptedRandomNumberPort — returns a pre-scripted sequence of int values,
## one per roll() call, in order — lets tests pin the EXACT attack roll and
## damage roll without depending on any real randomness.
class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var calls: Array = []   ## records each dice_spec passed to roll(), in order

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		calls.append(dice_spec)
		var v = _values[_index]
		_index += 1
		return v


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


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker() -> Dictionary:
	return {
		"name":     "Attacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


func _target(hp: int = 50, ac: int = 10) -> Dictionary:
	return {"name": "Target", "hp_current": hp, "ac": ac}


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port    = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: spend_action()/spend_reaction() Result handling.
# ══════════════════════════════════════════════════════════════════════════════

func test_already_spent_action_economy_returns_unresolved_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	# FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so
	# exhausting the round budget requires a fresh start_of_turn() before
	# each spend (AC-4 interleaving simulated across MAX_BUDGET turns).
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.start_of_turn()
		ae.spend_action({})
	assert_true(ae.is_spent(), "sanity: ActionEconomy must be Spent after MAX_BUDGET spends")

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target()

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_false(result.get("resolved", true), "resolve() on an already-Spent ActionEconomy must report resolved:false")
	assert_false(result.get("ok", true), "resolve() on an already-Spent ActionEconomy must report ok:false")
	assert_eq(
		result.get("error", ""), "ERR_NO_ACTION_REMAINING",
		"FEAT-125/FIND-121: ALREADY_SPENT must surface the typed ERR_NO_ACTION_REMAINING error code"
	)
	assert_eq(rig["event_sink"].events.size(), 0, "No events may be emitted when the spend fails")
	assert_eq(rig["history"].entries.size(), 0, "No history entry may be recorded when the spend fails")
	assert_eq(target.get("hp_current", -1), 50, "Target HP must be untouched when the spend fails")


func test_successful_spend_consumes_one_budget_and_resolves() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])  # raw=12 (miss, see below), no damage roll consumed
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 99)  # very high AC -> guaranteed miss

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("resolved", false), "A fresh ActionEconomy must allow the action to resolve")
	assert_eq(ae.get_remaining(), 6, "spend_action() must decrement the shared budget by exactly 1")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: damage application driven entirely by the injected
# RandomNumberPort (hit / miss / crit math).
# ══════════════════════════════════════════════════════════════════════════════

func test_hit_non_crit_applies_correct_damage_via_random_number_port() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17 vs ac=10
	# -> hit (17>=10), not crit (17-10=7 < 10). Damage roll value=4 -> damage_final = 4 + 3 = 7.
	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("resolved", false))
	assert_eq(result.get("damage_final", -1), 7, "damage_final must equal damage_roll(4) + strength_mod(3) = 7")
	assert_eq(target.get("hp_current", -1), 43, "target.hp_current must be reduced by damage_final (50 - 7 = 43)")
	assert_false(result.get("target_defeated", true), "Target must not be defeated (43 HP remaining)")

	# RNG consumption order: d20 attack roll first, THEN the damage roll.
	assert_eq(rig["rng_port"].calls.size(), 2, "Exactly 2 rolls must be consumed: attack roll + damage roll")
	assert_eq(rig["rng_port"].calls[0], {"die": 20, "count": 1}, "First roll must be the d20 attack roll")
	assert_eq(rig["rng_port"].calls[1], {"die": 6, "count": 1}, "Second roll must be a single (non-crit) damage die")


func test_crit_doubles_damage_dice_and_attribute_modifier() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=20 -> roll_total = 20 + 3 + 2 = 25 vs ac=10 -> hit, diff=15>=10 -> crit.
	# Crit damage roll value=9 (sum of 2 dice) -> damage_final = 9 + 3*2 = 15.
	var rig: Dictionary = _make_use_case([20, 9])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_eq(result.get("damage_final", -1), 15, "Crit damage_final must equal damage_roll(9) + strength_mod(3)*2 = 15")
	assert_eq(target.get("hp_current", -1), 35, "target.hp_current must be reduced to 35 (50 - 15)")
	assert_eq(rig["rng_port"].calls[1], {"die": 6, "count": 2}, "A crit must roll 2 damage dice, not 1")

	var attack_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "Exactly one attack event must be emitted")
	assert_true(attack_events[0].crit, "attack event must report crit:true")


func test_miss_applies_zero_damage_and_consumes_no_damage_roll() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=1 -> roll_total = 1 + 3 + 2 = 6 vs ac=10 -> miss. No damage roll consumed.
	var rig: Dictionary = _make_use_case([1])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_eq(result.get("damage_final", -1), 0, "A miss must apply zero damage")
	assert_eq(target.get("hp_current", -1), 50, "target.hp_current must be untouched on a miss")
	assert_eq(rig["rng_port"].calls.size(), 1, "A miss must consume only the attack roll, never a damage roll")

	var attack_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_false(attack_events[0].hit, "attack event must report hit:false")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: event emission ('attack' always; 'combatant_defeated' iff the
# target's HP transitions to <= 0).
# ══════════════════════════════════════════════════════════════════════════════

func test_attack_event_emitted_with_correct_fields() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	rig["use_case"].resolve(attacker, ae, target, "Strike", 3, 2)

	var events: Array = rig["event_sink"].events
	assert_eq(events.size(), 1, "Only an 'attack' event is expected (target survives)")
	var ev = events[0]
	assert_true(ev is RoundEventsClass.AttackBroadcast, "emitted event must be a typed RoundEvents.AttackBroadcast")
	assert_eq(ev.round, 3, "event round must match the round_number argument")
	assert_eq(ev.attacker_name, "Attacker")
	assert_eq(ev.target_name, "Target")
	assert_eq(ev.defense_type, "ac")
	assert_eq(ev.defense_value, 10)
	assert_eq(ev.damage_final, 7)


func test_combatant_defeated_event_emitted_when_hp_drops_to_zero_or_below() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	# raw=12 -> roll_total=17 vs ac=10 -> hit; damage roll value=4 -> damage_final=7.
	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(5, 10)  # 5 HP — lethal given damage_final=7

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("target_defeated", false), "target_defeated must be true once HP <= 0")
	assert_true(target.get("hp_current", 1) <= 0, "target.hp_current must be <= 0")

	var events: Array = rig["event_sink"].events
	assert_eq(events.size(), 2, "Both 'attack' and 'combatant_defeated' events must be emitted")
	assert_true(events[0] is RoundEventsClass.AttackBroadcast, "'attack' must be emitted before 'combatant_defeated'")
	assert_true(events[1] is RoundEventsClass.CombatantDefeatedEvent, "second emitted event must be a typed RoundEvents.CombatantDefeatedEvent")
	assert_eq(events[1].name, "Target")
	assert_eq(events[1].defeated_by, "Attacker")


func test_no_combatant_defeated_event_when_target_survives() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(1000, 10)

	rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0, "No combatant_defeated event may be emitted when the target survives")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: RoundHistoryPort.append() receives the correct
# budget_remaining/round/cycle_index/action fields.
# ══════════════════════════════════════════════════════════════════════════════

func test_round_history_entry_records_post_spend_budget_and_cycle_index() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	ae.spend_action({})  # pre-spend once: budget 7 -> 6
	# FEAT-003 (ADR-103): the upcoming resolve() call below spends its own
	# action, so it needs a fresh turn boundary now that the pre-spend above
	# already used this turn's one action.
	ae.start_of_turn()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	rig["use_case"].resolve(attacker, ae, target, "Strike", 4, 3)

	var entries: Array = rig["history"].entries
	assert_eq(entries.size(), 1, "Exactly one round-history entry must be appended")
	var entry: Dictionary = entries[0]
	assert_eq(entry.get("budget_remaining", -1), 5, "budget_remaining must reflect the POST-spend value (7 -> 6 -> 5)")
	assert_eq(entry.get("round", -1), 4, "history entry round must match the round_number argument")
	assert_eq(entry.get("cycle_index", -1), 3, "history entry cycle_index must match the cycle_index argument")
	assert_eq(entry.get("action", ""), "Strike", "history entry action must match the action_name argument")
	assert_eq(entry.get("attacker", {}).get("name", ""), "Attacker")
	assert_eq(entry.get("target", {}).get("name", ""), "Target")
	assert_eq(entry.get("damage_final", -1), 7)
	assert_eq(entry.get("roll", -1), 17, "history entry roll must equal the computed roll_total")


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-125 (FIND-121): typed error codes for the remaining failure paths —
# ERR_NO_ACTION_REMAINING (covered above), ERR_TARGET_INVALID,
# ERR_NOT_ACTIVE_COMBATANT. ERR_TARGET_NOT_ADJACENT is covered separately by
# tests/unit/core/application/test_resolve_action_reach.gd (US-003) and is
# unchanged by this feature.
# ══════════════════════════════════════════════════════════════════════════════

func test_target_does_not_exist_returns_err_target_invalid_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var missing_target: Dictionary = {}  # "does not exist" sentinel

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, missing_target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "Strike against a nonexistent target must report ok:false")
	assert_false(result.get("resolved", true), "Strike against a nonexistent target must report resolved:false")
	assert_eq(result.get("error", ""), "ERR_TARGET_INVALID")
	assert_eq(rig["event_sink"].events.size(), 0, "No events may be emitted for an invalid target")
	assert_eq(rig["history"].entries.size(), 0, "No history entry may be recorded for an invalid target")
	assert_eq(ae.get_remaining(), ActionEconomyClass.MAX_BUDGET, "The actor's action budget must remain UNSPENT")


func test_target_already_defeated_returns_err_target_invalid_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var defeated_target: Dictionary = _target(0, 10)  # hp_current <= 0 -> already defeated

	var result: Dictionary = rig["use_case"].resolve(attacker, ae, defeated_target, "Strike", 1, 0)

	assert_false(result.get("ok", true), "Strike against an already-defeated target must report ok:false")
	assert_false(result.get("resolved", true), "Strike against an already-defeated target must report resolved:false")
	assert_eq(result.get("error", ""), "ERR_TARGET_INVALID")
	assert_eq(rig["event_sink"].events.size(), 0, "No events may be emitted for an already-defeated target")
	assert_eq(rig["history"].entries.size(), 0, "No history entry may be recorded for an already-defeated target")
	assert_eq(ae.get_remaining(), ActionEconomyClass.MAX_BUDGET, "The actor's action budget must remain UNSPENT")


func test_non_active_combatant_returns_err_not_active_combatant_with_no_side_effects() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	# The current turn's actor is "someone_else" -- attacker ("Attacker") is
	# not the active combatant.
	var result: Dictionary = rig["use_case"].resolve(
		attacker, ae, target, "Strike", 1, 0, "someone_else"
	)

	assert_false(result.get("ok", true), "resolve() for a non-active combatant must report ok:false")
	assert_false(result.get("resolved", true), "resolve() for a non-active combatant must report resolved:false")
	assert_eq(result.get("error", ""), "ERR_NOT_ACTIVE_COMBATANT")
	assert_eq(rig["event_sink"].events.size(), 0, "No events may be emitted for a non-active combatant")
	assert_eq(rig["history"].entries.size(), 0, "No history entry may be recorded for a non-active combatant")
	assert_eq(target.get("hp_current", -1), 50, "Target HP must be untouched")
	assert_eq(ae.get_remaining(), ActionEconomyClass.MAX_BUDGET, "The actor's action budget must remain UNSPENT")


func test_active_combatant_id_matching_combatant_id_key_resolves_normally() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	attacker["combatant_id"] = "attacker_1"
	var target: Dictionary = _target(50, 10)

	var result: Dictionary = rig["use_case"].resolve(
		attacker, ae, target, "Strike", 1, 0, "attacker_1"
	)

	assert_true(result.get("ok", false), "Strike must resolve when active_combatant_id matches combatant_id")
	assert_true(result.get("resolved", false))


func test_active_combatant_id_omitted_is_backward_compatible_no_op() -> void:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()

	var rig: Dictionary = _make_use_case([12, 4])
	var attacker: Dictionary = _attacker()
	var target: Dictionary = _target(50, 10)

	# StrikeActionControl/RoundSession never pass active_combatant_id -- the
	# 6-positional-argument call shape (FEAT-098/FEAT-003, unchanged) must
	# keep resolving exactly as before FEAT-125.
	var result: Dictionary = rig["use_case"].resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "Omitting active_combatant_id must remain a no-op (backward compatible)")
	assert_true(result.get("resolved", false))
