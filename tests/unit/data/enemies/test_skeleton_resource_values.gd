extends GutTest
## tests/unit/data/enemies/test_skeleton_resource_values.gd
##
## GUT unit tests for FEAT-002 (FR-007 / iteration-G P1): pinned attribute
## and defense values authored onto data/enemies/skeleton.tres.
##
## data/enemies/enemy_resource.gd (FEAT-001) already defines the
## ac/fortitude/reflex/will defense fields plus the constitution/intuition/
## willpower/social/intellect attribute fields. This feature POPULATES
## skeleton.tres with the pinned v0 starting values documented in
## docs/iterations/iteration-G-per-turn-action-economy-and-enemy-defense.org:
##
##   Attributes: str=2, dex=1 (unchanged from prior iteration),
##               constitution=1, intuition=1, willpower=1, social=1,
##               intellect=0 (no consumer yet, template completeness only).
##   Defenses (authored/pinned, NOT derived at load):
##               ac=14, fortitude=13, reflex=12, will=12.
##
## Test criteria covered:
##   1. Loading skeleton.tres yields ac=14, fortitude=13, reflex=12, will=12.
##   2. intellect=0 and other attribute fields load with pinned values.
##   3. str/dex values are unchanged from the prior iteration's authored
##      values (str=2, dex=1).
##
## FEAT-003 (US-003): skeleton.tres was subsequently rewired to reference
## data/weapons/arming_sword.tres via weapon_paths, removing the legacy
## inline weapon dict and top-level parry_bonus/block_value/block_die
## fields. None of the fields asserted below are weapon-related, so this
## file's assertions are unaffected by that change; test_skeleton_str_dex_
## unchanged_from_prior_iteration() below additionally guards that the
## non-weapon fields it checks remain stable across the FEAT-003 rewrite.

const SKELETON_TRES_PATH := "res://data/enemies/skeleton.tres"


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: pinned defense values — ac=14, fortitude=13, reflex=12, will=12
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_defenses_load_with_pinned_values() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return

	assert_eq(res.ac, 14, "skeleton.ac must be pinned to 14; got: %s" % str(res.ac))
	assert_eq(res.fortitude, 13, "skeleton.fortitude must be pinned to 13; got: %s" % str(res.fortitude))
	assert_eq(res.reflex, 12, "skeleton.reflex must be pinned to 12; got: %s" % str(res.reflex))
	assert_eq(res.will, 12, "skeleton.will must be pinned to 12; got: %s" % str(res.will))


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: intellect=0 and other attribute fields load with pinned values
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_attributes_load_with_pinned_values() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return

	assert_eq(res.constitution, 1, "skeleton.constitution must be pinned to 1; got: %s" % str(res.constitution))
	assert_eq(res.intuition, 1, "skeleton.intuition must be pinned to 1; got: %s" % str(res.intuition))
	assert_eq(res.willpower, 1, "skeleton.willpower must be pinned to 1; got: %s" % str(res.willpower))
	assert_eq(res.social, 1, "skeleton.social must be pinned to 1; got: %s" % str(res.social))
	assert_eq(res.intellect, 0, "skeleton.intellect must be pinned to 0 (no consumer yet); got: %s" % str(res.intellect))


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: str/dex unchanged from prior iteration's authored values
# ══════════════════════════════════════════════════════════════════════════════

func test_skeleton_str_dex_unchanged_from_prior_iteration() -> void:
	var res = ResourceLoader.load(SKELETON_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(res, "skeleton.tres must load")
	if res == null:
		return

	assert_eq(res.str, 2, "skeleton.str must remain unchanged at 2; got: %s" % str(res.str))
	assert_eq(res.dex, 1, "skeleton.dex must remain unchanged at 1; got: %s" % str(res.dex))

	# Other pre-existing fields must also be untouched by this feature.
	assert_eq(res.name, "Skeleton")
	assert_eq(res.hp, 8)
