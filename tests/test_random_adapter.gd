extends GutTest
## tests/test_random_adapter.gd
##
## GUT test suite for FEAT-005 / US-004 — RandomNumberPort contract plus
## the GodotRandomAdapter (production) and SeededRandomAdapter (test/sim,
## deterministic) implementations.
##
## Test criteria verified here:
##   1. SeededRandomAdapter given the same seed produces an identical
##      sequence of roll() results across two independent instances.
##   2. GodotRandomAdapter.roll() returns an integer within the expected
##      dice_spec range.
##   3. Both adapters conform to the same RandomNumberPort method
##      signature and can be substituted interchangeably.

const RandomNumberPortClass  = preload("res://core/rules/random_port.gd")
const GodotRandomAdapterClass  = preload("res://core/combat/godot_random_adapter.gd")
const SeededRandomAdapterClass = preload("res://core/combat/seeded_random_adapter.gd")


# ── Criterion 1: SeededRandomAdapter determinism ──────────────────────────────

func test_seeded_adapter_same_seed_produces_identical_sequence() -> void:
	var a = SeededRandomAdapterClass.new(12345)
	var b = SeededRandomAdapterClass.new(12345)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(10):
		seq_a.append(a.roll({"die": 6, "count": 2}))
		seq_b.append(b.roll({"die": 6, "count": 2}))

	assert_eq(seq_a, seq_b, "two SeededRandomAdapter instances with the same seed must produce identical roll() sequences")


func test_seeded_adapter_different_seeds_diverge() -> void:
	var a = SeededRandomAdapterClass.new(1)
	var b = SeededRandomAdapterClass.new(99999)

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(10):
		seq_a.append(a.roll({"die": 20, "count": 1}))
		seq_b.append(b.roll({"die": 20, "count": 1}))

	assert_ne(seq_a, seq_b, "different seeds should (overwhelmingly likely) diverge across a 10-roll d20 sequence")


func test_seeded_adapter_exposes_its_seed() -> void:
	var a = SeededRandomAdapterClass.new(777)
	assert_eq(a.seed(), 777, "SeededRandomAdapter.seed() must return the constructor seed")


# ── Criterion 2: GodotRandomAdapter range checks ──────────────────────────────

func test_godot_adapter_roll_single_die_in_range() -> void:
	var adapter = GodotRandomAdapterClass.new(42)
	for i in range(50):
		var value: int = adapter.roll({"die": 6, "count": 1})
		assert_true(value >= 1, "roll(d6) call %d must be >= 1, got %d" % [i, value])
		assert_true(value <= 6, "roll(d6) call %d must be <= 6, got %d" % [i, value])


func test_godot_adapter_roll_multi_die_in_range() -> void:
	var adapter = GodotRandomAdapterClass.new(42)
	for i in range(50):
		var value: int = adapter.roll({"die": 6, "count": 2})
		assert_true(value >= 2, "roll(2d6) call %d must be >= 2, got %d" % [i, value])
		assert_true(value <= 12, "roll(2d6) call %d must be <= 12, got %d" % [i, value])


func test_godot_adapter_roll_d20_in_range() -> void:
	var adapter = GodotRandomAdapterClass.new(7)
	for i in range(50):
		var value: int = adapter.roll({"die": 20, "count": 1})
		assert_true(value >= 1, "roll(d20) call %d must be >= 1, got %d" % [i, value])
		assert_true(value <= 20, "roll(d20) call %d must be <= 20, got %d" % [i, value])


func test_godot_adapter_auto_seeds_when_no_seed_given() -> void:
	var adapter = GodotRandomAdapterClass.new()
	var value: int = adapter.roll({"die": 6, "count": 1})
	assert_true(value >= 1 and value <= 6, "auto-seeded GodotRandomAdapter.roll(d6) must still be in [1,6], got %d" % value)


## FEAT-002 / US-002: two GodotRandomAdapter instances constructed with a
## null seed_value (the production, "real play" path MainScene now uses --
## see MainScene.gd's `resolved_seed`) must each derive their own
## Time.get_ticks_usec()-based seed rather than sharing any fixed value, so
## two separate real launches never replay the identical combat sequence.
func test_godot_adapter_null_seed_produces_non_repeating_sequences_across_instances() -> void:
	var a = GodotRandomAdapterClass.new()
	var b = GodotRandomAdapterClass.new()

	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(10):
		seq_a.append(a.roll({"die": 20, "count": 1}))
		seq_b.append(b.roll({"die": 20, "count": 1}))

	assert_ne(
		seq_a, seq_b,
		"two GodotRandomAdapter instances each constructed with a null seed_value must "
		+ "(overwhelmingly likely, given each derives its seed from Time.get_ticks_usec() "
		+ "at construction time) diverge across a 10-roll d20 sequence (FEAT-002 / US-002)"
	)


# ── Criterion 3: interchangeable substitution via RandomNumberPort ───────────

func test_both_adapters_are_randomnumberport_instances() -> void:
	var godot_adapter: RandomNumberPort = GodotRandomAdapterClass.new(1)
	var seeded_adapter: RandomNumberPort = SeededRandomAdapterClass.new(1)

	assert_true(godot_adapter is RandomNumberPortClass, "GodotRandomAdapter must extend RandomNumberPort")
	assert_true(seeded_adapter is RandomNumberPortClass, "SeededRandomAdapter must extend RandomNumberPort")


func test_adapters_are_interchangeable_behind_the_port_contract() -> void:
	var ports: Array = [GodotRandomAdapterClass.new(5), SeededRandomAdapterClass.new(5)]
	for port in ports:
		var value: int = port.roll({"die": 8, "count": 1})
		assert_true(value >= 1 and value <= 8, "every RandomNumberPort implementation must honor the same dice_spec contract")


func test_random_port_is_pure_refcounted_with_no_engine_inheritance() -> void:
	var port = RandomNumberPortClass.new()
	assert_true(port is RefCounted, "RandomNumberPort must be a RefCounted")
	assert_false(port is Node, "RandomNumberPort must NOT be a Node (ADR-001 domain purity)")


# ── Linter regression guard: adapters must not bypass RNG (ADR-002) ──────────

func test_adapters_do_not_call_random_number_generator_directly() -> void:
	var paths: Array = [
		"res://core/rules/random_port.gd",
		"res://core/combat/godot_random_adapter.gd",
		"res://core/combat/seeded_random_adapter.gd",
	]
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "%s must be readable" % path)
		if file == null:
			continue
		var content: String = file.get_as_text()
		file.close()
		assert_false(
			content.contains("RandomNumberGenerator.new()"),
			"%s must not contain 'RandomNumberGenerator.new()' — delegate to RNG (ADR-002)" % path
		)
