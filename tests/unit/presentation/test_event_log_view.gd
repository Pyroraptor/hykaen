extends GutTest
## tests/unit/presentation/test_event_log_view.gd
##
## GUT test suite for FEAT-010 / US-008 — EventLogView is an append-only,
## read-only projection subscribed exclusively to EventSinkPort broadcasts
## (AttackEvent, CombatantDefeatedEvent, EncounterResultEvent), rendering
## human-readable, chronologically ordered log entries. This is the primary
## player-facing observability surface for the steel thread.
##
## Verifies:
##   1. A simulated AttackEvent signal produces a correctly formatted,
##      human-readable log entry.
##   2. Simulated CombatantDefeatedEvent and EncounterResultEvent signals
##      each produce correctly formatted entries.
##   3. Entries are appended and rendered in strict sequence_number/
##      chronological order for a batch of out-of-order-dispatched test
##      signals (i.e. append order — the log never re-sorts by the domain
##      `round` field carried on each event).
##   4. Code-review assertion (source-inspection): event_log_view.gd
##      contains no direct reference to resolve_action_use_case or
##      run_round_use_case — EventLogView must never call into a use case
##      (read-only projection).

const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")

const EVENT_LOG_VIEW_PATH: String = "res://presentation/event_log_view.gd"


## _FakeEventEmitter — a minimal Node exposing custom Signals, used to
## simulate round-event signals arriving at EventLogView the way a future
## SignalEventSinkAdapter (design notes, ADR-003) would broadcast one —
## WITHOUT depending on that adapter (out of scope for this feature).
class _FakeEventEmitter:
	extends Node
	signal attack_event(event)
	signal combatant_defeated_event(event)
	signal encounter_result_event(event)


var _log = null


func before_each() -> void:
	_log = EventLogViewScene.instantiate()
	add_child_autofree(_log)


# ── Criterion 1: a simulated AttackEvent signal produces a correctly ───────
# ── formatted, human-readable log entry ─────────────────────────────────────

func test_attack_event_signal_produces_hit_entry() -> void:
	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.attack_event.connect(_log.on_attack_event)

	emitter.emit_signal("attack_event", {
		"round": 1,
		"attacker_name": "Titus",
		"target_name": "Skeleton",
		"hit": true,
		"crit": false,
		"damage_final": 6,
	})

	assert_eq(_log.get_entry_count(), 1, "one AttackEvent must produce exactly one log entry")
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Titus", "entry must name the attacker")
	assert_string_contains(text, "Skeleton", "entry must name the target")
	assert_string_contains(text, "6", "entry must show the damage dealt")
	assert_string_contains(text, "Hit", "entry must indicate the attack hit")


func test_attack_event_signal_produces_miss_entry() -> void:
	_log.on_attack_event({
		"round": 1,
		"attacker_name": "Skeleton",
		"target_name": "Titus",
		"hit": false,
		"crit": false,
		"damage_final": 0,
	})

	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Skeleton", "entry must name the attacker")
	assert_string_contains(text, "Titus", "entry must name the target")
	assert_string_contains(text, "Miss", "entry must indicate the attack missed")


func test_attack_event_signal_produces_critical_hit_entry() -> void:
	_log.on_attack_event({
		"round": 2,
		"attacker_name": "Titus",
		"target_name": "Skeleton",
		"hit": true,
		"crit": true,
		"damage_final": 12,
	})

	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Critical", "entry must call out a critical hit")


func test_round_event_with_production_attack_event_value_object() -> void:
	# Exercises the ACTUAL core/rules/round_events.gd shape — confirms
	# EventLogView works against the real production event type, not only
	# the Dictionary test double above.
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	var attack_event = RoundEventsClass.AttackEvent.new(
		1, "Titus", "Skeleton", 17, "ac", 14, true, false, 5
	)
	_log.on_round_event(attack_event)

	assert_eq(_log.get_entry_count(), 1)
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Titus")
	assert_string_contains(text, "Skeleton")
	assert_string_contains(text, "5")


# ── Criterion 2: CombatantDefeatedEvent and EncounterResultEvent signals ───
# ── each produce correctly formatted entries ────────────────────────────────

func test_combatant_defeated_event_signal_produces_entry() -> void:
	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.combatant_defeated_event.connect(_log.on_combatant_defeated_event)

	emitter.emit_signal("combatant_defeated_event", {
		"round": 3,
		"name": "Skeleton",
		"defeated_by": "Titus",
	})

	assert_eq(_log.get_entry_count(), 1)
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Skeleton", "entry must name the defeated combatant")
	assert_string_contains(text, "Titus", "entry must name who defeated them")
	assert_string_contains(text, "defeated", "entry must use human-readable 'defeated' wording")


