## data/scenarios/scenario_encounter_entry_resource.gd —
## ScenarioEncounterEntryResource placement wrapper (FEAT-005 / US-004,
## FR-004, NFR-002)
##
## Custom Resource forming the join entity between ScenarioResource and
## EncounterResource: it pairs a stable encounter_id with the actual
## EncounterResource to load and an optional TriggerResource describing
## when/how the encounter should fire. This is a pure placement wrapper —
## it carries no trigger-evaluation or encounter-loading logic itself; that
## belongs to a future application-layer use case (LoadScenarioEncounterUseCase)
## that reads these fields.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (data/scenarios/).
##   It extends Resource — NOT Node, Control, CanvasItem, or SceneTree.
##   It carries ZERO business logic; it is a pure typed data container,
##   constructed/serialized entirely by Godot's ResourceLoader/ResourceSaver.
##
## Fields:
##   encounter_id — Stable string identifier for this placement within a
##                   scenario's encounter_entries array (e.g. "prologue_fight").
##                   Preserved exactly as authored; no normalization/trimming.
##   encounter     — The EncounterResource to load when this entry fires.
##                   Typed as EncounterResource; null is technically
##                   constructible but not a valid authored entry (a
##                   use-case-level concern, not a schema-level one).
##   trigger       — Optional TriggerResource describing when this encounter
##                   should fire (ADR-003). Null is explicitly valid and
##                   accepted without error — it means "no explicit trigger
##                   condition" (deferred to use-case default handling, e.g.
##                   AUTO/immediate-start semantics).
##
## Usage:
##   var entry := ScenarioEncounterEntryResource.new()
##   entry.encounter_id = "prologue_fight"
##   entry.encounter = preload("res://data/encounters/prologue_encounter.tres")
##   entry.trigger = null   # valid: no trigger condition authored

class_name ScenarioEncounterEntryResource
extends Resource

## Stable identifier for this placement within a scenario's
## encounter_entries array. Preserved exactly as authored.
@export var encounter_id: String = ""

## The EncounterResource to load when this entry fires.
@export var encounter: EncounterResource = null

## Optional TriggerResource describing when this encounter should fire.
## Null is valid and accepted without error (ADR-003 "AUTO" semantics
## deferred to use-case default handling).
@export var trigger: TriggerResource = null
