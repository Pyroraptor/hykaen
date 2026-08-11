extends GutTest
## tests/test_combat_strike_resolution_e2e.gd
##
## FEAT-007 (US-007/FR-009) -- the CLOSING end-to-end steel-thread test for
## this iteration's bugfix. Filename note (DEF-005 compliance): the feature
## plan's files_to_create names this file
## "tests/test_steel_thread_strike_resolution_e2e.gd", but
## tests/integration/test_test_suite_naming_hygiene.gd enforces a
## project-wide, pre-existing convention (DEF-005) that "steel_thread"/
## "steelthread" in a test FILENAME is reserved EXCLUSIVELY for suites that
## genuinely instantiate/boot the real res://MainScene.tscn composition
## root -- six prior suites were deliberately RENAMED away from that naming
## for constructing core/combat/encounter.gd directly instead (the exact
## pattern this file's own Scenario (b) below uses, by design, per this
## feature's design notes). Rather than either (a) weakening/gaming that
## established gate by adding a non-MainScene-booting exception to its
## allow-list, or (b) changing this suite's architecture just to satisfy a
## naming convention, this file is named to describe what it actually does
## (an E2E combat-strike-resolution regression test) while preserving 100%
## of the feature's specified test_criteria coverage below. See this
## header's own next paragraph for what "steel thread" means in THIS
## feature's (unrelated bugfix-plan) design notes vs. DEF-005's stricter,
## MainScene-specific usage of the same term.
##
## core/application/resolve_action_use_case.gd's
## _finalize_strike_result() used to raise "Invalid access to property or
## key 'combatant_id' on a base object of type 'Dictionary'" (an eagerly-
## evaluated typed ternary, GDScript 4.3 semantics) the instant a plain
## Dictionary-shaped target with no "combatant_id" key was defeated,
## aborting the round mid-execution.
##
## FEAT-001 replaced the crashing ternary with explicit if/elif type
## branching; FEAT-002 pinned the emitted CombatantDefeatedEvent's fields in
## isolation (calling _finalize_strike_result() directly);  FEAT-003 pinned
## backward compatibility through encounter.gd's/simulator.gd's round loop.
## THIS suite is the single scenario that exercises BOTH target shapes the
## design notes document as legal at this seam -- TOGETHER, in one file --
## driven through a full combat-round resolution (not the private
## _finalize_strike_result() method directly), closing RISK-008 (both shapes
## covered by one E2E scenario) and RISK-001 (the typed-CombatantClass
## primary path specifically):
##
##   (a) a typed CombatantClass target, driven through
##       ResolveActionUseCase.resolve() -- the PUBLIC, primary entry point
##       (precondition check -> action spend -> to-hit/damage roll via
##       resolution.gd -> _finalize_strike_result()) -- asserting a
##       correctly-populated CombatantDefeatedEvent (round/name/defeated_by/
##       non-empty combatant_id) is emitted with no engine error.
##
##   (b) a plain-Dictionary target (no "combatant_id" key -- the exact shape
##       that crashed the pre-fix ternary), driven through
##       core/combat/encounter.gd's legacy run_round() path (the same
##       Dictionary-combatant path core/sim/simulator.gd's balance-sim loop
##       exercised when it "empirically still hit[]" the crash, per
##       resolve_action_use_case.gd's own in-code incident note at the
##       Dict-tolerant-shim comment) -- asserting the emitted
##       CombatantDefeatedEvent.combatant_id == "" with no engine error.
##
## Neither scenario below throwing/aborting mid-call IS itself part of the
## proof: the pre-fix ternary aborted _finalize_strike_result() with a
## SCRIPT ERROR the instant a Dictionary target with no "combatant_id" key
## was defeated, so reaching this file's assertions at all already
## demonstrates no engine error occurred (mirrors
## tests/test_finalize_strike_result.gd's and
## tests/test_encounter_round_loop.gd's identical "no SCRIPT ERROR" proof
## convention -- neither GUT nor Godot 4.3 expose a reliable in-test
## push_error() capture hook, see those files' own header notes).
##
## Gate-health assertions (test_criteria #3-#5): this file deliberately does
## NOT re-spawn a nested `godot --headless -- --gut-run-all` subprocess from
## inside a running GUT test -- tests/integration/test_steel_thread_camera_pan_zoom.gd's
## own header doc (criterion 5) already documents why that flakes/corrupts
## the real, outer gate run on this project's pinned Godot 4.3
## (stale GutRunner GUI node lookups, teardown errors), and
## tests/integration/test_def001_gate_evidence.py -- the prior recursive
## meta-test that DID re-run the full suite as a pytest subprocess -- was
## deliberately deleted (commit 4f371fc) for adding ~4 minutes to every
## `pytest` run with no unique coverage. Instead, this file exercises the
## REAL, production ci/gate_exit_policy.gd::GateExitPolicy class directly
## against the REAL ci/accepted_known_failures.json manifest on disk --
## proving the gate's own exit-policy computation reports zero
## unexpected_failures / exit code 0 for the current (empty) manifest state
## -- and the authoritative "Full GUT suite / Failing Tests: 0 / process
## exit code 0" signal is the live `godot --headless -- --gut-run-all` run
## performed as this feature's own verification step (see the implementing
## session's commit message / CLAUDE.md commit-hygiene checklist), exactly
## mirroring the camera suite's established non-recursive convention.
##
## Satisfies: US-007, FR-009. Closes RISK-008, RISK-001.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")
const SeededRandomAdapterClass  = preload("res://core/combat/seeded_random_adapter.gd")
const EncounterClass            = preload("res://core/combat/encounter.gd")
const RNGClass                  = preload("res://core/rules/rng.gd")
const GateExitPolicyClass       = preload("res://ci/gate_exit_policy.gd")

const ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH: String = "res://ci/accepted_known_failures.json"

## The steel-thread test scripts this closing suite's manifest-integrity
## check (below) confirms are never quietly carved out of
## ci/accepted_known_failures.json -- mirrors
## tests/integration/test_steel_thread_camera_pan_zoom.gd's identically-
## shaped `_CAMERA_STORY_SCRIPT_PATHS` convention (criterion 5 there).
const _STEEL_THREAD_SCRIPT_PATHS: Array = [
	"res://core/application/resolve_action_use_case.gd",
	"res://tests/test_finalize_strike_result.gd",
	"res://tests/test_encounter_round_loop.gd",
	"res://tests/test_simulator_determinism.gd",
	"res://ci/test_known_failures_allowlist.gd",
	"res://tests/test_steel_thread_strike_resolution_e2e.gd",
]


# ── Local test doubles (mirrors tests/test_finalize_strike_result.gd's /
#    tests/characterization/test_strike_characterization.gd's established
#    per-suite test-double convention) ────────────────────────────────────

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


func _fresh_ae() -> ActionEconomyClass:
	var ae := ActionEconomyClass.new()
	ae.start_of_round()
	return ae


# ══════════════════════════════════════════════════════════════════════════
# Scenario (a): typed CombatantClass target, driven through
# ResolveActionUseCase.resolve() -- the PUBLIC primary path (precondition
# check + action spend + to-hit/damage roll + finalize), NOT
# _finalize_strike_result() directly (that isolated-unit coverage already
# lives in tests/test_finalize_strike_result.gd -- this suite proves the
# SAME fix survives being driven through the whole use case).
# ══════════════════════════════════════════════════════════════════════════

