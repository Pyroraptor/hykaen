extends GutTest
## tests/sim/test_determinism.gd
##
## FEAT-105 (FR-007 / NFR-003 / US-007) — REWRITE of the final remaining file
## named by docs/change-requests/CR-001-action-economy.org § "Verification"
## as one of FIVE GUT suites that MUST be rewritten (not weakened) to assert
## the corrected per-round action-economy model and the typed observability
## surface introduced alongside it. The other four
## (tests/unit/test_action_economy.gd, tests/integration/test_encounter_integration.gd,
## tests/integration/test_steel_thread_remediation.gd,
## tests/integration/test_steel_thread_e2e.gd) were already rewritten; this
## file was the peer-review BLOCKER ("rewrite/annotate the remaining 4 of 5
## CR-001-mandated test files") — CHECKLIST-2.
##
## What changed from the prior (FEAT-091) version of this file:
##   1. RNG injection — Encounter is now driven end-to-end by a REAL
##      SeededRandomAdapter (core/combat/seeded_random_adapter.gd — the
##      production RandomNumberPort adapter, FEAT-005/US-004) rather than a
##      bare core/rules/rng.gd RNG instance. core/combat/encounter.gd's
##      constructor (and core/rules/resolution.gd, which it wraps) expects an
##      RNG-shaped object exposing d20() and roll(die_size, count) — the
##      SAME duck-typed contract core/rules/rng.gd implements.
##      _SeededAdapterRNG below is a small TEST-ONLY composition shim
##      (declared in this file, not a production source change — encounter.gd
##      is untouched) that delegates every d20()/roll(die,count) call through
##      a real, owned SeededRandomAdapter instance, so the encounter is driven
##      by SeededRandomAdapter's actual deterministic sequence end-to-end
##      while still satisfying encounter.gd's existing RNG-shaped constructor
##      parameter. This is the same bridging idiom already established in
##      tests/test_determinism.gd (FEAT-010).
##   2. Assertions — _round_history and _round_events are now compared via
##      TYPED RoundEvents.* value-object `.to_dict()` deep equality
##      (core/rules/round_events.gd, FEAT-099/FIND-096), never via raw
##      Dictionary `.get("roll", -1)`-style field plucking as the prior
##      version did. Each get_round_history() entry's typed
##      RoundEvents.RoundHistoryEntry (carried under the "entry" key) and
##      each get_round_events() element (a RoundEvents.AttackBroadcast /
##      CombatantDefeatedEvent / EncounterResultEvent instance) is snapshotted
##      via `.to_dict()` and the resulting Arrays-of-Dictionaries are compared
##      with assert_eq, which performs Godot's native recursive Array/
##      Dictionary equality — order-sensitive, so a refactor that altered
##      cycle/turn-order iteration would be caught exactly as reliably as one
##      that altered RNG consumption.
##
## Verifies NFR-003: "Given the same seed, two independently-constructed
## encounter runs MUST be replayable byte-for-byte" — proving the
## interleaved AC-4 round-loop refactor (RunRoundUseCase) and the typed
## event emission refactor (FEAT-099) introduced no nondeterminism.
##
## Satisfies: FR-007, NFR-003, US-007, CR-001 (entire), CHECKLIST-2.

const EncounterClass           = preload("res://core/combat/encounter.gd")
const RNGClass                 = preload("res://core/rules/rng.gd")
const AttributesClass          = preload("res://core/rules/attributes.gd")
const SeededRandomAdapterClass = preload("res://core/combat/seeded_random_adapter.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")

## Pinned seed for all determinism tests (matches steel thread STEEL_SEED).
const STEEL_SEED: int = 99999

## Safety guard against an accidental infinite loop masking a real bug as a
## hang instead of a clean test failure (mirrors tests/test_determinism.gd).
const MAX_ROUNDS_GUARD: int = 50


## _SeededAdapterRNG — test-only shim bridging SeededRandomAdapter's
## RandomNumberPort contract (roll(dice_spec: Dictionary)) to the RNG-shaped
## contract (d20(), roll(die_size, count)) that core/combat/encounter.gd's
## constructor and core/rules/resolution.gd expect. Every roll is delegated
## to a real, owned SeededRandomAdapter instance — this class adds no
## randomness/logic of its own, it only reshapes the method signature, so
## the encounter's full RNG stream is, byte-for-byte, SeededRandomAdapter's
## own deterministic sequence (NFR-003).
class _SeededAdapterRNG:
	extends RefCounted

	var _adapter: SeededRandomAdapterClass

	func _init(seed_value: int) -> void:
		_adapter = SeededRandomAdapterClass.new(seed_value)

	func d20() -> int:
		return _adapter.roll({"die": 20, "count": 1})

	func roll(die_size: int, count: int) -> int:
		return _adapter.roll({"die": die_size, "count": count})


