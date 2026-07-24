extends GutTest
## tests/smoke/test_release_readiness_smoke.gd — FEAT-304 (US-009; resolves
## CHECKLIST-3, CHECKLIST-4, CHECKLIST-5).
##
## Final remediation smoke test closing the deployment blockers exercised by
## this fix cycle. This is the ONE executable checkpoint that proves, in a
## single GUT run:
##
##   1. The real res://MainScene.tscn composition root boots headlessly with
##      no script errors (mirrors tests/smoke/test_main_scene_headless_boot.gd's
##      established in-process boot convention).
##   2. The real Charge steel thread (COMBINE press -> STRIDE pick -> STRIKE
##      pick -> Confirm -> Stride hex-pick -> Strike target-pick) resolves
##      end to end through the SAME production signal chain
##      tests/e2e/combine/test_charge_end_to_end.gd (FEAT-299/DEF-NEW-004)
##      exercises -- a real VerbBarView.press("COMBINE"), real
##      SelectionOverlay.choose_option()/hex_grid_view.hex_clicked
##      emissions, and the REAL, live-wired core CombineActionController.
##      execute() (FEAT-297/298) -- with NO mocks/doubles anywhere in the
##      chain, asserting exactly 1 action + 1 Stamina spent and a Strike
##      resolution that reflects the post-Stride actor position (the steel
##      thread's stated exit point).
##   3. FIX-001's version-bump gate (tests/unit/config/test_project_version.gd,
##      FEAT-301, CHECKLIST-5) still reports the target release version.
##   4. FIX-002's data-commit-hygiene gate
##      (tests/unit/data/test_combine_data_commit_hygiene.gd, FEAT-302,
##      CHECKLIST-4) still reports a clean res://data/ tree.
##   5. FIX-003's own US-008 clean-cancellation regression (also asserted in
##      full, at all three phases, by
##      tests/e2e/combine/test_charge_end_to_end.gd and
##      tests/acceptance/combine/test_us008_clean_cancellation_acceptance.gd,
##      FEAT-303) is unaffected by this iteration's changes -- re-confirmed
##      here at the queue-build-step phase (the phase this suite's own
##      steel thread most directly touches) as this checkpoint's own
##      executable proof.
##
## Criteria 3 and 4 "delegate" to FIX-001/FIX-002's own dedicated gates by
## reusing THEIR checked-in scripts as the single source of truth for the
## expected value / detection mechanism (preloading
## test_project_version.gd's EXPECTED_VERSION const, and mirroring
## test_combine_data_commit_hygiene.gd's `git status --porcelain -- data/`
## invocation verbatim) rather than re-deriving a second, potentially
## divergent copy of either check.
##
## Fixture geometry/seed below mirrors tests/e2e/combine/
## test_charge_end_to_end.gd's own established PROLOGUE_SEED /
## SKELETON_REPOSITIONED_HEX_Q / STRIDE_DESTINATION_HEX_Q convention (that
## file's own consts, reused here directly via preload rather than
## re-declared, so the two suites' fixtures can never silently drift apart).

