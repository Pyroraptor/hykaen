## core/application/dto/effect_application_error.gd — EffectApplicationError
## (FEAT-002 / US-002, ADR-002/ADR-005)
##
## Application layer (Clean Architecture): a plain RefCounted DATA object —
## no ports, no I/O, no engine imports — describing exactly ONE effect that
## EffectsApplierUseCase (core/application/use_cases/
## effects_applier_use_case.gd) could NOT apply during a batch. Depends only
## on core/domain/effects/effect_kind.gd (a domain value/enum) for
## formatting its human-readable message; never imports an adapter/
## infrastructure/presentation type.
##
## api_contracts #1 (design notes): apply() is fail-soft PER EFFECT — one
## bad effect must never abort the rest of the batch. Instead of throwing
## (GDScript has no exceptions) or push_error()-and-forget (the prior
## domain-only EffectsApplier's approach), EffectsApplierUseCase collects
## one of these per skipped effect into AppliedEffectsResult.errors
## (core/application/dto/applied_effects_result.gd) — a caller (a future
## EventSinkPort logging integration, or a test) can inspect exactly which
## effects failed and why, without parsing push_error() console output.
##
## Two codes only (api_contracts #1 / error_handling policy):
##   EFFECT_TARGET_NOT_FOUND — effect.target_id is not a key in the live
##     `combatants` Dictionary passed to apply(). The most common real
##     failure: a stale/expired target_id (e.g. a target that left the
##     encounter between targeting and resolution).
##   EFFECT_UNKNOWN_KIND — defensive; should be unreachable given typed
##     Effect subtypes (core/domain/effects/*.gd), each of which sets its
##     own `kind` from EffectKind (core/domain/effects/effect_kind.gd) via
##     EffectBase._init(). Guards against a malformed/hand-built effect
##     object whose `kind` doesn't match any recognized EffectKind member.
##
## Usage:
##   var err := EffectApplicationError.target_not_found("ghost_id", EffectKind.DAMAGE)
##   err.code_name()   # "EFFECT_TARGET_NOT_FOUND"
##   err.target_id     # "ghost_id"
##   err.message        # human-readable diagnostic string

class_name EffectApplicationError
extends RefCounted

## The two fail-soft error codes this DTO can carry (api_contracts #1).
enum Code {
	EFFECT_TARGET_NOT_FOUND,
	EFFECT_UNKNOWN_KIND,
}

const _CODE_NAMES := {
	Code.EFFECT_TARGET_NOT_FOUND: "EFFECT_TARGET_NOT_FOUND",
	Code.EFFECT_UNKNOWN_KIND: "EFFECT_UNKNOWN_KIND",
}

## One of the Code enum members above.
var code: int

## The offending effect's target_id (may be "" for a malformed effect that
## never carried one).
var target_id: String = ""

## The offending effect's `kind` (an EffectKind member, or an unrecognized
## raw int for EFFECT_UNKNOWN_KIND).
var kind: int = -1

## Human-readable diagnostic, suitable for EventSinkPort ERROR-level logging
## (design notes' observability section) or direct test assertion messages.
var message: String = ""


func _init(p_code: int, p_target_id: String = "", p_kind: int = -1, p_message: String = "") -> void:
	code = p_code
	target_id = p_target_id
	kind = p_kind
	message = p_message


## code_name() -> String — the Code enum member's name (e.g.
## "EFFECT_TARGET_NOT_FOUND"), for log lines/assertions that want a stable
## string rather than the bare int.
func code_name() -> String:
	return _CODE_NAMES.get(code, "UNKNOWN_EFFECT_APPLICATION_ERROR_CODE")


## target_not_found(target_id, kind) -> EffectApplicationError — factory for
## the EFFECT_TARGET_NOT_FOUND case: `target_id` was not a key in the live
## combatants Dictionary at apply-time.
static func target_not_found(p_target_id: String, p_kind: int):
	return new(
		Code.EFFECT_TARGET_NOT_FOUND,
		p_target_id,
		p_kind,
		"EFFECT_TARGET_NOT_FOUND: target_id '%s' not present in the live combatant set (kind=%d)" % [p_target_id, p_kind]
	)


## unknown_kind(target_id, kind) -> EffectApplicationError — factory for the
## defensive EFFECT_UNKNOWN_KIND case: `kind` did not match any recognized
## EffectKind member.
static func unknown_kind(p_target_id: String, p_kind: int):
	return new(
		Code.EFFECT_UNKNOWN_KIND,
		p_target_id,
		p_kind,
		"EFFECT_UNKNOWN_KIND: effect kind %s is not a recognized EffectKind (target_id='%s')" % [p_kind, p_target_id]
	)
