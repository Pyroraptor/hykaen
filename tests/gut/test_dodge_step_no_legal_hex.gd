extends GutTest
## tests/gut/test_dodge_step_no_legal_hex.gd
##
## GUT suite for FEAT-003 (US-003, Dodge-Step steel thread edge-condition
## coverage): proves the "successful Dodge, but the defender has ZERO legal
## adjacent Step hexes" edge case (this steel thread's error_handling design
## note #1, ADR-005 guard-clause discipline) end-to-end against the REAL
## res://MainScene.tscn composition root (G2 -- never a hand-wired double),
## per this feature's test_criteria:
##
##   1. final_damage is negated (0) for a successful Dodge, even when the
##      defender has zero legal adjacent Step hexes.
##   2. The Step-selection prompt is never shown in this branch.
##   3. The turn coroutine completes within the test timeout (no stall/
##      deadlock) -- proven the same way tests/gut/test_async_reaction_propagation.gd's
##      own deadlock-proof convention already establishes: "the test itself
##      completing (rather than hanging forever) IS the proof".
##
## This is deliberately NOT a new algorithm: ResolveDodgeStepUseCase
## (core/application/resolve_dodge_step_use_case.gd) already carries the
## "legal_hexes.is_empty() -> return immediately, no prompt, no await" guard
## clause established by FEAT-002 -- this suite is the dedicated edge-
## condition regression test that pins it, plus proves the damage-negation
## half of the contract (which lives entirely in core/rules/resolution.gd's
## resolve_to_hit() math: a successful Dodge is recorded as a miss, so
## damage_raw/damage_final are already 0 regardless of legal_hexes -- see
## that use case's own doc for why it never re-derives this math itself).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ResolutionClass = preload("res://core/rules/resolution.gd")


## SequenceRNG -- multi-step RNG stub mirroring tests/unit/test_dodge_reaction.gd's
## own SequenceRNG: returns successive values from pre-set d20/roll sequences,
## used to FORCE a successful Dodge deterministically (mobility check beats
## the attacker's roll_total) without depending on the real seeded RNG.
class SequenceRNG:
	var _d20_seq: Array
	var _roll_seq: Array
	var _d20_idx: int = 0
	var _roll_idx: int = 0

	func _init(d20_seq: Array, roll_seq: Array = []) -> void:
		_d20_seq = d20_seq
		_roll_seq = roll_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(_die_size: int, _count: int) -> int:
		var val: int = _roll_seq[_roll_idx % _roll_seq.size()]
		_roll_idx += 1
		return val


## CountingScriptedHexChoiceResolver -- a concrete HexChoiceResolverPort test
## double (mirrors tests/gut/test_dodge_step_prompt.gd's own double of the
## same name/role exactly): records every resolve() call so this suite can
## assert the Step-selection prompt was NEVER invoked.
class CountingScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var call_count: int = 0
	var received_legal_hexes: Array = []

	func resolve(legal_hexes: Array):
		call_count += 1
		received_legal_hexes = legal_hexes
		if legal_hexes.is_empty():
			return null
		return legal_hexes[0]


## _boot_main_scene() -> Node -- instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention, e.g.
## tests/gut/test_dodge_step_prompt.gd), pinning seed_override=42 for a
## deterministic boot (Titus vs the Skeleton, prologue encounter).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1-3: a successful Dodge with ZERO legal adjacent Step hexes still
# negates final_damage, never shows the Step-selection prompt, and the
# coroutine completes without stalling/deadlocking.
# ══════════════════════════════════════════════════════════════════════════

