extends GutTest
## tests/integration/test_steel_thread_prologue_encounter.gd
##
## FEAT-113 / US-015: End-to-end steel thread validation.
##
## The FINAL integration/E2E test exercising the complete steel thread from
## entry_point to exit_point, closing out the automated/testable portions of
## US-015. Two complementary halves:
##
##   (A) Headless PRODUCTION BOOT (the real entry_point, MainScene.tscn,
##       composition root wired by MainScene.gd/US-004/US-013): asserts the
##       hex battlefield/status panel/initiative order are populated
##       correctly from the real prologue_encounter.tres data, and
##       re-confirms determinism (NFR-002/006) by booting the SAME seeded
##       encounter twice and diffing the ordered event sequence.
##
##   (B) The INTERACTIVE Presentation pipeline (StrikeActionControl /
##       TurnController / EndTurnControl / ResultScreenView, US-009 through
##       US-012): MainScene.gd's current _ready() still boots directly into
##       the pre-existing AUTONOMOUS batch loop (Encounter.run_round() in a
##       while-loop) — it does not yet wire the interactive controls that
##       already sit, unconfigured, as MainScene.tscn child nodes. Driving
##       those controls through a real player Strike + a real AI turn + a
##       real Win/Loss ResultScreenView therefore requires this test to act
##       as ITS OWN composition root for that half — exactly the same
##       pattern already established by tests/unit/core/application/
##       test_round_session_ai_turn.gd and tests/unit/presentation/
##       test_strike_action_control.gd: real, REUSED production classes
##       throughout (ResourceEncounterRepository, ResolveActionUseCase,
##       DetermineOutcomeUseCase, RunRoundUseCase/RoundSession, the REAL
##       core/combat/ai.gd, and the REAL Presentation Control scenes), with
##       only the RandomNumberPort scripted (deterministic hit/miss/damage
##       values, mirroring the existing convention in
##       test_strike_action_control.gd / test_round_session_ai_turn.gd) so
##       the narrative — Titus Strikes the Skeleton but does not kill it,
##       the Skeleton's AI turn attacks back and misses, Titus's second
##       Strike finishes the Skeleton — is fully deterministic and
##       guaranteed to exercise a genuine AI-driven enemy turn before the
##       encounter concludes.
##
## No production code is modified for this feature (ADR-002/CR-001
## guardrail; this feature's files_to_modify is test_command only) — every
## object driven in part (B) is the exact, unmodified, REUSED production
## class already covered by its own unit tests; this file's job is proving
## they compose correctly end-to-end through one real UI/event pipeline.
##
## test_criteria satisfied:
##   1. test_mainscene_boot_populates_hex_battlefield_status_panel_and_initiative()
##   2. test_player_strike_through_real_pipeline_observable_in_event_log_and_status_panel()
##   3. test_enemy_ai_turn_auto_drives_through_identical_pipeline_after_end_turn()
##   4. test_encounter_concludes_with_result_screen_matching_determine_outcome_use_case()
##   5. test_determinism_two_independent_mainscene_boots_produce_identical_event_sequence()
##   6. (whole-suite regression) — enforced by test_command, not this file.

const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## Mirrors MainScene.gd's DEFAULT_ENEMY_AC constant (EnemyResource carries no
## AC field in the v0 schema) — duplicated here per this codebase's
## established integration-test convention (fixture-building logic is
## duplicated in test files rather than reaching into MainScene.gd's
## internal helpers; see tests/integration/test_steel_thread_e2e.gd's
## _build_titus_combatant()/_skeleton_dict() for the precedent).
const DEFAULT_ENEMY_AC: int = 12

const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")
const AttributesClass                  = preload("res://core/rules/attributes.gd")
const RNGClass                         = preload("res://core/rules/rng.gd")

const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")

