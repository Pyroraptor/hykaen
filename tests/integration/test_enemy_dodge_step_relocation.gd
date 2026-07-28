extends GutTest
## tests/integration/test_enemy_dodge_step_relocation.gd — FEAT-229 (US-005 /
## FR-004, resolves DEF-002).
##
## DEF-002 named a coverage gap: every existing Dodge-Step relocation proof
## (tests/gut/test_e2e_dodge_step_capstone.gd, tests/gut/
## test_dodge_step_no_legal_hex.gd) drives the enemy-strikes-PLAYER path (the
## Skeleton attacking Titus, Titus Dodging) — none of them boot the REAL
## res://MainScene.tscn composition root and prove the REVERSE direction: a
## real PLAYER Strike against the enemy, the enemy's OWN AI-chosen Dodge
## succeeding, and the Skeleton's Combatant.hex_coord/on-screen HexGridView
## token actually relocating via infrastructure/ai_hex_choice_resolver.gd's
## AIHexChoiceResolver (MainScene.gd's `_resolve_enemy_dodge_step()`, FEAT-005
## / ADR-004) — a DISTINCT call path from the player's own Dodge-Step prompt
## (round_session.gd's `_resolve_dodge_step_prompt()`, backed by the real,
## blocking `_UIHexChoiceResolver`).
##
## This suite closes that gap with a dedicated boot-real integration test:
##   1. Boots the REAL MainScene.tscn (G2 — never a hand-wired double),
##      drives a genuine player Strike (verb_bar_view.press("STRIKE") +
##      hex_grid_view.hex_clicked.emit(), the SAME entry point
##      tests/gut/test_player_strikes_enemy_pass_through.gd already
##      establishes) against the live Skeleton, with the Skeleton's own
##      Mobility skill forced absurdly high (mirrors
##      tests/gut/test_e2e_dodge_step_capstone.gd's own
##      `_force_guaranteed_dodge_success()` convention) so BOTH
##      infrastructure/ai_reaction_policy.gd's AIReactionPolicy (which
##      decides WHETHER to Dodge, via core/domain/mobility_dodge_rule.gd)
##      AND core/rules/resolution.gd's own real, seeded mobility-check roll
##      (which decides whether the attempted Dodge actually SUCCEEDS) are
##      driven to a deterministic, guaranteed-successful outcome regardless
##      of which face the real RNG rolls for either side. Asserts the
##      Skeleton's Combatant.hex_coord AND its on-screen HexGridView token
##      both relocate to the SAME AI-chosen hex, in the SAME test run.
##   2. The dedicated "successful Dodge, but the defender (the Skeleton) has
##      ZERO legal adjacent Step hexes" edge case for this SAME
##      player-strikes-enemy path (mirrors tests/gut/
##      test_dodge_step_no_legal_hex.gd's own edge-case convention, applied
##      here to MainScene.gd's `_resolve_enemy_dodge_step()` instead of
##      round_session.gd's `_resolve_dodge_step_prompt()`): final_damage is
##      still negated (0) for a successful Dodge, the Skeleton's
##      Combatant.hex_coord and on-screen token stay exactly where they
##      started (no Step), and the coroutine completes without stalling —
##      the test itself finishing (rather than hanging) IS this criterion's
##      deadlock proof, matching test_dodge_step_no_legal_hex.gd's own
##      established convention.
##
## Verifies (test_criteria):
##   1. test_forced_skeleton_dodge_relocates_hex_coord_and_token_on_real_boot
##      passes.
##   2. test_no_legal_adjacent_hex_still_negates_hit_with_no_step passes.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ResolutionClass = preload("res://core/rules/resolution.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed: Titus
## acts first and the sole enemy (Skeleton) starts adjacent to him (see
## tests/integration/test_mainscene_skeleton_defense_eligibility.gd /
## tests/gut/test_e2e_dodge_step_capstone.gd).
const PROLOGUE_SEED: int = 42


