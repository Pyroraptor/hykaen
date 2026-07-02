## presentation/end_turn_control.gd — EndTurnControl (FEAT-110 / US-010)
##
## Presentation layer (Clean Architecture): the player-facing control that
## ends the active combatant's turn, satisfying the steel thread's "end
## turn / pass" criterion (US-010). EndTurnControl is intentionally thin: it
## holds no combat-rule logic of its own — pressing it forwards directly to
## the injected RoundSession's end_current_turn() (core/application/
## round_session.gd, ADR-007's declared RoundSession stepwise API on the
## existing, REUSED RunRoundUseCase), which owns cursor sequencing and the
## post-action outcome check. EndTurnControl never resolves an action, never
## constructs a RoundSession, and never duplicates the turn-sequencing rule
## (ADR-002/CR-001: no duplicate action/turn path).
##
## ALWAYS available for the active PLAYER combatant, regardless of whether
## an action was spent this turn (US-010) — configure() enables the control
## whenever the injected RoundSession's current_actor() is a living player
## combatant, and disables it otherwise (no current actor / round over / an
## Enemy's turn).
##
## FEAT-137 / DEF-004: lock()/is_locked() add a persistent, sticky
## post-resolution guard — once presentation/result_screen_view.gd observes
## an EncounterResultEvent it calls lock() here, after which press() always
## rejects with ERR_ENCOUNTER_ALREADY_RESOLVED and is_enabled() always
## reports false, regardless of any later configure() call. This mirrors
## scenes/battlefield/EndTurnController.gd's lock()/is_locked() contract
## exactly and is deliberately independent of (and stickier than) the
## one-time configure(null)-clear technique this file used to rely on —
## that technique re-enabled input the moment anything called configure()
## again (e.g. a stray reconfigure() from a leftover TurnController signal)
## after the encounter had already concluded. There is no unlock() — this
## steel thread never continues a round past resolution.

class_name EndTurnControl
extends Control

## FEAT-137 / DEF-004: local/defensive rejection code returned by press()
## once lock() has been called — mirrors scenes/battlefield/
## EndTurnController.gd's identically-named contract.
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

## turn_ended(result) — emitted after press() invokes the injected
## RoundSession's end_current_turn(), carrying that call's result Dictionary
## verbatim. Presentation code composing this control MAY listen for richer
## UX feedback; no subscriber is required for this control to work.
signal turn_ended(result: Dictionary)

## The injected, REUSED RoundSession (core/application/round_session.gd) —
## EndTurnControl never constructs one itself.
var _round_session = null

## FEAT-137 / DEF-004: true once lock() has been called — sticky across any
## later configure() call (see file-level doc). press()/is_enabled() always
## report rejected/false while true.
var _locked: bool = false

@onready var _button: Button = $Button


func _ready() -> void:
	if _button != null:
		_button.pressed.connect(_on_button_pressed)


## lock() -> void — permanently locks this control (FEAT-137 / DEF-004):
## every subsequent press() call is rejected with
## ERR_ENCOUNTER_ALREADY_RESOLVED and is_enabled() always reports false,
## regardless of any later configure() call. Intended to be called exactly
## once, by presentation/result_screen_view.gd, the moment an
## EncounterResultEvent is observed. There is no unlock().
func lock() -> void:
	_locked = true
	_refresh_enabled_state()


## is_locked() -> bool — true once lock() has been called.
func is_locked() -> bool:
	return _locked


## configure(round_session) -> void — injects the CURRENT RoundSession and
## refreshes the button's enabled/disabled state for whatever actor the
## session now sits on. Safe to call repeatedly (e.g. once per turn/round)
## with no leaked state. Does NOT reset a prior lock() — see file-level doc.
func configure(round_session) -> void:
	_round_session = round_session
	_refresh_enabled_state()


## is_enabled() -> bool — true iff the control is currently pressable (a
## living player combatant is the current actor and the round is not over).
## For test inspection, mirroring the other controls' getters
## (get_button_count(), get_selectable_target_ids(), ...). Always false once
## lock() has been called (FEAT-137 / DEF-004).
func is_enabled() -> bool:
	if _locked:
		return false
	return _compute_enabled()


## press() -> Dictionary — forwards directly to the injected RoundSession's
## end_current_turn() (ADR-007: no duplicate turn-sequencing logic) and
## returns its result Dictionary verbatim, emitting turn_ended with that
## same result, then refreshes the enabled state for whatever actor the
## session now sits on (which may be the round being over, an Enemy's turn,
## or the next player's turn).
##
## FEAT-137 / DEF-004: once lock() has been called, press() is rejected HERE
## FIRST, before end_current_turn() is ever called again, returning
## {"ok": false, "resolved": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}
## -- sticky regardless of any later configure() call.
func press() -> Dictionary:
	if _locked:
		return {"ok": false, "resolved": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}
	if _round_session == null:
		return {"ok": false}

	var result: Dictionary = _round_session.end_current_turn()
	turn_ended.emit(result)
	_refresh_enabled_state()
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

func _compute_enabled() -> bool:
	if _round_session == null:
		return false
	if _round_session.is_round_over():
		return false

	var actor: Dictionary = _round_session.current_actor()
	if actor.is_empty():
		return false

	return not actor.get("_is_enemy", false)


func _refresh_enabled_state() -> void:
	if _button != null:
		_button.disabled = not is_enabled()


func _on_button_pressed() -> void:
	press()
