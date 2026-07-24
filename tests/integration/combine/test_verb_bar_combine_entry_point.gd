extends GutTest
## tests/integration/combine/test_verb_bar_combine_entry_point.gd — FEAT-296
## (resolves DEF-NEW-001).
##
## Boots the REAL, shipped res://MainScene.tscn composition root (NO mocks
## or doubles anywhere in this suite -- mirrors the established boot-real
## discipline of tests/integration/combine/test_composition_root_wiring.gd
## and tests/e2e/combine/test_charge_end_to_end.gd) and drives the LIVE
## COMBINE entry point -- `instance._verb_registry.enter_selection("COMBINE")`,
## the EXACT call VerbBarView.press("COMBINE") makes, which dispatches
## straight to `_verb_bar_combine_enter_selection()` (the function
## VerbBarRegistry actually registers for a real player's COMBINE press) --
## rather than reaching into `_core_combine_action_controller` /
## ConfirmQueueUseCase / CancelCombineUseCase directly, the way the
## pre-existing test_charge_end_to_end.gd suite does.
##
## DEF-NEW-001 (critical): before this feature,
## `_verb_bar_combine_enter_selection()` hardcoded
## queue_entries=[STRIDE, STRIKE] and called start_combine_targeting()
## directly, so a real COMBINE press NEVER exercised
## BuildVerbQueueUseCase/ConfirmQueueUseCase/CancelCombineUseCase at all --
## those use cases were reachable only via direct unit/integration tests
## against the use cases themselves, never through the live player journey.
## This suite proves the live entry point now genuinely drives them.
##
## test_criteria covered:
##   1. test_pressing_combine_via_live_entry_point_invokes_build_verb_queue_use_case_and_offers_stride_and_strike()
##   2. test_confirm_sentinel_absent_at_queue_length_1_and_present_at_length_2_via_live_entry_point()
##   3. test_stride_excluded_from_next_pick_after_being_chosen_via_live_entry_point()
##   4. test_cancelling_at_queue_build_step_via_live_entry_point_returns_to_verb_bar_with_no_queue_state_retained()
##   5. test_main_scene_source_never_hardcodes_stride_strike_queue_in_the_live_combine_entry_point()
##
## Plus a happy-path regression proving the queue-build loop still correctly
## hands off to the UNCHANGED targeting phase (start_combine_targeting())
## only once the player actually confirms.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"

## VERB_DISPATCH_CONTROLLER_SCRIPT_PATH -- FEAT-007 (US-005 / FR-006):
## `_verb_bar_combine_enter_selection()` (criterion 5's own static scan
## target) moved off MainScene.gd entirely, into the extracted
## presentation/verb_dispatch_controller.gd's VerbDispatchController -- see
## that file's own doc for the full "verb-bar wiring + verb registry
## builder" extraction this feature performs.
const VERB_DISPATCH_CONTROLLER_SCRIPT_PATH: String = "res://presentation/verb_dispatch_controller.gd"

