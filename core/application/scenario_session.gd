## core/application/scenario_session.gd — ScenarioSession runtime state
## (FEAT-003 / US-002, FR-001, ADR-002)
##
## Application layer (Clean Architecture / ADR-001): extends RefCounted only
## — no Node/Control/CanvasItem inheritance, no engine lifecycle callbacks
## (_ready/_process/_physics_process), no engine I/O, and NO imports from
## presentation/ or MainScene.gd. Depends only on the DATA-layer
## ScenarioResource/ScenarioEncounterEntryResource types it holds a
## reference to and returns — never on a concrete Node/Control type. This
## directly mitigates RISK-002 (accidental Node/Presentation coupling); see
## tests/unit/test_scenario_session.gd's dedicated source-scan test.
##
## This is RUNTIME-ONLY application state (ADR-002): it is NOT persisted —
## a fresh ScenarioSession is constructed per play session/exploration
## start, with no save/load surface this iteration. It tracks:
##
##   scenario                 — the currently-loaded ScenarioResource
##                               reference (not owned/copied — the SAME
##                               instance a caller/ResourceLoader-backed
##                               repository handed it). Defaults to null
##                               (no scenario loaded yet).
##   party_hex_positions       — Dictionary<combatant_id: String, HexCoord>;
##                               functional-dependency combatant_id -> hex,
##                               single-column key (3NF-trivial per design
##                               notes' data_model). Empty by default.
##   completed_encounter_ids   — Array[String]; logically a set (no
##                               duplicate entries are ever appended — see
##                               mark_encounter_complete()'s guard) of
##                               encounter_id values already resolved this
##                               session. Empty by default.
##
## Two DELIBERATELY asymmetric contracts (design notes' api_contracts #4,
## both intentional per this feature's own test_criteria):
##
##   is_encounter_complete(encounter_id) — FAIL-OPEN for an id never seen:
##   returns false for ANY id not currently present in
##   completed_encounter_ids, including an id that doesn't correspond to
##   any real entry in `scenario` at all ("not yet seen" semantics — a
##   membership check only, never a scenario/entry lookup).
##
##   mark_encounter_complete(encounter_id) — FAIL-CLOSED / defensive no-op
##   for a "dangling" id: an id is only ever added to
##   completed_encounter_ids when it matches an actual
##   ScenarioEncounterEntryResource.encounter_id within the CURRENTLY
##   loaded `scenario` (or when no `scenario` is loaded at all, in which
##   case the call is unconditionally a no-op). This is what RISK-010's
##   idempotency requirement means by "a defensive no-op on unknown ids" —
##   it prevents completed_encounter_ids from ever accumulating a
##   reference to an encounter that doesn't exist, which would otherwise be
##   a silent, unbounded-growth "dangling reference" leak with no way to
##   ever clean it back up. Marking an id that DOES match a real entry is
##   idempotent (repeat calls never append a duplicate).
##
## get_active_encounter_entries() -> Array[ScenarioEncounterEntryResource]
## — every entry in `scenario.encounter_entries` whose encounter_id is NOT
## in completed_encounter_ids, preserving authored order. Returns an empty
## Array (never null, never an error) when `scenario` is null/unset or
## carries no entries.
##
## Usage:
##   var session := ScenarioSession.new()
##   session.scenario = preload("res://data/scenarios/prologue_scenario.tres")
##   session.party_hex_positions["titus"] = HexCoord.new(0, 0)
##   for entry in session.get_active_encounter_entries():
##       ...
##   session.mark_encounter_complete("prologue")
##   session.is_encounter_complete("prologue")   # true

class_name ScenarioSession
extends RefCounted

## The currently-loaded ScenarioResource (data/scenarios/scenario_resource.gd).
## A reference, not a copy. Null until a caller assigns one.
var scenario = null

## Dictionary<combatant_id: String, HexCoord> — each party member's current
## hex position during exploration. Empty until populated by a caller
## (e.g. a future ExplorationController).
var party_hex_positions: Dictionary = {}

## Array[String] — encounter_id values already resolved this session. A
## logical set: mark_encounter_complete() never appends a duplicate.
var completed_encounter_ids: Array = []


## is_encounter_complete(encounter_id) -> bool
##
## FAIL-OPEN membership check: true only if `encounter_id` is currently
## present in completed_encounter_ids. An id never marked complete
## (including one that matches no real entry in `scenario`) returns false
## — "not yet seen", never an error.
func is_encounter_complete(encounter_id: String) -> bool:
	return completed_encounter_ids.has(encounter_id)


## mark_encounter_complete(encounter_id) -> void
##
## Defensive, FAIL-CLOSED completion: `encounter_id` is appended to
## completed_encounter_ids ONLY when it matches an actual
## ScenarioEncounterEntryResource.encounter_id within the currently loaded
## `scenario`. A no-op (no crash, no mutation) when:
##   - `scenario` is null (no scenario loaded yet), or
##   - `encounter_id` matches no entry in `scenario.encounter_entries`
##     (a "dangling" id — RISK-010), or
##   - `encounter_id` is already present (idempotent — never a duplicate).
func mark_encounter_complete(encounter_id: String) -> void:
	if scenario == null:
		return
	if completed_encounter_ids.has(encounter_id):
		return
	if not _scenario_has_entry(encounter_id):
		return
	completed_encounter_ids.append(encounter_id)


## get_active_encounter_entries() -> Array[ScenarioEncounterEntryResource]
##
## Every entry in `scenario.encounter_entries` whose encounter_id is NOT in
## completed_encounter_ids, in authored order. Returns an empty Array
## (never null) when `scenario` is null/unset or has no entries.
func get_active_encounter_entries() -> Array:
	var active: Array = []
	if scenario == null:
		return active
	for entry in scenario.encounter_entries:
		if not completed_encounter_ids.has(entry.encounter_id):
			active.append(entry)
	return active


## _scenario_has_entry(encounter_id) -> bool — true iff `scenario` (already
## known non-null by mark_encounter_complete()'s guard above) carries an
## entry whose encounter_id equals `encounter_id` exactly (first-match
## scan, mirroring LoadScenarioEncounterUseCase._find_entry()'s established
## convention — no normalization/trimming).
func _scenario_has_entry(encounter_id: String) -> bool:
	for entry in scenario.encounter_entries:
		if entry.encounter_id == encounter_id:
			return true
	return false
