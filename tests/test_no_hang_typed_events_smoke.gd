extends GutTest
## tests/test_no_hang_typed_events_smoke.gd
##
## FEAT-005 (US-005, FR-006/FR-008, ADR-003): dedicated post-fix regression
## smoke test proving the AD-1 crash fix in
## core/application/resolve_action_use_case.gd's _finalize_strike_result()
## (see docs/iterations/iteration-AD-gut-regression-fix.org) did not
## reintroduce a hang and that the typed round-event objects it emits
## (core/rules/round_events.gd's RoundEvents.*) remain well-formed and
## readable across a full, defeat-spanning encounter.
##
## DELIBERATELY SEPARATE from the pre-existing
## tests/test_encounter_no_hang_typed_events_smoke.gd (FEAT-100) — this is a
## narrower, independent pinning suite for THIS iteration's fix. It never
## edits core/combat/encounter.gd or core/sim/simulator.gd (ADR-003).
##
## Note on typed-event introspection (mirrors
## tests/test_resolve_action_use_case.gd's own documented convention):
## core/rules/round_events.gd's value objects are plain RefCounted objects,
## NOT Dictionaries. `Object.get(property)` has no 2-argument/default
## overload, so calling `event.get("some_key", default)` on one of these
## typed events raises a runtime SCRIPT ERROR ("Invalid call ... Expected 1
## arguments"). This suite therefore ALWAYS introspects events via `is
## RoundEventsClass.XEvent` + direct field access (e.g. `event.name`,
## `event.combatant_id`), never via `.get()` — which is itself part of what
## "no SCRIPT ERROR" this suite's test_criteria requires.

const EncounterClass            = preload("res://core/combat/encounter.gd")
const RNGClass                  = preload("res://core/rules/rng.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")

## Safety cap on run_round() calls — reaching completion (rather than
## hitting this cap) is itself the primary no-hang proof.
const MAX_ROUNDS_GUARD: int = 50

## Generous wall-clock ceiling (ms) for one full encounter run — proves the
## AD-1 fix did not reintroduce the pre-fix "corrupted round budget /
## safe-DRAW backstop churn" pathology that made runs balloon in duration.
const MAX_ELAPSED_MS: int = 5000


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

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index % _values.size()]
		_index += 1
		return v


# ── Fixture helpers ────────────────────────────────────────────────────────────

func _dict_combatant(p_name: String, hp: int, ac: int) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 8,
		},
	}


func _make_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_dict_combatant("Scout", 50, 11), _dict_combatant("Mystic", 50, 11)],
		[_dict_combatant("Wraith", 65, 12)],
		RNGClass.new(seed_value)
	)


func _run_full_encounter(enc: EncounterClass) -> Dictionary:
	enc.initialize()
	var all_events: Array = []
	var rounds_run: int = 0
	var outcome: String = enc.get_outcome()

	while outcome == "" and rounds_run < MAX_ROUNDS_GUARD:
		var result: Dictionary = enc.run_round()
		all_events.append_array(enc.get_round_events())
		outcome = result.get("outcome", "")
		rounds_run += 1

	return {
		"outcome":    outcome,
		"rounds":     rounds_run,
		"all_events": all_events,
	}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — a full, defeat-spanning encounter completes within a bounded
# round count AND a bounded wall-clock time, with no hang.
# ══════════════════════════════════════════════════════════════════════════════

