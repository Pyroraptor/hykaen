extends GutTest
## tests/gut/test_exploration_mode_controller.gd — FEAT-009 (US-008 / FR-005).
##
## GUT suite for presentation/exploration_mode_controller.gd's
## ExplorationModeController — the extracted controller now owning
## exploration-mode BOOT (constructing scenario_session/exploration_controller
## and wiring hex_grid_view.hex_clicked/exploration_controller.combat_triggered
## to caller-supplied Callables) and scenario-encounter loading
## (load_encounter_from_scenario(), moved verbatim from MainScene.gd's own
## former inline body).
##
## Drives the controller purely through its own public setup(deps)/
## boot(hex_combatants)/load_encounter_from_scenario(scenario, encounter_id,
## seed)/resume_after_combat_won(encounter_id) surface against fakes (this
## codebase's established "small real fake, not a Mock-everything spy"
## convention, mirrors tests/gut/test_round_flow_controller.gd/
## test_spell_picker_panel_controller.gd) plus the REAL
## data/scenarios/prologue_scenario.tres fixture for the loading tests
## (mirrors tests/unit/presentation/test_main_scene_load_encounter_from_
## scenario.gd's identical real-fixture convention) — no MainScene.tscn boot
## is required for this suite.
##
## test_criteria covered:
##   1. boot(hex_combatants) populates exploration UI state and is
##      idempotent-safe when called a second time.
##   2. load_encounter_from_scenario(scenario, encounter_id) returns false
##      for an unknown encounter_id (no crash); returns true and later
##      emits combat_triggered(encounter_id) for a valid one.
##   3. MainScene.load_encounter_from_scenario() delegates to
##      _exploration.load_encounter_from_scenario() only (no duplicated
##      logic) — a static source-scan complement.
##   4. (full-suite regression is verified by running the whole GUT suite,
##      not scoped to this file).

const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const MAIN_SCENE_SCRIPT_PATH: String = "res://MainScene.gd"
const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"
const PROLOGUE_ENCOUNTER_ID: String = "prologue"
const PROLOGUE_SEED: int = 42


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## _FakeHexGridView — a hand-written fake exposing only the `hex_clicked`
## signal boot() connects to (this codebase's established "small real fake"
## convention) — no real HexGridView node/rendering required.
class _FakeHexGridView:
	extends RefCounted
	signal hex_clicked(hex_coord)


## _FakeHexCombatant — a minimal duck-typed stand-in for the
## `hex_combatants` entries boot() reads (`combatant_id`/`hex_coord`), so
## this suite never needs to boot a real CombatSessionFactory pipeline just
## to exercise boot()'s own party_hex_positions-seeding logic.
class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord


## _SignalTargetTracker — records every invocation of the two Callables
## boot() wires (on_hex_clicked/on_combat_triggered), mirroring
## test_spell_picker_panel_controller.gd's own `_OnSelectedTracker`
## "small real fake, not a Mock-everything spy" philosophy.
class _SignalTargetTracker:
	extends RefCounted
	var hex_clicked_calls: Array = []
	var combat_triggered_calls: Array = []

	func on_hex_clicked(hex_coord) -> void:
		hex_clicked_calls.append(hex_coord)

	func on_combat_triggered(encounter_id: String) -> void:
		combat_triggered_calls.append(encounter_id)


func _make_controller(hex_grid_view, tracker) -> ExplorationModeControllerClass:
	var controller := ExplorationModeControllerClass.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": PROLOGUE_SCENARIO_PATH,
		"on_hex_clicked": Callable(tracker, "on_hex_clicked"),
		"on_combat_triggered": Callable(tracker, "on_combat_triggered"),
	})
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a — boot(hex_combatants) populates exploration UI state.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_constructs_a_real_scenario_session_seeded_from_hex_combatants() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var tracker := _SignalTargetTracker.new()
	var controller := _make_controller(hex_grid_view, tracker)

	var hex_combatants: Array = [
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(3, -1)),
		_FakeHexCombatant.new("hero_b", HexCoordClass.new(2, -1)),
	]
	controller.boot(hex_combatants)

	assert_not_null(controller.scenario_session, "boot() must construct a real scenario_session")
	assert_true(controller.scenario_session is ScenarioSessionClass, "scenario_session must be a real ScenarioSession instance")
	assert_not_null(controller.scenario_session.scenario, "scenario_session.scenario must be populated from the injected scenario_path")
	assert_eq(controller.scenario_session.scenario.scenario_id, "prologue", "the loaded scenario must be the authored prologue scenario")

	var hero_a_hex = controller.scenario_session.party_hex_positions.get("hero_a")
	assert_not_null(hero_a_hex, "party_hex_positions must be seeded for every hex_combatants entry within the scenario's party count")
	assert_eq(hero_a_hex.q, 3, "party_hex_positions must be seeded from the hex_combatants entry's own hex_coord")
	assert_eq(hero_a_hex.r, -1, "party_hex_positions must be seeded from the hex_combatants entry's own hex_coord")


