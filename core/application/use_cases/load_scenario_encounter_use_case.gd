## core/application/use_cases/load_scenario_encounter_use_case.gd —
## LoadScenarioEncounterUseCase (FEAT-008 / US-008, FR-007, NFR-002, NFR-005)
##
## Application layer (Clean Architecture / ADR-001): assembles everything a
## Presentation-layer caller (e.g. MainScene.load_encounter_from_scenario(),
## a later feature) needs to stand up a single encounter FROM a scenario's
## already-loaded ScenarioResource — resolving the encounter_id placement,
## the scenario-authoritative party roster (ADR-002), and hydrating live
## combatant Dictionaries via an injected CombatantFactoryPort. Depends
## ONLY on domain data (ScenarioResource / ScenarioEncounterEntryResource /
## EncounterResource / PartyResource / HexCoord, all data/ + core/geometry/
## Resource-or-RefCounted types) plus the injected combatant_factory
## dependency — it NEVER imports ResourceLoader, Node, Control, or any
## Presentation type.
##
## Steel-thread scope note (RISK-002 mitigation, incremental TDD): this
## feature (FEAT-008) implements ONLY the happy path — successful
## encounter_id lookup, scenario.party-authoritative resolution, and
## tiles/start-position forwarding. The three failure branches
## (NULL_SCENARIO / ENCOUNTER_NOT_FOUND / COMBATANT_BUILD_FAILED) are
## represented below (so the result-dict contract documented in the
## design's api_contracts section is coherent end-to-end, and a caller can
## never observe a partially-built "ok:true" payload after a combatant
## build failure) but are exercised by a LATER feature's own dedicated
## test file — this feature's test suite covers the happy path only.
##
## execute(scenario, encounter_id, deps = {}) -> Dictionary
##
## scenario     — a ScenarioResource (data/scenarios/scenario_resource.gd),
##                already loaded by the caller (this use case never touches
##                ResourceLoader itself in this steel thread).
## encounter_id — String; matched against scenario.encounter_entries[i]
##                .encounter_id (exact string equality, first match wins).
## deps         — OPTIONAL Dictionary of injected collaborators, mirroring
##                this codebase's established `deps.get("key", Real.new())`
##                composition-root idiom (see e.g.
##                core/controllers/stride_action_controller.gd,
##                presentation/verbs/spell_action_controller.gd). Recognized
##                key:
##                  "combatant_factory" — a CombatantFactoryPort: any object
##                  exposing build_party_combatant(path, hex_coord,
##                  combatant_id="") -> Dictionary and
##                  build_enemy_combatant(path, hex_coord, combatant_id="",
##                  weapon_path_override="") -> Dictionary, each returning
##                  either a playable combatant Dictionary or
##                  {"error": <code>, ...} on failure
##                  (infrastructure/combatant_factory.gd's own, REUSED,
##                  ADR-006 real-collaborator-by-default contract).
##                  Defaults to a real CombatantFactory.new() when omitted,
##                  so callers/tests that don't care about combatant
##                  construction never have to wire a double. FEAT-007
##                  (US-007 / FR-006): the 4th arg is this encounter's own
##                  weapon_path_overrides[j] for spawn slot j (""
##                  when the array is shorter than j), resolved by
##                  execute() itself — a duck-typed double that only
##                  declares 3 params will now fail loudly (too many
##                  arguments), by design.
##
## Returns (result-dict pattern, no exceptions — matches
## begin_cast_use_case.gd / resolve_stride_use_case.gd's established
## convention):
##   Success: {ok: true, encounter_resource: EncounterResource,
##             party_combatants: Array[Dictionary],
##             enemy_combatants: Array[Dictionary],
##             party_start_positions: Array (verbatim from
##               encounter_resource.party_hex_positions),
##             enemy_start_positions: Array (verbatim from
##               encounter_resource.enemy_hex_positions),
##             tiles: Array[HexTileDataResource] (verbatim from
##               encounter_resource.tiles)}
##   Failure: {ok: false, error_code: String} — one of
##             ERR_NULL_SCENARIO / ERR_ENCOUNTER_NOT_FOUND /
##             ERR_COMBATANT_BUILD_FAILED (see constants below).
##
## ADR-002 (party authority): party_combatants are built from
## scenario.party.character_resource_paths, NEVER from
## encounter_resource.party_resource_paths — even when the matched
## EncounterResource carries its own (non-empty) party_resource_paths, the
## scenario-level roster always wins. This removes the prior redundancy
## where party membership had to be repeated per encounter.

class_name LoadScenarioEncounterUseCase
extends RefCounted