const HexGridViewScene         : PackedScene = preload("res://presentation/hex_grid_view.tscn")
const StatusPanelViewScene     : PackedScene = preload("res://presentation/status_panel_view.tscn")
const InitiativeViewScene      : PackedScene = preload("res://presentation/initiative_view.tscn")
const EventLogViewScene        : PackedScene = preload("res://presentation/event_log_view.tscn")
const StrikeActionControlScene : PackedScene = preload("res://presentation/strike_action_control.tscn")
const EndTurnControlScene      : PackedScene = preload("res://presentation/end_turn_control.tscn")
const ResultScreenViewScene    : PackedScene = preload("res://presentation/result_screen_view.tscn")


# ══════════════════════════════════════════════════════════════════════════
# Port test doubles (RandomNumberPort scripted for determinism; the other
# three are plain in-memory recorders — mirrors the FakeEventSinkPort /
# FakeRoundHistoryPort / FakeTurnOrderPort / ScriptedRandomNumberPort
# doubles already established by tests/unit/core/application/
# test_round_session_ai_turn.gd and tests/unit/presentation/
# test_strike_action_control.gd).
# ══════════════════════════════════════════════════════════════════════════

class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


class RecordingEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	## events — every emitted event, in emission order (used for the
	## determinism / "identical pipeline" assertions).
	var events: Array = []

	## forward_to — Presentation nodes exposing on_round_event(event); the
	## SAME production wiring pattern MainScene.gd's ConsoleEventSinkAdapter
	## uses (forwarding every event to each Presentation projection).
	var forward_to: Array = []

	func emit(event) -> void:
		events.append(event)
		for target in forward_to:
			target.on_round_event(event)


class InMemoryRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## FixedTurnOrderPort — returns the exact entries supplied at construction,
## unchanged, on every call — this test drives a fixed, known-in-advance
## turn order (Titus first) rather than re-deriving it from initiative rolls
## (initiative rolling itself is already covered by the real, unmodified
## core/combat/encounter.gd's initialize(), exercised in part (A) below).
class FixedTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


# ══════════════════════════════════════════════════════════════════════════
# Part (A) fixtures — helpers for booting the real MainScene.tscn entry point.
# ══════════════════════════════════════════════════════════════════════════

## _boot_main_scene() -> Node — instantiates the real MainScene.tscn
## composition root and lets one real process frame elapse, mirroring
## tests/smoke/test_main_scene_headless_boot.gd's already-established,
## reliable in-process boot pattern.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	var instance = packed.instantiate()
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Part (A) — Criterion 1: MainScene boots headlessly into prologue_encounter
# .tres and populates the hex battlefield/status panel/initiative order.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_boot_populates_hex_battlefield_status_panel_and_initiative() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# Steel thread exit_point: the booted encounter reaches a terminal outcome.
	assert_true(
		instance.outcome == "won" or instance.outcome == "lost",
		"MainScene must boot the prologue encounter to a terminal outcome; got '%s'" % instance.outcome
	)
	assert_true(instance.round_count >= 1, "the booted encounter must run at least 1 round")

	# Hex battlefield (US-005): one token per combatant loaded from
	# prologue_encounter.tres (Titus + Skeleton).
	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_eq(hex_grid_view.get_token_count(), 2, "the hex battlefield must render one token per prologue combatant")
	assert_not_null(hex_grid_view.get_token("player_0"), "the hex battlefield must render Titus's token (player_0)")
	assert_not_null(hex_grid_view.get_token("enemy_0"), "the hex battlefield must render the Skeleton's token (enemy_0)")

	# Status panel (US-006): populated for both combatants.
	var status_panel_view = instance.status_panel_view
	assert_not_null(status_panel_view, "MainScene must expose a non-null status_panel_view")
	assert_eq(status_panel_view.get_row_count(), 2, "the status panel must show one row per prologue combatant")
	assert_eq(status_panel_view.get_status("player_0").get("name", ""), "Titus")
	assert_eq(status_panel_view.get_status("enemy_0").get("name", ""), "Skeleton")

	# Initiative order (US-007): populated for both combatants.
	var initiative_view = instance.initiative_view
	assert_not_null(initiative_view, "MainScene must expose a non-null initiative_view")
	assert_eq(initiative_view.get_row_count(), 2, "the initiative list must show one row per prologue combatant")
	var ordered_ids: Array = initiative_view.get_ordered_combatant_ids()
	assert_true(ordered_ids.has("player_0"), "the initiative order must include Titus (player_0)")
	assert_true(ordered_ids.has("enemy_0"), "the initiative order must include the Skeleton (enemy_0)")


