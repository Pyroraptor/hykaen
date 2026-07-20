## core/domain/combine/verb_traits.gd — VerbTraits value object (FEAT-001,
## Iteration O "Combine Selection UX"; US-001, FR-001).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript RefCounted
## value object — zero Node/Control/CanvasItem inheritance, zero engine
## I/O, zero imports from application/presentation/infrastructure.
##
## VerbTraits is the DOMAIN-layer schema a later combine_actions() domain
## service evaluates (design notes' architecture) — the runtime-evaluated
## counterpart to core/resources/verb_resource.gd's VerbResource AUTHORED
## .tres shape, matching this codebase's established SpellResource ->
## Spell split (core/resources/spell_resource.gd's own file-level doc).
##
## 3NF note (design notes' data_model): traits live ONLY on
## VerbResource/VerbTraits, never copied onto a VerbQueueEntry, so a rule
## change to a trait can never desync from an already-built queue — a
## queue re-reads traits via VerbRegistryPort (from_verb_resource() below)
## at validation time.
##
## Fields (design notes' architecture, VerbTraits schema):
##   repeat             — true when this verb may legally appear twice
##                         within the same CombineQueue.
##   reaction_follow_up — true when this verb may be offered as a
##                         REACTION-context follow-up.
##   movement           — true when this verb changes the actor's hex
##                         position.
##   action_cost        — action-point cost to perform this verb.
##   stamina_cost       — Stamina cost to perform this verb.
##
## Usage:
##   var traits := VerbTraits.new(false, false, true, 1, 0)
##   traits.movement  # true
##
##   var stride_res := ResourceLoader.load("res://data/verbs/stride.tres")
##   var stride_traits := VerbTraits.from_verb_resource(stride_res)
##   stride_traits.movement  # true

class_name VerbTraits
extends RefCounted

## True when this verb may legally appear twice within the same
## CombineQueue (the "Repeat" trait).
var repeat: bool = false

## True when this verb may be offered as a REACTION-context follow-up.
var reaction_follow_up: bool = false

## True when this verb changes the actor's hex position.
var movement: bool = false

## Action-point cost to perform this verb.
var action_cost: int = 1

## Stamina cost to perform this verb.
var stamina_cost: int = 0


func _init(
	p_repeat: bool = false,
	p_reaction_follow_up: bool = false,
	p_movement: bool = false,
	p_action_cost: int = 1,
	p_stamina_cost: int = 0
) -> void:
	repeat = p_repeat
	reaction_follow_up = p_reaction_follow_up
	movement = p_movement
	action_cost = p_action_cost
	stamina_cost = p_stamina_cost


## from_verb_resource(verb_resource) -> VerbTraits — builds a VerbTraits
## snapshot from a loaded VerbResource (core/resources/verb_resource.gd),
## re-reading its trait fields fresh rather than trusting any
## previously-cached copy — the seam a future combine_actions() domain
## service uses to re-derive traits at validation time (DEF-001).
static func from_verb_resource(verb_resource):
	return VerbTraits.new(
		verb_resource.repeat,
		verb_resource.reaction_follow_up,
		verb_resource.movement,
		verb_resource.action_cost,
		verb_resource.stamina_cost
	)
