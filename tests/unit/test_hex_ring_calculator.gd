extends GutTest
## tests/unit/test_hex_ring_calculator.gd
##
## GUT test suite for FEAT-002 (US-003 / US-004): core/domain/
## hex_ring_calculator.gd's HexRingCalculator domain service, plus
## core/domain/trigger_type.gd's TriggerType constants — both foundational,
## pure-domain pieces this feature adds together (per the feature's design
## notes, TriggerType exists so US-001/US-003 never hardcode the
## "PROXIMITY" magic string in more than one place).
##
## Verifies (this feature's test_criteria):
##   1. HexRingCalculator.ring(HexCoord.new(0,0), 2).size() == 12 — the
##      distance-2 hex ring cardinality (6 * radius).
##   2. Every returned hex is at HexMath.hex_distance() == 2 from the
##      center exactly — no radius-1 (interior) or radius-3 (bounding-box
##      corner) leakage.
##   3. ring(center, 0) returns an empty array (edge case — a distance-0
##      "ring" is degenerate, not [center]).
##   4. Static source-inspection check: hex_ring_calculator.gd contains no
##      'extends Node' / 'extends Resource' / presentation-layer imports
##      (ADR-001 domain purity).
##   5. TriggerType.PROXIMITY / TriggerType.DIALOGUE are the expected
##      string constants (the small value object this feature adds
##      alongside HexRingCalculator).

const HexRingCalculatorClass = preload("res://core/domain/hex_ring_calculator.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const TriggerTypeClass = preload("res://core/domain/trigger_type.gd")

const HEX_RING_CALCULATOR_PATH: String = "res://core/domain/hex_ring_calculator.gd"


# ── Criterion 1: distance-2 ring cardinality ─────────────────────────────────

func test_ring_radius_2_has_12_hexes() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, 2)
	assert_eq(result.size(), 12, "A distance-2 hex ring must contain exactly 12 hexes (6 * radius)")


func test_ring_radius_1_has_6_hexes() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, 1)
	assert_eq(result.size(), 6, "A distance-1 hex ring must contain exactly 6 hexes")


func test_ring_off_origin_center_has_correct_cardinality() -> void:
	var center = HexCoordClass.new(3, -2)
	var result: Array = HexRingCalculatorClass.ring(center, 2)
	assert_eq(result.size(), 12, "Ring cardinality must not depend on the center hex's own coordinates")


# ── Criterion 2: every returned hex is at EXACTLY the requested distance ────

func test_every_ring_hex_is_at_exact_distance_no_leakage() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, 2)
	for hex_coord in result:
		assert_eq(
			HexMathClass.hex_distance(hex_coord, center), 2,
			"Every hex returned by ring(center, 2) must be at distance exactly 2 (no radius-1/radius-3 leakage): got %s" % hex_coord
		)


func test_ring_contains_no_duplicate_hexes() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, 2)
	var seen: Dictionary = {}
	for hex_coord in result:
		var key: String = "%d,%d" % [hex_coord.q, hex_coord.r]
		assert_false(seen.has(key), "ring() must not return duplicate hexes: %s appeared more than once" % key)
		seen[key] = true


# ── Criterion 3: radius 0 edge case ──────────────────────────────────────────

func test_ring_radius_zero_returns_empty_array() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, 0)
	assert_eq(result.size(), 0, "ring(center, 0) must return an empty array, not [center]")


func test_ring_negative_radius_returns_empty_array() -> void:
	var center = HexCoordClass.new(0, 0)
	var result: Array = HexRingCalculatorClass.ring(center, -1)
	assert_eq(result.size(), 0, "ring(center, negative) must return an empty array")


# ── Criterion 4: static check — domain purity (ADR-001) ──────────────────────

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the ADR-001 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_or_resource_inheritance() -> void:
	var content: String = _read_source(HEX_RING_CALCULATOR_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "hex_ring_calculator.gd must not extend Node (ADR-001)")
	assert_false(content.contains("extends Resource"), "hex_ring_calculator.gd must not extend Resource (ADR-001)")
	assert_false(content.contains("extends Control"), "hex_ring_calculator.gd must not extend Control (ADR-001)")
	assert_false(content.contains("extends CanvasItem"), "hex_ring_calculator.gd must not extend CanvasItem (ADR-001)")


func test_source_has_no_presentation_imports() -> void:
	var content: String = _read_source(HEX_RING_CALCULATOR_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("res://presentation/"), "hex_ring_calculator.gd must not import presentation/ (ADR-001)")
	assert_false(content.contains("preload(\"res://MainScene"), "hex_ring_calculator.gd must not import MainScene (ADR-001)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(HEX_RING_CALCULATOR_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "hex_ring_calculator.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "hex_ring_calculator.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"hex_ring_calculator.gd must not define _physics_process() (ADR-001)"
	)


# ── Criterion 5: TriggerType constants ───────────────────────────────────────

func test_trigger_type_proximity_constant() -> void:
	assert_eq(TriggerTypeClass.PROXIMITY, "PROXIMITY", "TriggerType.PROXIMITY must be the string 'PROXIMITY'")


func test_trigger_type_dialogue_constant_reserved() -> void:
	assert_eq(TriggerTypeClass.DIALOGUE, "DIALOGUE", "TriggerType.DIALOGUE must be the string 'DIALOGUE' (reserved)")
