extends GutTest
## tests/unit/domain/combine/test_verb_traits.gd
##
## GUT suite for FEAT-001 (US-001; FR-001): the domain VerbTraits value
## object (core/domain/combine/verb_traits.gd).
##
## Not individually enumerated in FEAT-001's files_to_create list, but
## added here per this project's "every new source file MUST have a
## corresponding test file" rule — core/domain/combine/verb_traits.gd is a
## new source file this feature creates, so it gets a test file living
## alongside its siblings (test_selection_descriptor.gd,
## test_verb_queue_entry.gd, test_combine_queue.gd) under this same
## tests/unit/domain/combine/ directory.
##
## Verifies:
##   1. VerbTraits constructs with (repeat, reaction_follow_up, movement,
##      action_cost, stamina_cost), all readable back exactly as passed
##      in, with sane defaults.
##   2. from_verb_resource() re-derives a VerbTraits snapshot from a loaded
##      VerbResource's own fields (the DEF-001 "re-read traits fresh, never
##      trust a cached copy" seam), proven against the real
##      data/verbs/stride.tres and data/verbs/strike.tres fixtures.

const VerbTraitsClass = preload("res://core/domain/combine/verb_traits.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: constructs with all fields, sane defaults
# ══════════════════════════════════════════════════════════════════════════

func test_constructs_with_all_fields_readable_back() -> void:
	var traits := VerbTraitsClass.new(true, true, true, 2, 1)

	assert_true(traits.repeat)
	assert_true(traits.reaction_follow_up)
	assert_true(traits.movement)
	assert_eq(traits.action_cost, 2)
	assert_eq(traits.stamina_cost, 1)


func test_defaults_are_repeat_false_reaction_follow_up_false_movement_false() -> void:
	var traits := VerbTraitsClass.new()

	assert_false(traits.repeat)
	assert_false(traits.reaction_follow_up, "reaction_follow_up must default to false")
	assert_false(traits.movement)
	assert_eq(traits.action_cost, 1)
	assert_eq(traits.stamina_cost, 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: from_verb_resource() re-derives from a loaded VerbResource
# ══════════════════════════════════════════════════════════════════════════

func test_from_verb_resource_derives_stride_traits() -> void:
	var stride_resource = ResourceLoader.load("res://data/verbs/stride.tres")
	assert_not_null(stride_resource, "data/verbs/stride.tres must load")
	if stride_resource == null:
		return

	var traits = VerbTraitsClass.from_verb_resource(stride_resource)

	assert_true(traits.movement, "STRIDE's traits must carry movement=true")
	assert_eq(traits.action_cost, stride_resource.action_cost)
	assert_eq(traits.stamina_cost, stride_resource.stamina_cost)
	assert_eq(traits.repeat, stride_resource.repeat)
	assert_eq(traits.reaction_follow_up, stride_resource.reaction_follow_up)


func test_from_verb_resource_derives_strike_traits() -> void:
	var strike_resource = ResourceLoader.load("res://data/verbs/strike.tres")
	assert_not_null(strike_resource, "data/verbs/strike.tres must load")
	if strike_resource == null:
		return

	var traits = VerbTraitsClass.from_verb_resource(strike_resource)

	assert_false(traits.movement, "STRIKE's traits must carry movement=false")
	assert_eq(traits.action_cost, strike_resource.action_cost)
	assert_eq(traits.stamina_cost, strike_resource.stamina_cost)