func test_successful_dodge_with_zero_legal_hexes_negates_damage_never_prompts_and_never_stalls() -> void:
	var instance = _boot_main_scene()

	assert_true(instance._party.size() > 0, "fixture assumption: MainScene must boot with at least one party combatant")
	assert_true(instance._enemies.size() > 0, "fixture assumption: MainScene must boot with at least one enemy combatant")

	var defender: Dictionary = instance.round_session.current_actor()
	assert_eq(defender.get("name", ""), "Titus", "fixture: Titus (the real player combatant) must be the current actor at boot")

	var attacker: Dictionary = instance._enemies[0]
	var attacker_weapon: Dictionary = attacker.get("weapon", {})
	assert_false(attacker_weapon.is_empty(), "fixture assumption: the real enemy combatant must carry a weapon Dictionary")

	# ── Criterion 1: force a genuinely successful Dodge (mobility check beats
	# the attacker's roll_total) using the REAL domain-layer resolution.gd
	# against the REAL, booted Titus/Skeleton combatant data -- mob_d20=20
	# (the maximum possible roll) guarantees the mobility check beats even a
	# maximal attacker roll_total, while atk_d20=1 (the minimum possible roll)
	# minimizes it further. No damage roll is ever consumed (roll_seq
	# intentionally left empty) since a successful Dodge is a miss. ────────
	var resolution := ResolutionClass.new(SequenceRNG.new([20, 1]))
	var attack_result: Dictionary = resolution.resolve_weapon_attack(
		attacker, defender, attacker_weapon, "ac", "dodge", {"open_space_available": true}
	)

	assert_false(attack_result["hit"], "a successful Dodge (mobility check beats roll_total) must miss")
	assert_true(attack_result["defender_stepped"], "a successful Dodge must set defender_stepped=true")
	assert_eq(attack_result["damage_final"], 0, "final_damage must be negated (0) for a successful Dodge, regardless of legal Step hexes")

	# ── Criteria 2 + 3: drive the REAL RoundSession seam
	# (_resolve_dodge_step_prompt(), the same production seam
	# tests/gut/test_dodge_step_prompt.gd exercises) for this SAME
	# successful-Dodge outcome, but force the Step-hex query to report ZERO
	# legal adjacent hexes -- the G3/G4 edge case this feature covers --
	# without touching movement_input_controller's own (unmodified)
	# adjacency rule. Override the REAL, composition-root-wired
	# hex_choice_resolver field (never a resolver self-wired/constructed in
	# isolation, G2) with a counting double so "was the prompt invoked" is
	# directly observable. ──────────────────────────────────────────────────
	var scripted := CountingScriptedHexChoiceResolver.new()
	instance.hex_choice_resolver = scripted
	instance.round_session.set_step_hex_query_fn(func(_combatant_id): return [])

	# The test itself completing (rather than hanging forever) IS this
	# criterion's stall/deadlock proof -- mirrors
	# tests/gut/test_async_reaction_propagation.gd's own established
	# deadlock-proof convention: a real self-deadlock here (e.g. an
	# unconditional await on a never-resolved prompt) would hang this
	# test/CI forever instead of reaching the assertions below.
	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": attack_result["defender_stepped"]})

	assert_eq(scripted.call_count, 0, "a successful Dodge with zero legal Step hexes must NEVER invoke the Step-selection prompt")
	assert_true(scripted.received_legal_hexes.is_empty(), "no legal hexes must ever have been offered to the resolver (it was never called)")


# ══════════════════════════════════════════════════════════════════════════
# Application-layer unit coverage (no Godot/scene dependency): pins
# ResolveDodgeStepUseCase's own guard clause directly, isolated from the
# MainScene boot above.
# ══════════════════════════════════════════════════════════════════════════

const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")


func test_use_case_never_prompts_or_awaits_for_a_successful_dodge_with_zero_legal_hexes() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var prompt_invoked: bool = false
	var resolver_fn := func(_legal_hexes: Array):
		prompt_invoked = true
		return null

	# defender_stepped=true (a genuinely successful Dodge) but legal_hexes=[]
	# (zero legal adjacent hexes) -- this feature's exact edge case.
	var result: Dictionary = await use_case.resolve("defender-1", true, [], resolver_fn)

	assert_false(result["prompted"], "a successful Dodge with zero legal hexes must report prompted=false")
	assert_null(result["chosen_hex"], "no hex can ever be chosen when zero legal hexes exist")
	assert_false(prompt_invoked, "the resolver Callable must never be invoked (no prompt, no await) for an empty legal_hexes set")
