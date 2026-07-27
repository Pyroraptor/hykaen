## presentation/initiative_view.gd — InitiativeView (FEAT-009 / US-007)
##
## Presentation layer (Clean Architecture): a READ-ONLY projection of the
## domain-determined turn order, satisfying US-007's "sees ... initiative"
## steel-thread criterion. InitiativeView lists every combatant ordered by
## initiative_order, highlights whichever entry is currently active, and
## marks a combatant as defeated once its CombatantDefeatedEvent arrives.
##
## InitiativeView is populated in exactly two ways, both non-mutating with
## respect to domain state (mirrors presentation/status_panel_view.gd,
## ADR-003):
##   1. load_combatants(view_models) — an initial SNAPSHOT load performed
##      once at boot by the composition root (MainScene.gd). `view_models`
##      is an Array of duck-typed Dictionaries (see load_combatants() doc
##      below) sorted by `initiative_order` (descending — highest acts
##      first, matching core/combat/encounter.gd's initiative-roll sort).
##      The FIRST entry in the resulting order is marked active by default,
##      since that combatant is the one whose turn it is when the encounter
##      begins.
##   2. on_round_event(event) / on_turn_advanced_event(event) /
##      on_combatant_defeated_event(event) — incremental updates driven
##      exclusively by typed round events (core/rules/round_events.gd) or
##      duck-typed Dictionaries carrying the same shape (ADR-003:
##      Presentation subscribes to EventSinkPort broadcasts, never polls
##      domain state). A TurnAdvancedEvent-shaped payload (carrying
##      `active_combatant_id` and/or `active_combatant_name`) moves the
##      highlight; a CombatantDefeatedEvent-shaped payload (carrying `name`
##      and `defeated_by`, the core/rules/round_events.gd
##      RoundEvents.CombatantDefeatedEvent shape) visually marks that row
##      defeated and clears the highlight if it was the active combatant.
##
## InitiativeView MUST NOT call into either of the two Application-layer
## use cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a
## read-only projection, never a mutator of domain state (enforced by a
## source-inspection regression test,
## tests/unit/presentation/test_initiative_view.gd).
##
## Event duck-typing (`_event_has` / `_event_get`): events may arrive either
## as a typed core/rules/round_events.gd value object (a RefCounted with
## plain `var` fields) or as a plain Dictionary (as used by tests to
## "simulate" an event without depending on a concrete adapter/event-sink
## wiring). Both helpers read a field from either shape uniformly.

class_name InitiativeView
extends Control

## Row keys copied verbatim into each row's Dictionary (get_entry()'s return
## shape) from the view model passed to load_combatants().
const _ROW_FIELDS: Array = ["name", "initiative_order"]

## combatant_id (String) -> row Dictionary ({name, initiative_order}).
var _rows: Dictionary = {}

## Ordered Array[String] of combatant_id, descending by initiative_order —
## the turn order this view displays.
var _order: Array = []

## combatant name (String) -> combatant_id (String) — round events identify
## combatants by name (core/rules/round_events.gd), not by combatant_id, so
## incoming events are resolved through this lookup.
var _id_by_name: Dictionary = {}

## combatant_id (String) -> Label node, one per row, added as a child of
## this Control so the initiative list is visible when run inside the game.
var _labels: Dictionary = {}

## combatant_id (String) of the currently active/highlighted combatant, or
## "" if none (e.g. before load_combatants() or after the active combatant
## was defeated with no subsequent TurnAdvancedEvent).
var _active_combatant_id: String = ""

## combatant_id (String) -> true for every combatant marked defeated.
var _defeated: Dictionary = {}

@onready var _rows_container: VBoxContainer = $RowsContainer


## BUGFIX (post-iteration-E): this read-only projection panel is a Control on the
## right side of the battlefield. With the Control default MOUSE_FILTER_STOP it
## swallowed clicks on hexes (e.g. far Stride destinations) drawn beneath it, so
## only hexes in the clear central area were selectable. Make the panel and its
## row container transparent to mouse input (row Labels are set IGNORE at
## creation) so those clicks reach HexGridView's _unhandled_input.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _rows_container != null:
		_rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE


## load_combatants(view_models) → void — (re)populates the list from an
## initial snapshot, sorted descending by `initiative_order`. Each entry of
## `view_models` is a duck-typed Dictionary with keys:
##   combatant_id      (String)
##   name              (String)
##   initiative_order  (int) — higher acts first (descending sort)
## Clears any previously-loaded rows first, so a repeated call never leaks
## duplicate rows (mirrors status_panel_view.gd's load_combatants() reload
## contract). The first entry in the resulting order becomes the active
## combatant.
func load_combatants(view_models: Array) -> void:
	_rows.clear()
	_id_by_name.clear()
	_defeated.clear()
	_active_combatant_id = ""

	var sortable: Array = view_models.duplicate()
	sortable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("initiative_order", 0) > b.get("initiative_order", 0)
	)

	_order = []
	for view_model in sortable:
		var combatant_id: String = view_model.get("combatant_id", "")
		var row: Dictionary = {}
		for field in _ROW_FIELDS:
			row[field] = view_model.get(field, _default_for_field(field))
		_rows[combatant_id] = row
		_id_by_name[row["name"]] = combatant_id
		_order.append(combatant_id)

	if not _order.is_empty():
		_active_combatant_id = _order[0]

	_rebuild_labels()


## get_row_count() → int — number of combatants currently displayed.
func get_row_count() -> int:
	return _rows.size()


