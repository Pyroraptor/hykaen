extends GutTest
## tests/integration/test_selection_overlay_area_targeting.gd
##
## GUT suite for FEAT-242 (US-011): presentation/selection_overlay.gd
## additively adds AREA_SET origin-hex pick and preview to the existing
## two-layer verb->target flow -- picking a candidate origin hex computes
## the affected-hex set via core/application/selection_resolution_use_case.gd
## (which itself is a pure CONSUMER of core/geometry's HexMath, per that
## file's own "affected_set() ... exposed ... so a future consumer (e.g.
## presentation preview/highlight, US-011) can call it directly" doc) and
## previews/highlights that computed set through the SAME
## hex_grid_view.set_selectable_hexes() highlight path FEAT-008/FEAT-009/
## FEAT-010 already established -- no forked/parallel rendering. Confirming
## the preview (a second click landing within the previewed set) resolves
## the FULL computed target set into registry.execute(), mirroring the
## OPTION_TARGET Dictionary-shape precedent action_controller.gd's
## TARGET_SET SelectionShape (FEAT-009) already contracts for.
##
## Driven entirely through the REAL, shipped
## presentation/selection_overlay.gd SelectionOverlay -- no self-wired
## double stands in for it. Its two collaborators are exercised via the
## SAME "small, stateful, real (not all-mocked) double" convention
## tests/integration/test_selection_overlay_option_list.gd already
## established for SelectionOverlay's duck-typed registry/hex_grid_view
## contracts (SpyHexGridView here has exactly ONE highlight entry point --
## set_selectable_hexes() -- so any attempt by SelectionOverlay to reach for
## a second/parallel highlight mechanism would simply have no method to
## call and this suite would fail loudly, not silently pass).
##
## test_criteria covered:
##   1. real-selection-path test: AREA origin-hex pick triggers preview
##      highlighting of the core/geometry-computed affected set.
##   2. real-selection-path test: confirming an AREA selection resolves the
##      full computed target set into execute().
##   3. AREA highlighting reuses the existing hex_grid_view highlight path
##      (no forked rendering) -- SpyHexGridView's single set_selectable_hexes()
##      entry point proves this structurally.
##   4. driven via the real selection_overlay wiring (no self-wired doubles).

const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

const BLAST: String = "BLAST"
const STRIKE: String = "STRIKE"


## FakeVerbRegistry -- mirrors tests/integration/test_selection_overlay_option_list.gd's
## identically-named fixture: a small, stateful, real (not all-mocked)
## double satisfying SelectionOverlay's duck-typed registry contract.
class FakeVerbRegistry:
	var execute_calls: Array = []
	var execute_result: Dictionary = {"ok": true}

	func execute(verb_id: String, selection = null):
		execute_calls.append([verb_id, selection])
		return execute_result


## SpyHexGridView -- mirrors tests/integration/test_selection_overlay_option_list.gd's
## identically-named fixture: a minimal RefCounted stand-in for
## presentation/hex_grid_view.gd exposing exactly what
## SelectionOverlay.configure() relies on -- a `hex_clicked` signal, and the
## ONE highlight entry point set_selectable_hexes() -- so a forked/parallel
## AREA highlight mechanism would have no method here to call.
class SpyHexGridView:
	extends RefCounted

	signal hex_clicked(hex_coord)

	var set_selectable_calls: Array = []
	var _tokens: Dictionary = {}

	func register_token(combatant_id: String, hex_coord) -> void:
		_tokens[combatant_id] = {"hex_coord": hex_coord}

	func set_selectable_hexes(hexes: Array) -> void:
		set_selectable_calls.append(hexes.duplicate())

	func get_token(combatant_id: String):
		return _tokens.get(combatant_id, null)


var _overlay = null
var _registry = null
var _hex_grid_view = null


func before_each() -> void:
	_registry = FakeVerbRegistry.new()
	_hex_grid_view = SpyHexGridView.new()
	_overlay = SelectionOverlayClass.new()
	_overlay.configure(_registry, _hex_grid_view)


