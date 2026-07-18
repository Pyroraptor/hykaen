extends GutTest
## tests/regression/test_seed_determinism.gd — FEAT-166 (US-012 /
## FR-008,FR-009,FR-010,FR-012): regression verification of preserved
## behaviors on the KEPT single-stack MainScene composition root (post
## FEAT-001/FEAT-002 UI consolidation, iteration D).
##
## Re-runs/retargets the seed-determinism guarantee (NFR-002/NFR-006,
## FEAT-002/FEAT-003, ADR-004) through BOTH of infrastructure/seed_policy.gd's
## precedence entry points against the real, shipped res://MainScene.tscn --
## proving the consolidation to a single presentation/* stack did not
## silently break determinism:
##
##   1. the in-process `seed_override` injectable -- ALREADY exercised as a
##      double-boot event-sequence diff by tests/integration/
##      test_steel_thread_prologue_encounter.gd's
##      test_determinism_two_independent_mainscene_boots_produce_identical_event_sequence().
##      Re-affirmed here for 1:1 traceability against the specifically KEPT
##      stack, per this feature's regression-verification scope.
##   2. the HYKAEN_SEED environment variable -- NOT previously exercised via
##      a real double-MainScene-boot event-sequence diff:
##      tests/gut/test_seed_policy.gd (FEAT-003) only proves
##      infrastructure/seed_policy.gd's pure resolve()/resolve_from_
##      environment() functions resolve the correct int; it never drives
##      that resolved seed through a full MainScene boot and diffs the
##      resulting event sequence. That gap is closed here.
##   3. seed_override's precedence over a simultaneously-set HYKAEN_SEED env
##      var (ADR-004), verified against a REAL MainScene boot's
##      `resolved_seed` field -- not just seed_policy.gd's pure resolve().
##
## test_criteria satisfied: "Seed determinism test passes identically with
## HYKAEN_SEED set and with an injectable seed override, against the kept
## stack."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const SeedPolicyClass = preload("res://infrastructure/seed_policy.gd")

## PINNED_SEED — mirrors the prologue fixture's known-good seed=42
## (established convention across this codebase's determinism suites).
const PINNED_SEED: int = 42

## ENV_SEED — an arbitrary, distinct seed used only for the HYKAEN_SEED
## env-var scenarios below (deliberately different from PINNED_SEED so the
## two code paths can never be confused for one another).
const ENV_SEED: int = 4242


# ══════════════════════════════════════════════════════════════════════════
# Real-environment isolation: set/unset the actual HYKAEN_SEED process
# environment variable around each test, restoring whatever the process
# already had beforehand -- mirrors tests/gut/test_seed_policy.gd's own
# before_each()/after_each() convention so no test state leaks to any other
# GUT script sharing this headless run.
# ══════════════════════════════════════════════════════════════════════════

var _had_env_var_before: bool = false
var _original_env_value: String = ""


func before_each() -> void:
	_had_env_var_before = OS.has_environment(SeedPolicyClass.ENV_VAR_NAME)
	if _had_env_var_before:
		_original_env_value = OS.get_environment(SeedPolicyClass.ENV_VAR_NAME)


func after_each() -> void:
	if _had_env_var_before:
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, _original_env_value)
	else:
		OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)


