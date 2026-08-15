extends GutTest
## tests/unit/combat/test_mindless_ai.gd
##
## GUT unit test suite for FEAT-003 (US-003 / FR-010): the DOMAIN-layer
## core/combat/mindless_ai.gd baseline AI planner.
##
## Verifies (this feature's test_criteria):
##   1. Adjacent target -> plan is exactly [Strike].
##   2. Non-adjacent target -> plan is exactly [Stride, Strike], where the
##      Stride destination is one of Movement.get_stride_destinations()'s
##      legal candidates.
##   3. No living targets -> plan is [] (a first-class WAIT, not an error).
##   4. Two equidistant targets are resolved via the SAME stable
##      lowest-(q, r) tie-break rule core/combat/ai.gd already established
##      — deterministic, no RNG.
##   5. Static check: core/combat/mindless_ai.gd contains no
##      import/reference to core/combat/ai.gd (clean-room domain service,
##      per the design note — MindlessAI never imports the frozen ai.gd).
##
## Satisfies: FEAT-003, US-003, FR-010.

const MindlessAIClass = preload("res://core/combat/mindless_ai.gd")
const HexCoordClass   = preload("res://core/geometry/hex_coord.gd")
const MovementClass   = preload("res://core/rules/movement.gd")

const MINDLESS_AI_PATH := "res://core/combat/mindless_ai.gd"


func _combatant(name: String, hex_coord, hp: int = 10) -> Dictionary:
	return {"name": name, "hp_current": hp, "hex_coord": hex_coord}


func _world_context(party: Array, enemies: Array = []) -> Dictionary:
	return {"party": party, "enemies": enemies, "action_economy": null}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: adjacent target -> plan is exactly [Strike]
# ══════════════════════════════════════════════════════════════════════════

func test_adjacent_target_plan_is_exactly_strike() -> void:
	var ai := MindlessAIClass.new()
	var combatant: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var target: Dictionary = _combatant("Titus", HexCoordClass.new(1, 0))

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))

	assert_eq(plan.size(), 1, "an adjacent target must yield a single-item plan")
	assert_eq(plan[0].get("action_type", ""), "Strike", "the single plan item must be a Strike")
	assert_eq(plan[0].get("target", null), target, "the Strike must target the adjacent living combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: non-adjacent target -> plan is exactly [Stride, Strike] using
# Movement.get_stride_destinations()
# ══════════════════════════════════════════════════════════════════════════

func test_non_adjacent_target_plan_is_exactly_stride_then_strike() -> void:
	var ai := MindlessAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Skeleton", origin_hex)
	var target_hex = HexCoordClass.new(6, 0)
	var target: Dictionary = _combatant("Titus", target_hex)

	var expected_destinations: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [target])
	assert_false(expected_destinations.is_empty(), "fixture assumption: at least one legal Stride destination must exist")

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))

	assert_eq(plan.size(), 2, "an out-of-reach target must yield a two-item plan")
	assert_eq(plan[0].get("action_type", ""), "Stride", "the first plan item must be a Stride")
	assert_eq(plan[1].get("action_type", ""), "Strike", "the second plan item must be a Strike")
	assert_eq(plan[1].get("target", null), target, "the Strike must target the same combatant the Stride closed on")

	var destination = plan[0].get("destination", null)
	assert_not_null(destination, "the Stride plan item must carry a non-null destination")

	var is_legal: bool = false
	for candidate in expected_destinations:
		if candidate.equals(destination):
			is_legal = true
			break
	assert_true(is_legal, "the chosen Stride destination must be one of Movement.get_stride_destinations()'s legal candidates")


func test_non_adjacent_target_stride_destination_reduces_distance() -> void:
	var ai := MindlessAIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _combatant("Skeleton", origin_hex)
	var target_hex = HexCoordClass.new(6, 0)
	var target: Dictionary = _combatant("Titus", target_hex)

	var plan: Array = ai.plan_turn(combatant, _world_context([target]))
	var destination = plan[0].get("destination", null)

	var HexMathClass = preload("res://core/geometry/hex_math.gd")
	var original_distance: int = HexMathClass.hex_distance(origin_hex, target_hex)
	var new_distance: int = HexMathClass.hex_distance(destination, target_hex)
	assert_true(new_distance < original_distance, "the chosen Stride destination must strictly reduce hex_distance to the target")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: no living targets -> plan is []
