## presentation/end_turn_control.gd — EndTurnControl (FEAT-110 / US-010)
##
## Presentation layer (Clean Architecture): the player-facing control that
## ends the active combatant's turn, satisfying US-010's "can always end
## their turn" steel-thread criterion.
##
## EndTurnControl is intentionally thin, mirroring
## presentation/strike_action_control.gd's shape (FEAT-109 / US-009):
##   1. configure() is handed the currently active combatant Dictionary (so
##      this control knows there IS an active combatant to end a turn for)
##      and the injected, REUSED round-advancement use case
##      (core/application/run_round_use_case.gd, ADR-002/CR-001: no
##      duplicate turn-advancement path) that end_turn() forwards to.
##   2. EndTurnControl is ALWAYS enabled for the active combatant, whether
##      or not that combatant has spent an action this turn — ending a turn
##      voluntarily (no action taken) is exactly as valid as ending it after
##      acting (US-010). is_enabled() therefore never inspects the injected
##      action_economy's is_spent() flag; only whether an active combatant
##      is currently configured.
##   3. Invocation: end_turn() calls the INJECTED run_round_use_case's
##      advance_turn() method directly — the existing, REUSED
##      Application-layer use case this control forwards a "pass" to. That
##      use case is responsible for advancing initiative to the next living
##      combatant and emitting a typed TurnAdvancedEvent via the injected
##      EventSinkPort (ADR-003), observable by any Presentation projection
##      already subscribed to that sink (InitiativeView in particular) —
##      EndTurnControl never pushes events to those views itself, and never
##      re-implements turn-advancement/initiative-cycling logic here.
##
## EndTurnControl MUST NOT re-implement turn-advancement/initiative rules —
## it only (a) exposes an always-available "end turn" affordance for the
## active combatant and (b) forwards the player's choice to the existing
## use case. No new port or use case is introduced (ADR-002 / CR-001
## guardrail).

class_name EndTurnControl
extends Control

## turn_ended(result) -- emitted after end_turn() invokes
## run_round_use_case.advance_turn(), carrying that call's full result
## Dictionary. Presentation code composing this control MAY listen for
## richer UX feedback; no subscriber is required for this control to work.
signal turn_ended(result: Dictionary)

## The currently active combatant Dictionary (as passed to configure()).
## EndTurnControl is enabled exactly when this is non-empty -- it identifies
## THAT there is an active combatant to end a turn for, nothing more.
var _actor: Dictionary = {}

## The active combatant's ActionEconomy instance (core/rules/action_economy.gd),
## injected -- accepted for parity with the actor's turn state, but NEVER
## consulted by is_enabled()/end_turn(): the end-turn affordance is always
## available for the active combatant regardless of is_spent() (US-010).
var _action_economy = null

## The injected, REUSED run_round_use_case (core/application/
## run_round_use_case.gd) -- EndTurnControl never constructs one itself and
## never forks/duplicates its logic (ADR-002). Duck-typed: any object
## exposing advance_turn(encounter_id) -> Dictionary may be substituted
## (test doubles in particular).
var _run_round_use_case = null

## The encounter identifier forwarded verbatim to
## run_round_use_case.advance_turn().
var _encounter_id: String = ""

@onready var _button: Button = $EndTurnButton


func _ready() -> void:
	if _button != null:
		_button.pressed.connect(_on_end_turn_button_pressed)
	_update_button_state()


## configure(actor, action_economy, run_round_use_case, encounter_id) -> void
##
## actor              -- the currently active combatant Dictionary. A
##                        non-empty Dictionary makes this control enabled;
##                        an empty Dictionary (no active combatant, e.g.
##                        before the encounter starts) disables it.
## action_economy     -- the active combatant's ActionEconomy instance for
##                        this round. Stored for parity/inspection only --
##                        NEVER gates is_enabled()/end_turn() (US-010: end
##                        turn works whether or not an action was spent).
## run_round_use_case -- the injected, REUSED use case instance this
##                        control forwards "end turn" to.
## encounter_id       -- forwarded verbatim to advance_turn(); defaults to
##                        "" when the caller has no encounter identifier to
##                        supply.
func configure(
	actor: Dictionary,
	action_economy,
	run_round_use_case,
	encounter_id: String = ""
) -> void:
	_actor = actor
	_action_economy = action_economy
	_run_round_use_case = run_round_use_case
	_encounter_id = encounter_id
	_update_button_state()


## is_enabled() -> bool -- true iff an active combatant is currently
## configured. ALWAYS true for the active combatant regardless of whether
## that combatant's action_economy reports is_spent() true or false
## (US-010's "functioning correctly whether or not an action was spent this
## turn" criterion).
func is_enabled() -> bool:
	return not _actor.is_empty()


## end_turn() -> Dictionary -- forwards directly to the injected
## run_round_use_case.advance_turn(encounter_id) (ADR-002: no duplicate
## turn-advancement path) and returns its result Dictionary verbatim,
## emitting turn_ended with that same result. When no active combatant is
## configured (is_enabled() == false) this is a defensive no-op: no
## use-case call at all, returning
## {"ok": false, "error": "ERR_NO_ACTIVE_COMBATANT"}.
func end_turn() -> Dictionary:
	if not is_enabled() or _run_round_use_case == null:
		return {"ok": false, "error": "ERR_NO_ACTIVE_COMBATANT"}

	var result: Dictionary = _run_round_use_case.advance_turn(_encounter_id)
	turn_ended.emit(result)
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

func _update_button_state() -> void:
	if _button != null:
		_button.disabled = not is_enabled()


func _on_end_turn_button_pressed() -> void:
	end_turn()
