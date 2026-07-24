## presentation/exploration_mode_controller.gd — ExplorationModeController
## (FEAT-009 / US-008 / FR-005).
##
## Presentation layer (Clean Architecture): the extracted, independently-
## testable controller for exploration-mode BOOT, hex-click handling, and
## scenario-encounter loading -- moved out of MainScene.gd's own former
## `_boot_exploration_mode()` / `load_encounter_from_scenario()` bodies
## (FEAT-006/FEAT-010). Owns the two Application-layer collaborators those
## methods used to construct inline:
##
##   scenario_session       — a fresh core/application/scenario_session.gd
##                             ScenarioSession, seeded from the injected
##                             scenario_path + boot()'s hex_combatants.
##   exploration_controller — a fresh core/application/exploration_controller.gd
##                             ExplorationController wrapping scenario_session.
##
## MainScene.gd remains the composition root: it owns `_game_mode`/
## `_active_encounter_id` (pure composition-root state, never duplicated
## here) and its own PINNED `_on_combat_triggered()` / `_on_exploration_hex_
## clicked()` / `_on_combat_won()` handler bodies (unchanged by this
## feature -- see MainScene.gd's own doc for why rewriting the multi-step
## combat handoff/round-wiring those methods drive is explicitly out of this
## feature's scope, mirroring presentation/round_flow_controller.gd's own
## "wrap, don't replace the pinned method" precedent). What MOVES here is:
##
##   1. BOOT: constructing scenario_session/exploration_controller and wiring
##      hex_grid_view.hex_clicked / exploration_controller.combat_triggered
##      to caller-supplied Callables (setup(deps)'s "on_hex_clicked"/
##      "on_combat_triggered" targets -- typically
##      Callable(main_scene, "_on_exploration_hex_clicked") /
##      Callable(main_scene, "_on_combat_triggered"), so the REAL, booted
##      res://MainScene.tscn's own signal-connection assertions
##      (tests/boot/test_boot_exploration_mode.gd et al.) keep observing
##      those exact connections, just wired from here instead of inline).
##   2. SCENARIO-ENCOUNTER LOADING: load_encounter_from_scenario(scenario,
##      encounter_id, seed) -- the LoadScenarioEncounterUseCase-driven use
##      case call + CombatantClass.from_dict() lift + EncounterClass.new()/
##      initialize() call, moved here verbatim (ADR-006, no duplicated
##      algorithm). On success this method ALSO emits this controller's own
##      `combat_triggered(encounter_id)` signal (design notes' api_contracts
##      #2: "load_encounter_from_scenario returns true and later emits
##      combat_triggered(encounter_id)") -- a signal independent of (and not
##      wired to) `exploration_controller.combat_triggered` above, available
##      for a future composition step; MainScene.gd's OWN
##      load_encounter_from_scenario() wrapper only reads the boolean return
##      value + this controller's `party`/`enemies`/`encounter` fields today.
##
## `combat_won_return_to_exploration()` is likewise declared here (this
## feature's own signal-surface requirement) and emitted by
## `resume_after_combat_won(encounter_id)` -- the exploration-side half of
## the post-combat handoff (mark the encounter complete in scenario_session,
## reconnect hex_click) -- available for a later feature to wire
## MainScene.gd's `_on_combat_won()` through; this feature does not itself
## rewire that pinned method (see file-level doc above).
##
## Idempotency (this feature's own test_criterion): boot(hex_combatants) is
## safe to call a second time -- a `_booted` guard makes every call after
## the first a no-op, so scenario_session/exploration_controller are never
## reconstructed (which would reset party_hex_positions) and hex_clicked/
## combat_triggered are never double-connected.

class_name ExplorationModeController
extends RefCounted

const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const RNGClass = preload("res://core/rules/rng.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")

## Emitted by load_encounter_from_scenario() on success, carrying the
## encounter_id that was just loaded.
signal combat_triggered(encounter_id: String)

## Emitted by resume_after_combat_won() once the exploration-side half of
## the post-combat handoff (mark-complete + hex_click reconnect) is done.
signal combat_won_return_to_exploration()

## scenario_session — the ScenarioSession this controller constructs at
## boot(). Null until boot() has run.
var scenario_session = null

## exploration_controller — the ExplorationController this controller
## constructs at boot(), wrapping scenario_session. Null until boot() has
## run. Settable (not just gettable) so a caller (MainScene.gd's own
## `exploration_controller` proxy, or a GUT test) may substitute a spy/fake
## after boot() -- mirrors this codebase's established "assign over a real
## collaborator with a hand-written spy" test convention.
var exploration_controller = null

## party / enemies / encounter — the live Combatant roster + initialized
## Encounter assembled by the most recent successful load_encounter_from_
## scenario() call. Empty/null until a successful call.
var party: Array = []
var enemies: Array = []
var encounter = null

var _hex_grid_view = null
var _scenario_path: String = ""
var _on_hex_clicked_target: Callable = Callable()
var _on_combat_triggered_target: Callable = Callable()
var _booted: bool = false


## setup(deps) -> void — injects this controller's collaborators. Recognized
## keys (all optional, each defaulting to a harmless no-op value so a
## partially-configured setup() never crashes boot()):
##   "hex_grid_view"        — the HexGridView node whose hex_clicked signal
##                             boot() wires to "on_hex_clicked".
##   "scenario_path"        — String res:// path to the ScenarioResource
##                             boot() loads.
##   "on_hex_clicked"       — Callable invoked (via hex_grid_view.hex_clicked)
##                             on every exploration-mode hex click.
##   "on_combat_triggered"  — Callable invoked (via exploration_controller.
##                             combat_triggered) the instant a proximity
##                             trigger fires.
func setup(deps: Dictionary) -> void:
	_hex_grid_view = deps.get("hex_grid_view", null)
	_scenario_path = deps.get("scenario_path", "")
	_on_hex_clicked_target = deps.get("on_hex_clicked", Callable())
	_on_combat_triggered_target = deps.get("on_combat_triggered", Callable())


