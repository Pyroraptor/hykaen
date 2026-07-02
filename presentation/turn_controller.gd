## presentation/turn_controller.gd — TurnController (FEAT-110 / US-010/US-011)
##
## Presentation layer (Clean Architecture): a thin turn-driving Node — NOT an
## Application-layer type. The interactive stepwise API itself lives on
## core/application/round_session.gd's RoundSession (ADR-007); this node
## only decides WHEN to call it:
##   - On an Enemy current_actor(), TurnController auto-drives the turn by
##     calling RoundSession.advance_ai_turn() (US-011) — enemy and player
##     turns funnel through the SAME resolve_action_use_case pipeline the
##     session owns; this node never resolves an action itself.
##   - On a player current_actor(), TurnController enables EndTurnControl
##     (US-010) so the human can act (via StrikeActionControl, unchanged)
##     and/or end their turn.
##
## TurnController never mutates domain state directly, never constructs a
## RoundSession itself, and never reaches into Infrastructure — it is handed
## a RoundSession via set_session() by the composition root (MainScene.gd),
## exactly as the other Presentation nodes are handed their collaborators.

class_name TurnController
extends Node

## Defensive guard against a stalled RoundSession looping forever if
## advance_ai_turn() somehow never leaves the Enemy side (mirrors the
## FEAT-097/CWE-835 backstop philosophy used elsewhere in this codebase).
const _MAX_AI_TURNS_PER_DRIVE: int = 1000

## active_actor_changed(combatant) — emitted whenever _drive() settles on a
## new (player) current actor. Presentation nodes MAY listen for richer UX
## (e.g. re-configuring StrikeActionControl for the new active combatant);
## no subscriber is required for this node to work.
signal active_actor_changed(combatant: Dictionary)

## round_over() — emitted once the held RoundSession reports is_round_over().
signal round_over()

## The injected, REUSED RoundSession (core/application/round_session.gd) —
## TurnController never constructs one itself.
var _round_session = null

## The injected EndTurnControl (presentation/end_turn_control.gd) this
## driver keeps configured with the current RoundSession.
var _end_turn_control = null


## set_session(round_session, end_turn_control) -> void — injects the
## current round's RoundSession and the EndTurnControl this driver manages.
## Immediately drives any leading Enemy turns and refreshes
## end_turn_control's enabled state for whatever actor the round now sits
## on. Safe to call again for a new round (e.g. once RunRoundUseCase.
## begin_round() is called again), with no leaked state from the prior
## RoundSession.
func set_session(round_session, end_turn_control = null) -> void:
	_round_session = round_session
	if end_turn_control != null:
		_end_turn_control = end_turn_control
	_drive()


## on_end_turn_pressed() -> Dictionary — forwards to the held RoundSession's
## end_current_turn() (US-010: EndTurnControl always available, whether or
## not an action was spent this turn), then auto-drives any following Enemy
## turns before yielding back to the player.
func on_end_turn_pressed() -> Dictionary:
	if _round_session == null:
		return {"ok": false}

	var result: Dictionary = _round_session.end_current_turn()
	_drive()
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

## _drive() -> void — auto-resolves consecutive Enemy turns via
## RoundSession.advance_ai_turn() until either a player's turn comes up or
## the round is over, then refreshes end_turn_control's enabled state and
## broadcasts the settled actor.
func _drive() -> void:
	if _round_session == null:
		return

	var guard: int = 0
	while not _round_session.is_round_over() and guard < _MAX_AI_TURNS_PER_DRIVE:
		var actor: Dictionary = _round_session.current_actor()
		if actor.is_empty() or not actor.get("_is_enemy", false):
			break
		_round_session.advance_ai_turn()
		guard += 1

	if _end_turn_control != null:
		_end_turn_control.configure(_round_session)

	if _round_session.is_round_over():
		round_over.emit()
	else:
		active_actor_changed.emit(_round_session.current_actor())
