extends GutTest
## tests/integration/test_selection_overlay_option_list.gd
##
## GUT suite for FEAT-010 (US-010): presentation/selection_overlay.gd
## additively inserts a Layer-2a candidate_options presentation step ahead
## of Layer-2b targeting, carries the chosen option forward, and wires
## execute(option, target) -- reusing the exact same two-layer flow and
## hex_grid_view highlight path FEAT-008/FEAT-009 already established, with
## no parallel UI.
##
## Driven entirely through the REAL, shipped presentation/selection_overlay.gd
## SelectionOverlay -- no self-wired double stands in for it. Its two
## collaborators are exercised via the SAME "small, stateful, real (not
## all-mocked) double" convention tests/gut/test_post_resolution_lock_regression.gd
## and tests/gut/test_verb_bar_view.gd already established for
## SelectionOverlay's duck-typed registry contract and hex_grid_view
## contract (SpyHexGridView here has exactly ONE highlight entry point --
## set_selectable_hexes() -- so any attempt by SelectionOverlay to reach for
## a second/parallel highlight mechanism would simply have no method to call
## and this suite would fail loudly, not silently pass).
##
## test_criteria covered:
##   1. test_descriptor_with_candidate_options_presents_layer_2a_before_layer_2b_targeting
##   2. test_choosing_option_carries_forward_into_layer_2b_targeting_and_execute_receives_option_and_target
##   3. (both above) hex_grid_view's existing set_selectable_hexes() highlight
##      path is the ONLY highlight call site exercised -- no separate/
##      parallel rendering.
##   4. test_descriptor_with_no_candidate_options_is_unaffected_scalar_regression
##      -- driven via the real wiring, proving this feature is purely
##      additive for every pre-existing (SCALAR) verb shape.

const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const HexCoordClass         = preload("res://core/geometry/hex_coord.gd")

const CAST: String = "CAST"
const STRIKE: String = "STRIKE"


## FakeVerbRegistry -- a small, stateful, real (not all-mocked) double
## satisfying SelectionOverlay's duck-typed registry contract, mirroring
## tests/gut/test_post_resolution_lock_regression.gd's/tests/gut/
## test_verb_bar_view.gd's identically-named fixture.
class FakeVerbRegistry:
	var execute_calls: Array = []
	var execute_result: Dictionary = {"ok": true}

	func execute(verb_id: String, selection = null):
		execute_calls.append([verb_id, selection])
		return execute_result


