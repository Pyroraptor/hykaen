extends GutTest
## tests/test_finalize_strike_result.gd
##
## GUT regression suite for FEAT-001 (US-001/FR-001, ADR-001): pins
## core/application/resolve_action_use_case.gd's ResolveActionUseCase.
## _finalize_strike_result() against the SCRIPT ERROR root-caused by a typed
## ternary at (pre-fix) lines ~638-640:
##
##   var target_cid: String = target.get("combatant_id", "") if target is Dictionary else target.combatant_id
##
## GDScript 4.3 eagerly evaluates BOTH operands of a ternary assigned to a
## typed variable, so `target.combatant_id` (the else-branch) is evaluated
## even when `target` is a plain Dictionary — raising "Invalid access to
## property or key 'combatant_id' on a base object of type 'Dictionary'" and
## aborting _finalize_strike_result() mid-execution (a partially-updated
## encounter: budget tracking corrupted, zero events emitted).
##
## This suite exercises _finalize_strike_result() DIRECTLY (it is GDScript's
## "_"-prefixed convention-only privacy, callable from a test double) for
## BOTH target shapes the design notes document as legal at this seam:
##   1. A typed CombatantClass target (core/domain/combatant.gd).
##   2. A plain Dictionary target (the shape produced by
##      tests/test_encounter_regression.gd's `_fragile_combatant` factory /
##      core/combat/encounter.gd's legacy caller path).
##
## Validates, for EACH shape:
##   - hp_current <= 0 -> target_defeated == true, no SCRIPT ERROR raised.
##   - hp_current > 0  -> target_defeated == false.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
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


## A no-roll RandomNumberPort — _finalize_strike_result() itself never rolls
## dice (that already happened upstream in _resolve_strike()), so this
## double's roll()/d20() are never expected to be called; present only to
## satisfy ResolveActionUseCase's constructor contract.
class UnusedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	func roll(_dice_spec: Dictionary) -> int:
		push_error("UnusedRandomNumberPort.roll() must never be called by _finalize_strike_result()")
		return 0


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


## Typed CombatantClass target — the CombatantClass branch of the fixed
## if/elif type-branch.
func _typed_target(hp: int, combatant_id: String = "target_1"):
	return CombatantClass.from_dict({
		"name":         "Target",
		"combatant_id": combatant_id,
		"hp_current":   hp,
		"ac":           10
	})


## A plain Dictionary target mirroring
## tests/test_encounter_regression.gd's `_fragile_combatant` factory — the
## legacy untyped shape encounter.gd/simulator.gd still pass in places, and
## the shape that crashed the pre-fix ternary's else-branch (no
## "combatant_id" key at all).
func _fragile_combatant(p_name: String, hp: int) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": hp,
		"ac":         1,
		"strength":   1,
		"dexterity":  1,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4
		}
	}


func _make_use_case() -> Dictionary:
	var rng_port    = UnusedRandomNumberPort.new()
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "event_sink": event_sink, "history": history}


## A strike_result Dictionary shaped like core/rules/resolution.gd's
## resolve_weapon_attack() return value — _finalize_strike_result()'s
## documented contract (see that method's own file-level doc). damage_final
## of 0 means _finalize_strike_result() applies NO further damage itself;
## each test pre-sets the target's hp_current to the value under test
## (already <= 0 or > 0) so this suite isolates the target_defeated /
## combatant_id branching logic from the damage-application arithmetic
## covered by tests/test_resolve_action_use_case.gd.
func _zero_damage_strike_result() -> Dictionary:
	return {
		"hit":              false,
		"crit":             false,
		"roll_total":       1,
		"damage_raw":       0,
		"damage_final":     0,
		"defense_value":    10,
		"defender_stepped": false,
		"active_defense_applied": "none",
		"on_hit_suppressed": false,
	}


func _fresh_ae() -> ActionEconomyClass:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	return ae


# ══════════════════════════════════════════════════════════════════════════════
# Typed CombatantClass target.
# ══════════════════════════════════════════════════════════════════════════════

