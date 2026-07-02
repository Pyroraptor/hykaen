## scenes/battlefield/TurnOrderWidget.gd — TurnOrderWidget (FEAT-006 / US-006)
##
## Presentation layer (Clean Architecture): a READ-ONLY projection of the
## domain-determined turn order, rendered as the "turn order" surface that
## sits alongside scenes/battlefield/HexBattlefield.gd (FEAT-005) on the
## battlefield scene. Lists every combatant ordered descending by initiative
## (the design model's InitiativeOrder view over Combatant.initiative_score —
## realized here, as everywhere else in this codebase, via the
## `initiative_order` view-model field already built by MainScene.gd's
## _build_initiative_view_models() helper, so this widget introduces no new
## initiative-computation path of its own), and visually flags whichever
## entry is currently active.
##
## TurnOrderWidget is populated in exactly two ways, both non-mutating with
## respect to domain state (mirrors presentation/initiative_view.gd,
## ADR-003):
##   1. load_combatants(view_models) — an initial SNAPSHOT load. Each entry
##      of `view_models` is a duck-typed Dictionary with keys combatant_id/
##      name/initiative_order (see load_combatants() doc below). Sorted
##      descending by initiative_order (highest acts first, matching
##      core/combat/encounter.gd's initiative-roll sort). The FIRST entry in
##      the resulting order is marked active by default, since that
##      combatant is the one whose turn it is when the round begins. A
##      repeated call (e.g. a subsequent round) clears any previously-loaded
##      rows first, so this widget never accumulates duplicate/stale entries
##      across multiple simulated rounds.
##   2. on_round_event(event) / on_turn_advanced_event(event) — incremental
##      updates driven EXCLUSIVELY by RoundEvents.TurnAdvancedEvent
##      (core/rules/round_events.gd), emitted by
##      core/application/round_session.gd's RoundSession every time the
##      round-advancement use case's stepwise cycle (end_current_turn() /
##      advance_ai_turn()) moves the cursor to a new living, un-Spent
##      combatant (ADR-003: Presentation subscribes to EventSinkPort
##      broadcasts, never polls domain state). `event` may arrive either as
##      that typed value object or as a duck-typed Dictionary carrying the
##      same shape (active_combatant_id / active_combatant_name) — both are
##      used interchangeably by tests/gut/test_turn_order_widget.gd.
##
## TurnOrderWidget MUST NOT call into either of the two Application-layer use
## cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a read-only
## projection, never a mutator of domain state (enforced by a
## source-inspection regression test, tests/gut/test_turn_order_widget.gd).

class_name TurnOrderWidget
extends Control

## Row keys copied verbatim into each row's Dictionary (get_entry()'s return
## shape) from the view model passed to load_combatants().
const _ROW_FIELDS: Array = ["name", "initiative_order"]

## combatant_id (String) -> row Dictionary ({name, initiative_order}).
var _rows: Dictionary = {}

## Ordered Array[String] of combatant_id, descending by initiative_order —
## the turn order this widget displays.
var _order: Array = []

## combatant name (String) -> combatant_id (String) — TurnAdvancedEvent
## identifies combatants primarily by combatant_id, falling back to name
## (core/rules/round_events.gd), so incoming events are resolved through
## this lookup when no combatant_id match is found.
var _id_by_name: Dictionary = {}

## combatant_id (String) -> Label node, one per row, added as a child of
## this Control so the turn order is visible when run inside the game.
var _labels: Dictionary = {}

## combatant_id (String) of the currently active/highlighted combatant, or
## "" if none (e.g. before load_combatants()).
var _active_combatant_id: String = ""

@onready var _rows_container: VBoxContainer = $RowsContainer


## load_combatants(view_models) → void — (re)populates the list from an
## initial snapshot, sorted descending by `initiative_order`. Each entry of
## `view_models` is a duck-typed Dictionary with keys:
##   combatant_id      (String)
##   name              (String)
##   initiative_order  (int) — higher acts first (descending sort); the
##                             InitiativeOrder view over each combatant's
##                             initiative score.
## Clears any previously-loaded rows first, so a repeated call (e.g. loading
## a subsequent simulated round) never leaks duplicate/stale rows. The first
## entry in the resulting order becomes the active combatant.
func load_combatants(view_models: Array) -> void:
	_rows.clear()
	_id_by_name.clear()
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


## get_row_text(combatant_id) → String — the exact text rendered on this
## combatant's Label, for display-level assertions.
func get_row_text(combatant_id: String) -> String:
	var label: Label = _labels.get(combatant_id, null)
	return label.text if label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes a
## TurnAdvancedEvent-shaped payload (carries `active_combatant_id` and/or
## `active_combatant_name`) and forwards it to on_turn_advanced_event(). Any
## other/unrecognized event shape is a silent no-op — this widget only
## reacts to the one event shape that moves the turn-order highlight, never
## errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_has(event, "active_combatant_id") or _event_has(event, "active_combatant_name"):
		on_turn_advanced_event(event)


## on_turn_advanced_event(event) → void — moves the active-combatant
## highlight to the entry identified by `event`. `event` must carry either:
##   `active_combatant_id`   (String) — matched directly against a loaded row
##   `active_combatant_name` (String) — resolved through the name->id lookup
##     established by load_combatants(), used when `active_combatant_id` is
##     absent or does not match a loaded row.
## An event identifying a combatant this widget was never loaded with is a
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


# ── Internal helpers ─────────────────────────────────────────────────────

func _default_for_field(field: String):
	match field:
		"name":
			return ""
		_:
			return 0


## _rebuild_labels() → void — recreates every row Label from the current
## `_order`/`_rows`/`_active_combatant_id` state. Recreating (rather than
## mutating in place) guarantees no stale/duplicate Label ever survives a
## reload — the exact behavior tests/gut/test_turn_order_widget.gd verifies
## across multiple simulated rounds. Existing rows are removed from the tree
## IMMEDIATELY (not merely queue_free()'d) so a caller that reloads/advances
## several times within the same frame never observes a stale row still
## present among this Control's children — only actual memory deallocation
## is deferred to queue_free()'s usual end-of-frame cleanup.
func _rebuild_labels() -> void:
	for existing_label in _labels.values():
		if existing_label.get_parent() != null:
			existing_label.get_parent().remove_child(existing_label)
		existing_label.queue_free()
	_labels.clear()

	for position in range(_order.size()):
		var combatant_id: String = _order[position]
		var label := Label.new()
		label.name = "Row_%s" % combatant_id
		if _rows_container != null:
			_rows_container.add_child(label)
		_labels[combatant_id] = label
		_update_label(combatant_id, position)


func _update_label(combatant_id: String, position: int) -> void:
	var label: Label = _labels.get(combatant_id, null)
	if label == null:
		return

	var row: Dictionary = _rows.get(combatant_id, {})
	var marker: String = "-> " if is_active(combatant_id) else "   "

	label.text = "%s%d. %s (Initiative %d)" % [
		marker,
		position + 1,
		row.get("name", ""),
		row.get("initiative_order", 0),
	]
	label.modulate = Color(1.0, 0.9, 0.4, 1.0) if is_active(combatant_id) else Color(1.0, 1.0, 1.0, 1.0)


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## TurnOrderWidget never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