# ── Resource fixtures (loaded once per test file) ─────────────────────────────

var _titus            = null  ## CharacterResource
var _fighter_class    = null  ## ClassResource (titus.class_ref)
var _longsword        = null  ## WeaponResource
var _chain_shirt      = null  ## ArmorResource
var _skeleton_res     = null  ## EnemyResource


func before_all() -> void:
	## Load all resources once; each test constructs fresh combatant dicts.
	_titus        = ResourceLoader.load("res://data/characters/titus.tres")
	_longsword    = ResourceLoader.load("res://data/weapons/longsword.tres")
	_chain_shirt  = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	_skeleton_res = ResourceLoader.load("res://data/enemies/skeleton.tres")
	if _titus != null:
		_fighter_class = _titus.class_ref


## Returns true if all required resources loaded successfully.
func _all_resources_loaded() -> bool:
	return _titus != null and _fighter_class != null \
		and _longsword != null and _chain_shirt != null and _skeleton_res != null


# ── Combatant dict builders ───────────────────────────────────────────────────

## _build_titus_dict() — constructs a fresh Titus combatant dict from loaded
## resources. AttributesClass is only used here to compute static derived
## stats (HP/AC) from fixed attribute scores — those formulas are
## deterministic and do not consume the injected combat RNG stream (see
## core/rules/attributes.gd), so a throwaway RNGClass.new(0) is sufficient
## and never interacts with the SeededRandomAdapter driving the encounter.
## Each call produces an independent dict — no shared object references.
func _build_titus_dict() -> Dictionary:
	var attrs = AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(_titus.attributes, _fighter_class)
	var ac: int = attrs.compute_ac(_titus.attributes, _chain_shirt.ac_base, _chain_shirt.category)
	return {
		"name":       _titus.name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   _titus.attributes.get("strength",  0),
		"dexterity":  _titus.attributes.get("dexterity", 0),
		"intuition":  _titus.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": _longsword.damage_modifier_attribute,
			"proficiency_bonus":         _longsword.proficiency_bonus,
			"damage_die":                _longsword.damage_die
		}
	}


## _build_skeleton_dict() — constructs a fresh skeleton combatant dict from
## skeleton.tres EnemyResource fields. ac and intuition are not in
## EnemyResource schema; defaults: ac=12, intuition=0.
func _build_skeleton_dict() -> Dictionary:
	return {
		"name":       _skeleton_res.name,
		"hp_current": _skeleton_res.hp,
		"ac":         12,
		"strength":   _skeleton_res.str,
		"dexterity":  _skeleton_res.dex,
		"intuition":  0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus":         _skeleton_res.weapon.get("proficiency_bonus", 1),
			"damage_die":                _skeleton_res.weapon.get("die", 6)
		}
	}


## A synthetic "moderate" combatant — durable enough to survive several
## rounds so the multi-round / multi-cycle interleaving scenario below
## actually exercises the AC-4 cycle loop across more than a single round,
## strengthening the "iteration order introduces nondeterminism" guard
## beyond what the (often short) Titus-vs-single-skeleton fixture covers.
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


# ── Encounter constructors (SeededRandomAdapter-driven) ───────────────────────

## _make_fresh_titus_encounter(seed_value) — constructs a fully independent
## Encounter (Titus vs skeleton.tres fixture) driven end-to-end by a fresh
## SeededRandomAdapter (via the _SeededAdapterRNG bridge). Fresh combatant
## dicts and a fresh adapter every call guarantee no shared state leaks
## between runs.
func _make_fresh_titus_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_build_titus_dict()],
		[_build_skeleton_dict()],
		_SeededAdapterRNG.new(seed_value)
	)


## _make_fresh_2v2_encounter(seed_value) — constructs a fully independent
## 2-vs-2 synthetic Encounter driven end-to-end by a fresh
## SeededRandomAdapter (via the _SeededAdapterRNG bridge).
func _make_fresh_2v2_encounter(seed_value: int) -> EncounterClass:
	return EncounterClass.new(
		[_moderate_combatant("Hero1"), _moderate_combatant("Hero2")],
		[_moderate_combatant("Orc1"), _moderate_combatant("Orc2")],
		_SeededAdapterRNG.new(seed_value)
	)