# ══════════════════════════════════════════════════════════════════════════
# Part (A) — Determinism regression (NFR-002/006): re-running the SAME
# seeded prologue encounter (the real entry_point, booted twice) produces an
# identical ordered event sequence.
# ══════════════════════════════════════════════════════════════════════════

func test_determinism_two_independent_mainscene_boots_produce_identical_event_sequence() -> void:
	var instance_1 = _boot_main_scene()
	await get_tree().process_frame
	var instance_2 = _boot_main_scene()
	await get_tree().process_frame

	assert_true(
		instance_1.outcome == "won" or instance_1.outcome == "lost",
		"run 1 must reach a terminal outcome before comparing determinism"
	)
	assert_eq(instance_2.outcome, instance_1.outcome, "two independent boots of the same seeded encounter must reach the identical outcome")
	assert_eq(instance_2.round_count, instance_1.round_count, "two independent boots of the same seeded encounter must take the identical number of rounds")

	var log_1: Array = instance_1.event_sink.log
	var log_2: Array = instance_2.event_sink.log

	assert_true(log_1.size() > 0, "the booted encounter must emit at least one round event")
	assert_eq(log_2.size(), log_1.size(), "two independent boots of the same seeded encounter must emit the same NUMBER of events")

	var count: int = mini(log_1.size(), log_2.size())
	for i in range(count):
		assert_eq(
			log_2[i].to_dict(), log_1[i].to_dict(),
			"event[%d] must be byte-identical across two independent boots of the same seed (NFR-002/006 determinism)" % i
		)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) fixtures — an interactive-pipeline "composition root" built from
# the real prologue_encounter.tres data and real, REUSED production classes
# (see file-level doc for why this test assembles the wiring MainScene.gd
# does not yet perform).
# ══════════════════════════════════════════════════════════════════════════

## _build_titus_combatant(hex_coord, combatant_id) -> Dictionary — builds the
## Dictionary shape resolve_action_use_case expects, from the REAL
## titus.tres / fighter.tres / longsword.tres / chain_shirt.tres resources
## (the same resources MainScene.gd's _build_party_combatant() reads),
## computing derived HP/AC via the REAL core/rules/attributes.gd.
func _build_titus_combatant(hex_coord, combatant_id: String) -> Dictionary:
	var titus       = ResourceLoader.load("res://data/characters/titus.tres")
	var class_data  = titus.class_ref
	var chain_shirt = ResourceLoader.load("res://data/armor/chain_shirt.tres")
	var longsword   = ResourceLoader.load("res://data/weapons/longsword.tres")

	var attrs := AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(titus.attributes, class_data)
	var ac: int = attrs.compute_ac(titus.attributes, chain_shirt.ac_base, chain_shirt.category)
	var stamina: int = attrs.compute_stamina(titus.attributes, class_data)

	return {
		"name":         titus.name,
		"combatant_id": combatant_id,
		"hex_coord":    hex_coord,
		"_is_enemy":    false,
		"hp_current":   hp,
		"hp_max":       hp,
		"stamina":      stamina,
		"ac":           ac,
		"strength":     titus.attributes.get("strength", 0),
		"dexterity":    titus.attributes.get("dexterity", 0),
		"intuition":    titus.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": longsword.damage_modifier_attribute,
			"proficiency_bonus":         longsword.proficiency_bonus,
			"damage_die":                longsword.damage_die,
		},
	}


