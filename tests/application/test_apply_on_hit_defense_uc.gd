extends GutTest
## tests/application/test_apply_on_hit_defense_uc.gd
##
## GUT suite for FEAT-002 (US-001 / US-002, ADR-001): core/application/
## apply_on_hit_defense_uc.gd — PHASE 2 of the ADR-001 two-phase
## Strike-resolution split. Fixes the Iteration J defect where Parry/Block
## never reduced damage: this phase is the ONLY place hp_current is
## committed and AttackEvent/CombatantDefeatedEvent are emitted, and it
## always runs Block/Parry mitigation (via the SAME Resolution instance the
## to-hit phase used) BEFORE either happens.
##
## Validates (test_criteria):
##   1. hp_current commit and AttackEvent emission carry the FINAL
##      (post-mitigation) damage, never the raw pre-mitigation value.
##   2. Scripted Parry/Block/Pass outcomes each produce the correct
##      final_damage.
##   3. A lethal-but-parried scripted hit must NOT emit
##      CombatantDefeatedEvent (the pre-mitigation-lethal hit never reaches
##      defeat logic once Parry negates it).
##   4. CombatantDefeatedEvent is emitted only when hp_current <= 0 AFTER
##      mitigation -- never before, never for a hit mitigated back to a
##      survivable amount.

const ResolveToHitUseCaseClass      = preload("res://core/application/resolve_to_hit_uc.gd")
const ApplyOnHitDefenseUseCaseClass = preload("res://core/application/apply_on_hit_defense_uc.gd")
const RoundEventsClass               = preload("res://core/rules/round_events.gd")


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


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker() -> Dictionary:
	return {"name": "Attacker", "strength": 3}


func _weapon() -> Dictionary:
	return {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}


func _target(hp: int = 50, ac: int = 10) -> Dictionary:
	return {"name": "Target", "hp_current": hp, "ac": ac}


## _rig(values) -> Dictionary -- builds a to-hit use case and an apply-phase
## use case SHARING the same Resolution instance (mirrors how a future
## round_session integration would wire these two use cases across an
## awaited on-hit reaction window -- see resolve_to_hit_uc.gd's
## get_resolution() doc, ADR-002).
func _rig(values: Array) -> Dictionary:
	var to_hit_uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new(values))
	var event_sink = FakeEventSinkPort.new()
	var apply_uc = ApplyOnHitDefenseUseCaseClass.new(to_hit_uc.get_resolution(), event_sink)
	return {"to_hit_uc": to_hit_uc, "apply_uc": apply_uc, "event_sink": event_sink}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: hp_current commit + AttackEvent emission carry FINAL damage.
# ══════════════════════════════════════════════════════════════════════════

func test_apply_commits_hp_current_with_final_post_mitigation_damage() -> void:
	# raw=12 -> hit(17>=10); damage_raw=4+3=7; block roll=2+block_value(3)=5 -> final=2.
	var rig: Dictionary = _rig([12, 4, 2])
	var target: Dictionary = _target(50, 10)
	var block_weapon: Dictionary = {"damage_die": 6, "block_value": 3}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "block", {"blocking_weapon": block_weapon}, 1)

	assert_eq(result["damage_final"], 2, "final damage must be the POST-mitigation value (7 raw - 5 block = 2)")
	assert_eq(target.get("hp_current", -1), 48, "hp_current must be reduced by the FINAL mitigated damage (50-2=48), not the raw 7")

	var attack_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1)
	assert_eq(attack_events[0].damage_final, 2, "the emitted AttackEvent must carry the FINAL post-mitigation damage")


func test_to_hit_phase_alone_never_commits_hp_or_emits_events() -> void:
	# Sanity companion: confirms ALL side effects genuinely originate from
	# apply() -- the to-hit phase by itself (no apply() call at all) leaves
	# hp untouched and emits nothing.
	var rig: Dictionary = _rig([12, 4, 2])
	var target: Dictionary = _target(50, 10)
	rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})

	assert_eq(target.get("hp_current", -1), 50)
	assert_eq(rig["event_sink"].events.size(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: scripted Parry/Block/Pass outcomes -> correct final_damage.
# ══════════════════════════════════════════════════════════════════════════

func test_apply_pass_leaves_damage_raw_unmodified() -> void:
	var rig: Dictionary = _rig([12, 4])
	var target: Dictionary = _target(50, 10)

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "none", {}, 1)

	assert_eq(result["damage_final"], 7, "Pass (on_hit_defense='none') must leave damage_final == damage_raw")
	assert_eq(target.get("hp_current", -1), 43)


func test_apply_block_reduces_final_damage() -> void:
	var rig: Dictionary = _rig([12, 4, 2])
	var target: Dictionary = _target(50, 10)
	var block_weapon: Dictionary = {"damage_die": 6, "block_value": 3}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "block", {"blocking_weapon": block_weapon}, 1)

	assert_eq(result["damage_final"], 2, "block must reduce final_damage to 7-(2+3)=2")
	assert_eq(result["active_defense_applied"], "block")
	assert_true(result["on_hit_suppressed"])


func test_apply_block_floors_final_damage_at_zero() -> void:
	var rig: Dictionary = _rig([12, 4, 50])
	var target: Dictionary = _target(50, 10)
	var block_weapon: Dictionary = {"damage_die": 6, "block_value": 3}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "block", {"blocking_weapon": block_weapon}, 1)

	assert_eq(result["damage_final"], 0, "an oversized block reduction must floor final_damage at 0")
	assert_eq(target.get("hp_current", -1), 50, "no HP may be lost when the block reduction exceeds the raw damage")