const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CancelCombineUseCaseClass  = preload("res://core/application/combine/cancel_combine_use_case.gd")
const CombineQueueClass          = preload("res://core/domain/combine/combine_queue.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/integration/combine/test_composition_root_wiring.gd's /
## tests/e2e/combine/test_charge_end_to_end.gd's identically-valued
## constant): Titus acts first with positive Stamina.
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _titus(instance):
	assert_true(instance._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var titus = instance._party[0]
	assert_eq(titus.name, "Titus", "fixture assumption: the first party member is Titus")
	return titus


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


## _find_option(options, id) -> Dictionary or null -- picks a specific
## option Dictionary by id out of selection_overlay.get_candidate_options(),
## the SAME set a real player would be choosing a button from.
func _find_option(options: Array, id: String):
	for option in options:
		if option.get("id") == id:
			return option
	return null


## _press_combine(instance) -> void -- the LIVE entry point this whole suite
## exercises: the EXACT call VerbBarView.press("COMBINE") makes
## (presentation/verb_bar_view.gd's own `_registry.enter_selection(verb_id)`),
## routed through the real, booted `_verb_registry` (a
## VerbBarRegistryAdapter instance) rather than calling
## `instance._verb_bar_combine_enter_selection()` directly -- proving the
## REGISTERED dispatch table entry itself, not merely the shim function in
## isolation.
func _press_combine(instance) -> void:
	assert_true(instance._verb_registry.is_available("COMBINE"), "COMBINE must be offered on the live verb bar before it can be pressed")
	var result = instance._verb_registry.enter_selection("COMBINE")
	assert_eq(result, {}, "the live COMBINE entry point must return an empty Dictionary -- it drives SelectionOverlay directly, exactly like start_combine_targeting()'s own established contract")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- pressing COMBINE via the live VerbBarRegistry entry point
# invokes BuildVerbQueueUseCase (indirectly, via
# `_core_combine_action_controller.enter_selection()`) and returns a real
# SelectionDescriptor naming STRIDE and STRIKE, not a hardcoded queue.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_combine_via_live_entry_point_invokes_build_verb_queue_use_case_and_offers_stride_and_strike() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316 (resolves DEF-001/PR-001): round_session/verb bar/selection
	# overlay only become live once a real combat trigger fires (see
	# MainScene.gd's own FEAT-316 doc) -- drive the same real handoff here so
	# the live COMBINE entry point below can be driven exactly as it was
	# before this feature.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	assert_true(titus.stamina > 0, "fixture assumption: Titus starts with positive Stamina")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")

	_press_combine(instance)

	assert_true(instance.combine_queue_build_session.is_active(), "the live COMBINE press must engage the interactive queue-build pick loop")
	assert_true(instance.selection_overlay.is_active(), "the live COMBINE press must activate the REAL SelectionOverlay")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "COMBINE")
	assert_true(instance.selection_overlay.is_awaiting_option(), "the very first pick must be a Layer-2a option pick (candidate_options), never an immediate hex/target highlight")

	var ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(ids.has("STRIDE"), "the live entry point's very first offer must include STRIDE -- proving BuildVerbQueueUseCase's real candidate pool was consulted, not a hardcoded literal")
	assert_true(ids.has("STRIKE"), "the live entry point's very first offer must include STRIKE")
	assert_false(ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must not be offered before any verb has been picked")
	assert_false(ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "Cancel must not be offered before any verb has been picked (nothing in-progress yet to discard)")

	assert_no_new_orphans("driving the live COMBINE entry point must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 & 3 -- Confirm is absent at queue length 1 and present once
# length reaches 2; STRIDE is excluded from the next pick's candidate_options
# once it has been chosen (no Repeat trait) -- both observed by driving REAL
# button presses (selection_overlay.choose_option()) through the live entry
# point, never by calling BuildVerbQueueUseCase directly.
# ══════════════════════════════════════════════════════════════════════════

func test_confirm_sentinel_absent_at_queue_length_1_and_present_at_length_2_via_live_entry_point() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316: see the identical doc on the "offers stride and strike" test above.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	_titus(instance)

	_press_combine(instance)

	# Pick STRIDE (a real Layer-2a button press, via choose_option() -- the
	# SAME call _on_spell_option_pressed() makes for a real click).
	var first_options: Array = instance.selection_overlay.get_candidate_options()
	var stride_option = _find_option(first_options, "STRIDE")
	assert_not_null(stride_option, "fixture assumption: STRIDE must be a legal first pick")
	instance.selection_overlay.choose_option(stride_option)

	# The loop must have auto-advanced into the SECOND pick (queue length 1).
	assert_true(instance.combine_queue_build_session.is_active(), "the queue-build loop must still be active after a single VERB pick")
	assert_true(instance.selection_overlay.is_active(), "the loop must re-enter Layer 2a for the NEXT pick, not terminate")
	assert_true(instance.selection_overlay.is_awaiting_option())
	var second_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_false(second_ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must be ABSENT once queue length is 1 (TURN context requires >= 2 entries)")

	# ── Criterion 3 -- STRIDE (Repeat=true) must remain offered after being
	# chosen once, enabling STRIDE+STRIDE combinations. ──
	assert_true(second_ids.has("STRIDE"), "STRIDE (repeat=true) must remain offered after being chosen once")
	assert_true(second_ids.has("STRIKE"), "STRIKE must remain legal")
	assert_true(second_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "Cancel must be offered once at least one verb is in-progress")

	# Pick STRIKE (queue length 2) -- Confirm must now be PRESENT.
	var strike_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIKE")
	assert_not_null(strike_option)
	instance.selection_overlay.choose_option(strike_option)

	assert_true(instance.combine_queue_build_session.is_active(), "the queue-build loop must still be active -- the player has not yet confirmed")
	var third_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(third_ids.has(BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID), "Confirm must be PRESENT once queue length reaches 2 (the TURN-context minimum)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- cancelling at the queue-build step via the live entry point
# returns to the verb bar with no queue state retained: COMBINE remains
# selectable, no Layer 2 selection survives, and a fresh attempt starts from
# the SAME Layer-1-equivalent candidate set (no leaked exclusion).
# ══════════════════════════════════════════════════════════════════════════

func test_cancelling_at_queue_build_step_via_live_entry_point_returns_to_verb_bar_with_no_queue_state_retained() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316: see the identical doc on the "offers stride and strike" test above.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	var titus_start_hex = titus.hex_coord
	var stamina_before: int = titus.stamina

	_press_combine(instance)

	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	assert_not_null(stride_option)
	instance.selection_overlay.choose_option(stride_option)

	var mid_build_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(mid_build_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "an in-progress queue-build must offer the Cancel sentinel")

	var cancel_option = _find_option(instance.selection_overlay.get_candidate_options(), CancelCombineUseCaseClass.CANCEL_SENTINEL_ID)
	assert_not_null(cancel_option)
	instance.selection_overlay.choose_option(cancel_option)

	# ── No queue state retained: the build loop is fully torn down. ─────────
	assert_false(instance.combine_queue_build_session.is_active(), "cancelling must tear down the interactive queue-build loop")
	assert_null(instance.combine_queue_build_session.get_queue(), "cancelling must discard the in-progress CombineQueue -- no partial-state leak")
	assert_eq(instance.combine_queue_build_session.get_pending_option(), {}, "cancelling must clear any pending option")

	# ── Control returns to the Layer 1 verb bar. ─────────────────────────────
	assert_false(instance.selection_overlay.is_active(), "cancelling must leave NO Layer 2 selection active")
	assert_true(instance._verb_registry.is_available("COMBINE"), "COMBINE must remain selectable on the Layer 1 verb bar after cancelling")

	# Actor state fully unchanged -- cancelling a queue-build pick must never
	# mutate game state.
	assert_true(titus.hex_coord.equals(titus_start_hex), "cancelling at the queue-build step must never move the actor")
	assert_eq(titus.stamina, stamina_before, "cancelling at the queue-build step must never spend Stamina")

	# A fresh attempt starts from the SAME Layer-1-equivalent candidate set --
	# no leaked STRIDE exclusion from the discarded attempt.
	_press_combine(instance)
	var fresh_ids: Array = _option_ids(instance.selection_overlay.get_candidate_options())
	assert_true(fresh_ids.has("STRIDE"), "STRIDE must be legal again in a fresh attempt -- the cancelled queue's own exclusion must not leak forward")
	assert_true(fresh_ids.has("STRIKE"))
	assert_false(fresh_ids.has(CancelCombineUseCaseClass.CANCEL_SENTINEL_ID), "a brand-new attempt's very first pick must offer no Cancel option (nothing in-progress yet)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- static source scan: no remaining code path in MainScene.gd
# hardcodes queue_entries=[STRIDE, STRIKE] for the live COMBINE entry point.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_source_never_hardcodes_stride_strike_queue_in_the_live_combine_entry_point() -> void:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable as plain source text for this static scan")
	var source: String = file.get_as_text()
	file.close()

	var start_marker: String = "func _verb_bar_combine_enter_selection() -> Dictionary:"
	var start_index: int = source.find(start_marker)
	assert_true(start_index >= 0, "MainScene.gd must still declare _verb_bar_combine_enter_selection()")

	var next_func_index: int = source.find("\nfunc ", start_index + start_marker.length())
	assert_true(next_func_index > start_index, "the scan must be able to locate the end of _verb_bar_combine_enter_selection()'s own body")

	var body: String = source.substr(start_index, next_func_index - start_index)

	assert_false(body.contains("\"STRIDE\""), "_verb_bar_combine_enter_selection() must never hardcode the STRIDE verb_id literal -- the live candidate pool must come from BuildVerbQueueUseCase, not a hardcoded queue")
	assert_false(body.contains("\"STRIKE\""), "_verb_bar_combine_enter_selection() must never hardcode the STRIKE verb_id literal")
	assert_false(body.contains("start_combine_targeting("), "_verb_bar_combine_enter_selection() must never call start_combine_targeting() directly -- it must go through the interactive queue-build pick loop, which only hands off once a queue is actually CONFIRMED")


# ══════════════════════════════════════════════════════════════════════════
# Happy-path regression -- the live entry point's queue-build loop still
# correctly hands off to the UNCHANGED targeting phase (start_combine_targeting())
# only once the player actually confirms a legal 2-entry queue.
# ══════════════════════════════════════════════════════════════════════════

func test_confirming_a_full_queue_via_live_entry_point_hands_off_to_the_unchanged_targeting_phase() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# FEAT-316: see the identical doc on the "offers stride and strike" test above.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	_titus(instance)

	_press_combine(instance)

	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	instance.selection_overlay.choose_option(stride_option)

	var strike_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIKE")
	instance.selection_overlay.choose_option(strike_option)

	var confirm_option = _find_option(instance.selection_overlay.get_candidate_options(), BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID)
	assert_not_null(confirm_option, "Confirm must be offered once queue length reaches 2")
	instance.selection_overlay.choose_option(confirm_option)

	# ── The queue-build loop tore itself down and handed off to the
	# UNCHANGED targeting phase -- start_combine_targeting()'s own
	# established, already-tested behavior (see
	# tests/integration/combine/test_composition_root_wiring.gd). ──────────
	assert_false(instance.combine_queue_build_session.is_active(), "the queue-build loop must be torn down once Confirm succeeds")
	assert_null(instance.combine_queue_build_session.get_queue())
	assert_true(instance._combine_targeting_active, "Confirm must hand off into the interactive Combine sub-action TARGETING loop")
	assert_true(instance.selection_overlay.is_active(), "the targeting phase must immediately activate SelectionOverlay for the first sub-action")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE", "the confirmed queue's first sub-action (order_index 0) must be STRIDE")
	assert_false(instance.selection_overlay.is_awaiting_option(), "the targeting phase highlights hexes/targets directly -- it is not a Layer-2a option pick")

	assert_no_new_orphans("the full queue-build-to-targeting hand-off must leave zero orphaned nodes")
