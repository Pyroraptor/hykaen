extends GutTest
## tests/sim/test_simulator.gd
##
## GUT unit tests for core/sim/simulator.gd (FEAT-048 / DEF-004).
##
## Test criteria covered:
##   1. simulator.run(10, 12345) returns a Dictionary with exactly the keys
##      'win_rate', 'avg_rounds', 'total_damage_dealt'.
##   2. win_rate is a float in the closed interval [0.0, 1.0].
##   3. Two sequential calls simulator.run(10, 12345) return identical win_rate
##      values — determinism proven.
##   4. test_balance_invariant_seed_averaged: mean win_rate across seeds [42, 12345, 99999]
##      (30 battles each) is in [0.40, 0.80] — the v0 SEED-AVERAGED balance gate.
##   5. simulator.gd has no extends Node / Control / CanvasItem (ADR-001 purity).
##   6. simulator.gd has no randf(), randi(), RandomNumberGenerator.new() (ADR-002).

const SimulatorClass = preload("res://core/sim/simulator.gd")

var _sim: SimulatorClass


func before_each() -> void:
	_sim = SimulatorClass.new()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: run() returns a Dictionary with exactly the three required keys
# ══════════════════════════════════════════════════════════════════════════════

func test_run_returns_dictionary() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result is Dictionary,
		"run(10, 12345) must return a Dictionary"
	)


func test_run_result_has_win_rate_key() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result.has("win_rate"),
		"result Dictionary must contain key 'win_rate'"
	)


func test_run_result_has_avg_rounds_key() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result.has("avg_rounds"),
		"result Dictionary must contain key 'avg_rounds'"
	)


func test_run_result_has_total_damage_dealt_key() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result.has("total_damage_dealt"),
		"result Dictionary must contain key 'total_damage_dealt'"
	)


func test_run_result_has_exactly_three_keys() -> void:
	var result = _sim.run(10, 12345)
	assert_eq(
		result.keys().size(), 3,
		"result Dictionary must have exactly 3 keys ('win_rate', 'avg_rounds', 'total_damage_dealt'); got: %s"
		% str(result.keys())
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: win_rate is a float in [0.0, 1.0]
# ══════════════════════════════════════════════════════════════════════════════

func test_win_rate_is_float() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result["win_rate"] is float,
		"win_rate must be a float; got type %s" % typeof(result["win_rate"])
	)


func test_win_rate_is_at_least_zero() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result["win_rate"] >= 0.0,
		"win_rate must be >= 0.0; got %f" % result["win_rate"]
	)


func test_win_rate_is_at_most_one() -> void:
	var result = _sim.run(10, 12345)
	assert_true(
		result["win_rate"] <= 1.0,
		"win_rate must be <= 1.0; got %f" % result["win_rate"]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: Determinism — two sequential calls produce identical win_rate
# ══════════════════════════════════════════════════════════════════════════════

func test_two_sequential_calls_produce_identical_win_rate() -> void:
	var result_a = _sim.run(10, 12345)
	var result_b = _sim.run(10, 12345)
	assert_eq(
		result_a["win_rate"], result_b["win_rate"],
		"Determinism: two sequential calls with same seed must produce identical win_rate"
	)


func test_two_sequential_calls_produce_identical_avg_rounds() -> void:
	var result_a = _sim.run(10, 12345)
	var result_b = _sim.run(10, 12345)
	assert_eq(
		result_a["avg_rounds"], result_b["avg_rounds"],
		"Determinism: two sequential calls with same seed must produce identical avg_rounds"
	)


func test_two_sequential_calls_produce_identical_total_damage() -> void:
	var result_a = _sim.run(10, 12345)
	var result_b = _sim.run(10, 12345)
	assert_eq(
		result_a["total_damage_dealt"], result_b["total_damage_dealt"],
		"Determinism: two sequential calls with same seed must produce identical total_damage_dealt"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: v0 SEED-AVERAGED Balance Invariant (FEAT-048 / DEF-004)
#
# The mean win_rate, averaged across at least 3 distinct base seeds, must be
# in [0.40, 0.80].  Using a single pinned seed is explicitly FORBIDDEN by the
# spec — the invariant must be seed-averaged to avoid false passes that arise
# from a lucky single-seed sequence.
#
# Agent-chosen configuration:
#   Seeds: [42, 12345, 99999]  — widely spaced to sample different RNG regions
#   Battles per seed: 30       — 90 total encounters
#
# This test BLOCKS CI MERGE if the averaged win_rate is outside [0.40, 0.80].
# ══════════════════════════════════════════════════════════════════════════════

func test_balance_invariant_seed_averaged() -> void:
	## v0 SEED-AVERAGED Balance Invariant — FEAT-048 test criterion.
	##
	## Averages win_rate across 3 distinct base seeds (42, 12345, 99999)
	## with 30 battles per seed (90 total encounters).  The mean must be
	## in [0.40, 0.80]; this test fails — and blocks CI — if it is not.
	var seeds: Array = [42, 12345, 99999]
	var battles_per_seed: int = 30
	var total_win_rate: float = 0.0

	for seed in seeds:
		var result = _sim.run(battles_per_seed, seed)
		assert_true(
			result.has("win_rate"),
			"run(%d, %d) must return a result with 'win_rate' key" % [battles_per_seed, seed]
		)
		total_win_rate += result["win_rate"]

	var mean_win_rate: float = total_win_rate / float(seeds.size())

	assert_true(
		mean_win_rate >= 0.40 and mean_win_rate <= 0.80,
		(
			"v0 SEED-AVERAGED balance invariant FAILED: "
			"mean win_rate across seeds %s (%d battles each) "
			"must be in [0.40, 0.80]; got mean_win_rate = %.4f. "
			"This indicates the v0 encounter balance is outside the acceptable range."
		) % [str(seeds), battles_per_seed, mean_win_rate]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: ADR-001 domain purity — simulator.gd must not extend Node,
#              Control, or CanvasItem
# ══════════════════════════════════════════════════════════════════════════════

func test_simulator_gd_does_not_extend_node() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"simulator.gd must not contain 'extends Node' — ADR-001 domain purity"
	)


func test_simulator_gd_does_not_extend_control() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Control"),
		"simulator.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


func test_simulator_gd_does_not_extend_canvas_item() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends CanvasItem"),
		"simulator.gd must not contain 'extends CanvasItem' — ADR-001 domain purity"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 6: ADR-002 injected RNG — no direct randf/randi/
#              RandomNumberGenerator.new() in simulator.gd
# ══════════════════════════════════════════════════════════════════════════════

func test_no_direct_randf_in_simulator_gd() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("randf("),
		"simulator.gd must not contain 'randf(' — use injected RNG (ADR-002)"
	)


func test_no_direct_randi_in_simulator_gd() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("randi("),
		"simulator.gd must not contain 'randi(' — use injected RNG (ADR-002)"
	)


func test_no_random_number_generator_new_in_simulator_gd() -> void:
	var file := FileAccess.open("res://core/sim/simulator.gd", FileAccess.READ)
	assert_not_null(file, "core/sim/simulator.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("RandomNumberGenerator.new()"),
		"simulator.gd must not contain 'RandomNumberGenerator.new()' — use RNGClass (ADR-002)"
	)