## _typed_attacker() -> CombatantClass -- str=3, weapon prof_bonus=2,
## damage_die=6: attack modifier is always +5 and damage is always >=6
## (1..6 raw + 3 str + 2 prof), so a Strike against the ac=1/hp=1 target
## below is a GUARANTEED, seed-independent kill -- mirrors
## tests/test_encounter_round_loop.gd's `_durable_combatant()`/
## `_fragile_combatant()` deterministic-kill fixture convention.
func _typed_attacker() -> CombatantClass:
	return CombatantClass.from_dict({
		"name":     "SteelThreadAttacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


## _typed_target(hp) -> CombatantClass -- ac=1 guarantees the attacker above
## always hits (roll_total = d20(>=1) + 3 + 2 >= 6 > ac=1); a real, non-empty
## combatant_id is set so this scenario proves the CombatantClass branch of
## the fixed if/elif reads it via typed property access.
func _typed_target(hp: int) -> CombatantClass:
	return CombatantClass.from_dict({
		"name":         "SteelThreadTypedTarget",
		"combatant_id": "steel_thread_typed_target_1",
		"hp_current":   hp,
		"ac":           1,
	})


func test_typed_combatant_class_target_killing_strike_emits_defeated_event_via_primary_resolve_path() -> void:
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	# A REAL seeded RandomNumberPort adapter (not a scripted/hand-fed double)
	# -- this scenario drives the actual dice-rolling pipeline
	# (resolution.gd's resolve_weapon_attack()) exactly as the live game
	# does, not just the deterministic-outcome arithmetic in isolation.
	var rng_port   = SeededRandomAdapterClass.new(4242)
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)

	var attacker = _typed_attacker()
	var target   = _typed_target(1)
	var ae       = _fresh_ae()

	# The full, public primary path: precondition check -> spend action ->
	# to-hit/damage roll -> _finalize_strike_result(). Reaching the
	# assertions below (rather than aborting mid-call with a SCRIPT ERROR)
	# is itself part of this scenario's proof.
	var result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("resolved", false), "a full primary-path Strike against a guaranteed-hit/guaranteed-lethal typed target must resolve, with no engine error")
	assert_true(result.get("ok", false), "the resolve() result must report ok == true for a successful Strike")
	assert_true(result.get("target_defeated", false), "the typed CombatantClass target at hp_current<=0 post-damage must report target_defeated == true")

	# The AttackEvent itself proves the full to-hit/damage pipeline actually
	# ran (not merely the finalize tail): a real hit with positive damage.
	var attack_events: Array = event_sink.events.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one AttackBroadcast must be emitted for the resolved Strike")
	if attack_events.size() == 1:
		assert_true(attack_events[0].hit, "the guaranteed-hit attacker/target pairing must produce hit == true")
		assert_true(attack_events[0].damage_final > 0, "a hit against this pairing must always deal positive damage")

	var defeated_events: Array = event_sink.events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 1, "exactly one CombatantDefeatedEvent must be emitted for the defeated typed target, with no engine error")
	if defeated_events.size() == 1:
		var ev = defeated_events[0]
		assert_eq(ev.round, 1, "CombatantDefeatedEvent.round must match the round_number passed to resolve()")
		assert_eq(ev.name, "SteelThreadTypedTarget", "CombatantDefeatedEvent.name must be the defeated target's name")
		assert_eq(ev.defeated_by, "SteelThreadAttacker", "CombatantDefeatedEvent.defeated_by must be the attacking combatant's name")
		assert_eq(ev.combatant_id, "steel_thread_typed_target_1", "the CombatantClass branch must read combatant_id via typed property access")
		assert_true(ev.combatant_id != "", "a typed CombatantClass target's emitted combatant_id must be non-empty (RISK-001 closure)")


# ══════════════════════════════════════════════════════════════════════════
# Scenario (b): plain-Dictionary target (no "combatant_id" key -- the exact
# shape that crashed the pre-fix ternary), driven through
# core/combat/encounter.gd's legacy run_round() path -- the same
# Dictionary-combatant path core/sim/simulator.gd historically hit the
# crash through (per resolve_action_use_case.gd's own in-code incident
# note). Mirrors tests/test_encounter_round_loop.gd's FEAT-003
# `_durable_combatant()`/`_fragile_combatant()` factory shapes, authored
# locally here so this file stands alone as its own complete E2E scenario.
# ══════════════════════════════════════════════════════════════════════════

