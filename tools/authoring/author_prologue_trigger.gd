## tools/authoring/author_prologue_trigger.gd — one-off authoring script
## (FEAT-004 / US-003, FR-008)
##
## Reads the skeleton enemy's start hex out of the READ-ONLY
## data/encounters/prologue_encounter.tres, uses HexRingCalculator
## (FEAT-002) to compute the distance-2 ring around it, and attaches a
## ProximityTriggerResource (defaulting trigger_type='PROXIMITY' via
## FEAT-001's ProximityTriggerResource._init()) populated with those
## trigger_hexes to data/scenarios/prologue_scenario.tres's single
## encounter entry.
##
## This drives the computation via a script rather than hand-typing the
## 12-hex ring literal into the .tres by hand, so it is reproducible and
## independently testable (tests/unit/test_prologue_scenario_trigger_
## authoring.gd calls the static helpers below directly, without booting
## this file as a SceneTree main loop).
##
## Architecture note (Clean Architecture / ADR-001): this is a dev-only
## authoring TOOL (tools/, not shipped in the running game), analogous to
## tools/sim_demo.gd. Its pure computation (hex_dicts_for_ring /
## build_proximity_trigger) is extracted into static funcs with no engine
## I/O so it can be exercised in isolation; only _init() (the SceneTree
## entry point invoked by `godot -s`) performs file I/O
## (ResourceLoader.load / ResourceSaver.save), and it NEVER writes to
## prologue_encounter.tres — only reads it.
##
## Usage (re-run only if prologue_encounter.tres's enemy start hex ever
## changes; the output is committed, not regenerated on every build):
##   godot --headless --path . -s tools/authoring/author_prologue_trigger.gd

extends SceneTree

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexRingCalculatorClass = preload("res://core/domain/hex_ring_calculator.gd")
const ProximityTriggerResourceClass = preload("res://data/triggers/proximity_trigger_resource.gd")

const PROLOGUE_ENCOUNTER_PATH := "res://data/encounters/prologue_encounter.tres"
const PROLOGUE_SCENARIO_PATH := "res://data/scenarios/prologue_scenario.tres"

## Trigger fires when the party enters the ring exactly 2 hexes out from
## the enemy's starting position (per US-003 / FR-008).
const TRIGGER_RADIUS := 2


## hex_dicts_for_ring(center, radius) → Array of {"q": int, "r": int} —
## pure computation: HexRingCalculator.ring()'s HexCoord results,
## converted to the Dictionary shape ProximityTriggerResource.trigger_hexes
## expects (see data/triggers/proximity_trigger_resource.gd). No file I/O.
static func hex_dicts_for_ring(center, radius: int) -> Array:
	var result: Array = []
	for hex_coord in HexRingCalculatorClass.ring(center, radius):
		result.append({"q": hex_coord.q, "r": hex_coord.r})
	return result


## build_proximity_trigger(enemy_start_hex) → ProximityTriggerResource —
## pure construction of the trigger resource this script attaches to the
## scenario's first encounter entry. No file I/O.
static func build_proximity_trigger(enemy_start_hex) -> ProximityTriggerResource:
	var trigger := ProximityTriggerResourceClass.new()
	trigger.trigger_hexes = hex_dicts_for_ring(enemy_start_hex, TRIGGER_RADIUS)
	return trigger


func _init() -> void:
	# Read-only load of prologue_encounter.tres -- this script must NEVER
	# write to it (US-003's "byte-unchanged" constraint).
	var encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	if encounter == null:
		push_error("author_prologue_trigger: failed to load %s" % PROLOGUE_ENCOUNTER_PATH)
		quit(1)
		return
	if encounter.enemy_hex_positions.is_empty():
		push_error("author_prologue_trigger: %s has no enemy_hex_positions" % PROLOGUE_ENCOUNTER_PATH)
		quit(1)
		return

	var start_dict = encounter.enemy_hex_positions[0]
	var enemy_start_hex := HexCoordClass.new(int(start_dict["q"]), int(start_dict["r"]))

	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	if scenario == null:
		push_error("author_prologue_trigger: failed to load %s" % PROLOGUE_SCENARIO_PATH)
		quit(1)
		return
	if scenario.encounter_entries.is_empty():
		push_error("author_prologue_trigger: %s has no encounter_entries" % PROLOGUE_SCENARIO_PATH)
		quit(1)
		return

	scenario.encounter_entries[0].trigger = build_proximity_trigger(enemy_start_hex)

	var save_err := ResourceSaver.save(scenario, PROLOGUE_SCENARIO_PATH)
	if save_err != OK:
		push_error(
			"author_prologue_trigger: failed to save %s (error %d)" % [PROLOGUE_SCENARIO_PATH, save_err]
		)
		quit(1)
		return

	print(
		"author_prologue_trigger: attached ProximityTriggerResource with %d trigger_hexes to %s"
		% [scenario.encounter_entries[0].trigger.trigger_hexes.size(), PROLOGUE_SCENARIO_PATH]
	)
	quit(0)
