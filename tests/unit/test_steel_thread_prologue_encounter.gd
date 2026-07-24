extends GutTest
## tests/unit/test_steel_thread_prologue_encounter.gd — FEAT-159
## (US-001/004/007/009/010/015, resolves FIND-142/143/144/145/146)
##
## Final "steel thread" end-to-end regression exercising the REAL, shipped
## res://MainScene.tscn composition root (project.godot's own run/main_scene
## entry point) AFTER all of FIX-001..FIX-007 have landed. No production
## code is touched by this feature (files_to_create is empty; this test
## file is the only file_to_modify) — every object driven below is the
## exact, unmodified, REUSED production class already covered individually
## by FEAT-152 (tests/unit/test_ranged_weapon_fixtures.gd), FEAT-153
## (tests/unit/core/application/test_resolve_action_off_guard.gd), FEAT-155
## through FEAT-158, and the pre-existing steel-thread suites
## (tests/gut/test_steel_thread_e2e.gd, tests/integration/
## test_steel_thread_prologue_encounter.gd, tests/e2e/
## test_steel_thread_post_remediation_smoke.gd). This file's job is to
## prove ALL of those remediations still compose correctly TOGETHER,
## through the ONE real, shipped entry point, closing out the steel-thread
## exit criteria.
##
## FEAT-181 (DEF-001 / FR-009/NFR-003): FEAT-006 (US-006) later removed the
## legacy presentation/strike_action_control.gd/.tscn control entirely --
## Strike is now driven SOLELY through the Layer 1 verb bar
## (presentation/verb_bar_view.gd) -> `_verb_registry`'s STRIKE entry (see
## MainScene.gd's file-level FEAT-006 doc). This file's Strike-driving
## criteria below (3 and 5) are retargeted onto that real two-layer flow
## instead of the deleted control, preserving their original regression
## intent unchanged.
##
## test_criteria satisfied:
##   1. FIX-001 fixture files (data/weapons/shortbow.tres,
##      data/weapons/longbow.tres) are present and load on a fresh
##      checkout, so `godot --gut-run-all` cannot fail on a missing
##      Resource -- this file lives under res://tests (root .gutconfig.json,
##      include_subdirs=true), so it is itself part of that
##      `--gut-run-all` gate (FIND-144).
##      -> test_fix001_ranged_weapon_fixtures_present_and_loadable()
##   2. The full captured event log (MainScene's real, live
##      ConsoleEventSinkAdapter.log) shows an AttackEvent resolved against
##      an Off-Guard target with defense_value reduced by exactly 2 relative
##      to the SAME target's plain (non-Off-Guard) ac baseline, in the same
##      run (FIND-142/FIND-145).
##      -> test_off_guard_condition_reduces_defense_value_by_two_in_live_event_log()
##   3. The full captured event log shows a successful ranged Strike (a
##      shortbow-equipped actor) against a target 3+ hexes away, with that
##      target having been offered as selectable (get_selectable_target_ids())
##      BEFORE resolution (FIND-143/FIND-146).
##      -> test_ranged_shortbow_strike_against_target_three_hexes_away_is_selectable_and_resolves_and_is_logged()
##   4. The headless smoke boot (US-001/NFR-006) still passes with zero
##      unhandled errors: MainScene.tscn boots, reaches an interactive
##      (not auto-resolved) state, and every composition-root field
##      resolves non-null, with no leaked orphan nodes.
##      -> test_headless_smoke_boot_reaches_interactive_state_with_zero_unhandled_errors()
##   5. Driving the real $StrikeActionControl/$EndTurnControl controls to
##      conclusion under the pinned seed=42 fixture fires exactly one
##      EncounterResultEvent and reaches the correct Win/Loss
##      $ResultScreenView state, matching the pre-remediation steel-thread
##      outcome for this pinned fixture (Titus's first Strike is a critical
##      hit that one-shots the 8-HP Skeleton -- "won" -- documented already
##      by tests/e2e/test_prologue_encounter_e2e_smoke.gd and
##      tests/gut/test_steel_thread_e2e.gd).
##      -> test_seed_42_fixture_concludes_with_encounter_result_event_and_matches_pre_remediation_win_outcome()

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass    = preload("res://core/rules/round_events.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const HexMathClass        = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")
const FlankingClass       = preload("res://core/rules/flanking.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) --
## injected in-process via MainScene's `seed_override` contract (ADR-004
## top precedence) so every scenario below is reproducible.
const SEED: int = 42

## Safety bound on the player-Strike/End-Turn exchange loop in criterion 5
## (CWE-835 "never loop unbounded" guard, mirroring this codebase's
## established convention -- see tests/e2e/test_steel_thread_post_
## remediation_smoke.gd / tests/integration/test_steel_thread_prologue_
## encounter.gd's identically-motivated guards).
const _MAX_DRIVE_ITERATIONS: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture helper
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene_with_seed(seed_value) -- instantiates the REAL
## res://MainScene.tscn (project.godot's own run/main_scene, the steel
## thread's entry_point), pinning `seed_override` BEFORE add_child()
## triggers _ready() so the resulting boot is reproducible (ADR-004's
## in-process composition-root contract). No manual setup beyond this one
## injected property -- MainScene.gd's own _ready() performs every other
## wiring step.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (FIND-144 / FIX-001) -- the ranged-weapon fixture files this
# steel thread depends on (data/weapons/shortbow.tres, data/weapons/
# longbow.tres) are present and load on a fresh checkout.
# ══════════════════════════════════════════════════════════════════════════

func test_fix001_ranged_weapon_fixtures_present_and_loadable() -> void:
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	var longbow  = ResourceLoader.load("res://data/weapons/longbow.tres")

	assert_not_null(shortbow, "data/weapons/shortbow.tres must be committed and load on a fresh checkout (FIX-001/FIND-144)")
	assert_not_null(longbow, "data/weapons/longbow.tres must be committed and load on a fresh checkout (FIX-001/FIND-144)")
	if shortbow == null or longbow == null:
		return

	assert_is(shortbow, WeaponResourceClass, "shortbow.tres must be a WeaponResource")
	assert_is(longbow, WeaponResourceClass, "longbow.tres must be a WeaponResource")
	assert_true(shortbow.range_hexes >= 3, "shortbow.range_hexes must be able to reach a 3+ hex target for criterion 3 below")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (US-001/NFR-006) -- headless smoke boot still passes with zero
# unhandled errors: real MainScene.tscn boots into an interactive (not
# auto-resolved) state, every composition-root field resolves non-null, no
# leaked orphan nodes.
# ══════════════════════════════════════════════════════════════════════════

func test_headless_smoke_boot_reaches_interactive_state_with_zero_unhandled_errors() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# FEAT-316 (resolves DEF-001/PR-001): round_session and the rest of the
	# legacy combat pipeline are now gated behind a real combat trigger rather
	# than being wired unconditionally in _ready() -- drive the same real
	# _on_combat_triggered() handoff so this headless smoke boot still reaches
	# a genuinely interactive (live RoundSession) state.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance.resolved_seed, SEED, "seed_override must be honored as the resolved seed")
	assert_eq(instance.outcome, "", "MainScene must NOT auto-resolve the prologue encounter to a terminal outcome on first frame")
	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with zero player input")

	assert_not_null(instance.encounter_repository, "encounter_repository (repository adapter) must be non-null after first frame")
	assert_not_null(instance.random_port, "random_port (RandomPort adapter) must be non-null after first frame")
	assert_not_null(instance.event_sink, "event_sink (EventSinkPort adapter) must be non-null after first frame")
	assert_not_null(instance.resolve_action_use_case, "resolve_action_use_case must be non-null after first frame")
	assert_not_null(instance.run_round_use_case, "run_round_use_case must be non-null after first frame")
	assert_not_null(instance.determine_outcome_use_case, "determine_outcome_use_case must be non-null after first frame")

	assert_not_null(instance.hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_eq(instance.hex_grid_view.get_token_count(), 3, "HexGridView must render one token per live combatant (Titus + Marigold + Skeleton)")

	assert_not_null(instance.event_log_view, "MainScene must expose a non-null event_log_view")
	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events have been logged yet before any player input")

	assert_false(instance.result_screen_view.is_shown(), "the real ResultScreenView must not show a result before any input has been given")

	# No unhandled errors manifest as a crash before reaching this line; this
	# final orphan check additionally guards against leaked nodes across the
	# boot (a common symptom of an unhandled error mid-_ready()).
	assert_no_new_orphans("MainScene's real boot must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (FIND-142/FIND-145) -- the Off-Guard +2 defense reduction
# actually reaches the LIVE Strike resolution path, observable in
# MainScene's real, captured event log (instance.event_sink.log).
# ══════════════════════════════════════════════════════════════════════════

func test_off_guard_condition_reduces_defense_value_by_two_in_live_event_log() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# Titus (party[0]) already occupies (0,0); the Skeleton (_enemies[0])
	# occupies (1,0) per prologue_encounter.tres. Appending a second party
	# combatant at (2,0) -- the hex directly OPPOSITE (0,0) around (1,0) --
	# completes a flanking pair, matching FEAT-153's own MainScene wiring
	# fixture (tests/unit/core/application/test_resolve_action_off_guard.gd).
	var ally = CombatantClass.from_dict({
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "steel_thread_off_guard_ally",
		"hex_coord": HexCoordClass.new(2, 0),
	})
	instance._party.append(ally)

	assert_eq(
		instance._enemies[0].conditions, [],
		"fixture assumption: before any flanking, the live Skeleton carries no conditions"
	)

	instance._refresh_off_guard_conditions()

	assert_true(
		FlankingClass.OFF_GUARD_CONDITION in instance._enemies[0].conditions,
		"MainScene._refresh_off_guard_conditions() must write Off-Guard into the LIVE _enemies[0] Dictionary"
	)

	# Baseline: the target's plain, non-Off-Guard defense value is its "ac"
	# field, untouched by the conditions list (core/application/
	# resolve_action_use_case.gd computes defense_value = target["ac"] -
	# off_guard_reduction -- this IS the "non-Off-Guard baseline").
	var baseline_defense_value: int = instance._enemies[0].ac

	# Resolve a REAL Strike through MainScene's own, live
	# resolve_action_use_case -- the SAME instance wired into the composition
	# root -- so the resulting AttackEvent lands in MainScene's real, full
	# captured event log (instance.event_sink.log), not a throwaway test rig.
	# A fresh, unrelated ActionEconomy is used so this does not perturb the
	# live round_session's own turn-order/budget bookkeeping.
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	var attacker = instance._party[0]
	var target = instance._enemies[0]

	var events_before: int = instance.event_sink.log.size()
	var result: Dictionary = instance.resolve_action_use_case.resolve(
		attacker, ae, target, "Strike", 1, 0
	)
	assert_true(result.get("ok", false), "the Off-Guard Strike must resolve through the real, live resolve_action_use_case")

	var new_attack_events: Array = instance.event_sink.log.slice(events_before).filter(
		func(e): return e is RoundEventsClass.AttackBroadcast
	)
	assert_eq(new_attack_events.size(), 1, "exactly one new AttackEvent must appear in MainScene's real, full captured event log")

	var logged_event = new_attack_events[0]
	assert_eq(logged_event.target_name, "Skeleton", "the logged AttackEvent must target the Off-Guard Skeleton")
	assert_eq(
		logged_event.defense_value, baseline_defense_value - 2,
		"the FULL captured event log must show the AttackEvent resolved against the Off-Guard target with defense_value reduced by exactly 2 relative to the non-Off-Guard baseline (FIND-142/FIND-145)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (FIND-143/FIND-146) -- a shortbow-equipped actor's ranged
# Strike against a target 3+ hexes away is offered as selectable BEFORE
# resolution, then resolves and is logged in MainScene's real, full
# captured event log.
#
# FEAT-181 (DEF-001): retargeted onto the real `_verb_registry` (the SOLE
# Strike entry point since FEAT-006 removed presentation/
# strike_action_control.gd) instead of the deleted control. The live active
# actor's own "weapon" Dictionary is mutated in place to the shortbow
# fixture -- the SAME "mutate the LIVE Dictionary" convention criterion 2
# above already uses via _refresh_off_guard_conditions() -- and a synthetic,
# far-away ranged target is appended to the LIVE `_enemies` list so
# `_verb_registry`'s STRIKE entry (which reads round_session.current_actor()/
# `_enemies` directly, see MainScene.gd's _strike_reachable_targets()) picks
# it up without needing a rendered HexGridView token of its own.
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_shortbow_strike_against_target_three_hexes_away_is_selectable_and_resolves_and_is_logged() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(shortbow, "data/weapons/shortbow.tres must load (FIX-001)")

	var actor = instance.round_session.current_actor_entity()
	var actor_hex = actor.hex_coord
	assert_not_null(actor_hex, "fixture assumption: the live active actor has a hex_coord")

	# Equip the LIVE active actor with the shortbow fixture in place -- the
	# SAME live Dictionary `_verb_registry`'s STRIKE entry reads from, never a
	# second/independent actor.
	actor.weapon = {
		"damage_modifier_attribute": shortbow.damage_modifier_attribute,
		"proficiency_bonus":         shortbow.proficiency_bonus,
		"damage_die":                shortbow.damage_die,
		"range_hexes":               shortbow.range_hexes,
	}

	# Placed far from the live Titus/Skeleton fixture so this scenario is
	# fully isolated from it; hex_distance(actor_hex, target_hex) == 3, well
	# within shortbow.range_hexes (8).
	var target_hex := HexCoordClass.new(actor_hex.q + 3, actor_hex.r)
	assert_true(
		HexMathClass.hex_distance(actor_hex, target_hex) >= 3,
		"fixture assumption: the target must be at least 3 hexes away from the shortbow-equipped actor"
	)

	# ac deliberately far below any possible roll_total so the Strike is
	# guaranteed to hit (a genuinely "successful" ranged Strike), without
	# needing to control MainScene's live, real (seeded but shared) RNG roll
	# order -- isolates this scenario's "successful"/logged assertion from
	# exactly which value that shared RNG happens to yield here.
	#
	# Iteration K FEAT-004 (US-004, ADR-004): the enemy target now genuinely
	# reacts on this call site (resolve_action_use_case.resolve_reactive(),
	# MainScene.gd's _verb_bar_strike_execute()) -- an ac this low makes a
	# PreHitAvoidance Dodge always "worthwhile" (MobilityDodgeRule), which
	# would SUBSTITUTE a fresh Mobility check for this fixture's absurd ac,
	# defeating the "guaranteed hit" isolation this scenario needs (it is
	# testing ranged-reach selectability/logging, not reactions). Marking the
	# target Immobilized keeps it ineligible for Dodge (core/rules/
	# resolution.gd's is_dodge_eligible()), restoring the deterministic
	# guaranteed-hit contract this scenario has always relied on.
	var target = CombatantClass.from_dict({
		"name":        "SteelThreadRangedTarget",
		"combatant_id": "steel_thread_ranged_target",
		"hp_current":  50,
		"ac":          -1000,
		"hex_coord":   target_hex,
		"conditions":  ["Immobilized"]
	})
	instance._enemies.append(target)

	# ── Pre-resolution: the 3+ hex target must be offered as selectable
	# through the real `_verb_registry`'s STRIKE entry. ─────────────────────
	assert_true(instance._verb_registry.is_available("STRIKE"), "STRIKE must be available with a live ranged in-reach target")
	var selection: Dictionary = instance._verb_registry.enter_selection("STRIKE")
	var selectable_ids: Array = selection.get("candidate_targets", [])
	assert_true(
		selectable_ids.has("steel_thread_ranged_target"),
		"a target 3+ hexes away must be offered as selectable BEFORE resolution when the actor wields a ranged (shortbow) weapon (FIND-143/FIND-146)"
	)

	# ── Resolution: `_verb_registry.execute()` forwards to MainScene's real,
	# live resolve_action_use_case -- the resulting AttackEvent lands in
	# MainScene's real, full captured event log. ────────────────────────────
	var events_before: int = instance.event_sink.log.size()
	var result: Dictionary = instance._verb_registry.execute("STRIKE", "steel_thread_ranged_target")

	assert_true(result.get("ok", false), "the ranged Strike against the 3+ hex target must resolve successfully")
	assert_true(result.get("resolved", false), "the ranged Strike must be marked resolved")

	var new_attack_events: Array = instance.event_sink.log.slice(events_before).filter(
		func(e): return e is RoundEventsClass.AttackBroadcast
	)
	assert_eq(new_attack_events.size(), 1, "the resolved ranged Strike must appear in MainScene's real, full captured event log")
	var logged_event = new_attack_events[0]
	assert_eq(logged_event.attacker_name, actor.name, "the logged AttackEvent must attribute the ranged Strike to the shortbow-equipped actor")
	assert_eq(logged_event.target_name, "SteelThreadRangedTarget", "the logged AttackEvent must target the 3+ hex-away target")
	assert_true(logged_event.hit, "the ranged Strike must be a successful (hit) Strike, per this fixture's guaranteed-hit target ac")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- driving the real $VerbBarView (STRIKE, via `_verb_registry`
# and the real SelectionOverlay/HexGridView click flow)/$EndTurnControl
# controls to conclusion under the pinned seed=42 fixture fires exactly one
# EncounterResultEvent and reaches the correct Win/Loss $ResultScreenView
# state, matching the pre-remediation steel-thread outcome for this fixture.
#
# FEAT-181 (DEF-001): retargeted onto the real Layer 1 (VerbBarView.press())
# / Layer 2 (SelectionOverlay via HexGridView.hex_clicked) two-layer flow
# instead of the deleted presentation/strike_action_control.gd control (see
# tests/gut/test_strike_layer2_integration.gd's identically-shaped click
# convention).
# ══════════════════════════════════════════════════════════════════════════

func test_seed_42_fixture_concludes_with_encounter_result_event_and_matches_pre_remediation_win_outcome() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(instance.result_screen_view.is_shown(), "fixture assumption: no result is shown before any input")
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption (seed 42): the first actor is the living player combatant Titus"
	)

	# ── Drive the REAL controls, one player turn at a time, until the round
	# concludes -- every enemy turn in between (if any) is auto-driven by the
	# real $TurnController via MainScene's EndTurnControl.turn_ended handoff. ──
	var guard: int = 0
	while not instance.round_session.is_round_over() and guard < _MAX_DRIVE_ITERATIONS:
		if not instance.round_session.current_actor().is_enemy:
			if instance._verb_registry.is_available("STRIKE"):
				var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
				var target_ids: Array = selection.get("candidate_targets", [])
				if target_ids.size() > 0:
					var target_token = instance.hex_grid_view.get_token(target_ids[0])
					if target_token != null:
						instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
		instance.end_turn_control.press()
		guard += 1

	assert_true(
		instance.round_session.is_round_over(),
		"driving the real VerbBarView(STRIKE)/EndTurnControl controls must conclude the round well within this loop's safety bound (guard=%d/%d)" % [guard, _MAX_DRIVE_ITERATIONS]
	)

	var decided_outcome: String = instance.round_session.outcome()
	assert_eq(
		decided_outcome, "won",
		"the pinned seed=42 prologue fixture must reach the SAME pre-remediation outcome ('won' -- Titus's first Strike is a critical hit that one-shots the 8-HP Skeleton, per tests/e2e/test_prologue_encounter_e2e_smoke.gd's documented fixture behavior); got '%s'" % decided_outcome
	)

	var result_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "exactly one EncounterResultEvent must be emitted through the real event sink")
	assert_eq(result_events[0].outcome, "won", "the terminal event's outcome must match the decided 'won' outcome")

	assert_true(instance.result_screen_view.is_shown(), "the real ResultScreenView must render once EncounterResultEvent is received")
	assert_eq(instance.result_screen_view.get_result_text(), "Win", "ResultScreenView must render 'Win' matching the decided outcome")
	assert_eq(instance.result_screen_view.get_label_text(), "Win", "the rendered Label text must match the displayed result text")

	# Post-conclusion input guard (US-010/US-012): combat controls disabled.
	assert_true(instance.verb_bar_view.is_locked(), "VerbBarView must be locked (no verb, including STRIKE, remains pressable) once the encounter has concluded")
	assert_false(instance.end_turn_control.is_enabled(), "EndTurnControl must be disabled once the encounter has concluded")