func test_boot_constructs_a_real_exploration_controller_and_wires_both_callables() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var tracker := _SignalTargetTracker.new()
	var controller := _make_controller(hex_grid_view, tracker)

	controller.boot([])

	assert_not_null(controller.exploration_controller, "boot() must construct a real exploration_controller")
	assert_true(controller.exploration_controller is ExplorationControllerClass, "exploration_controller must be a real ExplorationController instance")
	assert_true(
		controller.exploration_controller.combat_triggered.is_connected(Callable(tracker, "on_combat_triggered")),
		"exploration_controller.combat_triggered must be connected to the injected on_combat_triggered Callable"
	)
	assert_true(
		hex_grid_view.hex_clicked.is_connected(Callable(tracker, "on_hex_clicked")),
		"hex_grid_view.hex_clicked must be connected to the injected on_hex_clicked Callable"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b — boot() is idempotent-safe when called a second time.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_called_a_second_time_is_a_safe_no_op() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var tracker := _SignalTargetTracker.new()
	var controller := _make_controller(hex_grid_view, tracker)

	controller.boot([_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0))])
	var scenario_session_after_first_boot = controller.scenario_session
	var exploration_controller_after_first_boot = controller.exploration_controller

	# A second boot() call, even with different hex_combatants, must not
	# crash, must not reconstruct scenario_session/exploration_controller
	# (which would silently reset party_hex_positions), and must not
	# double-connect either wired signal.
	controller.boot([_FakeHexCombatant.new("hero_z", HexCoordClass.new(9, 9))])

	assert_same(
		controller.scenario_session, scenario_session_after_first_boot,
		"a second boot() call must not reconstruct scenario_session (idempotent-safe)"
	)
	assert_same(
		controller.exploration_controller, exploration_controller_after_first_boot,
		"a second boot() call must not reconstruct exploration_controller (idempotent-safe)"
	)
	assert_false(
		controller.scenario_session.party_hex_positions.has("hero_z"),
		"a second boot() call must not re-seed party_hex_positions from the new hex_combatants argument"
	)

	var hex_clicked_connections: int = 0
	for connection in hex_grid_view.get_signal_connection_list("hex_clicked"):
		var callable: Callable = connection["callable"]
		if callable.get_object() == tracker and callable.get_method() == "on_hex_clicked":
			hex_clicked_connections += 1
	assert_eq(hex_clicked_connections, 1, "a second boot() call must not double-connect hex_clicked")

	var combat_triggered_connections: int = 0
	for connection in controller.exploration_controller.get_signal_connection_list("combat_triggered"):
		var callable: Callable = connection["callable"]
		if callable.get_object() == tracker and callable.get_method() == "on_combat_triggered":
			combat_triggered_connections += 1
	assert_eq(combat_triggered_connections, 1, "a second boot() call must not double-connect combat_triggered")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — load_encounter_from_scenario(): false for an unknown
# encounter_id (no crash); true + later combat_triggered(encounter_id) for
# a valid one.
# ══════════════════════════════════════════════════════════════════════════

func test_load_encounter_from_scenario_unknown_encounter_id_returns_false_without_crash_or_mutation() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load")

	var controller := ExplorationModeControllerClass.new()
	watch_signals(controller)

	var ok: bool = controller.load_encounter_from_scenario(scenario, "no-such-encounter-id", PROLOGUE_SEED)

	# no crash -- reaching this line is part of the assertion.
	assert_false(ok, "load_encounter_from_scenario() must return false for an unknown encounter_id")
	assert_eq(controller.party, [], "an unknown encounter_id must leave `party` unmutated (still the empty default)")
	assert_eq(controller.enemies, [], "an unknown encounter_id must leave `enemies` unmutated (still the empty default)")
	assert_null(controller.encounter, "an unknown encounter_id must leave `encounter` unmutated (still null)")
	assert_signal_not_emitted(controller, "combat_triggered", "an unknown encounter_id must never emit combat_triggered")


func test_load_encounter_from_scenario_valid_encounter_id_returns_true_and_emits_combat_triggered() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load")

	var controller := ExplorationModeControllerClass.new()
	watch_signals(controller)

	var ok: bool = controller.load_encounter_from_scenario(scenario, PROLOGUE_ENCOUNTER_ID, PROLOGUE_SEED)

	assert_true(ok, "load_encounter_from_scenario() must return true for the real prologue_scenario.tres fixture")

	assert_eq(controller.party.size(), 2, "party must contain exactly 2 live combatants (Titus + Marigold)")
	for combatant in controller.party:
		assert_is(combatant, CombatantClass, "every party entry must be a live Combatant instance")

	assert_eq(controller.enemies.size(), 1, "enemies must contain exactly 1 live combatant (Skeleton)")
	if controller.enemies.size() == 1:
		assert_is(controller.enemies[0], CombatantClass, "the enemies entry must be a live Combatant instance")

	assert_is(controller.encounter, EncounterClass, "encounter must be a real, initialize()d EncounterClass instance")

	assert_signal_emit_count(controller, "combat_triggered", 1, "a successful load must emit combat_triggered exactly once")
	assert_signal_emitted_with_parameters(
		controller, "combat_triggered", [PROLOGUE_ENCOUNTER_ID],
		"combat_triggered must carry the encounter_id that was just loaded"
	)


