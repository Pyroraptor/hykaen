extends GutTest
## tests/integration/test_charge_boot_real_e2e.gd — FEAT-286 (US-011;
## FR-011, Iteration N Combinations close-out).
##
## Boot-real (NO mocks/doubles anywhere in this suite), no-selection-UI
## proof that Charge — authored as CONTENT at data/combines/charge.tres
## (core/rules/verb_table.gd's CombineContentResource schema; queue =
## [STRIDE, STRIKE]) — is genuinely PLAYABLE end-to-end through the real
## verb path: this suite boots the REAL res://MainScene.tscn composition
## root and drives its REAL, live CombineActionController EXCLUSIVELY
## through `_controller("COMBINE")` (never reaching `_controller("STRIDE")`/
## `_controller("STRIKE")` directly itself — those sub-controllers are only
## ever reached INTERNALLY, by CombineActionController's own
## `_controller(verb_id)` lookups, exactly as every other boot-real Combine
## suite already proves — see tests/integration/test_combine_execute_
## stride_then_strike.gd / tests/unit/test_combine_single_charge.gd).
##
## Unlike those earlier suites (which hand-build the STRIDE+STRIKE
## selection queue inline), this suite first loads
## data/combines/charge.tres directly and asserts CombineActionController's
## own enter_selection() queue MATCHES that authored content exactly — the
## thing this feature adds is proving Charge is DATA, registered as
## playable content, not a hand-rolled fixture literal duplicated per test.
##
## test_criteria covered:
##   1. Selects COMBINE->Charge for a combatant (Titus) with sufficient
##      Stamina, driving it through `_controller("COMBINE")` only.
##   2. The token's position after execute() is closer to (adjacent to) the
##      target hex than before.
##   3. The Strike effect (damage) is applied to the target after the move.
##   4. The ledger (the actor's live ActionEconomy + Stamina, inspected
##      directly) shows exactly one action and one Stamina spent for the
##      WHOLE Charge.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const CHARGE_CONTENT_PATH: String = "res://data/combines/charge.tres"

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_combine_execute_stride_then_strike.gd's
## identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## Fixture geometry (mirrors tests/integration/test_combine_execute_stride_
## then_strike.gd's own established convention): the Skeleton is
## repositioned (test-fixture-only) to (3,0) — 3 hexes from Titus's start
## (0,0), out of melee reach — but exactly adjacent to (2,0), a hex already
## within Titus's real, boot-time-computed legal Stride destination set.
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


func test_charge_content_is_authored_and_valid() -> void:
	# ── Charge is genuinely DATA, not a hardcoded literal: loaded straight
	# off disk, independent of any controller. ────────────────────────────
	var content = ResourceLoader.load(CHARGE_CONTENT_PATH)
	assert_not_null(content, "data/combines/charge.tres must load as a Resource")
	assert_true(content.has_method("is_valid"), "Charge content must be a CombineContentResource (is_valid())")
	assert_true(content.is_valid(), "the authored Charge content must satisfy its own load-time invariants: %s" % [content.validation_error() if content.has_method("validation_error") else ""])
	assert_eq(content.combine_id, "CHARGE", "Charge content's combine_id must be 'CHARGE'")
	assert_eq(content.queue_verb_ids, ["STRIDE", "STRIKE"], "Charge's v0 content must queue exactly [STRIDE, STRIKE], in that order")


