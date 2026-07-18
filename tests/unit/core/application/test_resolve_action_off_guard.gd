extends GutTest
## tests/unit/core/application/test_resolve_action_off_guard.gd
##
## GUT test suite for FEAT-153 (US-015 / FR-016, resolves FIND-142/FIND-145):
## the Off-Guard positional condition (core/rules/flanking.gd) computed by
## Flanking.is_off_guard() and shown in the UI (MainScene.gd's
## _refresh_off_guard_conditions()) previously never reached the LIVE Strike
## resolution path this composition root actually drives --
## core/application/resolve_action_use_case.gd's resolve()/_resolve_strike()
## -- even though core/rules/resolution.gd's legacy resolve_weapon_attack()
## path already implemented the FR-016 blanket +2 bonus correctly. This
## suite proves the bonus now reaches resolve() itself, and that
## MainScene._refresh_off_guard_conditions() feeds the SAME live combatant
## Dictionary structure resolve() reads (not a parallel/mocked copy).
##
## Validates (test_criteria):
##   1. A Strike resolved via resolve() against a target whose live
##      "conditions" carry "Off-Guard" uses an effective defense_value
##      exactly 2 lower than the identical target without the condition.
##   2. Hit-rate/outcome over repeated seeded rolls differs consistently
##      (attacker-favorable, never fewer hits) with the +2 bonus present.
##   3. MainScene.gd's _refresh_off_guard_conditions() now writes
##      Flanking.off_guard_conditions() into the LIVE _party/_enemies
##      combatant Dictionaries -- the SAME Dictionaries
##      resolve_action_use_case.resolve() consumes as its `target` argument
##      -- demonstrated end-to-end via a real MainScene.tscn boot.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const FlankingClass             = preload("res://core/rules/flanking.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")
const SeededRandomAdapterClass  = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


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


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	})


## _target(conditions) -> Dictionary — ac=12 is JUST out of reach of a raw
## d20 roll of 10 (roll_total=10 < ac=12 -> miss), but exactly in reach of
## the same roll against an Off-Guard-reduced effective ac of 10 (10 >= 10
## -> hit) -- isolating the +2 bonus's effect precisely, mirroring
## tests/unit/test_resolution.gd's _boundary_target() fixture.
func _target(conditions: Array = []):
	return CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 12, "conditions": conditions})


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


func _fresh_action_economy():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: effective defense_value used by resolve() is exactly 2 lower
# when the target's live "conditions" carry Off-Guard.
# ══════════════════════════════════════════════════════════════════════════════

func test_resolve_defense_value_is_two_lower_with_off_guard_condition() -> void:
	var attacker = _attacker()

	var rig_baseline: Dictionary = _make_use_case([10, 4])
	var baseline_target = _target([])
	var result_baseline: Dictionary = rig_baseline["use_case"].resolve(
		attacker, _fresh_action_economy(), baseline_target, "Strike", 1, 0
	)

	var rig_off_guard: Dictionary = _make_use_case([10, 4])
	var off_guard_target = _target([FlankingClass.OFF_GUARD_CONDITION])
	var result_off_guard: Dictionary = rig_off_guard["use_case"].resolve(
		attacker, _fresh_action_economy(), off_guard_target, "Strike", 1, 0
	)

	assert_true(result_baseline.get("ok", false), "baseline Strike must resolve")
	assert_true(result_off_guard.get("ok", false), "Off-Guard Strike must resolve")

	var baseline_defense_value: int = result_baseline["event"].defense_value
	var off_guard_defense_value: int = result_off_guard["event"].defense_value

	assert_eq(baseline_defense_value, 12, "baseline defense_value must be the target's plain ac (12)")
	assert_eq(
		off_guard_defense_value, baseline_defense_value - 2,
		"Off-Guard's blanket +2 bonus must reduce the effective defense_value used by resolve() by exactly 2"
	)


func test_resolve_off_guard_turns_a_boundary_miss_into_a_hit() -> void:
	# raw=10, attribute_mod=0, proficiency=0 -> roll_total=10.
	# Baseline: 10 < ac=12 -> miss. Off-Guard: 10 >= (12-2)=10 -> hit.
	var attacker = _attacker()

	var rig_baseline: Dictionary = _make_use_case([10, 4])
	var result_baseline: Dictionary = rig_baseline["use_case"].resolve(
		attacker, _fresh_action_economy(), _target([]), "Strike", 1, 0
	)
	assert_false(result_baseline["event"].hit, "without Off-Guard, roll_total=10 must miss ac=12")

	var rig_off_guard: Dictionary = _make_use_case([10, 4])
	var result_off_guard: Dictionary = rig_off_guard["use_case"].resolve(
		attacker, _fresh_action_economy(), _target([FlankingClass.OFF_GUARD_CONDITION]), "Strike", 1, 0
	)
	assert_true(
		result_off_guard["event"].hit,
		"Off-Guard's blanket +2 must turn roll_total=10 vs ac=12 into a hit through resolve()"
	)


func test_resolve_ignores_unrelated_conditions_for_defense_reduction() -> void:
	var attacker = _attacker()
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		attacker, _fresh_action_economy(), _target(["Dazed"]), "Strike", 1, 0
	)
	assert_eq(
		result["event"].defense_value, 12,
		"an unrelated condition (Dazed) must not reduce defense_value -- only Off-Guard may"
	)
	assert_false(result["event"].hit, "an unrelated condition (Dazed) must not grant the Off-Guard bonus")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: hit-rate/outcome over repeated seeded rolls differs
# consistently (attacker-favorable) with Off-Guard present.
# ══════════════════════════════════════════════════════════════════════════════

const _TRIAL_SEED_COUNT: int = 200

