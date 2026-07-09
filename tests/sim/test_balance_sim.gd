extends GutTest
## tests/sim/test_balance_sim.gd
##
## FEAT-090 (NFR-006): Balance Simulation CI Gate — N=1000 Battles with Timeout Assertion.
##
## Raises the balance invariant test from N=90 to N=1000 to achieve the NFR-006
## minimum sample size.  At N=1000 the 95% CI margin of error is ±3.1pp,
## adequate for detecting balance regressions (vs. ±10.5pp at N=90).
##
## Test criteria covered:
##   1. simulator.run(1000, 12345) result contains 'total_battles' key equal to 1000.
##   2. win_rate across 1000 battles is in [0.40, 0.80].
##   3. Wall-clock elapsed (via Time.get_unix_time_from_system()) is < 300 seconds.
##   4. simulator.run() with no arguments defaults to battle_count=1000 (backward compat).
##   5. sim_results.json artifact is written with keys:
##        total_battles, win_rate, avg_rounds, confidence_interval.
##   6. CI exit code: GUT exits 0 when win_rate in [0.40, 0.80], exits 1 otherwise
##      (enforced by the balance invariant assertion in this file).
##
## Satisfies: FEAT-090, NFR-006, US-003, US-009

const SimulatorClass = preload("res://core/sim/simulator.gd")

## Results from a single 1000-battle run, shared across all tests via before_all().
var _result: Dictionary
var _elapsed_seconds: float

## Pinned seed for the 1000-battle run — deterministic CI gate.
const BALANCE_SEED: int = 12345
const BALANCE_COUNT: int = 1000
const TIMEOUT_SECONDS: float = 300.0


func before_all() -> void:
	## Run 1000 battles once and store results.
	## All tests in this file share _result and _elapsed_seconds.
	## Using before_all() avoids repeating a 1000-battle run per test function.
	var sim = SimulatorClass.new()
	var t_start: float = Time.get_unix_time_from_system()
	_result = sim.run(BALANCE_COUNT, BALANCE_SEED)
	_elapsed_seconds = Time.get_unix_time_from_system() - t_start


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: sim_results.total_battles == 1000
# ══════════════════════════════════════════════════════════════════════════════

func test_result_has_total_battles_key() -> void:
	assert_true(
		_result.has("total_battles"),
		"simulator.run(1000, ...) must return a Dictionary with key 'total_battles' — FEAT-090"
	)


