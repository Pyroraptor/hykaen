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
##   - While it is auto-driving (i.e. any Enemy turn is being resolved),
##     TurnController disables player input (US-011: "the player watches the
##     enemy AI take its automated turn" — no player action must be able to
##     interleave with an in-flight AI turn). EndTurnControl already
##     re-derives its own enabled state from the RoundSession on every
##     configure() call (FEAT-110); the injected StrikeActionControl has no
##     such derivable state of its own (it needs live actor/target data this
##     node does not own), so TurnController disables it the same way its
##     own configure() API already expresses "no selectable targets" — by
##     clearing it via configure() with an empty candidate list (ADR-002: no
##     new StrikeActionControl API is introduced for this). Re-enabling
##     StrikeActionControl with the next player's real targets remains the
##     composition root's responsibility (via active_actor_changed), exactly
##     as before this feature.
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

## The injected StrikeActionControl (presentation/strike_action_control.gd)
## this driver disables (US-011) whenever it is auto-driving an Enemy turn.
## Optional — a caller that never passes one (e.g. existing FEAT-110 tests)
## sees no behavior change.
var _strike_action_control = null


## set_session(round_session, end_turn_control, strike_action_control) ->
## void — injects the current round's RoundSession, the EndTurnControl this
## driver manages, and (optionally, US-011) the StrikeActionControl this
## driver disables while auto-driving Enemy turns. Immediately drives any
## leading Enemy turns and refreshes end_turn_control's enabled state (and
## strike_action_control's disabled state) for whatever actor the round now
## sits on. Safe to call again for a new round (e.g. once RunRoundUseCase.
## begin_round() is called again), with no leaked state from the prior
## RoundSession.
func set_session(round_session, end_turn_control = null, strike_action_control = null) -> void:
	_round_session = round_session
	if end_turn_control != null:
		_end_turn_control = end_turn_control
	if strike_action_control != null:
		_strike_action_control = strike_action_control
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
##
## strike_action_control (US-011) is disabled BEFORE the auto-drive loop
## runs — clearing any stale/leaked configuration from a prior turn — so no
## player Strike input can ever interleave with an Enemy turn this call is
## about to auto-resolve. It is intentionally left disabled once the loop
## settles (even on a player actor): re-enabling it with that player's real,
## live targets is the composition root's job (unchanged by this feature),
## exactly as StrikeActionControl.configure() has always been invoked
## per-turn rather than owned by this node.
func _drive() -> void:
	if _round_session == null:
		return

	_disable_strike_action_control()

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


## _disable_strike_action_control() -> void — clears the injected
## StrikeActionControl (no acting combatant, no selectable targets), which
## reuses StrikeActionControl's existing configure() contract to express
## "disabled" (zero rendered buttons) rather than introducing a new
## enable/disable API on that control (ADR-002 / CR-001 guardrail: no
## duplicate/parallel control-state surface).
func _disable_strike_action_control() -> void:
	if _strike_action_control != null:
		_strike_action_control.configure({}, null, null, [])