func test_typed_combatant_target_at_zero_hp_is_defeated_with_no_engine_error() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target = _typed_target(0, "target_1")

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "CombatantClass target at hp_current<=0 must report target_defeated == true")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "Exactly one combatant_defeated event must be emitted for a defeated typed target")
	assert_eq(defeated_events[0].combatant_id, "target_1", "the typed branch must read combatant_id via property access")

	# FEAT-002 (US-002/FR-002/FR-003): the combatant_id fix must not disturb
	# the event's other fields — round_number, the defeated target's name, and
	# the attacking combatant's name are unchanged from pre-fix expectations.
	assert_eq(defeated_events[0].round, 1, "round_number must be threaded through unchanged for a typed target")
	assert_eq(defeated_events[0].name, "Target", "the defeated target's name must be threaded through unchanged for a typed target")
	assert_eq(defeated_events[0].defeated_by, "Attacker", "the attacking combatant's name must be threaded through unchanged for a typed target")


func test_typed_combatant_target_at_negative_hp_is_defeated_with_no_engine_error() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target = _typed_target(-5, "target_1")

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "CombatantClass target at negative hp_current must report target_defeated == true")


func test_typed_combatant_target_above_zero_hp_is_not_defeated() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target = _typed_target(50, "target_1")

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_false(result.get("target_defeated", true), "CombatantClass target at hp_current>0 must report target_defeated == false")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0, "No combatant_defeated event may be emitted for a surviving typed target")


# ══════════════════════════════════════════════════════════════════════════════
# Plain Dictionary target (`_fragile_combatant`-shaped, no "combatant_id" key)
# — the shape that crashed the pre-fix eager ternary.
# ══════════════════════════════════════════════════════════════════════════════

func test_dictionary_target_at_zero_hp_is_defeated_with_no_script_error() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target: Dictionary = _fragile_combatant("Fragile", 0)

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "Dictionary target at hp_current<=0 must report target_defeated == true, with no SCRIPT ERROR raised")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "Exactly one combatant_defeated event must be emitted for a defeated Dictionary target")
	assert_eq(defeated_events[0].combatant_id, "", "a Dictionary target with no 'combatant_id' key must default to '' (never raise)")

	# FEAT-002 (US-002/FR-002/FR-003): the '' default for combatant_id must
	# not disturb the event's other fields — round_number, the defeated
	# target's name, and the attacking combatant's name are unchanged from
	# pre-fix expectations.
	assert_eq(defeated_events[0].round, 1, "round_number must be threaded through unchanged for a Dictionary target")
	assert_eq(defeated_events[0].name, "Fragile", "the defeated target's name must be threaded through unchanged for a Dictionary target")
	assert_eq(defeated_events[0].defeated_by, "Attacker", "the attacking combatant's name must be threaded through unchanged for a Dictionary target")


func test_dictionary_target_at_negative_hp_is_defeated_with_no_script_error() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target: Dictionary = _fragile_combatant("Fragile", -3)

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "Dictionary target at negative hp_current must report target_defeated == true, with no SCRIPT ERROR raised")


func test_dictionary_target_above_zero_hp_is_not_defeated() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target: Dictionary = _fragile_combatant("Fragile", 1)

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_false(result.get("target_defeated", true), "Dictionary target at hp_current>0 must report target_defeated == false")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0, "No combatant_defeated event may be emitted for a surviving Dictionary target")


func test_dictionary_target_with_explicit_combatant_id_is_read_without_error() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target: Dictionary = _fragile_combatant("Fragile", 0)
	target["combatant_id"] = "fragile_1"

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false))
	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events[0].combatant_id, "fragile_1", "a Dictionary target WITH a 'combatant_id' key must surface it on the emitted event")

	# FEAT-002 (US-002/FR-002/FR-003): round_number/name/defeated_by remain
	# unchanged when combatant_id is sourced from an explicit Dictionary key.
	assert_eq(defeated_events[0].round, 1, "round_number must be threaded through unchanged when combatant_id is explicit")
	assert_eq(defeated_events[0].name, "Fragile", "the defeated target's name must be threaded through unchanged when combatant_id is explicit")
	assert_eq(defeated_events[0].defeated_by, "Attacker", "the attacking combatant's name must be threaded through unchanged when combatant_id is explicit")