## _build_skeleton_combatant(hex_coord, combatant_id) -> Dictionary — builds
## the Dictionary shape resolve_action_use_case expects, from the REAL
## skeleton.tres EnemyResource (the same resource MainScene.gd's
## _build_enemy_combatant() reads).
func _build_skeleton_combatant(hex_coord, combatant_id: String) -> Dictionary:
	var skeleton = ResourceLoader.load("res://data/enemies/skeleton.tres")

	var attribute_map: Dictionary = {"str": "strength", "dex": "dexterity"}
	var raw_attribute: String = skeleton.weapon.get("attribute", "strength")
	var weapon_attribute: String = attribute_map.get(raw_attribute, raw_attribute)

	return {
		"name":         skeleton.name,
		"combatant_id": combatant_id,
		"hex_coord":    hex_coord,
		"_is_enemy":    true,
		"hp_current":   skeleton.hp,
		"hp_max":       skeleton.hp,
		"stamina":      0,
		"ac":           DEFAULT_ENEMY_AC,
		"strength":     skeleton.str,
		"dexterity":    skeleton.dex,
		"intuition":    0,
		"weapon": {
			"damage_modifier_attribute": weapon_attribute,
			"proficiency_bonus":         skeleton.weapon.get("proficiency_bonus", 1),
			"damage_die":                skeleton.weapon.get("die", 6),
		},
	}


