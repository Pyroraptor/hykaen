## presentation/result_screen_view.gd — ResultScreenView (FEAT-112 / US-012)
##
## Presentation layer (Clean Architecture): the terminal projection that
## satisfies the steel thread's exit_point criterion. ResultScreenView
## subscribes to the SAME typed round-event pipeline every other Presentation
## projection already subscribes to (ADR-003, EventSinkPort) and, on the ONE
## terminal event an encounter ever emits — RoundEvents.EncounterResultEvent
## (core/rules/round_events.gd) — renders "Win"/"Loss" and disables all
## combat input controls, so no further Strike/EndTurn input can ever reach a
## concluded encounter.
##
## Outcome text mapping mirrors core/application/determine_outcome_use_case.gd's
## classify()/build_event() contract EXACTLY (the single classification
## authority, reused unchanged — ADR-002/CR-001): that use case classifies
## from the PLAYER party's perspective and returns 'won' when the enemies
## side is fully defeated, 'lost' when the party side is fully defeated.
## ResultScreenView therefore renders:
##   outcome == "won"  -> "Win"
##   outcome == "lost" -> "Loss"
## No other outcome value (e.g. the empty "undecided" string, or the
## per-round-only "DRAW" RunRoundUseCase never surfaces as an
## EncounterResultEvent — see round_session.gd) ever reaches this view in
## production; an unrecognized value renders as "" (a defensive no-op display,
## matching every other Presentation projection's "unfamiliar event shape is a
## silent no-op" convention).
##
## Disabling combat input controls (US-012, hardened by FEAT-137 / DEF-004)
## reuses each control's EXISTING lock() API — no new method is added to
## either control (ADR-002/CR-001: no duplicate/parallel disable surface):
##   StrikeActionControl (presentation/strike_action_control.gd) — lock()
##     clears every selectable-target button (the same visible effect the
##     prior one-time configure({}, null, null, [])-clear had) AND
##     permanently rejects select_target()/is_target_selectable() from that
##     point on.
##   EndTurnControl (presentation/end_turn_control.gd) — lock() permanently
##     rejects press() and reports is_enabled() == false from that point on.
## Unlike the prior one-time configure()-clear technique, lock() is a
## PERSISTENT, sticky guard: it survives any later configure() call on
## either control (e.g. a stray reconfigure() from a leftover
## TurnController signal) after the encounter has already concluded --
## defense in depth, mirroring the error_handling design note's
## "ENCOUNTER_ALREADY_RESOLVED is a defensive domain-level guard behind
## [the UI guard], in case the UI guard is bypassed". Both controls are
## OPTIONAL (configure() accepts either/both as null) so this view can be
## unit-tested in isolation from either control.
##
## ResultScreenView MUST NOT call into either of the two Application-layer
## use cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a read-only
## terminal projection, never a mutator of domain state (enforced by a
## source-inspection regression test,
## tests/unit/presentation/test_result_screen_view.gd).
##
## Event duck-typing (`_event_has` / `_event_get`): events may arrive either
## as a typed core/rules/round_events.gd value object (a RefCounted with
## plain `var` fields) or as a plain Dictionary (as used by tests to simulate
## an event without depending on a concrete adapter/event-sink wiring), the
## same convention already established by status_panel_view.gd/
## initiative_view.gd. An EncounterResultEvent is discriminated from every
## other round event by carrying an `outcome` key — no other event in
## core/rules/round_events.gd's shape declares that field.

class_name ResultScreenView
extends Control

## result_shown(result_text) — emitted once, the first time an
## EncounterResultEvent is processed, carrying the exact text now displayed
## ("Win" or "Loss"). Presentation code composing this view MAY listen for
## richer UX feedback; no subscriber is required for this view to work.
signal result_shown(result_text: String)

## The injected StrikeActionControl (presentation/strike_action_control.gd)
## this view disables once an EncounterResultEvent is received. Optional —
## a caller that never passes one sees no error, only no-op.
var _strike_action_control = null

## The injected EndTurnControl (presentation/end_turn_control.gd) this view
## disables once an EncounterResultEvent is received. Optional, same as above.
var _end_turn_control = null

## True once an EncounterResultEvent has been processed and the result is
## being displayed.
var _shown: bool = false

## The exact text currently displayed ("Win" / "Loss" / "" before any
## EncounterResultEvent has arrived).
var _result_text: String = ""

@onready var _result_label: Label = $ResultLabel


func _ready() -> void:
	if _result_label != null:
		_result_label.visible = false
		_result_label.text = ""


## configure(strike_action_control, end_turn_control) -> void — injects the
## combat input controls this view disables once shown (US-012). Both
## parameters are OPTIONAL (default null); passing null for either simply
## means this view will not attempt to disable that control. Safe to call
## repeatedly (e.g. once per turn, mirroring the other controls' configure()
## contracts) with no leaked state.
func configure(strike_action_control = null, end_turn_control = null) -> void:
	_strike_action_control = strike_action_control
	_end_turn_control = end_turn_control


## is_shown() -> bool — true once an EncounterResultEvent has been processed.
func is_shown() -> bool:
	return _shown


## get_result_text() -> String — the exact text currently displayed
## ("Win" / "Loss" / "" before any EncounterResultEvent has arrived).
func get_result_text() -> String:
	return _result_text


## get_label_text() -> String — the exact text rendered on the result Label,
## for display-level assertions (mirrors the other views' get_row_text()).
func get_label_text() -> String:
	return _result_label.text if _result_label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes an
## EncounterResultEvent-shaped payload (carries `outcome`) and forwards it to
## on_encounter_result_event(). Any other/unrecognized event shape is a
## silent no-op — ResultScreenView only reacts to the one terminal event it
## understands, never errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_has(event, "outcome"):
		on_encounter_result_event(event)


## on_encounter_result_event(event) → void — renders "Win"/"Loss" for the
## given EncounterResultEvent-shaped payload and disables all combat input
## controls injected via configure(). `event` must carry `outcome` (String,
## "won" or "lost" — see core/application/determine_outcome_use_case.gd).
## Idempotent: a second EncounterResultEvent (should not occur in production
## — it is a terminal, once-only event) simply re-renders/re-disables rather
## than erroring.
func on_encounter_result_event(event) -> void:
	var outcome: String = _event_get(event, "outcome", "")
	_result_text = _text_for_outcome(outcome)
	_shown = true

	if _result_label != null:
		_result_label.text = _result_text
		_result_label.visible = true

	_disable_combat_controls()
	result_shown.emit(_result_text)


# ── Internal helpers ─────────────────────────────────────────────────────

## _text_for_outcome(outcome) -> String — maps a determine_outcome_use_case
## outcome string to this view's displayed text. See file-level doc for the
## full contract.
func _text_for_outcome(outcome: String) -> String:
	match outcome:
		"won":
			return "Win"
		"lost":
			return "Loss"
		_:
			return ""


## _disable_combat_controls() -> void — permanently locks the injected
## StrikeActionControl/EndTurnControl via their EXISTING lock() APIs (see
## file-level doc — no new method added to either control, ADR-002/CR-001).
## FEAT-137 / DEF-004: lock() is persistent/sticky, unlike the one-time
## configure()-clear this method used to perform.
func _disable_combat_controls() -> void:
	if _strike_action_control != null:
		_strike_action_control.lock()
	if _end_turn_control != null:
		_end_turn_control.lock()


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## ResultScreenView never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