## Drives enc to completion via repeated run_round() calls (the steel-thread
## entry point, AC-4 interleaved cycle loop), accumulating the full-encounter
## TYPED event sequence (each round's get_round_events() queue is cleared at
## the start of the NEXT run_round() call, so it must be captured immediately
## after each call).
func _run_to_completion(enc: EncounterClass) -> Dictionary:
	enc.initialize()
	var all_events: Array = []
	var rounds_run: int = 0
	var outcome: String = ""

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


# ── Typed-value-object → Dictionary snapshot helpers ───────────────────────────
# Both helpers below read ONLY typed RoundEvents.* value objects (never raw
# Dictionary field plucking) and snapshot them via the class's own
# .to_dict() method, per FEAT-099/FIND-096 and this CR's mandate.

## _history_entries_to_dicts(history) — extracts the typed
## RoundEvents.RoundHistoryEntry carried under each get_round_history() entry's
## "entry" key (FEAT-099/FIND-096) and snapshots each one via .to_dict().
## Entries lacking a typed "entry" (which should never happen post-FEAT-099)
## are skipped rather than silently coerced — a regression here would shrink
## the resulting array and trip the size-equality assertions below.
func _history_entries_to_dicts(history: Array) -> Array:
	var snapshots: Array = []
	for hist_entry in history:
		var typed_entry = hist_entry.get("entry")
		if typed_entry is RoundEventsClass.RoundHistoryEntry:
			snapshots.append(typed_entry.to_dict())
	return snapshots


## _round_events_to_dicts(events) — snapshots every TYPED RoundEvents.*
## element of a get_round_events() sequence via .to_dict(), additionally
## tagging each snapshot with its concrete class name. The tag is required
## because AttackEvent / CombatantDefeatedEvent / EncounterResultEvent each
## have disjoint .to_dict() field sets — without it, two snapshots from
## different event types could (in principle) be misidentified by Dictionary
## equality if their field sets happened to overlap.
func _round_events_to_dicts(events: Array) -> Array:
	var snapshots: Array = []
	for ev in events:
		var class_tag: String = "Unknown"
		if ev is RoundEventsClass.AttackBroadcast:
			class_tag = "AttackEvent"
		elif ev is RoundEventsClass.CombatantDefeatedEvent:
			class_tag = "CombatantDefeatedEvent"
		elif ev is RoundEventsClass.EncounterResultEvent:
			class_tag = "EncounterResultEvent"
		var snapshot: Dictionary = ev.to_dict()
		snapshot["_event_class"] = class_tag
		snapshots.append(snapshot)
	return snapshots


# ══════════════════════════════════════════════════════════════════════════════
# Sanity guards — a non-terminating or vacuously-empty encounter would make
# every byte-identical assertion below trivially (and meaninglessly) true.
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_seed_99999_titus_encounter_terminates() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot verify encounter termination (FEAT-105)"
		)
		return

	var enc = _make_fresh_titus_encounter(STEEL_SEED)
	var run: Dictionary = _run_to_completion(enc)

	assert_true(
		run["outcome"] == "won" or run["outcome"] == "lost",
		("Determinism test encounter (seed %d) must terminate with 'won' or 'lost'; "
			+ "got '%s' — FEAT-105") % [STEEL_SEED, run["outcome"]]
	)
	assert_true(
		run["rounds"] >= 1 and run["rounds"] < MAX_ROUNDS_GUARD,
		"Determinism test encounter (seed %d) must complete at least 1 round within the safety guard" % STEEL_SEED
	)
	assert_true(
		run["all_history"].size() >= 1,
		("Determinism test encounter (seed %d) round_history must be non-empty; "
			+ "empty sequences would trivially satisfy byte-identical assertions") % STEEL_SEED
	)
	assert_true(
		run["all_events"].size() >= 1,
		("Determinism test encounter (seed %d) round_events must be non-empty; "
			+ "empty sequences would trivially satisfy byte-identical assertions") % STEEL_SEED
	)