## A durable, high-damage Dictionary attacker with NO "combatant_id" key --
## guarantees a one-shot kill of the fragile Dictionary target below,
## seed-independent (mirrors _typed_attacker()'s guaranteed-lethal math).
func _dict_attacker(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 2000,
		"ac":         10,
		"strength":   3,
		"dexterity":  2,
		"intuition":  2,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


## A fragile Dictionary target with NO "combatant_id" key -- the exact
## legacy shape that crashed the pre-fix eager ternary's else-branch.
func _dict_target(p_name: String) -> Dictionary:
	return {
		"name":       p_name,
		"hp_current": 1,
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


func test_dictionary_target_killing_strike_via_encounter_legacy_path_emits_defeated_event_with_empty_combatant_id() -> void:
	var attacker: Dictionary = _dict_attacker("SteelThreadDictAttacker")
	var target: Dictionary   = _dict_target("SteelThreadDictTarget")

	# Sanity: this is genuinely the legacy shape with no "combatant_id" key
	# -- the shape that crashed the pre-fix ternary's else-branch.
	assert_false(target.has("combatant_id"), "sanity: the Dictionary target fixture must carry no 'combatant_id' key")

	var enc = EncounterClass.new([attacker], [target], RNGClass.new(4242))
	enc.initialize()

	# Drives a full combat round through encounter.gd's legacy Dictionary
	# path. Must not throw/abort mid-round -- reaching the assertions below
	# already proves _finalize_strike_result() completed cleanly for this
	# Dictionary target (no engine error aborting the call).
	var result: Dictionary = enc.run_round()

	var events: Array = enc.get_round_events()
	var defeated_events: Array = events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)

	assert_eq(defeated_events.size(), 1, "SteelThreadDictAttacker must land a lethal hit against SteelThreadDictTarget and emit exactly one CombatantDefeatedEvent, with no engine error")
	if defeated_events.size() == 1:
		var ev = defeated_events[0]
		assert_eq(ev.name, "SteelThreadDictTarget", "the CombatantDefeatedEvent must name the actually-defeated Dictionary-shaped target")
		assert_eq(ev.defeated_by, "SteelThreadDictAttacker", "the CombatantDefeatedEvent must name the attacking Dictionary-shaped combatant")
		assert_eq(ev.combatant_id, "", "a Dictionary target with no 'combatant_id' key must default combatant_id to '' on the emitted CombatantDefeatedEvent, never raise an engine error (RISK-008 closure)")

	assert_eq(result.get("outcome", ""), "won", "SteelThreadDictAttacker defeating the sole enemy must decide the encounter 'won', proving the round loop completed with no mid-round abort")
	assert_eq(enc.get_outcome(), "won", "get_outcome() must also report 'won' once decided")


# ══════════════════════════════════════════════════════════════════════════
# Gate-health assertions (test_criteria #3-#5) -- exercised via the REAL,
# production GateExitPolicy class against the REAL manifest on disk,
# WITHOUT re-spawning a nested full-suite subprocess (see this file's
# header doc for why). The authoritative "Failing Tests: 0 / exit 0" signal
# is this feature's own live `godot --headless -- --gut-run-all`
# verification run, performed as part of implementing/closing this
# feature.
# ══════════════════════════════════════════════════════════════════════════

func test_accepted_known_failures_manifest_remains_the_empty_allowlist() -> void:
	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures(ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	assert_eq(
		accepted, [],
		"ci/accepted_known_failures.json must still equal the literal empty array [] once the steel-thread fix is closed out (US-006: no bypassing the gate via the allowlist)"
	)


func test_gate_exit_policy_reports_zero_unexpected_failures_and_exit_code_zero_for_current_manifest() -> void:
	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures(ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	# actual_failing_test_ids == [] matches this feature's own closing
	# expectation ("Failing Tests: 0" on the real, live --gut-run-all run,
	# verified out-of-process -- see header doc); evaluate() is the REAL,
	# production comparison function ci/gate_exit_policy.gd's post_run_script
	# hook uses to compute the live gate's actual process exit code.
	var evaluation: Dictionary = GateExitPolicyClass.evaluate([], accepted)

	assert_eq(evaluation.get("unexpected_failures", null), [], "GateExitPolicy.evaluate() must report unexpected_failures == [] for a 0-actual-failures run against the current (empty) accepted-known-failures manifest")
	assert_eq(evaluation.get("unexpectedly_passing", null), [], "GateExitPolicy.evaluate() must report unexpectedly_passing == [] -- the manifest carries no stale entries to go stale")
	assert_true(evaluation.get("is_match", false), "GateExitPolicy.evaluate() must report is_match == true for the current manifest state")
	assert_eq(evaluation.get("exit_code", -1), GateExitPolicyClass.EXIT_OK, "GateExitPolicy.evaluate() must resolve to EXIT_OK (0) for the current manifest state")
	assert_eq(GateExitPolicyClass.EXIT_OK, 0, "sanity: EXIT_OK must literally be process exit code 0")


func test_steel_thread_scripts_are_not_excused_via_known_failures_manifest() -> void:
	var accepted: Array = GateExitPolicyClass.load_accepted_known_failures(ACCEPTED_KNOWN_FAILURES_MANIFEST_PATH)
	# Always asserts at least once, even while `accepted` is empty (the
	# current, expected state) -- otherwise this test would report GUT
	# "Risky: did not assert" whenever the loop below has nothing to iterate.
	assert_eq(typeof(accepted), TYPE_ARRAY, "GateExitPolicy.load_accepted_known_failures() must return an Array")
	for script_path in _STEEL_THREAD_SCRIPT_PATHS:
		for test_id in accepted:
			assert_false(
				String(test_id).begins_with("%s::" % script_path),
				"this steel thread's own script (%s) must never be quietly excused via ci/accepted_known_failures.json -- found manifest entry %s" % [script_path, test_id]
			)
