extends GutTest
## tests/test_determinism.gd
##
## FEAT-010 (NFR-003, US-008): Determinism regression test for the steel
## thread. Confirms that _round_history and _round_events produced by a
## FULL multi-round Encounter (driven via repeated Encounter.run_round()
## calls, the steel-thread entry point) are byte-identical across two
## independently constructed runs that share the same seed, routed through
## the production SeededRandomAdapter (core/combat/seeded_random_adapter.gd
## — FEAT-005 / US-004) rather than a bare RNG instance.
##
## core/combat/encounter.gd's constructor (and core/rules/resolution.gd,
## which it wraps) expects an RNG-shaped object exposing d20() and
## roll(die_size, count) — the SAME duck-typed contract core/rules/rng.gd
## implements. SeededRandomAdapter instead implements the RandomNumberPort
## contract (roll(dice_spec: Dictionary)) used by the application-layer
## ports described in the FEAT-010 design notes. _SeededAdapterRNG below is
## a small TEST-ONLY composition shim — declared inside this test file, not
## a production source change — that delegates every d20()/roll(die,count)
## call through a real SeededRandomAdapter instance, so the encounter is
## driven by SeededRandomAdapter's actual deterministic sequence end-to-end
## while still satisfying encounter.gd's existing RNG-shaped constructor
## parameter (no edits to encounter.gd are needed or made).
##
## Test criteria covered:
##   1. Two full multi-round encounters, constructed completely
##      independently (fresh SeededRandomAdapter, fresh Encounter) but with
##      the IDENTICAL seed, produce byte-identical get_round_history()
##      sequences (every field, every entry, across every round).
##   2. The same pair of runs produce byte-identical CONCATENATED
##      get_round_events() sequences across every round of the encounter
##      (not just the first round).
##   3. A third run with a DIFFERENT seed is shown to (overwhelmingly
##      likely) diverge — demonstrating the equality above is a genuine
##      seed-driven determinism property, not a vacuous always-equal stub.
##
## Satisfies: NFR-003, US-008, CR-001 AC-4/AC-5

const EncounterClass           = preload("res://core/combat/encounter.gd")
const SeededRandomAdapterClass = preload("res://core/combat/seeded_random_adapter.gd")

const MAX_ROUNDS_GUARD: int = 50


## _SeededAdapterRNG — test-only shim bridging SeededRandomAdapter's
## RandomNumberPort contract (roll(dice_spec: Dictionary)) to the
## RNG-shaped contract (d20(), roll(die_size, count)) that
## core/combat/encounter.gd's constructor and core/rules/resolution.gd
## expect. Every roll is delegated to a real, owned SeededRandomAdapter
## instance — this class adds no randomness/logic of its own, it only
## reshapes the method signature.
class _SeededAdapterRNG:
	extends RefCounted

	var _adapter: SeededRandomAdapterClass

	func _init(seed_value: int) -> void:
		_adapter = SeededRandomAdapterClass.new(seed_value)

	func d20() -> int:
		return _adapter.roll({"die": 20, "count": 1})

	func roll(die_size: int, count: int) -> int:
		return _adapter.roll({"die": die_size, "count": count})


# ── Fixture helpers ────────────────────────────────────────────────────────────

func _moderate_combatant(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 60,
		"ac":         11,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## Builds a fully independent 2-vs-2 Encounter, driven end-to-end by a
## fresh SeededRandomAdapter (via the _SeededAdapterRNG bridge) seeded with
## seed_value. Fresh combatant dicts and a fresh adapter every call
## guarantee no shared state leaks between runs.
func _make_2v2_encounter_via_seeded_adapter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_moderate_combatant("Hero1"), _moderate_combatant("Hero2")],
		[_moderate_combatant("Orc1"), _moderate_combatant("Orc2")],
		_SeededAdapterRNG.new(seed_value)
	)


## Drives enc to completion via repeated run_round() calls (the steel-thread
## entry point), accumulating the full-encounter event sequence (each
## round's get_round_events() queue is cleared at the start of the NEXT
## run_round() call, so it must be captured immediately after each call).
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
		"outcome":     outcome,
		"rounds":      rounds_run,
		"all_events":  all_events,
		"all_history": enc.get_round_history()
	}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 — byte-identical get_round_history() across two independent
# runs sharing the same seed, routed through SeededRandomAdapter.
# ══════════════════════════════════════════════════════════════════════════════

