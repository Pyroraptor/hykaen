## data/triggers/dialogue_trigger_resource.gd — DialogueTriggerResource
## (ADR-003, FEAT-002 / US-003, FR-003, NFR-002, NFR-003)
##
## Custom Resource encoding the schema for a dialogue trigger: fires from a
## referenced dialogue node. SCHEMA-ONLY, deferred evaluation per ADR-003 —
## this file contains NO dialogue-evaluation/firing logic; that belongs to
## a future application-layer use case.
##
## Architecture note (Clean Architecture / ADR-001, ADR-003):
##   This file lives in the DOMAIN layer (data/triggers/).
##   It extends TriggerResource (itself a Resource) — NOT Node, Control,
##   CanvasItem, or SceneTree. It carries ZERO business logic.
##
## Fields:
##   trigger_type   — inherited discriminator (declared on TriggerResource);
##                    defaults to 'DIALOGUE' for this subclass. Godot 4
##                    forbids redeclaring an @export member already present
##                    on the parent class, so the subclass-specific default
##                    is applied via a trivial _init() override instead of
##                    a second @export declaration — this is a literal
##                    default assignment, not trigger-evaluation/firing
##                    logic (ADR-003 / RISK-001, RISK-008 still hold).
##   npc_id         — identifier of the NPC whose dialogue fires this
##                    trigger.
##   dialogue_node  — identifier of the specific dialogue node/branch that
##                    fires this trigger.
##
## Usage:
##   var trig := DialogueTriggerResource.new()
##   print(trig.trigger_type)   # "DIALOGUE"
##   trig.npc_id = "elder_maren"
##   trig.dialogue_node = "quest_accept"

class_name DialogueTriggerResource
extends TriggerResource

## Identifier of the NPC whose dialogue fires this trigger.
@export var npc_id: String = ""

## Identifier of the specific dialogue node/branch that fires this trigger.
@export var dialogue_node: String = ""


func _init() -> void:
	trigger_type = "DIALOGUE"
