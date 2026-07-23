## data/characters/party_resource.gd — PartyResource cross-encounter party
## definition (ADR-002, FEAT-003 / US-005, FR-005, NFR-002)
##
## Custom Resource encoding a scenario's party roster as a flat array of
## res:// paths to CharacterResource .tres files. This establishes the
## scenario-authoritative party model per ADR-002: party membership belongs
## to the scenario (one PartyResource on ScenarioResource.party), not to
## each individual EncounterResource — removing the prior redundancy where
## EncounterResource.party_resource_paths had to be repeated per encounter.
##
## Architecture note (Clean Architecture / ADR-001):
##   This file lives in the DOMAIN layer (data/characters/).
##   It extends Resource — NOT Node, Control, CanvasItem, or SceneTree.
##   It carries ZERO business logic; it is a pure typed data container,
##   constructed/serialized entirely by Godot's ResourceLoader/ResourceSaver.
##
## Fields:
##   character_resource_paths — Array of res:// paths to CharacterResource
##                               .tres files (e.g.
##                               ["res://data/characters/titus.tres",
##                                "res://data/characters/marigold.tres"]).
##                               An empty array is valid (e.g. a scenario
##                               under construction, or a solo/no-party
##                               vignette) — no non-empty invariant is
##                               enforced here; that is a use-case-level
##                               concern, not a schema-level one.
##
## Usage:
##   var party := PartyResource.new()
##   party.character_resource_paths = [
##       "res://data/characters/titus.tres",
##       "res://data/characters/marigold.tres",
##   ]

class_name PartyResource
extends Resource

## Array of res:// paths to CharacterResource .tres files for party members.
## Empty array is valid.
@export var character_resource_paths: Array = []
