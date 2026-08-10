extends GutTest
## tests/unit/test_simulator_defense_source_parity.gd
##
## GUT unit tests for FEAT-008 (US-008 / FR-008, ADR-106): core/sim/
## simulator.gd's combatant-construction path must read enemy defenses
## (ac/fortitude/reflex/will) from the SAME EnemyResource source
## presentation/../MainScene.gd's _build_enemy_combatant() reads from — never
## an independently hard-coded literal (the previous "ac": 14 inline literal
## in Simulator.run()'s per-battle loop). A silent divergence here would let
## the balance simulation validate against a different AC than the live,
## interactive game actually enforces.
##
## Test criteria covered:
##   1. Simulator's combatant construction for skeleton.tres (via the
##      extracted, independently-testable _build_skeleton_combatant() helper)
##      yields the IDENTICAL ac/fortitude/reflex/will values MainScene's
##      _build_enemy_combatant() yields for the same resource — sim/game
##      defense-source parity (equality assertion).
##   2. A Strike resolved via ResolveActionUseCase against a skeleton-built
##      Combatant reports the target's effective defense value used for the
##      hit check ("target_ac_used") == 14 — the AttackEvent's defense_value
##      field, sourced transitively from skeleton.tres via
##      _build_enemy_combatant(), not any hard-coded constant.

const MainSceneClass             = preload("res://MainScene.gd")
const SimulatorClass             = preload("res://core/sim/simulator.gd")
const ResolveActionUseCaseClass  = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass         = preload("res://core/rules/action_economy.gd")
const RoundEventsClass           = preload("res://core/rules/round_events.gd")

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"

## Attribute name mapping mirrored from core/sim/simulator.gd's own
## SKELETON_ATTR_MAP local constant (EnemyResource uses compact keys).
const _SKELETON_ATTR_MAP: Dictionary = {"str": "strength", "dex": "dexterity"}


## ScriptedRandomNumberPort — deterministic stand-in for RandomNumberPort,
## mirroring tests/test_resolve_action_use_case.gd's identically-named
## fixture: returns a pre-scripted sequence of int values, one per roll().
class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


var _main_scene = null


func before_each() -> void:
	_main_scene = MainSceneClass.new()


func after_each() -> void:
	if _main_scene != null:
		_main_scene.free()
	_main_scene = null


func _skeleton_weapon_attribute(skeleton_res) -> String:
	## FEAT-002 (US-002, ADR-001/ADR-002): resolve via weapon_paths[0] ->
	## WeaponResource; damage_modifier_attribute is already canonical
	## long-form (e.g. "strength"), so no attribute-map translation remains.
	if skeleton_res.weapon_paths.is_empty():
		return "strength"
	var weapon_res = ResourceLoader.load(skeleton_res.weapon_paths[0])
	if weapon_res == null:
		return "strength"
	return weapon_res.damage_modifier_attribute


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Simulator's skeleton combatant and MainScene's skeleton
# combatant carry IDENTICAL ac/fortitude/reflex/will values.
# ══════════════════════════════════════════════════════════════════════════

func test_simulator_and_mainscene_agree_on_skeleton_defenses() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var sim = SimulatorClass.new()
	var sim_combatant: Dictionary = sim._build_skeleton_combatant(skeleton_res, _skeleton_weapon_attribute(skeleton_res))

	var game_combatant: Dictionary = _main_scene._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_eq(sim_combatant.get("ac", -1), game_combatant.get("ac", -2),
		"Simulator and MainScene must agree on skeleton ac; sim=%s game=%s" % [str(sim_combatant.get("ac")), str(game_combatant.get("ac"))])
	assert_eq(sim_combatant.get("fortitude", -1), game_combatant.get("fortitude", -2),
		"Simulator and MainScene must agree on skeleton fortitude")
	assert_eq(sim_combatant.get("reflex", -1), game_combatant.get("reflex", -2),
		"Simulator and MainScene must agree on skeleton reflex")
	assert_eq(sim_combatant.get("will", -1), game_combatant.get("will", -2),
		"Simulator and MainScene must agree on skeleton will")


func test_simulator_skeleton_defenses_match_pinned_resource_values() -> void:
	var skeleton_res = ResourceLoader.load(SKELETON_TRES_PATH)
	var sim = SimulatorClass.new()
	var sim_combatant: Dictionary = sim._build_skeleton_combatant(skeleton_res, _skeleton_weapon_attribute(skeleton_res))

	assert_eq(sim_combatant.get("ac", -1), 14, "Simulator's skeleton ac must equal the resource's authored ac=14")
	assert_eq(sim_combatant.get("fortitude", -1), 13, "Simulator's skeleton fortitude must equal the resource's authored fortitude=13")
	assert_eq(sim_combatant.get("reflex", -1), 12, "Simulator's skeleton reflex must equal the resource's authored reflex=12")
	assert_eq(sim_combatant.get("will", -1), 12, "Simulator's skeleton will must equal the resource's authored will=12")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a Strike resolved via ResolveActionUseCase against a
# skeleton-built Combatant reports target_ac_used == 14 (never a
# hard-coded constant).
# ══════════════════════════════════════════════════════════════════════════

func test_strike_against_skeleton_built_combatant_reports_target_ac_used_14() -> void:
	var target: Dictionary = _main_scene._build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	var attacker: Dictionary = {
		"name":     "Attacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}

	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	ae.start_of_turn()

	var rng_port   = ScriptedRandomNumberPort.new([12, 4])
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)

	var result: Dictionary = use_case.resolve(attacker, ae, target, "Strike", 1, 0)

	assert_true(result.get("resolved", false), "Strike against the skeleton-built target must resolve")

	var attack_event = result.get("event", null)
	assert_not_null(attack_event, "resolve() must return the emitted AttackEvent")
	if attack_event == null:
		return

	var target_ac_used: int = attack_event.defense_value
	assert_eq(
		target_ac_used, 14,
		"target_ac_used (the effective AC the Strike rolled against) must equal skeleton.tres' authored ac=14, not a hard-coded constant; got: %d" % target_ac_used
	)
