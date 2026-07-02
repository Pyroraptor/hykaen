extends GutTest
## tests/gut/test_combatant_readout.gd — FEAT-005 (US-005 / FR-004, NFR-001)
##
## GUT test suite for scenes/battlefield/CombatantReadout.gd — a single
## combatant's read-only, event-driven readout (name/HP/Stamina/action
## budget/Spent/conditions), the per-combatant half of the hex battlefield
## renderer feature.
##
## Verifies (test_criteria):
##   1. HP/Stamina/action-budget/Spent/conditions displayed match live
##      Combatant domain state after a round_event fires.
##   2. Readouts update in response to AttackEvent/CombatantDefeatedEvent
##      WITHOUT polling (no _process()/_physics_process() loop; the readout
##      only ever changes state inside its on_round_event() dispatch entry
##      point, called directly by whatever forwards event_sink_port
##      broadcasts, mirroring presentation/status_panel_view.gd's
##      established ADR-003 pattern).
##   3. Code-review guardrail: CombatantReadout.gd contains no reach/damage/
##      hit computation (read-and-render only, ADR-001).

const RoundEventsClass = preload("res://core/rules/round_events.gd")
const CombatantReadoutClass: GDScript = preload("res://scenes/battlefield/CombatantReadout.gd")

const COMBATANT_READOUT_SOURCE_PATH: String = "res://scenes/battlefield/CombatantReadout.gd"

var _readout = null


func before_each() -> void:
	_readout = CombatantReadoutClass.new()
	add_child_autofree(_readout)


func _sample_view_model() -> Dictionary:
	return {
		"combatant_id": "player_0",
		"name": "Titus",
		"hp_current": 10,
		"hp_max": 10,
		"stamina_current": 6,
		"stamina_max": 6,
		"action_budget_remaining": 7,
		"spent": false,
		"conditions": [],
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: displayed status matches live Combatant domain state.
# ══════════════════════════════════════════════════════════════════════════

func test_initialize_reflects_the_supplied_view_model() -> void:
	_readout.initialize(_sample_view_model())
	var status: Dictionary = _readout.get_status()
	assert_eq(status.get("combatant_id"), "player_0")
	assert_eq(status.get("name"), "Titus")
	assert_eq(status.get("hp_current"), 10)
	assert_eq(status.get("hp_max"), 10)
	assert_eq(status.get("stamina_current"), 6)
	assert_eq(status.get("stamina_max"), 6)
	assert_eq(status.get("action_budget_remaining"), 7)
	assert_eq(status.get("spent"), false)
	assert_eq(status.get("conditions"), [])


func test_display_text_includes_all_required_fields() -> void:
	var view_model: Dictionary = _sample_view_model()
	view_model["spent"] = true
	view_model["conditions"] = ["Dazed"]
	_readout.initialize(view_model)

	var text: String = _readout.get_display_text()
	assert_string_contains(text, "Titus")
	assert_string_contains(text, "10")
	assert_string_contains(text, "6")
	assert_string_contains(text, "7")
	assert_string_contains(text, "Spent: Yes")
	assert_string_contains(text, "Dazed")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2a: updates in response to an AttackEvent.
# ══════════════════════════════════════════════════════════════════════════

func test_on_round_event_with_attack_event_reduces_hp() -> void:
	_readout.initialize(_sample_view_model())

	var attack_event = RoundEventsClass.AttackEvent.new(1, "Skeleton", "Titus", 17, "ac", 14, true, false, 6)
	_readout.on_round_event(attack_event)

	assert_eq(_readout.get_status().get("hp_current"), 4, "a real AttackEvent (damage_final=6) must reduce HP from 10 to 4")


func test_on_round_event_ignores_attack_event_for_a_different_target() -> void:
	_readout.initialize(_sample_view_model())

	var attack_event = RoundEventsClass.AttackEvent.new(1, "Skeleton", "SomeoneElse", 17, "ac", 14, true, false, 6)
	_readout.on_round_event(attack_event)

	assert_eq(_readout.get_status().get("hp_current"), 10, "an AttackEvent targeting a different combatant must not change this readout")


func test_attack_event_prefers_target_hp_after_when_present() -> void:
	_readout.initialize(_sample_view_model())
	_readout.on_round_event({"target_name": "Titus", "damage_final": 6, "target_hp_after": 2})
	assert_eq(_readout.get_status().get("hp_current"), 2)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2b: updates in response to a CombatantDefeatedEvent.
# ══════════════════════════════════════════════════════════════════════════

func test_on_round_event_with_combatant_defeated_event_zeroes_hp_and_flags_defeated() -> void:
	_readout.initialize(_sample_view_model())

	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Titus", "Skeleton")
	_readout.on_round_event(defeated_event)

	var status: Dictionary = _readout.get_status()
	assert_eq(status.get("hp_current"), 0, "CombatantDefeatedEvent must zero the readout's displayed HP")
	assert_true(status.get("conditions").has("Defeated"), "CombatantDefeatedEvent must surface a Defeated condition")


func test_combatant_defeated_event_for_a_different_combatant_is_a_silent_noop() -> void:
	_readout.initialize(_sample_view_model())

	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "SomeoneElse", "Skeleton")
	_readout.on_round_event(defeated_event)

	var status: Dictionary = _readout.get_status()
	assert_eq(status.get("hp_current"), 10)
	assert_false(status.get("conditions").has("Defeated"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2c: purely event-driven — no polling.
# ══════════════════════════════════════════════════════════════════════════

func _read_source() -> String:
	var file := FileAccess.open(COMBATANT_READOUT_SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % COMBATANT_READOUT_SOURCE_PATH)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_declares_no_polling_process_callbacks() -> void:
	var source: String = _read_source()
	assert_eq(source.find("_process("), -1, "CombatantReadout.gd must not poll domain state via _process()")
	assert_eq(source.find("_physics_process("), -1, "CombatantReadout.gd must not poll domain state via _physics_process()")


func test_updates_are_reflected_immediately_with_no_frame_wait() -> void:
	# No `await get_tree().process_frame` anywhere in this test -- the status
	# change from on_round_event() must be synchronous/immediate, proving
	# there is no polling loop involved in propagating it.
	_readout.initialize(_sample_view_model())
	_readout.on_round_event(RoundEventsClass.AttackEvent.new(1, "Skeleton", "Titus", 17, "ac", 14, true, false, 3))
	assert_eq(_readout.get_status().get("hp_current"), 7)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (code review guardrail): no reach/damage/hit computation.
# ══════════════════════════════════════════════════════════════════════════

func test_source_contains_no_combat_computation_keywords() -> void:
	var source: String = _read_source().to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "is_adjacent", "compute_ac", "compute_hp",
		"reach", "hit_chance", "randi", "randf",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"scenes/battlefield/CombatantReadout.gd must contain no combat computation ('%s' found) -- read-and-render only (ADR-001)" % keyword
		)
