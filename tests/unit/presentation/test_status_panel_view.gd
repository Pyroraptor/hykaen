extends GutTest
## tests/unit/presentation/test_status_panel_view.gd
##
## GUT test suite for FEAT-008 / US-006 — StatusPanelView is a read-only
## projection of each combatant's status (name, HP, Stamina, action budget,
## Spent, conditions), populated once at boot (load_combatants()) and
## thereafter updated ONLY in response to typed round events (ADR-003),
## never by polling/mutating domain state directly.
##
## Verifies:
##   1. StatusPanelView displays the correct name/HP/Stamina/action budget/
##      Spent/conditions for each combatant immediately after boot
##      (load_combatants()).
##   2. The panel's HP display updates in response to a simulated AttackEvent
##      SIGNAL carrying target_hp_after (connected via a real Godot Signal,
##      exercising on_attack_event() as a signal-handler entry point).
##   3. Code-review assertion (source-inspection): status_panel_view.gd
##      contains no direct reference to resolve_action_use_case or
##      run_round_use_case — StatusPanelView must never call into a use case
##      (read-only projection).

const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")

const STATUS_PANEL_VIEW_PATH: String = "res://presentation/status_panel_view.gd"


## _FakeEventEmitter — a minimal Node exposing a custom Signal, used to
## simulate "an AttackEvent signal" arriving at StatusPanelView the way a
## future SignalEventSinkAdapter (see design notes, ADR-003) would broadcast
## one — WITHOUT depending on that adapter (out of scope for this feature).
class _FakeEventEmitter:
	extends Node
	signal attack_event(event)


var _panel = null


func before_each() -> void:
	_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(_panel)


func _sample_view_models() -> Array:
	return [
		{
			"combatant_id": "player_0",
			"name": "Titus",
			"hp_current": 10,
			"hp_max": 10,
			"stamina_current": 6,
			"stamina_max": 6,
			"action_budget_remaining": 7,
			"spent": false,
			"conditions": [],
		},
		{
			"combatant_id": "enemy_0",
			"name": "Skeleton",
			"hp_current": 8,
			"hp_max": 8,
			"stamina_current": 0,
			"stamina_max": 0,
			"action_budget_remaining": 7,
			"spent": true,
			"conditions": ["Dazed"],
		},
	]


# ── Criterion 1: correct status for each combatant immediately after boot ──

func test_load_combatants_creates_one_row_per_combatant() -> void:
	_panel.load_combatants(_sample_view_models())
	assert_eq(_panel.get_row_count(), 2, "StatusPanelView must have one row per loaded combatant")


func test_status_reflects_name_hp_stamina_budget_spent_conditions_for_player() -> void:
	_panel.load_combatants(_sample_view_models())
	var status: Dictionary = _panel.get_status("player_0")
	assert_eq(status.get("name"), "Titus")
	assert_eq(status.get("hp_current"), 10)
	assert_eq(status.get("hp_max"), 10)
	assert_eq(status.get("stamina_current"), 6)
	assert_eq(status.get("stamina_max"), 6)
	assert_eq(status.get("action_budget_remaining"), 7)
	assert_eq(status.get("spent"), false)
	assert_eq(status.get("conditions"), [])


func test_status_reflects_name_hp_stamina_budget_spent_conditions_for_enemy() -> void:
	_panel.load_combatants(_sample_view_models())
	var status: Dictionary = _panel.get_status("enemy_0")
	assert_eq(status.get("name"), "Skeleton")
	assert_eq(status.get("hp_current"), 8)
	assert_eq(status.get("hp_max"), 8)
	assert_eq(status.get("stamina_current"), 0)
	assert_eq(status.get("stamina_max"), 0)
	assert_eq(status.get("action_budget_remaining"), 7)
	assert_eq(status.get("spent"), true)
	assert_eq(status.get("conditions"), ["Dazed"])


func test_row_text_displays_all_required_fields() -> void:
	_panel.load_combatants(_sample_view_models())
	var text: String = _panel.get_row_text("enemy_0")
	assert_string_contains(text, "Skeleton", "row text must show the combatant's name")
	assert_string_contains(text, "8", "row text must show HP")
	assert_string_contains(text, "Spent: Yes", "row text must show Spent state")
	assert_string_contains(text, "Dazed", "row text must show conditions")


func test_load_combatants_reload_does_not_leak_duplicate_rows() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.load_combatants(_sample_view_models())
	assert_eq(_panel.get_row_count(), 2, "a second load_combatants() call must not leak duplicate rows")


func test_unknown_combatant_id_returns_empty_status() -> void:
	_panel.load_combatants(_sample_view_models())
	assert_eq(_panel.get_status("does_not_exist"), {})


# ── Criterion 2: HP updates in response to a simulated AttackEvent signal ──

func test_hp_updates_in_response_to_simulated_attack_event_signal_with_target_hp_after() -> void:
	_panel.load_combatants(_sample_view_models())

	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.attack_event.connect(_panel.on_attack_event)

	var simulated_attack_event: Dictionary = {
		"target_name": "Skeleton",
		"damage_final": 5,
		"target_hp_after": 3,
	}
	emitter.emit_signal("attack_event", simulated_attack_event)

	assert_eq(
		_panel.get_status("enemy_0").get("hp_current"), 3,
		"HP must update to the simulated event's target_hp_after value"
	)