## get_ordered_combatant_ids() → Array[String] — the turn order currently
## displayed, descending by initiative_order.
func get_ordered_combatant_ids() -> Array:
	return _order.duplicate()


## get_entry(combatant_id) → Dictionary — a snapshot Dictionary with keys
## name/initiative_order for the given combatant, or an empty Dictionary if
## combatant_id is unknown.
func get_entry(combatant_id: String) -> Dictionary:
	return _rows.get(combatant_id, {}).duplicate()


## get_active_combatant_id() → String — the currently highlighted
## combatant_id, or "" if none.
func get_active_combatant_id() -> String:
	return _active_combatant_id


## is_active(combatant_id) → bool — true iff `combatant_id` is currently
## highlighted as the active combatant.
func is_active(combatant_id: String) -> bool:
	return combatant_id != "" and combatant_id == _active_combatant_id


## is_defeated(combatant_id) → bool — true iff `combatant_id` has been
## marked defeated by a CombatantDefeatedEvent.
func is_defeated(combatant_id: String) -> bool:
	return _defeated.get(combatant_id, false)


## get_row_text(combatant_id) → String — the exact text rendered on this
## combatant's Label, for display-level assertions.
func get_row_text(combatant_id: String) -> String:
	var label: Label = _labels.get(combatant_id, null)
	return label.text if label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes a
## TurnAdvancedEvent-shaped payload (carries `active_combatant_id` and/or
## `active_combatant_name`) and forwards it to on_turn_advanced_event();
## recognizes a CombatantDefeatedEvent-shaped payload (carries `name` and
## `defeated_by`, matching core/rules/round_events.gd's
## RoundEvents.CombatantDefeatedEvent) and forwards it to
## on_combatant_defeated_event(). Any other/unrecognized event shape is a
## silent no-op — InitiativeView only reacts to events it understands, never
## errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_has(event, "active_combatant_id") or _event_has(event, "active_combatant_name"):
		on_turn_advanced_event(event)
	elif _event_has(event, "defeated_by"):
		on_combatant_defeated_event(event)


## on_turn_advanced_event(event) → void — moves the active-combatant
## highlight to the entry identified by `event`. `event` must carry either:
##   `active_combatant_id`   (String) — matched directly against a loaded row
##   `active_combatant_name` (String) — resolved through the name->id lookup
##     established by load_combatants(), used when `active_combatant_id` is
##     absent or does not match a loaded row.
## An event identifying a combatant this view was never loaded with is a
## silent no-op — the highlight is left unchanged.
func on_turn_advanced_event(event) -> void:
	var combatant_id: String = _event_get(event, "active_combatant_id", "")
	if combatant_id == "" or not _rows.has(combatant_id):
		var active_name: String = _event_get(event, "active_combatant_name", "")
		combatant_id = _id_by_name.get(active_name, "")

	if combatant_id == "" or not _rows.has(combatant_id):
		return

	_active_combatant_id = combatant_id
	_rebuild_labels()


## on_combatant_defeated_event(event) → void — visually marks the target
## combatant defeated in response to one CombatantDefeatedEvent. `event`
## must carry `name` (String) identifying the combatant by name (matching
## the `name` supplied to load_combatants()), mirroring
## core/rules/round_events.gd's RoundEvents.CombatantDefeatedEvent shape. If
## the defeated combatant was the active one, the highlight is cleared (no
## combatant is active until the next TurnAdvancedEvent). A `name` with no
## matching row (e.g. an event for a combatant this view was never loaded
## with) is a silent no-op.
func on_combatant_defeated_event(event) -> void:
	var name: String = _event_get(event, "name", "")
	var combatant_id: String = _id_by_name.get(name, "")
	if combatant_id == "" or not _rows.has(combatant_id):
		return

	_defeated[combatant_id] = true
	if _active_combatant_id == combatant_id:
		_active_combatant_id = ""

	_rebuild_labels()


# ── Internal helpers ─────────────────────────────────────────────────────

func _default_for_field(field: String):
	match field:
		"name":
			return ""
		_:
			return 0


## _rebuild_labels() → void — recreates every row Label from the current
## `_order`/`_rows`/`_active_combatant_id`/`_defeated` state. Recreating
## (rather than mutating in place) keeps display order in sync with `_order`
## even though `_order` is only ever (re)established by load_combatants().
func _rebuild_labels() -> void:
	if _rows_container != null:
		for child in _rows_container.get_children():
			_rows_container.remove_child(child)
			child.queue_free()
	_labels.clear()

	for position in range(_order.size()):
		var combatant_id: String = _order[position]
		var label := Label.new()
		label.name = "Row_%s" % combatant_id
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _rows_container != null:
			_rows_container.add_child(label)
		_labels[combatant_id] = label
		_update_label(combatant_id, position)


func _update_label(combatant_id: String, position: int) -> void:
	var label: Label = _labels.get(combatant_id, null)
	if label == null:
		return

	var row: Dictionary = _rows.get(combatant_id, {})
	var is_defeated_row: bool = _defeated.get(combatant_id, false)
	var marker: String = "-> " if is_active(combatant_id) else "   "
	var defeated_suffix: String = " (Defeated)" if is_defeated_row else ""

	label.text = "%s%d. %s (Initiative %d)%s" % [
		marker,
		position + 1,
		row.get("name", ""),
		row.get("initiative_order", 0),
		defeated_suffix,
	]
	label.modulate = Color(0.5, 0.5, 0.5, 1.0) if is_defeated_row else Color(1.0, 1.0, 1.0, 1.0)


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## InitiativeView never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
