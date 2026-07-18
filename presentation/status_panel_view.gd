## presentation/status_panel_view.gd — StatusPanelView (FEAT-008 / US-006)
##
## Presentation layer (Clean Architecture): a READ-ONLY projection of each
## combatant's status (name, HP, Stamina, action budget, Spent, conditions)
## satisfying US-006's "sees ... status" steel-thread criterion.
##
## FEAT-009 (US-009 / FR-014, ADR-003): update_action_budget(actor_id, event)
## is a THIRD, narrower push-based update entry point — projecting an
## AttackEvent's post-Strike actor_updated_action_budget snapshot
## ({remaining, spent}) onto the acting combatant's row, called
## automatically from on_attack_event() below when the event resolves an
## attacker identity. Like on_round_event()/on_attack_event(), it is a pure
## read-only projection: it never calls into core/rules/action_economy.gd or
## any Application-layer use case, and it defensively no-ops + logs
## (push_warning(), never throws) when the field is absent — see its own doc
## below.
##
## StatusPanelView is populated in exactly two ways, both of which are
## non-mutating with respect to domain state:
##   1. load_combatants(view_models) — an initial SNAPSHOT load performed
##      once at boot by the composition root (MainScene.gd), mirroring how
##      presentation/hex_grid_view.gd's load_combatants() seeds the
##      battlefield. `view_models` is an Array of duck-typed Dictionaries
##      (see load_combatants() doc below) — StatusPanelView never reaches
##      into core/combat/encounter.gd, core/rules/action_economy.gd, or any
##      other domain/application object to pull this data itself.
##   2. on_round_event(event) / on_attack_event(event) — incremental updates
##      driven exclusively by the typed round events declared in
##      core/rules/round_events.gd (ADR-003: Presentation subscribes to
##      EventSinkPort broadcasts, never polls domain state). The composition
##      root forwards each event obtained from Encounter.get_round_events()
##      to on_round_event() the same way it already forwards them to the
##      ConsoleEventSinkAdapter (MainScene.gd) — no new port or use case is
##      introduced (ADR-002 / CR-001 guardrail).
##
## StatusPanelView MUST NOT call into either of the two Application-layer
## use cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a
## read-only projection, never a mutator of domain state. (Enforced by a
## source-inspection regression test,
## tests/unit/presentation/test_status_panel_view.gd.)
##
## Event duck-typing (`_event_get`): events may arrive either as a typed
## core/rules/round_events.gd value object (a RefCounted with plain `var`
## fields) or as a plain Dictionary (as used by tests to "simulate" an event
## without depending on the exact RoundEvents.AttackBroadcast field list).
## `_event_get()` reads a field from either shape uniformly. An AttackEvent
## carries `damage_final` (the production core/rules/round_events.gd shape);
## a `target_hp_after` field, when present, takes precedence — allowing a
## caller (or a future richer event shape) to supply the post-attack HP
## directly instead of having StatusPanelView compute it via subtraction.

class_name StatusPanelView
extends Control

## FEAT-015 (US-015 / FR-016): the SAME domain constant
## core/rules/flanking.gd / core/rules/resolution.gd use for the Off-Guard
## condition label — StatusPanelView reads/derives it from the domain
## rather than re-hardcoding the string "Off-Guard" itself (ADR-001:
## Presentation reads/derives from domain state only).
const FlankingClass = preload("res://core/rules/flanking.gd")

## Row keys copied verbatim into each row's status Dictionary
## (get_status()'s return shape) from the view model passed to
## load_combatants().
const _ROW_FIELDS: Array = [
	"name", "hp_current", "hp_max",
	"stamina_current", "stamina_max",
	"action_budget_remaining", "spent", "conditions",
]

## combatant_id (String) -> status Dictionary (see _ROW_FIELDS above).
var _rows: Dictionary = {}

## combatant name (String) -> combatant_id (String) — round events identify
## combatants by name (core/rules/round_events.gd AttackEvent.target_name),
## not by combatant_id, so incoming events are resolved through this lookup.
var _id_by_name: Dictionary = {}

