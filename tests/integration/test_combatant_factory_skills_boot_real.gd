extends GutTest
## tests/integration/test_combatant_factory_skills_boot_real.gd — FEAT-236
## (US-001 / US-002, resolves DEF-001).
##
## DEF-001 named a "green tests, dead in play" gap: infrastructure/
## combatant_factory.gd's build_enemy_combatant()/build_party_combatant()
## never threaded EnemyResource.skills / CharacterResource.skills (the
## mobility/determination scores authored on data/enemies/skeleton.tres and
## data/characters/titus.tres) onto the runtime combatant Dictionary at all.
## Every UNIT test of the Dodge decision (e.g. tests/infrastructure/
## test_ai_reaction_policy.gd, core/application/tests/test_reaction_window_prehit.gd)
## hand-builds its own combatant Dictionary and populates "skills" itself, so
## those suites stayed green while the REAL composition-root factory silently
## built combatants with NO "skills" key at all -- core/application/
## _build_defense_context.gd's build_prehit_context() reads
## target.get("skills", {}).get("mobility", 0), so every real enemy/party
## combatant's Mobility silently defaulted to 0 in live play regardless of
## its authored .tres data, even boot-real tests that already exercise this
## path (e.g. tests/integration/test_enemy_dodge_step_relocation.gd) never
## caught it because THEY manually override combatant["skills"] on the built
## dict as a workaround before driving their Strike.
##
## This suite closes that gap with THREE tests, all sharing this ONE file per
## FEAT-236's file scope:
##
##   1. test_build_enemy_combatant_threads_real_skeleton_mobility_skill --
##      a direct (non-boot) unit test: CombatantFactory.build_enemy_combatant()
##      against the REAL data/enemies/skeleton.tres resource returns a dict
##      whose skills.mobility equals the resource's OWN authored value (1),
##      non-zero/non-default.
##   2. test_build_party_combatant_threads_real_titus_mobility_skill --
##      the mirrored unit test for build_party_combatant() against the REAL
##      data/characters/titus.tres, proving no field-name drift: both paths
##      populate the SAME "skills" key with the SAME "mobility" sub-key.
##   3. test_real_skeleton_mobility_drives_live_dodge_decision_boot_real --
##      the boot-real proof: boots the REAL res://MainScene.tscn composition
##      root (G2 -- never a hand-wired double) TWICE, drives a genuine player
##      Strike (verb_bar_view.press("STRIKE") + hex_grid_view.hex_clicked.emit(),
##      the SAME entry point tests/gut/test_player_strikes_enemy_pass_through.gd
##      already establishes) against the live Skeleton in each boot, and
##      NEVER overrides the built combatant's "skills"/"mobility" field by
##      hand -- the ONLY thing that differs between the two boots is the
##      Skeleton's OWN EnemyResource.skills Dictionary (mutated directly on
##      the cached data/enemies/skeleton.tres Resource between boots, exactly
##      per this feature's design notes: "flips skeleton.tres mobility
##      between two fixture values across two runs"). No monkey-patching:
##      no class/method is replaced, only the authored data field this
##      feature's fix threads through is varied. The observable proof is
##      core/rules/round_events.gd's real AttackEvent.defense_value emitted
##      by core/application/resolve_action_use_case.gd's
##      _finalize_strike_result() -- when infrastructure/ai_reaction_policy.gd's
##      AIReactionPolicy (real, undoubled) declines Dodge (10+mobility does
##      NOT exceed the Skeleton's authored ac=14), the attack resolves against
##      the Skeleton's passive ac (defense_value == 14); when it genuinely
##      CHOOSES Dodge (10+mobility DOES exceed ac=14), core/rules/resolution.gd
##      substitutes the real, seeded Mobility check (d20 + mobility) for the
##      passive ac, so defense_value is provably driven upward by the
##      SAME authored mobility value, entirely through this feature's fix.
##
## Verifies (test_criteria):
##   1. build_enemy_combatant(skeleton.tres)'s "skills" dict's "mobility" key
##      equals EnemyResource.skills.mobility (non-zero, matches fixture data).
##   2. build_party_combatant(titus.tres)'s "skills" dict's "mobility" key
##      equals CharacterResource.skills.mobility, mirroring the enemy path
##      with no field-name drift.
##   3. A real Strike, real PreHitAvoidance window, Dodge/Pass outcome
##      provably driven by the Skeleton's actual mobility_skill value across
##      two flipped fixture runs.
##   4. Regression: existing US-002/US-003 policy unit tests still pass
##      unchanged (verified by running the full suite alongside this file,
##      not inside it -- see scripts/test_command.sh).

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const EnemyResourceClass    = preload("res://data/enemies/enemy_resource.gd")
const RoundEventsClass      = preload("res://core/rules/round_events.gd")