# ══════════════════════════════════════════════════════════════════════════
# resume_after_combat_won() — marks the encounter complete, reconnects
# hex_click, and emits combat_won_return_to_exploration().
# ══════════════════════════════════════════════════════════════════════════

func test_resume_after_combat_won_marks_encounter_complete_reconnects_hex_click_and_emits_signal() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var tracker := _SignalTargetTracker.new()
	var controller := _make_controller(hex_grid_view, tracker)
	controller.boot([])
	watch_signals(controller)

	# Mirror _on_combat_triggered()'s own disconnect-before-handoff step, so
	# resume_after_combat_won()'s reconnect is a meaningful assertion (not
	# merely "was already connected").
	hex_grid_view.hex_clicked.disconnect(Callable(tracker, "on_hex_clicked"))
	assert_false(hex_grid_view.hex_clicked.is_connected(Callable(tracker, "on_hex_clicked")), "fixture assumption: hex_clicked must be disconnected before resume")

	controller.resume_after_combat_won(PROLOGUE_ENCOUNTER_ID)

	assert_true(
		controller.scenario_session.completed_encounter_ids.has(PROLOGUE_ENCOUNTER_ID),
		"resume_after_combat_won() must mark encounter_id complete in scenario_session"
	)
	assert_true(
		hex_grid_view.hex_clicked.is_connected(Callable(tracker, "on_hex_clicked")),
		"resume_after_combat_won() must reconnect hex_clicked -> the injected on_hex_clicked Callable"
	)
	assert_signal_emit_count(controller, "combat_won_return_to_exploration", 1, "resume_after_combat_won() must emit combat_won_return_to_exploration exactly once")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — MainScene.load_encounter_from_scenario() delegates to
# _exploration.load_encounter_from_scenario() only (static source scan).
# ══════════════════════════════════════════════════════════════════════════

func _extract_function_body(content: String, func_signature_prefix: String) -> String:
	var func_start: int = content.find(func_signature_prefix)
	assert_true(func_start >= 0, "MainScene.gd must declare a function starting with '%s'" % func_signature_prefix)
	var next_func_start: int = content.find("\nfunc ", func_start + 1)
	assert_true(next_func_start > func_start, "must be able to locate the end of the function body")
	return content.substr(func_start, next_func_start - func_start)


func test_main_scene_load_encounter_from_scenario_delegates_to_exploration_controller_only() -> void:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var body: String = _extract_function_body(content, "func load_encounter_from_scenario(")

	assert_true(
		body.contains("_exploration.load_encounter_from_scenario("),
		"MainScene.load_encounter_from_scenario() must delegate to _exploration.load_encounter_from_scenario()"
	)

	# No duplicated logic: none of the use-case-invocation/Combatant-lifting/
	# Encounter-construction algorithm _exploration.load_encounter_from_
	# scenario() now owns may be re-implemented inline here.
	assert_false(body.contains("LoadScenarioEncounterUseCase"), "MainScene must not directly invoke LoadScenarioEncounterUseCase itself (duplicated logic)")
	assert_false(body.contains("CombatantClass.from_dict"), "MainScene must not directly lift Combatant dicts itself (duplicated logic)")
	assert_false(body.contains("RNGClass.new("), "MainScene must not directly construct an RNG itself inside this method (duplicated logic)")
	assert_false(body.contains("EncounterClass.new("), "MainScene must not directly construct an Encounter itself inside this method (duplicated logic)")


func test_main_scene_boot_exploration_mode_delegates_construction_to_exploration_controller() -> void:
	var file := FileAccess.open(MAIN_SCENE_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var body: String = _extract_function_body(content, "func _boot_exploration_mode(")

	assert_true(body.contains("_exploration.setup("), "_boot_exploration_mode() must configure _exploration via setup()")
	assert_true(body.contains("_exploration.boot("), "_boot_exploration_mode() must delegate construction to _exploration.boot()")
	assert_false(body.contains("ScenarioSessionClass.new("), "MainScene must not directly construct a ScenarioSession itself (duplicated logic)")
	assert_false(body.contains("ExplorationControllerClass.new("), "MainScene must not directly construct an ExplorationController itself (duplicated logic)")
