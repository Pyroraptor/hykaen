extends GutTest
## tests/regression/test_end_turn_direct_execute.gd — FEAT-243 (US-012):
## regression guard preserving END_TURN's direct-execute special case
## (presentation/verb_bar_view.gd's press()) unchanged and untouched by the
## additive Layer-2a (candidate_options, FEAT-010) / Layer-2b AREA_SET
## (FEAT-242) selection-overlay extensions.
##
## Those two features additively taught presentation/selection_overlay.gd to
## interpose an option pick and/or resolve a whole affected-hex SET ahead of
## a verb's Layer-2b targeting — but per presentation/verb_bar_view.gd's own
## file-level doc, END_TURN has NO Layer 2 at all: pressing it calls
## registry.execute(END_TURN) DIRECTLY, never registry.enter_selection(),
## and therefore never emits verb_selection_entered (the ONLY signal
## MainScene.gd's composition root wires into
## SelectionOverlay.activate() — see MainScene.gd's
## _on_verb_bar_selection_entered()). This suite proves that guarantee holds
## STRUCTURALLY, driven through the REAL, shipped VerbBarView and
## SelectionOverlay wired together exactly as MainScene.gd wires them (not a
## hand-waved "should still work" assertion) — including a direct, contrasting
## proof that OTHER verbs (an OPTION_THEN_TARGET-shaped CAST and an
## AREA_SET-shaped BLAST) DO enter SelectionOverlay's Layer-2a/2b flow via
## that exact same wiring, so this suite's own harness is proven capable of
## detecting a regression, not just incapable of ever failing.
##
## test_criteria covered:
##   1. "regression test: END_TURN verb executes directly, never entering
##      selection_overlay's Layer-2a/2b flow" —
##      test_end_turn_never_enters_selection_overlay_layer2a_or_layer2b_flow
##      and test_verb_bar_selection_entered_wiring_never_fires_for_end_turn
##      (contrasted against test_other_verbs_do_enter_selection_overlay_
##      layer2_flow_via_the_same_wiring, proving the harness has teeth).
##   2. "regression test: END_TURN outcome identical to pre-targeting-
##      generalization baseline" —
##      test_end_turn_execute_call_and_result_are_byte_identical_to_pre_
##      generalization_baseline (execute() invoked with exactly
##      (END_TURN, null) — never wrapped in the {"option":...,"target":...}
##      Dictionary shape Layer-2a resolution produces, nor a target-set/tuple
##      shape AREA_SET resolution produces — and press()'s return value is
##      the registry's own result verbatim, unmodified).

const VerbBarViewScene: PackedScene = preload("res://presentation/verb_bar_view.tscn")
const SelectionOverlayClass         = preload("res://presentation/selection_overlay.gd")
const SelectionDescriptorClass      = preload("res://core/application/selection_descriptor.gd")
const HexCoordClass                 = preload("res://core/geometry/hex_coord.gd")

const STRIKE: String    = "STRIKE"
const CAST: String      = "CAST"
const BLAST: String     = "BLAST"
const END_TURN: String  = "END_TURN"


## FakeVerbRegistry — a small, stateful, real (not all-mocked) double
## satisfying VerbBarView's/SelectionOverlay's shared duck-typed registry
## contract, mirroring tests/gut/test_verb_bar_view.gd's/
## tests/gut/test_post_resolution_lock_regression.gd's identically-named
## fixture, extended with a CAST (Layer-2a option list) and BLAST (AREA_SET)
## verb so this suite can prove, via the SAME real wiring, that those verbs
## DO enter Layer 2 while END_TURN structurally cannot.
class FakeVerbRegistry:
	var _verb_ids: Array = [STRIKE, CAST, BLAST, END_TURN]
	var available: Dictionary = {STRIKE: true, CAST: true, BLAST: true, END_TURN: true}

	var enter_selection_calls: Array = []
	var execute_calls: Array = []
	var end_turn_execute_result: Dictionary = {"verb_id": END_TURN, "ok": true, "turn_advanced": true}

	func list_verbs() -> Array:
		var descriptors: Array = []
		for verb_id in _verb_ids:
			descriptors.append({"verb_id": verb_id})
		return descriptors

	func is_available(verb_id: String) -> bool:
		return available.get(verb_id, false)

	func enter_selection(verb_id: String):
		enter_selection_calls.append(verb_id)
		if verb_id == CAST:
			return {
				"candidate_targets": ["enemy_0"],
				"candidate_hexes": [],
				"candidate_options": [{"id": "fireball", "label": "Fireball"}, {"id": "ice_bolt", "label": "Ice Bolt"}],
			}
		if verb_id == BLAST:
			return {
				"candidate_hexes": [HexCoordClass.new(0, 0)],
				"candidate_targets": [],
				"resolution_mode": SelectionDescriptorClass.ResolutionMode.AREA_SET,
				"geometry_rule": {"radius": 1},
			}
		return {"candidate_hexes": [], "candidate_targets": []}

	func execute(verb_id: String, selection = null):
		execute_calls.append([verb_id, selection])
		if verb_id == END_TURN:
			return end_turn_execute_result
		return {"verb_id": verb_id, "success": true}