## combatant_id (String) -> Label node, one per row, added as a child of
## this Control so the panel is visible when run inside the game.
var _labels: Dictionary = {}

@onready var _rows_container: VBoxContainer = $RowsContainer


## BUGFIX (post-iteration-E): this read-only projection panel is a Control that
## overlaps the battlefield play area. With the Control default
## MOUSE_FILTER_STOP it swallowed clicks on hexes (e.g. far Stride destinations)
## drawn beneath it, so only hexes in the clear central area were selectable.
## Make the panel and its row container transparent to mouse input (row Labels
## are set IGNORE at creation) so those clicks reach HexGridView's _unhandled_input.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _rows_container != null:
		_rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE


## load_combatants(view_models) → void — (re)populates the panel from an
## initial snapshot. Each entry of `view_models` is a duck-typed Dictionary
## with keys:
##   combatant_id            (String)
##   name                     (String)
##   hp_current, hp_max       (int)
##   stamina_current, stamina_max (int)
##   action_budget_remaining (int)
##   spent                    (bool)
##   conditions               (Array[String])
## Clears any previously-loaded rows first, so a repeated call never leaks
## duplicate rows (mirrors presentation/hex_grid_view.gd's load_combatants()
## reload contract).
func load_combatants(view_models: Array) -> void:
	for existing_label in _labels.values():
		existing_label.queue_free()
	_labels.clear()
	_rows.clear()
	_id_by_name.clear()

	for view_model in view_models:
		var combatant_id: String = view_model.get("combatant_id", "")
		var row: Dictionary = {}
		for field in _ROW_FIELDS:
			row[field] = view_model.get(field, _default_for_field(field))
		_rows[combatant_id] = row
		_id_by_name[row["name"]] = combatant_id
		_create_or_update_label(combatant_id)


## get_status(combatant_id) → Dictionary — a snapshot Dictionary with keys
## name/hp_current/hp_max/stamina_current/stamina_max/
## action_budget_remaining/spent/conditions for the given combatant, or an
## empty Dictionary if combatant_id is unknown.
func get_status(combatant_id: String) -> Dictionary:
	return _rows.get(combatant_id, {}).duplicate()


## get_row_count() → int — number of combatants currently displayed.
func get_row_count() -> int:
	return _rows.size()


## set_off_guard(combatant_id, is_off_guard) → void — FEAT-015 (US-015 /
## FR-016): toggles FlankingClass.OFF_GUARD_CONDITION ("Off-Guard") in the
## given combatant's displayed conditions list and refreshes its rendered
## row label, so the Off-Guard positional condition is visible in the
## per-combatant readout. StatusPanelView never computes flanking itself
## (that is core/rules/flanking.gd's Flanking.is_off_guard(), invoked by the
## composition root — MainScene.gd — as combatant positions change); this
## method only reflects a caller-supplied bool into the display, mirroring
## on_attack_event()'s existing "presentation reflects, never derives"
## contract. A combatant_id with no loaded row is a silent no-op (mirrors
## on_attack_event()'s unknown-combatant behavior).
func set_off_guard(combatant_id: String, is_off_guard: bool) -> void:
	if not _rows.has(combatant_id):
		return

	var row: Dictionary = _rows[combatant_id]
	var conditions: Array = row.get("conditions", [])
	var has_condition: bool = FlankingClass.OFF_GUARD_CONDITION in conditions

	if is_off_guard and not has_condition:
		conditions.append(FlankingClass.OFF_GUARD_CONDITION)
	elif not is_off_guard and has_condition:
		conditions.erase(FlankingClass.OFF_GUARD_CONDITION)

	row["conditions"] = conditions
	_create_or_update_label(combatant_id)


## is_off_guard(combatant_id) → bool — true iff the given combatant's
## currently displayed conditions include Off-Guard (FEAT-015 / US-015).
## Unknown combatant_id returns false.
func is_off_guard(combatant_id: String) -> bool:
	var row: Dictionary = _rows.get(combatant_id, {})
	return FlankingClass.OFF_GUARD_CONDITION in row.get("conditions", [])


