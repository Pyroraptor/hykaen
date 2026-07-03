extends GutTest
## tests/unit/presentation/test_strike_action_control.gd
##
## GUT test suite for FEAT-109 (US-009): StrikeActionControl restricts
## selectable Strike targets to in-reach hexes (the domain adjacency
## function, core/geometry/hex_math.gd HexMath.hex_neighbors(), US-002/
## US-003) and forwards a selected target directly to the injected, REUSED
## resolve_action_use_case (core/application/resolve_action_use_case.gd,
## ADR-002 — no duplicate action path), consuming the actor's action budget.
##
## Verifies:
##   1. get_selectable_target_ids() exactly matches HexMath.hex_neighbors()
##      membership for the active combatant, excluding non-adjacent enemies.
##   2. Selecting a valid adjacent target invokes
##      resolve_action_use_case.resolve() and decrements the active
##      combatant's action budget (core/rules/action_economy.gd).
##   3. Integration: the resulting AttackEvent is observable in
##      EventLogView and StatusPanelView after the control invocation (via
##      the shared EventSinkPort those views already subscribe to, ADR-003).
##   4. Attempting to select a non-adjacent hex is prevented at the UI layer
##      — never rendered as a selectable button, AND rejected defensively
##      even when select_target() is called with its id directly, with no
##      use-case invocation / no action-budget spend / no event emitted.

const StrikeActionControlScene: PackedScene = preload("res://presentation/strike_action_control.tscn")
const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")
const HexMathClass              = preload("res://core/geometry/hex_math.gd")


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []
	var forward_to: Array = []  # Array of Nodes exposing on_round_event(event)

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			target.on_round_event(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


class SpyResolveActionUseCase:
	## A spy standing in for resolve_action_use_case (ADR-002 contract:
	## resolve(combatant, action_economy, target, action_name, round_number,
	## cycle_index) -> Dictionary) — used ONLY by criterion 4's "never
	## invoked" assertion, so that test does not depend on a real RNG rig.
	var call_count: int = 0
	var last_args: Array = []

	func resolve(combatant, action_economy, target, action_name: String, round_number: int, cycle_index: int) -> Dictionary:
		call_count += 1
		last_args = [combatant, action_economy, target, action_name, round_number, cycle_index]
		return {"ok": true, "resolved": true}


var _control = null


func before_each() -> void:
	_control = StrikeActionControlScene.instantiate()
	add_child_autofree(_control)


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _actor(hex_coord) -> Dictionary:
	return {
		"name": "Titus",
		"strength": 3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	}


func _enemy(name: String, hex_coord, hp: int = 20, ac: int = 10) -> Dictionary:
	return {"combatant_id": name.to_lower(), "name": name, "hp_current": hp, "ac": ac, "hex_coord": hex_coord}


## _ranged_actor(hex_coord, weapon) -> Dictionary -- FEAT-154: an actor
## equipped with a real ranged WeaponResource fixture (e.g.
## data/weapons/shortbow.tres), wiring its range_hexes field through into
## the weapon Dictionary exactly as MainScene.gd's _build_party_combatant()
## does for damage_modifier_attribute/proficiency_bonus/damage_die.
func _ranged_actor(hex_coord, weapon: Resource) -> Dictionary:
	return {
		"combatant_id": "archer",
		"name": "Archer",
		"strength": 3,
		"dexterity": 3,
		"hex_coord": hex_coord,
		"weapon": {
			"damage_modifier_attribute": weapon.damage_modifier_attribute,
			"proficiency_bonus": weapon.proficiency_bonus,
			"damage_die": weapon.damage_die,
			"range_hexes": weapon.range_hexes,
		},
	}


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: selectable target list exactly matches hex_neighbors().
# ══════════════════════════════════════════════════════════════════════════════

func test_selectable_targets_exactly_match_hex_neighbors() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy, far_enemy])

	assert_eq(
		_control.get_selectable_target_ids(), ["skeleton"],
		"only the adjacent enemy (hex_neighbors member) must be selectable"
	)
	assert_true(_control.is_target_selectable("skeleton"))
	assert_false(_control.is_target_selectable("goblin"), "a non-adjacent enemy must not be selectable")


