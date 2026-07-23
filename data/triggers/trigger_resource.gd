## data/triggers/trigger_resource.gd — TriggerResource base schema
## (ADR-003, FEAT-002 / US-003, FR-003, NFR-002, NFR-003)
##
## Custom Resource encoding the base schema for a scenario/encounter
## trigger. This is a SCHEMA-ONLY, deferred-evaluation data container per
## ADR-003 — it declares WHAT a trigger is (its type discriminator) but
## contains NO firing/evaluation logic whatsoever. Trigger evaluation
## (e.g. "has the party entered these hexes?") is explicitly out of scope
## for this feature and will be implemented by a future application-layer
## use case that reads these fields — never by this file.
##
## Architecture note (Clean Architecture / ADR-001, ADR-003):
##   This file lives in the DOMAIN layer (data/triggers/).
##   It extends Resource — NOT Node, Control, CanvasItem, or SceneTree.
##   It carries ZERO business logic; it is a pure typed data container,
##   constructed/serialized entirely by Godot's ResourceLoader/ResourceSaver.
##   RISK-001 / RISK-008 mitigation: no trigger-evaluation/firing logic may
##   ever be added to this file or its subclasses — that is enforced by a
##   static review (see tests/unit/data/triggers/test_trigger_resource.gd)
##   rather than deferred to end-of-project review.
##
## Subclasses (closed polymorphic hierarchy, per ADR-003):
##   ProximityTriggerResource — fires when the party occupies given hexes.
##   DialogueTriggerResource  — fires from a dialogue node reference.
##   ActionTriggerResource    — fires from an interactable's action.
##
## Fields:
##   trigger_type — discriminator string identifying the trigger's kind.
##                  Base default is 'AUTO' (no explicit trigger condition —
##                  the encounter is presumed to start immediately).
##                  Subclasses override the default via their own @export
##                  initializer (e.g. ProximityTriggerResource='PROXIMITY').
##
## Usage:
##   var trig := TriggerResource.new()
##   print(trig.trigger_type)   # "AUTO"

class_name TriggerResource
extends Resource

## Discriminator identifying the trigger's kind. Base default 'AUTO' means
## "no explicit trigger condition" (fires immediately / unconditionally).
@export var trigger_type: String = "AUTO"
