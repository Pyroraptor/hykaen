## presentation/event_log_view.gd — EventLogView (FEAT-010 / US-008)
##
## Presentation layer (Clean Architecture): an APPEND-ONLY, read-only
## projection subscribed exclusively to EventSinkPort broadcasts, satisfying
## US-008's "sees a human-readable combat log" steel-thread criterion. This
## is the primary player-facing observability surface for the steel thread —
## every AttackEvent / CombatantDefeatedEvent / EncounterResultEvent is
## rendered as a chronologically ordered, human-readable entry.
##
## EventLogView is populated in exactly one way, mirroring
## presentation/status_panel_view.gd and presentation/initiative_view.gd
## (ADR-003: Presentation subscribes to EventSinkPort broadcasts, never polls
## or mutates domain state):
##   on_round_event(event) / on_attack_event(event) /
##   on_combatant_defeated_event(event) / on_encounter_result_event(event) —
##   incremental appends driven exclusively by typed round events
##   (core/rules/round_events.gd) or duck-typed Dictionaries carrying the
##   same shape. Each recognized event appends exactly one entry; there is no
##   load_combatants()-style snapshot seed, since the log has no initial
##   state — it starts empty and only ever grows (append-only).
##
## Chronological ordering (US-008 / test_criteria): EventLogView assigns
## each entry a strictly monotonically increasing `sequence_number` at the
## moment it is appended, and entries are ALWAYS rendered in that append
## (dispatch) order — never re-sorted by the domain `round` field an event
## happens to carry. This matches an append-only log's real-world semantics:
## "chronological" means the order entries actually arrived at this view,
## not the in-fiction round number they describe.
##
## EventLogView MUST NOT call into either of the two Application-layer use
## cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a read-only
## projection, never a mutator of domain state (enforced by a
## source-inspection regression test,
## tests/unit/presentation/test_event_log_view.gd).
##
## Event duck-typing (`_event_has` / `_event_get`): events may arrive either
## as a typed core/rules/round_events.gd value object (a RefCounted with
## plain `var` fields) or as a plain Dictionary (as used by tests to
## "simulate" an event without depending on a concrete adapter/event-sink
## wiring). Both helpers read a field from either shape uniformly (mirrors
## presentation/status_panel_view.gd and presentation/initiative_view.gd).

class_name EventLogView
extends Control

## _entries — ordered Array[Dictionary] of every appended log entry, in
## strict append (dispatch) order. Each entry: {sequence_number, round, text}.
var _entries: Array = []

## _next_sequence_number — the sequence_number the NEXT appended entry will
## receive; incremented on every append, guaranteeing strict monotonicity
## regardless of what `round` value the underlying event carries.
var _next_sequence_number: int = 1

## _labels — one Label per appended entry, in the same append order as
## `_entries`, added as a child of this Control so the log is visible when
## run inside the game.
var _labels: Array = []

@onready var _rows_container: VBoxContainer = $RowsContainer


## get_entry_count() → int — number of entries currently in the log.
func get_entry_count() -> int:
	return _entries.size()


## get_entry(index) → Dictionary — a snapshot Dictionary
## ({sequence_number, round, text}) for the entry at append-order `index`, or
## an empty Dictionary if `index` is out of range.
func get_entry(index: int) -> Dictionary:
	if index < 0 or index >= _entries.size():
		return {}
	return _entries[index].duplicate()


## get_entry_text(index) → String — the human-readable text of the entry at
## append-order `index`, or "" if `index` is out of range.
func get_entry_text(index: int) -> String:
	return get_entry(index).get("text", "")


## get_sequence_numbers() → Array[int] — the sequence_number of every entry,
## in append order (strictly increasing by construction).
func get_sequence_numbers() -> Array:
	var numbers: Array = []
	for entry in _entries:
		numbers.append(entry.get("sequence_number", 0))
	return numbers


## get_row_text(index) → String — the exact text rendered on the Label for
## the entry at append-order `index`, for display-level assertions. "" if
## `index` is out of range.
func get_row_text(index: int) -> String:
	if index < 0 or index >= _labels.size():
		return ""
	var label: Label = _labels[index]
	return label.text if label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes:
##   - an AttackEvent-shaped payload (carries `attacker_name` and
##     `target_name`) → on_attack_event()
##   - a CombatantDefeatedEvent-shaped payload (carries `defeated_by`) →
##     on_combatant_defeated_event()
##   - an EncounterResultEvent-shaped payload (carries `outcome`) →
##     on_encounter_result_event()
## Any other/unrecognized event shape is a silent no-op — EventLogView only
## reacts to events it understands, never errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_has(event, "attacker_name") and _event_has(event, "target_name"):
		on_attack_event(event)
	elif _event_has(event, "defeated_by"):
		on_combatant_defeated_event(event)
	elif _event_has(event, "outcome"):
		on_encounter_result_event(event)


## on_attack_event(event) → void — appends one human-readable entry
## describing a resolved Strike. `event` must carry `attacker_name`,
## `target_name`, `hit` (bool), `crit` (bool), `damage_final` (int), and
## optionally `round` (int), matching core/rules/round_events.gd's
## RoundEvents.AttackEvent shape.
func on_attack_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var attacker_name: String = _event_get(event, "attacker_name", "")
	var target_name: String = _event_get(event, "target_name", "")
	var hit: bool = _event_get(event, "hit", false)
	var crit: bool = _event_get(event, "crit", false)
	var damage_final: int = _event_get(event, "damage_final", 0)

	var text: String
	if hit:
		var hit_label: String = "Critical Hit" if crit else "Hit"
		text = "Round %d: %s attacks %s — %s for %d damage." % [
			round_number, attacker_name, target_name, hit_label, damage_final,
		]
	else:
		text = "Round %d: %s attacks %s — Miss." % [round_number, attacker_name, target_name]

	_append_entry(round_number, text)


## on_combatant_defeated_event(event) → void — appends one human-readable
## entry describing a combatant's defeat. `event` must carry `name` and
## `defeated_by`, and optionally `round` (int), matching
## core/rules/round_events.gd's RoundEvents.CombatantDefeatedEvent shape.
func on_combatant_defeated_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var name: String = _event_get(event, "name", "")
	var defeated_by: String = _event_get(event, "defeated_by", "")

	var text: String = "Round %d: %s was defeated by %s." % [round_number, name, defeated_by]
	_append_entry(round_number, text)


## on_encounter_result_event(event) → void — appends one human-readable
## entry describing the encounter's terminal outcome. `event` must carry
## `outcome` and optionally `round` (int), matching
## core/rules/round_events.gd's RoundEvents.EncounterResultEvent shape.
func on_encounter_result_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var outcome: String = _event_get(event, "outcome", "")

	var text: String = "Round %d: Encounter concluded — %s." % [round_number, outcome]
	_append_entry(round_number, text)


# ── Internal helpers ─────────────────────────────────────────────────────

## _append_entry(round_number, text) → void — appends one entry with the
## next strictly-increasing sequence_number, and creates its Label in the
## SAME append order (never re-sorted), guaranteeing chronological
## (dispatch-order) rendering.
func _append_entry(round_number: int, text: String) -> void:
	var sequence_number: int = _next_sequence_number
	_next_sequence_number += 1

	_entries.append({
		"sequence_number": sequence_number,
		"round": round_number,
		"text": text,
	})

	var label := Label.new()
	label.name = "Entry_%d" % sequence_number
	label.text = text
	if _rows_container != null:
		_rows_container.add_child(label)
	_labels.append(label)


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## EventLogView never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