func test_resolve_off_guard_hit_rate_is_consistently_attacker_favorable_across_seeds() -> void:
	var attacker = _attacker()

	var baseline_hits: int = 0
	var off_guard_hits: int = 0
	var any_seed_flipped_miss_to_hit: bool = false

	for seed in range(_TRIAL_SEED_COUNT):
		# Two independently-seeded adapters constructed from the SAME seed
		# always agree on the raw d20 roll (SeededRandomAdapter's documented
		# determinism contract) -- so any hit/miss divergence between the two
		# resolve() calls below is attributable ONLY to the Off-Guard
		# defense_value reduction, never to a different underlying roll.
		var baseline_rng = SeededRandomAdapterClass.new(seed)
		var baseline_use_case = ResolveActionUseCaseClass.new(
			baseline_rng, FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
		)
		var baseline_result: Dictionary = baseline_use_case.resolve(
			attacker, _fresh_action_economy(), _target([]), "Strike", 1, 0
		)

		var off_guard_rng = SeededRandomAdapterClass.new(seed)
		var off_guard_use_case = ResolveActionUseCaseClass.new(
			off_guard_rng, FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
		)
		var off_guard_result: Dictionary = off_guard_use_case.resolve(
			attacker, _fresh_action_economy(), _target([FlankingClass.OFF_GUARD_CONDITION]), "Strike", 1, 0
		)

		var baseline_hit: bool = baseline_result["event"].hit
		var off_guard_hit: bool = off_guard_result["event"].hit

		assert_true(
			off_guard_hit or not baseline_hit,
			"seed %d: Off-Guard must never turn a baseline HIT into a miss (attacker-favorable, never negative)" % seed
		)

		if off_guard_hit and not baseline_hit:
			any_seed_flipped_miss_to_hit = true

		if baseline_hit:
			baseline_hits += 1
		if off_guard_hit:
			off_guard_hits += 1

	assert_true(
		any_seed_flipped_miss_to_hit,
		"at least one of the %d seeded rolls must land exactly in the +2 boundary window (a baseline miss that Off-Guard turns into a hit)" % _TRIAL_SEED_COUNT
	)
	assert_true(
		off_guard_hits > baseline_hits,
		"Off-Guard's blanket +2 must strictly increase the overall hit rate across repeated seeded rolls (%d vs %d)" % [off_guard_hits, baseline_hits]
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: MainScene._refresh_off_guard_conditions() feeds the SAME live
# conditions structure resolve() reads (real MainScene.tscn boot, not a
# mocked/re-derived copy).
# ══════════════════════════════════════════════════════════════════════════════

func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


func test_main_scene_refresh_off_guard_conditions_writes_into_live_combatant_dictionary() -> void:
	var instance = _boot_main_scene()

	# Skeleton (instance._enemies[0]) sits at hex (1,0); Titus (the sole
	# party member at boot) already occupies (0,0), the neighbor directly
	# opposite hex (2,0) around Skeleton. Appending a second party combatant
	# at (2,0) completes the opposite-adjacent flanking pair -- identical
	# fixture setup to tests/unit/test_main_scene_interactive_wiring.gd's
	# existing StatusPanelView-only wiring coverage, extended here to assert
	# the LIVE combatant Dictionary itself is also updated.
	var ally = CombatantClass.from_dict({
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "synthetic_ally_off_guard_resolve_test",
		"hex_coord": HexCoordClass.new(2, 0),
	})
	instance._party.append(ally)

	assert_eq(
		instance._enemies[0].conditions, [],
		"fixture assumption: before any flanking, the live target Dictionary carries no conditions"
	)

	instance._refresh_off_guard_conditions()

	assert_true(
		FlankingClass.OFF_GUARD_CONDITION in instance._enemies[0].conditions,
		"MainScene._refresh_off_guard_conditions() must write Off-Guard into the LIVE _enemies[0] Dictionary -- " +
		"the SAME Dictionary resolve_action_use_case.resolve() consumes as its `target` argument"
	)


func test_main_scene_off_guard_wiring_reduces_defense_value_through_a_real_resolve_call() -> void:
	var instance = _boot_main_scene()

	var ally = CombatantClass.from_dict({
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "synthetic_ally_off_guard_resolve_defense_test",
		"hex_coord": HexCoordClass.new(2, 0),
	})
	instance._party.append(ally)
	instance._refresh_off_guard_conditions()

	var live_target = instance._enemies[0]
	assert_true(
		FlankingClass.OFF_GUARD_CONDITION in live_target.conditions,
		"fixture setup: the live enemy target must be Off-Guard before comparing defense_value"
	)

	var attacker = instance._party[0]

	# A fresh baseline target duplicated from the SAME live Dictionary but
	# with conditions cleared isolates the Off-Guard reduction from every
	# other stat (ac, hp, weapon) the real prologue fixture assigns.
	var baseline_target = CombatantClass.from_dict(live_target.to_dict())
	baseline_target.conditions = []

	var rig_baseline: Dictionary = _make_use_case([12, 4])
	var result_baseline: Dictionary = rig_baseline["use_case"].resolve(
		attacker, _fresh_action_economy(), baseline_target, "Strike", 1, 0
	)

	var rig_off_guard: Dictionary = _make_use_case([12, 4])
	var result_off_guard: Dictionary = rig_off_guard["use_case"].resolve(
		attacker, _fresh_action_economy(), live_target, "Strike", 1, 0
	)

	assert_eq(
		result_off_guard["event"].defense_value, result_baseline["event"].defense_value - 2,
		"MainScene's real Off-Guard wiring must reduce the live enemy's effective defense_value by exactly 2 " +
		"when resolved through the actual resolve_action_use_case.resolve() call"
	)
