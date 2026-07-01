extends GutTest
## tests/unit/presentation/test_hex_grid_view_mapping.gd
##
## GUT test suite for FEAT-007 / US-005 — HexGridView renders the flat-top
## hex battlefield and instantiates a CombatantTokenView per combatant.
##
## Verifies:
##   1. HexGridView.axial_to_pixel() produces expected screen coordinates for
##      a set of sample hex_coords (flat-top formula, ADR-004).
##   2. Runtime: instantiating HexGridView and calling load_combatants() with
##      the combatants loaded from data/encounters/prologue_encounter.tres
##      (via infrastructure/resource_encounter_repository.gd) produces
##      exactly one CombatantTokenView child per combatant.
##   3. Each instantiated CombatantTokenView is positioned at its
##      combatant's mapped screen position (axial_to_pixel(hex_coord)).
##   4. CombatantTokenView.set_combatant() carries over combatant_id/name/team.

const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const CombatantTokenViewClass: GDScript = preload("res://presentation/combatant_token_view.gd")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const ResourceEncounterRepositoryClass: GDScript = preload("res://infrastructure/resource_encounter_repository.gd")

const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## Tolerance for floating-point pixel comparisons.
const EPSILON: float = 0.01


# ── Criterion 1: axial-to-pixel mapping (flat-top formula, ADR-004) ─────────

func test_axial_to_pixel_origin_maps_to_zero() -> void:
	var pixel: Vector2 = HexGridViewClass.axial_to_pixel(HexCoordClass.new(0, 0), 48.0)
	assert_almost_eq(pixel, Vector2(0.0, 0.0), Vector2(EPSILON, EPSILON))


func test_axial_to_pixel_matches_flat_top_formula_for_sample_coords() -> void:
	# Each sample: [q, r, expected_x, expected_y] for hex_size = 48.0, using
	# the flat-top axial formula: x = size*(3/2*q), y = size*(sqrt(3)/2*q + sqrt(3)*r)
	var samples: Array = [
		[1, 0, 72.0, 41.5692],
		[0, 1, 0.0, 83.1384],
		[1, -1, 72.0, -41.5692],
		[-1, 0, -72.0, -41.5692],
		[2, -1, 144.0, 0.0],
		[-2, 1, -144.0, 0.0],
	]
	for sample in samples:
		var coord = HexCoordClass.new(sample[0], sample[1])
		var expected := Vector2(sample[2], sample[3])
		var pixel: Vector2 = HexGridViewClass.axial_to_pixel(coord, 48.0)
		assert_almost_eq(
			pixel, expected, Vector2(EPSILON, EPSILON),
			"axial_to_pixel(q=%d, r=%d) must match the flat-top formula" % [sample[0], sample[1]]
		)


func test_axial_to_pixel_defaults_hex_size_to_hex_size_constant() -> void:
	var coord = HexCoordClass.new(1, 0)
	var default_pixel: Vector2 = HexGridViewClass.axial_to_pixel(coord)
	var explicit_pixel: Vector2 = HexGridViewClass.axial_to_pixel(coord, HexGridViewClass.HEX_SIZE)
	assert_almost_eq(
		default_pixel, explicit_pixel, Vector2(EPSILON, EPSILON),
		"axial_to_pixel() with no hex_size argument must use the HEX_SIZE constant"
	)


# ── Criteria 2-4: runtime token instantiation from the prologue encounter ───

var _combatants: Array = []
var _hex_grid_view = null


func before_each() -> void:
	var repo = ResourceEncounterRepositoryClass.new()
	_combatants = repo.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	var packed: PackedScene = HexGridViewScene
	_hex_grid_view = packed.instantiate()
	add_child_autofree(_hex_grid_view)


func test_prologue_encounter_yields_at_least_one_combatant() -> void:
	assert_true(_combatants.size() > 0, "prologue_encounter.tres must yield at least one combatant")


func test_load_combatants_instantiates_one_token_per_combatant() -> void:
	_hex_grid_view.load_combatants(_combatants)
	assert_eq(
		_hex_grid_view.get_token_count(), _combatants.size(),
		"HexGridView must instantiate exactly one CombatantTokenView per loaded combatant"
	)


func test_load_combatants_child_count_matches_combatant_count() -> void:
	_hex_grid_view.load_combatants(_combatants)
	var token_children: int = 0
	for child in _hex_grid_view.get_children():
		if child is CombatantTokenViewClass:
			token_children += 1
	assert_eq(
		token_children, _combatants.size(),
		"HexGridView must have exactly one CombatantTokenView child per loaded combatant"
	)


func test_load_combatants_reload_does_not_leak_duplicate_tokens() -> void:
	_hex_grid_view.load_combatants(_combatants)
	_hex_grid_view.load_combatants(_combatants)
	assert_eq(
		_hex_grid_view.get_token_count(), _combatants.size(),
		"A second load_combatants() call must not leak duplicate tokens"
	)


func test_each_token_is_positioned_at_its_combatants_mapped_screen_position() -> void:
	_hex_grid_view.load_combatants(_combatants)
	for combatant in _combatants:
		var token = _hex_grid_view.get_token(combatant.combatant_id)
		assert_not_null(token, "get_token() must return the instantiated token for combatant_id=%s" % combatant.combatant_id)
		if token == null:
			continue
		var expected_position: Vector2 = HexGridViewClass.axial_to_pixel(combatant.hex_coord)
		assert_almost_eq(
			token.position, expected_position, Vector2(EPSILON, EPSILON),
			"Token for %s must be positioned at axial_to_pixel(hex_coord)" % combatant.combatant_id
		)


func test_each_token_carries_over_combatant_identity_fields() -> void:
	_hex_grid_view.load_combatants(_combatants)
	for combatant in _combatants:
		var token = _hex_grid_view.get_token(combatant.combatant_id)
		if token == null:
			fail_test("missing token for combatant_id=%s" % combatant.combatant_id)
			continue
		assert_eq(token.combatant_id, combatant.combatant_id, "token.combatant_id must match the source combatant")
		assert_eq(token.display_name, combatant.name, "token.display_name must match the source combatant's name")
		assert_eq(token.team, combatant.team, "token.team must match the source combatant's team")


func test_token_count_equals_prologue_party_plus_enemy_count() -> void:
	var encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	assert_not_null(encounter_resource, "prologue_encounter.tres must load")
	if encounter_resource == null:
		return
	var expected_count: int = (
		encounter_resource.party_resource_paths.size()
		+ encounter_resource.enemy_resource_paths.size()
	)
	_hex_grid_view.load_combatants(_combatants)
	assert_eq(
		_hex_grid_view.get_token_count(), expected_count,
		"Instantiated token count must equal prologue_encounter.tres's party+enemy count"
	)
