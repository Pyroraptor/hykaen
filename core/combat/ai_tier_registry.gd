## core/combat/ai_tier_registry.gd — AITierRegistry (FEAT-006 / US-006 / FR-009)
##
## Domain layer (Clean Architecture): a pure tier-string -> AIPlannerPort
## instance mapping factory/strategy-selector. NOT a composition root — it
## has no knowledge of Godot nodes, RoundSession, or combatant dict shape
## beyond the tier string itself. The composition root (run_round_use_case.gd
## / CombatSessionFactory, FEAT-013) calls get_planner() and stores the
## result on the entry it wires up.
##
## Deliberately no class_name: this registry is a preload-based static
## helper, not part of the public port surface (AIPlannerPort is the port;
## this is one of several possible ways to select a concrete implementation
## of it). Callers reach it via:
##   const AITierRegistryClass = preload("res://core/combat/ai_tier_registry.gd")
##   var planner = AITierRegistryClass.get_planner(combatant.ai_tier)
##
## Mapping (per design notes / test_criteria):
##   'grunt'    -> GruntAI (core/combat/grunt_ai.gd)
##   'mindless' -> MindlessAI (core/combat/mindless_ai.gd)
##   anything else, INCLUDING the TEMPORARY 'soldier' alias (per RISK-005)
##              -> MindlessAI
##
## TEMPORARY (RISK-005 / iteration-2 follow-up): 'soldier' is not yet a
## shipped tier -- there is no SoldierAI planner in this iteration. Until
## one lands, 'soldier' is intentionally routed through the same defensive
## unrecognized-tier fallback as any other unknown/typo'd string, so
## content authors can pre-tag enemy data with ai_tier = 'soldier' today
## without crashing the composition root; it will silently behave as
## 'mindless' until SoldierAI is implemented. Remove this note (and add an
## explicit 'soldier' branch) when SoldierAI ships.
##
## Error handling: there is no invalid input for get_planner() by design --
## any String not in the known set defensively falls back to MindlessAI
## rather than raising or crashing, so malformed/typo'd ai_tier data in a
## .tres file never crashes the composition root; it just silently
## downgrades AI sophistication for that enemy.

const MindlessAIClass = preload("res://core/combat/mindless_ai.gd")
const GruntAIClass = preload("res://core/combat/grunt_ai.gd")


## get_planner(ai_tier) -> AIPlannerPort — maps a tier String to a freshly
## constructed concrete planner instance. Returns a NEW instance on every
## call (no shared/singleton state across combatants). Unrecognized strings
## (including the TEMPORARY 'soldier' alias -- see file-level doc) fall
## back to MindlessAI.
static func get_planner(ai_tier: String):
	match ai_tier:
		"grunt":
			return GruntAIClass.new()
		"mindless":
			return MindlessAIClass.new()
		_:
			# Unrecognized string -- including the TEMPORARY 'soldier' alias
			# (RISK-005) -- defensively downgrades to MindlessAI rather than
			# erroring/crashing. See file-level doc.
			return MindlessAIClass.new()
