## core/rules/verb_table.gd — CombineContentResource (FEAT-286; US-011;
## FR-011, Iteration N Combinations close-out).
##
## Domain layer (Clean Architecture, ADR-001): pure typed data container,
## zero framework/business logic — mirrors core/rules/spell_definition.gd's
## / core/resources/spell_resource.gd's established "extends Resource,
## authored .tres counterpart" convention (Resource is a data-container
## base, not a scene-tree/engine-lifecycle type, so it is permitted in this
## layer per those files' own precedent).
##
## Encodes a single named Combine's AUTHORED CONTENT — which verb_ids
## compose it, and in what order — so a Combine (e.g. Charge = Stride then
## Strike) is DATA rather than a value baked into
## presentation/combine_action_controller.gd's own source. This is the
## data-driven counterpart to MainScene.gd's own VERB_TABLE (verb_id ->
## controller class): where MainScene's table answers "which controller
## implements verb X", THIS schema answers "which ordered verb_ids does
## named Combine content Y fuse together" — the same "one small table,
## looked up by id" registry shape, one layer up. Authoring a new Combine
## is then ~one new data/combines/{combine_id}.tres file on this schema,
## not a source-code edit.
##
## Fields:
##   combine_id     — canonical string identifier matching the .tres
##                     filename's content (e.g. "CHARGE").
##   name            — display name shown to the player (e.g. "Charge").
##   queue_verb_ids — ordered Array of verb_id Strings fused by this
##                     Combine (e.g. ["STRIDE", "STRIKE"] for Charge).
##                     Order is authoritative: resolved in this EXACT
##                     sequence by presentation/combine_action_controller.gd
##                     (order_index == array index — see build_charge_queue()
##                     there, which walks this Array to build the
##                     SubActionQueueEntry queue it resolves in order).
##                     Must contain at least 2 entries (Combine always fuses
##                     two-or-more actions; see design notes' "generalizes
##                     to N" requirement).
##
## Usage:
##   var charge = ResourceLoader.load("res://data/combines/charge.tres")
##   charge.queue_verb_ids   # ["STRIDE", "STRIKE"]
##   charge.is_valid()       # true

class_name CombineContentResource
extends Resource

## Canonical string identifier for this Combine content (e.g. "CHARGE").
@export var combine_id: String = ""

## Display name shown to the player (e.g. "Charge").
@export var name: String = ""

## Ordered Array[String] of verb_ids this Combine fuses, resolved in this
## exact sequence. Must contain at least 2 entries.
@export var queue_verb_ids: Array = []


## is_valid() -> bool — true when every load-time invariant holds (see
## validation_error()). Callers (adapters/controllers) MUST check this
## before trusting or exposing a hydrated instance — matches
## core/rules/spell_definition.gd / core/resources/spell_resource.gd's
## established "malformed authored data must fail fast, never silently
## corrupt runtime state" convention.
func is_valid() -> bool:
	return validation_error() == ""


## validation_error() -> String — the human-readable reason this
## CombineContentResource violates a load-time invariant, or "" when valid.
## Computed on demand (not cached at construction) since Resource
## subclasses are hydrated field-by-field by ResourceLoader, not via a
## parameterized constructor call site.
func validation_error() -> String:
	if combine_id == "":
		return "combine_id must not be empty"
	if queue_verb_ids.size() < 2:
		return "queue_verb_ids must contain at least 2 entries (got %d)" % queue_verb_ids.size()
	for verb_id in queue_verb_ids:
		if not (verb_id is String) or verb_id == "":
			return "queue_verb_ids entries must be non-empty Strings"
	return ""
