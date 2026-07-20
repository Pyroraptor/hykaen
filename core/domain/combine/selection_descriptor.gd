## core/domain/combine/selection_descriptor.gd — SelectionDescriptor value
## object (FEAT-001, Iteration O "Combine Selection UX"; US-001, FR-001).
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript RefCounted
## value object — zero Node/Control/CanvasItem inheritance, zero engine
## I/O, zero imports from application/presentation/infrastructure. Extends
## RefCounted only, matching the existing value-object convention
## (core/domain/effects/effect_base.gd, core/rules/sub_action_queue_entry.gd).
##
## SelectionDescriptor is the SINGLE return shape every verb controller's
## enter_selection() hands back (api_contracts): whether the request
## succeeded, what the player may pick from next (verbs/hexes/targets),
## which sub-action within a queue this descriptor is for, and a free-form
## meta bag (e.g. an accumulated post-move hex a later sub-action's
## targeting needs). SelectionOverlay (an outer presentation adapter,
## UNMODIFIED per this iteration's design notes) consumes exactly this
## shape to drive hex/target highlighting — it never receives a bespoke
## {ok, queue}-only Dictionary.
##
## Immutable after construction (design notes' data_model): every field is
## set exactly once in _init() and never reassigned afterward — the SAME
## "immutable after construction" convention already established by
## core/domain/effects/effect_base.gd (see its own file-level doc) rather
## than a getter-only access-control scheme, since nothing else in this
## codebase enforces immutability via language-level privacy and GDScript
## has no such mechanism for RefCounted script fields. Callers MUST treat
## every field as read-only; nothing downstream of construction ever
## reassigns one.
##
## Fields (design notes' data_model, SelectionDescriptor entity — transient,
## returned by enter_selection(), never persisted):
##   ok                — bool; false when the request failed (see
##                       api_contracts' NO_LEGAL_OPTIONS / INVALID_CONTEXT
##                       error responses) — an empty candidate_options list
##                       must never be silently treated as a valid pick set
##                       by a consumer (this is the exact class of bug
##                       FEAT-001's steel thread was named to fix: empty
##                       candidates must be an explicit error state).
##   candidate_options  — Array of {id, label, kind} Dictionaries the
##                        player may pick from (kind: VERB|CONFIRM|SPELL).
##   candidate_hexes    — Array of hex coordinates the player may pick
##                        (e.g. Stride/Step destinations).
##   candidate_targets  — Array of entity refs/ids the player may pick
##                        (e.g. Strike targets).
##   order_index        — int; which sub-action within a CombineQueue this
##                        descriptor is for (0 for a single, non-queued
##                        verb).
##   meta               — Dictionary of free-form accumulated context (e.g.
##                        {"post_move_hex": ...}) a later sub-action's
##                        targeting phase needs. Empty Dictionary when
##                        unused.
##
## Usage:
##   var d := SelectionDescriptor.new(true, [], legal_hexes, [], 0, {})
##   d.ok               # true
##   d.candidate_hexes   # legal_hexes
##
##   var failure := SelectionDescriptorClass.new(false)
##   failure.ok          # false
##   failure.candidate_options  # [] — an explicit empty/failed state, not
##                                     a silently-empty success
##
## NAMING NOTE: this file deliberately carries NO `class_name` declaration.
## core/application/selection_descriptor.gd already registers the GLOBAL
## script class `SelectionDescriptor` (FEAT-007, application layer:
## verb_id/candidate_hexes/candidate_targets/cancellable/candidate_options
## — a DIFFERENT shape serving the existing Layer 2 selection pipeline).
## Godot requires global script class names to be unique project-wide, so
## THIS domain-layer value object (a distinct ok/candidate_options/
## candidate_hexes/candidate_targets/order_index/meta shape, per this
## iteration's design notes) is accessed exclusively via
## `preload("res://core/domain/combine/selection_descriptor.gd")` — see
## this file's own test suite
## (tests/unit/domain/combine/test_selection_descriptor.gd) and every
## future core/domain/combine/ consumer, which MUST do the same rather
## than ever introducing a colliding `class_name SelectionDescriptor` here.
extends RefCounted

## false when the request failed (api_contracts' NO_LEGAL_OPTIONS /
## INVALID_CONTEXT error responses). Set exactly once in _init().
var ok: bool = false

## Array of {id, label, kind} option Dictionaries the player may pick from.
var candidate_options: Array = []

## Array of hex coordinates the player may pick (e.g. Stride destinations).
var candidate_hexes: Array = []

## Array of entity refs/ids the player may pick (e.g. Strike targets).
var candidate_targets: Array = []

## Which sub-action within a CombineQueue this descriptor is for (0 for a
## single, non-queued verb).
var order_index: int = 0

## Free-form Dictionary of accumulated context a later sub-action's
## targeting phase needs (e.g. the post-move hex). Empty when unused.
var meta: Dictionary = {}


func _init(
	p_ok: bool = false,
	p_candidate_options: Array = [],
	p_candidate_hexes: Array = [],
	p_candidate_targets: Array = [],
	p_order_index: int = 0,
	p_meta: Dictionary = {}
) -> void:
	ok = p_ok
	candidate_options = p_candidate_options
	candidate_hexes = p_candidate_hexes
	candidate_targets = p_candidate_targets
	order_index = p_order_index
	meta = p_meta
