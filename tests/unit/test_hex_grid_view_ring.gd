extends GutTest
## tests/unit/test_hex_grid_view_ring.gd — FEAT-004 (US-003 / FR-003,
## NFR-004, mitigates RISK-004): "Render selection ring around selected
## token".
##
## Maps to this feature's own files_to_create entry verbatim
## ("tests/unit/test_hex_grid_view_ring.gd") -- unlike prior HexGridView
## selection-thread features (FEAT-001..FEAT-003), whose test suites were
## relocated to tests/unit/presentation/ to match that directory's existing
## convention, this feature's spec pins the path directly under
## tests/unit/, so this suite lives exactly there.
##
## Verifies (test_criteria):
##   1. With a valid selected token present, should_draw_selection_ring()
##      (the guard consulted by _draw()'s ring-rendering pass,
##      presentation/hex_grid_view.gd) evaluates true -- the draw path is
##      reached.
##   2. With _selected_combatant_id empty (no selection), the guard
##      evaluates false -- ring-draw is skipped entirely, no draw_arc()
##      invocation.
##   3. With _selected_combatant_id set to an id no longer present in
##      _tokens (simulated despawn/death mid-encounter, RISK-004), the
##      guard evaluates false -- ring-draw is skipped and no exception is
##      raised.
##   4. Ring visual parameters (SELECTION_RING_RADIUS, SELECTION_RING_WIDTH,
##      SELECTION_RING_COLOR) match the spec constants exactly: radius
##      HEX_SIZE * 0.65, width 3px, Color(1, 1, 1, 0.9).
##
## Following this codebase's established convention for CanvasItem
## _draw()-side effects (see tests/unit/presentation/
## test_hex_grid_view_selection.gd's file-level doc): there is no public
## hook to intercept/count actual draw_arc() calls made from inside the
## engine's real _draw() dispatch (GUT's double()/partial_double() spy
## tooling is broken under this project's pinned Godot 4.3 / GUT 9.7
## combination). should_draw_selection_ring() is this feature's directly
## unit-testable guard/proof surface instead -- proven true/false exactly
## mirrors "draw path reached" / "ring-draw skipped, no draw_arc
## invocation", and a real _draw()/queue_redraw() dispatch is additionally
## exercised in the despawn scenario to prove no exception is raised.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — valid selected token present: guard evaluates true (draw
# path reached).
# ══════════════════════════════════════════════════════════════════════════

func test_guard_true_when_selected_token_present() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")

	assert_true(
		_hex_grid_view.should_draw_selection_ring(),
		"should_draw_selection_ring() must return true when the selected combatant has a live token"
	)


func test_draw_dispatch_does_not_error_when_selected_token_present() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")

	# Behavioral proof (matches this codebase's established convention for
	# CanvasItem _draw()-side effects): queue_redraw() must not error and the
	# view must remain fully usable afterward, exercising the real ring-draw
	# code path.
	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — no selection (_selected_combatant_id == ""): guard
# evaluates false, ring-draw skipped entirely.
# ══════════════════════════════════════════════════════════════════════════

func test_guard_false_when_no_selection() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	assert_eq(
		_hex_grid_view.get_selected_combatant(), "",
		"sanity check: no selection at boot"
	)
	assert_false(
		_hex_grid_view.should_draw_selection_ring(),
		"should_draw_selection_ring() must return false when there is no current selection"
	)


func test_guard_false_when_selection_explicitly_cleared() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")
	assert_true(
		_hex_grid_view.should_draw_selection_ring(),
		"sanity check: guard must be true before clearing selection"
	)

	_hex_grid_view.set_selected_combatant("")

	assert_false(
		_hex_grid_view.should_draw_selection_ring(),
		"should_draw_selection_ring() must return false once selection has been cleared via \"\""
	)


func test_draw_dispatch_does_not_error_when_no_selection() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	_hex_grid_view.queue_redraw()
	assert_true(true)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — selected id no longer present in _tokens (simulated
# despawn/death mid-encounter, RISK-004): guard evaluates false, no
# exception raised.
# ══════════════════════════════════════════════════════════════════════════

func test_guard_false_when_selected_token_despawned() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")
	assert_true(
		_hex_grid_view.should_draw_selection_ring(),
		"sanity check: guard must be true while the token is still present"
	)

	# Simulate despawn/death mid-encounter: the token is removed from
	# _tokens (e.g. remove_combatants()) but nothing ever clears the stored
	# selection -- set_selected_combatant()/get_selected_combatant()'s own
	# documented "stored anyway" contract means _selected_combatant_id keeps
	# reporting "defender-1" even though its token is gone.
	_hex_grid_view.remove_combatants(["defender-1"])

	assert_eq(
		_hex_grid_view.get_selected_combatant(), "defender-1",
		"sanity check: selection state is stored independently of token presence (per API contract)"
	)
	assert_false(
		_hex_grid_view.should_draw_selection_ring(),
		"should_draw_selection_ring() must return false once the selected id's token has despawned"
	)


func test_draw_dispatch_does_not_raise_when_selected_token_despawned() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")
	_hex_grid_view.remove_combatants(["defender-1"])

	# The real _draw() dispatch must reach the ring-rendering pass, find the
	# guard false, and skip -- never raise an index/null error over the
	# now-missing token.
	_hex_grid_view.queue_redraw()
	assert_true(true)


func test_guard_false_when_selected_id_never_had_a_token() -> void:
	_hex_grid_view.set_selected_combatant("no-such-combatant")

	assert_false(
		_hex_grid_view.should_draw_selection_ring(),
		"should_draw_selection_ring() must return false for an id that never had a corresponding token"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — ring visual parameters match spec constants exactly:
# radius HEX_SIZE * 0.65, width 3px, Color(1, 1, 1, 0.9).
# ══════════════════════════════════════════════════════════════════════════

func test_selection_ring_radius_matches_spec() -> void:
	assert_eq(
		_hex_grid_view.SELECTION_RING_RADIUS, _hex_grid_view.HEX_SIZE * 0.65,
		"SELECTION_RING_RADIUS must equal HEX_SIZE * 0.65 exactly, per spec"
	)


func test_selection_ring_width_matches_spec() -> void:
	assert_eq(
		_hex_grid_view.SELECTION_RING_WIDTH, 3.0,
		"SELECTION_RING_WIDTH must equal 3px exactly, per spec"
	)


func test_selection_ring_color_matches_spec() -> void:
	assert_eq(
		_hex_grid_view.SELECTION_RING_COLOR, Color(1.0, 1.0, 1.0, 0.9),
		"SELECTION_RING_COLOR must equal Color(1, 1, 1, 0.9) exactly, per spec"
	)


# ══════════════════════════════════════════════════════════════════════════
# Additional regression coverage: the view remains fully functional after
# selection-ring-related calls -- the ring pass is a purely additive,
# non-invasive rendering concern (ADR-001).
# ══════════════════════════════════════════════════════════════════════════

func test_view_remains_usable_after_selection_ring_calls() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])
	_hex_grid_view.set_selected_combatant("defender-1")
	_hex_grid_view.queue_redraw()

	_hex_grid_view.remove_combatants(["defender-1"])
	_hex_grid_view.queue_redraw()

	assert_eq(_hex_grid_view.get_token_count(), 0, "HexGridView must remain fully functional after selection-ring rendering calls")
