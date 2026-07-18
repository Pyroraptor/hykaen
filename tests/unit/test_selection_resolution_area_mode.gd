extends GutTest
## tests/unit/test_selection_resolution_area_mode.gd
##
## GUT suite for FEAT-008 (US-008): SelectionResolutionUseCase
## (core/application/selection_resolution_use_case.gd) extends
## SelectionDescriptor (core/application/selection_descriptor.gd) resolution
## to support OPTION_THEN_TARGET/AREA_SET resolution_modes, computing
## affected-hex sets via core/geometry (HexMath) from a chosen origin hex,
## and introduces the ResolvedSelection value object
## (core/application/resolved_selection.gd).
##
## Verifies exactly the four test_criteria named for this feature:
##   1. SCALAR mode resolution behavior identical to legacy
##      first-hex-clicked scalar result.
##   2. AREA_SET mode computes the affected-hex set via core/geometry
##      (HexMath.hex_neighbors) correctly for a known origin/shape.
##   3. AREA_SET descriptor with no bound geometry_rule is rejected at
##      validation time before any resolution begins.
##   4. ResolvedSelection enforces exactly one of scalar_target /
##      (option+scalar_target) / target_set populated per mode.

const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")
const SelectionResolutionUseCaseClass = preload("res://core/application/selection_resolution_use_case.gd")
const ResolvedSelectionClass = preload("res://core/application/resolved_selection.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: SCALAR mode resolution behavior identical to legacy
# first-hex-clicked scalar result
# ══════════════════════════════════════════════════════════════════════════

func test_scalar_mode_is_the_default_resolution_mode_for_existing_verb_shapes() -> void:
	# Mirrors Strike's exact existing 4-positional-arg construction --
	# proves this feature introduces zero behavior change for descriptors
	# that never mention resolution_mode at all.
	var descriptor := SelectionDescriptorClass.new("STRIKE", [], ["enemy_0"], true)

	assert_eq(descriptor.resolution_mode, SelectionDescriptorClass.ResolutionMode.SCALAR, "resolution_mode must default to SCALAR, preserving every pre-existing verb's behavior")
	assert_null(descriptor.geometry_rule, "geometry_rule must default to null for a SCALAR descriptor")


func test_scalar_mode_resolves_a_clicked_target_id_identically_to_legacy_behavior() -> void:
	# Mirrors presentation/selection_overlay.gd's existing _on_hex_clicked()
	# -> _resolve(target_id) legacy path for a Strike-shaped descriptor: a
	# click matching a highlighted target resolves to that bare target_id
	# String, unchanged.
	var descriptor := SelectionDescriptorClass.new("STRIKE", [], ["enemy_0", "enemy_1"], true)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {"scalar_target": "enemy_0"})

	assert_true(resolved.is_valid(), "a well-formed SCALAR resolution must be valid: %s" % resolved.validation_error())
	assert_eq(resolved.mode, SelectionDescriptorClass.ResolutionMode.SCALAR, "mode must read back SCALAR")
	assert_eq(resolved.scalar_target, "enemy_0", "scalar_target must be exactly the legacy clicked target_id, unchanged")
	assert_null(resolved.option, "SCALAR mode must never populate option")
	assert_null(resolved.target_set, "SCALAR mode must never populate target_set")


func test_scalar_mode_resolves_a_clicked_hex_identically_to_legacy_behavior() -> void:
	# Mirrors the Step/Stride legacy path: a click matching a highlighted
	# candidate_hex resolves to that bare HexCoord, unchanged.
	var hex_b := HexCoordClass.new(3, -1)
	var descriptor := SelectionDescriptorClass.new("STEP", [HexCoordClass.new(1, 0), hex_b], [], true)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {"scalar_target": hex_b})

	assert_true(resolved.is_valid(), "a well-formed SCALAR hex resolution must be valid: %s" % resolved.validation_error())
	assert_same(resolved.scalar_target, hex_b, "scalar_target must be the exact same HexCoord instance the legacy click resolved, never a copy")


func test_scalar_mode_with_no_pick_is_rejected_rather_than_silently_resolved() -> void:
	var descriptor := SelectionDescriptorClass.new("STRIKE", [], ["enemy_0"], true)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {})

	assert_false(resolved.is_valid(), "SCALAR resolution with no scalar_target pick must be rejected, not silently resolved to null")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: AREA_SET mode computes the affected-hex set via
# core/geometry (HexMath) correctly for a known origin/shape
# ══════════════════════════════════════════════════════════════════════════