const SKELETON_TRES_PATH: String = "res://data/enemies/skeleton.tres"
const TITUS_TRES_PATH: String    = "res://data/characters/titus.tres"
const MAIN_SCENE_PATH: String    = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/integration/test_enemy_dodge_step_relocation.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## SKELETON_AC -- data/enemies/skeleton.tres's own authored, unmodified
## "ac" field (never overridden by this suite). Dodge is "worthwhile" per
## core/domain/mobility_dodge_rule.gd iff 10+mobility strictly exceeds this
## value.
const SKELETON_AC: int = 14

## LOW_MOBILITY -- skeleton.tres's OWN authored default (data/enemies/
## skeleton.tres: skills = {"mobility": 1, ...}). 10+1=11 does NOT exceed
## SKELETON_AC(14) -- Dodge is not worthwhile, AIReactionPolicy must Pass.
const LOW_MOBILITY: int = 1

## HIGH_MOBILITY -- a second fixture value this suite flips the Skeleton's
## EnemyResource.skills to for its second boot. 10+20=30 DOES strictly
## exceed SKELETON_AC(14) -- Dodge is worthwhile, AIReactionPolicy must
## genuinely choose it.
const HIGH_MOBILITY: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: build_enemy_combatant(skeleton.tres) threads the REAL
# EnemyResource.skills.mobility value onto the combatant dict.
# ══════════════════════════════════════════════════════════════════════════

func test_build_enemy_combatant_threads_real_skeleton_mobility_skill() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_TRES_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "fixture assumption: skeleton.tres must build a valid combatant with no error")

	var enemy_resource = ResourceLoader.load(SKELETON_TRES_PATH)
	var expected_mobility: int = int(enemy_resource.skills.get("mobility", -1))
	assert_eq(expected_mobility, LOW_MOBILITY, "fixture assumption: skeleton.tres's authored skills.mobility must be 1")

	var skills: Dictionary = combatant.get("skills", {})
	assert_true(skills.has("mobility"), "build_enemy_combatant() must populate a 'skills' dict carrying a 'mobility' key")
	assert_eq(
		skills.get("mobility", -1), expected_mobility,
		"build_enemy_combatant()'s combatant['skills']['mobility'] must equal EnemyResource.skills.mobility (%d), not a missing/zero-defaulted value" % expected_mobility
	)
	assert_ne(skills.get("mobility", 0), 0, "the threaded mobility value must be non-zero (skeleton.tres's real fixture data), not the pre-fix default")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: build_party_combatant(titus.tres) threads the REAL
# CharacterResource.skills.mobility value onto the combatant dict, with the
# SAME "skills"/"mobility" key names as the enemy path (no field-name drift).
# ══════════════════════════════════════════════════════════════════════════

