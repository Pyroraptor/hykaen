## scenes/battlefield/ResultScreen.gd — ResultScreen (FEAT-010 / US-010)
##
## Presentation layer (Clean Architecture): the terminal projection that
## realizes the steel thread's exit_point — "A Win or Loss result screen is
## displayed after EncounterResultEvent fires, with the full event log and
## final combatant states visible." ResultScreen subscribes to the SAME typed
## round-event pipeline every other Presentation projection already
## subscribes to (ADR-003, EventSinkPort) and, on the ONE terminal event an
## encounter ever emits — RoundEvents.EncounterResultEvent
## (core/rules/round_events.gd) — becomes visible, renders "Win"/"Loss",
## renders the final combatant HP/state snapshot, renders the full ordered
## event log, and locks the battlefield input controllers so no further
## Strike/EndTurn input can ever reach a concluded encounter.
##
## Mirrors the prior iteration's presentation/result_screen_view.gd (FEAT-112
## / US-012), but scoped to this iteration's scenes/battlefield/ controllers
## (StrikeInputController / EndTurnController, FEAT-007/FEAT-008) rather than
## their presentation/ counterparts, and additionally responsible for
## rendering the final combatant snapshot and the full event log itself
## (US-010's exit_point explicitly calls out both as visible on the result
## screen) instead of relying on a second widget the caller must remember to
## also show.
##
## Outcome text mapping mirrors core/application/determine_outcome_use_case.gd's
## classify()/build_event() contract EXACTLY (the single classification
## authority, reused unchanged — ADR-002/CR-001): that use case classifies
## from the PLAYER party's perspective and returns 'won' when the enemies
## side is fully defeated, 'lost' when the party side is fully defeated.
## ResultScreen therefore renders:
##   outcome == "won"  -> "Win"
##   outcome == "lost" -> "Loss"
## No other outcome value ever reaches this view in production; an
## unrecognized value renders as "" (a defensive no-op display, matching
## every other Presentation projection's "unfamiliar event shape is a silent
## no-op" convention).
##
## Final combatant snapshot (US-010's "final combatant states" criterion):
## configure() is handed the LIVE combatant Dictionaries (the same references
## the action-resolution use case mutates in place throughout the encounter,
## exactly as MainScene.gd's _party/_enemies fields already are) — since
## Dictionaries are reference types in GDScript, reading hp_current/hp_max/
## name from them at the moment EncounterResultEvent fires yields the true
## final state with no separate bookkeeping of its own required.
##
## Full event log (US-010's "full event log" criterion): ResultScreen tracks
## every AttackEvent/CombatantDefeatedEvent/EncounterResultEvent it receives
## via on_round_event() into its OWN strictly append-ordered log (mirroring
## presentation/event_log_view.gd's approach), so this widget is fully
## self-contained and testable in isolation without depending on a second
## widget instance being wired correctly elsewhere.
##
## Locking the input controllers (US-010's "blocking further player input"
## criterion) calls each injected controller's EXISTING lock() API
## (scenes/battlefield/StrikeInputController.gd / scenes/battlefield/
## EndTurnController.gd, FEAT-010) — a persistent, sticky guard (unaffected
## by any later configure() call) rather than merely clearing their live
## target/session state once, so the guard survives even if something else
## reconfigures either controller afterward (defense in depth, mirroring the
## error_handling design note's "ENCOUNTER_ALREADY_RESOLVED is a defensive
## domain-level guard behind [the UI guard], in case the UI guard is
## bypassed"). Both injected controllers are OPTIONAL (configure() accepts
## either/both as null) so this view can be unit-tested in isolation.
##
## ResultScreen MUST NOT call into either of the two Application-layer use
## cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a read-only
## terminal projection, never a mutator of domain state (enforced by a
## source-inspection regression test, tests/gut/test_result_screen.gd).
##
## Event duck-typing (`_event_has` / `_event_get`): events may arrive either
## as a typed core/rules/round_events.gd value object (a RefCounted with
## plain `var` fields) or as a plain Dictionary (as used by tests to simulate
## an event without depending on a concrete adapter/event-sink wiring), the
## same convention already established by every other Presentation
## projection in this codebase.

class_name ResultScreen
extends Control

## result_shown(result_text) — emitted once, the first time an
## EncounterResultEvent is processed, carrying the exact text now displayed
## ("Win" or "Loss"). No subscriber is required for this view to work.
signal result_shown(result_text: String)

## The live combatant Dictionaries (party + enemies) this view reads the
## final HP/state snapshot from once shown. Injected via configure() —
## ResultScreen never constructs or loads these itself.
var _combatants: Array = []