func test_full_encounter_with_a_defeat_completes_without_hanging() -> void:
	var enc = _make_encounter(31337)
	var started_at_ms: int = Time.get_ticks_msec()
	var run_data: Dictionary = _run_full_encounter(enc)
	var elapsed_ms: int = Time.get_ticks_msec() - started_at_ms

	assert_true(
		run_data["rounds"] < MAX_ROUNDS_GUARD,
		"Encounter must terminate well within the %d-round safety guard (no hang); ran %d rounds without a decided outcome"
		% [MAX_ROUNDS_GUARD, run_data["rounds"]]
	)
	assert_true(
		run_data["outcome"] == "won" or run_data["outcome"] == "lost",
		"Full encounter must terminate with outcome 'won' or 'lost'; got '%s'" % run_data["outcome"]
	)
	assert_true(
		elapsed_ms < MAX_ELAPSED_MS,
		"Full encounter must complete within %d ms (no hang); took %d ms" % [MAX_ELAPSED_MS, elapsed_ms]
	)

	var defeated_events: Array = run_data["all_events"].filter(
		func(e): return e is RoundEventsClass.CombatantDefeatedEvent
	)
	assert_true(
		defeated_events.size() > 0,
		"The uneven 2v1 fixture must produce at least one combatant_defeated event, proving the AD-1 kill path actually ran without hanging"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — every emitted round event is a well-formed, correctly-typed
# RoundEvents.* value object, readable via typed field access with no
# SCRIPT ERROR (never via `.get()` on a RefCounted object).
# ══════════════════════════════════════════════════════════════════════════════

func test_all_emitted_round_events_are_typed_value_objects_readable_without_script_error() -> void:
	var enc = _make_encounter(31337)
	var run_data: Dictionary = _run_full_encounter(enc)
	var all_events: Array = run_data["all_events"]

	assert_true(all_events.size() > 0, "Full encounter must emit at least one round event")

	var attack_count: int = 0
	var defeated_count: int = 0
	var result_count: int = 0

	for ev in all_events:
		if ev is RoundEventsClass.AttackBroadcast:
			attack_count += 1
			# Typed field access only — this is the exact style that avoids
			# the "Invalid call to function 'get' ... Expected 1 arguments"
			# SCRIPT ERROR a Dictionary-style `.get("key", default)` call
			# would raise on a RefCounted value object.
			assert_true(ev.attacker_name != "", "AttackBroadcast.attacker_name must be non-empty")
			assert_true(ev.target_name != "", "AttackBroadcast.target_name must be non-empty")
		elif ev is RoundEventsClass.CombatantDefeatedEvent:
			defeated_count += 1
			assert_true(ev.name != "", "CombatantDefeatedEvent.name must be non-empty")
			assert_true(ev.defeated_by != "", "CombatantDefeatedEvent.defeated_by must be non-empty")
			# AD-1's fix: a plain-Dictionary target with no "combatant_id"
			# key must default to "" — never raise, never be left unset.
			assert_eq(typeof(ev.combatant_id), TYPE_STRING, "CombatantDefeatedEvent.combatant_id must always be a String (possibly '')")
		elif ev is RoundEventsClass.EncounterResultEvent:
			result_count += 1
			assert_true(
				ev.outcome == "won" or ev.outcome == "lost" or ev.outcome == "draw",
				"EncounterResultEvent.outcome must be one of 'won'/'lost'/'draw'; got '%s'" % ev.outcome
			)
		else:
			fail_test("Unexpected round event type emitted: %s" % ev)

	assert_true(attack_count > 0, "At least one AttackBroadcast must be emitted across the full encounter")
	assert_true(defeated_count > 0, "At least one CombatantDefeatedEvent must be emitted (the uneven fixture guarantees a kill)")
	assert_eq(result_count, 1, "Exactly one terminal EncounterResultEvent must be emitted across the full encounter")

	# The terminal EncounterResultEvent must be strictly last.
	assert_true(
		all_events[all_events.size() - 1] is RoundEventsClass.EncounterResultEvent,
		"EncounterResultEvent must be the LAST event in the full encounter's concatenated event sequence"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — the public ResolveActionUseCase.resolve() entry point (not
# just the private _finalize_strike_result() helper) resolves a
# dict-combatant kill promptly, with a properly-typed CombatantDefeatedEvent
# and no SCRIPT ERROR — the exact call shape encounter.gd/simulator.gd use.
# ══════════════════════════════════════════════════════════════════════════════

func test_resolve_action_use_case_resolve_kills_a_dict_target_without_hanging_or_script_error() -> void:
	var rng_port   = ScriptedRandomNumberPort.new([20, 6])  # guaranteed crit hit + damage roll
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)

	var attacker = CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 5,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 3,
			"damage_die": 8,
		},
	})
	# Plain-Dictionary target with NO "combatant_id" key and hp low enough
	# that even a modest hit defeats it — the exact legacy shape that
	# crashed pre-AD-1.
	var target: Dictionary = {
		"name":       "Fragile",
		"hp_current": 1,
		"ac":         1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 4,
		},
	}
	var ae := ActionEconomyClass.new()
	ae.start_of_round()

	var started_at_ms: int = Time.get_ticks_msec()
	var result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)
	var elapsed_ms: int = Time.get_ticks_msec() - started_at_ms

	assert_true(elapsed_ms < MAX_ELAPSED_MS, "A single resolve() call must complete within %d ms (no hang)" % MAX_ELAPSED_MS)
	assert_true(result.get("resolved", false), "resolve() must report resolved:true for a successful spend")
	assert_true(result.get("target_defeated", false), "The low-hp Dictionary target must be reported as defeated")

	var defeated_events: Array = event_sink.events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "Exactly one CombatantDefeatedEvent must be emitted for the defeated Dictionary target")
	assert_eq(defeated_events[0].combatant_id, "", "A Dictionary target with no 'combatant_id' key must default to '' with no SCRIPT ERROR")
	assert_eq(defeated_events[0].name, "Fragile", "CombatantDefeatedEvent.name must be threaded through unchanged")
	assert_eq(defeated_events[0].defeated_by, "Attacker", "CombatantDefeatedEvent.defeated_by must be threaded through unchanged")