const CombatantFactoryClass = preload("res://infrastructure/combatant_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## Stable error codes for the failure branches of the result-dict contract
## (see file-level doc). A caller keys behavior off these strings, never
## off a raw/engine exception (this codebase's established convention —
## see infrastructure/combatant_factory.gd's ERR_ constants).
const ERR_NULL_SCENARIO: String = "NULL_SCENARIO"
const ERR_ENCOUNTER_NOT_FOUND: String = "ENCOUNTER_NOT_FOUND"
const ERR_COMBATANT_BUILD_FAILED: String = "COMBATANT_BUILD_FAILED"


func execute(scenario, encounter_id: String, deps: Dictionary = {}) -> Dictionary:
	if scenario == null:
		return {"ok": false, "error_code": ERR_NULL_SCENARIO}

	var matched_entry = _find_entry(scenario.encounter_entries, encounter_id)
	if matched_entry == null:
		return {"ok": false, "error_code": ERR_ENCOUNTER_NOT_FOUND}

	var encounter_resource = matched_entry.encounter

	var combatant_factory = deps.get("combatant_factory", CombatantFactoryClass.new())

	# ADR-002: scenario.party is the AUTHORITATIVE roster source — this
	# deliberately ignores encounter_resource.party_resource_paths even
	# when the matched EncounterResource carries its own (non-empty) list.
	var party_paths: Array = []
	if scenario.party != null:
		party_paths = scenario.party.character_resource_paths

	var party_combatants: Array = []
	for i in range(party_paths.size()):
		var hex_coord = _hex_coord_at(encounter_resource.party_hex_positions, i)
		# FEAT-008 (US-007 / FR-006, regression fix): pass a stable
		# combatant_id ("player_%d"), mirroring
		# infrastructure/resource_encounter_repository.gd's identical
		# "%s_%d" % [team.to_lower(), i] convention -- the SAME ids the
		# boot-time hardcoded pipeline's tokens are already keyed by on
		# HexGridView. Without this, every scenario-assembled combatant fell
		# back to CombatantFactory's "" default id (unset param), so a LATER
		# caller (e.g. MainScene's exploration-to-combat handoff) could never
		# correlate a freshly-assembled Combatant back to its already-
		# rendered token, party position, or turn-order bookkeeping — every
		# such combatant collapsed onto the SAME empty-string id.
		var combatant: Dictionary = combatant_factory.build_party_combatant(party_paths[i], hex_coord, "player_%d" % i)
		if combatant.has("error"):
			return {"ok": false, "error_code": ERR_COMBATANT_BUILD_FAILED}
		party_combatants.append(combatant)

	var enemy_combatants: Array = []
	for j in range(encounter_resource.enemy_resource_paths.size()):
		var enemy_hex_coord = _hex_coord_at(encounter_resource.enemy_hex_positions, j)
		# FEAT-007 (US-007 / FR-006, ADR-005/ADR-006): look up this spawn
		# slot's weapon_path_overrides[j] per the design's "Encounter
		# spawn-slot override lookup" api_contract -- an index beyond
		# weapon_path_overrides.size() (or an authored empty string) both
		# collapse to "" (no override, CombatantFactory falls back to the
		# enemy's own weapon_paths[0]), never an index-out-of-range error.
		var weapon_path_override: String = ""
		if j < encounter_resource.weapon_path_overrides.size():
			weapon_path_override = encounter_resource.weapon_path_overrides[j]
		var enemy_combatant: Dictionary = combatant_factory.build_enemy_combatant(
			encounter_resource.enemy_resource_paths[j], enemy_hex_coord, "enemy_%d" % j, weapon_path_override
		)
		if enemy_combatant.has("error"):
			return {"ok": false, "error_code": ERR_COMBATANT_BUILD_FAILED}
		enemy_combatants.append(enemy_combatant)

	return {
		"ok": true,
		"encounter_resource": encounter_resource,
		"party_combatants": party_combatants,
		"enemy_combatants": enemy_combatants,
		"party_start_positions": encounter_resource.party_hex_positions,
		"enemy_start_positions": encounter_resource.enemy_hex_positions,
		"tiles": encounter_resource.tiles,
	}


## _find_entry(entries, encounter_id) -> ScenarioEncounterEntryResource|null
##
## First-match scan over scenario.encounter_entries for an entry whose
## encounter_id equals `encounter_id` exactly (no normalization/trimming,
## mirroring ScenarioEncounterEntryResource's own "preserved exactly as
## authored" field contract). Returns null for an empty entries array or
## when no entry matches — both collapse to the same ENCOUNTER_NOT_FOUND
## error_code at the call site.
func _find_entry(entries: Array, encounter_id: String):
	for entry in entries:
		if entry.encounter_id == encounter_id:
			return entry
	return null


## _hex_coord_at(positions, index) -> HexCoord|null
##
## Converts the {"q": int, "r": int} Dictionary at `positions[index]` (the
## authored EncounterResource.party_hex_positions / enemy_hex_positions
## shape) into a core/geometry/hex_coord.gd HexCoord instance, matching the
## shape CombatantFactoryPort.build_party_combatant()/build_enemy_combatant()
## expect for their hex_coord parameter. Returns null (not an out-of-range
## crash) when `positions` has no entry at `index` — a combatant with no
## authored starting position is built with hex_coord=null, the same
## "no reach-gating applied" contract CombatantFactory already documents
## for a null hex_coord.
func _hex_coord_at(positions: Array, index: int):
	if index >= positions.size():
		return null
	var pos: Dictionary = positions[index]
	return HexCoordClass.new(int(pos.get("q", 0)), int(pos.get("r", 0)))
