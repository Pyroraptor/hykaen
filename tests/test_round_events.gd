extends GutTest
## tests/test_round_events.gd
##
## GUT test suite for core/rules/round_events.gd — Domain round/event value
## objects (FEAT-004 / US-004 / US-005 / ADR-004).
##
## Test criteria verified here:
##   1. AttackEvent, CombatantDefeatedEvent, EncounterResultEvent instantiate
##      with documented fields and are simple value objects (no
##      Node/SceneTree refs).
##   2. RoundHistoryEntry instantiates with round_number, cycle_index,
##      combatant_id, action_type, budget_remaining fields populated
##      correctly.
##   3. Value objects support equality/inspection sufficient for test
##      assertions (exported fields and to_dict()).

const RoundEventsClass = preload("res://core/rules/round_events.gd")


# ── AttackEvent ────────────────────────────────────────────────────────────────

func test_attack_event_instantiates_with_documented_fields() -> void:
	var ev = RoundEventsClass.AttackBroadcast.new(
		1, "Titus", "Goblin", 17, "ac", 14, true, false, 6
	)
	assert_eq(ev.round, 1, "round must be set")
	assert_eq(ev.attacker_name, "Titus", "attacker_name must be set")
	assert_eq(ev.target_name, "Goblin", "target_name must be set")
	assert_eq(ev.roll, 17, "roll must be set")
	assert_eq(ev.defense_type, "ac", "defense_type must be set")
	assert_eq(ev.defense_value, 14, "defense_value must be set")
	assert_true(ev.hit, "hit must be set")
	assert_false(ev.crit, "crit must be set")
	assert_eq(ev.damage_final, 6, "damage_final must be set")


func test_attack_event_is_refcounted_value_object() -> void:
	var ev = RoundEventsClass.AttackBroadcast.new()
	assert_true(ev is RefCounted, "AttackEvent must be a RefCounted")
	assert_false(ev is Node, "AttackEvent must NOT be a Node")


func test_attack_event_to_dict_matches_fields() -> void:
	var ev = RoundEventsClass.AttackBroadcast.new(
		2, "Goblin", "Titus", 9, "ac", 16, false, false, 0
	)
	var d: Dictionary = ev.to_dict()
	assert_eq(d["round"], 2, "to_dict round must match")
	assert_eq(d["attacker_name"], "Goblin", "to_dict attacker_name must match")
	assert_eq(d["target_name"], "Titus", "to_dict target_name must match")
	assert_eq(d["roll"], 9, "to_dict roll must match")
	assert_eq(d["defense_type"], "ac", "to_dict defense_type must match")
	assert_eq(d["defense_value"], 16, "to_dict defense_value must match")
	assert_false(d["hit"], "to_dict hit must match")
	assert_false(d["crit"], "to_dict crit must match")
	assert_eq(d["damage_final"], 0, "to_dict damage_final must match")


# ── CombatantDefeatedEvent ──────────────────────────────────────────────────────

func test_combatant_defeated_event_instantiates_with_documented_fields() -> void:
	var ev = RoundEventsClass.CombatantDefeatedEvent.new(3, "Goblin", "Titus")
	assert_eq(ev.round, 3, "round must be set")
	assert_eq(ev.name, "Goblin", "name must be set")
	assert_eq(ev.defeated_by, "Titus", "defeated_by must be set")


func test_combatant_defeated_event_is_refcounted_value_object() -> void:
	var ev = RoundEventsClass.CombatantDefeatedEvent.new()
	assert_true(ev is RefCounted, "CombatantDefeatedEvent must be a RefCounted")
	assert_false(ev is Node, "CombatantDefeatedEvent must NOT be a Node")


func test_combatant_defeated_event_to_dict_matches_fields() -> void:
	var ev = RoundEventsClass.CombatantDefeatedEvent.new(4, "Orc", "Lyra")
	var d: Dictionary = ev.to_dict()
	assert_eq(d, {"round": 4, "name": "Orc", "defeated_by": "Lyra"}, "to_dict must match fields")


