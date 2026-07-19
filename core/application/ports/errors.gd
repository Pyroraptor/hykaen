## core/application/ports/errors.gd — ErrorCode (FEAT-004 / US-004; FR-003)
##
## Application layer (Clean Architecture, ADR-001): a single closed enum
## shared by every Cast-a-Spell use case (BeginCastUseCase/
## ContinueCastUseCase/ResolveCastUseCase/CancelCastUseCase, landed by later
## features in this iteration) and their adapter callers (SpellActionController/
## ResolveSpellController, presentation/verbs/), so both sides of the port
## boundary speak the SAME vocabulary — per design notes' error_handling
## section: "Errors are modeled as an explicit closed enum ... GDScript
## exceptions are avoided across port boundaries to keep control flow
## explicit and testable" and api_contracts section 5: "All error codes are
## a closed enum (ErrorCode) defined in core/application/ports/errors.gd so
## both use cases and adapters share one vocabulary; adapters translate
## ErrorCode -> user-facing UI messaging, never leak GDScript exceptions
## across the port boundary."
##
## Declared as a bare (unnamed) enum so each member is exposed directly as
## an ErrorCode.<NAME> integer constant — no extra nesting level for every
## call site to spell out, mirroring core/domain/effects/effect_kind.gd's
## identical EffectKind convention.
##
## NONE is member 0 (the enum's default/zero value) so an ExecuteResult/
## ResolveResult "error" field defaults to "no error" rather than aliasing
## whichever real error code happens to be declared first — every concrete
## error member below is deliberately non-zero.
##
## Membership mirrors the design notes' api_contracts section verbatim —
## this feature (FEAT-004) only DECLARES the vocabulary; the use cases that
## actually RETURN each code land with the later features that implement
## BeginCastUseCase/ContinueCastUseCase/ResolveCastUseCase/CancelCastUseCase:
##   ERR_NO_CASTABLE_SPELL   — enter_selection() defensive (US-004 contract
##                             #2): the filtered known-spell list came back
##                             empty even though availability() said yes.
##   ERR_INSUFFICIENT_ENERGY — execute() (US-004 contract #3): RoundEnergyPoolPort
##                             .reserve() failed; no casting_state/action spent.
##   ERR_NOT_CASTABLE        — execute() (US-004 contract #3): the selected
##                             spell_id is not in the actor's known_spell_ids.
##   ERR_CAST_CANCELLED      — execute() (US-004 contract #3): a lethal
##                             Opportunistic Strike fired mid-action (US-014/
##                             US-015); casting_state cleared, no resolution.
##   ERR_NO_VALID_TARGET     — ResolveSpellController.execute() (US-004
##                             contract #2): no in-range target at resolution;
##                             the cast still resolves as a wasted action.
##   ERR_INVALID_STATE       — ResolveSpellController.execute() (US-004
##                             contract #2): the re-entrancy-guard precondition
##                             (remaining_actions == 0) was violated; defensive,
##                             should be unreachable given US-008's own gate.
##
## Usage:
##   var error_code: int = ErrorCode.ERR_INSUFFICIENT_ENERGY
##   if error_code == ErrorCode.NONE:
##       ...

class_name ErrorCode
extends RefCounted

enum {
	NONE,
	ERR_NO_CASTABLE_SPELL,
	ERR_INSUFFICIENT_ENERGY,
	ERR_NOT_CASTABLE,
	ERR_CAST_CANCELLED,
	ERR_NO_VALID_TARGET,
	ERR_INVALID_STATE,
}
