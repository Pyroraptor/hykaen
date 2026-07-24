extends GutTest
## tests/unit/presentation/test_hex_grid_view_remove_combatants.gd
##
## GUT test suite for FEAT-009 (US-008 / FR-007): HexGridView.remove_combatants()
## — the mirror operation to add_combatants() (FEAT-008), used by MainScene's
## post-combat exploration-return handoff (_on_combat_won()) to strip a
## just-won encounter's enemy tokens off the battlefield without touching any
## other on-screen token.
##
## Verifies:
##   1. remove_combatants() frees the token(s) for the given ids and
##      get_token() subsequently returns null for them.
##   2. remove_combatants() leaves every OTHER already-tracked token
##      completely untouched (position, existence).
##   3. get_token_count() drops by exactly the number of ids removed.
##   4. An unknown/stale combatant_id is a silent no-op — never a crash,
##      mirroring this view's established "never raises/throws" convention.

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

var _hex_grid_view = null


func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)
	_hex_grid_view.load_combatants([
		CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0)),
		CombatantClass.new("player_1", "Marigold", "Player", HexCoordClass.new(-1, 0)),
	])
	_hex_grid_view.add_combatants([
		CombatantClass.new("enemy_0", "Skeleton", "Enemy", HexCoordClass.new(3, 0)),
	])


func test_remove_combatants_frees_the_named_token() -> void:
	_hex_grid_view.remove_combatants(["enemy_0"])

	assert_null(_hex_grid_view.get_token("enemy_0"), "the removed combatant_id must have no token on record afterward")


func test_remove_combatants_leaves_other_tokens_untouched() -> void:
	var titus_position_before: Vector2 = _hex_grid_view.get_token("player_0").position
	var marigold_position_before: Vector2 = _hex_grid_view.get_token("player_1").position

	_hex_grid_view.remove_combatants(["enemy_0"])

	assert_not_null(_hex_grid_view.get_token("player_0"), "an unrelated token must remain on record")
	assert_eq(_hex_grid_view.get_token("player_0").position, titus_position_before, "an unrelated token's position must be unaffected")
	assert_not_null(_hex_grid_view.get_token("player_1"), "an unrelated token must remain on record")
	assert_eq(_hex_grid_view.get_token("player_1").position, marigold_position_before, "an unrelated token's position must be unaffected")


func test_remove_combatants_decrements_token_count_by_exactly_the_removed_count() -> void:
	var count_before: int = _hex_grid_view.get_token_count()

	_hex_grid_view.remove_combatants(["enemy_0"])

	assert_eq(_hex_grid_view.get_token_count(), count_before - 1, "get_token_count() must drop by exactly the number of ids removed")


func test_remove_combatants_unknown_combatant_id_does_not_crash_and_leaves_tokens_untouched() -> void:
	var count_before: int = _hex_grid_view.get_token_count()

	_hex_grid_view.remove_combatants(["no_such_combatant"])

	# no crash -- reaching this line is part of the assertion.
	assert_eq(_hex_grid_view.get_token_count(), count_before, "an unknown combatant_id must be a silent no-op, never removing an unrelated token")
