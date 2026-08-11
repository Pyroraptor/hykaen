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


## FEAT-393 (US-001/US-002, RISK-001 remediation, PR-006): a target that is
## NEITHER a CombatantClass instance NOR a Dictionary — the caller-contract
## violation the if/elif type-branch must fail CLOSED against rather than
## silently defaulting combatant_id as if it were the legitimate
## dict-missing-combatant_id case. Deliberately carries `name`/`hp_current`
## (so it clears the earlier, unrelated `target.name`/`target.hp_current <=
## 0` reads _finalize_strike_result() performs for EVERY target shape) but
## has NO `combatant_id` property and does not extend CombatantClass or
## Dictionary — isolating this test to the type-branch under repair.
class _MalformedTarget:
	extends RefCounted

	var name: String = "Malformed"
	var hp_current: int = 0


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


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-393 (US-001/US-002, RISK-001 remediation, PR-006): targeted hardening
# review of the if/elif type-branch — edge-case inputs beyond the two
# happy-path shapes (typed CombatantClass, well-formed Dictionary) already
# pinned above.
# ══════════════════════════════════════════════════════════════════════════════

## Regression re-affirmation (RISK-001 test #1): a well-formed Dictionary
## target missing the optional "combatant_id" key must still emit
## CombatantDefeatedEvent.combatant_id == "" with no exception — this is the
## exact shape that crashed the pre-FEAT-001 eager ternary. Already exercised
## by test_dictionary_target_at_zero_hp_is_defeated_with_no_script_error()
## above; re-affirmed here explicitly under FEAT-393 for traceability against
## RISK-001's own acceptance bullet.
func test_feat393_wellformed_dictionary_missing_combatant_id_still_defeats_cleanly() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var target: Dictionary = _fragile_combatant("ReAffirmed", 0)
	assert_false(target.has("combatant_id"), "fixture precondition: _fragile_combatant must not carry a combatant_id key")

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "a well-formed Dictionary missing combatant_id must still report target_defeated == true")
	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "exactly one combatant_defeated event must be emitted")
	assert_eq(defeated_events[0].combatant_id, "", "combatant_id must default to '' — never raise — when the key is absent")


## RISK-001 test #2: a Dictionary target carrying ONLY the two fields the
## documented contract guarantees ("hp_current" and "name") — no "ac", no
## "weapon", no "combatant_id", no other non-critical field — must still
## compute target_defeated correctly and must not crash. This isolates the
## Dictionary branch from every optional field a richer fixture (like
## _fragile_combatant) happens to also carry.
func test_bare_dictionary_with_only_hp_current_and_name_computes_defeat_without_crash() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var bare_target: Dictionary = {"hp_current": 0, "name": "Bare"}

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), bare_target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result.get("target_defeated", false), "a bare Dictionary with only hp_current/name at hp_current<=0 must report target_defeated == true")
	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "exactly one combatant_defeated event must be emitted for the bare Dictionary")
	assert_eq(defeated_events[0].combatant_id, "", "a bare Dictionary lacking every optional field, including combatant_id, must default to '' — never raise")
	assert_eq(defeated_events[0].name, "Bare", "the defeated target's name must be threaded through unchanged for the bare Dictionary")
	assert_eq(defeated_events[0].defeated_by, "Attacker", "the attacking combatant's name must be threaded through unchanged for the bare Dictionary")

	# Surviving case: same minimal shape, but hp_current > 0.
	var bare_survivor: Dictionary = {"hp_current": 1, "name": "BareSurvivor"}
	var survivor_result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), bare_survivor, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)
	assert_false(survivor_result.get("target_defeated", true), "a bare Dictionary at hp_current>0 must report target_defeated == false")


## RISK-001 test #3 (the risk's own scenario — "may miss an edge case ...
## reintroducing a crash under a different input pattern"): a target that is
## NEITHER a CombatantClass instance NOR a Dictionary is a caller contract
## violation the if/elif branch must fail CLOSED against — it must NOT raise
## a fresh engine error, and it must NOT silently emit a
## CombatantDefeatedEvent whose combatant_id is masked/defaulted as if this
## were the legitimate dict-missing-combatant_id path (that would hide the
## contract violation behind output indistinguishable from a normal case).
## The verifiable, non-swallowed fail-closed signal this suite asserts on is
## the ABSENCE of any emitted CombatantDefeatedEvent for the malformed
## target — an absent event can never be mistaken for the documented ''
## default, whereas an emitted one with combatant_id == "" could.
func test_unrecognized_target_type_fails_closed_without_masked_defeat_event() -> void:
	var rig: Dictionary = _make_use_case()
	var attacker = _attacker()
	var malformed_target = _MalformedTarget.new()
	assert_false(malformed_target is Dictionary, "fixture precondition: _MalformedTarget must not be a Dictionary")

	var result: Dictionary = rig["use_case"]._finalize_strike_result(
		attacker, _fresh_ae(), malformed_target, "Strike", 1, 0, {"remaining": 6}, _zero_damage_strike_result()
	)

	assert_true(result is Dictionary, "_finalize_strike_result() must still return its normal Dictionary shape rather than crashing outright")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0, "an unrecognized target type must NEVER produce a CombatantDefeatedEvent — fail closed rather than silently defaulting combatant_id, per RISK-001/the fail-closed design contract")

	# The 'attack' event is unrelated to the combatant_id type-branch under
	# repair and must still be emitted normally — this confirms the fail-
	# closed behavior is scoped to the CombatantDefeatedEvent construction
	# only, not a wholesale abort of _finalize_strike_result().
	var attack_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "the unrelated 'attack' event must still be emitted even when the defeat event is withheld")
