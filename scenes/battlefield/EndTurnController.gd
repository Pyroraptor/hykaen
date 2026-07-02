## scenes/battlefield/EndTurnController.gd — EndTurnController (FEAT-008 /
## US-008)
##
## Presentation layer (Clean Architecture): the player-facing controller that
## lets the active combatant end their turn/pass at any point, completing the
## steel thread's "passes their turn" step alongside scenes/battlefield/
## StrikeInputController.gd (FEAT-007) and the turn-order surface it sits
## next to (scenes/battlefield/TurnOrderWidget.gd, FEAT-006).
##
## EndTurnController is intentionally thin, mirroring the prior iteration's
## presentation/end_turn_control.gd and StrikeInputController's own division
## of responsibility: it holds no combat-rule/turn-sequencing logic of its
## own. press() forwards directly to the injected RoundSession's
## end_current_turn() (core/application/round_session.gd, ADR-007's declared
## stepwise API on the existing, REUSED RunRoundUseCase -- obtained by the
## composition root via RunRoundUseCase.begin_round()) -- the SAME
## round-advancement path every other turn-ending trigger in this codebase
## goes through (ADR-002/CR-001: no duplicate/forked turn-sequencing path).
## EndTurnController never resolves an action itself and never constructs a
## RoundSession/RunRoundUseCase.
##
## This steel thread's RunRoundUseCase manages exactly one encounter/round at
## a time -- there is no separate encounter_id parameter anywhere in its or
## RoundSession's contract (core/application/run_round_use_case.gd,
## core/application/round_session.gd). The injected RoundSession instance
## itself IS "the encounter" this controller advances; configure() binds this
## controller to exactly one such instance, and press() only ever advances
## that one (tests/gut/test_end_turn_controller.gd's Criterion 1).
##
## Once the injected RoundSession reports is_round_over() (or none was
## configured at all), press() is rejected LOCALLY, before end_current_turn()
## is ever called again -- a non-blocking, typed ENCOUNTER_ALREADY_RESOLVED
## result rather than a crash (error_handling design note: "Post-resolution
## input guard ... ENCOUNTER_ALREADY_RESOLVED is a defensive domain-level
## guard behind [the UI guard], in case the UI guard is bypassed").

class_name EndTurnController
extends RefCounted

## Local/defensive rejection code returned by press() once the injected
## RoundSession reports the round already over (or none is configured) --
## mirrors the design's ENCOUNTER_ALREADY_RESOLVED contract for
## run_round_use_case's round-advancement path.
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

const _ERROR_MESSAGES: Dictionary = {
	ERR_ENCOUNTER_ALREADY_RESOLVED: "The encounter has already been resolved -- no further turns can be passed.",
}

const _DEFAULT_ERROR_MESSAGE: String = "That action could not be completed."

## turn_ended(result) -- emitted after press() successfully invokes the
## injected RoundSession's end_current_turn(), carrying that call's result
## Dictionary verbatim. No subscriber is required for this control to work.
signal turn_ended(result: Dictionary)

## action_error(message) -- emitted whenever press() is rejected (locally,
## e.g. ENCOUNTER_ALREADY_RESOLVED), carrying the same human-readable message
## get_last_error_message() returns.
signal action_error(message: String)

## The injected, REUSED RoundSession (core/application/round_session.gd) --
## EndTurnController never constructs one itself.
var _round_session = null

var _last_error_code: String = ""
var _last_error_message: String = ""


## configure(round_session) -> void -- injects the CURRENT RoundSession this
## controller advances. Safe to call repeatedly (e.g. rebinding to a fresh
## RoundSession for a subsequent round) with no leaked state.
func configure(round_session) -> void:
	_round_session = round_session
	_last_error_code = ""
	_last_error_message = ""


## is_enabled() -> bool -- true iff pressing pass is currently meaningful: a
## RoundSession is configured, the round is not over, and the current actor
## is a living player combatant. For test inspection and UI affordance
## gating (error_handling design note: "UI disables/greys the affordance
## proactively"), mirroring the prior iteration's EndTurnControl.is_enabled().
func is_enabled() -> bool:
	return _compute_enabled()


## has_error() -> bool -- true iff the most recent press() call was rejected
## and its inline message has not yet been cleared by a subsequent
## configure().
func has_error() -> bool:
	return _last_error_code != ""


## get_last_error_code() -> String -- the error code from the most recent
## rejected press() call, or "" if none/cleared.
func get_last_error_code() -> String:
	return _last_error_code


## get_last_error_message() -> String -- the non-blocking, human-readable
## inline message for the most recent rejected press() call, or "" if
## none/cleared.
func get_last_error_message() -> String:
	return _last_error_message


## press() -> Dictionary -- the player's "pass"/"end turn" input.
##
## When a RoundSession is configured and it does not yet report
## is_round_over(), forwards directly to its end_current_turn() (ADR-007: no
## duplicate turn-sequencing logic) and returns that result Dictionary
## verbatim, emitting turn_ended with it. end_current_turn() itself owns
## checking that any action spent this turn (Spent/action-consumed state) is
## correctly reflected before advancing the cursor -- EndTurnController never
## re-derives or duplicates that check.
##
## When no RoundSession is configured, or it already reports is_round_over()
## (including the defensive case where end_current_turn() itself declines to
## advance), this is rejected -- gracefully, with no exception -- returning
## {"ok": false, "resolved": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}
## and recording a non-blocking inline message (US-008 test_criteria: pass
## issued after resolution must never crash).
func press() -> Dictionary:
	if _round_session == null or _round_session.is_round_over():
		return _fail(ERR_ENCOUNTER_ALREADY_RESOLVED)

	var result: Dictionary = _round_session.end_current_turn()
	if not result.get("ok", false):
		return _fail(ERR_ENCOUNTER_ALREADY_RESOLVED)

	_last_error_code = ""
	_last_error_message = ""
	turn_ended.emit(result)
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

func _fail(error_code: String) -> Dictionary:
	_last_error_code = error_code
	_last_error_message = _ERROR_MESSAGES.get(error_code, _DEFAULT_ERROR_MESSAGE)
	action_error.emit(_last_error_message)
	return {"ok": false, "resolved": false, "error": error_code}


func _compute_enabled() -> bool:
	if _round_session == null:
		return false
	if _round_session.is_round_over():
		return false

	var actor: Dictionary = _round_session.current_actor()
	if actor.is_empty():
		return false

	return not actor.get("_is_enemy", false)