func _make_area_descriptor(radius: int) -> SelectionDescriptorClass:
	return SelectionDescriptorClass.new(
		"BLAST", [], [], true, null,
		SelectionDescriptorClass.ResolutionMode.AREA_SET, {"radius": radius}
	)


func test_area_set_mode_resolves_origin_plus_radius_zero_to_just_the_origin() -> void:
	var descriptor := _make_area_descriptor(0)
	var use_case := SelectionResolutionUseCaseClass.new()
	var origin := HexCoordClass.new(2, -2)

	var resolved := use_case.resolve(descriptor, {"origin": origin})

	assert_true(resolved.is_valid(), "a well-formed AREA_SET resolution must be valid: %s" % resolved.validation_error())
	assert_eq(resolved.mode, SelectionDescriptorClass.ResolutionMode.AREA_SET, "mode must read back AREA_SET")
	assert_eq(resolved.target_set.size(), 1, "a radius-0 AREA_SET must affect exactly the origin hex")
	assert_true(resolved.target_set[0].equals(origin), "the sole affected hex must be the origin itself")


func test_area_set_mode_resolves_origin_plus_six_neighbors_for_radius_one() -> void:
	# Known origin/shape: HexCoord(0, 0) at radius 1 must affect exactly the
	# origin plus its 6 flat-top axial neighbors (HexMath.hex_neighbors'
	# own documented fixed direction set) -- 7 hexes total, no duplicates,
	# no omissions.
	var descriptor := _make_area_descriptor(1)
	var use_case := SelectionResolutionUseCaseClass.new()
	var origin := HexCoordClass.new(0, 0)

	var resolved := use_case.resolve(descriptor, {"origin": origin})

	assert_true(resolved.is_valid(), "a well-formed AREA_SET resolution must be valid: %s" % resolved.validation_error())
	assert_eq(resolved.target_set.size(), 7, "radius-1 AREA_SET from (0,0) must affect exactly 7 hexes (origin + 6 neighbors)")

	var expected_coords := [
		[0, 0], [1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1],
	]
	for coord in expected_coords:
		var found := false
		for hex_coord in resolved.target_set:
			if hex_coord.q == coord[0] and hex_coord.r == coord[1]:
				found = true
				break
		assert_true(found, "affected set must include hex (q=%d, r=%d)" % [coord[0], coord[1]])


func test_affected_set_is_directly_callable_and_matches_resolve_output() -> void:
	# The use case's affected_set() is public so a future presentation
	# preview/highlight step (US-011) can call it directly -- proves it
	# produces the identical result resolve() itself derives from it.
	var use_case := SelectionResolutionUseCaseClass.new()
	var origin := HexCoordClass.new(0, 0)

	var direct_result: Array = use_case.affected_set(origin, {"radius": 1})

	assert_eq(direct_result.size(), 7, "affected_set() called directly must also return 7 hexes for radius 1 from the origin")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: AREA_SET descriptor with no bound geometry rule is rejected
# at validation time before any resolution begins
# ══════════════════════════════════════════════════════════════════════════

func test_area_set_descriptor_with_no_geometry_rule_is_rejected() -> void:
	var descriptor := SelectionDescriptorClass.new(
		"BLAST", [], [], true, null, SelectionDescriptorClass.ResolutionMode.AREA_SET
		# geometry_rule omitted -- defaults to null.
	)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {"origin": HexCoordClass.new(0, 0)})

	assert_false(resolved.is_valid(), "an AREA_SET descriptor with no bound geometry_rule must be rejected")
	assert_ne(resolved.validation_error(), "", "a rejected resolution must carry a human-readable reason")
	assert_null(resolved.target_set, "no target_set may be populated on a rejected resolution")


func test_area_set_descriptor_with_no_geometry_rule_is_rejected_before_any_geometry_computation() -> void:
	# Defense-in-depth proof that validation happens BEFORE resolution:
	# `origin` here is a String, not a HexCoord -- if the use case ever
	# attempted to compute an affected set from it (calling
	# HexMath.hex_neighbors on a non-HexCoord), the missing `.q`/`.r`
	# members would raise a script error and this test would fail/crash
	# rather than merely assert false. A clean, non-crashing rejection
	# proves the geometry_rule check short-circuits first.
	var descriptor := SelectionDescriptorClass.new(
		"BLAST", [], [], true, null, SelectionDescriptorClass.ResolutionMode.AREA_SET
	)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {"origin": "not_a_hex_coord"})

	assert_false(resolved.is_valid(), "must reject before ever touching the malformed origin pick")


