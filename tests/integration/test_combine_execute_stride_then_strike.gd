extends GutTest
## tests/integration/test_combine_execute_stride_then_strike.gd — FEAT-007
## (US-007; the steel thread's exit point).
##
## Boot-real integration complement to tests/unit/test_combine_stamina_decrement.gd
## / tests/unit/test_combine_enter_selection.gd / tests/unit/test_sub_action_queue_resolution.gd
## (all of which drive CombineActionController with hand-rolled fake session/
## controller doubles): this suite drives the REAL res://MainScene.tscn
## composition root's own CombineActionController -- resolved through the
## SAME memoized `_controller("COMBINE")` table lookup every other verb is
## resolved through -- and lets it orchestrate the REAL, live
## StrideActionController + StrikeActionController (also resolved via
## `_controller(verb_id)`, never a hard preload/class_name reference from
## combine_action_controller.gd -- see that file's own FEAT-001 doc +
## tests/unit/test_combine_action_controller_registration.gd's static-scan
## criterion, which this suite does not re-implement).
##
## Fixture geometry (PROLOGUE_SEED=42): Titus starts at (0,0); the Skeleton
## is repositioned (test-fixture-only, mirroring
## tests/integration/test_reserve_gate_boot_real.gd's own "force the
## Skeleton's own real field" convention) from its authored (1,0) out to
## (3,0) -- 3 hexes from Titus's start (out of melee reach: Strike from the
## START position must fail) but exactly ADJACENT to (2,0), a hex already
## within Titus's real, boot-time-computed legal Stride destination set (2
## hexes from (0,0), well within Movement.DEFAULT_SPEED=4, and unoccupied at
## every point in this fixture). The Skeleton's own "ac" is forced to an
## absurdly low guaranteed-hit value (mirrors every other boot-real suite's
## AC_GUARANTEED_HIT convention) so the resolved Strike's damage is
## deterministic without touching RNG/seed math.
##
## test_criteria covered:
##   1. execute() with a valid STRIDE+STRIKE selection moves the actor's
##      position to the chosen hex (2,0) BEFORE Strike resolves.
##   2. Strike's reach/target-validity check reads the actor's POST-move
##      position, not the pre-move one -- proven by asserting the Skeleton is
##      NOT among Strike's reachable targets from Titus's start hex, yet the
##      Combine (Stride then Strike, in that order) still fully resolves and
##      deals real damage.
##   3. Sub-controllers are resolved via `_controller(verb_id)` -- asserted
##      by a spy Callable wrapped around the REAL, composition-root-wired
##      `_controller_for_fn` the booted CombineActionController already
##      carries (never a direct StrideActionController/StrikeActionController
##      class reference constructed by this test).
##   4. Final combatant position equals the Stride destination and the
##      target has taken real Strike damage.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const StrideActionControllerClass  = preload("res://presentation/stride_action_controller.gd")
const StrikeActionControllerClass  = preload("res://presentation/strike_action_controller.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_reserve_gate_boot_real.gd's identically-
## named/valued constant).
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT — mirrors this project's established convention: an
## absurdly low AC guarantees a hit with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -1000

## SKELETON_START_DISTANCE / STRIDE_DESTINATION — see file-level doc's
## "fixture geometry" section for the arithmetic these encode.
const SKELETON_REPOSITIONED_HEX_Q: int = 3
const STRIDE_DESTINATION_HEX_Q: int = 2


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _titus(instance):
	assert_true(instance._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var titus = instance._party[0]
	assert_eq(titus.name, "Titus", "fixture assumption: the first party member is Titus")
	return titus


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


## _drain_action_economy_to_reserve_floor(ae) -> void — mirrors
## tests/integration/test_reserve_gate_boot_real.gd's identically-named/
## purposed helper: spends reactions off the Skeleton's OWN real, live
## ActionEconomy one at a time (spend_reaction(), never a hand-constructed/
## fresh ActionEconomy) until exactly the RESERVE floor remains, so
## infrastructure/ai_reaction_policy.gd's real RESERVE gate forces every
## reaction (Dodge included) to Pass regardless of how "worthwhile" AC_
## GUARANTEED_HIT would otherwise make Dodge look. This is used here
## instead of the "Immobilized" condition convention other AC_GUARANTEED_HIT
## suites rely on, because MainScene._refresh_off_guard_conditions() (fired
## by this test's own Stride, via _after_successful_move()) OVERWRITES a
## combatant's entire "conditions" list every time either side moves --
## wiping out a manually-set "Immobilized" tag before Strike ever resolves.
## Draining the ActionEconomy instead is immune to that: it is a completely
## separate live field _refresh_off_guard_conditions() never touches.
func _drain_action_economy_to_reserve_floor(ae) -> void:
	while ae.get_remaining() > ActionEconomyClass.RESERVE:
		ae.spend_reaction()
	assert_eq(ae.get_remaining(), ActionEconomyClass.RESERVE, "fixture assumption: the Skeleton's own live ActionEconomy must be drained to exactly the RESERVE floor")


func test_execute_moves_actor_then_resolves_strike_against_the_now_reachable_target() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	assert_not_null(titus_start_hex, "fixture assumption: Titus carries a hex_coord before the Combine")
	assert_eq([titus_start_hex.q, titus_start_hex.r], [0, 0], "fixture assumption: Titus starts at (0,0) per the prologue encounter resource")

	# ── Reposition the Skeleton (test-fixture-only) out of melee reach of
	# Titus's START hex, but adjacent to the Stride destination this test
	# drives Titus to. ──────────────────────────────────────────────────────
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)
	skeleton.ac = AC_GUARANTEED_HIT
	# AC_GUARANTEED_HIT is so far below any possible defense_value that it
	# would ALSO make MobilityDodgeRule.dodge_worthwhile() (10 + mobility >
	# targeted_defense_value) unconditionally true, routing this Strike into
	# the PreHitAvoidance Dodge branch (substituting a real Mobility-skill
	# roll for the deliberately-tanked AC) instead of resolving a guaranteed
	# hit. Disabled here via the Skeleton's own live ActionEconomy RESERVE
	# floor (see _drain_action_economy_to_reserve_floor()'s own doc above)
	# rather than the "Immobilized" condition convention, since this test's
	# own Stride would otherwise wipe that condition via
	# MainScene._refresh_off_guard_conditions().
	var skeleton_action_economy = instance._action_economy_for(skeleton)
	assert_not_null(skeleton_action_economy, "fixture assumption: the Skeleton must have a live ActionEconomy wired at boot")
	_drain_action_economy_to_reserve_floor(skeleton_action_economy)

	var stride_destination = HexCoordClass.new(STRIDE_DESTINATION_HEX_Q, 0)

	assert_true(
		HexMathClass.hex_distance(titus_start_hex, stride_destination) <= MovementClass.DEFAULT_SPEED,
		"test setup: the Stride destination must be within Titus's real Speed"
	)
	assert_true(
		HexMathClass.hex_distance(titus_start_hex, skeleton.hex_coord) > 1,
		"test setup: the repositioned Skeleton must be OUT of melee reach of Titus's START hex"
	)
	assert_eq(
		HexMathClass.hex_distance(stride_destination, skeleton.hex_coord), 1,
		"test setup: the repositioned Skeleton must be adjacent to the Stride destination"
	)

	# ── Criterion 2 (half 1) — from Titus's PRE-move position, the Skeleton
	# is genuinely NOT a reachable Strike target. If Strike's reach check
	# read the pre-move position, the Combine below would fail. ───────────
	var strike_controller_before = instance._controller("STRIKE")
	assert_false(
		strike_controller_before.reachable_target_ids().has(skeleton.display_id()),
		"fixture assumption: the Skeleton must be UNREACHABLE from Titus's pre-move (start) position"
	)

	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus starts with positive Stamina")
	var skeleton_hp_before: int = skeleton.hp_current

	# ── Criterion 3 — resolve the COMBINE controller through the SAME
	# `_controller("COMBINE")` table lookup every other verb uses, then wrap
	# (never replace/fork) its already-injected, composition-root-wired
	# `_controller_for_fn` with a spy that only OBSERVES which verb_ids get
	# looked up, delegating every call straight through to the REAL
	# `instance._controller`. ──────────────────────────────────────────────
	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")
	assert_same(combine_controller, instance._controllers.get("COMBINE"), "the COMBINE controller must be the SAME memoized VERB_TABLE-resolved instance")

	var real_controller_for: Callable = combine_controller._controller_for_fn
	assert_true(real_controller_for.is_valid(), "fixture assumption: the real, booted CombineActionController must already carry a live controller_for resolver")

	var looked_up_verb_ids: Array = []
	var spy_controller_for := func(verb_id: String):
		looked_up_verb_ids.append(verb_id)
		return real_controller_for.call(verb_id)
	combine_controller._controller_for_fn = spy_controller_for

	var selection: Dictionary = {
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	}

	var result: Dictionary = await combine_controller.execute(selection)

	# ── Criterion 1 + 4 — the actor's position now equals the Stride
	# destination, and the queue fully resolved in STRIDE-then-STRIKE order. ─
	assert_true(result.get("ok", false), "a valid STRIDE+STRIKE Combine must resolve ok=true (result: %s)" % [result])
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the Combine must resolve STRIDE then STRIKE, in that order")
	assert_true(titus.hex_coord.equals(stride_destination), "Titus's live position must equal the Stride destination once the Combine resolves")

	# ── Criterion 3 — both sub-controllers were reached via
	# `_controller(verb_id)`, in queue order, never a direct class reference. ─
	assert_eq(looked_up_verb_ids, ["STRIDE", "STRIKE"], "CombineActionController must resolve its sub-actions via _controller(verb_id), in STRIDE-then-STRIKE order")
	assert_true(real_controller_for.call("STRIDE") is StrideActionControllerClass, "the verb_id 'STRIDE' must resolve to a real StrideActionController via the SAME table lookup")
	assert_true(real_controller_for.call("STRIKE") is StrikeActionControllerClass, "the verb_id 'STRIKE' must resolve to a real StrikeActionController via the SAME table lookup")

	# ── Criterion 2 (half 2) + 4 — the Strike genuinely resolved against the
	# Skeleton using Titus's POST-move position (only reachable from (2,0),
	# never from (0,0) -- proven above), dealing real, positive damage. ─────
	assert_true(skeleton.hp_current < skeleton_hp_before, "the Skeleton must have taken real Strike damage once Titus's Stride put him in reach")

	# ── Combine's own single-charge invariant: exactly one Stamina spent at
	# the Combine level, never a second/duplicate spend from the sub-actions
	# it orchestrates. ──────────────────────────────────────────────────────
	assert_eq(titus.stamina, stamina_before - 1, "the Combine must spend exactly one Stamina, regardless of how many sub-actions it resolved")
