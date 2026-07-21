extends GutTest
## tests/acceptance/combine/test_us007_overlay_reuse_acceptance.gd —
## FEAT-303 (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-007 ("As the system, the
## existing presentation/selection_overlay.gd SelectionOverlay must be
## reused UNMODIFIED to drive Combine targeting phases -- no Combine-aware
## fork, no parallel highlight/resolution mechanism").
##
## Deeper coverage (a pinned SHA-256 hash of the file's own content, plus a
## full boot-real MainScene proof that standalone Stride/Strike presses are
## unaffected) already lives in
## tests/regression/combine/test_selection_overlay_unmodified.gd -- this
## suite exists to give the deployment-readiness checklist an explicit,
## individually-named, CI-verifiable trace back to US-007's own acceptance
## behavior via a SECOND, independent proof technique: driving the REAL,
## already-shipped presentation/selection_overlay.gd SelectionOverlay
## DIRECTLY (a plain RefCounted adapter -- no scene tree required) with the
## SAME core/domain/combine/selection_descriptor.gd SelectionDescriptor
## shape a real Combine verb controller's enter_selection() returns, and
## confirming it resolves through completely unchanged.
##
## Acceptance behavior verified:
##   1. presentation/selection_overlay.gd's own source contains ZERO
##      Combine-specific identifiers (CombineQueue/VerbQueueEntry/
##      MultiPhaseTargetingController/CombineActionController) -- proving no
##      Combine-aware branching was ever baked into it.
##   2. SelectionOverlay.activate() accepts a REAL
##      core/domain/combine/selection_descriptor.gd SelectionDescriptor
##      (the exact object type a Combine verb controller's enter_selection()
##      returns) directly, via its existing duck-typed candidate_hexes/
##      candidate_targets extraction -- no translation/adapter object is
##      required.
##   3. A hex click against that unmodified overlay resolves through the
##      SAME selection_resolved signal every standalone (non-Combine) verb
##      already uses.

const SELECTION_OVERLAY_PATH: String = "res://presentation/selection_overlay.gd"
const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const CombineSelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


## FakeHexGridView — a minimal RefCounted stand-in for
## presentation/hex_grid_view.gd's own public surface (hex_clicked signal,
## get_token(), set_selectable_hexes()) -- enough for SelectionOverlay's OWN
## unmodified activate()/_on_hex_clicked() path to run without booting a
## scene tree.
class FakeHexGridView:
	extends RefCounted

	signal hex_clicked(hex_coord)

	var selectable_hexes_calls: Array = []

	func set_selectable_hexes(hexes: Array) -> void:
		selectable_hexes_calls.append(hexes)

	func get_token(_combatant_id: String):
		return null


## FakeRegistry — a minimal duck-typed registry (execute(verb_id, value) ->
## Dictionary), mirroring SelectionOverlay's own `_registry` doc.
class FakeRegistry:
	var execute_calls: Array = []

	func execute(verb_id: String, value) -> Dictionary:
		execute_calls.append({"verb_id": verb_id, "value": value})
		return {"resolved": true}


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ══════════════════════════════════════════════════════════════════════════
# US-007, criterion 1 -- zero Combine-specific identifiers in the source.
# ══════════════════════════════════════════════════════════════════════════

func test_us007_selection_overlay_source_has_no_combine_specific_identifiers() -> void:
	var content: String = _read_file(SELECTION_OVERLAY_PATH)

	for forbidden in ["CombineQueue", "VerbQueueEntry", "MultiPhaseTargetingController", "CombineActionController", "combine_actions"]:
		assert_false(content.contains(forbidden), "US-007: presentation/selection_overlay.gd must contain ZERO Combine-specific identifiers -- found '%s'" % forbidden)


# ══════════════════════════════════════════════════════════════════════════
# US-007, criteria 2-3 -- the UNMODIFIED overlay accepts a REAL Combine
# SelectionDescriptor directly and resolves a click through the SAME
# selection_resolved signal.
# ══════════════════════════════════════════════════════════════════════════

func test_us007_unmodified_overlay_accepts_real_combine_selection_descriptor_and_resolves_click() -> void:
	var overlay := SelectionOverlayClass.new()
	var hex_grid_view := FakeHexGridView.new()
	var registry := FakeRegistry.new()
	overlay.configure(registry, hex_grid_view)

	var destination := HexCoordClass.new(1, 0)
	# THE exact SelectionDescriptor shape a real Combine verb controller
	# (e.g. StrideActionController) hands back -- core/domain/combine/
	# selection_descriptor.gd's own ok/candidate_options/candidate_hexes/
	# candidate_targets/order_index/meta value object.
	var combine_descriptor = CombineSelectionDescriptorScript.new(true, [], [destination], [], 0, {})

	overlay.activate("STRIDE", combine_descriptor)

	assert_true(overlay.is_active(), "US-007: the unmodified overlay must enter Layer 2 for a real Combine SelectionDescriptor with zero adapter/translation required")
	assert_eq(overlay.get_active_verb_id(), "STRIDE")
	assert_eq(overlay.get_highlighted_hexes(), [destination], "US-007: candidate_hexes must be read straight off the Combine descriptor's own field, unmodified")

	watch_signals(overlay)
	hex_grid_view.hex_clicked.emit(destination)

	assert_signal_emitted(overlay, "selection_resolved", "US-007: a click against the Combine descriptor must resolve through the SAME selection_resolved signal every standalone verb already uses")
	var resolved_params: Array = get_signal_parameters(overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIDE")
	assert_eq(registry.execute_calls.size(), 1, "US-007: the click must dispatch through the overlay's OWN existing registry.execute() path, unchanged")
	assert_false(overlay.is_active(), "US-007: the overlay must return to Layer 1 exactly as it always has")
