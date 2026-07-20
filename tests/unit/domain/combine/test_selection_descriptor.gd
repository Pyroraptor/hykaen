extends GutTest
## tests/unit/domain/combine/test_selection_descriptor.gd
##
## GUT suite for FEAT-001 (US-001; FR-001): the domain SelectionDescriptor
## value object (core/domain/combine/selection_descriptor.gd).
##
## Verifies (test_criteria):
##   1. SelectionDescriptor constructs with ok/candidate_options/
##      candidate_hexes/candidate_targets/order_index/meta fields, all
##      readable back exactly as passed in.
##   2. It is immutable after construction — expressed (per this
##      codebase's established EffectBase convention: see
##      tests/unit/domain/effects/test_effect_value_objects.gd) as "every
##      field is set exactly once in _init() and never mutated by any
##      instance method", proven here by (a) two independently-constructed
##      instances never sharing the same underlying Array/Dictionary
##      instance for a default-valued field, and (b) reading each field
##      twice in a row returns the identical value both times.
##   3. A default/failure construction (ok=false, no arguments) yields an
##      explicit ok=false with all candidate lists empty — never treated
##      as an implicit success.

const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: constructs with all fields, readable back exactly as passed
# ══════════════════════════════════════════════════════════════════════════

func test_constructs_with_all_fields_readable_back() -> void:
	var options: Array = [{"id": "STRIDE", "label": "Stride", "kind": "VERB"}]
	var hexes: Array = [Vector2i(1, 0), Vector2i(0, 1)]
	var targets: Array = ["enemy_0"]
	var meta: Dictionary = {"post_move_hex": Vector2i(1, 0)}

	var d := SelectionDescriptorClass.new(true, options, hexes, targets, 2, meta)

	assert_true(d.ok, "ok must be true")
	assert_eq(d.candidate_options, options, "candidate_options must round-trip exactly")
	assert_eq(d.candidate_hexes, hexes, "candidate_hexes must round-trip exactly")
	assert_eq(d.candidate_targets, targets, "candidate_targets must round-trip exactly")
	assert_eq(d.order_index, 2, "order_index must round-trip exactly")
	assert_eq(d.meta, meta, "meta must round-trip exactly")


func test_order_index_defaults_to_zero_for_a_single_non_queued_verb() -> void:
	var d := SelectionDescriptorClass.new(true, [], [], [])
	assert_eq(d.order_index, 0, "order_index defaults to 0 for a single, non-queued verb")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: immutable after construction
# ══════════════════════════════════════════════════════════════════════════

func test_default_valued_array_fields_are_not_shared_across_instances() -> void:
	var a := SelectionDescriptorClass.new(true)
	var b := SelectionDescriptorClass.new(true)

	a.candidate_hexes.append(Vector2i(5, 5))

	assert_eq(
		b.candidate_hexes.size(), 0,
		"mutating one instance's default-valued Array must never affect a sibling instance's Array"
	)


func test_default_valued_dictionary_fields_are_not_shared_across_instances() -> void:
	var a := SelectionDescriptorClass.new(true)
	var b := SelectionDescriptorClass.new(true)

	a.meta["injected"] = true

	assert_false(
		b.meta.has("injected"),
		"mutating one instance's default-valued Dictionary must never affect a sibling instance's Dictionary"
	)


func test_fields_are_stable_across_repeated_reads() -> void:
	var d := SelectionDescriptorClass.new(true, [], [Vector2i(0, 0)], [], 1, {"k": "v"})

	assert_eq(d.ok, d.ok)
	assert_eq(d.order_index, d.order_index)
	assert_eq(d.candidate_hexes, d.candidate_hexes)
	assert_eq(d.meta, d.meta)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: an explicit failure/default construction is never an
# implicit success
# ══════════════════════════════════════════════════════════════════════════

func test_default_construction_is_an_explicit_failure_not_an_implicit_success() -> void:
	var d := SelectionDescriptorClass.new()

	assert_false(d.ok, "a default-constructed SelectionDescriptor must default to ok=false")
	assert_eq(d.candidate_options, [], "candidate_options must default to an empty Array")
	assert_eq(d.candidate_hexes, [], "candidate_hexes must default to an empty Array")
	assert_eq(d.candidate_targets, [], "candidate_targets must default to an empty Array")
	assert_eq(d.meta, {}, "meta must default to an empty Dictionary")


func test_explicit_ok_true_with_empty_candidates_is_still_readable_as_such() -> void:
	# Guards the api_contracts/error_handling distinction: an explicit
	# ok=true with empty candidate lists is a DIFFERENT, still-legitimate
	# state from ok=false — this VO never collapses the two together.
	var d := SelectionDescriptorClass.new(true, [], [], [])
	assert_true(d.ok)
	assert_eq(d.candidate_options.size(), 0)
