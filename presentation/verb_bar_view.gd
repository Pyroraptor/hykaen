## presentation/verb_bar_view.gd — VerbBarView (FEAT-004 / US-004/FR-001)
##
## Presentation layer (Clean Architecture): the Layer 1 verb bar — the steel
## thread's entry_point ("the Layer 1 verb bar renders with correctly gated
## ... controls"). Renders exactly ONE control per verb yielded by the
## injected registry's list_verbs() — there is NO hardcoded per-verb UI (no
## "if verb_id == 'STRIKE'" branching anywhere in this file) so a future verb
## (e.g. Cast a Spell) renders here automatically the moment it is
## registered, with zero changes to this file (mirrors the extensibility
## guarantee core/application/verb_registry.py's VerbRegistry already proves
## at the pytest layer, see tests/pytest/test_verb_registry.py).
##
## registry contract (duck-typed — VerbBarView never inspects a concrete
## class, only calls these four methods):
##   - list_verbs() -> Array[Dictionary]; each Dictionary carries at least a
##     "verb_id" (String) key, mirroring core/application/verb_registry.py's
##     VerbDescriptor.verb_id field. (VerbRegistry itself is a pytest-only,
##     zero-Godot-import Python module per ADR-004/ADR-001 and is therefore
##     never imported or instantiated here directly — this Dictionary shape
##     is the GDScript-side projection of that SAME contract, kept in sync
##     by the composition root that supplies the concrete registry, e.g.
##     MainScene.gd.)
##   - is_available(verb_id: String) -> bool
##   - enter_selection(verb_id: String) -> Variant — a Layer 2 selection
##     descriptor; VerbBarView never inspects its shape, only forwards it via
##     verb_selection_entered.
##   - execute(verb_id: String, selection = null) -> Variant — a resolution
##     result; VerbBarView never inspects its shape, only forwards it via
##     verb_executed.
##
## THE CORE US-004 CONTRACT: pressing a verb button calls
## registry.enter_selection(verb_id) — entering that verb's Layer 2
## selection mode — NEVER registry.execute(verb_id) directly, EXCEPT for
## END_TURN, which has no Layer 2 (design notes: "End Turn -> ends the turn
## ... no Layer 2") and therefore calls registry.execute(END_TURN) directly
## instead. This one exception is the ONLY verb-identity check this file
## performs — every other aspect of rendering/dispatch is fully generic over
## whatever registry.list_verbs() returns (ADR-004's "no if/elif verb_id ==
## ... branching" discipline, mirrored here at the presentation boundary
## rather than re-implemented as new domain dispatch logic).
##
## Availability gating: configure() renders every verb's button disabled
## exactly when registry.is_available(verb_id) is false at that moment.
## refresh_availability() re-queries is_available() for every already-
## rendered verb WITHOUT rebuilding the button set — intended to be called
## by the composition root once per turn-start/action-resolution (design
## notes: "queries availability() each frame/turn-start to gate enabled
## state") so a stale-availability button is never left clickable after the
## game state that determined it has changed.
##
## Post-resolution lock (FEAT-177 / US-013, extending the EXISTING
## presentation/result_screen_view.gd lock mechanism -- not a new one):
## lock() permanently disables every rendered verb button and permanently
## rejects press() from that point on, mirroring presentation/
## movement_input_controller.gd's/presentation/end_turn_control.gd's
## sticky lock()/is_locked() contract EXACTLY, including the SAME
## ERR_ENCOUNTER_ALREADY_RESOLVED error code. Sticky: neither a later
## configure() (rebuild) nor refresh_availability() may ever re-enable a
## button once locked -- a stray active_actor_changed/turn_started re-fire
## after the encounter has concluded must not resurrect a clickable verb
## button (the same DEF-004/DEF-001 class of regression the other three
## controls already guard against).

class_name VerbBarView
extends Control

## Mirrors core/application/verb_registry.py's END_TURN literal exactly —
## the ONE verb_id this file branches on (see file-level doc). Kept as a
## local constant (rather than importing the Python module, which is
## impossible from GDScript / would violate ADR-001's engine-purity split)
## so this file's single special case is explicit and greppable.
const END_TURN: String = "END_TURN"

## The SAME sticky post-resolution error code presentation/
## movement_input_controller.gd / presentation/end_turn_control.gd already
## use (FEAT-177 / US-013).
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

## verb_selection_entered(verb_id, selection) — emitted after press()
## invokes registry.enter_selection(verb_id) for any non-END_TURN verb,
## carrying that call's return value verbatim. A future Layer 2
## SelectionOverlay MAY subscribe to drive its own UI; no subscriber is
## required for this control to work.
signal verb_selection_entered(verb_id: String, selection)

## verb_executed(verb_id, result) — emitted after press() invokes
## registry.execute(verb_id) directly for END_TURN (the only verb with no
## Layer 2), carrying that call's return value verbatim.
signal verb_executed(verb_id: String, result)

## The injected registry (see file-level doc for its duck-typed contract) —
## VerbBarView never constructs one itself.
var _registry = null

## verb_id (String) -> Button, one per currently rendered verb, in
## registration order.
var _buttons: Dictionary = {}

## The verb_id order buttons were last rendered in — mirrors
## presentation/strike_action_control.gd's _selectable_targets ordering
## convention (list order preserved end to end).
var _verb_ids: Array = []

