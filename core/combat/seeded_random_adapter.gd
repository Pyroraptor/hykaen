## core/combat/seeded_random_adapter.gd — Deterministic RandomNumberPort
## adapter (FEAT-005 / US-004 / NFR-003)
##
## Adapter layer (Clean Architecture): test/sim implementation of
## RandomNumberPort. Given the same seed, two independent instances
## produce an identical sequence of roll() results — required so the
## future RunRoundUseCase damage resolution can be replayed/asserted
## deterministically instead of depending on a global RNG (NFR-003).
##
## Delegates every dice roll to an owned RNG instance (core/rules/rng.gd /
## ADR-002) — never touches the engine's low-level random-number
## primitives directly.
##
## Usage example:
##   var a: RandomNumberPort = SeededRandomAdapter.new(12345)
##   var b: RandomNumberPort = SeededRandomAdapter.new(12345)
##   a.roll({"die": 6, "count": 2}) == b.roll({"die": 6, "count": 2})  # true

class_name SeededRandomAdapter
extends "res://core/rules/random_port.gd"

const RNGClass = preload("res://core/rules/rng.gd")

var _rng
var _seed: int


## _init(seed_value) — REQUIRED seed (no auto-seeding; determinism is the
## entire purpose of this adapter).
func _init(seed_value: int) -> void:
	_seed = seed_value
	_rng = RNGClass.new(seed_value)


## roll(dice_spec) -> int — see RandomNumberPort contract (core/rules/random_port.gd).
func roll(dice_spec: Dictionary) -> int:
	var die_size: int = dice_spec.get("die", 6)
	var count: int = dice_spec.get("count", 1)
	return _rng.roll(die_size, count)


## seed() -> int — exposes the seed this adapter was constructed with, for
## test assertions/logging.
func seed() -> int:
	return _seed
