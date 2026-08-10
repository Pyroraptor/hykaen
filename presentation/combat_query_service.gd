## presentation/combat_query_service.gd — CombatQueryService
## Pure query helpers extracted from MainScene (ADR-002 composition-root debt).
## Injected with party_fn/enemies_fn Callables so it reads live state without
## holding a back-reference to the composition root.
class_name CombatQueryService
extends RefCounted

var _party_fn: Callable
var _enemies_fn: Callable


func _init(party_fn: Callable, enemies_fn: Callable) -> void:
	_party_fn = party_fn
	_enemies_fn = enemies_fn


## Filter: hp_current > 0.
func living_combatants(combatants: Array) -> Array:
	var living: Array = []
	for c in combatants:
		if c.hp_current > 0:
			living.append(c)
	return living


## Lookup by display_id among current party + enemies.
func find_combatant_by_id(combatant_id: String):
	for c in _party_fn.call() + _enemies_fn.call():
		if c.display_id() == combatant_id:
			return c
	return null


## Live ActionEconomy for a combatant from the encounter turn order.
## Object-identity match first, display_id fallback (mirrors the former
## MainScene._action_economy_for() idiom — extracted here so the composition
## root carries only a thin lambda delegate rather than 17 lines of search).
func action_economy_for(combatant, encounter):
	if encounter == null:
		return null
	var order: Array = encounter.get_turn_order()
	for i in range(order.size()):
		if is_same(order[i], combatant):
			return encounter.get_action_economy(i)
	var combatant_id: String = combatant.display_id()
	if combatant_id != "":
		for i in range(order.size()):
			if order[i].display_id() == combatant_id:
				return encounter.get_action_economy(i)
	return null


## Living combatants excluding the given one.
func other_living_combatants(combatant) -> Array:
	var self_id: String = combatant.display_id()
	var others: Array = []
	for c in living_combatants(_party_fn.call() + _enemies_fn.call()):
		if c.display_id() != self_id:
			others.append(c)
	return others
