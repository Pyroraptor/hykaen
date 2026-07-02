extends GutTest
## tests/gut/test_steel_thread_e2e.gd
##
## FEAT-134 / US-001 through US-011: the FINAL integration/E2E test exercising
## the complete steel thread from entry_point to exit_point through the real,
## shipped res://MainScene.tscn composition root -- not mocks, not a
## test-local resolver/use-case graph.
##
## Boots the REAL production scene (matching project.godot's run/main_scene)
## headlessly with an injected `seed_override` of 42 (the deterministic-test
## fixture seed baked into data/encounters/prologue_encounter.tres, honored
## as the top-precedence branch of infrastructure/seed_policy.gd's
## SeedPolicy.resolve_from_environment(), ADR-004), then:
##
##   1. asserts zero unhandled errors on first frame (every composition-root
##      field wired -- see tests/gut/test_smoke_boot.gd's established
##      convention for why this is this project's proxy for that criterion
##      under Godot 4.3, whose push_error capture hook is a 4.4+ API);
##   2. asserts the hex battlefield / turn-order / event-log widgets
##      (FEAT-005 / FEAT-006 / FEAT-004 -- scenes/battlefield/HexBattlefield.gd,
##      scenes/battlefield/TurnOrderWidget.gd, presentation/event_log_view.gd)
##      are populated and reflect the TRUE domain state immediately after boot;
##   3. programmatically drives a player Strike (FEAT-007,
##      scenes/battlefield/StrikeInputController.gd) against an in-reach
##      enemy and asserts an AttackEvent appears in the event log with the
##      hex-battlefield readouts updated accordingly;
##   4. programmatically issues a pass (FEAT-008,
##      scenes/battlefield/EndTurnController.gd) and asserts the enemy's turn
##      is auto-driven by the SAME resolve_action_use_case pipeline via
##      core/combat/ai.gd (FEAT-009), producing further logged events;
##   5. drives the full round loop to conclusion and asserts
##      scenes/battlefield/ResultScreen.gd (FEAT-010) displays WIN or LOSS
##      with the full, correctly ordered event log and the final combatant
##      HP/state snapshot, and that further input is rejected once concluded;
##   6. re-runs the whole drive under the SAME pinned seed and asserts a
##      byte-identical ordered event sequence (CI determinism gate, NFR-002/006).
##
## Scope note: this file drives the FEAT-001..FEAT-011 "legacy" battlefield
## widget stack MainScene.gd still wires alongside its newer presentation/
## controls (hex_battlefield / turn_order_widget / strike_input_controller /
## end_turn_controller / result_screen -- see MainScene.gd's own file-level
## doc, steps 5/6/7/9/10/11) -- the exact FEAT-004 through FEAT-010
## dependency set this feature (FEAT-134) declares. The newer presentation/
## stack (StrikeActionControl/EndTurnControl/TurnController/ResultScreenView,
## FEAT-109 onward) already has its own dedicated end-to-end coverage in
## tests/integration/test_steel_thread_prologue_encounter.gd (FEAT-113 /
## FEAT-123 / FEAT-124) -- this file is NOT a duplicate of that coverage; it
## closes out the original steel thread's own widget/controller set, driven
## through the SAME real MainScene.tscn entry point and the SAME
## resolve_action_use_case / run_round_use_case pipeline (ADR-002/ADR-007: no
## forked/duplicate path exists for either stack).
##
## No production code is modified for this feature -- every object driven
## below is the exact, unmodified, REUSED production class already covered
## by its own unit tests (tests/gut/test_hex_battlefield.gd,
## test_turn_order_widget.gd, test_event_log_widget.gd,
## test_strike_input_controller.gd, test_end_turn_controller.gd,
## test_result_screen.gd, test_enemy_ai_turn.gd, test_seed_policy.gd,
## test_smoke_boot.gd) -- this file's job is proving they compose correctly
## end-to-end through the ONE real, shipped composition root.
##
## Picked up automatically by the root `.gutconfig.json` (`res://tests`,
## include_subdirs=true) and therefore by both `scripts/test_command.sh`
## (stage 3, `godot --headless -- --gut-run-all`, FEAT-011/FEAT-133's CI
## gate) and `.github/workflows/test.yml`'s "Run GUT tests" step -- no
## additional CI wiring is required by this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass = preload("res://core/rules/round_events.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) -- injected
## in-process via MainScene's `seed_override` contract (FEAT-002/003, ADR-004
## top precedence) so this file's assertions never depend on the randomized
## real-play seed MainScene resolves by default.
const SEED: int = 42

