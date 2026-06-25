extends GutTest
## tests/unit/test_rng.gd
##
## GUT test suite for core/rules/rng.gd — Injectable Seeded Deterministic RNG.
## Validates all test criteria for FEAT-002 / US-002.

const RNGClass = preload("res://core/rules/rng.gd")


# ── Criterion 1: Seeded determinism — two instances with seed 12345 ──────────
# produce the byte-identical 10-call d20() sequence.

func test_seeded_determinism_d20_sequence() -> void:
	var rng_a = RNGClass.new(12345)
	var rng_b = RNGClass.new(12345)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(10):
		seq_a.append(rng_a.d20())
		seq_b.append(rng_b.d20())

	assert_eq(seq_a[0], seq_b[0], "call 0: both instances (seed 12345) must match")
	assert_eq(seq_a[1], seq_b[1], "call 1: both instances (seed 12345) must match")
	assert_eq(seq_a[2], seq_b[2], "call 2: both instances (seed 12345) must match")
	assert_eq(seq_a[3], seq_b[3], "call 3: both instances (seed 12345) must match")
	assert_eq(seq_a[4], seq_b[4], "call 4: both instances (seed 12345) must match")
	assert_eq(seq_a[5], seq_b[5], "call 5: both instances (seed 12345) must match")
	assert_eq(seq_a[6], seq_b[6], "call 6: both instances (seed 12345) must match")
	assert_eq(seq_a[7], seq_b[7], "call 7: both instances (seed 12345) must match")
	assert_eq(seq_a[8], seq_b[8], "call 8: both instances (seed 12345) must match")
	assert_eq(seq_a[9], seq_b[9], "call 9: both instances (seed 12345) must match")


# ── Criterion 2: d20() returns int in [1, 20] across 100 calls ───────────────

func test_d20_range_100_calls() -> void:
	var rng = RNGClass.new(42)
	for i in range(100):
		var value: int = rng.d20()
		assert_true(value >= 1, "d20() call %d must be >= 1, got %d" % [i, value])
		assert_true(value <= 20, "d20() call %d must be <= 20, got %d" % [i, value])


# ── Criterion 3: roll(6, 1) in [1, 6] and roll(6, 2) in [2, 12] ─────────────
# across 50 calls each.

func test_roll_single_die_range() -> void:
	var rng = RNGClass.new(42)
	for i in range(50):
		var value: int = rng.roll(6, 1)
		assert_true(value >= 1, "roll(6,1) call %d must be >= 1, got %d" % [i, value])
		assert_true(value <= 6,  "roll(6,1) call %d must be <= 6, got %d"  % [i, value])


func test_roll_two_dice_range() -> void:
	var rng = RNGClass.new(42)
	for i in range(50):
		var value: int = rng.roll(6, 2)
		assert_true(value >= 2,  "roll(6,2) call %d must be >= 2, got %d"  % [i, value])
		assert_true(value <= 12, "roll(6,2) call %d must be <= 12, got %d" % [i, value])


# ── Criterion 4: roll_raw() returns float in [0.0, 1.0) across 50 calls ──────

func test_roll_raw_range() -> void:
	var rng = RNGClass.new(7)
	for i in range(50):
		var value: float = rng.roll_raw()
		assert_true(value >= 0.0, "roll_raw() call %d must be >= 0.0, got %f" % [i, value])
		assert_true(value < 1.0,  "roll_raw() call %d must be < 1.0, got %f"  % [i, value])


# ── Criterion 5: Seeds 1 and 99999 produce different first d20() values ───────

func test_different_seeds_produce_different_first_d20() -> void:
	var rng_1     = RNGClass.new(1)
	var rng_99999 = RNGClass.new(99999)
	var roll_1:     int = rng_1.d20()
	var roll_99999: int = rng_99999.d20()
	assert_ne(
		roll_1, roll_99999,
		"Seeds 1 and 99999 must produce different first d20() values (got %d vs %d)" % [roll_1, roll_99999]
	)


# ── Criterion 6: rng.gd must not extend Node or Control ──────────────────────

func test_rng_gd_has_no_node_inheritance() -> void:
	var file := FileAccess.open("res://core/rules/rng.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/rng.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"rng.gd must not contain 'extends Node' — ADR-001 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"rng.gd must not contain 'extends Control' — ADR-001 domain purity"
	)


# ── Criterion 7: No other core/ file calls randf/randi/RNG.new() directly ────

func test_linter3_no_direct_rng_usage_in_core_except_rng_gd() -> void:
	var violations: Array = []
	_scan_core_for_rng_violations("res://core", violations)
	assert_eq(
		violations.size(), 0,
		"ADR-002 violation — direct RNG usage in core/ (excluding rng.gd):\n"
		+ "\n".join(violations)
	)


func _scan_core_for_rng_violations(dir_path: String, violations: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_scan_core_for_rng_violations(dir_path + "/" + entry, violations)
		elif entry.ends_with(".gd") and entry != "rng.gd":
			var full_path := dir_path + "/" + entry
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var content: String = f.get_as_text()
				f.close()
				# Mirror the CI grep patterns (ADR-002)
				if content.contains("randf(") or content.contains("randi(") \
						or content.contains("RandomNumberGenerator.new()"):
					violations.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
