## core/combat/godot_random_adapter.gd — Production RandomNumberPort adapter
## (FEAT-005 / US-004)
##
## Adapter layer (Clean Architecture): production implementation of
## RandomNumberPort. Wraps the project's single authorised randomness
## source, RNG (core/rules/rng.gd / ADR-002), so this file never touches
## the engine's low-level random-number primitives directly itself — it
## delegates every dice roll to an injected/owned RNG instance, preserving
## the ADR-002 lint invariant that only rng.gd touches the engine RNG API.
##
## Usage example:
##   var adapter: RandomNumberPort = GodotRandomAdapter.new()  # auto-seeded
##   var damage: int = adapter.roll({"die": 6, "count": 2})    # 2d6
##
## An explicit seed may also be supplied (e.g. for adapter-plumbing tests);
## gameplay/simulation determinism should use SeededRandomAdapter instead.
##   var adapter = GodotRandomAdapter.new(12345)

class_name GodotRandomAdapter
extends "res://core/rules/random_port.gd"

const RNGClass = preload("res://core/rules/rng.gd")

var _rng


## _init(seed_value) — seed_value defaults to null, in which case a
## time-derived seed is used so successive production instances do not
## replay the same sequence. Pass an explicit int to pin the sequence
## (adapter-plumbing tests only — see SeededRandomAdapter for the
## deterministic test/sim contract).
func _init(seed_value = null) -> void:
	if seed_value == null:
		seed_value = int(Time.get_ticks_usec())
	_rng = RNGClass.new(seed_value)


## roll(dice_spec) -> int — see RandomNumberPort contract (core/rules/random_port.gd).
func roll(dice_spec: Dictionary) -> int:
	var die_size: int = dice_spec.get("die", 6)
	var count: int = dice_spec.get("count", 1)
	return _rng.roll(die_size, count)