func test_seeded_adapter_two_runs_identical_round_history() -> void:
	var enc1 = _make_2v2_encounter_via_seeded_adapter(9090)
	var run1: Dictionary = _run_full_encounter(enc1)

	var enc2 = _make_2v2_encounter_via_seeded_adapter(9090)
	var run2: Dictionary = _run_full_encounter(enc2)

	assert_true(run1["rounds"] < MAX_ROUNDS_GUARD, "Run 1 must terminate within the safety guard")
	assert_true(run2["rounds"] < MAX_ROUNDS_GUARD, "Run 2 must terminate within the safety guard")

	assert_eq(
		run1["outcome"], run2["outcome"],
		"Two SeededRandomAdapter-driven runs with the same seed must produce the identical outcome"
	)
	assert_eq(
		run1["rounds"], run2["rounds"],
		"Two SeededRandomAdapter-driven runs with the same seed must run the identical number of rounds"
	)

	var history1: Array = run1["all_history"]
	var history2: Array = run2["all_history"]
	assert_eq(
		history1.size(), history2.size(),
		"Two SeededRandomAdapter-driven runs with the same seed must produce round_history of identical length"
	)

	var count: int = mini(history1.size(), history2.size())
	for i in range(count):
		var e1: Dictionary = history1[i]
		var e2: Dictionary = history2[i]
		assert_eq(
			e1.get("attacker", {}).get("name", ""), e2.get("attacker", {}).get("name", ""),
			"round_history[%d].attacker.name must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("target", {}).get("name", ""), e2.get("target", {}).get("name", ""),
			"round_history[%d].target.name must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("action", ""), e2.get("action", ""),
			"round_history[%d].action must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("roll", -1), e2.get("roll", -1),
			"round_history[%d].roll must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("damage_final", -1), e2.get("damage_final", -1),
			"round_history[%d].damage_final must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("budget_remaining", -1), e2.get("budget_remaining", -1),
			"round_history[%d].budget_remaining must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("round", -1), e2.get("round", -1),
			"round_history[%d].round must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			e1.get("cycle_index", -1), e2.get("cycle_index", -1),
			"round_history[%d].cycle_index must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2 — byte-identical CONCATENATED get_round_events() across every
# round of the encounter, for two independent runs sharing the same seed.
# ══════════════════════════════════════════════════════════════════════════════

func test_seeded_adapter_two_runs_identical_round_events_full_encounter() -> void:
	var enc1 = _make_2v2_encounter_via_seeded_adapter(9090)
	var run1: Dictionary = _run_full_encounter(enc1)

	var enc2 = _make_2v2_encounter_via_seeded_adapter(9090)
	var run2: Dictionary = _run_full_encounter(enc2)

	var events1: Array = run1["all_events"]
	var events2: Array = run2["all_events"]

	assert_true(events1.size() > 0, "Run 1 must emit at least one round event across the full encounter")
	assert_eq(
		events1.size(), events2.size(),
		"Two SeededRandomAdapter-driven runs with the same seed must emit the identical NUMBER of events "
		+ "across the full (multi-round) encounter"
	)

	var count: int = mini(events1.size(), events2.size())
	for i in range(count):
		var ev1: Dictionary = events1[i]
		var ev2: Dictionary = events2[i]
		assert_eq(
			ev1.get("type", ""), ev2.get("type", ""),
			"round_events[%d].type must be byte-identical across runs (same seed via SeededRandomAdapter)" % i
		)
		assert_eq(
			ev1, ev2,
			"round_events[%d] must be a byte-identical Dictionary across runs (same seed via SeededRandomAdapter); "
			% i + "run1=%s run2=%s" % [str(ev1), str(ev2)]
		)

	# The terminal encounter_result event (present exactly once, per the
	# steel-thread exit contract) must report the identical outcome on both
	# runs — the determinism guarantee extends all the way to the
	# encounter's final decided result, not merely its intermediate state.
	var result_events1: Array = events1.filter(func(e): return e.get("type", "") == "encounter_result")
	var result_events2: Array = events2.filter(func(e): return e.get("type", "") == "encounter_result")
	assert_eq(result_events1.size(), 1, "Run 1 must emit exactly one terminal encounter_result event")
	assert_eq(result_events2.size(), 1, "Run 2 must emit exactly one terminal encounter_result event")
	if result_events1.size() == 1 and result_events2.size() == 1:
		assert_eq(
			result_events1[0].get("outcome", ""), result_events2[0].get("outcome", ""),
			"The terminal encounter_result outcome must be byte-identical across runs (same seed via SeededRandomAdapter)"
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 — sanity guard: a DIFFERENT seed (overwhelmingly likely)
# diverges, proving the equality above is a genuine seed-driven property.
# ══════════════════════════════════════════════════════════════════════════════

func test_seeded_adapter_different_seed_diverges_from_baseline() -> void:
	var enc_baseline = _make_2v2_encounter_via_seeded_adapter(9090)
	var run_baseline: Dictionary = _run_full_encounter(enc_baseline)

	var enc_other = _make_2v2_encounter_via_seeded_adapter(31337)
	var run_other: Dictionary = _run_full_encounter(enc_other)

	var rolls_baseline: Array = []
	for entry in run_baseline["all_history"]:
		rolls_baseline.append(entry.get("roll", -1))

	var rolls_other: Array = []
	for entry in run_other["all_history"]:
		rolls_other.append(entry.get("roll", -1))

	assert_ne(
		rolls_baseline, rolls_other,
		"A different seed routed through the identical SeededRandomAdapter bridge must (overwhelmingly likely) "
		+ "produce a divergent roll sequence — proves the byte-identical assertions above are seed-driven, not vacuous"
	)


# ── SeededRandomAdapter contract sanity (NFR-003 baseline) ───────────────────

## Directly proves the underlying production adapter's own determinism
## property (two raw SeededRandomAdapter instances, same seed, identical
## roll() sequence) — the foundation the full-encounter assertions above
## build on.
func test_raw_seeded_random_adapter_same_seed_identical_sequence() -> void:
	var a = SeededRandomAdapterClass.new(2024)
	var b = SeededRandomAdapterClass.new(2024)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(20):
		seq_a.append(a.roll({"die": 20, "count": 1}))
		seq_b.append(b.roll({"die": 20, "count": 1}))

	assert_eq(
		seq_a, seq_b,
		"Two raw SeededRandomAdapter instances constructed with the same seed must produce an identical roll() sequence (NFR-003)"
	)