## An upper bound on how many player-turn/pass drive cycles
## _drive_to_round_over() will run before giving up. core/rules/
## action_economy.gd caps every combatant at MAX_BUDGET=7 actions per round
## and this steel thread's only action is a 1-action Strike, so a 1v1
## encounter (prologue_encounter.tres: Titus vs one Skeleton) must conclude
## well within this bound -- purely a defensive guard against a stalled drive
## hanging the test suite (mirrors tests/integration/
## test_steel_thread_prologue_encounter.gd's identically-motivated guard).
const _MAX_DRIVE_ITERATIONS: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture helpers
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene_with_seed(seed_value) -- instantiates the REAL
## res://MainScene.tscn (project.godot's own run/main_scene, the steel
## thread's entry_point) with `seed_override` pinned BEFORE add_child()
## triggers _ready(), so the resulting boot is reproducible (FEAT-002/003 /
## US-002/003 in-process composition-root contract).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Dictionary -- looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the SAME
## Dictionaries every resolve_action_use_case call mutates in place) by
## combatant_id.
func _find_combatant_by_id(instance, combatant_id: String) -> Dictionary:
	for combatant in instance._party + instance._enemies:
		if combatant.get("combatant_id", "") == combatant_id:
			return combatant
	return {}


## _drive_to_round_over(instance) -> void -- drives the REAL
## $HexBattlefield/$TurnOrderWidget-adjacent StrikeInputController /
## EndTurnController controllers, one player turn at a time, until the round
## concludes. Every enemy turn in between is auto-driven by the real
## $TurnController via MainScene's `_on_end_turn_control_turn_ended` handoff
## (which both scenes/battlefield/EndTurnController.gd's `turn_ended` signal
## and presentation/end_turn_control.gd's own are wired to -- see
## MainScene.gd _ready()).
func _drive_to_round_over(instance) -> void:
	var guard: int = 0
	while not instance.round_session.is_round_over() and guard < _MAX_DRIVE_ITERATIONS:
		if not instance.round_session.current_actor().get("_is_enemy", true):
			var target_ids: Array = instance.strike_input_controller.get_selectable_target_ids()
			if target_ids.size() > 0:
				instance.strike_input_controller.select_target(target_ids[0])
		instance.end_turn_controller.press()
		guard += 1


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — real MainScene.tscn boots headlessly with seed_override=42
# and zero unhandled errors on first frame.
# ══════════════════════════════════════════════════════════════════════════

func test_boots_real_main_scene_with_seed_override_42_and_zero_unhandled_errors() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(
		instance.resolved_seed, SEED,
		"seed_override=42 must be honored as the resolved seed (ADR-004 top precedence)"
	)

	# Every composition-root field is only left null when an internal
	# push_error() fail-fast path was hit (see MainScene.gd's _ready()) --
	# asserting non-null on all of them is this project's established proxy
	# for "zero unhandled errors on boot" (tests/gut/test_smoke_boot.gd).
	assert_not_null(instance.encounter_repository, "encounter_repository (EncounterRepositoryPort adapter) must be non-null after first frame")
	assert_not_null(instance.random_port, "random_port (RandomPort adapter) must be non-null after first frame")
	assert_not_null(instance.event_sink, "event_sink (EventSinkPort adapter) must be non-null after first frame")
	assert_not_null(instance.encounter, "encounter (EncounterClass) must be non-null after first frame")
	assert_not_null(instance.round_session, "round_session must be a real RoundSession after first frame")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no input")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — HexBattlefield, TurnOrderWidget, and EventLogView are all
