## data/triggers/action_trigger_resource.gd — ActionTriggerResource
## (ADR-003, FEAT-002 / US-003, FR-003, NFR-002, NFR-003)
##
## Custom Resource encoding the schema for an action trigger: fires from a
## referenced interactable's action (e.g. a lever, a chest). SCHEMA-ONLY,
## deferred evaluation per ADR-003 — this file contains NO
## interaction-evaluation/firing logic; that belongs to a future
## application-layer use case.
##
## Architecture note (Clean Architecture / ADR-001, ADR-003):
##   This file lives in the DOMAIN layer (data/triggers/).
##   It extends TriggerResource (itself a Resource) — NOT Node, Control,
##   CanvasItem, or SceneTree. It carries ZERO business logic.
##
## Fields:
##   trigger_type     — inherited discriminator (declared on
##                      TriggerResource); defaults to 'ACTION' for this
##                      subclass. Godot 4 forbids redeclaring an @export
##                      member already present on the parent class, so the
##                      subclass-specific default is applied via a trivial
##                      _init() override instead of a second @export
##                      declaration — this is a literal default assignment,
##                      not trigger-evaluation/firing logic (ADR-003 /
##                      RISK-001, RISK-008 still hold).
##   interactable_id  — identifier of the interactable object whose action
##                      fires this trigger.
##
## Usage:
##   var trig := ActionTriggerResource.new()
##   print(trig.trigger_type)   # "ACTION"
##   trig.interactable_id = "lever_north_gate"

class_name ActionTriggerResource
extends TriggerResource

## Identifier of the interactable object whose action fires this trigger.
@export var interactable_id: String = ""


func _init() -> void:
	trigger_type = "ACTION"