## SpyHexGridView — a minimal RefCounted stand-in for presentation/
## hex_grid_view.gd, mirroring tests/integration/test_selection_overlay_
## option_list.gd's/tests/integration/test_selection_overlay_area_targeting.gd's
## identically-named fixture: exactly ONE highlight entry point
## (set_selectable_hexes()) so a forked/parallel highlight path would have
## nothing to call.
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


var _verb_bar_view = null
var _selection_overlay = null
var _hex_grid_view = null
var _registry = null


func before_each() -> void:
	_registry = FakeVerbRegistry.new()
	_hex_grid_view = SpyHexGridView.new()
	_hex_grid_view.register_token("enemy_0", HexCoordClass.new(2, 0))

	_verb_bar_view = VerbBarViewScene.instantiate()
	add_child_autofree(_verb_bar_view)

	_selection_overlay = SelectionOverlayClass.new()
	_selection_overlay.configure(_registry, _hex_grid_view)

	_verb_bar_view.configure(_registry)

	# The EXACT composition-root wiring MainScene.gd establishes:
	# VerbBarView.verb_selection_entered -> SelectionOverlay.activate() (see
	# MainScene.gd's _on_verb_bar_selection_entered()). END_TURN never fires
	# this signal at all (see presentation/verb_bar_view.gd's press()), so if
	# this test harness is wired correctly, activate() can only ever be
	# reached here for a non-END_TURN verb.
	_verb_bar_view.verb_selection_entered.connect(_on_verb_selection_entered)


func _on_verb_selection_entered(verb_id: String, selection) -> void:
	_selection_overlay.activate(verb_id, selection)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — END_TURN executes directly, never entering
# selection_overlay's Layer-2a/2b flow.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_never_enters_selection_overlay_layer2a_or_layer2b_flow() -> void:
	watch_signals(_verb_bar_view)
	watch_signals(_selection_overlay)

	var result = _verb_bar_view.press(END_TURN)

	assert_eq(_registry.enter_selection_calls, [], "END_TURN must NEVER call registry.enter_selection() -- it has no Layer 2 descriptor to produce")
	assert_eq(_registry.execute_calls, [[END_TURN, null]], "END_TURN must call registry.execute() directly")

	assert_false(_selection_overlay.is_active(), "SelectionOverlay must never become active for END_TURN")
	assert_eq(_selection_overlay.get_active_verb_id(), "", "SelectionOverlay's active verb must remain empty after END_TURN")
	assert_false(_selection_overlay.is_awaiting_option(), "SelectionOverlay must never enter Layer-2a (awaiting an option) for END_TURN")
	assert_false(_selection_overlay.is_awaiting_area_confirm(), "SelectionOverlay must never enter an AREA_SET preview/confirm state for END_TURN")
	assert_eq(_selection_overlay.get_candidate_options(), [], "SelectionOverlay must hold no candidate_options after END_TURN")
	assert_eq(_selection_overlay.get_highlighted_hexes(), [], "SelectionOverlay must push no highlight to hex_grid_view for END_TURN")
	assert_eq(_hex_grid_view.set_selectable_calls, [], "hex_grid_view must never receive a set_selectable_hexes() call as a side effect of pressing END_TURN")

	assert_signal_not_emitted(_verb_bar_view, "verb_selection_entered", "END_TURN must never emit verb_selection_entered -- the one signal that drives SelectionOverlay.activate()")
	assert_signal_emitted(_verb_bar_view, "verb_executed", "END_TURN must emit verb_executed for its direct execute() call")
	assert_signal_not_emitted(_selection_overlay, "selection_resolved", "SelectionOverlay must never resolve anything as a side effect of END_TURN, since it was never activated")

	assert_eq(result, _registry.end_turn_execute_result, "press(END_TURN) must return registry.execute()'s result verbatim")


