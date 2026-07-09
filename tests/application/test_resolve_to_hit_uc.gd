extends GutTest
## tests/application/test_resolve_to_hit_uc.gd
##
## GUT suite for FEAT-002 (US-001, ADR-001): core/application/resolve_to_hit_uc.gd
## — PHASE 1 of the ADR-001 two-phase Strike-resolution split, exposed at the
## APPLICATION layer via an injected RandomNumberPort (core/rules/resolution.gd
## already provides the underlying domain-layer split; see that file's
## FEAT-001 doc and core/rules/tests/test_resolution_two_phase.gd).
##
## Validates (test_criteria):
##   1. resolve_to_hit() never mutates target.hp_current and never emits an
##      AttackEvent — this use case has no EventSinkPort collaborator at all,
##      so the no-emit guarantee is structural, not merely a runtime check
##      (pinned by a source-scan below, mirroring
##      core/rules/tests/test_resolution_two_phase.gd's own static-inspection
##      convention).
##   2. resolve_to_hit() correctly forwards roll/damage math through to the
##      underlying Resolution instance.
##   3. get_resolution() returns the SAME Resolution instance across calls,
##      so a caller sharing it with ApplyOnHitDefenseUseCase preserves the
##      RNG sequence (ADR-002).

const ResolveToHitUseCaseClass = preload("res://core/application/resolve_to_hit_uc.gd")

const RESOLVE_TO_HIT_UC_PATH: String = "res://core/application/resolve_to_hit_uc.gd"


## ScriptedRandomNumberPort — returns a pre-scripted sequence of int values,
## one per roll() call, in order (mirrors tests/test_resolve_action_use_case.gd's
## identically-named/identically-shaped double — each suite in this project
## owns its own doubles).
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

func _attacker() -> Dictionary:
	return {"name": "Attacker", "strength": 3}


func _weapon() -> Dictionary:
	return {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6}


func _target(hp: int = 50, ac: int = 10) -> Dictionary:
	return {"name": "Target", "hp_current": hp, "ac": ac}


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: no hp_current mutation, no AttackEvent emitted.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_to_hit_never_mutates_target_hp_current_on_a_hit() -> void:
	# raw=12 -> roll_total=12+3+2=17 vs ac=10 -> hit; damage roll=4 -> damage_raw=7.
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([12, 4]))
	var target: Dictionary = _target(50, 10)

	var partial: Dictionary = uc.resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})

	assert_true(partial["hit"], "sanity: this scripted scenario must be a hit")
	assert_eq(partial["damage_raw"], 7, "sanity: damage_raw must be computed")
	assert_eq(
		target.get("hp_current", -1), 50,
		"resolve_to_hit() must NEVER mutate target.hp_current -- committing HP is the apply-phase's exclusive job"
	)


func test_resolve_to_hit_never_mutates_target_hp_current_on_a_miss() -> void:
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([1]))
	var target: Dictionary = _target(50, 10)

	uc.resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})

	assert_eq(target.get("hp_current", -1), 50, "a miss must also never mutate target.hp_current")


func test_resolve_to_hit_never_mutates_target_hp_current_across_repeated_calls() -> void:
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([12, 4, 12, 4, 12, 4]))
	var target: Dictionary = _target(50, 10)

	for _i in range(3):
		uc.resolve_to_hit(_attacker(), target, _weapon(), "ac", "none", {})

	assert_eq(target.get("hp_current", -1), 50, "repeated to-hit calls must never accumulate an hp_current mutation")


func test_resolve_to_hit_has_no_event_sink_collaborator() -> void:
	# Structural proof (test_criteria #1): this use case's ONLY constructor
	# argument is a RandomNumberPort -- it never stores/receives an
	# EventSinkPort collaborator, and never calls .emit(), so it is
	# structurally incapable of emitting an AttackEvent. Mirrors
	# core/rules/tests/test_resolution_two_phase.gd's static-inspection
	# convention for "this code cannot do X" proofs. (Doc comments MAY
	# mention "EventSinkPort" by name for cross-referencing purposes -- this
	# scans for actual wiring, not the bare word.)
	var content: String = _read_file(RESOLVE_TO_HIT_UC_PATH)
	assert_false(
		content.contains("_event_sink_port"),
		"ResolveToHitUseCase must never declare/receive an _event_sink_port collaborator"
	)
	assert_false(
		content.contains(".emit("),
		"ResolveToHitUseCase must never call .emit() -- it must be structurally unable to emit events"
	)
	assert_true(
		content.contains("func _init(random_number_port)"),
		"ResolveToHitUseCase's constructor must accept exactly ONE argument (random_number_port) -- no EventSinkPort parameter"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: correct roll/damage math forwarding.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_to_hit_computes_correct_roll_and_damage_on_hit() -> void:
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([12, 4]))
	var partial: Dictionary = uc.resolve_to_hit(_attacker(), _target(50, 10), _weapon(), "ac", "none", {})

	assert_eq(partial["roll_total"], 17, "roll_total must be raw(12)+strength(3)+prof(2)=17")
	assert_true(partial["hit"])
	assert_false(partial["crit"])
	assert_eq(partial["damage_raw"], 7, "damage_raw must be roll(4)+strength(3)=7")


func test_resolve_to_hit_miss_produces_zero_damage_raw_and_consumes_no_damage_roll() -> void:
	var rng := ScriptedRandomNumberPort.new([1])
	var uc = ResolveToHitUseCaseClass.new(rng)
	var partial: Dictionary = uc.resolve_to_hit(_attacker(), _target(50, 10), _weapon(), "ac", "none", {})

	assert_false(partial["hit"])
	assert_eq(partial["damage_raw"], 0)
	assert_eq(rng._index, 1, "a miss must consume only the attack roll, never a damage roll")


func test_resolve_to_hit_crit_doubles_damage_dice_and_attribute_modifier() -> void:
	# raw=20 -> roll_total=20+3+2=25 vs ac=10 -> hit, diff=15>=10 -> crit.
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([20, 9]))
	var partial: Dictionary = uc.resolve_to_hit(_attacker(), _target(50, 10), _weapon(), "ac", "none", {})

	assert_true(partial["crit"])
	assert_eq(partial["damage_raw"], 15, "crit damage_raw must be roll(9)+strength(3)*2=15")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: get_resolution() RNG-sequence-sharing contract.
# ══════════════════════════════════════════════════════════════════════════

func test_get_resolution_returns_the_same_instance_across_calls() -> void:
	var uc = ResolveToHitUseCaseClass.new(ScriptedRandomNumberPort.new([12, 4]))
	var res_a = uc.get_resolution()
	var res_b = uc.get_resolution()
	assert_same(
		res_a, res_b,
		"get_resolution() must return the SAME Resolution instance every call, so a shared apply-phase use case continues the identical RNG sequence (ADR-002)"
	)