const ChargeE2EClass = preload("res://tests/e2e/combine/test_charge_end_to_end.gd")
const ProjectVersionTestClass = preload("res://tests/unit/config/test_project_version.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const CombineQueueClass   = preload("res://core/domain/combine/combine_queue.gd")
const VerbQueueEntryClass = preload("res://core/domain/combine/verb_queue_entry.gd")
const CancelCombineUseCaseClass = preload("res://core/application/combine/cancel_combine_use_case.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass  = preload("res://core/geometry/hex_math.gd")
const MovementClass = preload("res://core/rules/movement.gd")

const PROLOGUE_SEED: int = ChargeE2EClass.PROLOGUE_SEED
const SKELETON_REPOSITIONED_HEX_Q: int = ChargeE2EClass.SKELETON_REPOSITIONED_HEX_Q
const STRIDE_DESTINATION_HEX_Q: int = ChargeE2EClass.STRIDE_DESTINATION_HEX_Q

## PROLOGUE_ENCOUNTER_ID -- this project's established fixture encounter id
## (mirrors tests/boot/test_first_cast_firebolt.gd's identically-named/valued
## constant), driven through the real _on_combat_triggered() handoff below.
const PROLOGUE_ENCOUNTER_ID: String = "prologue"


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into GameMode.EXPLORATION with the legacy combat pipeline
## (round_session, VerbBarView/SelectionOverlay configuration, turn_controller
## signal wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This whole suite drives the real Charge
## steel thread (COMBINE press -> ... -> execute()) against round_session/
## the live verb registry, so this shared boot helper now also drives the
## SAME real handoff tests/boot/test_first_cast_firebolt.gd's own
## _boot_main_scene() convention establishes, landing the instance in
## GameMode.COMBAT with a live round_session before returning. Adding an
## `await` here makes this a coroutine -- every call site now does
## `var instance = await _boot_main_scene()`.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

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


# ══════════════════════════════════════════════════════════════════════════
# Checkpoint 1 -- headless MainScene boot succeeds with no script errors.
# ══════════════════════════════════════════════════════════════════════════

func test_headless_main_scene_boot_succeeds_with_no_script_errors() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance, "MainScene.tscn must instantiate headlessly with no script errors")
	assert_eq(instance.outcome, "", "MainScene must not auto-resolve the prologue encounter to a terminal outcome on first frame")
	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession on first frame")
	assert_not_null(instance.encounter_repository, "MainScene.encounter_repository must be non-null after first frame")
	assert_not_null(instance.random_port, "MainScene.random_port must be non-null after first frame")
	assert_not_null(instance.event_sink, "MainScene.event_sink must be non-null after first frame")
	assert_not_null(instance.multi_phase_targeting_controller, "the real MultiPhaseTargetingController must be wired at boot")

	assert_no_new_orphans("headless boot must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Checkpoints 2/3 -- the real Charge steel thread, driven end to end
# exclusively through production signal emissions, ending at execute()'s
# real ExecutionResult with post-move-aware Strike resolution.
# ══════════════════════════════════════════════════════════════════════════

func test_real_charge_steel_thread_executes_with_one_action_one_stamina_and_post_move_strike() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)
	var geo: Dictionary = _reposition_skeleton_for_charge(titus, skeleton)
	var stride_destination = geo["stride_destination"]

	# ── COMBINE pressed via the real VerbBarView/VerbBarRegistry. ───────────
	_press_combine(instance)
	assert_true(instance._combine_build_active, "pressing COMBINE must engage the real interactive queue-build pick loop")

	var stride_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIDE")
	assert_not_null(stride_option, "fixture assumption: STRIDE must be a legal first pick")
	instance.selection_overlay.choose_option(stride_option)

	var strike_option = _find_option(instance.selection_overlay.get_candidate_options(), "STRIKE")
	assert_not_null(strike_option, "fixture assumption: STRIKE must be a legal second pick")
	instance.selection_overlay.choose_option(strike_option)

	# Resolve the Confirm sentinel's real id from the real candidate set
	# rather than hardcoding it, mirroring test_charge_end_to_end.gd's own
	# BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID convention.
	var BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
	var confirm_option = _find_option(instance.selection_overlay.get_candidate_options(), BuildVerbQueueUseCaseClass.CONFIRM_SENTINEL_ID)
	assert_not_null(confirm_option, "Confirm must be offered once the TURN-context minimum queue length is met")
	instance.selection_overlay.choose_option(confirm_option)

	assert_true(instance._combine_targeting_active, "Confirm must hand off into the real interactive targeting loop")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIDE", "the confirmed queue's first sub-action must be STRIDE")

	# ── Stride hex-pick. ─────────────────────────────────────────────────
	var candidate_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	var chosen_hex = null
	for h in candidate_hexes:
		if h.equals(stride_destination):
			chosen_hex = h
			break
	assert_not_null(chosen_hex, "fixture assumption: the intended Stride destination must be a legal candidate")

	instance.hex_grid_view.hex_clicked.emit(chosen_hex)

	assert_true(titus.hex_coord.equals(geo["titus_start_hex"]), "picking a Stride destination must never itself move the actor before execute() runs")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE", "the loop must advance into the STRIKE phase")
	assert_true(instance.selection_overlay.get_highlighted_target_ids().has(skeleton.display_id()), "STRIKE's phase must offer the Skeleton as reachable from the post-move hex")

	var skeleton_hp_before_execute: int = skeleton.hp_current
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina

	# ── Strike target-pick -- fires the entire resolve-validate-dispatch-
	# charge chain automatically from inside production code. ──────────────
	var skeleton_token = instance.hex_grid_view.get_token(skeleton.combatant_id)
	assert_not_null(skeleton_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(skeleton_token.hex_coord)

	assert_false(instance._combine_targeting_active, "the interactive targeting loop must have finished")

	var loop_result: Dictionary = instance._combine_targeting_result
	assert_true(loop_result.get("ok", false), "the real interactive targeting loop must report ok:true (result: %s)" % [loop_result])

	var execution_result: Dictionary = loop_result.get("execution_result", {})

	# ── Checkpoint 3 -- ExecutionResult.ok, actions_spent, stamina_spent. ──
	assert_true(execution_result.get("ok", false), "the REAL, live-wired CombineActionController.execute() must resolve ok=true (result: %s)" % [execution_result])
	assert_eq(execution_result.get("actions_spent", -1), 1, "the steel thread must spend exactly ONE action")
	assert_eq(execution_result.get("stamina_spent", -1), 1, "the steel thread must spend exactly ONE Stamina")

	var actions_spent: int = actions_remaining_before - economy.get_remaining()
	var stamina_spent: int = stamina_before - titus.stamina
	assert_eq(actions_spent, 1, "the live ActionEconomy ledger must reflect exactly ONE action spent")
	assert_eq(stamina_spent, 1, "the live Combatant.stamina ledger must reflect exactly ONE Stamina spent")

	# ── Post-Stride-aware Strike resolution: the actor is at the chosen
	# Stride hex, and the target actually took damage FROM that position. ──
	assert_true(titus.hex_coord.equals(chosen_hex), "actor.hex_coord must equal the chosen Stride destination after execute()")
	assert_true(skeleton.hp_current < skeleton_hp_before_execute, "target.hp_current must reflect the Strike damage applied from the post-move position")

	var resolution_log: Array = execution_result.get("resolution_log", [])
	assert_eq(resolution_log.size(), 2, "resolution_log must carry exactly one entry per dispatched sub-action")
	assert_eq(resolution_log[0].get("verb_id"), "STRIDE", "STRIDE must resolve before STRIKE")
	assert_eq(resolution_log[1].get("verb_id"), "STRIKE")

	assert_no_new_orphans("the real Charge steel thread must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Checkpoint 4 -- FIX-001's version-bump gate: delegates to
# tests/unit/config/test_project_version.gd's own EXPECTED_VERSION const as
# the single source of truth for the target release version, rather than
# re-deriving a second, potentially divergent copy of the expected value.
# ══════════════════════════════════════════════════════════════════════════

func test_project_settings_version_matches_target_release_version_fix_001() -> void:
	var version: Variant = ProjectSettings.get_setting("application/config/version")
	assert_eq(
		version, ProjectVersionTestClass.EXPECTED_VERSION,
		"application/config/version must report the target release version %s (FIX-001, CHECKLIST-5)" % ProjectVersionTestClass.EXPECTED_VERSION
	)
	assert_ne(
		version, ProjectVersionTestClass.STALE_VERSION,
		"application/config/version must have been bumped past the stale %s value (FIX-001, CHECKLIST-5)" % ProjectVersionTestClass.STALE_VERSION
	)


# ══════════════════════════════════════════════════════════════════════════
# Checkpoint 5 -- FIX-002's data-commit-hygiene gate: mirrors
# tests/unit/data/test_combine_data_commit_hygiene.gd's own
# `git status --porcelain -- data/` invocation verbatim, so this checkpoint
# and that dedicated gate can never silently diverge.
# ══════════════════════════════════════════════════════════════════════════

func _git_available() -> bool:
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--is-inside-work-tree"], out, true)
	return rc == 0


func test_data_directory_has_no_uncommitted_or_untracked_changes_fix_002() -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping data/ commit-hygiene gate")
		return

	var repo_root: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", repo_root, "status", "--porcelain", "--", "data/"], out, true)
	var combined: String = ""
	for line in out:
		combined += String(line)

	assert_eq(rc, 0, "git status --porcelain -- data/ must exit 0; got %d, output: %s" % [rc, combined])
	assert_eq(
		combined.strip_edges(), "",
		(
			"res://data/ has uncommitted or untracked changes at smoke-test run time "
			+ "(FIX-002, CHECKLIST-4). Run `git add data/ && git commit` to resolve. "
			+ "Offending `git status --porcelain -- data/` output:\n%s"
		) % combined
	)


# ══════════════════════════════════════════════════════════════════════════
# Checkpoint 6 -- US-008 clean-cancellation regression is unaffected by this
# iteration's changes. Full three-phase coverage remains in
# tests/e2e/combine/test_charge_end_to_end.gd and
# tests/acceptance/combine/test_us008_clean_cancellation_acceptance.gd; this
# smoke checkpoint re-confirms the build-step phase (the phase this file's
# own steel thread most directly exercises) as its own single, executable
# regression proof, run in the SAME gut invocation as checkpoints 1-5 above.
# ══════════════════════════════════════════════════════════════════════════

func test_cancel_during_queue_build_step_regression_still_passes() -> void:
	var instance = await _boot_main_scene()
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

	var cancel_option = _find_option(instance.selection_overlay.get_candidate_options(), CancelCombineUseCaseClass.CANCEL_SENTINEL_ID)
	assert_not_null(cancel_option)
	instance.selection_overlay.choose_option(cancel_option)

	assert_false(instance._combine_build_active, "cancelling must tear down the interactive queue-build loop")
	assert_null(instance._combine_build_queue, "cancelling must discard the in-progress CombineQueue -- no partial-state leak")

	assert_true(titus.hex_coord.equals(titus_start_hex))
	assert_eq(skeleton.hp_current, skeleton_hp_before)
	assert_eq(titus.stamina, stamina_before)

	assert_false(instance.selection_overlay.is_active())
	assert_true(instance._verb_registry.is_available("COMBINE"), "cancellation must leave COMBINE selectable again on the Layer 1 verb bar")