## SequenceRNG — mirrors tests/gut/test_dodge_step_no_legal_hex.gd's own
## multi-step RNG stub exactly: returns successive values from pre-set d20/
## roll sequences, used to FORCE a genuinely successful Dodge deterministically
## (the defender's mobility check beats the attacker's roll_total) without
## depending on the real seeded RNG's actual faces.
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


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention), pinning
## seed_override=PROLOGUE_SEED for a deterministic boot (Titus vs the
## Skeleton, prologue encounter).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _force_guaranteed_dodge_success(combatant) -> void — mirrors
## tests/gut/test_e2e_dodge_step_capstone.gd's identically-purposed
## `_force_guaranteed_dodge_success()` helper, applied here to WHICHEVER
## combatant Dictionary is handed in (the Skeleton, for this suite's
## player-strikes-enemy direction) rather than always Titus: setting Mobility
## absurdly high guarantees BOTH infrastructure/ai_reaction_policy.gd's
## AIReactionPolicy chooses "dodge" (core/domain/mobility_dodge_rule.gd:
## 10+mobility > targeted_defense_value) AND core/rules/resolution.gd's own
## real, seeded mobility-check roll beats the attacker's roll_total
## regardless of which face either die actually shows.
func _force_guaranteed_dodge_success(combatant) -> void:
	combatant["skills"] = {"mobility": 500, "determination": 500}


func _combatant_id(combatant) -> String:
	return combatant.combatant_id