func test_verb_bar_selection_entered_wiring_never_fires_for_end_turn() -> void:
	# A stricter, purely-structural companion to the above: even if a future
	# regression accidentally connected additional listeners to
	# verb_selection_entered, this proves the signal itself is never emitted
	# for END_TURN -- so SelectionOverlay.activate() (or ANY other listener)
	# is categorically unreachable from an END_TURN press, not merely
	# "happens to not be reached by this one wiring."
	var received: Array = []
	_verb_bar_view.verb_selection_entered.connect(func(verb_id, _selection): received.append(verb_id))

	_verb_bar_view.press(END_TURN)

	assert_eq(received, [], "verb_selection_entered must never fire for END_TURN")


## Proves this suite's harness has teeth: the SAME real wiring DOES drive
## OTHER verbs into SelectionOverlay's Layer-2a (CAST, candidate_options) and
## AREA_SET (BLAST) flow -- so "END_TURN never enters Layer 2" is a genuine,
## verb-specific structural guarantee, not an artifact of a harness that
## simply never activates SelectionOverlay for anything.
func test_other_verbs_do_enter_selection_overlay_layer2_flow_via_the_same_wiring() -> void:
	_verb_bar_view.press(CAST)
	assert_true(_selection_overlay.is_active(), "sanity check: CAST must enter Layer 2 through the real wiring")
	assert_true(_selection_overlay.is_awaiting_option(), "sanity check: CAST's candidate_options must present Layer-2a through the real wiring")
	assert_eq(_registry.enter_selection_calls, [CAST])
	_selection_overlay.cancel()

	_verb_bar_view.press(BLAST)
	assert_true(_selection_overlay.is_active(), "sanity check: BLAST must enter Layer 2 through the real wiring")
	_hex_grid_view.hex_clicked.emit(HexCoordClass.new(0, 0))
	assert_true(_selection_overlay.is_awaiting_area_confirm(), "sanity check: BLAST's AREA_SET origin pick must preview through the real wiring")
	_selection_overlay.cancel()

	assert_eq(_registry.enter_selection_calls, [CAST, BLAST], "sanity check: both non-END_TURN verbs above genuinely called enter_selection()")


func test_end_turn_bypasses_layer2_even_when_pressed_interleaved_with_other_verbs_layer2_activity() -> void:
	# A stray Layer 2 selection left open for another verb must never leak
	# into, or be disturbed in a way that makes END_TURN LOOK like it entered
	# Layer 2 -- END_TURN's execute() must still fire directly regardless of
	# any concurrent overlay state.
	_verb_bar_view.press(CAST)
	assert_true(_selection_overlay.is_active())

	# Cancel back to Layer 1 (mirrors presentation/cancel_controller.gd) --
	# END_TURN is only ever pressed from Layer 1 in real play, and this test
	# proves that even so, no residual state from CAST's Layer-2a bleeds into
	# END_TURN's direct-execute path.
	_selection_overlay.cancel()

	var result = _verb_bar_view.press(END_TURN)

	assert_false(_selection_overlay.is_active(), "SelectionOverlay must remain inactive across the END_TURN press")
	assert_eq(_registry.execute_calls[-1], [END_TURN, null])
	assert_eq(result, _registry.end_turn_execute_result)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — END_TURN outcome identical to the pre-targeting-
