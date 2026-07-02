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

class_name EndTurnControl
extends Control

## turn_ended(result) — emitted after press() invokes the injected
## RoundSession's end_current_turn(), carrying that call's result Dictionary
## verbatim. Presentation code composing this control MAY listen for richer
## UX feedback; no subscriber is required for this control to work.
signal turn_ended(result: Dictionary)

## The injected, REUSED RoundSession (core/application/round_session.gd) —
## EndTurnControl never constructs one itself.
var _round_session = null

@onready var _button: Button = $Button


func _ready() -> void:
	if _button != null:
		_button.pressed.connect(_on_button_pressed)


## configure(round_session) -> void — injects the CURRENT RoundSession and
## refreshes the button's enabled/disabled state for whatever actor the
## session now sits on. Safe to call repeatedly (e.g. once per turn/round)
## with no leaked state.
func configure(round_session) -> void:
	_round_session = round_session
	_refresh_enabled_state()


## is_enabled() -> bool — true iff the control is currently pressable (a
## living player combatant is the current actor and the round is not over).
## For test inspection, mirroring the other controls' getters
## (get_button_count(), get_selectable_target_ids(), ...).
func is_enabled() -> bool:
	return _compute_enabled()


## press() -> Dictionary — forwards directly to the injected RoundSession's
## end_current_turn() (ADR-007: no duplicate turn-sequencing logic) and
## returns its result Dictionary verbatim, emitting turn_ended with that
## same result, then refreshes the enabled state for whatever actor the
## session now sits on (which may be the round being over, an Enemy's turn,
## or the next player's turn).
func press() -> Dictionary:
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
		_button.disabled = not _compute_enabled()


func _on_button_pressed() -> void:
	press()
