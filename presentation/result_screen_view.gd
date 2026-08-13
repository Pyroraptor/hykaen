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
## Disabling combat input controls (US-012, hardened by FEAT-137 / DEF-004;
## FEAT-005 / US-005 / FR-011 / ADR-005: uniformly extended to Movement)
## reuses each control's EXISTING lock() API — no new method is added to any
## of the three controls (ADR-002/CR-001: no duplicate/parallel disable
## surface):
##   StrikeActionControl (presentation/strike_action_control.gd) — lock()
##     clears every selectable-target button (the same visible effect the
##     prior one-time configure({}, null, null, [])-clear had) AND
##     permanently rejects select_target()/is_target_selectable() from that
##     point on.
##   EndTurnControl (presentation/end_turn_control.gd) — lock() permanently
##     rejects press() and reports is_enabled() == false from that point on.
##   MovementInputController (presentation/movement_input_controller.gd,
##     FEAT-162 / DEF-001) — lock() clears every selectable Step/Stride
##     destination (and any HexGridView highlight), and permanently rejects
##     step_to()/stride_to() from that point on. This is the ONE remaining
##     post-resolution input surface the removed scenes/battlefield/
##     ResultScreen.gd already locked (via its own
##     _movement_input_controller field) that presentation/result_screen_view.gd
##     had not yet been wired to lock -- FEAT-005 closes that gap by
##     migrating the SAME lock-wiring logic here, uniformly, as one
##     operation (lock_all_controls()).
##   MoveActionControl (presentation/MoveActionControl.gd, FEAT-167 /
##     US-005/US-007/US-008, design notes' API contract #6 "MoveActionControl
##     hidden") — lock() hides the visible Move affordance and reports
##     is_enabled() == false from that point on, regardless of any later
##     configure() call. Closes the gap where MainScene's own
##     _on_round_over() backstop (which clears move_action_control via
##     configure([])) is never reached when the round concludes directly
##     inside end_current_turn() (e.g. the player's own Strike defeats the
##     last enemy and the very next EndTurnControl.press() decides "won"
##     without TurnController ever re-driving/emitting round_over) --
##     lock_all_controls() is the ONE place every combat/movement control is
##     guaranteed to be locked no matter which of the two RoundSession
##     outcome-decision call paths (advance_ai_turn() vs end_current_turn())
##     actually decided the encounter.
## Unlike the prior one-time configure()-clear technique, lock() is a
## PERSISTENT, sticky guard: it survives any later configure() call on any
## of the three controls (e.g. a stray reconfigure() from a leftover
## TurnController/active-actor-changed signal) after the encounter has
## already concluded -- defense in depth, mirroring the error_handling
## design note's "ENCOUNTER_ALREADY_RESOLVED is a defensive domain-level
## guard behind [the UI guard], in case the UI guard is bypassed". All three
## controls are OPTIONAL (configure() accepts any/all as null) so this view
## can be unit-tested in isolation from any of them.
##
## FEAT-177 (US-013 / FR-013): lock_all_controls() additionally locks two
## OPTIONAL presentation collaborators via their OWN lock()/is_locked()
## contract (no new lock surface invented here, same ADR-002/CR-001
## discipline as the four controls above):
##   VerbBarView (presentation/verb_bar_view.gd) — lock() permanently
##     disables every rendered verb button and permanently rejects press()
##     from that point on.
##   SelectionOverlay (presentation/selection_overlay.gd) — lock()
##     immediately discards any in-progress Layer 2 selection (clearing the
##     HexGridView highlight) and permanently rejects activate()/hex_clicked
##     dispatch from that point on, so a pending Strike/Step/Stride pick can
##     never resolve post-resolution.
## This is the steel thread's exit-point guarantee: "controls lock
## post-resolution" — see tests/gut/test_post_resolution_lock_regression.gd.
##
## lock_all_controls() (FEAT-005) is the single, idempotent operation that
## performs this uniform lock -- called once from on_encounter_result_event()
## when EncounterResolved (EncounterResultEvent) fires, but also exposed as a
## public method so composition-root/test code may invoke it directly.
## Idempotent: every one of Strike/EndTurn/MovementInputController's lock()
## methods is itself idempotent (setting an already-true "locked" flag and
## re-asserting an already-empty selectable/target set), so calling
## lock_all_controls() any number of times produces the SAME end state with
## no additional side effects beyond the first call.
##
## FEAT-008 / US-008 (FR-003): this is also the mechanism satisfying US-008's
## "clear/keep-cleared the movement highlight post-resolution" requirement --
## no new code is added here for that feature. lock_all_controls() ->
## MovementInputController.lock() (presentation/movement_input_controller.gd)
## already both clears any injected HexGridView's selectable-hex set
## immediately AND permanently rejects every later configure()-driven
## re-highlight attempt (sticky, FEAT-162/DEF-001), so a stray
## turn_started/active_actor_changed re-fire after EncounterResolved can
## never resurrect the highlight -- see
## tests/business_logic/test_clear_highlight_triggers.gd and this file's
## sibling tests/business_logic/test_result_screen_lock.gd.
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