## _run_interactive_playthrough() -> Dictionary
##
## Assembles a real, REUSED Application-layer pipeline (ResolveActionUseCase
## / DetermineOutcomeUseCase / RunRoundUseCase / RoundSession, the real
## core/combat/ai.gd) plus the real Presentation Control scenes
## (StrikeActionControl / TurnController / EndTurnControl / ResultScreenView
## / HexGridView / StatusPanelView / InitiativeView / EventLogView) around
## Titus and the Skeleton built from the REAL prologue_encounter.tres hex
## positions and the REAL titus.tres/skeleton.tres data.
##
## Drives ONE fully deterministic narrative (scripted RandomNumberPort
## values [10, 1, 5, 10, 1]):
##   1. Titus Strikes the Skeleton (hit, 6 damage) — the Skeleton survives
##      (8 -> 2 HP) so a real AI-controlled enemy turn is guaranteed to
##      follow (test_criteria #3).
##   2. Titus ends his turn; TurnController auto-drives the Skeleton's full
##      AI-controlled turn (a Strike back at Titus) through the IDENTICAL
##      resolve_action_use_case pipeline — it misses (0 damage).
##   3. Titus Strikes the Skeleton again (hit, 6 damage) — the Skeleton is
##      defeated (2 -> -4 HP).
##   4. Titus ends his turn; DetermineOutcomeUseCase decides the encounter
##      ("won"), RoundSession ends the round, and ResultScreenView renders
##      "Win" and disables the combat input controls.
##
## Returns a Dictionary bundling every wired object plus point-in-time
## snapshots, so each test_* function below can assert on a single facet of
## the SAME deterministic playthrough without re-deriving the wiring.
func _run_interactive_playthrough() -> Dictionary:
	var repository = ResourceEncounterRepositoryClass.new()
	var hex_combatants: Array = repository.load_combatants(PROLOGUE_ENCOUNTER_PATH)
	assert_eq(hex_combatants.size(), 2, "the prologue encounter must supply exactly 2 hex-positioned combatants (Titus + Skeleton)")

	var titus_hex    = hex_combatants[0]
	var skeleton_hex = hex_combatants[1]

	var titus: Dictionary    = _build_titus_combatant(titus_hex.hex_coord, titus_hex.combatant_id)
	var skeleton: Dictionary = _build_skeleton_combatant(skeleton_hex.hex_coord, skeleton_hex.combatant_id)

	var event_sink          = RecordingEventSinkPort.new()
	var round_history_port  = InMemoryRoundHistoryPort.new()
	var random_number_port  = ScriptedRandomNumberPort.new([10, 1, 5, 10, 1])

	var resolve_action_use_case    = ResolveActionUseCaseClass.new(random_number_port, event_sink, round_history_port)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()

	var titus_action_economy    = ActionEconomyClass.new()
	var skeleton_action_economy = ActionEconomyClass.new()
	var turn_order_port = FixedTurnOrderPort.new([
		{"combatant": titus,    "action_economy": titus_action_economy},
		{"combatant": skeleton, "action_economy": skeleton_action_economy},
	])

	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	# ── Real Presentation nodes, wired exactly as a composition root would ──
	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	var status_panel_view = StatusPanelViewScene.instantiate()
	add_child_autofree(status_panel_view)
	var initiative_view = InitiativeViewScene.instantiate()
	add_child_autofree(initiative_view)
	var event_log_view = EventLogViewScene.instantiate()
	add_child_autofree(event_log_view)
	var strike_action_control = StrikeActionControlScene.instantiate()
	add_child_autofree(strike_action_control)
	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)
	var result_screen_view = ResultScreenViewScene.instantiate()
	add_child_autofree(result_screen_view)
	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)

	event_sink.forward_to = [status_panel_view, initiative_view, event_log_view, result_screen_view]

	hex_grid_view.load_combatants(hex_combatants)
	status_panel_view.load_combatants([
		{
			"combatant_id": titus["combatant_id"], "name": titus["name"],
			"hp_current": titus["hp_current"], "hp_max": titus["hp_max"],
			"stamina_current": titus["stamina"], "stamina_max": titus["stamina"],
			"action_budget_remaining": 7, "spent": false, "conditions": [],
		},
		{
			"combatant_id": skeleton["combatant_id"], "name": skeleton["name"],
			"hp_current": skeleton["hp_current"], "hp_max": skeleton["hp_max"],
			"stamina_current": 0, "stamina_max": 0,
			"action_budget_remaining": 7, "spent": false, "conditions": [],
		},
	])
	initiative_view.load_combatants([
		{"combatant_id": titus["combatant_id"], "name": titus["name"], "initiative_order": 2},
		{"combatant_id": skeleton["combatant_id"], "name": skeleton["name"], "initiative_order": 1},
	])
	result_screen_view.configure(strike_action_control, end_turn_control)

	var snapshot: Dictionary = {
		"titus": titus, "skeleton": skeleton,
		"resolve_action_use_case": resolve_action_use_case,
		"determine_outcome_use_case": determine_outcome_use_case,
		"hex_grid_view": hex_grid_view, "status_panel_view": status_panel_view,
		"initiative_view": initiative_view, "event_log_view": event_log_view,
		"strike_action_control": strike_action_control, "end_turn_control": end_turn_control,
		"result_screen_view": result_screen_view, "event_sink": event_sink,
	}

	# ── Begin round 1 ────────────────────────────────────────────────────
	var session = run_round_use_case.begin_round(1, [titus], [skeleton])
	snapshot["session"] = session
	turn_controller.set_session(session, end_turn_control, strike_action_control)

	snapshot["current_actor_before_any_action"] = session.current_actor().get("name", "")

	# ── (1) Player Strike #1 — the Skeleton survives ────────────────────
	strike_action_control.configure(
		titus, session.current_action_economy(), resolve_action_use_case, [skeleton], 1, 0
	)
	snapshot["strike1_result"] = strike_action_control.select_target(skeleton["combatant_id"])
	snapshot["skeleton_hp_after_strike1"] = skeleton.get("hp_current", 0)
	snapshot["event_log_count_after_strike1"] = event_log_view.get_entry_count()
	snapshot["event_log_text_after_strike1"] = event_log_view.get_entry_text(event_log_view.get_entry_count() - 1)
	snapshot["status_panel_skeleton_hp_after_strike1"] = status_panel_view.get_status(skeleton["combatant_id"]).get("hp_current", -1)

	# ── (2) End Titus's turn — TurnController auto-drives the Skeleton's
	# full AI-controlled turn through the SAME resolve_action_use_case
	# pipeline (US-011), then settles back on Titus. ─────────────────────
	snapshot["end_turn_1_result"] = turn_controller.on_end_turn_pressed()
	snapshot["event_log_count_after_ai_turn"] = event_log_view.get_entry_count()
	snapshot["event_log_text_after_ai_turn"] = event_log_view.get_entry_text(event_log_view.get_entry_count() - 1)
	snapshot["status_panel_titus_hp_after_ai_turn"] = status_panel_view.get_status(titus["combatant_id"]).get("hp_current", -1)
	snapshot["current_actor_after_ai_turn"] = session.current_actor().get("name", "")
	snapshot["round_over_after_ai_turn"] = session.is_round_over()
	snapshot["strike_action_control_buttons_after_ai_turn"] = strike_action_control.get_button_count()

	# ── (3) Composition-root responsibility (mirrors turn_controller.gd's
	# documented division of labor): re-enable StrikeActionControl for the
	# new active player turn, then Titus Strikes again — finishing the
	# Skeleton. ────────────────────────────────────────────────────────────
	strike_action_control.configure(
		titus, session.current_action_economy(), resolve_action_use_case, [skeleton], 1, 1
	)
	snapshot["strike2_result"] = strike_action_control.select_target(skeleton["combatant_id"])
	snapshot["skeleton_hp_after_strike2"] = skeleton.get("hp_current", 0)

	# ── (4) End Titus's second turn — DetermineOutcomeUseCase decides the
	# encounter and RoundSession emits EncounterResultEvent. ─────────────
	snapshot["end_turn_2_result"] = turn_controller.on_end_turn_pressed()
	snapshot["final_outcome_via_classify"] = determine_outcome_use_case.classify([titus], [skeleton])

	return snapshot


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 2: StrikeActionControl performs a melee Strike on an
# in-reach enemy through the real UI/event pipeline; the resulting
# AttackEvent appears in EventLogView and StatusPanelView.
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_through_real_pipeline_observable_in_event_log_and_status_panel() -> void:
	var s: Dictionary = _run_interactive_playthrough()

	assert_eq(s["current_actor_before_any_action"], "Titus", "Titus (adjacent to the Skeleton per prologue_encounter.tres hex positions) must act first")

	assert_true(s["strike1_result"].get("ok", false), "the player's melee Strike on the in-reach Skeleton must resolve successfully")
	assert_true(s["strike1_result"].get("resolved", false), "the player's Strike must be marked resolved by resolve_action_use_case")

	assert_eq(s["event_log_count_after_strike1"], 1, "EventLogView must observe exactly one entry for the player's resolved Strike's AttackEvent")
	assert_string_contains(s["event_log_text_after_strike1"], "Titus")
	assert_string_contains(s["event_log_text_after_strike1"], "Skeleton")

	assert_eq(
		s["status_panel_skeleton_hp_after_strike1"], s["skeleton_hp_after_strike1"],
		"StatusPanelView must reflect the domain Skeleton's post-Strike HP via the same event pipeline"
	)
	assert_true(
		s["skeleton_hp_after_strike1"] < s["skeleton"]["hp_max"],
		"the player's Strike must have damaged the Skeleton"
	)
	assert_true(
		s["skeleton_hp_after_strike1"] > 0,
		"the Skeleton must survive the player's first Strike so a genuine AI-controlled enemy turn follows"
	)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 3: driving a full AI-controlled enemy turn through the
