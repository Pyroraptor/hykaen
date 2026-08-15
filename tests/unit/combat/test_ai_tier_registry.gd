extends GutTest
## tests/unit/combat/test_ai_tier_registry.gd
##
## GUT unit test suite for FEAT-006 (US-006 / FR-009): the DOMAIN-layer
## core/combat/ai_tier_registry.gd tier-to-planner mapping factory.
##
## Verifies (this feature's test_criteria):
##   1. get_planner('mindless') returns a MindlessAI instance.
##   2. get_planner('grunt') returns a GruntAI instance.
##   3. get_planner('soldier') and get_planner('unknown-typo') both fall
##      back to MindlessAI (no error/crash) — 'soldier' is a TEMPORARY
##      alias per RISK-005, flagged as an iteration-2 follow-up.
##   4. Static check: core/combat/ai_tier_registry.gd declares no
##      class_name (verified via file inspection), per ADR-006 — this
##      registry is deliberately not part of the public port surface.
##
## Satisfies: FEAT-006, US-006, FR-009.

const AITierRegistryClass = preload("res://core/combat/ai_tier_registry.gd")
const MindlessAIClass = preload("res://core/combat/mindless_ai.gd")
const GruntAIClass = preload("res://core/combat/grunt_ai.gd")

const AI_TIER_REGISTRY_PATH := "res://core/combat/ai_tier_registry.gd"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: get_planner('mindless') returns a MindlessAI instance
# ══════════════════════════════════════════════════════════════════════════

func test_get_planner_mindless_returns_mindless_ai_instance() -> void:
	var planner = AITierRegistryClass.get_planner("mindless")

	assert_true(
		is_instance_of(planner, MindlessAIClass),
		"get_planner('mindless') must return a MindlessAI instance"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: get_planner('grunt') returns a GruntAI instance
# ══════════════════════════════════════════════════════════════════════════

func test_get_planner_grunt_returns_grunt_ai_instance() -> void:
	var planner = AITierRegistryClass.get_planner("grunt")

	assert_true(
		is_instance_of(planner, GruntAIClass),
		"get_planner('grunt') must return a GruntAI instance"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: unrecognized tiers (including the TEMPORARY 'soldier' alias,
# per RISK-005) fall back to MindlessAI -- no error/crash
# ══════════════════════════════════════════════════════════════════════════

func test_get_planner_soldier_falls_back_to_mindless_ai() -> void:
	# TEMPORARY per RISK-005: 'soldier' is not yet a shipped tier. Until a
	# dedicated SoldierAI lands (a future iteration), the registry
	# defensively downgrades it to MindlessAI rather than crashing the
	# composition root on a not-yet-implemented tier string.
	var planner = AITierRegistryClass.get_planner("soldier")

	assert_true(
		is_instance_of(planner, MindlessAIClass),
		"get_planner('soldier') must fall back to MindlessAI (TEMPORARY alias, iteration-2 follow-up per RISK-005)"
	)


func test_get_planner_unknown_typo_falls_back_to_mindless_ai() -> void:
	var planner = AITierRegistryClass.get_planner("unknown-typo")

	assert_true(
		is_instance_of(planner, MindlessAIClass),
		"get_planner() with any unrecognized string must defensively fall back to MindlessAI, never error/crash"
	)


func test_get_planner_empty_string_falls_back_to_mindless_ai() -> void:
	var planner = AITierRegistryClass.get_planner("")

	assert_true(
		is_instance_of(planner, MindlessAIClass),
		"get_planner('') must defensively fall back to MindlessAI"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: no class_name declared on the registry script
# ══════════════════════════════════════════════════════════════════════════

## Strips full-line `##`/`#` doc/line comments so the class_name check below
## looks only at executable code, not prose that merely *discusses*
## class_name for documentation purposes. Mirrors
## tests/unit/combat/test_mindless_ai.gd's identically-named helper.
func _non_comment_lines(source: String) -> String:
	var kept: PackedStringArray = []
	for raw_line in source.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(raw_line)
	return "\n".join(kept)


func test_ai_tier_registry_declares_no_class_name() -> void:
	var file := FileAccess.open(AI_TIER_REGISTRY_PATH, FileAccess.READ)
	assert_not_null(file, "core/combat/ai_tier_registry.gd must be readable")
	if file == null:
		return
	var content: String = _non_comment_lines(file.get_as_text())
	file.close()

	assert_false(
		content.contains("class_name"),
		"core/combat/ai_tier_registry.gd must not declare a class_name -- it is a preload-based domain factory, not part of the public port surface (per design notes)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Sanity: get_planner() returns a fresh instance each call (no shared
# mutable singleton state leaking across combatants)
# ══════════════════════════════════════════════════════════════════════════

func test_get_planner_returns_distinct_instances_across_calls() -> void:
	var first = AITierRegistryClass.get_planner("mindless")
	var second = AITierRegistryClass.get_planner("mindless")

	assert_false(
		first == second,
		"get_planner() must return a fresh planner instance per call, not a shared singleton"
	)
