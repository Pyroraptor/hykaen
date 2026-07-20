extends GutTest
## tests/e2e/combine/test_charge_end_to_end.gd — FEAT-299 (Iteration O
## "Combine Selection UX"; US-009; resolves DEF-NEW-004; closes the NFR-004
## gap).
##
## Boots the REAL, shipped res://MainScene.tscn composition root (NO mocks
## or doubles on any controller, or on presentation/selection_overlay.gd's
## SelectionOverlay, or on presentation/hex_grid_view.gd's HexGridView,
## anywhere in this suite) at a pinned RNG seed, and drives the FULL
## Iteration O Combine steel thread end-to-end EXCLUSIVELY through the
## PRODUCTION signal chain a real player's mouse actually drives:
##
##   VerbBarView.press("COMBINE") -> _verb_registry.enter_selection("COMBINE")
##   -> _verb_bar_combine_enter_selection() -> the real interactive
##   queue-build pick loop (BuildVerbQueueUseCase, via
##   `_core_combine_action_controller`) -> SelectionOverlay.choose_option()
##   (STRIDE, then STRIKE, then Confirm) -> selection_overlay.selection_resolved
##   -> ConfirmQueueUseCase -> start_combine_targeting() (UNCHANGED) -> the
##   real targeting phases, resolved via hex_grid_view.hex_clicked (Stride
##   hex-pick, then Strike target-pick) -> selection_overlay.selection_resolved
##   -> _finish_combine_targeting() -> multi_phase_targeting_controller.execute()
##   (UNCHANGED) -> the REAL, live-wired core/controllers/
##   combine_action_controller.gd CombineActionController.execute()
##   (`_core_combine_action_controller`, FEAT-297/298) -- which re-validates
##   (DEF-001), dispatches STRIDE then STRIKE through the SAME real
##   presentation/stride_action_controller.gd / strike_action_controller.gd
##   instances every standalone Stride/Strike press already resolves through
##   (`_controller(verb_id)`), and charges exactly 1 action + 1 Stamina.
##
## THIS FEATURE'S OWN FIX (DEF-NEW-004): before this feature, this suite
## manually re-invoked a SECOND, disconnected CombineActionController
## instance (presentation/combine_action_controller.gd's own, never reached
## by the live interactive signal chain) with a hand-built
## {"queue":..., "STRIDE":..., "STRIKE":...} selection Dictionary passed
## straight to its own execute() -- exercising a code path a real player's
## mouse can NEVER reach, which is exactly why DEF-NEW-002/DEF-NEW-003
## shipped undetected by this suite. FEAT-297/298 (this feature's own
## depends_on) consolidated the REAL sub-action dispatch and a real
## ActionEconomyPort into `_core_combine_action_controller` -- the ONE
## instance both `multi_phase_targeting_controller` (the live signal chain's
## own terminal collaborator) and MainScene.gd's `_controller("COMBINE")`
## table lookup now resolve to -- so there is no longer any "second,
## disconnected" controller for this suite to accidentally exercise instead
## of the real one. This suite now NEVER calls `.execute()` on any
## CombineActionController directly, and NEVER hand-builds a selection
## Dictionary passed straight to it -- the entire resolve-and-charge chain
## fires automatically, from inside production code, the instant the final
## real hex_grid_view.hex_clicked signal for the Strike target-pick is
## emitted.
##
## test_criteria covered:
##   1. test_combine_press_offers_real_selection_descriptor_with_stride_and_strike()
##   2-6. test_full_happy_path_combine_stride_strike_confirm_hex_pick_target_pick_execute()
##   7. test_cancel_during_queue_build_step_leaves_state_unchanged_and_returns_to_layer1(),
##      test_cancel_during_stride_targeting_phase_aborts_entire_combine_with_no_state_leak(),
##      test_cancel_during_strike_targeting_phase_aborts_entire_combine_with_no_state_leak()
##   8. verified by running this suite alongside the pre-existing Iteration N
##      standalone Stride/Strike boot-real suites in the SAME gut run (see
##      this project's CI gate) -- this file introduces no shared mutable
##      state and modifies no production file.
##
## A NOTE ON TARGETING-PHASE CANCELLATION (test_criteria 7, the two
## `..._targeting_phase_aborts_entire_combine...` tests below): this
## codebase's real, shipped UI currently offers NO Layer-2b hex/target-click
## affordance that resolves to CancelCombineUseCase.CANCEL_SENTINEL_ID during
## a Stride/Strike TARGETING phase (core/controllers/stride_action_controller.gd
## / strike_action_controller.gd never populate `candidate_options` for a
## TARGET_PHASE descriptor, so SelectionOverlay never re-enters its Layer-2a
## option-pick step there -- Esc/right-click, presentation/cancel_controller.gd's
## OWN cancel affordance, is wired only to SelectionOverlay.cancel(), which is
## NOT connected to CancelCombineUseCase/the Combine loop's own bookkeeping at
## all). Introducing that real UI affordance is production code, out of this
## feature's own files_to_modify scope. This suite therefore drives
## `instance.multi_phase_targeting_controller` -- the EXACT SAME real,
## composition-root-owned singleton instance `_finish_combine_targeting()`
## itself invokes on every real hex-pick resolution above, never a
## second/forked instance -- directly with a `resolved_selections` Dictionary
## carrying CANCEL_SENTINEL_ID for the cancelled phase: this is the identical
## seam design notes' error_handling section documents ("CANCEL_SENTINEL on
## selection_resolved routes to CancelCombineUseCase") as the future landing
## point for that real UI affordance, exercised today at the one real,
## production object that seam already terminates in.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const BuildVerbQueueUseCaseClass   = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CombineQueueClass            = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass          = preload("res://core/domain/combine/verb_queue_entry.gd")
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