# IDENTICAL pipeline the player's own Strike used.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_ai_turn_auto_drives_through_identical_pipeline_after_end_turn() -> void:
	var s: Dictionary = _run_interactive_playthrough()

	assert_true(s["end_turn_1_result"].get("ok", false), "ending the player's turn must succeed")
	assert_false(s["round_over_after_ai_turn"], "the round must not be over after only the Skeleton's non-lethal AI turn")

	# One additional EventLogView entry (the Skeleton's AI-resolved Strike),
	# rendered via the SAME EventSinkPort broadcast the player's own Strike
	# used above — proving there is no parallel/duplicate event path.
	assert_eq(
		s["event_log_count_after_ai_turn"], 2,
		"EventLogView must observe exactly one additional entry for the AI-resolved Strike's AttackEvent"
	)
	assert_string_contains(s["event_log_text_after_ai_turn"], "Skeleton")
	assert_string_contains(s["event_log_text_after_ai_turn"], "Titus")

	assert_eq(
		s["status_panel_titus_hp_after_ai_turn"], s["titus"]["hp_max"],
		"the Skeleton's scripted AI Strike misses — Titus's displayed HP must remain unchanged"
	)

	# TurnController settles back on the player, ready for the next turn.
	assert_eq(s["current_actor_after_ai_turn"], "Titus", "the turn cursor must return to Titus once the AI turn resolves")
	assert_eq(
		s["strike_action_control_buttons_after_ai_turn"], 0,
		"StrikeActionControl must remain disabled after the AI-drive settles (US-011) until the composition root reconfigures it for the new turn"
	)