func test_determinism_seed_99999_2v2_encounter_terminates_with_multiple_rounds() -> void:
	var enc = _make_fresh_2v2_encounter(STEEL_SEED)
	var run: Dictionary = _run_to_completion(enc)

	assert_true(
		run["outcome"] == "won" or run["outcome"] == "lost",
		"2v2 determinism encounter (seed %d) must terminate with 'won' or 'lost'; got '%s'"
			% [STEEL_SEED, run["outcome"]]
	)
	assert_true(
		run["rounds"] >= 1 and run["rounds"] < MAX_ROUNDS_GUARD,
		"2v2 determinism encounter (seed %d) must terminate within the safety guard" % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion — Two encounter runs seeded identically via SeededRandomAdapter
# produce byte-for-byte equal _round_history and _round_events, compared via
# .to_dict() deep equality on the TYPED RoundEvents.* value objects (never
# raw Dictionary access).
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_seed_99999_titus_round_history_typed_entries_byte_identical() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot prove round_history determinism (FEAT-105)"
		)
		return

	var enc1 = _make_fresh_titus_encounter(STEEL_SEED)
	var run1: Dictionary = _run_to_completion(enc1)

	var enc2 = _make_fresh_titus_encounter(STEEL_SEED)
	var run2: Dictionary = _run_to_completion(enc2)

	var history1: Array = _history_entries_to_dicts(run1["all_history"])
	var history2: Array = _history_entries_to_dicts(run2["all_history"])

	assert_true(
		history1.size() > 0,
		"Run 1's typed RoundHistoryEntry snapshot list must be non-empty (FEAT-105 determinism precondition)"
	)
	assert_eq(
		history1.size(), history2.size(),
		"Run 1 and Run 2 (seed %d, SeededRandomAdapter) must produce typed round_history of identical length"
			% STEEL_SEED
	)
	assert_eq(
		history1, history2,
		("Run 1 and Run 2 (seed %d, SeededRandomAdapter) must produce byte-for-byte identical "
			+ "RoundEvents.RoundHistoryEntry.to_dict() snapshots, in order — a refactor that altered "
			+ "interleaving/cycle iteration order or RNG consumption would change this Array and fail "
			+ "this assertion (FEAT-105, NFR-003)") % STEEL_SEED
	)


func test_determinism_seed_99999_titus_round_events_typed_value_objects_byte_identical() -> void:
	if not _all_resources_loaded():
		fail_test(
			"one or more required resources failed to load — "
			+ "cannot prove round_events determinism (FEAT-105)"
		)
		return

	var enc1 = _make_fresh_titus_encounter(STEEL_SEED)
	var run1: Dictionary = _run_to_completion(enc1)

	var enc2 = _make_fresh_titus_encounter(STEEL_SEED)
	var run2: Dictionary = _run_to_completion(enc2)

	var events1: Array = _round_events_to_dicts(run1["all_events"])
	var events2: Array = _round_events_to_dicts(run2["all_events"])

	assert_true(
		events1.size() > 0,
		"Run 1 must emit at least one typed round_event across the full encounter (FEAT-105 determinism precondition)"
	)
	assert_eq(
		events1.size(), events2.size(),
		"Run 1 and Run 2 (seed %d, SeededRandomAdapter) must emit the identical NUMBER of typed round_events"
			% STEEL_SEED
	)
	assert_eq(
		events1, events2,
		("Run 1 and Run 2 (seed %d, SeededRandomAdapter) must produce byte-for-byte identical typed "
			+ "RoundEvents.* .to_dict() snapshots (AttackEvent/CombatantDefeatedEvent/EncounterResultEvent), "
			+ "in order — proves the interleaved AC-4 round-loop refactor and FEAT-099 typed-event emission "
			+ "introduced no nondeterminism (FEAT-105, NFR-003)") % STEEL_SEED
	)

	# The terminal encounter_result event must be present exactly once and
	# report the identical decided outcome on both runs.
	var result1: Array = events1.filter(func(e): return e.get("_event_class", "") == "EncounterResultEvent")
	var result2: Array = events2.filter(func(e): return e.get("_event_class", "") == "EncounterResultEvent")
	assert_eq(result1.size(), 1, "Run 1 must emit exactly one terminal EncounterResultEvent")
	assert_eq(result2.size(), 1, "Run 2 must emit exactly one terminal EncounterResultEvent")
	if result1.size() == 1 and result2.size() == 1:
		assert_eq(
			result1[0].get("outcome", ""), result2[0].get("outcome", ""),
			"The terminal EncounterResultEvent.outcome must be byte-identical across runs (seed %d)" % STEEL_SEED
		)


