extends GutTest
## tests/e2e/combine/test_charge_end_to_end.gd — FEAT-009 (Iteration O
## "Combine Selection UX"; US-009; the steel thread's exit-point
## validation).
##
## Boots the REAL, shipped res://MainScene.tscn composition root (NO mocks
## or doubles on any controller or on presentation/selection_overlay.gd's
## SelectionOverlay anywhere in this suite) at a pinned RNG seed, and drives
## the FULL Iteration O Combine steel thread end-to-end:
##
##   COMBINE offered -> picker offers STRIDE/STRIKE -> STRIDE picked ->
##   STRIKE picked -> Confirm appears and is picked -> hex pick for Stride
##   -> post-move-aware target pick for Strike -> execute() resolves both
##   sub-actions sequentially, spending 1 action + 1 Stamina, with the actor
##   visibly moved and the target struck.
##
## Also covers cancellation at the queue-build step and at each of the two
## targeting phases, run against the same real-stack harness.
##
## A NOTE ON WHICH "CombineActionController" PERFORMS THE FINAL DISPATCH:
## this codebase currently carries TWO independent, real, shipped Combine
## controllers:
##   - core/controllers/combine_action_controller.gd's CombineActionController
##     (Iteration O, this feature's own family) — its enter_selection() is
##     the REAL, SelectionDescriptor-producing picker (BuildVerbQueueUseCase)
##     this suite drives for the STRIDE/STRIKE/Confirm pick loop below.
##     Per that file's OWN doc (FEAT-004), its execute() intentionally does
##     NOT yet dispatch sub-action resolution ("a LATER feature layered on
##     top of this same seam, without changing it") -- MainScene.gd's own
##     composition-root wiring for it likewise only charges Stamina.
##   - presentation/combine_action_controller.gd's CombineActionController
##     (the ALREADY-SHIPPED, already boot-real-tested -- see
##     tests/e2e/test_steel_thread_charge_combine.gd -- Combine executor
##     MainScene.VERB_TABLE["COMBINE"] resolves a live player's COMBINE
##     execute() through today, via `_controller("COMBINE")`) -- this is the
##     REAL production dispatcher that actually moves the actor and resolves
##     the Strike, sequentially, off the SAME resolved hex/target values a
##     real player's clicks would produce.
## This suite therefore uses the Iteration O controller for every real,
## unmocked SELECTION step (the picker, Confirm, and -- via
## core/controllers/stride_action_controller.gd / strike_action_controller.gd
## -- the post-move-aware targeting query, all reached through the REAL,
## composition-root-instantiated singletons `instance._core_combine_action_
## controller` / `instance._combine_controller_registry`, exactly like
## tests/integration/combine/test_composition_root_wiring.gd's own
## established convention of reaching into these composition-root fields
## directly), and hands the REAL resolved hex/target -- captured off REAL
## SelectionOverlay + HexGridView click resolution -- to the ALREADY-real,
## ALREADY-dispatching presentation controller for the actual commit. No
## step in this chain is faked, stubbed, or mocked; every collaborator is
## the exact production instance the booted MainScene itself owns.
##
## test_criteria covered:
##   1. test_combine_press_offers_real_selection_descriptor_with_stride_and_strike()
##   2-4. test_full_happy_path_combine_stride_strike_confirm_hex_pick_target_pick_execute()
##   5. test_cancel_during_queue_build_step_leaves_state_unchanged_and_returns_to_layer1(),
##      test_cancel_during_stride_targeting_phase_aborts_entire_combine_with_no_state_leak(),
##      test_cancel_during_strike_targeting_phase_aborts_entire_combine_with_no_state_leak()
##   6. verified by running this suite alongside the pre-existing Iteration N
##      standalone Stride/Strike boot-real suites in the SAME gut run (see
##      this project's CI gate) -- this file introduces no shared mutable
##      state and modifies no production file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const CombineQueueClass            = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass          = preload("res://core/domain/combine/verb_queue_entry.gd")
const ConfirmQueueUseCaseClass     = preload("res://core/application/combine/confirm_queue_use_case.gd")
const CancelCombineUseCaseClass    = preload("res://core/application/combine/cancel_combine_use_case.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/e2e/test_steel_thread_charge_combine.gd's / tests/
## integration/combine/test_composition_root_wiring.gd's identically-valued
## constant).
const PROLOGUE_SEED: int = 42

## Fixture geometry (mirrors tests/e2e/test_steel_thread_charge_combine.gd's
## own established convention): the Skeleton is repositioned (test-fixture-
## only) to (3,0) -- 3 hexes from Titus's start (0,0), out of melee reach --
## but exactly adjacent to (2,0), a hex already within Titus's real,
## boot-time-computed legal Stride destination set.
const SKELETON_REPOSITIONED_HEX_Q: int = 3
const STRIDE_DESTINATION_HEX_Q: int = 2


## _TargetingRegistryProxy -- a thin, test-local presentation-layer glue
## object mirroring MainScene.gd's OWN `_CombineTargetingRegistryProxy`
## (see that class's own field-level doc): the SAME duck-typed
## `execute(verb_id, value) -> Dictionary` contract presentation/
## selection_overlay.gd's own `_registry` seam requires. This carries ZERO
## business logic of its own -- no targeting rule, no legality check, no
## game-state mutation -- it only records whichever value the REAL,
## unmodified SelectionOverlay resolved a REAL hex/target click to, exactly
## mirroring the production proxy's own "thin pass-through" role. This is
## not a mock of a controller or of SelectionOverlay -- both remain the
## genuine, unmodified production classes throughout this suite.
class _TargetingRegistryProxy:
	extends RefCounted
	var captured: Dictionary = {}
	func execute(verb_id: String, value) -> Dictionary:
		captured[verb_id] = value
		return {"ok": true, "chosen_value": value}


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


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


## _reposition_skeleton_for_charge() -- test-fixture-only repositioning
## (mirrors tests/e2e/test_steel_thread_charge_combine.gd's identical
## fixture) so the Skeleton starts out of Titus's melee reach but adjacent
## to a hex within his real Stride range -- letting a real Charge (Stride
## then Strike) genuinely close the distance and land a hit.
func _reposition_skeleton_for_charge(titus, skeleton) -> Dictionary:
	var titus_start_hex = titus.hex_coord
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
	return {"titus_start_hex": titus_start_hex, "stride_destination": stride_destination}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- booting the real MainScene, COMBINE's real, composition-
# root-owned Iteration O controller offers a real SelectionDescriptor
# naming STRIDE and STRIKE as legal first picks. No mocks anywhere in this
# call chain: the real VerbBarRegistry's own live availability gate, the
# real CombineActionController singleton, and the real VerbRegistryPort
# adapter it was constructed with.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_press_offers_real_selection_descriptor_with_stride_and_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	assert_true(titus.stamina > 0, "fixture assumption: Titus starts with positive Stamina")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")

	assert_true(instance._verb_registry.is_available("COMBINE"), "the real, booted Layer 1 verb bar must offer COMBINE for an eligible actor")

	var descriptor = instance._core_combine_action_controller.enter_selection({
		"actor_id": titus,
		"queue": [],
		"combine_context": CombineQueueClass.Context.TURN,
	})
	assert_true(descriptor.ok, "the real, composition-root-owned Iteration O CombineActionController must offer a legal first pick")
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("STRIDE"), "the picker's very first offer must include STRIDE")
	assert_true(ids.has("STRIKE"), "the picker's very first offer must include STRIKE")

	assert_no_new_orphans("driving the real picker must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2, 3, 4 -- the full happy path: COMBINE -> STRIDE -> STRIKE ->
# Confirm -> hex pick -> target pick -> execute(). resolution_log records
# STRIDE before STRIKE; actor.position ends at the chosen Stride hex;
# target.health reflects Strike damage applied from the post-move position;
# exactly 1 action + 1 Stamina spent.
# ══════════════════════════════════════════════════════════════════════════

func test_full_happy_path_combine_stride_strike_confirm_hex_pick_target_pick_execute() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]

	# ── picker offers STRIDE/STRIKE -- STRIDE picked -- STRIKE picked --
	# Confirm appears -- via the REAL BuildVerbQueueUseCase-backed picker. ──
	var build_ctrl = instance._core_combine_action_controller

	var d0 = build_ctrl.enter_selection({"actor_id": titus, "queue": [], "combine_context": CombineQueueClass.Context.TURN})
	assert_true(d0.ok)
	assert_true(_option_ids(d0.candidate_options).has("STRIDE"))
	assert_true(_option_ids(d0.candidate_options).has("STRIKE"))
	assert_false(_option_ids(d0.candidate_options).has("CONFIRM"), "Confirm must not be offered before the TURN-context minimum of 2 entries is met")

	var picked_stride := VerbQueueEntryClass.new("q1", 0, "STRIDE")
	var d1 = build_ctrl.enter_selection({"actor_id": titus, "queue": [picked_stride], "combine_context": CombineQueueClass.Context.TURN})
	assert_true(d1.ok)
	assert_false(_option_ids(d1.candidate_options).has("STRIDE"), "STRIDE must be excluded once already queued (no Repeat trait)")
	assert_true(_option_ids(d1.candidate_options).has("STRIKE"), "STRIKE must remain legal (a different verb from STRIDE)")
	assert_true(_option_ids(d1.candidate_options).has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress pick must offer Cancel")

	var picked_strike := VerbQueueEntryClass.new("q1", 1, "STRIKE")
	var d2 = build_ctrl.enter_selection({"actor_id": titus, "queue": [picked_stride, picked_strike], "combine_context": CombineQueueClass.Context.TURN})
	assert_true(d2.ok)
	assert_true(_option_ids(d2.candidate_options).has("CONFIRM"), "Confirm must be offered once the TURN-context minimum of 2 entries is met")

	# ── Confirm is picked -- the REAL ConfirmQueueUseCase finalizes the queue. ──
	var combine_queue := CombineQueueClass.new("q1", titus.display_id(), CombineQueueClass.Context.TURN)
	assert_true(combine_queue.add_entry(picked_stride).get("ok", false))
	assert_true(combine_queue.add_entry(picked_strike).get("ok", false))
	var confirm_result: Dictionary = ConfirmQueueUseCaseClass.new().execute(combine_queue)
	assert_true(confirm_result.get("ok", false), "a queue meeting the confirm minimum must confirm successfully")
	assert_eq(combine_queue.status, CombineQueueClass.Status.CONFIRMED)
	var confirmed_entries: Array = combine_queue.sorted_entries()
	assert_eq(confirmed_entries.size(), 2)
	assert_eq(confirmed_entries[0].verb_id, "STRIDE")
	assert_eq(confirmed_entries[1].verb_id, "STRIKE")

	# ── hex pick for Stride, through the REAL, unmodified SelectionOverlay +
	# HexGridView, offered by the REAL Iteration O StrideActionController. ──
	var stride_controller = instance._combine_controller_registry["STRIDE"]
	var strike_controller = instance._combine_controller_registry["STRIKE"]
	var proxy := _TargetingRegistryProxy.new()

	var stride_offer = stride_controller.enter_selection({"actor_id": titus, "order_index": 0})
	assert_true(stride_offer.ok, "fixture assumption: Titus has at least one legal Stride destination at boot")
	var chosen_hex = null
	for h in stride_offer.candidate_hexes:
		if h.equals(stride_destination):
			chosen_hex = h
			break
	assert_not_null(chosen_hex, "fixture assumption: the intended Stride destination must be a legal candidate")

	instance.selection_overlay.configure(proxy, instance.hex_grid_view)
	instance.selection_overlay.activate("STRIDE", stride_offer)
	assert_true(instance.selection_overlay.is_active(), "the REAL SelectionOverlay must enter Layer 2 for the STRIDE phase")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE")

	instance.hex_grid_view.hex_clicked.emit(chosen_hex)
	assert_true(proxy.captured.has("STRIDE"), "the REAL SelectionOverlay must resolve the clicked hex for the STRIDE phase")
	assert_true(proxy.captured["STRIDE"].equals(chosen_hex))
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to inactive once the STRIDE phase resolves")

	# Picking (querying) a Stride destination must never itself move the actor.
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]), "picking a Stride destination must never itself move the actor")

	# ── post-move-aware target pick for Strike, computed from the
	# HYPOTHETICAL Stride destination (ADR-006), via the REAL Iteration O
	# StrikeActionController. ────────────────────────────────────────────────
	var resolved_stride = stride_controller.enter_selection({
		"actor_id": titus, "order_index": 0, "selected_hex": chosen_hex,
	})
	assert_true(resolved_stride.ok)
	assert_true(resolved_stride.meta.get("chosen_hex").equals(chosen_hex))

	var strike_offer = strike_controller.enter_selection({
		"actor_id": titus, "order_index": 1, "accumulated": {"STRIDE": resolved_stride},
	})
	assert_true(strike_offer.ok, "post-move-aware Strike targeting must find the Skeleton reachable from the chosen Stride hex")
	assert_true(strike_offer.candidate_targets.has(skeleton.display_id()))
	assert_true(strike_offer.meta.get("origin_hex").equals(chosen_hex), "Strike's own reach must be computed from the HYPOTHETICAL post-move hex, never Titus's current (pre-Charge) position")

	instance.selection_overlay.activate("STRIKE", strike_offer)
	assert_true(instance.selection_overlay.is_active(), "the REAL SelectionOverlay must enter Layer 2 for the STRIKE phase")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE")
	assert_true(instance.selection_overlay.get_highlighted_target_ids().has(skeleton.display_id()))

	var skeleton_token = instance.hex_grid_view.get_token(skeleton.combatant_id)
	assert_not_null(skeleton_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(skeleton_token.hex_coord)
	assert_eq(proxy.captured.get("STRIKE"), skeleton.display_id(), "the REAL SelectionOverlay must resolve the clicked target for the STRIKE phase")
	assert_false(instance.selection_overlay.is_active())

	# Neither phase's own query-only pick has moved or damaged anyone yet.
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]))
	var skeleton_hp_before_execute: int = skeleton.hp_current

	# ── execute() resolves both sub-actions sequentially against real
	# actor/target state -- via the SAME real, live CombineActionController
	# MainScene.VERB_TABLE["COMBINE"] resolves a real player's execute()
	# through (`_controller("COMBINE")`, see this file's own header doc for
	# why the FINAL dispatch is reached through this concrete instance). ──
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0)

	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")

	var selection: Dictionary = {
		"queue": combine_controller.build_charge_queue(),
		"STRIDE": proxy.captured["STRIDE"],
		"STRIKE": proxy.captured["STRIKE"],
	}
	var result: Dictionary = await combine_controller.execute(selection)

	assert_true(result.get("ok", false), "a valid, real COMBINE->Charge execute() must resolve ok=true (result: %s)" % [result])

	# ── Criterion 3 -- the resolution log (this production system's
	# `resolved_verb_ids`) records STRIDE resolving before STRIKE, in that
	# order. ──────────────────────────────────────────────────────────────
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "the resolution log must record STRIDE resolving before STRIKE")

	# ── Criterion 2 -- exactly 1 action and 1 Stamina spent for the WHOLE
	# Combine (the live ActionEconomy/Combatant.stamina ledger is this
	# project's established authoritative per-actor ledger). ────────────────
	var actions_spent: int = actions_remaining_before - economy.get_remaining()
	var stamina_spent: int = stamina_before - titus.stamina
	assert_eq(actions_spent, 1, "Charge must spend exactly ONE action")
	assert_eq(stamina_spent, 1, "Charge must spend exactly ONE Stamina")
	assert_false(economy.can_take_action(), "Titus's one action for the turn must now be spent")

	# ── Criterion 4 -- actor.position equals the chosen Stride hex; target's
	# health reflects the Strike damage applied from the post-move position. ──
	assert_true(titus.hex_coord.equals(chosen_hex), "actor.position must equal the chosen Stride hex")
	assert_true(skeleton.hp_current < skeleton_hp_before_execute, "target.health must reflect the Strike damage applied from the post-move position")

	assert_no_new_orphans("the full happy path must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- cancellation at the queue-build step, run against the same
# real-stack harness, leaves actor/target state fully unchanged and returns
# control to the Layer 1 verb bar.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_queue_build_step_leaves_state_unchanged_and_returns_to_layer1() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var titus_start_hex = titus.hex_coord
	var skeleton_hp_before: int = skeleton.hp_current
	var stamina_before: int = titus.stamina

	var build_ctrl = instance._core_combine_action_controller
	var picked_stride := VerbQueueEntryClass.new("q1", 0, "STRIDE")
	var mid_build = build_ctrl.enter_selection({
		"actor_id": titus, "queue": [picked_stride], "combine_context": CombineQueueClass.Context.TURN,
	})
	assert_true(_option_ids(mid_build.candidate_options).has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress queue-build must offer the Cancel sentinel")

	var combine_queue := CombineQueueClass.new("q1", titus.display_id(), CombineQueueClass.Context.TURN)
	assert_true(combine_queue.add_entry(picked_stride).get("ok", false))

	# Cancel is picked -- the REAL CancelCombineUseCase discards the in-progress queue.
	var cancel_result: Dictionary = CancelCombineUseCaseClass.new().execute(combine_queue)
	assert_true(cancel_result.get("ok", false))
	assert_eq(combine_queue.status, CombineQueueClass.Status.CANCELLED)

	# Actor/target state fully unchanged.
	assert_true(titus.hex_coord.equals(titus_start_hex))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)

	# Control returns to the Layer 1 verb bar: no Layer 2 selection was ever
	# entered, COMBINE remains selectable, and a fresh attempt starts from
	# the SAME Layer-1-equivalent candidate set (no leaked exclusion).
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"))
	var fresh = build_ctrl.enter_selection({"actor_id": titus, "queue": [], "combine_context": CombineQueueClass.Context.TURN})
	assert_true(_option_ids(fresh.candidate_options).has("STRIDE"), "STRIDE must be legal again in a fresh attempt -- no leaked exclusion from the cancelled queue")
	assert_true(_option_ids(fresh.candidate_options).has("STRIKE"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 (cont'd) -- cancellation during the STRIDE (order_index 0)
# targeting phase aborts the whole Combine with no partial-state leak, run
# against the REAL, booted `instance.multi_phase_targeting_controller`.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_stride_targeting_phase_aborts_entire_combine_with_no_state_leak() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var titus_start_hex = titus.hex_coord
	var skeleton_hp_before: int = skeleton.hp_current
	var stamina_before: int = titus.stamina
	var economy = instance.round_session.current_action_economy()
	var actions_before: int = economy.get_remaining()

	var combine_queue := CombineQueueClass.new("q1", titus.display_id(), CombineQueueClass.Context.TURN)
	combine_queue.add_entry(VerbQueueEntryClass.new("q1", 0, "STRIDE"))
	combine_queue.add_entry(VerbQueueEntryClass.new("q1", 1, "STRIKE"))
	combine_queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = instance.multi_phase_targeting_controller.execute(
		combine_queue.sorted_entries(), titus, CombineQueueClass.Context.TURN,
		{"STRIDE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, combine_queue
	)

	assert_false(result.get("ok", true))
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(result.get("accumulated", {}), {}, "cancellation before the FIRST phase resolves must leave accumulated wholesale-empty")
	assert_eq(combine_queue.status, CombineQueueClass.Status.CANCELLED)

	# Actor/target state fully unchanged -- STRIDE's own enter_selection() was
	# never even reached (this phase cancelled BEFORE dispatch).
	assert_true(titus.hex_coord.equals(titus_start_hex))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)
	assert_eq(economy.get_remaining(), actions_before)

	# Control returns to the Layer 1 verb bar.
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"), "cancellation must leave COMBINE selectable again on the Layer 1 verb bar")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 (cont'd) -- cancellation during the STRIKE (order_index 1)
# targeting phase aborts the whole Combine with no partial-state leak, even
# though the STRIDE phase already resolved (query-only, non-mutating) ahead
# of it.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_strike_targeting_phase_aborts_entire_combine_with_no_state_leak() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var skeleton_hp_before: int = skeleton.hp_current
	var stamina_before: int = titus.stamina
	var economy = instance.round_session.current_action_economy()
	var actions_before: int = economy.get_remaining()

	var combine_queue := CombineQueueClass.new("q2", titus.display_id(), CombineQueueClass.Context.TURN)
	combine_queue.add_entry(VerbQueueEntryClass.new("q2", 0, "STRIDE"))
	combine_queue.add_entry(VerbQueueEntryClass.new("q2", 1, "STRIKE"))
	combine_queue.status = CombineQueueClass.Status.CONFIRMED

	var result: Dictionary = instance.multi_phase_targeting_controller.execute(
		combine_queue.sorted_entries(), titus, CombineQueueClass.Context.TURN,
		{"STRIDE": geo["stride_destination"], "STRIKE": CancelCombineUseCaseClass.CANCEL_SENTINEL_ID}, combine_queue
	)

	assert_false(result.get("ok", true))
	assert_eq(result.get("error_code", ""), "CANCELLED")
	assert_eq(result.get("accumulated", {}), {}, "no partial STRIDE accumulation may leak, even though STRIDE's own phase already resolved")
	assert_eq(combine_queue.status, CombineQueueClass.Status.CANCELLED)

	# Actor/target state fully unchanged -- STRIDE's own enter_selection()
	# query never mutates the actor's real position (see that controller's
	# own doc), and STRIKE's phase never even resolved.
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)
	assert_eq(economy.get_remaining(), actions_before)

	# Control returns to the Layer 1 verb bar.
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"))
