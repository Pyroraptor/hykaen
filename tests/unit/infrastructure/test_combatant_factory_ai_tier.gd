extends GutTest
## tests/unit/infrastructure/test_combatant_factory_ai_tier.gd
##
## FEAT-007 (US-007 / FR-006 / FR-008) — GUT suite for
## infrastructure/combatant_factory.gd's build_enemy_combatant() carrying
## EnemyResource.ai_tier and EnemyResource.stamina_max (authored on
## data/enemies/enemy_resource.gd by FEAT-002) into the runtime combatant
## Dictionary as combatant_dict['ai_tier'], combatant_dict['stamina'], and
## combatant_dict['stamina_max'] -- replacing the prior hardcoded
## "stamina": 0 / "stamina_max": 0 literals.
##
## Verifies (this feature's test_criteria):
##   1. Regression: skeleton.tres (ai_tier="mindless", stamina_max=0, per
##      FEAT-002's authored data) still yields stamina == 0,
##      stamina_max == 0, ai_tier == "mindless".
##   2. A fake EnemyResource fixture authored with stamina_max = 3 yields a
##      combatant_dict whose 'stamina' AND 'stamina_max' both equal 3.
##   3. core/domain/combatant.gd (the entity build_enemy_combatant() routes
##      its result through via CombatantClass.from_dict(...).to_dict()) is
##      untouched by this feature -- a diff-free check against git, since
##      from_dict()/to_dict() only round-trip a FIXED named-field schema
##      (stamina/stamina_max already round-trip; ai_tier does NOT, and must
##      therefore be re-attached to the dict by CombatantFactory itself,
##      AFTER the entity round-trip, mirroring build_party_combatant()'s
##      existing post-round-trip 'equipped_items' attachment pattern --
##      never by adding an ai_tier field to the entity).
##
## Satisfies: FEAT-007, US-007, FR-006, FR-008.

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const EnemyResourceClass = preload("res://data/enemies/enemy_resource.gd")

const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"
const ARMING_SWORD_PATH: String = "res://data/weapons/arming_sword.tres"

const ENEMY_FIXTURE_PATH: String = "user://test_combatant_factory_ai_tier_enemy_fixture.tres"

const COMBATANT_ENTITY_PATH: String = "res://core/domain/combatant.gd"


func after_each() -> void:
	var cleanup_dir := DirAccess.open("user://")
	if cleanup_dir != null:
		cleanup_dir.remove(ENEMY_FIXTURE_PATH)


func _save_enemy_fixture(res: EnemyResourceClass) -> String:
	var save_err := ResourceSaver.save(res, ENEMY_FIXTURE_PATH)
	assert_eq(save_err, OK, "ResourceSaver.save() must succeed for this test's fixture EnemyResource")
	return ENEMY_FIXTURE_PATH


# ══════════════════════════════════════════════════════════════════════════
# 1. Regression: skeleton.tres (ai_tier="mindless", stamina_max=0)
# ══════════════════════════════════════════════════════════════════════════

func test_skeleton_yields_stamina_0_stamina_max_0_ai_tier_mindless_regression() -> void:
	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, null, "skeleton_1")

	assert_false(combatant.has("error"), "skeleton.tres must build a valid combatant with no error; got: %s" % str(combatant))
	assert_eq(combatant.get("stamina", -1), 0, "regression: skeleton.tres-derived combatant['stamina'] must be 0")
	assert_eq(combatant.get("stamina_max", -1), 0, "regression: skeleton.tres-derived combatant['stamina_max'] must be 0")
	assert_eq(
		combatant.get("ai_tier", "SENTINEL"), "mindless",
		"regression: skeleton.tres-derived combatant['ai_tier'] must be 'mindless'"
	)


# ══════════════════════════════════════════════════════════════════════════
# 2. Fake EnemyResource with stamina_max = 3
# ══════════════════════════════════════════════════════════════════════════

func test_fake_enemy_resource_stamina_max_3_yields_matching_stamina_and_stamina_max() -> void:
	var res := EnemyResourceClass.new()
	res.name = "StaminaFixtureEnemy"
	res.hp = 5
	res.str = 1
	res.dex = 1
	res.weapon_paths = [ARMING_SWORD_PATH]
	res.ai_tier = "grunt"
	res.stamina_max = 3
	var enemy_path: String = _save_enemy_fixture(res)

	var factory := CombatantFactoryClass.new()
	var combatant: Dictionary = factory.build_enemy_combatant(enemy_path, null, "stamina_fixture_1")

	assert_false(combatant.has("error"), "fixture EnemyResource must build a valid combatant with no error; got: %s" % str(combatant))
	assert_eq(combatant.get("stamina", -1), 3, "combatant['stamina'] must match the fixture's stamina_max (3) -- a freshly-built combatant starts at full stamina")
	assert_eq(combatant.get("stamina_max", -1), 3, "combatant['stamina_max'] must match the fixture's authored stamina_max (3)")
	assert_eq(combatant.get("ai_tier", "SENTINEL"), "grunt", "combatant['ai_tier'] must carry the fixture's authored ai_tier ('grunt') verbatim")


# ══════════════════════════════════════════════════════════════════════════
# 3. core/domain/combatant.gd is untouched by this feature (diff-free check)
# ══════════════════════════════════════════════════════════════════════════

func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://")


func _git_available() -> bool:
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", _repo_root(), "rev-parse", "--is-inside-work-tree"], out, true)
	return rc == 0


func test_combatant_entity_is_unmodified_diff_free_check() -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping core/domain/combatant.gd diff-free check")
		return

	# Mirrors tests/unit/application/test_ai_planner_port.gd's established
	# `git status --porcelain -- <path>` convention: any staged, unstaged,
	# or untracked change to core/domain/combatant.gd fails this test,
	# proving this feature attached 'ai_tier' to the combatant Dictionary
	# WITHOUT modifying the entity's from_dict()/to_dict() fixed schema.
	var out: Array = []
	var rc: int = OS.execute(
		"git",
		["-C", _repo_root(), "status", "--porcelain", "--", "core/domain/combatant.gd"],
		out,
		true
	)
	var combined: String = ""
	for line in out:
		combined += String(line)

	assert_eq(rc, 0, "git status --porcelain -- core/domain/combatant.gd must exit 0")
	assert_eq(
		combined.strip_edges(), "",
		(
			"core/domain/combatant.gd must remain byte-for-byte unmodified by "
			+ "FEAT-007 -- ai_tier must be attached to the combatant dict by "
			+ "CombatantFactory itself (post round-trip), not by extending the "
			+ "entity's fixed from_dict()/to_dict() schema. Offending git status "
			+ "output:\n%s"
		) % combined
	)


func test_combatant_entity_file_exists_and_is_readable() -> void:
	assert_true(FileAccess.file_exists(COMBATANT_ENTITY_PATH), "core/domain/combatant.gd must still exist at its documented path")