# ══════════════════════════════════════════════════════════════════════════
# Part (B) — Criterion 4: running the encounter to conclusion; ResultScreenView
# shows Win/Loss matching determine_outcome_use_case, with
# StrikeActionControl/EndTurnControl disabled afterward.
# ══════════════════════════════════════════════════════════════════════════

func test_encounter_concludes_with_result_screen_matching_determine_outcome_use_case() -> void:
	var s: Dictionary = _run_interactive_playthrough()

	assert_true(s["strike2_result"].get("ok", false), "the player's second Strike must resolve successfully")
	assert_true(s["strike2_result"].get("target_defeated", false), "the player's second Strike must defeat the Skeleton")
	assert_true(s["skeleton_hp_after_strike2"] <= 0, "the Skeleton's HP must be <= 0 after the finishing Strike")

	assert_eq(s["final_outcome_via_classify"], "won", "determine_outcome_use_case.classify() must report 'won' once the Skeleton side is fully defeated")

	var session = s["session"]
	assert_true(session.is_round_over(), "the round must be over once the encounter's outcome is decided")
	assert_eq(session.outcome(), "won", "RoundSession.outcome() must match determine_outcome_use_case's classification")

	var result_screen_view = s["result_screen_view"]
	assert_true(result_screen_view.is_shown(), "ResultScreenView must have processed the EncounterResultEvent")
	assert_eq(result_screen_view.get_result_text(), "Win", "ResultScreenView must render 'Win' for a 'won' outcome")
	assert_eq(result_screen_view.get_label_text(), "Win", "ResultScreenView's rendered label text must show 'Win'")

	var strike_action_control = s["strike_action_control"]
	var end_turn_control = s["end_turn_control"]
	assert_eq(strike_action_control.get_button_count(), 0, "StrikeActionControl must be disabled (no selectable targets) once the encounter has concluded")
	assert_false(end_turn_control.is_enabled(), "EndTurnControl must be disabled once the encounter has concluded")

	# Selecting a target after conclusion must be a defensive no-op — no
	# further use-case call can reach the concluded encounter.
	var post_conclusion_result: Dictionary = strike_action_control.select_target(s["skeleton"]["combatant_id"])
	assert_false(post_conclusion_result.get("ok", true), "StrikeActionControl must reject input after the encounter has concluded")
	assert_false(end_turn_control.press().get("ok", true), "EndTurnControl must reject input after the encounter has concluded")
