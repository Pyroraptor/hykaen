extends GutTest
## tests/unit/test_energy_pool.gd
##
## GUT test suite for FEAT-003 (US-003; FR-012, FR-015): EnergyPool
## (core/domain/energy_pool.gd), the per-caster Channeling energy pool
## value object RoundSession keys by caster_id.
##
## Verifies (test_criteria):
##   1. EnergyPool.current caps at capacity (= spellcasting attribute score)
##      and never exceeds it, no matter how much is added in one or many
##      calls.
##   2. empty() resets current to 0 without touching capacity.
##   3. Clamp-on-add also floors at 0 (never goes negative).

const EnergyPoolClass = preload("res://core/domain/energy_pool.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: current caps at capacity, never exceeds it.
# ══════════════════════════════════════════════════════════════════════════

func test_new_pool_starts_at_zero_current_with_given_capacity() -> void:
	var pool := EnergyPoolClass.new(3)
	assert_eq(pool.capacity, 3, "capacity must equal the constructor argument (spellcasting_attribute_score)")
	assert_eq(pool.current, 0, "a freshly-created pool must start with zero current energy")


func test_add_within_capacity_is_not_clamped() -> void:
	var pool := EnergyPoolClass.new(3)
	var result: int = pool.add(2)
	assert_eq(result, 2, "add() must return the new current value")
	assert_eq(pool.current, 2, "adding less than capacity must not be clamped")


func test_add_beyond_capacity_clamps_current_to_capacity() -> void:
	var pool := EnergyPoolClass.new(3)
	pool.add(5)
	assert_eq(pool.current, 3, "current must never exceed capacity, no matter how large a single add() is")


func test_repeated_adds_never_push_current_past_capacity() -> void:
	var pool := EnergyPoolClass.new(3)
	pool.add(2)
	pool.add(2)
	pool.add(2)
	assert_eq(pool.current, 3, "current must remain clamped at capacity across multiple add() calls")


func test_zero_capacity_pool_clamps_every_add_to_zero() -> void:
	var pool := EnergyPoolClass.new(0)
	pool.add(4)
	assert_eq(pool.current, 0, "a non-caster's zero-capacity pool must never bank any energy")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: clamp-on-add also floors at 0 (never negative).
# ══════════════════════════════════════════════════════════════════════════

func test_negative_add_never_drops_current_below_zero() -> void:
	var pool := EnergyPoolClass.new(3)
	pool.add(1)
	pool.add(-5)
	assert_eq(pool.current, 0, "current must never go below 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion: empty() resets current to 0 without touching capacity.
# ══════════════════════════════════════════════════════════════════════════

func test_empty_resets_current_to_zero() -> void:
	var pool := EnergyPoolClass.new(3)
	pool.add(3)
	assert_eq(pool.current, 3, "fixture assumption: pool is full before empty()")

	pool.empty()

	assert_eq(pool.current, 0, "empty() must reset current to 0")


func test_empty_does_not_change_capacity() -> void:
	var pool := EnergyPoolClass.new(5)
	pool.add(3)

	pool.empty()

	assert_eq(pool.capacity, 5, "empty() must never mutate capacity — a fresh round reuses the SAME resolved capacity")
