extends GutTest
## tests/test_simulator_determinism.gd
##
## FEAT-003 (US-003/FR-004, RISK-004): backward-compatibility / no-regression
## test for core/sim/simulator.gd (the second legacy driving adapter named
## alongside core/combat/encounter.gd by the FEAT-001/FEAT-002 design notes)
## after the FEAT-001/FEAT-002 _finalize_strike_result() fix — a typed
## if/elif type-branch replacing a crashing eager ternary when reading a
## defeated target's combatant_id. Confirms:
##
##   1. Repeated Simulator.run() calls with an IDENTICAL (battle_count,
##      base_seed) pair produce a field-identical result Dictionary across
##      EVERY reported key — proving the fix introduced no drift into
##      simulator.gd's own N-battle balance-simulation loop, the exact call
##      site the pre-fix crash's own in-code incident note (see
##      core/application/resolve_action_use_case.gd's _finalize_strike_result()
##      doc, "empirically still hits ... inside core/sim/simulator.gd's
##      run_round() loop") flags as its highest-traffic consumer.
##   2. A different base_seed is (overwhelmingly likely) to diverge — proves
##      the equality assertions above are a genuine seed-driven determinism
##      property, not a vacuous always-equal stub.
##   3. core/sim/simulator.gd itself remains byte-for-byte unmodified
##      relative to a pinned pre-change baseline (RISK-004 mitigation,
##      mirrors tests/tools/test_protected_files_unchanged.gd's established
##      SHA-256-pinning convention and this feature's sibling guard in
##      tests/test_encounter_round_loop.gd for core/combat/encounter.gd and
##      its own _durable_combatant()/_fragile_combatant() factories).
##
## This file is FEAT-003's own explicitly-named regression-test file
## (files_to_modify) — it complements, and does not duplicate,
## tests/sim/test_simulator.gd's pre-existing (narrower) determinism checks
## or tests/sim/test_determinism.gd's/tests/test_determinism.gd's
## Encounter-level SeededRandomAdapter suites.
##
## Satisfies: US-003, FR-004. Mitigates RISK-004.

const SimulatorClass = preload("res://core/sim/simulator.gd")

const SIMULATOR_GD_PATH: String = "res://core/sim/simulator.gd"

## PINNED_SIMULATOR_GD_SHA256 — SHA-256 digest captured as this feature's
## (FEAT-003) own pre-change baseline. A future, deliberate change to
## simulator.gd must also regenerate this constant — never a silent drift.
const PINNED_SIMULATOR_GD_SHA256: String = "d3e7d64b42198239a037d6a9242fd6a5e5bfa75a3514c23e2262acd4d1e36f93"


func _read_res_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: repeated Simulator.run() calls with an identical seed produce
# an identical result Dictionary across every reported field, post-fix.
# ══════════════════════════════════════════════════════════════════════════════

func test_repeated_runs_identical_seed_produce_full_dictionary_equality() -> void:
	var sim := SimulatorClass.new()
	var run1: Dictionary = sim.run(10, 2026)
	var run2: Dictionary = sim.run(10, 2026)

	assert_eq(
		run1.keys().size(), run2.keys().size(),
		"two runs with the same (battle_count, base_seed) must report the same NUMBER of result keys"
	)
	assert_eq(
		run1, run2,
		"two Simulator.run() calls with the identical (battle_count=10, base_seed=2026) pair must produce a fully field-identical result Dictionary post-fix — no drift introduced by the FEAT-001/FEAT-002 _finalize_strike_result() fix"
	)

	# Pin each field individually too, so a future change that narrows the
	# whole-Dictionary equality assertion above still catches per-field drift.
	assert_eq(run1["win_rate"], run2["win_rate"], "win_rate must be identical across identically-seeded runs")
	assert_eq(run1["avg_rounds"], run2["avg_rounds"], "avg_rounds must be identical across identically-seeded runs")
	assert_eq(run1["total_damage_dealt"], run2["total_damage_dealt"], "total_damage_dealt must be identical across identically-seeded runs")
	assert_eq(run1["total_battles"], run2["total_battles"], "total_battles must be identical across identically-seeded runs")
	assert_eq(run1["confidence_interval"], run2["confidence_interval"], "confidence_interval must be identical across identically-seeded runs")


## A second, independently-chosen (battle_count, base_seed) pair — guards
## against a coincidental pass tied to one specific seed value.
func test_repeated_runs_second_identical_seed_pair_also_deterministic() -> void:
	var sim := SimulatorClass.new()
	var run1: Dictionary = sim.run(8, 777)
	var run2: Dictionary = sim.run(8, 777)

	assert_eq(
		run1, run2,
		"Simulator.run() determinism must hold for ANY fixed (battle_count, base_seed) pair, not just one pinned example"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: sanity guard — a DIFFERENT base_seed (overwhelmingly likely)
# diverges from the baseline, proving Criterion 1's equality is genuinely
# seed-driven rather than a vacuous always-equal stub.
# ══════════════════════════════════════════════════════════════════════════════

func test_different_seed_overwhelmingly_likely_diverges_from_baseline() -> void:
	var sim := SimulatorClass.new()
	var baseline: Dictionary = sim.run(10, 2026)
	var other: Dictionary = sim.run(10, 999999)

	assert_ne(
		baseline, other,
		"a different base_seed must (overwhelmingly likely) diverge from the baseline result — proves Criterion 1's determinism assertions are seed-driven, not vacuous"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: core/sim/simulator.gd byte-for-byte unmodified relative to the
# FEAT-003 pre-change baseline (RISK-004).
# ══════════════════════════════════════════════════════════════════════════════

func test_simulator_gd_has_zero_diff_from_pinned_baseline() -> void:
	var content: String = _read_res_file(SIMULATOR_GD_PATH)
	assert_eq(
		content.sha256_text(), PINNED_SIMULATOR_GD_SHA256,
		"REGRESSION: core/sim/simulator.gd must have ZERO diff relative to the FEAT-003 pre-change baseline — the FEAT-001/FEAT-002 fix must never require touching this legacy driving adapter (ADR-003)"
	)
