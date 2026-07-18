extends GutTest
## tests/unit/test_selection_descriptor_candidate_options.gd
##
## GUT suite for FEAT-007 (US-007): SelectionDescriptor
## (core/application/selection_descriptor.gd) gains an additive, optional
## `candidate_options` field (Array[Option] | null) plus a `resolution_mode`
## discriminator, laying the data-model groundwork the later
## OPTION_THEN_TARGET / AREA_SET selection work (US-008+) builds on.
##
## This suite covers exactly the three test_criteria named for this feature:
##   1. constructed without candidate_options -> defaults to null, and the
##      EXISTING Strike/Step/Stride shape (verb_id/candidate_hexes/
##      candidate_targets/cancellable) still reads back exactly as before.
##   2. constructed WITH candidate_options -> stores and exposes the list of
##      Option entries verbatim.
##   3. adding candidate_options does not alter candidate_targets/
##      candidate_hexes -- both remain plain Arrays, untouched by the new
##      field.
##
## Deliberately narrow: this feature only extends the descriptor's shape. It
## does NOT wire candidate_options into VerbRegistry/SelectionOverlay/
## action_controller -- that is later, out-of-scope work (US-008+).

const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: constructed without candidate_options defaults to null and
# existing consumers (Strike/Step/Stride) function unchanged
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_options_defaults_to_null_when_omitted() -> void:
	var descriptor := SelectionDescriptorClass.new("STRIKE", [], ["enemy_0"], true)

	assert_null(descriptor.candidate_options, "candidate_options must default to null when the constructor call omits it entirely (all pre-existing verbs)")


func test_strike_shaped_descriptor_reads_back_unchanged() -> void:
	# Mirrors StrikeActionController.enter_selection()'s current shape:
	# {"verb_id": "STRIKE", "candidate_targets": [...], "candidate_hexes": []}.
	var descriptor := SelectionDescriptorClass.new("STRIKE", [], ["enemy_0", "enemy_1"], true)

	assert_eq(descriptor.verb_id, "STRIKE", "verb_id must read back exactly as constructed")
	assert_eq(descriptor.candidate_targets, ["enemy_0", "enemy_1"], "candidate_targets must read back exactly as constructed, unaffected by candidate_options existing on the schema")
	assert_eq(descriptor.candidate_hexes, [], "candidate_hexes must read back exactly as constructed (empty for Strike)")
	assert_true(descriptor.cancellable, "cancellable must read back exactly as constructed")
	assert_null(descriptor.candidate_options, "Strike's descriptor must carry a null candidate_options -- Strike never populates it")

	# Duck-typed read via Object.get(), the exact access pattern
	# presentation/selection_overlay.gd's _extract() helper uses against any
	# non-Dictionary selection object -- proves this class is a drop-in for
	# that established convention without that file needing any change.
	assert_eq(descriptor.get("candidate_targets"), ["enemy_0", "enemy_1"], "Object.get('candidate_targets') duck-typed read must still work, unchanged")
	assert_eq(descriptor.get("candidate_hexes"), [], "Object.get('candidate_hexes') duck-typed read must still work, unchanged")


func test_step_and_stride_shaped_descriptors_read_back_unchanged() -> void:
	# Mirrors Step/Stride's current shape: candidate_hexes populated,
	# candidate_targets empty.
	var step_descriptor := SelectionDescriptorClass.new("STEP", ["hex_a", "hex_b"], [], true)
	var stride_descriptor := SelectionDescriptorClass.new("STRIDE", ["hex_c"], [], true)

	assert_eq(step_descriptor.candidate_hexes, ["hex_a", "hex_b"], "STEP's candidate_hexes must read back exactly as constructed")
	assert_eq(step_descriptor.candidate_targets, [], "STEP's candidate_targets must remain empty")
	assert_null(step_descriptor.candidate_options, "STEP's descriptor must default candidate_options to null")

	assert_eq(stride_descriptor.candidate_hexes, ["hex_c"], "STRIDE's candidate_hexes must read back exactly as constructed")
	assert_null(stride_descriptor.candidate_options, "STRIDE's descriptor must default candidate_options to null")


func test_end_turn_shaped_descriptor_with_no_layer_two_reads_back_unchanged() -> void:
	# Mirrors End Turn's current shape: both candidate collections empty,
	# cancellable false.
	var descriptor := SelectionDescriptorClass.new("END_TURN", [], [], false)

	assert_eq(descriptor.candidate_hexes, [], "END_TURN's candidate_hexes must remain empty")
	assert_eq(descriptor.candidate_targets, [], "END_TURN's candidate_targets must remain empty")
	assert_false(descriptor.cancellable, "END_TURN's cancellable must read back exactly as constructed (false)")
	assert_null(descriptor.candidate_options, "END_TURN's descriptor must default candidate_options to null")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: SelectionDescriptor with candidate_options stores and exposes
# a list of Option entries
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_options_stores_and_exposes_option_entries_when_provided() -> void:
	var fireball_option := {"id": "fireball", "label": "Fireball"}
	var ice_bolt_option := {"id": "ice_bolt", "label": "Ice Bolt"}

	var descriptor := SelectionDescriptorClass.new(
		"CAST", [], [], true, [fireball_option, ice_bolt_option]
	)

	assert_eq(descriptor.candidate_options.size(), 2, "candidate_options must expose exactly the two Option entries supplied")
	assert_eq(descriptor.candidate_options[0], fireball_option, "the first Option entry must read back verbatim")
	assert_eq(descriptor.candidate_options[1], ice_bolt_option, "the second Option entry must read back verbatim")


func test_candidate_options_duck_typed_get_matches_direct_field_access() -> void:
	var options := [{"id": "channel_a"}]
	var descriptor := SelectionDescriptorClass.new("CHANNEL", [], [], true, options)

	assert_eq(descriptor.get("candidate_options"), options, "Object.get('candidate_options') must match the field read directly")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: adding candidate_options does not alter the existing
# candidate_targets/candidate_hexes fields' own schema/behaviour
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_options_presence_does_not_alter_candidate_targets_or_hexes() -> void:
	var without_options := SelectionDescriptorClass.new("STRIKE", ["hex_x"], ["enemy_0"], true)
	var with_options := SelectionDescriptorClass.new(
		"STRIKE", ["hex_x"], ["enemy_0"], true, [{"id": "opt_0"}]
	)

	assert_eq(without_options.candidate_targets, with_options.candidate_targets, "candidate_targets must be identical whether or not candidate_options is populated")
	assert_eq(without_options.candidate_hexes, with_options.candidate_hexes, "candidate_hexes must be identical whether or not candidate_options is populated")
	assert_true(without_options.candidate_targets is Array, "candidate_targets must remain a plain Array")
	assert_true(without_options.candidate_hexes is Array, "candidate_hexes must remain a plain Array")


func test_candidate_targets_and_hexes_remain_independent_arrays_across_instances() -> void:
	# Guards against a shared-default-argument mutation bug (a classic
	# GDScript/Python foot-gun): each instance must own its own Array, not
	# alias a class-level default.
	var first := SelectionDescriptorClass.new("STEP", [], [], true)
	var second := SelectionDescriptorClass.new("STEP", [], [], true)

	first.candidate_hexes.append("hex_should_not_leak")

	assert_eq(second.candidate_hexes, [], "mutating one instance's candidate_hexes must never leak into another instance's candidate_hexes")
	assert_eq(second.candidate_targets, [], "mutating one instance's candidate_hexes must never leak into another instance's candidate_targets")
