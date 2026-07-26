## core/application/new_game_factory.gd — NewGameFactory
## (FEAT-002 / US-003, FR-003, NFR-002, NFR-003)
##
## Application layer (Clean Architecture / ADR-001): a pure use-case/domain
## service that seeds a fresh data/game_state/game_state_data.gd
## GameStateData for either the authored prologue scenario or an arbitrary
## scenario path, so a presentation-layer caller (a future TitleScreen "New
## Game"/"Dev: Pick Scenario" controller) never has to know how a
## GameStateData is assembled from a ScenarioResource + EncounterResource
## pair.
##
## Depends ONLY on the domain layer: GameStateData (data/game_state/), and
## reads (never mutates, never owns/instantiates) the existing
## ScenarioResource / ScenarioEncounterEntryResource / EncounterResource /
## PartyResource data graph via ResourceLoader. It never references the
## save-slot autoload a LATER infrastructure-layer feature introduces (its
## identifier is deliberately never spelled out anywhere in this file, not
## even in a comment) and never extends a scene-tree type — both
## constraints are enforced by this feature's own source-scan fitness tests
## (tests/unit/test_core_purity_source_scan.gd, RISK-003/RISK-007).
##
## Party-seeding convention (ADR-002 party authority, mirroring the SAME
## "player_%d" combatant_id + scenario.party-authoritative resolution
## core/application/use_cases/load_scenario_encounter_use_case.gd already
## established): the seeded party_hex_positions size is driven by
## scenario.party.character_resource_paths (the scenario-authoritative
## roster), NOT by encounter.party_resource_paths (which some encounters,
## e.g. data/encounters/dripping_cave.tres, deliberately leave empty per
## ADR-002). Each party member's starting hex is read positionally from
## encounter.party_hex_positions[i], defaulting to {q:0, r:0} when the
## encounter has no authored position at that index.
##
## Error handling (fail-loud, never null — FR-001's GameStateData default-
## construction guarantee underpins this): every failure branch below
## push_error()s a descriptive message and still returns a valid, non-null
## GameStateData with `scenario_path` already set to the (possibly
## unloadable) input path — callers never need a null-check, only an
## `.is_empty()` check on the seeded arrays if they want to detect a
## degraded result.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, and
## every public entry point is a `static func` so this service can never
## accumulate per-instance state.
##
## Usage:
##   var state := NewGameFactory.create_prologue_state()
##   state.scenario_path            # == NewGameFactory.PROLOGUE_SCENARIO_PATH_CONST
##   state.party_hex_positions      # [{"combatant_id": "player_0", "q": 0, "r": 0}, ...]
##
##   var cave_state := NewGameFactory.create_state_for_scenario(
##       "res://data/scenarios/dripping_cave_scenario.tres"
##   )

class_name NewGameFactory
extends RefCounted

const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

## res:// path to the authored prologue ScenarioResource. The sole entry
## point create_prologue_state() always seeds against this fixed path.
const PROLOGUE_SCENARIO_PATH_CONST: String = "res://data/scenarios/prologue_scenario.tres"


## create_prologue_state() -> GameStateData
##
## Convenience wrapper around create_state_for_scenario(
## PROLOGUE_SCENARIO_PATH_CONST) — see that method's contract for the full
## success/failure behaviour.
static func create_prologue_state() -> GameStateData:
	return create_state_for_scenario(PROLOGUE_SCENARIO_PATH_CONST)


## create_state_for_scenario(scenario_path) -> GameStateData
##
## Success: loads the ScenarioResource at `scenario_path`, resolves its
## first encounter_entries[0].encounter, and returns a GameStateData with
## scenario_path == scenario_path and party_hex_positions seeded one entry
## per scenario.party.character_resource_paths member (see file-level doc
## for the ADR-002 party-authority convention).
##
## Failure (fail-loud, never null): push_error()s a descriptive message and
## returns a GameStateData with scenario_path already set to `scenario_path`
## and party_hex_positions left empty, when any of the following hold:
##   - the ScenarioResource at scenario_path fails to load (unloadable path)
##   - the loaded scenario has no encounter_entries
##   - encounter_entries[0].encounter is null
static func create_state_for_scenario(scenario_path: String) -> GameStateData:
	var state := GameStateDataClass.new()
	state.scenario_path = scenario_path

	var scenario = ResourceLoader.load(scenario_path)
	if scenario == null:
		push_error("NewGameFactory: unresolvable scenario resource at '%s'" % scenario_path)
		return state

	if scenario.encounter_entries.is_empty():
		push_error("NewGameFactory: scenario '%s' has no encounter_entries" % scenario_path)
		return state

	var first_entry = scenario.encounter_entries[0]
	var encounter = first_entry.encounter if first_entry != null else null
	if encounter == null:
		push_error(
			"NewGameFactory: scenario '%s' encounter_entries[0] has no usable encounter resource"
			% scenario_path
		)
		return state

	state.party_hex_positions = _seed_party_hex_positions(scenario, encounter)
	return state


## _seed_party_hex_positions(scenario, encounter) -> Array[Dictionary]
##
## Builds one {combatant_id, q, r} entry per scenario.party.
## character_resource_paths member (the ADR-002 scenario-authoritative
## roster), reading each member's starting hex positionally from
## encounter.party_hex_positions[i] (defaulting to q=0, r=0 when the
## encounter has no authored position at that index). combatant_id follows
## the SAME "player_%d" convention already established by
## infrastructure/resource_encounter_repository.gd and
## core/application/use_cases/load_scenario_encounter_use_case.gd, so a
## later feature reconciling this seeded state against a freshly-assembled
## combat session's ids never has to translate between naming schemes.
static func _seed_party_hex_positions(scenario, encounter) -> Array[Dictionary]:
	var positions: Array[Dictionary] = []

	var party_paths: Array = []
	if scenario.party != null:
		party_paths = scenario.party.character_resource_paths

	for i in range(party_paths.size()):
		var q: int = 0
		var r: int = 0
		if i < encounter.party_hex_positions.size():
			var raw_position: Dictionary = encounter.party_hex_positions[i]
			q = int(raw_position.get("q", 0))
			r = int(raw_position.get("r", 0))
		positions.append({"combatant_id": "player_%d" % i, "q": q, "r": r})

	return positions
