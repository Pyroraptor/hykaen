extends GutTest
## tests/integration/test_combine_preflight_and_order_index_e2e.gd —
## FEAT-309 (US-004/US-009; resolves FIND-305, FIND-306).
##
## Boot-real (NO mocks/doubles anywhere in this suite) regression suite
## proving FIX-001 (the non-mutating economy/Stamina preflight gate added to
## core/controllers/combine_action_controller.gd's execute() —
## `_preflight_resource_check()`) and FIX-002 (the authoritative
## order_index-contiguity re-check added to
## core/application/combine/validate_combine_queue_use_case.gd's execute())
## hold together in the FULLY WIRED, live composition-root system — not just
## in the isolated unit-test doubles tests/unit/controllers/
## test_combine_action_controller_execute.gd and tests/unit/domain/combine/
## test_combine_queue.gd already pin.
##
## Drives the REAL, live steel thread exclusively through the SAME
## production signal chain tests/smoke/test_release_readiness_smoke.gd
## (FEAT-304) and tests/e2e/combine/test_charge_end_to_end.gd already
## exercise: a real VerbBarView.press("COMBINE"), real
## SelectionOverlay.choose_option()/hex_grid_view.hex_clicked emissions,
## and the REAL, live-wired `instance._core_combine_action_controller`
## (the SAME instance MultiPhaseTargetingController/MainScene's own
## `_finish_combine_targeting()` invoke on loop exhaustion, per
## core/controllers/combine_action_controller.gd's FEAT-297 doc) — no
## sub-action controller is ever mocked/doubled anywhere in this suite.
##
## test_criteria covered:
##   1. Boot-real happy path: the full COMBINE -> Stride -> Strike ->
##      Confirm -> execute() flow still spends exactly 1 action + 1 Stamina,
##      moves the actor, and deals Strike damage from the post-move hex —
##      unaffected by FIX-001/FIX-002.
##   2. Boot-real abort path (exhausted action economy): identical flow up
##      through Confirm and the Stride hex-pick, then the actor's real,
##      live ActionEconomy is driven to `is_spent() == true` (the SAME
##      economy `_GdCombineActionEconomyPort` — MainScene.gd's own
##      ActionEconomyPort adapter — forwards `is_spent()` from) before the
##      final Strike target-pick fires the whole resolve-validate-dispatch-
##      charge chain. execute() reports ok:false/INSUFFICIENT_RESOURCES with
##      zero actions/stamina spent, and the actor's position + the target's
##      HP are byte-for-byte unchanged from their pre-execute() values.
##   3. Boot-real abort path (zero Stamina): identical assertions, with the
##      actor's live `stamina` driven to 0 instead of the action budget.
##   4. Boot-real queue-integrity path: a queue with a manually injected
##      non-contiguous order_index sequence ({0, 2} instead of {0, 1}) is
##      rejected by `instance._core_combine_action_controller.execute()`
##      with VALIDATION_FAILED, BEFORE any sub-action dispatch or economy
##      charge — driven directly against the real, composition-root-wired
##      controller instance (no interactive picker needed for this
##      criterion; the manually-injected queue itself IS the malformed
##      input this gate defends against, per FIX-002's own doc: "a queue
##      built without routing through add_entry() ... could otherwise
##      carry a gapped or non-zero-start order_index sequence into the
##      sequential resolution loop").
##   5. All four scenarios run against the real composition-root-wired
##      `instance._core_combine_action_controller` / `instance.
##      round_session.current_action_economy()` / `instance.
##      multi_phase_targeting_controller` — never a hand-substituted spy or
##      fake collaborator.
##
## Fixture geometry/seed mirrors tests/smoke/test_release_readiness_smoke.gd's
## own established convention: rather than re-declare a second, potentially
## divergent copy, this suite preloads tests/e2e/combine/
## test_charge_end_to_end.gd directly and reuses its PROLOGUE_SEED /
## SKELETON_REPOSITIONED_HEX_Q / STRIDE_DESTINATION_HEX_Q consts verbatim.