func test_selectable_targets_include_all_six_neighbors_when_all_present() -> void:
	var origin := HexCoordClass.new(0, 0)
	var neighbor_coords: Array = HexMathClass.hex_neighbors(origin)

	var enemies: Array = []
	var expected_ids: Array = []
	for i in range(neighbor_coords.size()):
		var enemy_name: String = "Enemy%d" % i
		enemies.append(_enemy(enemy_name, neighbor_coords[i]))
		expected_ids.append(enemy_name.to_lower())

	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], enemies)

	var actual_ids: Array = _control.get_selectable_target_ids()
	assert_eq(actual_ids.size(), 6, "all 6 neighbors must be selectable when all are occupied by enemies")
	for expected_id in expected_ids:
		assert_true(actual_ids.has(expected_id), "expected neighbor target '%s' to be selectable" % expected_id)


func test_selectable_target_button_rendered_for_each_in_reach_enemy() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy, far_enemy])

	assert_eq(_control.get_button_count(), 1, "exactly one button must be rendered for the one in-reach enemy")


func test_reconfigure_does_not_leak_duplicate_buttons() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [adjacent_enemy])

	assert_eq(_control.get_button_count(), 1, "a second configure() call must not leak duplicate buttons")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: selecting a valid adjacent target invokes resolve_action_use_case
# and decrements the active combatant's action budget.
# ══════════════════════════════════════════════════════════════════════════════

func test_select_adjacent_target_invokes_use_case_and_decrements_action_budget() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	# raw=12 -> roll_total = 12 + strength(3) + proficiency(2) = 17 vs ac=10 -> hit.
	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), action_economy, rig["use_case"], [adjacent_enemy])

	var result: Dictionary = _control.select_target("skeleton")

	assert_true(result.get("ok", false), "selecting a valid adjacent target must resolve successfully")
	assert_eq(rig["event_sink"].events.size(), 1, "exactly one AttackEvent must be emitted")
	assert_eq(
		action_economy.get_remaining(), budget_before - 1,
		"the active combatant's action budget must be decremented by exactly one Strike"
	)


func test_select_target_emits_strike_resolved_signal() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), action_economy, rig["use_case"], [adjacent_enemy])

	watch_signals(_control)
	_control.select_target("skeleton")

	assert_signal_emitted(_control, "strike_resolved")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3 (integration): the resulting AttackEvent is observable in
# EventLogView and StatusPanelView after the control invocation.
# ══════════════════════════════════════════════════════════════════════════════

