## core/rules/random_port.gd — RandomNumberPort (FEAT-005 / US-004 / NFR-003)
##
## Application-layer port (Clean Architecture): defines the dice-rolling
## contract that future orchestration (RunRoundUseCase / ResolveActionUseCase)
## depends on, so damage resolution can be injected with either a production
## RNG (GodotRandomAdapter) or a deterministic seeded RNG (SeededRandomAdapter)
## for tests/simulation — instead of relying on a global RNG (NFR-003).
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides an abstract roll() that adapters
## MUST override. Concrete adapters extend this script directly
## (`extends "res://core/rules/random_port.gd"`) so any RandomNumberPort-
## typed caller can substitute either adapter interchangeably.
##
## Contract:
##   roll(dice_spec: Dictionary) -> int
##     dice_spec — {"die": int (faces per die, e.g. 6 or 20),
##                  "count": int (number of dice, default 1)}
##     Returns: sum of `count` independent rolls of a `die`-faced die,
##              an int in [count, die * count] inclusive.
##
## Domain purity (ADR-001): no Node/Control/SceneTree inheritance — this
## file extends RefCounted only, the same constraint already applied to
## rng.gd and round_events.gd.
##
## Usage example:
##   var port: RandomNumberPort = GodotRandomAdapter.new()   # production
##   # ...or, in a test/sim context...
##   var port: RandomNumberPort = SeededRandomAdapter.new(12345)
##   var damage: int = port.roll({"die": 6, "count": 2})  # 2d6

class_name RandomNumberPort
extends RefCounted


## roll(dice_spec) -> int — abstract; concrete adapters MUST override.
## The base implementation exists only to document the contract and to
## fail loudly (rather than silently returning a usable-looking value) if
## a caller is ever handed a bare RandomNumberPort instead of a concrete
## adapter.
func roll(dice_spec: Dictionary) -> int:
	push_error("RandomNumberPort.roll() is abstract — override in a concrete adapter (GodotRandomAdapter / SeededRandomAdapter)")
	return 0


## d20() -> int — FEAT-008 (US-008, CR-001): convenience sugar for
## roll({"die": 20, "count": 1}), matching core/rules/rng.gd's d20() call
## surface. Provided on the base class (not overridden by concrete
## adapters) so EVERY RandomNumberPort — SeededRandomAdapter,
## GodotRandomAdapter, or a test double that only overrides roll() — is
## automatically drivable through the SAME RNG-shaped d20()/roll(die_size,
## count) contract core/rules/resolution.gd's injected _rng duck-types
## against, without resolution.gd's contract ever changing. This is what
## lets core/application/resolve_action_use_case.gd delegate live Strike
## resolution to resolution.gd while still consuming its injected
## RandomNumberPort as the sole source of randomness — unifying
## RandomNumberPort and rng.gd onto one seeded RNG source (CR-001).
func d20() -> int:
	return roll({"die": 20, "count": 1})