func test_encounter_result_event_signal_produces_entry() -> void:
	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.encounter_result_event.connect(_log.on_encounter_result_event)

	emitter.emit_signal("encounter_result_event", {
		"round": 4,
		"outcome": "win",
	})

	assert_eq(_log.get_entry_count(), 1)
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "win", "entry must show the encounter outcome")


func test_round_event_with_production_combatant_defeated_event_value_object() -> void:
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(2, "Skeleton", "Titus")
	_log.on_round_event(defeated_event)

	assert_eq(_log.get_entry_count(), 1)
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "Skeleton")
	assert_string_contains(text, "Titus")


func test_round_event_with_production_encounter_result_event_value_object() -> void:
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	var result_event = RoundEventsClass.EncounterResultEvent.new(5, "loss")
	_log.on_round_event(result_event)

	assert_eq(_log.get_entry_count(), 1)
	var text: String = _log.get_entry_text(0)
	assert_string_contains(text, "loss")


# ── Criterion 3: entries appended/rendered in strict sequence_number/ ──────
# ── chronological order for out-of-order-dispatched test signals ───────────

func test_entries_are_appended_in_dispatch_order_not_round_order() -> void:
	const RoundEventsClass = preload("res://core/rules/round_events.gd")

	# Deliberately dispatched with `round` values out of numeric order
	# (3, 1, 2) — the log must preserve DISPATCH order, never re-sort by the
	# domain round field.
	var first_event = RoundEventsClass.AttackEvent.new(3, "Titus", "Skeleton", 10, "ac", 14, true, false, 4)
	var second_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Marigold", "Skeleton")
	var third_event = RoundEventsClass.EncounterResultEvent.new(2, "win")

	_log.on_round_event(first_event)
	_log.on_round_event(second_event)
	_log.on_round_event(third_event)

	assert_eq(_log.get_entry_count(), 3)

	var texts: Array = [
		_log.get_entry_text(0),
		_log.get_entry_text(1),
		_log.get_entry_text(2),
	]
	assert_string_contains(texts[0], "Skeleton", "entry 0 must be the first-dispatched AttackEvent")
	assert_string_contains(texts[1], "Marigold", "entry 1 must be the second-dispatched CombatantDefeatedEvent")
	assert_string_contains(texts[2], "win", "entry 2 must be the third-dispatched EncounterResultEvent")


func test_sequence_numbers_are_strictly_increasing_in_dispatch_order() -> void:
	_log.on_round_event({"round": 5, "attacker_name": "A", "target_name": "B", "hit": true, "crit": false, "damage_final": 1})
	_log.on_round_event({"round": 1, "attacker_name": "C", "target_name": "D", "hit": false, "crit": false, "damage_final": 0})
	_log.on_round_event({"round": 3, "name": "D", "defeated_by": "C"})

	var sequence_numbers: Array = _log.get_sequence_numbers()
	assert_eq(sequence_numbers.size(), 3)
	assert_true(sequence_numbers[0] < sequence_numbers[1], "sequence_number must strictly increase with append order")
	assert_true(sequence_numbers[1] < sequence_numbers[2], "sequence_number must strictly increase with append order")


func test_row_text_rendered_in_container_matches_append_order() -> void:
	_log.on_round_event({"round": 9, "attacker_name": "First", "target_name": "X", "hit": true, "crit": false, "damage_final": 1})
	_log.on_round_event({"round": 0, "attacker_name": "Second", "target_name": "X", "hit": true, "crit": false, "damage_final": 1})

	assert_string_contains(_log.get_row_text(0), "First")
	assert_string_contains(_log.get_row_text(1), "Second")


func test_unrecognized_event_shape_is_a_silent_noop() -> void:
	_log.on_round_event({"something": "unrelated"})
	assert_eq(_log.get_entry_count(), 0, "an unrecognized event shape must not create a log entry")


func test_null_event_is_a_silent_noop() -> void:
	_log.on_round_event(null)
	assert_eq(_log.get_entry_count(), 0)


# ── Criterion 4: code-review assertion — no direct use-case calls ──────────

func _read_source() -> String:
	var file := FileAccess.open(EVENT_LOG_VIEW_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/event_log_view.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"event_log_view.gd must never reference resolve_action_use_case (read-only projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"event_log_view.gd must never reference run_round_use_case (read-only projection)"
	)
