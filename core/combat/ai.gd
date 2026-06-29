## core/combat/ai.gd — Enemy AI Module (FEAT-089 / FR-012)
##
## Domain layer (ADR-001): pure GDScript class — no Node/Control inheritance.
## Encapsulates enemy action selection logic, decoupled from encounter.gd's
## run_round() method to satisfy the data-driven encounter architecture (FR-012).
##
## decide_action() is the single entry point: given a combatant dict and
## an array of potential targets, it returns a structured action dict describing
## what the combatant should do and against whom.
##
## Satisfies: FR-012, US-009, ADR-001

class_name AI


## decide_action(combatant: Dictionary, targets: Array) → Dictionary
##
## Selects the best action for the given combatant from the available target pool.
##
## Parameters:
##   combatant — A combatant Dictionary (name, hp_current, weapon, …).
##               Must have hp_current > 0 for a valid action to be returned.
##   targets   — Array of combatant Dictionaries on the opposing side.
##
## Returns a Dictionary with at minimum:
##   action_type: String — the action to perform ('Strike'), or '' if no action
##                          is available (no living targets).
##   target:      Dictionary — the chosen target combatant dict, or {} if none.
##
## v0 behaviour: always selects 'Strike' against the first living target.
## Future iterations may weight by hp, range, or conditions.
func decide_action(combatant: Dictionary, targets: Array) -> Dictionary:
	# Find the first living target in the provided pool
	var chosen_target: Dictionary = {}
	for t in targets:
		if t.get("hp_current", 0) > 0:
			chosen_target = t
			break

	# No living target — return a null-action sentinel
	if chosen_target.is_empty():
		return {"action_type": "", "target": {}}

	# v0: always choose Strike (sole available action in Tier 1)
	return {"action_type": "Strike", "target": chosen_target}