## The injected MovementInputController (presentation/
## movement_input_controller.gd, FEAT-162 / DEF-001) this view locks once an
## EncounterResultEvent is received (FEAT-005 / US-005 / FR-011 / ADR-005).
## Optional, same no-op-if-null behavior as the two controls above.
var _movement_input_controller = null

## The injected MoveActionControl (presentation/MoveActionControl.gd,
## FEAT-167) this view locks once an EncounterResultEvent is received.
## Optional, same no-op-if-null behavior as the other controls above.
var _move_action_control = null

## The injected VerbBarView (presentation/verb_bar_view.gd, FEAT-177 /
## US-013) this view locks once an EncounterResultEvent is received —
## extends the SAME lock mechanism to the Layer 1 verb bar so no verb
## button remains interactive post-resolution. Optional, same
## no-op-if-null behavior as the other controls above.
var _verb_bar_view = null

## The injected SelectionOverlay (presentation/selection_overlay.gd,
## FEAT-177 / US-013) this view locks once an EncounterResultEvent is
## received — extends the SAME lock mechanism to any open Layer 2
## selection so a pending Strike/Step/Stride target/hex pick can never
## resolve post-resolution. Optional, same no-op-if-null behavior as the
## other controls above.
var _selection_overlay = null

## True once an EncounterResultEvent has been processed and the result is
## being displayed.
var _shown: bool = false

## The exact text currently displayed ("Win" / "Loss" / "" before any
## EncounterResultEvent has arrived).
var _result_text: String = ""

@onready var _result_label: Label = $ResultLabel


func _ready() -> void:
	# The root Control must not eat battlefield or UI clicks — only the label
	# itself is interactive-adjacent (display only). Mirrors status_panel_view.gd,
	# event_log_view.gd, and initiative_view.gd's established MOUSE_FILTER_IGNORE pattern.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _result_label != null:
		_result_label.visible = false
		_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_result_label.text = ""


## configure(strike_action_control, end_turn_control, movement_input_controller,
##           move_action_control, verb_bar_view, selection_overlay) -> void
## — injects the combat input controls this view disables once shown
## (US-012; movement_input_controller added by FEAT-005 / US-005;
## move_action_control added by FEAT-167; verb_bar_view/selection_overlay
## added by FEAT-177 / US-013). All six parameters are OPTIONAL (default
## null); passing null for any simply means this view will not attempt to
## lock that control. Safe to call repeatedly (e.g. once per turn,
## mirroring the other controls' configure() contracts) with no leaked
## state. `movement_input_controller`/`move_action_control`/
## `verb_bar_view`/`selection_overlay` are appended as the LAST parameters,
## in the order they were introduced, so pre-existing callers/tests using
## fewer arguments are unaffected.
func configure(strike_action_control = null, end_turn_control = null, movement_input_controller = null, move_action_control = null, verb_bar_view = null, selection_overlay = null) -> void:
	_strike_action_control = strike_action_control
	_end_turn_control = end_turn_control
	_movement_input_controller = movement_input_controller
	_move_action_control = move_action_control
	_verb_bar_view = verb_bar_view
	_selection_overlay = selection_overlay


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

	lock_all_controls()
	result_shown.emit(_result_text)


## lock_all_controls() -> void — the single, idempotent post-resolution lock
## operation (FEAT-005 / US-005 / FR-011 / ADR-005: the FEAT-162 lock-wiring
## logic migrated from the removed scenes/battlefield/ResultScreen.gd,
## reimplemented here uniformly across Strike, EndTurn, AND Movement).
## Permanently locks every injected control via its EXISTING lock() API (see
## file-level doc — no new method added to any of the three controls,
## ADR-002/CR-001). FEAT-137 / DEF-004: lock() is persistent/sticky, unlike
## the one-time configure()-clear this used to perform. Called automatically
## once, from on_encounter_result_event(), but also exposed publicly so
## callers (composition root, tests) may trigger the SAME operation
## directly. Idempotent — safe to call any number of times: each injected
## control's own lock() is itself idempotent, so a repeated call produces no
## additional side effects beyond the first (see file-level doc).
func lock_all_controls() -> void:
	if _strike_action_control != null:
		_strike_action_control.lock()
	if _end_turn_control != null:
		_end_turn_control.lock()
	if _movement_input_controller != null:
		_movement_input_controller.lock()
	if _move_action_control != null:
		_move_action_control.lock()
	if _verb_bar_view != null:
		_verb_bar_view.lock()
	if _selection_overlay != null:
		_selection_overlay.lock()


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