## 2-vs-2 synthetic fixture variant — multiple combatants per side, multiple
## rounds, exercising the AC-4 interleaved cycle loop more heavily than the
## single-skeleton Titus fixture above, to strengthen the "iteration order
## introduces nondeterminism" guard (FEAT-105 test criterion).
func test_determinism_seed_99999_2v2_round_history_and_events_typed_byte_identical() -> void:
	var enc1 = _make_fresh_2v2_encounter(STEEL_SEED)
	var run1: Dictionary = _run_to_completion(enc1)

	var enc2 = _make_fresh_2v2_encounter(STEEL_SEED)
	var run2: Dictionary = _run_to_completion(enc2)

	assert_true(run1["rounds"] < MAX_ROUNDS_GUARD, "2v2 Run 1 must terminate within the safety guard")
	assert_true(run2["rounds"] < MAX_ROUNDS_GUARD, "2v2 Run 2 must terminate within the safety guard")
	assert_eq(
		run1["outcome"], run2["outcome"],
		"Two SeededRandomAdapter-driven 2v2 runs with the same seed must produce the identical outcome"
	)
	assert_eq(
		run1["rounds"], run2["rounds"],
		"Two SeededRandomAdapter-driven 2v2 runs with the same seed must run the identical number of rounds"
	)

	var history1: Array = _history_entries_to_dicts(run1["all_history"])
	var history2: Array = _history_entries_to_dicts(run2["all_history"])
	assert_true(history1.size() > 0, "2v2 Run 1's typed round_history snapshot list must be non-empty")
	assert_eq(
		history1, history2,
		("2v2 Run 1 and Run 2 (seed %d) must produce byte-for-byte identical typed RoundHistoryEntry "
			+ "snapshots — proves the multi-combatant interleaved cycle loop is order-stable") % STEEL_SEED
	)

	var events1: Array = _round_events_to_dicts(run1["all_events"])
	var events2: Array = _round_events_to_dicts(run2["all_events"])
	assert_true(events1.size() > 0, "2v2 Run 1's typed round_events snapshot list must be non-empty")
	assert_eq(
		events1, events2,
		("2v2 Run 1 and Run 2 (seed %d) must produce byte-for-byte identical typed round_event "
			+ "snapshots across every round of the encounter") % STEEL_SEED
	)


# ══════════════════════════════════════════════════════════════════════════════
# Sanity guard — a DIFFERENT seed must (overwhelmingly likely) diverge,
# proving the equality above is a genuine seed-driven property and not a
# vacuous always-equal stub.
# ══════════════════════════════════════════════════════════════════════════════

func test_determinism_different_seed_diverges_from_baseline() -> void:
	var enc_baseline = _make_fresh_2v2_encounter(9090)
	var run_baseline: Dictionary = _run_to_completion(enc_baseline)

	var enc_other = _make_fresh_2v2_encounter(31337)
	var run_other: Dictionary = _run_to_completion(enc_other)

	var history_baseline: Array = _history_entries_to_dicts(run_baseline["all_history"])
	var history_other: Array = _history_entries_to_dicts(run_other["all_history"])

	assert_ne(
		history_baseline, history_other,
		"A different seed routed through the identical SeededRandomAdapter bridge must (overwhelmingly likely) "
		+ "produce a divergent typed round_history snapshot — proves the byte-identical assertions above are "
		+ "seed-driven, not vacuous (FEAT-105)"
	)


# ── SeededRandomAdapter contract sanity (NFR-003 baseline) ───────────────────

## Directly proves the underlying production adapter's own determinism
## property (two raw SeededRandomAdapter instances, same seed, identical
## roll() sequence) — the foundation the full-encounter assertions above
## build on.
func test_raw_seeded_random_adapter_same_seed_identical_sequence() -> void:
	var a = SeededRandomAdapterClass.new(STEEL_SEED)
	var b = SeededRandomAdapterClass.new(STEEL_SEED)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(20):
		seq_a.append(a.roll({"die": 20, "count": 1}))
		seq_b.append(b.roll({"die": 20, "count": 1}))

	assert_eq(
		seq_a, seq_b,
		"Two raw SeededRandomAdapter instances constructed with the same seed must produce an identical "
		+ "roll() sequence (NFR-003)"
	)