## _resolve_one_real_player_strike_against(instance, target_id) -> void —
## mirrors tests/gut/test_player_strikes_enemy_pass_through.gd's
## `_resolve_one_real_player_strike()` exactly, but against a specific,
## caller-chosen target_id rather than "whichever candidate happens to be
## first" — this suite needs the Skeleton specifically, not merely "some
## reachable target". Drives the REAL verb_bar_view.press("STRIKE") ->
## hex_grid_view.hex_clicked.emit() entry point, the SAME
## MainScene._verb_bar_strike_execute() call site production code fires from
## a live player click.
func _resolve_one_real_player_strike_against(instance, target_id: String) -> void:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(target_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a real player Strike, a forced-successful Skeleton Dodge, and
# the resulting relocation of BOTH Combatant.hex_coord and the on-screen
# token — all observed together in ONE boot-real MainScene test run.
# ══════════════════════════════════════════════════════════════════════════

func test_forced_skeleton_dodge_relocates_hex_coord_and_token_on_real_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316 (resolves DEF-001/PR-001): round_session/verb bar/selection
	# overlay only become live once a real combat trigger fires (see
	# MainScene.gd's own FEAT-316 doc) -- this test drives a real player
	# Strike via verb_bar_view.press("STRIKE"), so it needs the same real
	# handoff here.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	var skeleton_id: String = _combatant_id(skeleton)

	var original_hex = skeleton.hex_coord
	assert_not_null(original_hex, "fixture assumption: the Skeleton must already carry a hex_coord at boot")

	var token_before = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(token_before, "fixture assumption: hex_grid_view must already carry a token for the Skeleton")
	assert_true(token_before.hex_coord.equals(original_hex), "the on-screen token must start at the Skeleton's pre-Strike hex")

	var legal_hexes_before: Array = instance._query_selectable_step_hexes(skeleton_id)
	assert_true(legal_hexes_before.size() > 0, "fixture assumption: the Skeleton must have at least one legal Step destination in the default prologue layout")

	# Force the Skeleton's OWN reaction to a guaranteed-successful Dodge: both
	# infrastructure/ai_reaction_policy.gd's WHETHER-to-Dodge decision and
	# core/rules/resolution.gd's real seeded mobility-check roll are driven by
	# this SAME "skills.mobility" field (core/application/
	# _build_defense_context.gd's build_prehit_context()).
	_force_guaranteed_dodge_success(skeleton)

	# ── Entry point: a genuine player Strike (Titus -> Skeleton), driven
	# through the REAL production call path. ────────────────────────────────
	_resolve_one_real_player_strike_against(instance, skeleton_id)

	# Sanity check: the Skeleton must have actually relocated — otherwise
	# this test would prove nothing about the relocation contract.
	var moved_hex = skeleton.hex_coord
	assert_not_null(moved_hex, "the Skeleton must still carry a hex_coord after the resolved Strike")
	assert_false(moved_hex.equals(original_hex), "fixture assumption: the forced-successful Dodge must actually relocate the Skeleton to a NEW hex")

	# Criterion: the Skeleton's own Combatant.hex_coord (the SAME live
	# Dictionary this suite already holds a reference to via `skeleton`) was
	# updated in place.
	assert_true(
		skeleton.hex_coord.equals(moved_hex),
		"the Skeleton's Combatant.hex_coord must equal the AI-chosen hex after the successful Dodge-Step"
	)

	# Criterion: the on-screen token (HexGridView Node2D) visibly relocated to
	# the SAME hex, in the SAME test run as the Combatant.hex_coord assertion
	# above.
	var token_after = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(token_after, "the Skeleton's token must still be on record after the Dodge-Step reposition")
	assert_true(
		token_after.hex_coord.equals(moved_hex),
		"the Skeleton's on-screen token hex must update to the AI-chosen hex"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(moved_hex),
		"the Skeleton's rendered screen position must resync to the AI-chosen hex's axial-to-pixel projection"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: the "successful Dodge, zero legal adjacent Step hexes" edge
# case for the SAME player-strikes-enemy path — final_damage still negated,
# the Skeleton's hex_coord/token stay unchanged (no Step), and the call
# completes without stalling.
# ══════════════════════════════════════════════════════════════════════════

func test_no_legal_adjacent_hex_still_negates_hit_with_no_step() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._party.size() > 0, "fixture assumption: MainScene must boot with at least one party combatant")
	assert_true(instance._enemies.size() > 0, "fixture assumption: MainScene must boot with at least one enemy combatant")

	var attacker = instance._party[0]
	assert_eq(attacker.name, "Titus", "fixture: Titus (the real player combatant) is the attacker on this path")

	var defender = instance._enemies[0]
	assert_eq(defender.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	var defender_id: String = _combatant_id(defender)

	var attacker_weapon = attacker.weapon
	assert_false(attacker_weapon.is_empty(), "fixture assumption: the real player combatant must carry a weapon Dictionary")

	# ── Force a genuinely successful Dodge using the REAL domain-layer
	# resolution.gd against the REAL, booted Titus/Skeleton combatant data --
	# mob_d20=20 (the maximum possible roll) guarantees the mobility check
	# beats even a maximal attacker roll_total, while atk_d20=1 (the minimum
	# possible roll) minimizes it further. No damage roll is ever consumed
	# (roll_seq intentionally left empty) since a successful Dodge is a
	# miss -- mirrors tests/gut/test_dodge_step_no_legal_hex.gd's own
	# established convention exactly, applied to the Skeleton as defender. ──
	_force_guaranteed_dodge_success(defender)
	var original_hex = defender.hex_coord
	assert_not_null(original_hex, "fixture assumption: the Skeleton must already carry a hex_coord at boot")

	var token_before = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_before, "fixture assumption: hex_grid_view must already carry a token for the Skeleton")

	var resolution := ResolutionClass.new(SequenceRNG.new([20, 1]))
	var attack_result: Dictionary = resolution.resolve_weapon_attack(
		attacker, defender, attacker_weapon, "ac", "dodge", {"open_space_available": true}
	)

	assert_false(attack_result["hit"], "a successful Dodge (mobility check beats roll_total) must miss")
	assert_true(attack_result["defender_stepped"], "a successful Dodge must set defender_stepped=true")
	assert_eq(attack_result["damage_final"], 0, "final_damage must be negated (0) for a successful Dodge, regardless of legal Step hexes")

	# ── Drive the REAL production seam (MainScene._resolve_enemy_dodge_step(),
	# the SAME method the live player-strikes-enemy call site
	# (_verb_bar_strike_execute()) awaits) for this SAME successful-Dodge
	# outcome, but with ZERO legal adjacent hexes handed in -- the G3/G4 edge
	# case this feature covers for the enemy's own Dodge-Step, mirroring
	# test_dodge_step_no_legal_hex.gd's identical edge case for the player's
	# own Dodge-Step. The test itself completing (rather than hanging
	# forever) IS this criterion's stall/deadlock proof. ────────────────────
	await instance._resolve_enemy_dodge_step(
		defender, {"defender_stepped": attack_result["defender_stepped"]}, attacker.hex_coord, []
	)

	# Criterion: no Step occurred -- the Skeleton's Combatant.hex_coord is
	# unchanged.
	assert_true(
		defender.hex_coord.equals(original_hex),
		"a successful Dodge with zero legal Step hexes must leave the Skeleton's Combatant.hex_coord unchanged"
	)

	# Criterion: the on-screen token never moved either.
	var token_after = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_after, "the Skeleton's token must still be on record after the no-legal-hex Dodge")
	assert_true(
		token_after.hex_coord.equals(original_hex),
		"a successful Dodge with zero legal Step hexes must leave the Skeleton's on-screen token unchanged"
	)
	assert_eq(
		token_after.position, token_before.position,
		"the Skeleton's rendered screen position must be byte-for-byte unchanged when no legal Step hex exists"
	)