## get_row_text(combatant_id) → String — the exact text rendered on this
## combatant's Label, for display-level assertions.
func get_row_text(combatant_id: String) -> String:
	var label: Label = _labels.get(combatant_id, null)
	return label.text if label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes an
## AttackEvent-shaped payload (carries `target_name` plus either
## `damage_final` or `target_hp_after`) and forwards it to on_attack_event().
## Any other/unrecognized event shape is a silent no-op — StatusPanelView
## only reacts to events it understands, never errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_get(event, "target_name", "") != "" and (
		_event_has(event, "damage_final") or _event_has(event, "target_hp_after")
	):
		on_attack_event(event)


## on_attack_event(event) → void — updates the target combatant's displayed
## HP in response to one resolved Strike. `event` must carry `target_name`
## (String) identifying the combatant by name (matching the `name` supplied
## to load_combatants()) and either:
##   `target_hp_after` (int) — the post-attack HP, used directly when present
##   `damage_final`     (int) — subtracted from the row's tracked hp_current
## (clamped at 0) when `target_hp_after` is absent.
## A target_name with no matching row (e.g. an event for a combatant this
## panel was never loaded with) is a silent no-op.
func on_attack_event(event) -> void:
	var target_name: String = _event_get(event, "target_name", "")
	var combatant_id: String = _id_by_name.get(target_name, "")
	if combatant_id != "" and _rows.has(combatant_id):
		var row: Dictionary = _rows[combatant_id]
		if _event_has(event, "target_hp_after"):
			row["hp_current"] = _event_get(event, "target_hp_after", row["hp_current"])
		elif _event_has(event, "damage_final"):
			var damage: int = _event_get(event, "damage_final", 0)
			row["hp_current"] = maxi(row.get("hp_current", 0) - damage, 0)

		_create_or_update_label(combatant_id)

	# ── FEAT-009 / US-009 / FR-014 (ADR-003): push the acting combatant's
	# post-resolution action-budget snapshot, when the event carries one.
	# Resolved by attacker_name -> combatant_id through the SAME _id_by_name
	# lookup used above for the target, so no second identity-resolution
	# rule is introduced. A Dictionary/event with no attacker_name (e.g. the
	# pre-FEAT-009 test doubles throughout this suite that only carry
	# target_name/damage_final) is simply not eligible for a budget update --
	# skipped silently, never a warning (the warning is reserved for a
	# resolvable actor whose event is missing the field entirely, see
	# update_action_budget() below). ─────────────────────────────────────────
	var attacker_name: String = _event_get(event, "attacker_name", "")
	if attacker_name != "":
		var attacker_id: String = _id_by_name.get(attacker_name, "")
		if attacker_id != "":
			update_action_budget(attacker_id, event)


## update_action_budget(actor_id, event) → void — FEAT-009 (US-009 / FR-014,
## ADR-003): projects `event`'s actor_updated_action_budget payload
## ({remaining: int, spent: bool}) onto actor_id's displayed row, AS A
## READ-ONLY PROJECTION — this method never reaches into
## core/rules/action_economy.gd or recomputes the budget itself, it only
## renders the value pushed to it (mirrors set_off_guard()'s
## "caller-supplied bool, presentation reflects, never derives" contract).
##
## `event` is duck-typed (a Dictionary or an Object/RefCounted value object,
## e.g. core/rules/round_events.gd's RoundEvents.AttackBroadcast) exactly like
## every other event entry point on this class (_event_get()). When `event`
## carries no actor_updated_action_budget (or a non-Dictionary value there --
## e.g. an older AttackEvent constructed before FEAT-009 added the field,
## which defaults to null), this is a DEFENSIVE no-op: push_warning() is
## logged and no row is mutated -- it never throws, so a partially-migrated
## event source can never crash the scene (design notes' "Status projection
## failure isolation").
##
## An actor_id with no loaded row (e.g. the acting combatant was never
## handed to load_combatants()) is also a silent no-op, matching every other
## unknown-combatant_id contract on this class (set_off_guard(), on_attack_event()).
func update_action_budget(actor_id: String, event) -> void:
	var budget = _event_get(event, "actor_updated_action_budget", null)
	if not (budget is Dictionary):
		push_warning(
			"StatusPanelView.update_action_budget: actor_updated_action_budget missing/invalid "
			+ "for actor_id=" + actor_id + " -- no-op"
		)
		return

	if not _rows.has(actor_id):
		return

	var row: Dictionary = _rows[actor_id]
	row["action_budget_remaining"] = budget.get("remaining", row.get("action_budget_remaining", 0))
	row["spent"] = budget.get("spent", row.get("spent", false))
	_create_or_update_label(actor_id)