func test_total_battles_equals_1000() -> void:
	## Criterion 1: instantiate simulator with battle_count=1000; assert total_battles == 1000.
	assert_eq(
		_result.get("total_battles", -1),
		1000,
		"sim_results.total_battles must equal 1000 when run(1000, ...) is called — FEAT-090 / NFR-006"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: win_rate across 1000 battles is in [0.40, 0.80]
# ══════════════════════════════════════════════════════════════════════════════

func test_win_rate_lower_bound_at_n1000() -> void:
	var wr: float = _result.get("win_rate", -1.0)
	assert_true(
		wr >= 0.40,
		(
			"Balance invariant FAILED (lower bound): win_rate across %d battles must be >= 0.40;"
			+ " got win_rate = %.4f (seed %d) — FEAT-090 / NFR-006"
		) % [BALANCE_COUNT, wr, BALANCE_SEED]
	)


func test_win_rate_upper_bound_at_n1000() -> void:
	var wr: float = _result.get("win_rate", 2.0)
	assert_true(
		wr <= 0.80,
		(
			"Balance invariant FAILED (upper bound): win_rate across %d battles must be <= 0.80;"
			+ " got win_rate = %.4f (seed %d) — FEAT-090 / NFR-006"
		) % [BALANCE_COUNT, wr, BALANCE_SEED]
	)


func test_balance_invariant_n1000_single_seed() -> void:
	## Combined balance gate: asserts win_rate in [0.40, 0.80] for N=1000.
	## This is the primary CI gate assertion — FEAT-090 test criterion 2.
	## Exit code enforcement: GUT exits 1 if this assertion fails, blocking merge.
	var wr: float = _result.get("win_rate", -1.0)
	assert_true(
		wr >= 0.40 and wr <= 0.80,
		(
			"N=1000 balance invariant FAILED: win_rate must be in [0.40, 0.80];"
			+ " got %.4f across %d battles (seed %d)."
			+ " 95%% CI at N=1000: ±3.1pp."
			+ " Indicates a balance regression in encounter resolution — FEAT-090 / NFR-006"
		) % [wr, BALANCE_COUNT, BALANCE_SEED]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Wall-clock elapsed < 300 seconds
# ══════════════════════════════════════════════════════════════════════════════

func test_wall_clock_under_300_seconds() -> void:
	## Criterion 3: asserts the 1000-battle run completes within the CI timeout.
	## Wall-clock elapsed is measured in before_all() via Time.get_unix_time_from_system().
	## 300 seconds is the NFR-006 / FEAT-090 CI wall-clock budget.
	assert_true(
		_elapsed_seconds < TIMEOUT_SECONDS,
		(
			"Timeout assertion FAILED: 1000-battle simulation must complete in < %.0f seconds;"
			+ " took %.2f seconds — FEAT-090 CI timeout gate"
		) % [TIMEOUT_SECONDS, _elapsed_seconds]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: simulator.run() with no arguments defaults to battle_count=1000
# ══════════════════════════════════════════════════════════════════════════════

func test_no_arg_call_returns_total_battles_1000() -> void:
	## Backward-compatibility check: run() with no arguments should use the
	## default battle_count=1000.  Verifies FEAT-090 "existing callers with no
	## argument continue to work" criterion.
	## NOTE: This test calls run() without arguments — uses default battle_count=1000
	## and default base_seed=0.  Verifies the default parameter is correctly applied.
	var sim = SimulatorClass.new()
	var result = sim.run()
	assert_true(
		result.has("total_battles"),
		"run() with no arguments must return a dict with 'total_battles' key — FEAT-090 backward compat"
	)
	assert_eq(
		result.get("total_battles", -1),
		1000,
		"run() with no arguments must default to total_battles=1000 — FEAT-090 backward compat"
	)


func test_existing_callers_with_explicit_args_still_work() -> void:
	## Existing callers: sim.run(n, seed) — positional args, no keyword arg change needed.
	## Verifies the signature change (n_battles → battle_count with default=1000) is
	## backward-compatible with positional argument passing — FEAT-090.
	var sim = SimulatorClass.new()
	var result = sim.run(10, 99999)
	assert_true(
		result.has("win_rate"),
		"run(10, 99999) must still work with the new signature — FEAT-090 backward compat"
	)
	assert_eq(
		result.get("total_battles", -1),
		10,
		"run(10, 99999) must report total_battles=10 — FEAT-090"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: sim_results.json artifact with required keys
# ══════════════════════════════════════════════════════════════════════════════

func test_result_has_win_rate_key() -> void:
	assert_true(
		_result.has("win_rate"),
		"sim_results must contain 'win_rate' key — FEAT-090 artifact"
	)


func test_result_has_avg_rounds_key() -> void:
	assert_true(
		_result.has("avg_rounds"),
		"sim_results must contain 'avg_rounds' key — FEAT-090 artifact"
	)


func test_result_has_confidence_interval_key() -> void:
	assert_true(
		_result.has("confidence_interval"),
		"sim_results must contain 'confidence_interval' key — FEAT-090 artifact"
	)


func test_confidence_interval_is_positive() -> void:
	var ci: float = _result.get("confidence_interval", -1.0)
	assert_true(
		ci >= 0.0,
		"confidence_interval must be >= 0.0; got %.6f — FEAT-090" % ci
	)


func test_confidence_interval_within_expected_range_for_n1000() -> void:
	## At N=1000 and win_rate near 0.5, the 95% CI margin of error is approximately
	## 1.96 * sqrt(0.5 * 0.5 / 1000) ≈ 0.031 (3.1pp).
	## This asserts the CI is < 0.11 (i.e., much tighter than the N=90 CI of ±10.5pp).
	var ci: float = _result.get("confidence_interval", 1.0)
	assert_true(
		ci < 0.11,
		(
			"95%% CI at N=1000 must be < 0.11 (±11pp); got %.4f."
			+ " Expected ≈ ±3.1pp (0.031). — FEAT-090 / NFR-006"
		) % ci
	)


func test_write_sim_results_json_artifact() -> void:
	## Writes sim_results.json for CI artifact upload.
	## This is a best-effort observability artifact — test does NOT fail if write fails.
	## The JSON contains the four required keys: total_battles, win_rate, avg_rounds,
	## confidence_interval.
	##
	## The CI workflow uploads this file as 'balance-sim-results' artifact.
	##
	## FEAT-211 (DEF-003): re-emit the PROVENANCE keys (commit_hash, seed,
	## timestamp) alongside the four result keys. FEAT-007's commit had
	## regenerated this file with only the four result keys, silently dropping
	## provenance; writing all seven here — plus the pinned regression test
	## tests/pytest/test_sim_results_provenance.py — makes a future drop fail CI
	## rather than pass unnoticed.
	var json_dict: Dictionary = {
		"commit_hash":        _current_commit_hash(),
		"seed":               BALANCE_SEED,
		"timestamp":          Time.get_datetime_string_from_system(false, true),
		"total_battles":      _result.get("total_battles",      0),
		"win_rate":           _result.get("win_rate",           0.0),
		"avg_rounds":         _result.get("avg_rounds",         0.0),
		"confidence_interval": _result.get("confidence_interval", 0.0)
	}
	var json_string: String = JSON.stringify(json_dict, "\t")

	## Write to project root via res:// (writable in non-exported headless mode).
	var file := FileAccess.open("res://sim_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(json_string)
		file.close()
		gut.p("sim_results.json written: " + json_string)
	else:
		gut.p("WARNING: could not write sim_results.json (non-fatal — artifact only)")

	## Assert the JSON structure regardless of write success (validates the return dict).
	assert_eq(
		json_dict["total_battles"],
		1000,
		"sim_results.json total_battles must be 1000 — FEAT-090 artifact"
	)
	assert_true(
		json_dict["win_rate"] >= 0.0 and json_dict["win_rate"] <= 1.0,
		"sim_results.json win_rate must be in [0.0, 1.0] — FEAT-090 artifact"
	)


## _current_commit_hash() -> String — FEAT-211 (DEF-003): the git HEAD SHA
## stamped into sim_results.json's provenance, obtained by shelling out to git
## (the repo IS a git checkout in every environment that runs this sim). Returns
## "" if git is unavailable or the command fails, so the artifact write stays
## best-effort / non-fatal, matching this method's existing contract.
func _current_commit_hash() -> String:
	var output: Array = []
	var exit_code: int = OS.execute(
		"git",
		["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"],
		output,
		true
	)
	if exit_code == 0 and output.size() > 0:
		return String(output[0]).strip_edges()
	return ""