func _boot_main_scene_with_seed_override(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _boot_main_scene_with_no_override():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	add_child_autofree(instance)
	return instance


## _assert_event_sequences_identical(log_1, log_2, context) -> void -- exact
## byte-identical, ordered event-sequence diff, mirroring the established
## determinism-proof convention (tests/integration/
## test_steel_thread_prologue_encounter.gd).
func _assert_event_sequences_identical(log_1: Array, log_2: Array, context: String) -> void:
	assert_eq(
		log_2.size(), log_1.size(),
		"%s: two independent boots of the same seed must emit the same NUMBER of events" % context
	)
	var count: int = mini(log_1.size(), log_2.size())
	for i in range(count):
		assert_eq(
			log_2[i].to_dict(), log_1[i].to_dict(),
			"%s: event[%d] must be byte-identical across two independent boots of the same seed" % [context, i]
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — seed_override injectable determinism, against the kept
# single presentation/* stack (US-001/US-002 iteration D consolidation).
# ══════════════════════════════════════════════════════════════════════════

func test_seed_override_produces_identical_event_sequence_across_two_boots() -> void:
	var instance_1 = _boot_main_scene_with_seed_override(PINNED_SEED)
	await get_tree().process_frame
	var instance_2 = _boot_main_scene_with_seed_override(PINNED_SEED)
	await get_tree().process_frame

	assert_eq(instance_1.resolved_seed, PINNED_SEED, "seed_override must resolve to the pinned seed")
	assert_eq(
		instance_2.resolved_seed, instance_1.resolved_seed,
		"two independent boots pinned to the same seed_override must resolve to the identical seed"
	)

	# Sanity check that this is genuinely the KEPT single stack, not a
	# resurrected duplicate (FEAT-001/US-001): exactly one HexGridView token
	# set, matching the prologue's two combatants.
	assert_eq(
		instance_1.hex_grid_view.get_token_count(), 2,
		"fixture assumption: the kept single HexGridView stack renders both prologue combatants"
	)

	assert_eq(
		instance_2.round_session.current_actor().name, instance_1.round_session.current_actor().name,
		"two independent boots of the same seed_override must position the RoundSession cursor on the identical first actor"
	)

	_assert_event_sequences_identical(instance_1.event_sink.log, instance_2.event_sink.log, "seed_override=%d" % PINNED_SEED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — HYKAEN_SEED environment-variable determinism, against the
# kept stack. NOT previously exercised as a real double-MainScene-boot
# event-sequence diff (see file-level doc).
# ══════════════════════════════════════════════════════════════════════════

func test_hykaen_seed_env_var_produces_identical_event_sequence_across_two_boots() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(ENV_SEED))

	var instance_1 = _boot_main_scene_with_no_override()
	await get_tree().process_frame
	var instance_2 = _boot_main_scene_with_no_override()
	await get_tree().process_frame

	assert_eq(instance_1.resolved_seed, ENV_SEED, "HYKAEN_SEED must be resolved into resolved_seed when no seed_override is set")
	assert_eq(instance_2.resolved_seed, ENV_SEED, "HYKAEN_SEED must be resolved identically for a second independent boot")

	assert_eq(
		instance_2.round_session.current_actor().name, instance_1.round_session.current_actor().name,
		"two independent boots reading the same HYKAEN_SEED must position the RoundSession cursor on the identical first actor"
	)

	_assert_event_sequences_identical(instance_1.event_sink.log, instance_2.event_sink.log, "HYKAEN_SEED=%d" % ENV_SEED)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — seed_override precedence over HYKAEN_SEED (ADR-004), proven
# against a REAL MainScene boot's resolved_seed, not just seed_policy.gd's
# pure resolve() function.
# ══════════════════════════════════════════════════════════════════════════

func test_seed_override_takes_precedence_over_hykaen_seed_env_var_on_a_real_boot() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(ENV_SEED))

	var instance = _boot_main_scene_with_seed_override(PINNED_SEED)
	await get_tree().process_frame

	assert_eq(
		instance.resolved_seed, PINNED_SEED,
		"a real MainScene boot's seed_override must take precedence over a simultaneously-set HYKAEN_SEED env var (ADR-004)"
	)
	assert_ne(
		instance.resolved_seed, ENV_SEED,
		"the env var's seed must NOT have been used when an in-process seed_override was also supplied"
	)


## test_two_different_seeds_are_not_required_to_produce_identical_sequences()
## -- a light sanity guard against a vacuously-true determinism suite (e.g. a
## fixture bug that always produces the same event log regardless of seed):
## two DIFFERENT seed_override values are not asserted to differ on every
## single run (RNG collisions are legitimately possible), but they at least
## may resolve to different `resolved_seed` values, proving seed_override is
## genuinely threaded through to `resolved_seed` and not silently ignored.
func test_seed_override_value_is_genuinely_threaded_through_to_resolved_seed() -> void:
	var instance_a = _boot_main_scene_with_seed_override(PINNED_SEED)
	await get_tree().process_frame
	var instance_b = _boot_main_scene_with_seed_override(PINNED_SEED + 1)
	await get_tree().process_frame

	assert_eq(instance_a.resolved_seed, PINNED_SEED)
	assert_eq(instance_b.resolved_seed, PINNED_SEED + 1)
	assert_ne(
		instance_a.resolved_seed, instance_b.resolved_seed,
		"two distinct seed_override values must resolve to two distinct resolved_seed values"
	)