## on_verb_action_budget_changed(actor_id, remaining, spent) → void —
## FEAT-178 (US-014 / FR-014, ADR-003): pushes a CALLER-SUPPLIED
## {remaining, spent} snapshot onto actor_id's displayed row -- a thin,
## explicit-argument wrapper over update_action_budget() (reusing its
## Dictionary-shape contract rather than forking a second mutation path,
## ADR-002), so callers with a plain (remaining: int, spent: bool) pair in
## hand (rather than an event-shaped Dictionary/Object) have a direct entry
## point. Exactly like update_action_budget(), StatusPanelView never
## queries or recomputes the budget itself here -- it only renders values
## the CALLER already queried/computed elsewhere (ADR-003's read-only-
## projection discipline, enforced by a dedicated source-inspection guard
## suite that this file must keep passing).
##
## Exists because Iteration E routed Strike/Step/Stride through the new
## two-layer verb flow (Layer 1 VerbBarView -> Layer 2 SelectionOverlay ->
## `_verb_registry`.execute()), but only Strike carries an AttackEvent for
## on_attack_event() to relay to update_action_budget() automatically. A
## Stride (core/rules/movement.gd Movement.stride()) also spends one action
## from the same shared per-round budget but emits no such event at all --
## so the composition root (MainScene.gd) reads its own live budget
## collaborator (a Presentation-layer responsibility per that collaborator's
## own doc) and calls THIS method immediately after a Stride resolves. A
## Step never spends an action (core/rules/movement.gd's file-level doc)
## and therefore never calls this method -- see tests/gut/
## test_status_bar_verb_flow_regression.gd for the regression coverage
## pinning all three verbs' status-bar behavior.
func on_verb_action_budget_changed(actor_id: String, remaining: int, spent: bool) -> void:
	update_action_budget(actor_id, {
		"actor_updated_action_budget": {"remaining": remaining, "spent": spent}
	})


# ── Internal helpers ─────────────────────────────────────────────────────

func _default_for_field(field: String):
	match field:
		"conditions":
			return []
		"spent":
			return false
		"name":
			return ""
		_:
			return 0


func _create_or_update_label(combatant_id: String) -> void:
	var row: Dictionary = _rows[combatant_id]
	var label: Label = _labels.get(combatant_id, null)
	if label == null:
		label = Label.new()
		label.name = "Row_%s" % combatant_id
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _rows_container != null:
			_rows_container.add_child(label)
		_labels[combatant_id] = label
	label.text = _format_row_text(row)


func _format_row_text(row: Dictionary) -> String:
	var conditions: Array = row.get("conditions", [])
	var conditions_text: String = ", ".join(conditions) if conditions.size() > 0 else "None"
	return "%s — HP %d/%d | Stamina %d/%d | Actions %d | Spent: %s | Conditions: %s" % [
		row.get("name", ""),
		row.get("hp_current", 0),
		row.get("hp_max", 0),
		row.get("stamina_current", 0),
		row.get("stamina_max", 0),
		row.get("action_budget_remaining", 0),
		"Yes" if row.get("spent", false) else "No",
		conditions_text,
	]


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## StatusPanelView never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