func test_hp_update_leaves_other_combatants_unaffected() -> void:
	_panel.load_combatants(_sample_view_models())

	var emitter := _FakeEventEmitter.new()
	add_child_autofree(emitter)
	emitter.attack_event.connect(_panel.on_attack_event)
	emitter.emit_signal("attack_event", {"target_name": "Skeleton", "target_hp_after": 3})

	assert_eq(
		_panel.get_status("player_0").get("hp_current"), 10,
		"an attack event targeting Skeleton must not change Titus's displayed HP"
	)


func test_hp_updates_via_generic_on_round_event_dispatch() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.on_round_event({"target_name": "Titus", "target_hp_after": 4})
	assert_eq(_panel.get_status("player_0").get("hp_current"), 4)


func test_hp_falls_back_to_damage_final_when_target_hp_after_absent() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.on_attack_event({"target_name": "Titus", "damage_final": 6})
	assert_eq(
		_panel.get_status("player_0").get("hp_current"), 4,
		"with no target_hp_after, HP must be derived from hp_current - damage_final"
	)


func test_attack_event_for_unloaded_combatant_is_a_silent_noop() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.on_attack_event({"target_name": "Nobody", "target_hp_after": 0})
	assert_eq(_panel.get_row_count(), 2, "an event for an unknown combatant must not create/remove rows")


func test_round_event_with_production_attack_event_value_object_updates_hp() -> void:
	# Exercises the ACTUAL core/rules/round_events.gd shape (damage_final,
	# no target_hp_after) — confirms StatusPanelView works against the real
	# production event type, not only the Dictionary test double above.
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	_panel.load_combatants(_sample_view_models())

	var attack_event = RoundEventsClass.AttackEvent.new(
		1, "Titus", "Skeleton", 17, "ac", 14, true, false, 5
	)
	_panel.on_round_event(attack_event)

	assert_eq(
		_panel.get_status("enemy_0").get("hp_current"), 3,
		"a real RoundEvents.AttackEvent (damage_final=5) must reduce Skeleton's HP from 8 to 3"
	)


# ── Criterion 3: code-review assertion — no direct use-case calls ──────────

func _read_source() -> String:
	var file := FileAccess.open(STATUS_PANEL_VIEW_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/status_panel_view.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_direct_resolve_action_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("resolve_action_use_case"), -1,
		"status_panel_view.gd must never reference resolve_action_use_case (read-only projection)"
	)


func test_source_contains_no_direct_run_round_use_case_reference() -> void:
	var source: String = _read_source()
	assert_eq(
		source.findn("run_round_use_case"), -1,
		"status_panel_view.gd must never reference run_round_use_case (read-only projection)"
	)


# ── FEAT-015 / US-015 / FR-016: Off-Guard condition is visible in the ──────
# per-combatant readout (StatusPanelView.set_off_guard() / is_off_guard()) ──

func test_set_off_guard_true_adds_off_guard_to_conditions() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("enemy_0", true)

	assert_true(_panel.is_off_guard("enemy_0"))
	assert_true(
		"Off-Guard" in _panel.get_status("enemy_0").get("conditions", []),
		"Off-Guard must appear in the combatant's displayed conditions list"
	)


func test_set_off_guard_true_preserves_existing_conditions() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("enemy_0", true)

	var conditions: Array = _panel.get_status("enemy_0").get("conditions", [])
	assert_true("Dazed" in conditions, "setting Off-Guard must not drop a pre-existing condition (Dazed)")
	assert_true("Off-Guard" in conditions)


func test_set_off_guard_false_removes_off_guard_from_conditions() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("enemy_0", true)
	_panel.set_off_guard("enemy_0", false)

	assert_false(_panel.is_off_guard("enemy_0"))
	assert_false("Off-Guard" in _panel.get_status("enemy_0").get("conditions", []))


func test_set_off_guard_false_when_never_set_is_a_noop() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("player_0", false)

	assert_false(_panel.is_off_guard("player_0"))
	assert_eq(_panel.get_status("player_0").get("conditions", []), [])


func test_set_off_guard_updates_row_text() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("player_0", true)

	var text: String = _panel.get_row_text("player_0")
	assert_string_contains(text, "Off-Guard", "row text must show the Off-Guard condition once set")


func test_set_off_guard_is_idempotent() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("player_0", true)
	_panel.set_off_guard("player_0", true)

	var conditions: Array = _panel.get_status("player_0").get("conditions", [])
	var count: int = 0
	for c in conditions:
		if c == "Off-Guard":
			count += 1
	assert_eq(count, 1, "Off-Guard must never be duplicated in the conditions list")


func test_set_off_guard_for_unknown_combatant_is_a_silent_noop() -> void:
	_panel.load_combatants(_sample_view_models())
	_panel.set_off_guard("does_not_exist", true)

	assert_false(_panel.is_off_guard("does_not_exist"))
	assert_eq(_panel.get_row_count(), 2, "an Off-Guard update for an unknown combatant must not create rows")


func test_is_off_guard_false_by_default() -> void:
	_panel.load_combatants(_sample_view_models())
	assert_false(_panel.is_off_guard("player_0"))
	assert_false(_panel.is_off_guard("enemy_0"))