func _make_area_descriptor(origin_candidates: Array, radius: int) -> Dictionary:
	return {
		"candidate_hexes": origin_candidates,
		"candidate_targets": [],
		"resolution_mode": SelectionDescriptorClass.ResolutionMode.AREA_SET,
		"geometry_rule": {"radius": radius},
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: AREA origin-hex pick triggers preview highlighting of the
# core/geometry-computed affected set.
# ══════════════════════════════════════════════════════════════════════════

func test_picking_a_candidate_origin_hex_previews_the_computed_affected_set() -> void:
	var origin := HexCoordClass.new(0, 0)
	var other_origin := HexCoordClass.new(3, 0)
	_overlay.activate(BLAST, _make_area_descriptor([origin, other_origin], 1))

	# Before any origin is picked, Layer 2 highlights the raw origin
	# candidates -- exactly the SAME hex-highlight path every other verb's
	# Layer 2 already uses.
	assert_eq(_overlay.get_highlighted_hexes().size(), 2, "before an origin pick, the raw origin candidates must be highlighted")

	watch_signals(_overlay)
	_hex_grid_view.hex_clicked.emit(origin)

	# Picking origin (0,0) at radius 1 must preview the origin + its 6
	# neighbors (7 hexes total) -- the exact core/geometry (HexMath)
	# computed set core/application/selection_resolution_use_case.gd's
	# affected_set() derives, and tests/unit/test_selection_resolution_area_mode.gd
	# already proves matches HexMath.hex_neighbors() directly.
	assert_signal_not_emitted(_overlay, "selection_resolved", "an origin pick must only preview -- it must never resolve by itself")
	assert_eq(_overlay.is_awaiting_area_confirm(), true, "picking a candidate origin hex must enter the AREA preview/awaiting-confirm state")

	var preview: Array = _overlay.get_highlighted_hexes()
	assert_eq(preview.size(), 7, "the preview must be the full radius-1 affected set (origin + 6 neighbors), not just the clicked origin hex")

	var expected_coords := [[0, 0], [1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]
	for coord in expected_coords:
		var found := false
		for hex_coord in preview:
			if hex_coord.q == coord[0] and hex_coord.r == coord[1]:
				found = true
				break
		assert_true(found, "affected-set preview must include hex (q=%d, r=%d)" % [coord[0], coord[1]])

	# Criterion 3: the SAME hex_grid_view.set_selectable_hexes() highlight
	# path -- no separate/forked rendering call.
	assert_gt(_hex_grid_view.set_selectable_calls.size(), 0, "the preview must reach hex_grid_view via its existing set_selectable_hexes() highlight path")
	var last_pushed: Array = _hex_grid_view.set_selectable_calls[-1]
	assert_eq(last_pushed.size(), 7, "the exact preview set pushed to hex_grid_view must be the full 7-hex affected set")


func test_picking_a_non_candidate_hex_does_not_enter_preview() -> void:
	var origin := HexCoordClass.new(0, 0)
	_overlay.activate(BLAST, _make_area_descriptor([origin], 1))

	watch_signals(_overlay)
	_hex_grid_view.hex_clicked.emit(HexCoordClass.new(9, 9))

	assert_signal_emitted(_overlay, "selection_rejected", "a click on a non-candidate hex must be rejected, exactly like the legacy SCALAR path")
	assert_false(_overlay.is_awaiting_area_confirm(), "a rejected click must never enter the AREA preview state")
	assert_eq(_registry.execute_calls, [], "no registry.execute() call may occur for a rejected click")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: confirming an AREA selection resolves the FULL computed
# target set into execute().
# ══════════════════════════════════════════════════════════════════════════

func test_confirming_the_preview_resolves_the_full_computed_target_set_into_execute() -> void:
	var origin := HexCoordClass.new(0, 0)
	_overlay.activate(BLAST, _make_area_descriptor([origin], 1))

	_hex_grid_view.hex_clicked.emit(origin)
	assert_true(_overlay.is_awaiting_area_confirm(), "must be previewing after the origin pick")

	var preview: Array = _overlay.get_highlighted_hexes()
	assert_eq(preview.size(), 7)

	watch_signals(_overlay)
	# Confirmation: clicking again within the previewed set (the origin
	# hex itself, which is always a member of its own affected set).
	_hex_grid_view.hex_clicked.emit(origin)

	assert_signal_emitted(_overlay, "selection_resolved", "confirming the preview must resolve the AREA selection")
	assert_eq(_registry.execute_calls.size(), 1, "exactly one registry.execute() call must occur on confirmation")

	var call: Array = _registry.execute_calls[0]
	assert_eq(call[0], BLAST, "execute() must be invoked for the active verb")
	var resolved_targets: Array = call[1]
	assert_eq(resolved_targets.size(), 7, "execute() must receive the FULL computed 7-hex target set, not just the clicked origin")

	var expected_coords := [[0, 0], [1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]
	for coord in expected_coords:
		var found := false
		for hex_coord in resolved_targets:
			if hex_coord.q == coord[0] and hex_coord.r == coord[1]:
				found = true
				break
		assert_true(found, "resolved target set handed to execute() must include hex (q=%d, r=%d)" % [coord[0], coord[1]])

	assert_false(_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the AREA selection resolves")
	assert_false(_overlay.is_awaiting_area_confirm(), "the AREA preview/awaiting-confirm state must be cleared once resolved")


func test_confirming_via_a_different_hex_within_the_previewed_set_still_resolves_full_set() -> void:
	# A neighbor of the origin (also a member of the previewed set) must
	# confirm just as well as re-clicking the origin itself -- the
	# confirmation gesture is "click anywhere within the highlighted
	# preview", mirroring the existing highlighted-hex click-resolution
	# convention every other verb's Layer 2 already uses.
	var origin := HexCoordClass.new(0, 0)
	var neighbor := HexCoordClass.new(1, 0)
	_overlay.activate(BLAST, _make_area_descriptor([origin], 1))

	_hex_grid_view.hex_clicked.emit(origin)
	_hex_grid_view.hex_clicked.emit(neighbor)

	assert_eq(_registry.execute_calls.size(), 1, "clicking a previewed neighbor hex must confirm the AREA selection")
	var resolved_targets: Array = _registry.execute_calls[0][1]
	assert_eq(resolved_targets.size(), 7, "confirming via a neighbor hex must still resolve the FULL computed target set")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (regression): a SCALAR-mode descriptor (every pre-existing
# verb) is completely unaffected by this feature.
# ══════════════════════════════════════════════════════════════════════════

func test_scalar_mode_descriptor_is_unaffected_by_area_targeting() -> void:
	var enemy_hex := HexCoordClass.new(2, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	_overlay.activate(STRIKE, {"candidate_targets": ["enemy_0"], "candidate_hexes": []})

	assert_false(_overlay.is_awaiting_area_confirm(), "a SCALAR descriptor must never enter the AREA preview state")

	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_eq(
		_registry.execute_calls, [[STRIKE, "enemy_0"]],
		"a SCALAR-shaped verb must still resolve via the legacy bare-scalar execute() call, unaffected by AREA targeting"
	)