## The injected StrikeInputController (scenes/battlefield/
## StrikeInputController.gd) this view locks once an EncounterResultEvent is
## received. Optional — a caller that never passes one sees no error, only
## no-op.
var _strike_input_controller = null

## The injected EndTurnController (scenes/battlefield/EndTurnController.gd)
## this view locks once an EncounterResultEvent is received. Optional, same
## as above.
var _end_turn_controller = null

## True once an EncounterResultEvent has been processed and the result is
## being displayed.
var _shown: bool = false

## The exact text currently displayed ("Win" / "Loss" / "" before any
## EncounterResultEvent has arrived).
var _result_text: String = ""

## The final combatant snapshot ({combatant_id, name, hp_current, hp_max}
## per combatant), captured the moment EncounterResultEvent is processed.
var _final_snapshot: Array = []

## _log_entries — ordered Array[Dictionary] of every recognized round event
## this view has received, in strict append (dispatch) order — the "full
## event log" US-010 requires be visible on the result screen. Each entry:
## {sequence_number, round, text}.
var _log_entries: Array = []
var _next_sequence_number: int = 1

@onready var _result_label: Label = $ResultLabel
@onready var _snapshot_container: VBoxContainer = $SnapshotContainer
@onready var _log_container: VBoxContainer = $LogContainer

var _snapshot_labels: Array = []
var _log_labels: Array = []


func _ready() -> void:
	visible = false
	if _result_label != null:
		_result_label.text = ""
		_result_label.visible = false


## configure(combatants, strike_input_controller, end_turn_controller) -> void
##
## combatants             — the LIVE party+enemies combatant Dictionaries
##                           (see file-level doc) this view reads the final
##                           snapshot from once shown. Defaults to [].
## strike_input_controller — OPTIONAL; locked once shown (US-010).
## end_turn_controller     — OPTIONAL; locked once shown (US-010).
## Safe to call repeatedly with no leaked state.
func configure(combatants: Array = [], strike_input_controller = null, end_turn_controller = null) -> void:
	_combatants = combatants
	_strike_input_controller = strike_input_controller
	_end_turn_controller = end_turn_controller


## is_shown() -> bool — true once an EncounterResultEvent has been processed.
func is_shown() -> bool:
	return _shown


## get_result_text() -> String — the exact text currently displayed
## ("Win" / "Loss" / "" before any EncounterResultEvent has arrived).
func get_result_text() -> String:
	return _result_text


## get_label_text() -> String — the exact text rendered on the result Label,
## for display-level assertions.
func get_label_text() -> String:
	return _result_label.text if _result_label != null else ""


## get_final_snapshot() -> Array — the final combatant HP/state snapshot
## ({combatant_id, name, hp_current, hp_max}), captured when
## EncounterResultEvent was processed. [] before any result has been shown.
func get_final_snapshot() -> Array:
	var copy: Array = []
	for entry in _final_snapshot:
		copy.append(entry.duplicate())
	return copy


## get_snapshot_row_count() -> int — number of combatant rows currently
## rendered on the snapshot panel.
func get_snapshot_row_count() -> int:
	return _snapshot_labels.size()


## get_snapshot_row_text(index) -> String — the exact text rendered for the
## combatant snapshot row at `index`, for display-level assertions. "" if
## `index` is out of range.
func get_snapshot_row_text(index: int) -> String:
	if index < 0 or index >= _snapshot_labels.size():
		return ""
	var label: Label = _snapshot_labels[index]
	return label.text if label != null else ""


## get_event_log_entry_count() -> int — number of entries in the full,
## ordered event log this view has recorded.
func get_event_log_entry_count() -> int:
	return _log_entries.size()


## get_event_log_entry_text(index) -> String — the human-readable text of the
## log entry at append-order `index`, or "" if `index` is out of range.
func get_event_log_entry_text(index: int) -> String:
	if index < 0 or index >= _log_entries.size():
		return ""
	return _log_entries[index].get("text", "")


## get_event_log_row_text(index) -> String — the exact text rendered on the
## Label for the log entry at append-order `index`, for display-level
## assertions. "" if `index` is out of range.
func get_event_log_row_text(index: int) -> String:
	if index < 0 or index >= _log_labels.size():
		return ""
	var label: Label = _log_labels[index]
	return label.text if label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Records every
## AttackEvent/CombatantDefeatedEvent/EncounterResultEvent-shaped payload
## into the full ordered event log (US-010), and additionally forwards an
## EncounterResultEvent-shaped payload (carries `outcome`) to
## on_encounter_result_event(). Any other/unrecognized event shape is a
## silent no-op — ResultScreen only reacts to events it understands, never
## errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return

	if _event_has(event, "attacker_name") and _event_has(event, "target_name"):
		_append_log_entry(_format_attack_event(event))
	elif _event_has(event, "defeated_by"):
		_append_log_entry(_format_defeated_event(event))
	elif _event_has(event, "outcome"):
		_append_log_entry(_format_result_event(event))
		on_encounter_result_event(event)