# populated and reflect the TRUE domain state immediately after boot.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_populates_hex_battlefield_turn_order_widget_and_event_log() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	var live_combatants: Array = instance._party + instance._enemies
	assert_eq(live_combatants.size(), 2, "fixture assumption: prologue_encounter.tres yields Titus + one Skeleton")

	# ── HexBattlefield (FEAT-005 / US-005) ──────────────────────────────────
	assert_not_null(instance.hex_battlefield, "MainScene must expose a non-null hex_battlefield")
	assert_eq(
		instance.hex_battlefield.get_combatant_count(), live_combatants.size(),
		"HexBattlefield must render one readout per live combatant"
	)
	for combatant in live_combatants:
		var combatant_id: String = combatant.get("combatant_id", "")
		var readout = instance.hex_battlefield.get_readout(combatant_id)
		assert_not_null(readout, "HexBattlefield must render a readout for %s" % combatant_id)
		if readout == null:
			continue
		var status: Dictionary = readout.get_status()
		assert_eq(status.get("name", ""), combatant.get("name", ""), "readout name must match the true domain combatant")
		assert_eq(status.get("hp_current", -1), combatant.get("hp_current", -2), "readout HP must reflect true domain state immediately after boot")

	# ── TurnOrderWidget (FEAT-006 / US-006) ─────────────────────────────────
	assert_not_null(instance.turn_order_widget, "MainScene must expose a non-null turn_order_widget")
	assert_eq(
		instance.turn_order_widget.get_row_count(), live_combatants.size(),
		"TurnOrderWidget must show one row per live combatant"
	)
	var ordered_ids: Array = instance.turn_order_widget.get_ordered_combatant_ids()
	for combatant in live_combatants:
		assert_true(
			ordered_ids.has(combatant.get("combatant_id", "")),
			"turn order must include %s" % combatant.get("name", "")
		)
	assert_eq(
		instance.turn_order_widget.get_active_combatant_id(), instance.round_session.current_actor().get("combatant_id", ""),
		"TurnOrderWidget's active highlight must match RoundSession's true current actor immediately after boot"
	)

	# ── EventLogView (FEAT-004 / US-004) ────────────────────────────────────
	assert_not_null(instance.event_log_view, "MainScene must expose a non-null event_log_view")
	assert_eq(
		instance.event_log_view.get_entry_count(), 0,
		"fixture assumption: no events have been logged yet before any player input"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a programmatic player Strike against an in-reach enemy
# produces an AttackEvent in the event log and updates the hex-battlefield
# readouts accordingly (FEAT-007 / US-007).
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_produces_attack_event_and_updates_readouts() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption (seed 42): the first actor is the living player combatant Titus"
	)

	var target_ids: Array = instance.strike_input_controller.get_selectable_target_ids()
	assert_true(target_ids.size() > 0, "StrikeInputController must offer at least one in-reach target immediately after boot")
	var target_id: String = target_ids[0]

	var result: Dictionary = instance.strike_input_controller.select_target(target_id)
	assert_true(result.get("ok", false), "the player's Strike against an in-reach target must resolve successfully")
	assert_true(result.get("resolved", false), "the Strike must be marked resolved by the real resolve_action_use_case")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the real EventLogView must observe at least one entry for the resolved Strike's AttackEvent"
	)
	var log_text: String = instance.event_log_view.get_entry_text(0)
	assert_string_contains(log_text, "Titus")
	assert_string_contains(log_text, "Skeleton")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "exactly one AttackEvent must have been emitted for the Strike")
	assert_eq(attack_events[0].attacker_name, "Titus", "the AttackEvent must attribute the Strike to Titus")
	assert_eq(attack_events[0].target_name, "Skeleton", "the AttackEvent must target the Skeleton")

	var target_combatant: Dictionary = _find_combatant_by_id(instance, target_id)
	assert_false(target_combatant.is_empty(), "fixture assumption: the selected target is one of MainScene's live combatant Dictionaries")

	var readout = instance.hex_battlefield.get_readout(target_id)
	assert_not_null(readout, "HexBattlefield must still have a readout for the struck target")
	if readout != null:
		# CombatantReadout clamps a displayed HP at 0 (see scenes/battlefield/
		# CombatantReadout.gd's maxi() floor) -- compare against the same floor.
		assert_eq(
			readout.get_status().get("hp_current", -1), maxi(target_combatant.get("hp_current", -2), 0),
			"the hex-battlefield readout must update to reflect the target's post-Strike HP"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — a programmatic pass drives the enemy's turn through
# core/combat/ai.gd via the SAME use cases, producing further logged events
# (FEAT-008 / FEAT-009 / US-008 / US-009).
#
# The player's turn is passed WITHOUT Striking first, so the turn cursor
# advances directly onto the Skeleton with zero prior RandomNumberPort draws
# consumed -- deterministically exercising the AI auto-drive path regardless
# of which values the fixed seed=42 RNG happens to yield for a first Strike
# (mirrors tests/integration/test_steel_thread_prologue_encounter.gd's
# identically-motivated ordering).
# ══════════════════════════════════════════════════════════════════════════

func test_pass_drives_enemy_turn_via_ai_through_same_use_cases() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: the first actor must be the living player combatant Titus"
	)
	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no Strike has been made yet")

	var press_result: Dictionary = instance.end_turn_controller.press()
	assert_true(press_result.get("ok", false), "EndTurnController must forward to RoundSession.end_current_turn() successfully")

	assert_false(
		instance.round_session.is_round_over(),
		"passing the player's turn with no damage yet dealt must not conclude a 1v1 round"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(
		attack_events.size(), 1,
		"TurnController, driven via EndTurnController.turn_ended, must auto-drive exactly one AI-controlled enemy Strike through resolve_action_use_case (core/combat/ai.gd)"
	)
	assert_eq(attack_events[0].attacker_name, "Skeleton", "the AI-driven Strike must be attributed to the Skeleton")
	assert_eq(attack_events[0].target_name, "Titus", "the AI-driven Strike must target Titus")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the real EventLogView must observe a new entry for the AI-resolved Strike's AttackEvent"
	)

	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"the real TurnController must auto-drive the enemy's full turn so the session settles back on the living player"
	)

	# A second, player-attributed AttackEvent through the SAME pipeline,
	# confirming both attributions flow through the identical use case.
	var target_ids: Array = instance.strike_input_controller.get_selectable_target_ids()
	assert_true(target_ids.size() > 0, "StrikeInputController must be reconfigured with live targets once settled back on the player")
	var player_result: Dictionary = instance.strike_input_controller.select_target(target_ids[0])
	assert_true(player_result.get("resolved", false), "the player's own Strike must resolve through the same pipeline")

	var attack_events_after: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events_after.size(), 2, "exactly one additional AttackEvent (the player's) must now exist")
	assert_eq(
		attack_events[0].to_dict().keys(), attack_events_after[1].to_dict().keys(),
		"the AI-resolved AttackEvent must carry the identical field shape as the player's own AttackEvent -- both flow through the same resolve_action_use_case"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — the round loop continues (Strike/pass, AI auto-drive in
# between) until EncounterResultEvent fires; ResultScreen becomes visible
# showing WIN or LOSS, the full ordered event log, and final combatant
# HP/state (FEAT-010 / US-010).
# ══════════════════════════════════════════════════════════════════════════

func test_full_round_loop_concludes_with_result_screen_full_log_and_final_states() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(instance.result_screen.is_shown(), "fixture assumption: no result is shown before any input")

	_drive_to_round_over(instance)

	assert_true(
		instance.round_session.is_round_over(),
		"driving StrikeInputController/EndTurnController must eventually conclude the round"
	)

	var decided_outcome: String = instance.round_session.outcome()
	assert_true(
		decided_outcome == "won" or decided_outcome == "lost",
		"RoundSession.outcome() must be a decided terminal outcome once the round concludes; got '%s'" % decided_outcome
	)

	# ── ResultScreen displays WIN/LOSS (US-010's exit_point) ────────────────
	assert_true(instance.result_screen.is_shown(), "ResultScreen must process the EncounterResultEvent and become visible")
	var expected_text: String = "Win" if decided_outcome == "won" else "Loss"
	assert_eq(instance.result_screen.get_result_text(), expected_text, "ResultScreen must render the text matching the decided outcome")
	assert_eq(instance.result_screen.get_label_text(), expected_text, "ResultScreen's rendered label text must match the decided outcome")

	# ── Final combatant HP/state snapshot ───────────────────────────────────
	var live_combatants: Array = instance._party + instance._enemies
	assert_eq(instance.result_screen.get_snapshot_row_count(), live_combatants.size(), "ResultScreen must render one snapshot row per combatant")
	var snapshot: Array = instance.result_screen.get_final_snapshot()
	for combatant in live_combatants:
		var combatant_id: String = combatant.get("combatant_id", "")
		var entry: Dictionary = {}
		for candidate in snapshot:
			if candidate.get("combatant_id", "") == combatant_id:
				entry = candidate
				break
		assert_false(entry.is_empty(), "final snapshot must include %s" % combatant_id)
		if not entry.is_empty():
			# ResultScreen's final snapshot (scenes/battlefield/ResultScreen.gd
			# _build_final_snapshot()) reads hp_current straight off the live
			# combatant Dictionary with NO clamp -- unlike CombatantReadout's
			# maxi(...,0) display floor -- so an overkill Strike may leave it
			# negative here; compare the raw value directly.
			assert_eq(
				entry.get("hp_current", -1), combatant.get("hp_current", -2),
				"final snapshot HP for %s must match the true final domain state" % combatant_id
			)

	# ── Full, correctly ordered event log (via the real event-sink pipeline) ─
	var full_log: Array = instance.event_sink.log
	assert_true(full_log.size() > 0, "the full encounter must emit at least one event")

	var result_events: Array = full_log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "exactly one terminal EncounterResultEvent must be emitted across the full encounter")
	assert_eq(
		full_log[full_log.size() - 1], result_events[0],
		"the terminal EncounterResultEvent must be the LAST event in the ordered log"
	)
	assert_eq(result_events[0].outcome, decided_outcome, "the terminal event's outcome must match RoundSession.outcome()")

	for i in range(full_log.size() - 1):
		assert_false(
			full_log[i] is RoundEventsClass.EncounterResultEvent,
			"EncounterResultEvent may only appear as the FINAL event; found a non-terminal occurrence at index %d" % i
		)

	var attacked_names: Dictionary = {}
	for event in full_log:
		if event is RoundEventsClass.AttackEvent:
			attacked_names[event.target_name] = true
		elif event is RoundEventsClass.CombatantDefeatedEvent:
			assert_true(
				attacked_names.get(event.name, false),
				"CombatantDefeatedEvent for '%s' must be preceded by at least one prior AttackEvent targeting it" % event.name
			)

	# The event log widget and ResultScreen's own self-contained log must
	# both have observed the SAME real, ordered event-sink pipeline.
	assert_true(instance.event_log_view.get_entry_count() > 0, "EventLogView must have recorded entries across the full encounter")
	assert_true(instance.result_screen.get_event_log_entry_count() > 0, "ResultScreen's own full event log must have recorded entries")

	# ── Post-conclusion input guard (US-010) ────────────────────────────────
	assert_true(instance.strike_input_controller.is_locked(), "StrikeInputController must be locked once the encounter has concluded")
	assert_true(instance.end_turn_controller.is_locked(), "EndTurnController must be locked once the encounter has concluded")
	var post_conclusion_press: Dictionary = instance.end_turn_controller.press()
	assert_false(post_conclusion_press.get("ok", true), "EndTurnController must reject input after the encounter has concluded")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — the test passes deterministically under the pinned seed on
# repeated runs (CI gate, NFR-002/006): two independent full drives under
# seed=42 produce byte-identical ordered event sequences.
# ══════════════════════════════════════════════════════════════════════════

func test_repeated_runs_under_pinned_seed_are_byte_identical() -> void:
	var instance_1 = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame
	_drive_to_round_over(instance_1)

	var instance_2 = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame
	_drive_to_round_over(instance_2)

	assert_true(instance_1.round_session.is_round_over(), "run 1 must conclude within the drive guard")
	assert_true(instance_2.round_session.is_round_over(), "run 2 must conclude within the drive guard")
	assert_eq(
		instance_2.round_session.outcome(), instance_1.round_session.outcome(),
		"two independent runs under the same pinned seed=42 must reach the identical outcome"
	)

	var log_1: Array = instance_1.event_sink.log
	var log_2: Array = instance_2.event_sink.log
	assert_eq(log_2.size(), log_1.size(), "two independent runs under the same pinned seed must emit the same NUMBER of events")

	var count: int = mini(log_1.size(), log_2.size())
	for i in range(count):
		assert_eq(
			log_2[i].to_dict(), log_1[i].to_dict(),
			"event[%d] must be byte-identical across two independent runs under the same pinned seed (determinism gate)" % i
		)
