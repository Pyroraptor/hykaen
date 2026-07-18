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
## FEAT-008 (US-008) additive extension: two further optional trailing
## constructor params, both defaulted so every pre-existing call site
## (4 or 5 positional args) is completely unaffected:
##   resolution_mode (NEW) — one of the ResolutionMode enum members below.
##     Defaults to ResolutionMode.SCALAR, preserving the legacy
##     first-hex/first-target-clicked behavior every verb registered so far
##     (Strike/Step/Stride/End Turn) already relies on — SCALAR is a purely
##     additive default, never a behavior change for those verbs.
##   geometry_rule (NEW) — an opaque Dictionary (shape TBD by
##     core/application/selection_resolution_use_case.gd, e.g.
##     {"radius": 1}), stored and exposed verbatim, never inspected by this
##     class (mirrors candidate_options' "opaque, stored verbatim"
##     convention). Only meaningful when resolution_mode ==
##     ResolutionMode.AREA_SET; null for every other mode. A descriptor
##     whose resolution_mode is AREA_SET but whose geometry_rule is null is
##     a malformed descriptor — SelectionResolutionUseCase.resolve() rejects
##     it at validation time, before any resolution begins (this class
##     itself performs no such validation — it is a plain data holder).
##
## Usage:
##   var descriptor := SelectionDescriptor.new("STRIKE", [], reachable_ids, true)
##   descriptor.candidate_options   # null -- Strike never populates this
##   descriptor.resolution_mode     # ResolutionMode.SCALAR -- the default
##
##   var cast_descriptor := SelectionDescriptor.new(
##       "CAST", [], [], true, [{"id": "fireball", "label": "Fireball"}]
##   )
##   cast_descriptor.candidate_options   # the Option entries verbatim
##
##   var blast_descriptor := SelectionDescriptor.new(
##       "BLAST", [], [], true, null,
##       SelectionDescriptor.ResolutionMode.AREA_SET, {"radius": 1}
##   )
##   blast_descriptor.resolution_mode   # ResolutionMode.AREA_SET
##   blast_descriptor.geometry_rule     # {"radius": 1}

class_name SelectionDescriptor
extends RefCounted

## FEAT-008 (US-008): the three selection-resolution shapes a descriptor's
## Layer 2 selection can require. SCALAR (default) is the legacy
## first-hex/first-target-clicked shape every pre-existing verb
## (Strike/Step/Stride/End Turn) uses, unchanged. OPTION_THEN_TARGET adds a
## Layer-2a option pick ahead of the existing Layer-2b target pick.
## AREA_SET resolves an origin hex pick into a whole affected-hex SET (via
## core/application/selection_resolution_use_case.gd, using core/geometry)
## rather than a single scalar. Declared as a nested enum (mirrors
## core/application/dto/effect_application_error.gd's `Code` convention) so
## it reads as SelectionDescriptor.ResolutionMode.<NAME> at call sites.
enum ResolutionMode {
	SCALAR,
	OPTION_THEN_TARGET,
	AREA_SET,
}

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

## NEW (US-008): one of the ResolutionMode enum members above. Defaults to
## ResolutionMode.SCALAR -- the unchanged, legacy first-hex/first-target-
## clicked behavior every verb registered before this feature (Strike/
## Step/Stride/End Turn) relies on. Never inspected/branched on by this
## class itself -- purely a data field consumed by
## core/application/selection_resolution_use_case.gd.
var resolution_mode: int = ResolutionMode.SCALAR

## NEW (US-008): opaque Dictionary (shape owned by
## core/application/selection_resolution_use_case.gd, e.g. {"radius": 1}),
## stored and exposed verbatim -- never inspected here (mirrors
## candidate_options' "opaque, stored verbatim" convention). Only
## meaningful when resolution_mode == ResolutionMode.AREA_SET; null
## (the default) for every other mode, and for every verb registered before
## this feature.
var geometry_rule = null


func _init(
	p_verb_id: String = "",
	p_candidate_hexes: Array = [],
	p_candidate_targets: Array = [],
	p_cancellable: bool = true,
	p_candidate_options = null,
	p_resolution_mode: int = ResolutionMode.SCALAR,
	p_geometry_rule = null
) -> void:
	verb_id = p_verb_id
	# .duplicate() so each instance owns its own Array -- never aliases a
	# caller-shared list (and never aliases another instance's default,
	# since GDScript default Array literals are re-evaluated per call).
	candidate_hexes = p_candidate_hexes.duplicate()
	candidate_targets = p_candidate_targets.duplicate()
	cancellable = p_cancellable
	candidate_options = p_candidate_options
	resolution_mode = p_resolution_mode
	geometry_rule = p_geometry_rule
