## core/domain/trigger_type.gd — TriggerType value object (FEAT-002 / US-003 /
## US-004, iteration Q)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O. Extends RefCounted only, matching the existing value-object
## convention (core/geometry/hex_coord.gd, core/domain/effects/effect_kind.gd).
##
## A tiny namespace of String constants naming the scenario-trigger kinds
## data/**/*TriggerResource.gd Resources (design notes' DATA layer,
## ProximityTriggerResource) and the application-layer
## ExplorationController (US-004) both need to recognize — so US-001/US-003
## never hardcode the literal "PROXIMITY" string in more than one place.
##
## PROXIMITY is the only trigger kind implemented this iteration (US-001's
## ProximityTriggerResource, US-004's distance-2 ring membership check).
## DIALOGUE is reserved for a future iteration (per design notes' DOMAIN
## section: "TriggerType: enum/constant value object (PROXIMITY today;
## DIALOGUE reserved for Iteration R)") — declared here now so a later
## feature only has to consume the constant, never invent/rename it.
##
## String constants (rather than a Godot `enum`) are used deliberately: the
## DATA layer's ProximityTriggerResource stores trigger_type as a String
## field (design notes' data_model), so this file's constants are the exact
## values serialized to/deserialized from .tres — a bare int enum would
## require a separate string<->int mapping table that doesn't otherwise
## exist anywhere in this codebase's data model.
##
## Usage:
##   trigger.trigger_type == TriggerType.PROXIMITY

class_name TriggerType
extends RefCounted

## The only trigger kind implemented this iteration — proximity to a hex
## ring around an encounter's enemy start position (US-003/US-004).
const PROXIMITY: String = "PROXIMITY"

## Reserved for a future iteration (dialogue-triggered encounters). Not
## consumed anywhere yet — declared now so the constant name is pinned
## ahead of that feature's implementation.
const DIALOGUE: String = "DIALOGUE"