func test_attack_event_observable_in_event_log_view_and_status_panel_view() -> void:
	var status_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(status_panel)
	var event_log = EventLogViewScene.instantiate()
	add_child_autofree(event_log)

	status_panel.load_combatants([
		{
			"combatant_id": "skeleton", "name": "Skeleton",
			"hp_current": 20, "hp_max": 20,
			"stamina_current": 0, "stamina_max": 0,
			"action_budget_remaining": 7, "spent": false, "conditions": [],
		},
	])

	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0), 20, 10)

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()

	# raw=12 -> roll_total = 17 vs ac=10 -> hit; damage roll raw=4 -> 4+3 = 7 damage.
	var rig: Dictionary = _make_use_case([12, 4])
	rig["event_sink"].forward_to = [status_panel, event_log]

	_control.configure(_actor(origin), action_economy, rig["use_case"], [adjacent_enemy])
	var result: Dictionary = _control.select_target("skeleton")

	assert_true(result.get("ok", false))

	assert_eq(
		event_log.get_entry_count(), 1,
		"EventLogView must observe exactly one entry for the resolved Strike's AttackEvent"
	)
	assert_string_contains(event_log.get_entry_text(0), "Titus")
	assert_string_contains(event_log.get_entry_text(0), "Skeleton")

	assert_eq(
		status_panel.get_status("skeleton").get("hp_current"), 13,
		"StatusPanelView must reflect the resolved Strike's damage (20 - 7 = 13)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# FEAT-154 (resolves FIND-143/FIND-146): ranged-weapon target selection --
# StrikeActionControl must branch on the actor's equipped weapon so a target
# at hex_distance(actor, target) <= weapon.range_hexes is offered as
# selectable, mirroring resolve_action_use_case's _is_ranged_weapon()/
# _is_in_range() check exactly, instead of hardcoding hex_neighbors() (which
# only ever allowed distance-1 melee targets even for a ranged-equipped
# actor).
# ══════════════════════════════════════════════════════════════════════════════

func test_shortbow_equipped_actor_selects_and_resolves_a_full_strike_against_a_three_hex_target() -> void:
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(shortbow, "data/weapons/shortbow.tres must load")
	if shortbow == null:
		return

	var origin := HexCoordClass.new(0, 0)
	# hex_distance(origin, (3, 0)) == 3 -- non-adjacent, but well within the
	# shortbow's range_hexes of 8.
	var ranged_target: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	# raw=12 -> roll_total = 12 + dexterity(3) + proficiency(2) = 17 vs ac=10 -> hit.
	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_ranged_actor(origin, shortbow), action_economy, rig["use_case"], [ranged_target])

	assert_eq(
		_control.get_selectable_target_ids(), ["goblin"],
		"a target 3 hexes away must be selectable when the actor is equipped with a shortbow (range_hexes=8)"
	)
	assert_true(_control.is_target_selectable("goblin"))

	var result: Dictionary = _control.select_target("goblin")

	assert_true(
		result.get("ok", false),
		"a full Strike against the selected non-adjacent ranged target must resolve successfully end-to-end"
	)
	assert_eq(rig["event_sink"].events.size(), 1, "exactly one AttackEvent must be emitted")
	assert_eq(
		action_economy.get_remaining(), budget_before - 1,
		"the actor's action budget must be decremented by exactly one Strike"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: a non-adjacent hex is never selectable at the UI layer.
# ══════════════════════════════════════════════════════════════════════════════

func test_non_adjacent_target_not_rendered_as_button() -> void:
	var origin := HexCoordClass.new(0, 0)
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var rig: Dictionary = _make_use_case([12, 4])
	_control.configure(_actor(origin), ActionEconomyClass.new(), rig["use_case"], [far_enemy])

	assert_eq(_control.get_button_count(), 0, "a non-adjacent enemy must never be rendered as a selectable button")
	assert_eq(_control.get_selectable_target_ids(), [])


func test_selecting_non_adjacent_target_id_is_rejected_with_no_use_case_call() -> void:
	var origin := HexCoordClass.new(0, 0)
	var far_enemy: Dictionary = _enemy("Goblin", HexCoordClass.new(3, 0))

	var action_economy := ActionEconomyClass.new()
	action_economy.start_of_round()
	var budget_before: int = action_economy.get_remaining()

	var spy := SpyResolveActionUseCase.new()
	_control.configure(_actor(origin), action_economy, spy, [far_enemy])

	var result: Dictionary = _control.select_target("goblin")

	assert_false(result.get("ok", true), "selecting a non-adjacent target id must be rejected")
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_SELECTABLE")
	assert_eq(spy.call_count, 0, "resolve_action_use_case must never be invoked for a non-selectable target")
	assert_eq(
		action_economy.get_remaining(), budget_before,
		"the actor's action budget must remain unspent when the target is rejected at the UI layer"
	)


func test_selecting_unknown_target_id_is_rejected() -> void:
	var origin := HexCoordClass.new(0, 0)
	var adjacent_enemy: Dictionary = _enemy("Skeleton", HexCoordClass.new(1, 0))

	var spy := SpyResolveActionUseCase.new()
	_control.configure(_actor(origin), ActionEconomyClass.new(), spy, [adjacent_enemy])

	var result: Dictionary = _control.select_target("does_not_exist")

	assert_false(result.get("ok", true))
	assert_eq(spy.call_count, 0)