## _find_option(options, id) -> Dictionary or null -- picks a specific option
## Dictionary by id out of selection_overlay.get_candidate_options(), the SAME
## set a real player would be choosing a button from.
func _find_option(options: Array, id: String):
	for option in options:
		if option.get("id") == id:
			return option
	return null


## _press_combine(instance) -> void -- the LIVE entry point this whole suite's
## happy-path/build-cancel tests exercise: a real VerbBarView.press("COMBINE")
## call, routed through the real, booted `_verb_registry`
## (VerbBarRegistryAdapter) exactly like a real player's mouse click on the
## Layer 1 verb bar -- never a direct call to
## `instance._verb_bar_combine_enter_selection()` or
## `_core_combine_action_controller.enter_selection()`.
func _press_combine(instance) -> void:
	assert_true(instance._verb_registry.is_available("COMBINE"), "COMBINE must be offered on the live verb bar before it can be pressed")
	instance.verb_bar_view.press("COMBINE")


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
# Criterion 1 -- pressing COMBINE via the REAL VerbBarView/VerbBarRegistry
# offers a real, incremental verb picker (Layer-2a option pick) naming STRIDE
# and STRIKE, never a hardcoded/pre-built queue or a direct call into any
# internal use case.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_press_offers_real_selection_descriptor_with_stride_and_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	assert_true(titus.stamina > 0, "fixture assumption: Titus starts with positive Stamina")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")

	_press_combine(instance)

	assert_true(instance._combine_build_active, "pressing COMBINE via the real VerbBarView must engage the real interactive queue-build pick loop")
	assert_true(instance.selection_overlay.is_active(), "pressing COMBINE via the real VerbBarView must activate the REAL SelectionOverlay")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "COMBINE")
	assert_true(instance.selection_overlay.is_awaiting_option(), "the very first pick must be a real Layer-2a option pick, never an immediate hex/target highlight")

	var ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(ids.has("STRIDE"), "the real picker's very first offer must include STRIDE")
	assert_true(ids.has("STRIKE"), "the real picker's very first offer must include STRIKE")

	assert_no_new_orphans("driving the real picker must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2-6 -- the full happy path, driven end to end purely through real
# production signal emissions: COMBINE press -> STRIDE pick -> STRIKE pick ->
# Confirm pick (each via selection_overlay.selection_resolved, fired by
# choose_option() -- the EXACT call a real Layer-2a button press makes) ->
# Stride hex-pick -> Strike target-pick (each via a real
# hex_grid_view.hex_clicked emission). The resolve-validate-dispatch-charge
# chain fires AUTOMATICALLY from inside production code the instant the
# final hex_clicked signal is emitted -- this test never calls .execute() on
# any controller itself.
# ══════════════════════════════════════════════════════════════════════════

func test_full_happy_path_combine_stride_strike_confirm_hex_pick_target_pick_execute() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]

	watch_signals(instance.selection_overlay)

	# ── COMBINE pressed via the real VerbBarView/VerbBarRegistry. ───────────
	_press_combine(instance)
	assert_true(instance._combine_build_active)
	assert_true(instance.selection_overlay.is_awaiting_option())

	var first_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(first_ids.has("STRIDE"))
	assert_true(first_ids.has("STRIKE"))
	assert_false(first_ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must not be offered before the TURN-context minimum of 2 entries is met")

	# ── STRIDE picked -- a real Layer-2a button press, via choose_option(),
	# resolved purely through the real selection_overlay.selection_resolved
	# signal. ─────────────────────────────────────────────────────────────
	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	assert_not_null(stride_option, "fixture assumption: STRIDE must be a legal first pick")
	instance.selection_overlay.choose_option(stride_option)

	assert_true(instance._combine_build_active, "the queue-build loop must still be active after a single VERB pick")
	var second_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_false(second_ids.has("STRIDE"), "STRIDE must be excluded from the next pick after being chosen -- it carries no Repeat trait")
	assert_true(second_ids.has("STRIKE"), "STRIKE (a different verb) must remain legal")
	assert_false(second_ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must be ABSENT once queue length is 1 (TURN context requires >= 2 entries)")

	# ── STRIKE picked. ───────────────────────────────────────────────────
	var strike_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIKE")
	assert_not_null(strike_option)
	instance.selection_overlay.choose_option(strike_option)

	var third_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(third_ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must be PRESENT once queue length reaches 2 (the TURN-context minimum)")

	# ── Confirm picked -- the REAL ConfirmQueueUseCase finalizes the queue
	# and hands off to the UNCHANGED real targeting phase (start_combine_targeting())
	# automatically, from inside production code. ──────────────────────────
	var confirm_option = _find_option(instance.selection_overlay.get_candidate_options(), BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID)
	assert_not_null(confirm_option)
	instance.selection_overlay.choose_option(confirm_option)

	assert_false(instance._combine_build_active, "the queue-build loop must be torn down once Confirm succeeds")
	assert_true(instance._combine_targeting_active, "Confirm must hand off into the real interactive Combine sub-action TARGETING loop")
	assert_true(instance.selection_overlay.is_active(), "the targeting phase must immediately activate SelectionOverlay for the first sub-action")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE", "the confirmed queue's first sub-action (order_index 0) must be STRIDE")
	assert_false(instance.selection_overlay.is_awaiting_option(), "the targeting phase highlights hexes/targets directly -- it is not a Layer-2a option pick")

	# ── Stride hex-pick, through the REAL, unmodified SelectionOverlay +
	# HexGridView, offered by the REAL Iteration O StrideActionController. ──
	var candidate_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_true(candidate_hexes.size() > 0, "fixture assumption: Titus has at least one legal Stride destination at boot")
	var chosen_hex = null
	for h in candidate_hexes:
		if h.equals(stride_destination):
			chosen_hex = h
			break
	assert_not_null(chosen_hex, "fixture assumption: the intended Stride destination must be a legal candidate")

	# Picking (querying) a Stride destination must never itself move the actor.
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]), "picking a Stride destination must never itself move the actor")

	instance.hex_grid_view.hex_clicked.emit(chosen_hex)

	# Picking the hex still must not itself move the actor -- resolution is
	# deferred until the WHOLE queue's targeting is complete and execute()
	# actually runs (design notes' error_handling: "no sub-action side
	# effects are applied until ALL targeting is resolved").
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]))

	# ── The loop must have auto-advanced into the STRIKE phase, computing
	# post-move-aware reach from the HYPOTHETICAL Stride destination (ADR-006),
	# via the REAL Iteration O StrikeActionController. ──────────────────────
	assert_true(instance._combine_targeting_active, "the loop must still be active -- STRIKE's own phase has not resolved yet")
	assert_true(instance.selection_overlay.is_active(), "the loop must advance into the STRIKE phase, not terminate")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE")
	assert_true(instance.selection_overlay.get_highlighted_target_ids().has(skeleton.display_id()), "STRIKE's own phase must offer the Skeleton as reachable from the chosen post-move hex")

	var skeleton_hp_before_execute: int = skeleton.hp_current

	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	var stamina_before: int = titus.stamina
	assert_true(stamina_before > 0)

	# ── Strike target-pick, through the REAL, unmodified SelectionOverlay +
	# HexGridView. This is the LAST real signal this test emits -- the entire
	# resolve-validate-dispatch-charge chain (_advance_combine_targeting_phase()
	# -> _finish_combine_targeting() -> multi_phase_targeting_controller.execute()
	# -> the REAL, live-wired core CombineActionController.execute(), FEAT-297/298)
	# fires AUTOMATICALLY from inside production code, synchronously, as part
	# of this single signal emission. No manual .execute() call, on any
	# controller, anywhere in this test. ─────────────────────────────────────
	var skeleton_token = instance.hex_grid_view.get_token(skeleton.combatant_id)
	assert_not_null(skeleton_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(skeleton_token.hex_coord)

	# ── Criteria 2/3 -- exactly five real selection_resolved emissions drove
	# the ENTIRE flow (STRIDE pick, STRIKE pick, Confirm, Stride hex-pick,
	# Strike target-pick) -- proving this test never bypassed the production
	# signal chain for any phase. ────────────────────────────────────────────
	assert_eq(
		get_signal_emit_count(instance.selection_overlay, "selection_resolved"), 5,
		"the whole Combine (3 queue-build picks + 2 targeting-phase picks) must resolve through exactly five real selection_overlay.selection_resolved emissions"
	)

	assert_false(instance.selection_overlay.is_active(), "selection_overlay must return to Layer 1 once both targeting phases resolve and execute() has run")
	assert_false(instance._combine_targeting_active, "the interactive targeting loop must have finished")

	var loop_result: Dictionary = instance._combine_targeting_result
	assert_true(loop_result.get("ok", false), "the real interactive targeting loop must report ok:true once both phases resolve (result: %s)" % [loop_result])

	var execution_result: Dictionary = loop_result.get("execution_result", {})
	assert_true(execution_result.get("ok", false), "the REAL, live-wired core CombineActionController.execute() must resolve ok=true (result: %s)" % [execution_result])

	# ── The resolution log records STRIDE resolving before STRIKE, in that
	# order (FEAT-297's real sub-action dispatch, strictly order_index-ordered). ──
	var resolution_log: Array = execution_result.get("resolution_log", [])
	assert_eq(resolution_log.size(), 2, "resolution_log must carry exactly one entry per dispatched sub-action")
	assert_eq(resolution_log[0].get("verb_id"), "STRIDE", "the resolution log must record STRIDE resolving before STRIKE")
	assert_eq(resolution_log[1].get("verb_id"), "STRIKE")

	# ── Criterion 4 -- actor.hex_coord equals the chosen Stride hex. ────────
	assert_true(titus.hex_coord.equals(chosen_hex), "actor.hex_coord must equal the chosen Stride destination")

	# ── Criterion 5 -- target.hp_current reflects the Strike damage applied
	# from the post-move position. ───────────────────────────────────────────
	assert_true(skeleton.hp_current < skeleton_hp_before_execute, "target.hp_current must reflect the Strike damage applied from the post-move position")

	# ── Criterion 6 -- exactly 1 action and 1 Stamina spent for the WHOLE
	# Combine (the live ActionEconomy/Combatant.stamina ledger is this
	# project's established authoritative per-actor ledger). ────────────────
	var actions_spent: int = actions_remaining_before - economy.get_remaining()
	var stamina_spent: int = stamina_before - titus.stamina
	assert_eq(actions_spent, 1, "Charge must spend exactly ONE action")
	assert_eq(stamina_spent, 1, "Charge must spend exactly ONE Stamina")
	assert_false(economy.can_take_action(), "Titus's one action for the turn must now be spent")

	assert_no_new_orphans("the full happy path must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 -- cancellation at the queue-build step, driven purely through
# the real VerbBarView/SelectionOverlay signal chain, leaves actor/target
# state fully unchanged and returns control to the Layer 1 verb bar, with no
# partial-state leak into a subsequent real Combine attempt.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_queue_build_step_leaves_state_unchanged_and_returns_to_layer1() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var titus_start_hex = titus.hex_coord
	var skeleton_hp_before: int = skeleton.hp_current
	var stamina_before: int = titus.stamina

	_press_combine(instance)
	assert_true(instance._combine_build_active)

	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	assert_not_null(stride_option)
	instance.selection_overlay.choose_option(stride_option)

	var mid_build_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(mid_build_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress queue-build must offer the real Cancel sentinel option")

	# Cancel is picked -- a real Layer-2a button press, via choose_option(),
	# routing through the REAL CancelCombineUseCase.
	var cancel_option = _find_option(instance.selection_overlay.get_candidate_options(), CancelCombineUseCaseClass.CANCEL_SENTINEL_ID)
	assert_not_null(cancel_option)
	instance.selection_overlay.choose_option(cancel_option)

	# ── No queue state retained. ─────────────────────────────────────────
	assert_false(instance._combine_build_active, "cancelling must tear down the interactive queue-build loop")
	assert_null(instance._combine_build_queue, "cancelling must discard the in-progress CombineQueue -- no partial-state leak")

	# Actor/target state fully unchanged.
	assert_true(titus.hex_coord.equals(titus_start_hex))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)

	# Control returns to the Layer 1 verb bar: no Layer 2 selection was left
	# active, COMBINE remains selectable, and a fresh attempt -- via the SAME
	# real VerbBarView press -- starts from the SAME Layer-1-equivalent
	# candidate set (no leaked exclusion).
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"))

	_press_combine(instance)
	var fresh_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(fresh_ids.has("STRIDE"), "STRIDE must be legal again in a fresh attempt -- no leaked exclusion from the cancelled queue")
	assert_true(fresh_ids.has("STRIKE"))
	assert_false(fresh_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "a brand-new attempt's very first pick must offer no Cancel option")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 (cont'd) -- cancellation during the STRIDE (order_index 0)
# targeting phase aborts the whole Combine with no partial-state leak, driven
# against `instance.multi_phase_targeting_controller` -- the REAL,
# composition-root-owned singleton `_finish_combine_targeting()` itself
# invokes on every real hex-pick resolution (see this file's own header doc
# for why no real hex-click-driven Cancel affordance exists at this phase
# today).
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
	# never even reached (this phase cancelled BEFORE dispatch), and
	# execute() (the real economy charge) was never reached either.
	assert_true(titus.hex_coord.equals(titus_start_hex))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)
	assert_eq(economy.get_remaining(), actions_before)

	# Control remains with the Layer 1 verb bar, and a SUBSEQUENT, real
	# Combine attempt -- driven through the actual VerbBarView entry point --
	# proves no partial state leaked from the cancelled attempt.
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"), "cancellation must leave COMBINE selectable again on the Layer 1 verb bar")

	_press_combine(instance)
	assert_true(instance._combine_build_active, "a subsequent real COMBINE press must engage a fresh queue-build loop with no leaked state")
	var fresh_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(fresh_ids.has("STRIDE"))
	assert_true(fresh_ids.has("STRIKE"))
	assert_false(fresh_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 (cont'd) -- cancellation during the STRIKE (order_index 1)
# targeting phase aborts the whole Combine with no partial-state leak, even
# though the STRIDE phase already resolved (query-only, non-mutating) ahead
# of it. Same real-singleton discipline as the STRIDE-phase cancellation
# test above.
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
	# own doc), STRIKE's phase never even resolved, and execute() (the real
	# economy charge) was never reached.
	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)
	assert_eq(economy.get_remaining(), actions_before)

	# Control remains with the Layer 1 verb bar, and a SUBSEQUENT, real
	# Combine attempt -- driven through the actual VerbBarView entry point --
	# proves no partial state leaked from the cancelled attempt.
	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"))

	_press_combine(instance)
	assert_true(instance._combine_build_active, "a subsequent real COMBINE press must engage a fresh queue-build loop with no leaked state")
	var fresh_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(fresh_ids.has("STRIDE"))
	assert_true(fresh_ids.has("STRIKE"))