# ── EncounterResultEvent ────────────────────────────────────────────────────────

func test_encounter_result_event_instantiates_with_documented_fields() -> void:
	var ev = RoundEventsClass.EncounterResultEvent.new(5, "won")
	assert_eq(ev.round, 5, "round must be set")
	assert_eq(ev.outcome, "won", "outcome must be set")


func test_encounter_result_event_is_refcounted_value_object() -> void:
	var ev = RoundEventsClass.EncounterResultEvent.new()
	assert_true(ev is RefCounted, "EncounterResultEvent must be a RefCounted")
	assert_false(ev is Node, "EncounterResultEvent must NOT be a Node")


func test_encounter_result_event_to_dict_matches_fields() -> void:
	var ev = RoundEventsClass.EncounterResultEvent.new(6, "lost")
	var d: Dictionary = ev.to_dict()
	assert_eq(d, {"round": 6, "outcome": "lost"}, "to_dict must match fields")


# ── RoundHistoryEntry ────────────────────────────────────────────────────────────

func test_round_history_entry_instantiates_with_documented_fields() -> void:
	var entry = RoundEventsClass.RoundHistoryEntry.new(2, 1, "titus", "ACTION", 5)
	assert_eq(entry.round_number, 2, "round_number must be set")
	assert_eq(entry.cycle_index, 1, "cycle_index must be set")
	assert_eq(entry.combatant_id, "titus", "combatant_id must be set")
	assert_eq(entry.action_type, "ACTION", "action_type must be set")
	assert_eq(entry.budget_remaining, 5, "budget_remaining must be set")


func test_round_history_entry_is_refcounted_value_object() -> void:
	var entry = RoundEventsClass.RoundHistoryEntry.new()
	assert_true(entry is RefCounted, "RoundHistoryEntry must be a RefCounted")
	assert_false(entry is Node, "RoundHistoryEntry must NOT be a Node")


func test_round_history_entry_to_dict_matches_fields() -> void:
	var entry = RoundEventsClass.RoundHistoryEntry.new(3, 2, "goblin-1", "REACTION", 0)
	var d: Dictionary = entry.to_dict()
	assert_eq(d, {
		"round_number":     3,
		"cycle_index":      2,
		"combatant_id":     "goblin-1",
		"action_type":      "REACTION",
		"budget_remaining": 0,
	}, "to_dict must match fields")


func test_round_history_entry_supports_multiple_entries_per_round_distinct_cycle_index() -> void:
	# AC-4 ordering verification: two entries in the same round but different
	# interleave cycles must be independently inspectable.
	var first = RoundEventsClass.RoundHistoryEntry.new(1, 0, "titus", "ACTION", 6)
	var second = RoundEventsClass.RoundHistoryEntry.new(1, 1, "titus", "ACTION", 5)
	assert_eq(first.round_number, second.round_number, "both entries share the same round_number")
	assert_ne(first.cycle_index, second.cycle_index, "cycle_index must distinguish interleave cycles")
	assert_eq(first.budget_remaining, 6, "first entry retains its own budget_remaining")
	assert_eq(second.budget_remaining, 5, "second entry retains its own budget_remaining")


# ── Domain purity (ADR-004) ──────────────────────────────────────────────────────

func test_round_events_gd_no_node_or_scenetree_inheritance() -> void:
	var file := FileAccess.open("res://core/rules/round_events.gd", FileAccess.READ)
	assert_not_null(file, "core/rules/round_events.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("extends Node"),
		"round_events.gd must not contain 'extends Node' — ADR-004 domain purity"
	)
	assert_false(
		content.contains("extends Control"),
		"round_events.gd must not contain 'extends Control' — ADR-004 domain purity"
	)
	assert_false(
		content.contains("extends SceneTree"),
		"round_events.gd must not contain 'extends SceneTree' — ADR-004 domain purity"
	)
