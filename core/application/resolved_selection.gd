## core/application/resolved_selection.gd — ResolvedSelection (FEAT-008 /
## US-008)
##
## Application layer (Clean Architecture): a plain RefCounted DATA object —
## no ports, no I/O, no engine imports beyond RefCounted — the output shape
## core/application/selection_resolution_use_case.gd's resolve() returns.
## Depends on nothing but core/application/selection_descriptor.gd's
## ResolutionMode enum (a sibling application-layer data type), never an
## adapter/infrastructure/presentation type.
##
## data_model (design notes): "Exactly one of {scalar_target,
## (option+scalar_target), target_set} is populated per mode — enforced by
## use-case validation, not by nullable-column proliferation." This class IS
## that enforcement: construction-time validation mirrors the existing
## fail-fast convention established by core/domain/effects/effect_base.gd
## (is_valid()/validation_error()/_reject()) and
## core/application/dto/effect_application_error.gd (named static factory
## methods instead of free-form positional construction at call sites).
##
## Per mode, exactly the fields below must be populated (everything else on
## the same instance must be null):
##   SCALAR             -> scalar_target only
##   OPTION_THEN_TARGET  -> option AND scalar_target
##   AREA_SET            -> target_set only
## A ResolvedSelection that fails this check (or an explicitly-rejected one,
## e.g. a malformed descriptor caught by SelectionResolutionUseCase before
## any resolution began) reports is_valid() == false and carries a
## human-readable validation_error() — mode/scalar_target/option/target_set
## are still whatever was passed in (for diagnostics), but MUST NOT be acted
## on by a caller that hasn't checked is_valid() first.
##
## Usage:
##   var resolved := ResolvedSelection.scalar("enemy_0")
##   resolved.is_valid()      # true
##   resolved.mode             # SelectionDescriptor.ResolutionMode.SCALAR
##   resolved.scalar_target    # "enemy_0"
##
##   var area := ResolvedSelection.area_set([HexCoord.new(0, 0)])
##   area.target_set            # [HexCoord.new(0, 0)]
##
##   var bad := ResolvedSelection.rejected("AREA_SET descriptor requires a bound geometry_rule")
##   bad.is_valid()             # false
##   bad.validation_error()     # the reason given above

class_name ResolvedSelection
extends RefCounted

const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")

## One of SelectionDescriptor.ResolutionMode's members, or -1 for a
## ResolvedSelection built via rejected() (no valid mode could be
## determined -- e.g. an unrecognized resolution_mode on the source
## descriptor).
var mode: int = -1

## Populated for SCALAR (the resolved target_id/hex) and OPTION_THEN_TARGET
## (the resolved target_id/hex, alongside `option`); null otherwise.
var scalar_target = null

## Populated for OPTION_THEN_TARGET only (the chosen Option entry, opaque —
## never inspected by this class); null otherwise.
var option = null

## Populated for AREA_SET only (the resolved Array of affected hexes/
## targets, computed by SelectionResolutionUseCase via core/geometry); null
## otherwise.
var target_set = null

var _valid: bool = true
var _validation_error: String = ""


func _init(
	p_mode: int = -1,
	p_scalar_target = null,
	p_option = null,
	p_target_set = null,
	p_forced_rejection_reason: String = ""
) -> void:
	mode = p_mode
	scalar_target = p_scalar_target
	option = p_option
	target_set = p_target_set

	if p_forced_rejection_reason != "":
		_reject(p_forced_rejection_reason)
		return

	match mode:
		SelectionDescriptorClass.ResolutionMode.SCALAR:
			if scalar_target == null:
				_reject("SCALAR mode requires scalar_target to be populated")
			elif option != null or target_set != null:
				_reject("SCALAR mode must not populate option or target_set")
		SelectionDescriptorClass.ResolutionMode.OPTION_THEN_TARGET:
			if option == null or scalar_target == null:
				_reject("OPTION_THEN_TARGET mode requires both option and scalar_target to be populated")
			elif target_set != null:
				_reject("OPTION_THEN_TARGET mode must not populate target_set")
		SelectionDescriptorClass.ResolutionMode.AREA_SET:
			if target_set == null:
				_reject("AREA_SET mode requires target_set to be populated")
			elif scalar_target != null or option != null:
				_reject("AREA_SET mode must not populate scalar_target or option")
		_:
			_reject("unrecognized resolution mode: %s" % mode)


## is_valid() -> bool — false when construction violated the "exactly one
## populated per mode" invariant, or this instance was built via
## rejected(). A caller MUST check this before acting on scalar_target/
## option/target_set.
func is_valid() -> bool:
	return _valid


## validation_error() -> String — the human-readable rejection reason, or ""
## when is_valid() is true.
func validation_error() -> String:
	return _validation_error


func _reject(reason: String) -> void:
	_valid = false
	_validation_error = reason
	push_error("ResolvedSelection rejected: %s" % reason)


## scalar(value) -> ResolvedSelection — SCALAR mode factory: `value` is the
## legacy first-hex/first-target-clicked resolved value (a target_id String
## or a HexCoord), unchanged from pre-FEAT-008 behavior.
static func scalar(value):
	return new(SelectionDescriptorClass.ResolutionMode.SCALAR, value, null, null)


## option_then_target(chosen_option, value) -> ResolvedSelection —
## OPTION_THEN_TARGET mode factory: `chosen_option` is the Layer-2a pick
## (opaque), `value` is the Layer-2b resolved target_id/hex.
static func option_then_target(chosen_option, value):
	return new(SelectionDescriptorClass.ResolutionMode.OPTION_THEN_TARGET, value, chosen_option, null)


## area_set(hexes) -> ResolvedSelection — AREA_SET mode factory: `hexes` is
## the full resolved Array of affected hexes/targets.
static func area_set(hexes: Array):
	return new(SelectionDescriptorClass.ResolutionMode.AREA_SET, null, null, hexes)


## rejected(reason) -> ResolvedSelection — an explicitly invalid instance
## (mode == -1, every field null) carrying `reason` verbatim as
## validation_error(). Used by SelectionResolutionUseCase.resolve() when a
## descriptor is malformed (e.g. AREA_SET with no bound geometry_rule) or an
## expected pick is missing -- rejected BEFORE any resolution/geometry
## computation is attempted.
static func rejected(reason: String):
	return new(-1, null, null, null, reason)
