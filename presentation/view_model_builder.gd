class_name ViewModelBuilder
extends RefCounted

## ViewModelBuilder — assembles the read-only view-model Arrays handed to the
## StatusPanelView and InitiativeView at boot. Pure construction: it reads the
## domain turn order / action economies off the passed-in encounter and joins
## them to the presentation combatant_ids by shared index; it holds no state and
## touches no scene nodes.
##
## Extracted verbatim from MainScene.gd (composition-root de-bloat, 2026-07-10):
## _build_status_view_models()/_build_initiative_view_models() were pure helpers
## crammed into the 2,788-line god-object. MainScene's _ready() now calls these
## directly. Behavior-preserving move (no logic changes).


## build_status_view_models(hex_combatants, party, enemies, encounter_instance) -> Array
##
## Builds the read-only view-model list handed to
## presentation/status_panel_view.gd's load_combatants() (FEAT-008 / US-006):
## one Dictionary per combatant with keys combatant_id/name/hp_current/
## hp_max/stamina_current/stamina_max/action_budget_remaining/spent/
## conditions. hex_combatants[i] (the domain Combatant built in step 1,
## carrying combatant_id) corresponds index-for-index to `party` then
## `enemies` -- combatant identity is joined by that shared index, never by
## reaching back into Encounter/ActionEconomy from StatusPanelView itself.
##
## action_budget_remaining/spent are read once, immediately after
## encounter.initialize(), from each combatant's freshly-constructed
## ActionEconomy (core/rules/action_economy.gd) -- resolved by name via
## encounter.get_turn_order()/get_action_economy(), since initiative sorting
## reorders combatants relative to `party`/`enemies`. conditions defaults to
## an empty Array -- no per-combatant Condition list exists in the domain
## model yet, so the panel simply shows none until that data exists.
func build_status_view_models(hex_combatants: Array, party: Array, enemies: Array, encounter_instance) -> Array:
	var action_economy_by_name: Dictionary = {}
	var turn_order: Array = encounter_instance.get_turn_order()
	for i in range(turn_order.size()):
		action_economy_by_name[turn_order[i].name] = encounter_instance.get_action_economy(i)

	var all_combatants: Array = party + enemies
	var view_models: Array = []
	for i in range(all_combatants.size()):
		# Phase C.3: party/enemies + the encounter's turn_order are now
		# Combatant instances; read fields directly off the entity.
		var combatant = all_combatants[i]
		var combatant_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		var action_economy = action_economy_by_name.get(combatant.name, null)

		view_models.append({
			"combatant_id":             combatant_id,
			"name":                     combatant.name,
			"hp_current":               combatant.hp_current,
			"hp_max":                   combatant.hp_max,
			"stamina_current":          combatant.stamina,
			"stamina_max":              combatant.stamina_max,
			"action_budget_remaining":  action_economy.get_remaining() if action_economy != null else 0,
			"spent":                    action_economy.is_spent() if action_economy != null else false,
			"conditions":               [],
		})
	return view_models


## build_initiative_view_models(hex_combatants, party, enemies, encounter_instance) -> Array
##
## Builds the read-only view-model list handed to
## presentation/initiative_view.gd's load_combatants() (FEAT-009 / US-007):
## one Dictionary per combatant with keys combatant_id/name/initiative_order.
## combatant_id is resolved via the SAME name-keyed join used by
## build_status_view_models() (hex_combatants[i] corresponds index-for-index to
## `party` then `enemies`) -- InitiativeView never reaches back into Encounter
## itself to obtain this data.
##
## encounter_instance.get_turn_order() (core/combat/encounter.gd) is already
## the domain-determined turn order -- sorted descending by each combatant's
## "_initiative_roll" (d20 + intuition + dexterity, per ADR-006) -- so that
## per-combatant roll is passed through unchanged as initiative_order;
## InitiativeView performs its own descending sort at load time, so the exact
## order handed in here is not itself load-bearing.
func build_initiative_view_models(hex_combatants: Array, party: Array, enemies: Array, encounter_instance) -> Array:
	var combatant_id_by_name: Dictionary = {}
	var all_combatants: Array = party + enemies
	for i in range(all_combatants.size()):
		var combatant_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		combatant_id_by_name[all_combatants[i].name] = combatant_id

	var view_models: Array = []
	for combatant in encounter_instance.get_turn_order():
		var name: String = combatant.name
		view_models.append({
			"combatant_id":     combatant_id_by_name.get(name, ""),
			"name":             name,
			"initiative_order": combatant.initiative_roll,
		})
	return view_models
