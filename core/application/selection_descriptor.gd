## core/application/selection_descriptor.gd — SelectionDescriptor (FEAT-007
## / US-007)
##
## Application layer (Clean Architecture): a plain RefCounted DATA object —
## no ports, no I/O, no engine imports beyond RefCounted — mirroring core/
## application/verb_registry.py's `SelectionDescriptor` dataclass shape
## exactly (verb_id / candidate_hexes / candidate_targets / cancellable),
## realized as a Godot-runtime GDScript class so a future Layer 2
## presentation surface (SelectionOverlay, action_controller.gd) can consume
## a real typed value object instead of the hand-rolled Dictionary shape
## MainScene.gd's `_VerbBarRegistryAdapter` currently hands back (see
## presentation/selection_overlay.gd's own file-level doc, which already
## calls out that this class is the one "this Godot runtime never
## instantiates directly but which this file's contract otherwise mirrors").
##
## THIS FEATURE'S SCOPE (US-007): purely additive data-model groundwork.
## Adds `candidate_options` (Array[Option] | null, NEW) alongside the
## existing fields. `candidate_options` defaults to null and is left
## entirely unpopulated by every verb registered this iteration (Strike/
## Step/Stride/End Turn) — no VerbRegistry/SelectionOverlay/
## action_controller.gd wiring happens here; that is later, out-of-scope
## work (US-008+, the OPTION_THEN_TARGET / AREA_SET selection modes). This
## file exists solely so that later work has a schema to extend rather than
## a breaking change to introduce.
##
## Backward compatibility (test_criteria): a descriptor built with the exact
## same four positional arguments Strike/Step/Stride/End Turn already use
## (verb_id, candidate_hexes, candidate_targets, cancellable) behaves
## byte-identically to before — candidate_options simply reads back null,
## and candidate_targets/candidate_hexes are untouched plain Arrays, each
## instance owning its own (never a shared/aliased default).
##
## Usage:
##   var descriptor := SelectionDescriptor.new("STRIKE", [], reachable_ids, true)
##   descriptor.candidate_options   # null -- Strike never populates this
##
##   var cast_descriptor := SelectionDescriptor.new(
##       "CAST", [], [], true, [{"id": "fireball", "label": "Fireball"}]
##   )
##   cast_descriptor.candidate_options   # the Option entries verbatim

class_name SelectionDescriptor
extends RefCounted

## The verb this descriptor's Layer 2 selection belongs to (e.g. "STRIKE").
var verb_id: String = ""

## Populated for hex-destination verbs (Step/Stride); empty Array for
## verbs with no hex candidates (existing, unchanged shape).
var candidate_hexes: Array = []

## Populated for combatant-target verbs (Strike); empty Array for verbs
## with no target candidates (existing, unchanged shape).
var candidate_targets: Array = []

## Whether this Layer 2 selection can be cancelled/backed out of (existing,
## unchanged field).
var cancellable: bool = true

## NEW (US-007): Array of Option entries (shape TBD by later work; opaque
## to this class -- stored and exposed verbatim, never inspected here) for
## verbs that present a Layer-2a option pick before Layer-2b targeting.
## null for every verb registered this iteration (Strike/Step/Stride/End
## Turn) -- absent/omitted is the backward-compatible default, distinct
## from an explicitly-empty Array.
var candidate_options = null


func _init(
	p_verb_id: String = "",
	p_candidate_hexes: Array = [],
	p_candidate_targets: Array = [],
	p_cancellable: bool = true,
	p_candidate_options = null
) -> void:
	verb_id = p_verb_id
	# .duplicate() so each instance owns its own Array -- never aliases a
	# caller-shared list (and never aliases another instance's default,
	# since GDScript default Array literals are re-evaluated per call).
	candidate_hexes = p_candidate_hexes.duplicate()
	candidate_targets = p_candidate_targets.duplicate()
	cancellable = p_cancellable
	candidate_options = p_candidate_options
