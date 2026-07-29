extends GutTest
## tests/unit/presentation/test_hex_grid_view_lookup.gd — FEAT-001 (US-001):
## "Hex-to-combatant lookup primitive on HexGridView".
##
## Maps to the feature plan's files_to_create entry
## "tests/unit/test_hex_grid_view_lookup.gd" — this project's actual,
## established file layout (every prior HexGridView feature, e.g. FEAT-004's
## test_hex_grid_view_hit_test.gd) keeps HexGridView's own script under
## presentation/hex_grid_view.gd and its tests under
## tests/unit/presentation/, alongside the existing test_hex_grid_view.gd /
## test_hex_grid_view_hover.gd / test_hex_grid_view_hit_test.gd suites this
## file follows the exact conventions of, so this suite lives here rather
## than directly under tests/unit/.
##
## Verifies (test_criteria):
##   1. get_combatant_id_at_hex returns the correct combatant_id for an
##      occupied hex.
##   2. get_combatant_id_at_hex returns "" for an unoccupied hex.
##   3. get_combatant_id_at_hex returns the first match (in `_tokens`
##      Dictionary insertion order) when multiple tokens exist -- a
##      deterministic ordering, not an unspecified/arbitrary one.
##   4. get_combatant_id_at_hex never throws when `_tokens` is empty.
##
## ITokenLookup port (design notes): get_combatant_id_at_hex(hex_coord) ->
## String. Pure data-layer primitive: scans the already-instantiated
## CombatantTokenView instances this view owns (`_tokens`, a
## Dictionary(combatant_id -> CombatantTokenView) populated by
## load_combatants()/add_combatants()) and returns the combatant_id of the
## first token whose own `hex_coord` (HexCoord value-equality via
## HexCoord.equals(), not object identity) matches the queried hex. No
## rendering/selection side effect of any kind -- this method must not
## call queue_redraw() or mutate any selection state.

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

func test_returns_combatant_id_for_an_occupied_hex() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	var resolved: String = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(1, 2))

	assert_eq(
		resolved, "defender-1",
		"get_combatant_id_at_hex must return the combatant_id of the token occupying the queried hex"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — unoccupied hex resolves to "".
# ══════════════════════════════════════════════════════════════════════════

func test_returns_empty_string_for_an_unoccupied_hex() -> void:
	_hex_grid_view.load_combatants([
		CombatantClass.new("defender-1", "Titus", "Player", HexCoordClass.new(1, 2)),
	])

	var resolved: String = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(5, 5))

	assert_eq(
		resolved, "",
		"get_combatant_id_at_hex must return \"\" (never null, never throw) for a hex with no token"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — first match wins under deterministic ordering.
# ══════════════════════════════════════════════════════════════════════════

func test_returns_first_match_when_multiple_tokens_share_a_hex() -> void:
	# Two tokens deliberately placed on the SAME hex -- an edge case the
	# design notes' "first match" contract exists to resolve
	# deterministically rather than leaving unspecified. `_tokens` is a
	# Dictionary keyed by combatant_id; Godot Dictionaries preserve
	# insertion order, so load_combatants()'s own iteration order over its
	# `combatants` argument is what determines "first".
	_hex_grid_view.load_combatants([
		CombatantClass.new("first-occupant", "Titus", "Player", HexCoordClass.new(3, -1)),
		CombatantClass.new("second-occupant", "Marcus", "Enemy", HexCoordClass.new(3, -1)),
	])

	var resolved: String = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(3, -1))

	assert_eq(
		resolved, "first-occupant",
		"get_combatant_id_at_hex must deterministically return the FIRST matching token's combatant_id"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — never throws on an empty _tokens array/Dictionary.
# ══════════════════════════════════════════════════════════════════════════

func test_never_throws_on_empty_tokens() -> void:
	assert_eq(_hex_grid_view.get_token_count(), 0, "sanity check: no tokens loaded yet")

	var resolved: String = _hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(0, 0))

	assert_eq(
		resolved, "",
		"get_combatant_id_at_hex must return \"\" (not throw) when _tokens is empty"
	)