func test_build_party_combatant_threads_real_titus_mobility_skill() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_party_combatant(TITUS_TRES_PATH, null, "titus_1")

	var character_resource = ResourceLoader.load(TITUS_TRES_PATH)
	var expected_mobility: int = int(character_resource.skills.get("mobility", -1))
	assert_eq(expected_mobility, 2, "fixture assumption: titus.tres's authored skills.mobility must be 2")

	var skills: Dictionary = combatant.get("skills", {})
	assert_true(skills.has("mobility"), "build_party_combatant() must populate a 'skills' dict carrying a 'mobility' key (same shape as build_enemy_combatant())")
	assert_eq(
		skills.get("mobility", -1), expected_mobility,
		"build_party_combatant()'s combatant['skills']['mobility'] must equal CharacterResource.skills.mobility (%d)" % expected_mobility
	)
	assert_ne(skills.get("mobility", 0), 0, "the threaded mobility value must be non-zero (titus.tres's real fixture data)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: a real Strike against a real, booted Skeleton drives a real
# PreHitAvoidance Dodge/Pass decision that is provably keyed off the
# Skeleton's OWN EnemyResource.skills.mobility value -- flipped across two
# boots, never hand-overridden on the built combatant dict.
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene() -> Node -- instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention), pinning
## seed_override=PROLOGUE_SEED for a deterministic boot.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func _combatant_id(combatant) -> String:
	return combatant.display_id()


## _resolve_one_real_player_strike_against(instance, target_id) -> void --
## mirrors tests/integration/test_enemy_dodge_step_relocation.gd's
## identically-purposed helper: drives the REAL verb_bar_view.press("STRIKE")
## -> hex_grid_view.hex_clicked.emit() entry point, the SAME
## MainScene._verb_bar_strike_execute() call site production code fires from
## a live player click.
func _resolve_one_real_player_strike_against(instance, target_id: String) -> void:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(target_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)


func _sole_attack_event(instance):
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	return attack_events[0]


## _skeleton_resource_ref -- holds a STRONG reference to the loaded, REAL
## data/enemies/skeleton.tres EnemyResource for the duration of criterion 3's
## test. Godot's ResourceLoader.load() path-cache is refcount-backed: once
## the LAST strong reference to a loaded Resource drops, the engine frees it,
## and the NEXT load() call re-parses the .tres file fresh from disk
## (resetting any in-memory mutation). This suite's own local variables would
## otherwise be exactly that "last strong reference", freed the moment
## _set_skeleton_mobility() returns -- so the mutation below is held alive
## here, on the GutTest script instance itself, across both boots.
var _skeleton_resource_ref = null


## _set_skeleton_mobility(mobility) -> Dictionary -- mutates the REAL
## data/enemies/skeleton.tres EnemyResource's OWN "skills" Dictionary field in
## place (kept alive via _skeleton_resource_ref above), so the mutation is
## visible to every subsequent boot's CombatantFactory.build_enemy_combatant()
## call -- exactly the "flips skeleton.tres mobility between two fixture
## values" technique this feature's design notes call for. This is REAL
## authored data being varied, not a monkey-patched method/class -- the SAME
## EnemyResource, CombatantFactory, and AIReactionPolicy classes run
## unmodified in both runs. Returns the ORIGINAL skills Dictionary so the
## caller can restore it afterward and avoid bleeding fixture state into
## later tests sharing this same engine process.
func _set_skeleton_mobility(mobility: int) -> Dictionary:
	_skeleton_resource_ref = ResourceLoader.load(SKELETON_TRES_PATH)
	var original_skills: Dictionary = _skeleton_resource_ref.skills.duplicate()
	var mutated_skills: Dictionary = original_skills.duplicate()
	mutated_skills["mobility"] = mobility
	_skeleton_resource_ref.skills = mutated_skills
	return original_skills


func _restore_skeleton_skills(original_skills: Dictionary) -> void:
	var enemy_resource = ResourceLoader.load(SKELETON_TRES_PATH)
	enemy_resource.skills = original_skills
	_skeleton_resource_ref = null