func test_apply_parry_success_negates_final_damage_to_zero() -> void:
	# roll_total=17; parry_d20=14+parry_bonus(4)=18 > 17 -> success -> final=0.
	var rig: Dictionary = _rig([12, 4, 14])
	var target: Dictionary = _target(50, 10)
	var parry_weapon: Dictionary = {"parry_bonus": 4}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "parry", {"parrying_weapon": parry_weapon}, 1)

	assert_eq(result["damage_final"], 0, "a successful Parry must negate final_damage to 0")
	assert_true(result["on_hit_suppressed"])
	assert_eq(target.get("hp_current", -1), 50, "no HP must be lost when Parry negates the hit entirely")


func test_apply_parry_failure_leaves_damage_raw_unmodified() -> void:
	# roll_total=17; parry_d20=2+parry_bonus(4)=6 <= 17 -> fail -> final stays 7.
	var rig: Dictionary = _rig([12, 4, 2])
	var target: Dictionary = _target(50, 10)
	var parry_weapon: Dictionary = {"parry_bonus": 4}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "parry", {"parrying_weapon": parry_weapon}, 1)

	assert_eq(result["damage_final"], 7, "a failed Parry must leave final_damage at the raw value")
	assert_false(result["on_hit_suppressed"])
	assert_eq(target.get("hp_current", -1), 43)


func test_apply_on_a_miss_applies_zero_damage_regardless_of_on_hit_defense() -> void:
	var rig: Dictionary = _rig([1])
	var target: Dictionary = _target(50, 10)

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	assert_false(partial["hit"], "sanity: scripted scenario must be a miss")

	var result: Dictionary = rig["apply_uc"].apply(
		partial, _attacker(), target, "block", {"blocking_weapon": {"damage_die": 6, "block_value": 3}}, 1
	)

	assert_eq(result["damage_final"], 0, "a miss must apply zero damage regardless of on_hit_defense")
	assert_eq(target.get("hp_current", -1), 50)

	var attack_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "a miss must still emit exactly one AttackEvent")
	assert_false(attack_events[0].hit)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3/4: CombatantDefeatedEvent emitted only when hp_current<=0
# AFTER mitigation; lethal-but-parried/blocked must NOT emit it.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_but_parried_hit_does_not_emit_combatant_defeated_event() -> void:
	# damage_raw=7 would be lethal against 5 HP, but a successful Parry negates
	# it entirely -> target survives -> CombatantDefeatedEvent must NOT fire.
	var rig: Dictionary = _rig([12, 4, 14])
	var target: Dictionary = _target(5, 10)
	var parry_weapon: Dictionary = {"parry_bonus": 4}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "parry", {"parrying_weapon": parry_weapon}, 1)

	assert_eq(target.get("hp_current", -1), 5, "a fully-parried lethal hit must leave hp_current untouched")
	assert_false(result["defender_defeated"], "defender_defeated must be false once Parry negates a pre-mitigation-lethal hit")

	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0, "CombatantDefeatedEvent must NOT be emitted for a lethal-but-parried hit")


func test_lethal_but_blocked_below_zero_threshold_does_not_emit_combatant_defeated_event() -> void:
	# damage_raw=7 would be lethal against 6 HP (6-7=-1), but Block mitigates
	# to 2 -> target survives at 4 HP -> no CombatantDefeatedEvent.
	var rig: Dictionary = _rig([12, 4, 2])
	var target: Dictionary = _target(6, 10)
	var block_weapon: Dictionary = {"damage_die": 6, "block_value": 3}

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "block", {"blocking_weapon": block_weapon}, 1)

	assert_eq(target.get("hp_current", -1), 4)
	assert_false(result["defender_defeated"])
	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0)


func test_combatant_defeated_event_emitted_when_hp_drops_to_zero_or_below_after_mitigation() -> void:
	# An UNMITIGATED lethal hit (on_hit_defense='none') must still defeat the
	# target and emit CombatantDefeatedEvent -- proving the gate is genuinely
	# "post-mitigation", not "never fires".
	var rig: Dictionary = _rig([12, 4])
	var target: Dictionary = _target(5, 10)

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	var result: Dictionary = rig["apply_uc"].apply(partial, _attacker(), target, "none", {}, 1)

	assert_true(target.get("hp_current", 1) <= 0)
	assert_true(result["defender_defeated"])

	var events: Array = rig["event_sink"].events
	assert_eq(events.size(), 2, "both AttackEvent and CombatantDefeatedEvent must be emitted")
	assert_true(events[0] is RoundEventsClass.AttackEvent, "AttackEvent must be emitted before CombatantDefeatedEvent")
	assert_true(events[1] is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(events[1].name, "Target")
	assert_eq(events[1].defeated_by, "Attacker")


func test_combatant_defeated_event_never_emitted_when_hit_missed() -> void:
	var rig: Dictionary = _rig([1])
	var target: Dictionary = _target(1, 10)  # would be trivially "defeated" if any damage were ever applied

	var partial: Dictionary = rig["to_hit_uc"].resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})
	rig["apply_uc"].apply(partial, _attacker(), target, "none", {}, 1)

	assert_eq(target.get("hp_current", -1), 1, "a miss must never reduce hp_current")
	var defeated_events: Array = rig["event_sink"].events.filter(func(e): return e is RoundEventsClass.CombatantDefeatedEvent)
	assert_eq(defeated_events.size(), 0)
