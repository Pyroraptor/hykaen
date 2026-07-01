extends GutTest
## tests/unit/core/domain/test_combatant_hex_init.gd
##
## GUT test suite for FEAT-001 / US-001 — Combatant.hex_coord initialization
## via infrastructure/resource_encounter_repository.gd loading
## data/encounters/prologue_encounter.tres.
##
## Verifies:
##   1. ResourceEncounterRepository.load_combatants() returns Combatant
##      instances for every party member + enemy authored in
##      prologue_encounter.tres.
##   2. Every Combatant.hex_coord is a HexCoord instance (never a raw
##      Dictionary/Array).
##   3. Combatant.hex_coord values match the authored party_hex_positions /
##      enemy_hex_positions in prologue_encounter.tres exactly.
##   4. Static source-inspection check (ADR-001): combatant.gd contains no
##      Node/Control/CanvasItem inheritance and no engine lifecycle
##      callbacks (_ready/_process/_physics_process).

const ResourceEncounterRepositoryClass: GDScript = preload("res://infrastructure/resource_encounter_repository.gd")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const CombatantClass: GDScript = preload("res://core/domain/combatant.gd")

const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"
const COMBATANT_PATH: String = "res://core/domain/combatant.gd"

var _encounter_resource = null
var _combatants: Array = []


func before_all() -> void:
	_encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	var repo = ResourceEncounterRepositoryClass.new()
	_combatants = repo.load_combatants(PROLOGUE_ENCOUNTER_PATH)


# ── Criterion 1: repository yields one Combatant per authored member ────────

func test_prologue_encounter_resource_loads_non_null() -> void:
	assert_not_null(
		_encounter_resource,
		"data/encounters/prologue_encounter.tres must load via ResourceLoader"
	)


func test_repository_returns_one_combatant_per_party_and_enemy_entry() -> void:
	if _encounter_resource == null:
		fail_test("prologue_encounter.tres failed to load — cannot verify combatant count")
		return
	var expected_count: int = (
		_encounter_resource.party_resource_paths.size()
		+ _encounter_resource.enemy_resource_paths.size()
	)
	assert_eq(
		_combatants.size(), expected_count,
		"ResourceEncounterRepository must return one Combatant per authored party/enemy entry"
	)


func test_repository_returns_combatant_instances() -> void:
	assert_true(_combatants.size() > 0, "prologue_encounter.tres must yield at least one combatant")
	for c in _combatants:
		assert_true(c is CombatantClass, "each loaded entry must be a Combatant instance")


# ── Criterion 2: hex_coord is a HexCoord instance ────────────────────────────

func test_every_combatant_hex_coord_is_hexcoord_instance() -> void:
	assert_true(_combatants.size() > 0, "prologue_encounter.tres must yield at least one combatant")
	for c in _combatants:
		assert_true(
			c.hex_coord is HexCoordClass,
			"Combatant.hex_coord must be a HexCoord instance, not a raw Dictionary/Array"
		)


# ── Criterion 3: hex_coord values match authored .tres data ─────────────────

func test_party_combatant_hex_coord_matches_authored_tres_values() -> void:
	if _encounter_resource == null:
		fail_test("prologue_encounter.tres failed to load — cannot verify authored hex values")
		return
	var party_positions: Array = _encounter_resource.party_hex_positions
	assert_true(party_positions.size() > 0, "prologue_encounter.tres must author party_hex_positions")
	if party_positions.is_empty():
		return

	var first_party = _combatants[0]
	assert_eq(first_party.team, "Player", "First loaded combatant must be tagged team=Player")
	assert_eq(
		first_party.hex_coord.q, int(party_positions[0].get("q", -999)),
		"Party combatant hex_coord.q must match prologue_encounter.tres party_hex_positions[0].q"
	)
	assert_eq(
		first_party.hex_coord.r, int(party_positions[0].get("r", -999)),
		"Party combatant hex_coord.r must match prologue_encounter.tres party_hex_positions[0].r"
	)


func test_enemy_combatant_hex_coord_matches_authored_tres_values() -> void:
	if _encounter_resource == null:
		fail_test("prologue_encounter.tres failed to load — cannot verify authored hex values")
		return
	var enemy_positions: Array = _encounter_resource.enemy_hex_positions
	assert_true(enemy_positions.size() > 0, "prologue_encounter.tres must author enemy_hex_positions")
	if enemy_positions.is_empty():
		return

	var party_count: int = _encounter_resource.party_resource_paths.size()
	var first_enemy = _combatants[party_count]
	assert_eq(first_enemy.team, "Enemy", "First enemy combatant must be tagged team=Enemy")
	assert_eq(
		first_enemy.hex_coord.q, int(enemy_positions[0].get("q", -999)),
		"Enemy combatant hex_coord.q must match prologue_encounter.tres enemy_hex_positions[0].q"
	)
	assert_eq(
		first_enemy.hex_coord.r, int(enemy_positions[0].get("r", -999)),
		"Enemy combatant hex_coord.r must match prologue_encounter.tres enemy_hex_positions[0].r"
	)


# ── Criterion 4: static check — no Node/Control/engine-lifecycle (ADR-001) ──

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the ADR-001 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_control_inheritance() -> void:
	var content: String = _read_source(COMBATANT_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "combatant.gd must not extend Node (ADR-001)")
	assert_false(content.contains("extends Control"), "combatant.gd must not extend Control (ADR-001)")
	assert_false(content.contains("extends CanvasItem"), "combatant.gd must not extend CanvasItem (ADR-001)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(COMBATANT_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "combatant.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "combatant.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"combatant.gd must not define _physics_process() (ADR-001)"
	)