## True once lock() has been called (FEAT-177 / US-013) — permanently
## disables every rendered button and permanently rejects press(), sticky
## across any later configure()/refresh_availability() call.
var _locked: bool = false

@onready var _buttons_container: HBoxContainer = $ButtonsContainer


## configure(registry) -> void — injects the CURRENT registry and rebuilds
## one Button per registry.list_verbs() entry, each gated disabled/enabled
## by registry.is_available(verb_id) at this moment. Safe to call repeatedly
## (e.g. a fresh registry each encounter) with no leaked button state.
func configure(registry) -> void:
	_registry = registry
	_rebuild_buttons()


## get_button_count() -> int — number of verb buttons currently rendered
## (mirrors presentation/strike_action_control.gd's get_button_count()).
func get_button_count() -> int:
	return _buttons.size()


## get_verb_ids() -> Array[String] — every currently rendered verb_id, in
## registration order.
func get_verb_ids() -> Array:
	return _verb_ids.duplicate()


## get_button(verb_id) -> Button or null — the rendered Button for verb_id,
## for direct test inspection/press simulation (mirrors
## presentation/end_turn_control.gd exposing its single $Button, generalized
## here to a lookup since VerbBarView renders a variable set of buttons).
func get_button(verb_id: String) -> Button:
	return _buttons.get(verb_id, null)


## refresh_availability() -> void — re-queries registry.is_available() for
## every currently rendered verb and updates each button's disabled state,
## WITHOUT rebuilding the button set (no flicker/no lost button identity).
## Intended to be called once per turn-start / after any action resolves
## (design notes' observability note), so gating never goes stale. No-op
## before any configure() call. Sticky post-resolution (FEAT-177 / US-013):
## once locked, this is a no-op — a stray call must never re-enable a
## button.
func refresh_availability() -> void:
	if _registry == null:
		return
	if _locked:
		return
	for verb_id in _verb_ids:
		var button: Button = _buttons.get(verb_id, null)
		if button != null:
			button.disabled = not _registry.is_available(verb_id)


## lock() -> void — FEAT-177 (US-013 / FR-013): the post-resolution guard
## extending the EXISTING presentation/result_screen_view.gd lock mechanism
## to the Layer 1 verb bar. Permanently disables every currently rendered
## button and permanently rejects press() (returning
## {"ok": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}) from this point
## on — no registry method (enter_selection()/execute()) is reachable
## through press() once locked. Idempotent and sticky: safe to call more
## than once, and neither a later configure() nor refresh_availability()
## call may ever undo it (mirrors presentation/movement_input_controller.gd
## / presentation/end_turn_control.gd's lock() contract exactly).
func lock() -> void:
	_locked = true
	for button in _buttons.values():
		button.disabled = true


## is_locked() -> bool — true once lock() has been called.
func is_locked() -> bool:
	return _locked


## press(verb_id) -> Variant — the player's chosen verb.
##
## When the registry is not configured, or verb_id does not name a
## currently rendered AND available verb, this is rejected here (no
## dispatch at all) and returns {"ok": false}.
##
## Otherwise:
##   - END_TURN: calls registry.execute(END_TURN) DIRECTLY — no Layer 2
##     transition, no enter_selection() call at all — emits verb_executed,
##     and returns that call's result verbatim.
##   - every other verb: calls registry.enter_selection(verb_id) — entering
##     Layer 2 selection mode, NEVER executing immediately — emits
##     verb_selection_entered, and returns that call's result verbatim.
func press(verb_id: String):
	if _locked:
		return {"ok": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}
	if _registry == null:
		return {"ok": false, "error": "ERR_NO_REGISTRY"}
	if not _buttons.has(verb_id):
		return {"ok": false, "error": "ERR_UNKNOWN_VERB"}
	if not _registry.is_available(verb_id):
		return {"ok": false, "error": "ERR_VERB_UNAVAILABLE"}

	if verb_id == END_TURN:
		var result = _registry.execute(verb_id)
		verb_executed.emit(verb_id, result)
		return result

	var selection = _registry.enter_selection(verb_id)
	verb_selection_entered.emit(verb_id, selection)
	return selection


# ── Internal helpers ─────────────────────────────────────────────────────

## _rebuild_buttons() -> void — recomputes _verb_ids/_buttons from
## _registry.list_verbs() and rebuilds one Button per entry. Clears any
## previously-rendered buttons first, so a repeated configure() call never
## leaks duplicate buttons (mirrors presentation/strike_action_control.gd's
## _rebuild_targets()).
func _rebuild_buttons() -> void:
	for button in _buttons.values():
		button.queue_free()
	_buttons.clear()
	_verb_ids = []

	if _registry == null:
		return

	for descriptor in _registry.list_verbs():
		var verb_id: String = descriptor.get("verb_id", "")
		if verb_id == "":
			continue
		_verb_ids.append(verb_id)

		var button := Button.new()
		button.name = "Verb_%s" % verb_id
		button.text = descriptor.get("label", verb_id)
		button.disabled = _locked or not _registry.is_available(verb_id)
		if _buttons_container != null:
			_buttons_container.add_child(button)
		button.pressed.connect(_on_verb_button_pressed.bind(verb_id))
		_buttons[verb_id] = button


func _on_verb_button_pressed(verb_id: String) -> void:
	press(verb_id)