# generalization baseline (byte-identical call shape and result).
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_execute_call_and_result_are_byte_identical_to_pre_generalization_baseline() -> void:
	# The pre-targeting-generalization baseline (tests/gut/test_verb_bar_view.gd's
	# own Criterion-3 suite, predating FEAT-010/FEAT-242): pressing END_TURN
	# calls registry.execute(END_TURN, null) with a bare null selection --
	# NEVER the Layer-2a {"option": ..., "target": ...} Dictionary shape, and
	# NEVER an AREA_SET target-set/Array shape -- and press() returns that
	# call's result completely unmodified.
	var result = _verb_bar_view.press(END_TURN)

	assert_eq(_registry.execute_calls.size(), 1, "exactly one execute() call must occur for one END_TURN press")
	var call: Array = _registry.execute_calls[0]
	assert_eq(call[0], END_TURN)
	assert_eq(typeof(call[1]), TYPE_NIL, "END_TURN's execute() selection argument must remain bare null -- never an {\"option\":...,\"target\":...} Dictionary or a resolved target-set/tuple shape")

	assert_eq(result, _registry.end_turn_execute_result, "press(END_TURN)'s return value must be the registry's own result, byte-identical and unwrapped")
	assert_true(result.has("turn_advanced"), "the pre-existing End Turn result shape's fields must survive untouched")


func test_end_turn_result_passthrough_is_unaffected_by_a_result_shape_resembling_option_target() -> void:
	# Defense in depth: even if registry.execute(END_TURN) itself happened to
	# return a Dictionary that LOOKS like the Layer-2a option/target shape
	# (e.g. a coincidental "option"/"target" key), VerbBarView must still
	# pass it through completely verbatim -- it must never itself construct,
	# rewrap, or otherwise reinterpret the result through any Layer-2a/2b
	# lens (that generalization logic lives entirely in
	# presentation/selection_overlay.gd, never duplicated into
	# presentation/verb_bar_view.gd's END_TURN branch).
	_registry.end_turn_execute_result = {"option": "should_pass_through_untouched", "target": "also_untouched"}

	var result = _verb_bar_view.press(END_TURN)

	assert_eq(result, {"option": "should_pass_through_untouched", "target": "also_untouched"})
	assert_eq(_registry.execute_calls, [[END_TURN, null]])


func test_multiple_end_turn_presses_across_rounds_each_execute_directly_with_no_drift() -> void:
	# Regression against any hidden statefulness creeping into the direct-
	# execute path across repeated turns/rounds.
	for i in range(3):
		_verb_bar_view.press(END_TURN)

	assert_eq(
		_registry.execute_calls,
		[[END_TURN, null], [END_TURN, null], [END_TURN, null]],
		"every END_TURN press across multiple turns must call execute() identically, with no Layer 2 drift creeping in over time"
	)
	assert_eq(_registry.enter_selection_calls, [], "no repeated END_TURN press may ever call enter_selection()")
	assert_false(_selection_overlay.is_active())


# ══════════════════════════════════════════════════════════════════════════
# Static-source companion: the END_TURN direct-execute branch in
# presentation/verb_bar_view.gd itself contains no Layer-2a/2b generalization
# vocabulary (candidate_options/resolution_mode/AREA_SET) -- that
# vocabulary is owned exclusively by presentation/selection_overlay.gd, per
# this file's own file-level doc ("no if/elif verb_id == ... branching...
# every other aspect of rendering/dispatch is fully generic").
# ══════════════════════════════════════════════════════════════════════════

func test_verb_bar_view_source_has_exactly_one_end_turn_branch_and_no_selection_overlay_vocabulary() -> void:
	var f := FileAccess.open("res://presentation/verb_bar_view.gd", FileAccess.READ)
	assert_not_null(f, "res://presentation/verb_bar_view.gd must be readable")
	if f == null:
		return
	var source: String = f.get_as_text()
	f.close()

	var occurrences: int = 0
	var search_from: int = 0
	while true:
		var idx: int = source.find("verb_id == END_TURN", search_from)
		if idx == -1:
			break
		occurrences += 1
		search_from = idx + 1

	assert_eq(occurrences, 1, "presentation/verb_bar_view.gd must retain EXACTLY ONE 'verb_id == END_TURN' special case (this file's sole verb-identity check) -- neither removed nor duplicated")

	for forbidden_token in ["candidate_options", "resolution_mode", "AREA_SET", "OPTION_THEN_TARGET"]:
		assert_false(
			source.contains(forbidden_token),
			"presentation/verb_bar_view.gd must never itself reference '%s' -- the Layer-2a/2b selection-resolution vocabulary belongs solely to presentation/selection_overlay.gd, never duplicated into the Layer 1 verb bar's END_TURN special case" % forbidden_token
		)