## boot(hex_combatants) -> void — constructs scenario_session/
## exploration_controller from `_scenario_path` (setup()), seeds
## scenario_session.party_hex_positions from `hex_combatants` (already
## loaded/rendered by the caller, mirrors the pre-extraction
## `_boot_exploration_mode()` contract verbatim), and wires the two
## injected Callables. IDEMPOTENT-SAFE: every call after the first is a
## silent no-op (this feature's own test_criterion) -- so re-entrant/
## repeated boot() calls can never reset an in-progress exploration session
## or double-connect a signal.
##
## A missing/malformed scenario resource push_error()s and leaves
## scenario_session.scenario null rather than aborting -- EXPLORATION mode
## still exists in a degenerate (no scenario) state instead of crashing
## (unchanged from the pre-extraction contract).
func boot(hex_combatants: Array) -> void:
	if _booted:
		return
	_booted = true

	scenario_session = ScenarioSessionClass.new()

	if _scenario_path == "":
		push_error("ExplorationModeController.boot(): no scenario_path configured (setup() not called?)")
	else:
		var scenario_resource = ResourceLoader.load(_scenario_path)
		if scenario_resource == null:
			push_error("ExplorationModeController.boot(): failed to load " + _scenario_path)
		else:
			scenario_session.scenario = scenario_resource
			var party_count: int = 0
			if scenario_resource.party != null:
				party_count = scenario_resource.party.character_resource_paths.size()
			for i in range(min(party_count, hex_combatants.size())):
				var party_hex_combatant = hex_combatants[i]
				scenario_session.party_hex_positions[party_hex_combatant.combatant_id] = party_hex_combatant.hex_coord

	exploration_controller = ExplorationControllerClass.new(scenario_session)

	if _on_combat_triggered_target.is_valid():
		if not exploration_controller.combat_triggered.is_connected(_on_combat_triggered_target):
			exploration_controller.combat_triggered.connect(_on_combat_triggered_target)

	if _hex_grid_view != null and _on_hex_clicked_target.is_valid():
		if not _hex_grid_view.hex_clicked.is_connected(_on_hex_clicked_target):
			_hex_grid_view.hex_clicked.connect(_on_hex_clicked_target)


## load_encounter_from_scenario(scenario, encounter_id, seed) -> bool —
## moved verbatim (ADR-006, no duplicated algorithm) from the pre-extraction
## MainScene.load_encounter_from_scenario(). Drives
## LoadScenarioEncounterUseCase.execute(scenario, encounter_id); on failure
## (ok=false) push_error()s and returns false WITHOUT mutating `party`/
## `enemies`/`encounter` at all. On success, lifts the use case's
## party_combatants/enemy_combatants Dictionaries onto live Combatant
## instances, assigns them to `party`/`enemies`, constructs + initialize()s
## a fresh EncounterClass around them seeded with `seed` (RNGClass.new(seed)),
## emits combat_triggered(encounter_id), and returns true.
func load_encounter_from_scenario(scenario, encounter_id: String, seed: int = -1) -> bool:
	var use_case := LoadScenarioEncounterUseCaseClass.new()
	var result: Dictionary = use_case.execute(scenario, encounter_id)

	if not result.get("ok", false):
		push_error(
			"ExplorationModeController.load_encounter_from_scenario: failed to load encounter_id '%s' (%s)"
			% [encounter_id, result.get("error_code", "UNKNOWN_ERROR")]
		)
		return false

	var new_party: Array = []
	for party_combatant_dict in result.get("party_combatants", []):
		new_party.append(CombatantClass.from_dict(party_combatant_dict))

	var new_enemies: Array = []
	for enemy_combatant_dict in result.get("enemy_combatants", []):
		new_enemies.append(CombatantClass.from_dict(enemy_combatant_dict))

	party = new_party
	enemies = new_enemies

	var rng := RNGClass.new(seed)
	encounter = EncounterClass.new(party, enemies, rng)
	encounter.initialize()

	combat_triggered.emit(encounter_id)
	return true


## resume_after_combat_won(encounter_id) -> void — the exploration-side half
## of the post-combat return-to-exploration handoff: marks `encounter_id`
## complete in scenario_session (idempotent/defensive against a dangling id,
## mirrors ScenarioSession.mark_encounter_complete()'s own contract) and
## reconnects hex_grid_view.hex_clicked -> the injected on_hex_clicked
## Callable (guarded against a double-connect), then emits
## combat_won_return_to_exploration(). Safe to call with an unset/empty
## encounter_id (a no-op mark-complete step) or before boot() has run (a
## no-op reconnect step, since `_hex_grid_view`/`_on_hex_clicked_target`
## default to null/invalid).
func resume_after_combat_won(encounter_id: String) -> void:
	if scenario_session != null and encounter_id != "":
		scenario_session.mark_encounter_complete(encounter_id)

	if _hex_grid_view != null and _on_hex_clicked_target.is_valid():
		if not _hex_grid_view.hex_clicked.is_connected(_on_hex_clicked_target):
			_hex_grid_view.hex_clicked.connect(_on_hex_clicked_target)

	combat_won_return_to_exploration.emit()
