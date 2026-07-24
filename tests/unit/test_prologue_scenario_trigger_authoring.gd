extends GutTest
## tests/unit/test_prologue_scenario_trigger_authoring.gd
##
## GUT unit tests for FEAT-004 (US-003 / FR-008):
## tools/authoring/author_prologue_trigger.gd's authored output on
## data/scenarios/prologue_scenario.tres, plus a regression proof that
## running the authoring script's (pure, read-only) computation never
## mutates data/encounters/prologue_encounter.tres.
##
## Test criteria covered:
##   1. ResourceLoader.load('res://data/scenarios/prologue_scenario.tres')
##      succeeds.
##   2. entries[0].trigger is a ProximityTriggerResource with
##      trigger_type == 'PROXIMITY' and trigger_hexes.size() >= 1
##      (referential completeness per the data-model integrity rule).
##   3. Every hex in entries[0].trigger.trigger_hexes has
##      HexMath.hex_distance() == 2 from the enemy start hex read out of
##      prologue_encounter.tres.
##   4. Byte-diff check: prologue_encounter.tres is unchanged (checksum
##      comparison before vs. after re-running the authoring script's
##      computation).

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const ProximityTriggerResourceClass = preload("res://data/triggers/proximity_trigger_resource.gd")
const AuthorPrologueTriggerClass = preload("res://tools/authoring/author_prologue_trigger.gd")

const PROLOGUE_SCENARIO_PATH := "res://data/scenarios/prologue_scenario.tres"
const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"


func _read_file_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _load_enemy_start_hex():
	var encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(encounter, "prologue_encounter.tres must load")
	if encounter == null:
		return null
	assert_true(
		encounter.enemy_hex_positions.size() >= 1,
		"prologue_encounter.tres must have at least one enemy_hex_position"
	)
	if encounter.enemy_hex_positions.is_empty():
		return null
	var start_dict = encounter.enemy_hex_positions[0]
	return HexCoordClass.new(int(start_dict["q"]), int(start_dict["r"]))


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: prologue_scenario.tres loads successfully
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_scenario_loads_successfully() -> void:
	assert_true(
		ResourceLoader.exists(PROLOGUE_SCENARIO_PATH),
		"data/scenarios/prologue_scenario.tres must exist"
	)
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "prologue_scenario.tres must load without error")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: entries[0].trigger is a well-formed ProximityTriggerResource
# ══════════════════════════════════════════════════════════════════════════════

func test_entry_trigger_is_proximity_trigger_with_at_least_one_hex() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario)
	if scenario == null:
		return

	assert_true(
		scenario.encounter_entries.size() >= 1,
		"prologue_scenario.tres must have at least one encounter entry"
	)
	if scenario.encounter_entries.is_empty():
		return

	var trigger = scenario.encounter_entries[0].trigger
	assert_not_null(trigger, "entries[0].trigger must be non-null")
	if trigger == null:
		return

	assert_is(
		trigger, ProximityTriggerResourceClass,
		"entries[0].trigger must be a ProximityTriggerResource"
	)
	assert_eq(trigger.trigger_type, "PROXIMITY", "entries[0].trigger.trigger_type must be 'PROXIMITY'")
	assert_true(
		trigger.trigger_hexes.size() >= 1,
		"entries[0].trigger.trigger_hexes must have at least 1 hex (referential completeness)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: every trigger hex is at exactly distance 2 from the enemy
# start hex read out of prologue_encounter.tres
# ══════════════════════════════════════════════════════════════════════════════

func test_every_trigger_hex_is_distance_2_from_enemy_start_hex() -> void:
	var enemy_start_hex = _load_enemy_start_hex()
	if enemy_start_hex == null:
		return

	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario)
	if scenario == null:
		return
	if scenario.encounter_entries.is_empty():
		assert_true(false, "prologue_scenario.tres must have at least one encounter entry")
		return

	var trigger = scenario.encounter_entries[0].trigger
	assert_not_null(trigger)
	if trigger == null:
		return

	assert_true(trigger.trigger_hexes.size() >= 1, "trigger_hexes must not be empty")

	for hex_dict in trigger.trigger_hexes:
		var hex_coord := HexCoordClass.new(int(hex_dict["q"]), int(hex_dict["r"]))
		assert_eq(
			HexMathClass.hex_distance(hex_coord, enemy_start_hex), 2,
			"trigger hex (q=%d, r=%d) must be at distance 2 from the enemy start hex" % [hex_coord.q, hex_coord.r]
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: byte-diff check — prologue_encounter.tres is unchanged by
# re-running the authoring script's (pure, read-only) computation
# ══════════════════════════════════════════════════════════════════════════════

func test_prologue_encounter_bytes_unchanged_by_authoring_computation() -> void:
	var before_bytes := _read_file_bytes(PROLOGUE_ENCOUNTER_PATH)
	assert_true(before_bytes.size() > 0, "prologue_encounter.tres must be readable")

	# Re-run the authoring script's computation (read the encounter's enemy
	# start hex + compute the trigger ring) against the CURRENT on-disk
	# files. author_prologue_trigger.gd's static helpers perform no file
	# I/O at all, so this can never mutate prologue_encounter.tres --
	# proving the "byte-unchanged" constraint holds for the actual
	# computation the authoring script runs, not just by omission.
	var enemy_start_hex = _load_enemy_start_hex()
	if enemy_start_hex != null:
		var trigger = AuthorPrologueTriggerClass.build_proximity_trigger(enemy_start_hex)
		assert_not_null(trigger, "build_proximity_trigger must return a ProximityTriggerResource")

	var after_bytes := _read_file_bytes(PROLOGUE_ENCOUNTER_PATH)
	assert_eq(
		before_bytes.size(), after_bytes.size(),
		"prologue_encounter.tres byte length must be unchanged after the authoring computation runs"
	)
	assert_eq(
		before_bytes.hex_encode(), after_bytes.hex_encode(),
		"prologue_encounter.tres bytes must be byte-identical (checksum match) after the authoring computation runs"
	)
