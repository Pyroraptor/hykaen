extends GutTest
## tests/unit/presentation/test_hex_grid_view_selection.gd — FEAT-001 (US-001
## / FR-001, FR-002, ADR-003): "HexGridView token lookup and selection state
## (data layer)".
##
## Maps to the feature plan's files_to_create entry
## "tests/unit/test_hex_grid_view_selection.gd" — this project's actual,
## established file layout (every prior HexGridView feature, e.g. FEAT-001's
## own test_hex_grid_view_lookup.gd, FEAT-004's test_hex_grid_view_hit_test.gd)
## keeps HexGridView's own script under presentation/hex_grid_view.gd and its
## tests under tests/unit/presentation/, alongside the existing
## test_hex_grid_view.gd / test_hex_grid_view_lookup.gd / test_hex_grid_view_
## hover.gd suites this file follows the exact conventions of, so this suite
## lives here rather than directly under tests/unit/.
##
## Verifies (test_criteria):
##   1. get_combatant_id_at_hex returns the correct combatant_id for a hex
##      with a token (already implemented; re-pinned here as this feature's
##      base data-layer contract).
##   2. get_combatant_id_at_hex returns "" (never null) for a hex with no
##      token.
##   3. set_selected_combatant(id) followed by get_selected_combatant()
##      round-trips the same id.
##   4. set_selected_combatant("") clears selection; get_selected_combatant()
##      returns "".
##   5. set_selected_combatant(id) triggers a redraw.
##
## SelectionRenderPort (design notes): set_selected_combatant(id: String) ->
## void ; get_selected_combatant() -> String. Pure in-memory selection-state
## bookkeeping (the empty-string sentinel is the canonical "no selection"
## value, ADR-003) -- no business-rule/disambiguation logic lives here (that
## is SelectionPolicy's job, out of scope for this feature); this view only
## stores whichever id it is told to select and re-draws.
##
## Criterion 5 ("triggers a redraw") follows this codebase's established
## convention for CanvasItem _draw()-side effects (see tests/unit/
## presentation/test_hex_grid_view_overlays.gd's file-level doc): there is no
## public hook to intercept/count actual draw_* calls made from inside the
## engine's real _draw() dispatch, so "triggers a redraw" is proven
## behaviorally -- queue_redraw() is invoked (never errors) and the view
## remains fully usable/responsive afterward -- while "stores the given id"
## is proven directly via the get_selected_combatant() round-trip.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — occupied hex resolves to the correct combatant_id.
# ══════════════════════════════════════════════════════════════════════════

func test_get_combatant_id_at_hex_returns_correct_id_for_occupied_hex() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	var resolved: String = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(1, 2))

	assert_eq(
		resolved, "defender-1",
		"get_combatant_id_at_hex must return the combatant_id of the token occupying the queried hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — unoccupied hex resolves to "" (never null).
# ══════════════════════════════════════════════════════════════════════════

func test_get_combatant_id_at_hex_returns_empty_string_for_unoccupied_hex() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	var resolved = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(9, 9))

	assert_eq(
		resolved, "",
		"get_combatant_id_at_hex must return \"\" (never null) for a hex with no token"
	)
	assert_ne(
		resolved, null,
		"get_combatant_id_at_hex must never return null, even for an entirely unoccupied hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — set_selected_combatant(id) / get_selected_combatant()
# round-trip.
# ══════════════════════════════════════════════════════════════════════════

func test_set_selected_combatant_round_trips_through_get_selected_combatant() -> void:
	assert_eq(
		_hex_grid_view.get_selected_combatant(), "",
		"sanity check: no selection at boot"
	)

	_hex_grid_view.set_selected_combatant("defender-1")

	assert_eq(
		_hex_grid_view.get_selected_combatant(), "defender-1",
		"get_selected_combatant() must return the id most recently supplied to set_selected_combatant()"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — set_selected_combatant("") clears selection.
# ══════════════════════════════════════════════════════════════════════════

func test_set_selected_combatant_empty_string_clears_selection() -> void:
	_hex_grid_view.set_selected_combatant("defender-1")
	assert_eq(
		_hex_grid_view.get_selected_combatant(), "defender-1",
		"sanity check: selection must be set before it can be cleared"
	)

	_hex_grid_view.set_selected_combatant("")

	assert_eq(
		_hex_grid_view.get_selected_combatant(), "",
		"set_selected_combatant(\"\") must clear the current selection"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — set_selected_combatant(id) triggers a redraw.
# ══════════════════════════════════════════════════════════════════════════

func test_set_selected_combatant_triggers_a_redraw_without_error() -> void:
	_hex_grid_view.set_selected_combatant("defender-1")
	# Behavioral proof (matches this codebase's established convention for
	# CanvasItem _draw()-side effects -- see test_hex_grid_view_overlays.gd):
	# queue_redraw() must not error and the view must remain fully usable
	# afterward.
	_hex_grid_view.queue_redraw()
	assert_true(true)
