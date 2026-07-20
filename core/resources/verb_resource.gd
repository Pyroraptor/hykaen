## core/resources/verb_resource.gd — VerbResource authoring schema
## (FEAT-001, Iteration O "Combine Selection UX"; US-001, FR-001).
##
## Custom Resource encoding a verb's immutable rule constants AND
## combinability/trait metadata, authored directly as
## data/verbs/{verb_id}.tres and loaded via ResourceLoader — the durable,
## data-driven counterpart to core/domain/combine/verb_traits.gd's
## VerbTraits VO (VerbResource is the AUTHORED on-disk shape; VerbTraits is
## the DOMAIN-layer value evaluated FROM it, matching this codebase's
## established SpellResource -> Spell / WeaponResource -> combat-math
## split — see core/resources/spell_resource.gd's own file-level doc).
##
## Architecture note (Clean Architecture / ADR-001), matching
## core/resources/spell_resource.gd and core/model/weapon_resource.gd's
## established convention: this file extends Resource — NOT Node,
## Control, or CanvasItem — and carries ZERO business logic; it is a pure
## typed data container for the AUTHORING/on-disk shape. Rule EVALUATION
## (the same-verb/Repeat exclusion, the reaction-composition rule) lives in
## core/domain/combine/'s combine_actions() domain service (a later
## feature in this iteration), never here.
##
## Fields (design notes' data_model, VerbResource entity — PK verb_id):
##   verb_id            — canonical string identifier (e.g. "STRIDE",
##                         "STRIKE"), matching the .tres filename's content
##                         and the verb_id key every VerbControllerPort
##                         implementation and VerbQueueEntry.verb_id
##                         reference.
##   label              — display name shown to the player (e.g. "Stride").
##   action_cost        — action-point cost to perform this verb. Must be
##                         > 0.
##   stamina_cost       — Stamina cost to perform this verb. Must be >= 0.
##   movement           — true when this verb changes the actor's hex
##                         position (e.g. Stride). false for a
##                         non-positional verb (e.g. Strike).
##   repeat             — true when this verb may legally appear twice in
##                         the SAME CombineQueue (the "Repeat" trait
##                         combine_actions() checks for an identical-verb
##                         pair — design notes' error_handling).
##   reaction_follow_up — true when this verb may be offered as a
##                         REACTION-context follow-up (e.g. a future
##                         Riposte). Defaults to false — most verbs are
##                         TURN-context only.
##   combinable         — true when this verb may be picked into a
##                         CombineQueue at all (VerbRegistryPort filters its
##                         returned pool by this flag before
##                         BuildVerbQueueUseCase ever sees it).
##
## Usage:
##   var stride = ResourceLoader.load("res://data/verbs/stride.tres")
##   stride.movement     # true
##   stride.combinable   # true
##   stride.is_valid()   # true

class_name VerbResource
extends Resource

## Canonical string identifier matching the .tres filename's content (e.g.
## "STRIDE").
@export var verb_id: String = ""

## Display name shown to the player (e.g. "Stride").
@export var label: String = ""

## Action-point cost to perform this verb. Must be > 0.
@export var action_cost: int = 1

## Stamina cost to perform this verb. Must be >= 0.
@export var stamina_cost: int = 0

## True when this verb changes the actor's hex position (e.g. Stride).
@export var movement: bool = false

## True when this verb may legally appear twice within the same
## CombineQueue (the "Repeat" trait).
@export var repeat: bool = false

## True when this verb may be offered as a REACTION-context follow-up
## (e.g. a future Riposte). Defaults to false.
@export var reaction_follow_up: bool = false

## True when this verb may be picked into a CombineQueue at all.
@export var combinable: bool = false


## is_valid() -> bool — true when every load-time invariant holds (see
## validation_error()). Callers (adapters, e.g. a future
## VerbResourceRepository) MUST check this before trusting or exposing a
## hydrated instance — matches core/resources/spell_resource.gd's
## established "malformed authored data must fail fast, never silently
## corrupt runtime state" convention.
func is_valid() -> bool:
	return validation_error() == ""


## validation_error() -> String — the human-readable reason this
## VerbResource violates a load-time invariant, or "" when valid. Computed
## on demand (not cached at construction) since Resource subclasses are
## hydrated field-by-field by ResourceLoader, not via a parameterized
## constructor call site.
func validation_error() -> String:
	if verb_id == "":
		return "verb_id must not be empty"
	if action_cost <= 0:
		return "action_cost must be > 0 (got %d)" % action_cost
	if stamina_cost < 0:
		return "stamina_cost must be >= 0 (got %d)" % stamina_cost
	return ""