## SpyHexGridView -- a minimal RefCounted stand-in for presentation/
## hex_grid_view.gd exposing exactly what SelectionOverlay.configure() relies
## on: a `hex_clicked` signal it subscribes to, set_selectable_hexes(), and
## get_token(). Mirrors tests/gut/test_post_resolution_lock_regression.gd's
## identically-named fixture, extended with a small token table so
## candidate_targets can resolve to a real hex.
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


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a descriptor with candidate_options presents Layer-2a (an
# option pick) BEFORE Layer-2b targeting begins -- no target/hex highlight
# reaches hex_grid_view, and no click can resolve, until an option is chosen.
# ══════════════════════════════════════════════════════════════════════════

func test_descriptor_with_candidate_options_presents_layer_2a_before_layer_2b_targeting() -> void:
	var enemy_hex := HexCoordClass.new(2, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	var fireball_option := {"id": "fireball", "label": "Fireball"}
	var ice_bolt_option := {"id": "ice_bolt", "label": "Ice Bolt"}
	var selection: Dictionary = {
		"candidate_targets": ["enemy_0"],
		"candidate_hexes": [],
		"candidate_options": [fireball_option, ice_bolt_option],
	}

	_overlay.activate(CAST, selection)

	assert_true(_overlay.is_active(), "activate() with candidate_options must still enter Layer 2 overall")
	assert_true(_overlay.is_awaiting_option(), "a descriptor with candidate_options must present Layer-2a (awaiting an option pick) first")
	assert_eq(_overlay.get_candidate_options(), [fireball_option, ice_bolt_option], "candidate_options must be exposed verbatim for the Layer-2a presentation")

	# No Layer-2b highlight may have reached hex_grid_view yet -- targeting
	# has not begun.
	assert_eq(_overlay.get_highlighted_target_ids(), [], "no target may be highlighted before an option is chosen")
	for pushed_hexes in _hex_grid_view.set_selectable_calls:
		assert_true(pushed_hexes.is_empty(), "hex_grid_view must never receive a non-empty selectable set before Layer-2a resolves")

	# A click before an option is chosen must resolve nothing at all -- not
	# even a rejection (it is too early in the sequence to mean anything).
	watch_signals(_overlay)
	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_signal_not_emitted(_overlay, "selection_resolved", "a click during Layer-2a's pending option pick must never resolve")
	assert_signal_not_emitted(_overlay, "selection_rejected", "a click during Layer-2a's pending option pick is ignored, not rejected")
	assert_eq(_registry.execute_calls, [], "no registry.execute() call may occur before an option is chosen")
	assert_true(_overlay.is_awaiting_option(), "Layer-2a must remain pending after an ignored click")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: choosing an option carries it forward into Layer-2b targeting
# -- the SAME hex_grid_view highlight path is (re)used -- and a subsequent
# target click invokes execute(verb_id, {"option": ..., "target": ...}) with
# exactly the chosen option and resolved target.
# ══════════════════════════════════════════════════════════════════════════

func test_choosing_option_carries_forward_into_layer_2b_targeting_and_execute_receives_option_and_target() -> void:
	var enemy_hex := HexCoordClass.new(2, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	var fireball_option := {"id": "fireball", "label": "Fireball"}
	var selection: Dictionary = {
		"candidate_targets": ["enemy_0"],
		"candidate_hexes": [],
		"candidate_options": [fireball_option, {"id": "ice_bolt", "label": "Ice Bolt"}],
	}

	_overlay.activate(CAST, selection)
	_overlay.choose_option(fireball_option)

	assert_false(_overlay.is_awaiting_option(), "choosing an option must end Layer-2a's pending state")
	assert_true(_overlay.is_active(), "Layer 2 (now Layer-2b targeting) must remain active after choosing an option")

	# Layer-2b targeting now highlights the SAME candidate_targets the
	# descriptor named, through the SAME hex_grid_view.set_selectable_hexes()
	# call every other verb's Layer-2b already uses -- no separate/parallel
	# highlight mechanism.
	assert_eq(_overlay.get_highlighted_target_ids(), ["enemy_0"], "Layer-2b must highlight the descriptor's candidate_targets once an option is chosen")
	var last_pushed: Array = _hex_grid_view.set_selectable_calls[-1]
	assert_eq(last_pushed.size(), 1, "exactly one hex must be pushed to hex_grid_view for the single candidate target")
	assert_true(last_pushed[0].equals(enemy_hex), "the pushed hex must be the target's own resolved hex, read via hex_grid_view.get_token() -- the same positional data every other verb's Layer-2b reads")

	watch_signals(_overlay)
	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_signal_emitted(_overlay, "selection_resolved", "clicking the highlighted target after choosing an option must resolve")
	assert_eq(
		_registry.execute_calls, [[CAST, {"option": fireball_option, "target": "enemy_0"}]],
		"execute() must be invoked with exactly the chosen option and the resolved target, not just the bare scalar target"
	)
	assert_false(_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the option/target selection resolves")
	assert_eq(_overlay.get_candidate_options(), [], "candidate_options must be cleared once the selection resolves")


func test_choosing_a_different_option_before_any_click_still_resolves_with_the_latest_choice() -> void:
	var enemy_hex := HexCoordClass.new(2, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	var fireball_option := {"id": "fireball"}
	var ice_bolt_option := {"id": "ice_bolt"}
	_overlay.activate(CAST, {
		"candidate_targets": ["enemy_0"], "candidate_hexes": [], "candidate_options": [fireball_option, ice_bolt_option],
	})

	_overlay.choose_option(fireball_option)
	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_eq(_registry.execute_calls, [[CAST, {"option": fireball_option, "target": "enemy_0"}]])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (regression): a descriptor with NO candidate_options is
# completely unaffected -- Layer-2b targeting begins immediately, exactly as
# the pre-existing Strike/Step/Stride path already behaves.
# ══════════════════════════════════════════════════════════════════════════

func test_descriptor_with_no_candidate_options_is_unaffected_scalar_regression() -> void:
	var enemy_hex := HexCoordClass.new(1, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	_overlay.activate(STRIKE, {"candidate_targets": ["enemy_0"], "candidate_hexes": []})

	assert_false(_overlay.is_awaiting_option(), "a descriptor with no candidate_options must never enter Layer-2a")
	assert_eq(_overlay.get_candidate_options(), [], "candidate_options must read back empty when the descriptor named none")
	assert_eq(_overlay.get_highlighted_target_ids(), ["enemy_0"], "Layer-2b targeting must highlight immediately, unaffected by this feature")

	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_eq(
		_registry.execute_calls, [[STRIKE, "enemy_0"]],
		"a SCALAR-shaped verb (no candidate_options) must still resolve via the legacy bare-scalar execute() call, never wrapped in an option/target Dictionary"
	)


func test_choose_option_is_a_no_op_when_not_awaiting_an_option() -> void:
	var enemy_hex := HexCoordClass.new(1, 0)
	_hex_grid_view.register_token("enemy_0", enemy_hex)

	_overlay.activate(STRIKE, {"candidate_targets": ["enemy_0"], "candidate_hexes": []})
	_overlay.choose_option({"id": "should_be_ignored"})
	_hex_grid_view.hex_clicked.emit(enemy_hex)

	assert_eq(
		_registry.execute_calls, [[STRIKE, "enemy_0"]],
		"choose_option() called on a verb that never entered Layer-2a must be inert -- the eventual resolution must stay the plain scalar shape"
	)


func test_choose_option_is_a_no_op_when_no_selection_is_active() -> void:
	_overlay.choose_option({"id": "fireball"})

	assert_false(_overlay.is_active(), "choose_option() must never itself activate Layer 2")
	assert_false(_overlay.is_awaiting_option())
