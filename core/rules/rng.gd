## core/rules/rng.gd — Injectable Seeded Deterministic Random Number Generator
##
## ADR-002 — Constructor-injection pattern:
##   This class is the SINGLE source of randomness for the entire domain layer.
##   All downstream modules (resolution.gd, attributes.gd, encounter.gd) accept
##   an RNG instance as a constructor parameter.  They NEVER construct their own
##   RandomNumberGenerator — they receive one at construction time.
##
## Usage example:
##   var rng = RNG.new(12345)      # deterministic seed for reproducible tests
##   var attack_roll = rng.d20()   # → int in [1, 20]
##   var damage      = rng.roll(6, 2)  # → sum of 2d6, int in [2, 12]
##   var probability = rng.roll_raw()  # → float in [0.0, 1.0)
##
## The CI linter (ADR-002) excludes this file by name:
##   grep ... core/ --exclude=rng.gd
## That exclusion is intentional — this file is the designated implementation.

class_name RNG

var _rng: RandomNumberGenerator


func _init(seed_value: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## d20() → int in [1, 20] inclusive.
## Standard twenty-sided die roll used for attack resolution and initiative.
func d20() -> int:
	return _rng.randi_range(1, 20)


## roll(die_size, count) → sum of `count` independent rolls of a `die_size`-faced die.
## Returns int in [count, die_size * count] inclusive.
func roll(die_size: int, count: int) -> int:
	var total: int = 0
	for _i in range(count):
		total += _rng.randi_range(1, die_size)
	return total


## roll_raw() → float in [0.0, 1.0).
## Used when a raw uniform random value is needed (e.g. probability checks).
func roll_raw() -> float:
	return _rng.randf()