## on_encounter_result_event(event) → void — renders "Win"/"Loss", the final
## combatant snapshot, and the full event log for the given
## EncounterResultEvent-shaped payload, and locks all injected combat input
## controllers (US-010). `event` must carry `outcome` (String, "won" or
## "lost" — see core/application/determine_outcome_use_case.gd). Idempotent:
## a second EncounterResultEvent (should not occur in production — it is a
## terminal, once-only event) simply re-renders/re-locks rather than erroring.
func on_encounter_result_event(event) -> void:
	var outcome: String = _event_get(event, "outcome", "")
	_result_text = _text_for_outcome(outcome)
	_shown = true
	visible = true

	if _result_label != null:
		_result_label.text = _result_text
		_result_label.visible = true

	_final_snapshot = _build_final_snapshot()
	_render_snapshot()
	_render_log()
	_lock_input_controllers()

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


## _build_final_snapshot() -> Array — one Dictionary per injected combatant,
## read from the LIVE combatant Dictionaries handed to configure() at the
## moment the encounter concluded (see file-level doc).
func _build_final_snapshot() -> Array:
	var snapshot: Array = []
	for combatant in _combatants:
		snapshot.append({
			"combatant_id": combatant.get("combatant_id", ""),
			"name":         combatant.get("name", ""),
			"hp_current":   combatant.get("hp_current", 0),
			"hp_max":       combatant.get("hp_max", combatant.get("hp_current", 0)),
		})
	return snapshot


func _render_snapshot() -> void:
	if _snapshot_container != null:
		for child in _snapshot_container.get_children():
			child.queue_free()
	_snapshot_labels = []

	for entry in _final_snapshot:
		var status: String = "Defeated" if entry.get("hp_current", 0) <= 0 else "Alive"
		var text: String = "%s — HP %d/%d (%s)" % [
			entry.get("name", ""), entry.get("hp_current", 0), entry.get("hp_max", 0), status,
		]
		var label := Label.new()
		label.name = "Snapshot_%d" % _snapshot_labels.size()
		label.text = text
		if _snapshot_container != null:
			_snapshot_container.add_child(label)
		_snapshot_labels.append(label)


func _render_log() -> void:
	if _log_container != null:
		for child in _log_container.get_children():
			child.queue_free()
	_log_labels = []

	for entry in _log_entries:
		var label := Label.new()
		label.name = "LogEntry_%d" % entry.get("sequence_number", 0)
		label.text = entry.get("text", "")
		if _log_container != null:
			_log_container.add_child(label)
		_log_labels.append(label)


func _append_log_entry(text: String) -> void:
	var sequence_number: int = _next_sequence_number
	_next_sequence_number += 1
	_log_entries.append({"sequence_number": sequence_number, "text": text})


func _format_attack_event(event) -> String:
	var round_number: int = _event_get(event, "round", 0)
	var attacker_name: String = _event_get(event, "attacker_name", "")
	var target_name: String = _event_get(event, "target_name", "")
	var hit: bool = _event_get(event, "hit", false)
	var crit: bool = _event_get(event, "crit", false)
	var damage_final: int = _event_get(event, "damage_final", 0)

	if hit:
		var hit_label: String = "Critical Hit" if crit else "Hit"
		return "Round %d: %s attacks %s — %s for %d damage." % [
			round_number, attacker_name, target_name, hit_label, damage_final,
		]
	return "Round %d: %s attacks %s — Miss." % [round_number, attacker_name, target_name]


func _format_defeated_event(event) -> String:
	var round_number: int = _event_get(event, "round", 0)
	var name: String = _event_get(event, "name", "")
	var defeated_by: String = _event_get(event, "defeated_by", "")
	return "Round %d: %s was defeated by %s." % [round_number, name, defeated_by]


func _format_result_event(event) -> String:
	var round_number: int = _event_get(event, "round", 0)
	var outcome: String = _event_get(event, "outcome", "")
	return "Round %d: Encounter concluded — %s." % [round_number, outcome]


## _lock_input_controllers() -> void — locks the injected
## StrikeInputController/EndTurnController via their EXISTING lock() API (see
## file-level doc — no duplicate/parallel disable surface).
func _lock_input_controllers() -> void:
	if _strike_input_controller != null:
		_strike_input_controller.lock()
	if _end_turn_controller != null:
		_end_turn_controller.lock()


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## ResultScreen never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
