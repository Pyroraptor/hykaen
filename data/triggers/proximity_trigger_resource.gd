## data/triggers/proximity_trigger_resource.gd — ProximityTriggerResource
## (ADR-003, FEAT-002 / US-003, FR-003, NFR-002, NFR-003)
##
## Custom Resource encoding the schema for a proximity trigger: fires when
## the party occupies one of `trigger_hexes`. SCHEMA-ONLY, deferred
## evaluation per ADR-003 — this file contains NO proximity-check/firing
## logic; that belongs to a future application-layer use case.
##
## Architecture note (Clean Architecture / ADR-001, ADR-003):
##   This file lives in the DOMAIN layer (data/triggers/).
##   It extends TriggerResource (itself a Resource) — NOT Node, Control,
##   CanvasItem, or SceneTree. It carries ZERO business logic.
##
## Fields:
##   trigger_type   — inherited discriminator (declared on TriggerResource);
##                    defaults to 'PROXIMITY' for this subclass. Godot 4
##                    forbids redeclaring an @export member already present
##                    on the parent class, so the subclass-specific default
##                    is applied via a trivial _init() override instead of
##                    a second @export declaration — this is a literal
##                    default assignment, not trigger-evaluation/firing
##                    logic (ADR-003 / RISK-001, RISK-008 still hold).
##   trigger_hexes  — Array of {"q": int, "r": int} Dictionaries describing
##                    the axial hex coordinates that fire this trigger.
##
## Usage:
##   var trig := ProximityTriggerResource.new()
##   print(trig.trigger_type)   # "PROXIMITY"
##   trig.trigger_hexes = [{"q": 2, "r": -1}]

class_name ProximityTriggerResource
extends TriggerResource

## Array of {"q": int, "r": int} Dictionaries — the axial hex coordinates
## that fire this trigger when a party member occupies one.
@export var trigger_hexes: Array = []


func _init() -> void:
	trigger_type = "PROXIMITY"
