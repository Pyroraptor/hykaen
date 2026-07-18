## core/domain/effect.gd — Effect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O. Extends RefCounted only, matching the existing value-object
## convention (core/geometry/hex_coord.gd, core/rules/round_events.gd).
## Zero imports from application/presentation — this is the entry point of
## the steel thread's data flow into business logic, and it must never
## import outward.
##
## Effect is the abstract base of a tagged-union / discriminated-subtype
## value-object family (design notes' data_model): DamageEffect,
## HealEffect, ConditionEffect, MoveEffect, AddEnergyEffect (the five
## concrete siblings in this same directory). Immutable after construction
## — every field is set exactly once in _init() and never mutated again —
## and carries no identity of its own; `target_id` is a logical FK resolved
## against the live combatant set at apply-time (a future
## CombatantSetPort.get_live_combatants() call, US-002), never a stored
## object reference across turns.
##
## Construction-time validation (design notes' error_handling policy #1):
## "Effect VO construction validates invariants ... and raises/asserts
## immediately on violation — invalid effects must never be constructible,
## let alone applied." GDScript's _init() has no way to refuse handing back
## an instance (there is no constructor-level exception mechanism), so a
## concrete subtype that violates its own invariant calls _reject() the
## moment the violation is detected. _reject() flips is_valid() to false,
## records a human-readable reason, and push_error()s immediately
## (fail-fast, matching this codebase's existing push_error habit — see
## core/domain/combatant.gd's defense()). "invalid effects must never be
## constructible, let alone applied" is honoured downstream: the future
## EffectsApplier (US-002) is contractually required to check is_valid()
## before ever dispatching an effect, so an invalid instance can exist
## transiently but can never reach live combat-state mutation.
##
## Base Effect enforces the ONE invariant every concrete subtype shares —
## a non-empty target_id, since every kind resolves against a live
## Combatant by id (data_model: "Effect.target_id -> Combatant.id").
## Concrete subtypes layer their own additional constraints on top by
## calling super(kind, target_id) first, then their own _reject() checks.
##
## Usage:
##   var e := DamageEffect.new("enemy_0", 6)
##   e.kind        # EffectKind.DAMAGE
##   e.is_valid()  # true
##   var bad := DamageEffect.new("enemy_0", 0)
##   bad.is_valid()          # false — amount must be > 0
##   bad.validation_error()  # "amount must be > 0 (got 0)"

class_name Effect
extends RefCounted

## The EffectKind discriminator identifying which concrete VO this is. -1
## on a bare Effect — production code never constructs Effect directly,
## only a concrete subtype, each of which sets its own kind via super().
var kind: int = -1

## Logical FK to Combatant.id (core/domain/combatant.gd), resolved against
## the live combatant set at apply-time — never stored by reference.
var target_id: String = ""

var _valid: bool = true
var _validation_error: String = ""


func _init(p_kind: int = -1, p_target_id: String = "") -> void:
	kind = p_kind
	target_id = p_target_id
	if target_id == "":
		_reject("target_id must not be empty")


## is_valid() -> bool — false when construction violated an invariant (see
## file-level doc). A caller (EffectsApplier) MUST check this before ever
## dispatching the effect to a Combatant mutator.
func is_valid() -> bool:
	return _valid


## validation_error() -> String — the human-readable reason this Effect was
## rejected at construction, or "" when is_valid() is true.
func validation_error() -> String:
	return _validation_error


## _reject(reason) -> void — subclasses (and this base class) call this the
## moment an invariant is violated. Marks the instance invalid and
## push_error()s immediately (fail-fast in dev/test builds; is_valid()
## additionally lets a shipped build fail-soft by skipping the effect
## instead of crashing — error_handling policy #1).
func _reject(reason: String) -> void:
	_valid = false
	_validation_error = reason
	push_error("Effect rejected at construction: %s" % reason)
