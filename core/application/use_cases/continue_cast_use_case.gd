## core/application/use_cases/continue_cast_use_case.gd — ContinueCastUseCase
## (FEAT-006 / US-006; FR-005)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant, core/domain/casting_state.gd's
## CastingState) -- never an adapter/infrastructure/presentation type, and
## never the engine scene tree. `action_economy` is injected duck-typed
## (matches core/application/use_cases/begin_cast_use_case.gd's own
## convention: no static port type annotation, so a caller may substitute a
## fake in a unit test without needing a concrete adapter).
##
## Implements the SUBSEQUENT-ACTION half of the Cast-a-Spell steel thread
## (design notes' architecture section) -- for an actor who IS already
## mid-cast (actor.is_casting() == true): NO re-selection (the spell was
## already picked at BeginCastUseCase time), NO re-payment of energy
## (committed_energy was already reserved up front, non-refundable per
## ADR-003 -- see begin_cast_use_case.gd's own doc), just:
##   1. decrement casting_state.remaining_actions by one
##   2. spend the actor's current turn action
##
## design notes' api_contracts #1 execute() continuing-cast branch:
## "Continuing cast: decrements remaining_actions, fires ReactionWindowPort
## again; no re-payment." -- the ReactionWindowPort/Concentrate-trait
## re-trigger is ProvokeReactionOnCastUseCase's job (an explicitly deferred
## extension point per the architecture section) and OUT of this feature's
## scope; likewise, "If remaining_actions reaches 0 after decrement:
## triggers ResolveCastUseCase" is ResolveCastUseCase's job (a separate,
## later feature) -- this use case only ever decrements and stops, leaving
## a fully-drained casting_state (remaining_actions == 0) in place for that
## later use case to pick up.
##
## Domain purity boundary (ADR-001): extends RefCounted only -- no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ContinueCastUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")
const CastingStateClass = preload("res://core/domain/casting_state.gd")


## execute(actor, action_economy) -> Dictionary{success, casting_state, error}
## -- api_contracts #1's execute() continuing-cast branch. `action_economy`
## is OPTIONAL (default null, duck-typed -- expects spend_action(metadata)
## -> Dictionary, mirroring BeginCastUseCase.execute()'s identical
## convention): when null, the turn-action spend step is simply skipped.
##
## Precondition: `actor` must be non-null AND already mid-cast
## (actor.is_casting() == true) -- this use case NEVER performs a fresh
## spell selection or a fresh energy reservation, so a caller that reaches
## it with a not-yet-casting actor has a wiring bug; fails safe to
## ERR_INVALID_STATE with NO mutation of `actor` and NO action spent
## (mirrors begin_cast_use_case.gd's own "no partial/inconsistent state"
## discipline).
func execute(actor, action_economy = null) -> Dictionary:
	if actor == null or not actor.is_casting():
		return _fail(ErrorCodeClass.ERR_INVALID_STATE)

	var state = CastingStateClass.from_dict(actor.casting_state)
	state.remaining_actions -= 1
	actor.casting_state = state.to_dict()

	if action_economy != null:
		action_economy.spend_action({"name": "Cast a Spell", "traits": []})

	return {
		"success": true,
		"casting_state": (actor.casting_state as Dictionary).duplicate(true),
		"error": ErrorCodeClass.NONE,
	}


func _fail(error_code: int) -> Dictionary:
	return {"success": false, "casting_state": null, "error": error_code}