func test_area_set_descriptor_with_bound_geometry_rule_is_not_rejected() -> void:
	var descriptor := _make_area_descriptor(0)
	var use_case := SelectionResolutionUseCaseClass.new()

	var resolved := use_case.resolve(descriptor, {"origin": HexCoordClass.new(0, 0)})

	assert_true(resolved.is_valid(), "an AREA_SET descriptor WITH a bound geometry_rule must resolve successfully")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: ResolvedSelection enforces exactly one of scalar_target /
# (option+scalar_target) / target_set populated per mode
# ══════════════════════════════════════════════════════════════════════════

func test_resolved_selection_scalar_factory_populates_only_scalar_target() -> void:
	var resolved = ResolvedSelectionClass.scalar("enemy_0")

	assert_true(resolved.is_valid(), "scalar() must produce a valid ResolvedSelection")
	assert_eq(resolved.scalar_target, "enemy_0")
	assert_null(resolved.option)
	assert_null(resolved.target_set)


func test_resolved_selection_option_then_target_factory_populates_option_and_scalar_target() -> void:
	var chosen_option := {"id": "fireball"}
	var resolved = ResolvedSelectionClass.option_then_target(chosen_option, "enemy_0")

	assert_true(resolved.is_valid(), "option_then_target() must produce a valid ResolvedSelection")
	assert_eq(resolved.option, chosen_option)
	assert_eq(resolved.scalar_target, "enemy_0")
	assert_null(resolved.target_set)


func test_resolved_selection_area_set_factory_populates_only_target_set() -> void:
	var hexes := [HexCoordClass.new(0, 0)]
	var resolved = ResolvedSelectionClass.area_set(hexes)

	assert_true(resolved.is_valid(), "area_set() must produce a valid ResolvedSelection")
	assert_eq(resolved.target_set, hexes)
	assert_null(resolved.scalar_target)
	assert_null(resolved.option)


func test_resolved_selection_rejects_scalar_mode_missing_scalar_target() -> void:
	var resolved = ResolvedSelectionClass.new(SelectionDescriptorClass.ResolutionMode.SCALAR, null, null, null)

	assert_false(resolved.is_valid(), "SCALAR mode with no scalar_target must be rejected")


func test_resolved_selection_rejects_scalar_mode_with_extraneous_target_set() -> void:
	# A SCALAR-mode instance must not ALSO carry a target_set -- exactly
	# one shape may be populated per mode, never a superset.
	var resolved = ResolvedSelectionClass.new(
		SelectionDescriptorClass.ResolutionMode.SCALAR, "enemy_0", null, [HexCoordClass.new(0, 0)]
	)

	assert_false(resolved.is_valid(), "SCALAR mode must reject an extraneous populated target_set")


func test_resolved_selection_rejects_option_then_target_mode_missing_option() -> void:
	var resolved = ResolvedSelectionClass.new(
		SelectionDescriptorClass.ResolutionMode.OPTION_THEN_TARGET, "enemy_0", null, null
	)

	assert_false(resolved.is_valid(), "OPTION_THEN_TARGET mode with no option must be rejected")


func test_resolved_selection_rejects_option_then_target_mode_missing_scalar_target() -> void:
	var resolved = ResolvedSelectionClass.new(
		SelectionDescriptorClass.ResolutionMode.OPTION_THEN_TARGET, null, {"id": "fireball"}, null
	)

	assert_false(resolved.is_valid(), "OPTION_THEN_TARGET mode with no scalar_target must be rejected")


func test_resolved_selection_rejects_area_set_mode_missing_target_set() -> void:
	var resolved = ResolvedSelectionClass.new(SelectionDescriptorClass.ResolutionMode.AREA_SET, null, null, null)

	assert_false(resolved.is_valid(), "AREA_SET mode with no target_set must be rejected")


func test_resolved_selection_rejects_area_set_mode_with_extraneous_scalar_target() -> void:
	var resolved = ResolvedSelectionClass.new(
		SelectionDescriptorClass.ResolutionMode.AREA_SET, "enemy_0", null, [HexCoordClass.new(0, 0)]
	)

	assert_false(resolved.is_valid(), "AREA_SET mode must reject an extraneous populated scalar_target")


func test_resolved_selection_rejected_factory_carries_reason_and_is_invalid() -> void:
	var resolved = ResolvedSelectionClass.rejected("some malformed descriptor reason")

	assert_false(resolved.is_valid(), "rejected() must always be invalid")
	assert_eq(resolved.validation_error(), "some malformed descriptor reason", "rejected() must carry the given reason verbatim")
	assert_null(resolved.scalar_target)
	assert_null(resolved.option)
	assert_null(resolved.target_set)