func test_real_skeleton_mobility_drives_live_dodge_decision_boot_real() -> void:
	# ── Run A: the Skeleton's OWN authored default (LOW_MOBILITY=1) -- 10+1=11
	# does not exceed ac=14, so the REAL AIReactionPolicy must Pass, and the
	# real Strike resolves against the Skeleton's passive ac. ─────────────────
	var original_skills: Dictionary = _set_skeleton_mobility(LOW_MOBILITY)

	var pass_instance = _boot_main_scene()
	await get_tree().process_frame

	var pass_skeleton = _skeleton(pass_instance)
	var pass_skills: Dictionary = pass_skeleton.skills
	assert_eq(
		pass_skills.get("mobility", -1), LOW_MOBILITY,
		"fixture assumption: the booted Skeleton combatant's skills.mobility must equal the low fixture value -- proves the value flowed from EnemyResource through CombatantFactory with NO manual override"
	)

	var pass_skeleton_id: String = _combatant_id(pass_skeleton)
	_resolve_one_real_player_strike_against(pass_instance, pass_skeleton_id)
	var pass_attack_event = _sole_attack_event(pass_instance)

	assert_eq(
		pass_attack_event.defense_value, SKELETON_AC,
		"low mobility (1): 10+1=11 does not exceed ac=14 -- AIReactionPolicy must Pass, so the Strike resolves against the Skeleton's passive ac (defense_value=14), not a Mobility check"
	)

	# ── Run B: the Skeleton's skills.mobility flipped to HIGH_MOBILITY=20 --
	# 10+20=30 DOES exceed ac=14, so the REAL AIReactionPolicy must genuinely
	# CHOOSE Dodge, substituting core/rules/resolution.gd's real, seeded
	# Mobility check (d20+20, in [21,40]) for the passive ac. ─────────────────
	_set_skeleton_mobility(HIGH_MOBILITY)

	var dodge_instance = _boot_main_scene()
	await get_tree().process_frame

	var dodge_skeleton = _skeleton(dodge_instance)
	var dodge_skills: Dictionary = dodge_skeleton.skills
	assert_eq(
		dodge_skills.get("mobility", -1), HIGH_MOBILITY,
		"fixture assumption: the booted Skeleton combatant's skills.mobility must equal the flipped high fixture value -- proves the SAME wiring re-reads the resource's CURRENT data on each boot, with NO manual override"
	)

	var dodge_skeleton_id: String = _combatant_id(dodge_skeleton)
	_resolve_one_real_player_strike_against(dodge_instance, dodge_skeleton_id)
	var dodge_attack_event = _sole_attack_event(dodge_instance)

	# Cleanup BEFORE asserting, so a failed assertion never leaves the shared,
	# cached skeleton.tres Resource mutated for later tests in this same
	# engine process.
	_restore_skeleton_skills(original_skills)

	assert_ne(
		dodge_attack_event.defense_value, SKELETON_AC,
		"high mobility (20): 10+20=30 exceeds ac=14 -- AIReactionPolicy must genuinely choose Dodge, so the Strike must NOT resolve against the passive ac(14) anymore"
	)
	assert_true(
		dodge_attack_event.defense_value >= 10 + HIGH_MOBILITY,
		"a genuinely-chosen Dodge substitutes the real Mobility check (d20[>=1]+mobility(20)) for ac -- defense_value must be at least 21, proving the flipped mobility value(20), not a stale/default one, drove the decision (got %d)" % dodge_attack_event.defense_value
	)

	# ── The criterion itself: the SAME code path, the SAME Skeleton fixture,
	# the SAME two combatant-factory functions under test, produced a
	# DIFFERENT Dodge/Pass outcome purely because the Skeleton's OWN
	# EnemyResource.skills.mobility value differed between the two runs. ─────
	assert_ne(
		pass_attack_event.defense_value, dodge_attack_event.defense_value,
		"the Dodge/Pass outcome (and therefore defense_value) must change when the Skeleton's real mobility_skill value changes"
	)
