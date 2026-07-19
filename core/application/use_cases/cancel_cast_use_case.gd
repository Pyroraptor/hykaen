## core/application/use_cases/cancel_cast_use_case.gd — CancelCastUseCase
## (FEAT-280 / US-015; FR-017)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant — specifically its EXISTING
## cancel_cast() mutator, reserved for exactly this purpose since FEAT-001's
## own "Cast-a-Spell hooks (reserved)" doc: "is_casting()/cancel_cast() are
## kept minimal now so the shape is reserved and cast interruption (a
## lethal Opportunistic Strike cancels an in-progress cast, mirroring
## lethal-OS-cancels-Stride) has a seam") — never an adapter/infrastructure/
## presentation type, and never the engine scene tree.
##
## Mirrors iteration K FEAT-238's lethal-OS-cancels-Stride machinery
## (core/application/use_cases/resolve_stride_use_case.gd's
## "mover_downed" -> "stride_should_commit: false" contract,
## presentation/stride_action_controller.gd's own cancel branch) for
## Cast-a-Spell: presentation/verbs/spell_action_controller.gd's own
## `_maybe_cancel_cast()` (this feature's other modified file) is the SOLE
## caller, invoked whenever core/application/use_cases/
## provoke_reaction_on_cast_use_case.gd's ProvokeReactionOnCastUseCase
## reports `stride_should_commit == false` for a mid-cast actor's action —
## i.e. a lethal Opportunistic Strike fired during casting (US-014/US-015).
##
## execute(actor) -> Dictionary{success, casting_state, error} — the SINGLE
## atomic transition design notes' error_handling section requires: clear
## `actor.casting_state` via the EXISTING Combatant.cancel_cast() mutator
## (no new Combatant mutator is introduced by this feature), WITHOUT
## refunding `committed_energy` to the caster's round energy pool (ADR-003
## — up-front payment is non-refundable by design; core/application/ports/
## round_energy_pool_port.gd deliberately exposes no public refund() method
## at all, so this use case has nothing it could even call to refund
## through — "not refunding" is therefore satisfied simply by NEVER
## touching the RoundEnergyPoolPort/EnergyPool at all, not by some
## corrective reversal step), and WITHOUT ever invoking ResolveCastUseCase
## (this guarantees the mutual-exclusion invariant "a cast either resolves
## exactly once or is cancelled exactly once, never both" — design notes'
## error_handling section).
##
## Precondition: `actor` must be non-null AND already mid-cast
## (actor.is_casting() == true) — a caller reaching this use case with a
## not-yet-casting actor has a wiring bug; fails safe to ERR_INVALID_STATE
## with NO mutation of `actor` (mirrors continue_cast_use_case.gd's own "no
## partial/inconsistent state" discipline).
##
## The returned "error" on the SUCCESS path is ERR_CAST_CANCELLED (per
## core/application/ports/errors.gd's own doc: "a lethal Opportunistic
## Strike fired mid-action ... casting_state cleared, no resolution")
## rather than ErrorCode.NONE — this is a successful CANCELLATION, not an
## unremarkable no-op, so the caller's own ExecuteResult carries that
## distinction through.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name CancelCastUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## execute(actor) -> Dictionary{success, casting_state, error} — see
## file-level doc for the full contract. `casting_state` is ALWAYS null on
## return (whether the precondition failed or the cancellation succeeded) —
## mirrors begin_cast_use_case.gd's/continue_cast_use_case.gd's own
## `_fail()` shape, and matches "casting_state cleared" on the success path.
func execute(actor) -> Dictionary:
	if actor == null or not actor.is_casting():
		return {"success": false, "casting_state": null, "error": ErrorCodeClass.ERR_INVALID_STATE}

	# The SOLE mutation this use case ever performs: clear casting_state via
	# Combatant's own existing mutator. No RoundEnergyPoolPort/EnergyPool
	# collaborator is touched -- ADR-003's "up-front payment is
	# non-refundable" is satisfied by omission, not by a corrective step.
	actor.cancel_cast()

	return {"success": true, "casting_state": null, "error": ErrorCodeClass.ERR_CAST_CANCELLED}