func test_charge_drives_the_real_verb_path_end_to_end() -> void:
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

	# ── Reposition the Skeleton (test-fixture-only, mirrors this project's
	# established boot-real Combine fixture geometry) out of melee reach of
	# Titus's START hex, but adjacent to the Stride destination Charge's
	# authored STRIDE leg will carry Titus to. ─────────────────────────────
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)

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

	# ── Resolve COMBINE through the SAME `_controller("COMBINE")` table
	# lookup every other verb is resolved through — this test never touches
	# `_controller("STRIDE")`/`_controller("STRIKE")` directly. ────────────
	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")
	assert_same(combine_controller, instance._controllers.get("COMBINE"), "the COMBINE controller must be the SAME memoized VERB_TABLE-resolved instance")

	assert_true(titus.stamina > 0, "fixture assumption: Titus must have sufficient (positive) Stamina to Combine")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")
	assert_true(combine_controller.availability(), "COMBINE->Charge must be selectable (available) for Titus at the start of his turn")

	# ── Criterion 1 — select COMBINE->Charge: the default (no-argument)
	# enter_selection() queue must match the AUTHORED Charge content exactly,
	# proving the real, live controller is genuinely driven off
	# data/combines/charge.tres rather than an independent hardcoded literal. ─
	var charge_content = ResourceLoader.load(CHARGE_CONTENT_PATH)
	assert_not_null(charge_content, "fixture assumption: data/combines/charge.tres must load")

	var selection_result: Dictionary = combine_controller.enter_selection()
	assert_true(selection_result.get("ok", false), "enter_selection() for the default (Charge) pair must succeed for an eligible actor")
	var queue: Array = selection_result.get("queue", [])
	assert_eq(queue.size(), charge_content.queue_verb_ids.size(), "the selected queue's length must match Charge's authored content")
	for i in queue.size():
		assert_eq(queue[i].verb_id, charge_content.queue_verb_ids[i], "queue entry %d's verb_id must match Charge's authored content" % i)
		assert_eq(queue[i].order_index, i, "queue entry %d's order_index must match its authored position" % i)

	# ── Ledger BEFORE — direct inspection of the actor's live ActionEconomy
	# + Stamina, the SAME collaborators every other boot-real Combine suite
	# reads its "ledger" off (this project carries no separate
	# ActionEconomyLedgerEntry object; the live ActionEconomy budget +
	# Combatant.stamina ARE the authoritative per-actor ledger). ───────────
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	var stamina_before: int = titus.stamina
	var skeleton_hp_before: int = skeleton.hp_current
	var titus_hex_before = titus.hex_coord

	var selection: Dictionary = {
		"queue": queue,
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	}

	# ── Drive the WHOLE Charge through `combine_controller.execute()` —
	# the sole entry point this test calls to resolve it. ──────────────────
	var result: Dictionary = await combine_controller.execute(selection)
	assert_true(result.get("ok", false), "a valid COMBINE->Charge execute() must resolve ok=true (result: %s)" % [result])
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "Charge must resolve STRIDE then STRIKE, in that order")

	# ── Criterion 2 — the token's position after execute() is closer to
	# (here, exactly adjacent to) the target hex than before. ──────────────
	var distance_before: int = HexMathClass.hex_distance(titus_hex_before, skeleton.hex_coord)
	var distance_after: int = HexMathClass.hex_distance(titus.hex_coord, skeleton.hex_coord)
	assert_true(distance_after < distance_before, "Titus's token must be CLOSER to the Skeleton after Charge than before it (before=%d, after=%d)" % [distance_before, distance_after])
	assert_eq(distance_after, 1, "Titus's post-Charge position must be adjacent to the Skeleton")
	assert_true(titus.hex_coord.equals(stride_destination), "Titus's live position must equal the authored STRIDE leg's destination once Charge resolves")

	# ── Criterion 3 — the Strike effect (damage) is applied to the target
	# AFTER the move. ───────────────────────────────────────────────────────
	assert_true(skeleton.hp_current < skeleton_hp_before, "the Skeleton must have taken real Strike damage once Titus's Stride put him in reach")

	# ── Criterion 4 — the ledger shows EXACTLY one action and one Stamina
	# spent for the WHOLE Charge, verified by direct ledger inspection. ────
	assert_eq(
		economy.get_remaining(), actions_remaining_before - 1,
		"Charge must spend exactly ONE action from Titus's live ActionEconomy ledger, regardless of resolving two sub-actions"
	)
	assert_false(economy.can_take_action(), "Titus's one action for the turn must now be spent, via Charge's own single Combine-level charge")
	assert_false(economy.is_self_spend_suppressed(), "the no-self-spend suppression flag must never leak past Charge's own execute() call")
	assert_eq(
		titus.stamina, stamina_before - 1,
		"Charge must spend exactly ONE Stamina from Titus's live ledger, regardless of resolving two sub-actions"
	)