# ══════════════════════════════════════════════════════════════════════════

func test_no_living_targets_plan_is_empty() -> void:
	var ai := MindlessAIClass.new()
	var combatant: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var dead_target: Dictionary = _combatant("Titus", HexCoordClass.new(1, 0), 0)

	var plan: Array = ai.plan_turn(combatant, _world_context([dead_target]))

	assert_eq(plan, [], "no living targets must yield an empty (WAIT) plan")


func test_empty_party_plan_is_empty() -> void:
	var ai := MindlessAIClass.new()
	var combatant: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))

	var plan: Array = ai.plan_turn(combatant, _world_context([]))

	assert_eq(plan, [], "an empty party (no targets at all) must yield an empty (WAIT) plan")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: two equidistant targets resolved via (q, r) tie-break
# deterministically
# ══════════════════════════════════════════════════════════════════════════

func test_equidistant_targets_resolved_via_lower_qr_tie_break() -> void:
	var ai := MindlessAIClass.new()
	var combatant: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))

	# Both (1, 0) and (0, 1) are adjacent (hex_distance == 1) to (0, 0) --
	# an exact tie. (0, 1) sorts lower than (1, 0) under (q, r) lexicographic
	# order (0 < 1 on q), so it must be the deterministically chosen target.
	var target_high_q: Dictionary = _combatant("HighQ", HexCoordClass.new(1, 0))
	var target_low_q: Dictionary = _combatant("LowQ", HexCoordClass.new(0, 1))

	var plan: Array = ai.plan_turn(combatant, _world_context([target_high_q, target_low_q]))

	assert_eq(plan.size(), 1, "both equidistant targets are adjacent, so the plan must be a single Strike")
	assert_eq(plan[0].get("action_type", ""), "Strike")
	assert_eq(plan[0].get("target", null), target_low_q, "the lower-(q, r) target must be deterministically chosen on a tie")


func test_equidistant_targets_tie_break_is_order_independent() -> void:
	var ai := MindlessAIClass.new()
	var combatant: Dictionary = _combatant("Skeleton", HexCoordClass.new(0, 0))
	var target_high_q: Dictionary = _combatant("HighQ", HexCoordClass.new(1, 0))
	var target_low_q: Dictionary = _combatant("LowQ", HexCoordClass.new(0, 1))

	# Reversed input order must not change the deterministic outcome.
	var plan: Array = ai.plan_turn(combatant, _world_context([target_low_q, target_high_q]))

	assert_eq(plan[0].get("target", null), target_low_q, "the tie-break outcome must not depend on input array order")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: mindless_ai.gd contains no import/reference to
# core/combat/ai.gd (clean-room domain service)
# ══════════════════════════════════════════════════════════════════════════

## Strips full-line `##`/`#` doc/line comments so the coupling check below
## looks only at executable code (extends/preload/class_name/type
## references), not prose that merely *discusses* the sibling legacy module
## for documentation purposes (e.g. this feature's own file-level doc
## explaining that MindlessAI is a clean-room reimplementation of, and
## deliberately never imports, ai.gd). Mirrors
## tests/unit/application/test_ai_planner_port.gd's identically-named
## helper/convention.
func _non_comment_lines(source: String) -> String:
	var kept: PackedStringArray = []
	for raw_line in source.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(raw_line)
	return "\n".join(kept)


func test_mindless_ai_does_not_reference_legacy_ai_gd() -> void:
	var file := FileAccess.open(MINDLESS_AI_PATH, FileAccess.READ)
	assert_not_null(file, "core/combat/mindless_ai.gd must be readable")
	if file == null:
		return
	var content: String = _non_comment_lines(file.get_as_text())
	file.close()

	assert_false(content.contains("core/combat/ai.gd"), "mindless_ai.gd's CODE (excluding comments) must not reference the frozen core/combat/ai.gd by path")
	assert_false(content.contains("preload(\"res://core/combat/ai.gd\")"), "mindless_ai.gd must not preload the frozen core/combat/ai.gd")
	assert_false(content.contains("\"res://core/combat/ai.gd\""), "mindless_ai.gd's CODE must not reference the frozen core/combat/ai.gd resource path in any form")