const ChargeE2EClass = preload("res://tests/e2e/combine/test_charge_end_to_end.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const MovementClass = preload("res://core/rules/movement.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const PROLOGUE_SEED: int = ChargeE2EClass.PROLOGUE_SEED
const SKELETON_REPOSITIONED_HEX_Q: int = ChargeE2EClass.SKELETON_REPOSITIONED_HEX_Q
const STRIDE_DESTINATION_HEX_Q: int = ChargeE2EClass.STRIDE_DESTINATION_HEX_Q


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


func _find_option(options: Array, id: String):
	for option in options:
		if option.get("id") == id:
			return option
	return null


## _reposition_skeleton_for_charge(titus, skeleton) -> Dictionary — mirrors
## tests/smoke/test_release_readiness_smoke.gd's own identically-named/
## purposed helper: repositions the Skeleton (test-fixture-only) out of
## Titus's melee reach but adjacent to a hex already within his real,
## boot-time-computed legal Stride destination set, so a real Charge
## (Stride then Strike) genuinely succeeds end-to-end once resources are
## sufficient.
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


func _press_combine(instance) -> void:
	assert_true(instance._verb_registry.is_available("COMBINE"), "COMBINE must be offered on the live verb bar before it can be pressed")
	instance.verb_bar_view.press("COMBINE")


## _drive_queue_build_and_confirm(instance) -> void — drives the REAL,
## interactive queue-build pick loop (COMBINE press -> STRIDE pick -> STRIKE
## pick -> Confirm) through production SelectionOverlay.choose_option()
## calls, exactly mirroring tests/smoke/test_release_readiness_smoke.gd's
## own established steel-thread driving code. Leaves the real interactive
## TARGETING loop active, positioned at its first (STRIDE) phase, ready for
## a caller to drive the Stride hex-pick / Strike target-pick itself.
func _drive_queue_build_and_confirm(instance) -> void:
	_press_combine(instance)
	assert_true(instance._combine_build_active, "pressing COMBINE must engage the real interactive queue-build pick loop")

	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	assert_not_null(stride_option, "fixture assumption: STRIDE must be a legal first pick")
	instance.selection_overlay.choose_option(stride_option)

	var strike_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIKE")
	assert_not_null(strike_option, "fixture assumption: STRIKE must be a legal second pick")
	instance.selection_overlay.choose_option(strike_option)

	var confirm_option = _find_option(instance.selection_overlay.get_candidate_options(), BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID)
	assert_not_null(confirm_option, "Confirm must be offered once the TURN-context minimum queue length is met")
	instance.selection_overlay.choose_option(confirm_option)

	assert_true(instance._combine_targeting_active, "Confirm must hand off into the real interactive targeting loop")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE", "the confirmed queue's first sub-action must be STRIDE")


## _drive_stride_hex_pick(instance, stride_destination) -> void — resolves
## the STRIDE phase of the real interactive targeting loop, advancing it
## into the STRIKE phase. Picking a Stride destination must never itself
## move the actor before execute() runs (this project's own established
## invariant, re-asserted by every caller of this helper below).
func _drive_stride_hex_pick(instance, stride_destination) -> void:
	var candidate_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	var chosen_hex = null
	for h in candidate_hexes:
		if h.equals(stride_destination):
			chosen_hex = h
			break
	assert_not_null(chosen_hex, "fixture assumption: the intended Stride destination must be a legal candidate")

	instance.hex_grid_view.hex_clicked.emit(chosen_hex)

	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE", "the loop must advance into the STRIKE phase")


## _drive_strike_target_pick(instance, skeleton) -> void — resolves the
## final (STRIKE) phase of the real interactive targeting loop. This is the
## click that fires the WHOLE resolve-validate-dispatch-charge chain
## automatically from inside production code
## (MainScene._advance_combine_targeting_phase() -> _finish_combine_targeting()
## -> multi_phase_targeting_controller.execute() ->
## instance._core_combine_action_controller.execute()) — the exact seam
## FIX-001's preflight gate and FIX-002's order_index re-check both sit on.
func _drive_strike_target_pick(instance, skeleton) -> void:
	assert_true(instance.selection_overlay.get_highlighted_target_ids().has(skeleton.display_id()), "STRIKE's phase must offer the Skeleton as reachable from the post-move hex")
	var skeleton_token = instance.hex_grid_view.get_token(skeleton.combatant_id)
	assert_not_null(skeleton_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(skeleton_token.hex_coord)
	assert_false(instance._combine_targeting_active, "the interactive targeting loop must have finished")


## _exhaust_action_budget(economy) -> void — drives a REAL, live
## core/rules/action_economy.gd ActionEconomy instance to `is_spent() ==
## true` via genuine spend_action() calls (never a private-field poke),
## mirroring tests/unit/test_action_economy_budget_regression.gd's own
## established "start_of_turn() before each spend_action() call" pattern
## (each spend_action() call trips the per-TURN `_action_used` gate, which
## only start_of_turn() clears — see action_economy.gd's own doc). This is
## the SAME `is_spent()` query MainScene.gd's `_GdCombineActionEconomyPort`
## adapter forwards to `_preflight_resource_check()`'s economy-availability
## peek, so exhausting the FULL per-round budget this way is the genuine,
## live-wired trigger for an "already-spent" actor's Combine to be rejected
## — not a synthetic shortcut.
func _exhaust_action_budget(economy) -> void:
	var guard: int = 0
	while not economy.is_spent():
		economy.start_of_turn()
		economy.spend_action({})
		guard += 1
		assert_true(guard <= ActionEconomyClass.MAX_BUDGET, "test setup: the action budget must exhaust within MAX_BUDGET spends")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — boot-real happy path: FIX-001/FIX-002 are additive and never
# regress the legal, affordable Charge steel thread.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_happy_path_charge_still_resolves_with_both_fixes_in_place() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]
	var titus_start_hex = geo["titus_start_hex"]

	_drive_queue_build_and_confirm(instance)
	_drive_stride_hex_pick(instance, stride_destination)

	assert_true(titus.hex_coord.equals(titus_start_hex), "picking a Stride destination must never itself move the actor before execute() runs")

	var skeleton_hp_before: int = skeleton.hp_current
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus must start with positive Stamina")
	assert_false(economy.is_spent(), "fixture assumption: Titus's action economy must not be spent before this Combine")

	_drive_strike_target_pick(instance, skeleton)

	var loop_result: Dictionary = instance._combine_targeting_result
	assert_true(loop_result.get("ok", false), "the real interactive targeting loop must report ok:true (result: %s)" % [loop_result])
	var execution_result: Dictionary = loop_result.get("execution_result", {})

	assert_true(execution_result.get("ok", false), "the REAL, live-wired CombineActionController.execute() must resolve ok=true (result: %s)" % [execution_result])
	assert_eq(execution_result.get("actions_spent", -1), 1, "the steel thread must spend exactly ONE action")
	assert_eq(execution_result.get("stamina_spent", -1), 1, "the steel thread must spend exactly ONE Stamina")

	assert_eq(actions_remaining_before - economy.get_remaining(), 1, "the live ActionEconomy ledger must reflect exactly ONE action spent")
	assert_eq(stamina_before - titus.stamina, 1, "the live Combatant.stamina ledger must reflect exactly ONE Stamina spent")

	assert_true(titus.hex_coord.equals(stride_destination), "actor.hex_coord must equal the chosen Stride destination after execute()")
	assert_true(skeleton.hp_current < skeleton_hp_before, "target.hp_current must reflect the Strike damage applied from the post-move position")

	var resolution_log: Array = execution_result.get("resolution_log", [])
	assert_eq(resolution_log.size(), 2, "resolution_log must carry exactly one entry per dispatched sub-action")
	assert_eq(resolution_log[0].get("verb_id"), "STRIDE", "STRIDE must resolve before STRIKE")
	assert_eq(resolution_log[1].get("verb_id"), "STRIKE")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — boot-real abort path: an actor whose action economy is
# already exhausted must be rejected with INSUFFICIENT_RESOURCES and ZERO
# world mutation, driven through the REAL live signal chain.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_abort_when_action_economy_exhausted_leaves_state_byte_for_byte_unchanged() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316 (resolves DEF-001/PR-001): round_session/verb bar/selection
	# overlay only become live once a real combat trigger fires (see
	# MainScene.gd's own FEAT-316 doc) -- drive the same real handoff here so
	# the live COMBINE queue-build/targeting loop below can be driven exactly
	# as it was before this feature.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]
	var titus_start_hex = geo["titus_start_hex"]

	_drive_queue_build_and_confirm(instance)
	_drive_stride_hex_pick(instance, stride_destination)
	assert_true(titus.hex_coord.equals(titus_start_hex), "picking a Stride destination must never itself move the actor before execute() runs")

	# ── Pre-execute() snapshot, taken BEFORE the actor's economy is
	# deliberately exhausted, so the "byte-for-byte unchanged" assertions
	# below are meaningful. ──────────────────────────────────────────────
	var titus_hex_before_execute = titus.hex_coord
	var skeleton_hp_before_execute: int = skeleton.hp_current
	var stamina_before_execute: int = titus.stamina

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	_exhaust_action_budget(economy)
	assert_true(economy.is_spent(), "test setup: Titus's live ActionEconomy must genuinely report is_spent()==true before the final target-pick")

	# ── The final Strike target-pick fires the WHOLE resolve-validate-
	# dispatch-charge chain automatically, reaching the REAL, live-wired
	# `_core_combine_action_controller.execute()` — the SAME instance
	# criterion 1's happy path above resolves through. ──────────────────
	_drive_strike_target_pick(instance, skeleton)

	var loop_result: Dictionary = instance._combine_targeting_result
	var execution_result: Dictionary = loop_result.get("execution_result", {})

	assert_false(execution_result.get("ok", true), "an actor with an exhausted action economy must have their Combine rejected (result: %s)" % [execution_result])
	assert_eq(execution_result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(execution_result.get("actions_spent"), 0, "an INSUFFICIENT_RESOURCES rejection must spend zero actions")
	assert_eq(execution_result.get("stamina_spent"), 0, "an INSUFFICIENT_RESOURCES rejection must spend zero Stamina")

	# ── Zero real-world mutation on either the actor OR the target. ─────
	assert_true(titus.hex_coord.equals(titus_hex_before_execute), "the actor's position must be byte-for-byte unchanged from its pre-execute() value once the preflight gate rejects")
	assert_eq(skeleton.hp_current, skeleton_hp_before_execute, "the target's HP must be byte-for-byte unchanged from its pre-execute() value once the preflight gate rejects")
	assert_eq(titus.stamina, stamina_before_execute, "the actor's Stamina must be byte-for-byte unchanged from its pre-execute() value once the preflight gate rejects")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — boot-real abort path: an actor with zero Stamina must be
# rejected with the SAME INSUFFICIENT_RESOURCES/zero-mutation guarantees.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_abort_when_stamina_zero_leaves_state_byte_for_byte_unchanged() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316: see the identical doc on the action-economy-exhausted test above.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]
	var titus_start_hex = geo["titus_start_hex"]

	_drive_queue_build_and_confirm(instance)
	_drive_stride_hex_pick(instance, stride_destination)
	assert_true(titus.hex_coord.equals(titus_start_hex), "picking a Stride destination must never itself move the actor before execute() runs")

	var titus_hex_before_execute = titus.hex_coord
	var skeleton_hp_before_execute: int = skeleton.hp_current

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	assert_false(economy.is_spent(), "test setup: Titus's action economy must remain UNSPENT for this scenario -- Stamina is the sole cause of rejection here")

	titus.stamina = 0

	_drive_strike_target_pick(instance, skeleton)

	var loop_result: Dictionary = instance._combine_targeting_result
	var execution_result: Dictionary = loop_result.get("execution_result", {})

	assert_false(execution_result.get("ok", true), "an actor with zero Stamina must have their Combine rejected (result: %s)" % [execution_result])
	assert_eq(execution_result.get("error_code"), "INSUFFICIENT_RESOURCES")
	assert_eq(execution_result.get("actions_spent"), 0, "an INSUFFICIENT_RESOURCES rejection must spend zero actions")
	assert_eq(execution_result.get("stamina_spent"), 0, "an INSUFFICIENT_RESOURCES rejection must spend zero Stamina")

	assert_true(titus.hex_coord.equals(titus_hex_before_execute), "the actor's position must be byte-for-byte unchanged from its pre-execute() value once the preflight gate rejects")
	assert_eq(skeleton.hp_current, skeleton_hp_before_execute, "the target's HP must be byte-for-byte unchanged from its pre-execute() value once the preflight gate rejects")
	assert_eq(titus.stamina, 0, "the actor's (already-zero) Stamina must remain untouched")
	assert_eq(economy.get_remaining(), actions_remaining_before, "the live ActionEconomy must be completely untouched by a Stamina-only rejection")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — boot-real queue-integrity path: a manually injected
# non-contiguous order_index sequence is rejected with VALIDATION_FAILED,
# BEFORE any sub-action dispatch or economy charge, through the real,
# composition-root-wired `_core_combine_action_controller`.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_non_contiguous_order_index_rejected_before_dispatch_or_charge() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var titus_start_hex = titus.hex_coord
	var skeleton_hp_before: int = skeleton.hp_current

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0, "fixture assumption: Titus must start with positive Stamina")
	assert_false(economy.is_spent(), "fixture assumption: Titus's action economy must not be spent before this call")

	assert_not_null(instance._core_combine_action_controller, "the composition root must construct a real core CombineActionController")

	# A legal VERB pair ([STRIDE, STRIKE]) but with a GAPPED, non-contiguous
	# order_index sequence ({0, 2} instead of {0, 1}) -- exactly the class of
	# malformed queue FIX-002's own doc describes: "a queue built without
	# routing through add_entry() ... could otherwise carry a gapped or
	# non-zero-start order_index sequence into the sequential resolution
	# loop." Since combine_actions() would happily accept [STRIDE, STRIKE]
	# on its own, this queue's ONLY defect is order_index contiguity --
	# proving FIX-002's gate is the one rejecting it, not DEF-001's
	# same-verb/Repeat rule.
	var non_contiguous_queue: Array = [
		VerbQueueEntryClass.new("q1", 0, "STRIDE"),
		VerbQueueEntryClass.new("q1", 2, "STRIKE"),
	]

	var result: Dictionary = instance._core_combine_action_controller.execute({
		"queue": non_contiguous_queue,
		"actor": titus,
		"context": CombineQueueClass.Context.TURN,
	})

	assert_false(result.get("ok", true), "a non-contiguous order_index sequence must be rejected by execute() (result: %s)" % [result])
	assert_eq(result.get("error_code"), "VALIDATION_FAILED")
	assert_eq(result.get("actions_spent"), 0, "a VALIDATION_FAILED rejection must spend zero actions")
	assert_eq(result.get("stamina_spent"), 0, "a VALIDATION_FAILED rejection must spend zero Stamina")
	assert_eq(result.get("resolution_log"), [], "a VALIDATION_FAILED rejection must never reach sub-action dispatch -- resolution_log stays empty")

	# ── Zero mutation anywhere: the queue-integrity gate rejects before
	# _preflight_resource_check()/_dispatch_sub_actions()/
	# _charge_action_economy() are ever reached. ─────────────────────────
	assert_true(titus.hex_coord.equals(titus_start_hex), "the actor's position must be completely unchanged -- no sub-action was ever dispatched")
	assert_eq(skeleton.hp_current, skeleton_hp_before, "the target's HP must be completely unchanged -- no sub-action was ever dispatched")
	assert_eq(titus.stamina, stamina_before, "the actor's Stamina must be completely unchanged -- the economy charge was never reached")
	assert_eq(economy.get_remaining(), actions_remaining_before, "the live ActionEconomy must be completely untouched by a VALIDATION_FAILED rejection")
