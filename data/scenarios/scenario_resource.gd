## data/scenarios/scenario_resource.gd — ScenarioResource top-level locale
## container (FEAT-006 / US-006, FR-006, NFR-002)
##
## Custom Resource forming the top-level, loadable container for a scenario
## (a "locale"): it composes a stable scenario_id, a human-readable
## display_name, the scenario-authoritative PartyResource (ADR-002 — party
## membership belongs to the scenario, not to each individual encounter),
## and the ordered array of ScenarioEncounterEntryResource placements
## (FEAT-005) that make up this scenario's encounters. This completes the
## domain data graph consumed by the future LoadScenarioEncounterUseCase.
## ScenarioResource itself carries no loading/lookup/trigger-evaluation
## logic — that belongs to the application layer.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (data/scenarios/).
##   It extends Resource — NOT Node, Control, CanvasItem, or SceneTree.
##   It carries ZERO business logic; it is a pure typed data container,
##   constructed/serialized entirely by Godot's ResourceLoader/ResourceSaver.
##
## Fields:
##   scenario_id      — Stable string identifier for this scenario
##                       (e.g. "prologue"). Preserved exactly as authored;
##                       no normalization/trimming.
##   display_name      — Human-readable name for this scenario
##                       (e.g. "The Hollow Prologue"). Preserved exactly as
##                       authored.
##   party             — The scenario-authoritative PartyResource (ADR-002).
##                       Typed as PartyResource; null is technically
##                       constructible but not a valid authored scenario (a
##                       use-case-level concern, not a schema-level one).
##   encounter_entries — Array[ScenarioEncounterEntryResource]; ordered set
##                       of encounter placements for this scenario. An empty
##                       array is valid (e.g. a scenario under construction)
##                       — no non-empty invariant is enforced here.
##
## Usage:
##   var scenario := ScenarioResource.new()
##   scenario.scenario_id = "prologue"
##   scenario.display_name = "The Hollow Prologue"
##   scenario.party = preload("res://data/scenarios/prologue_party.tres")
##   scenario.encounter_entries = [
##       preload("res://data/scenarios/prologue_fight_entry.tres"),
##   ]

class_name ScenarioResource
extends Resource

## Stable identifier for this scenario. Preserved exactly as authored.
@export var scenario_id: String = ""

## Human-readable display name for this scenario. Preserved exactly as
## authored.
@export var display_name: String = ""

## The scenario-authoritative PartyResource (ADR-002). Null is technically
## constructible but not a valid authored scenario.
@export var party: PartyResource = null

## Ordered array of ScenarioEncounterEntryResource placements for this
## scenario. Empty array is valid.
@export var encounter_entries: Array[ScenarioEncounterEntryResource] = []
