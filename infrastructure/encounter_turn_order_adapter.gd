extends "res://core/application/turn_order_port.gd"

## EncounterTurnOrderAdapter - implements TurnOrderPort over an already-
## initialize()d Encounter's PUBLIC accessors (get_turn_order() /
## get_action_economy()), reusing Encounter's existing, tested initiative-
## rolling/ActionEconomy bookkeeping without reaching into its private fields or
## calling its autonomous run_round() (FEAT-123 / FIND-120).
##
## Composition-root de-bloat (2026-07-10): extracted from a MainScene.gd inner
## class; wired ONLY by MainScene, referenced via EncounterTurnOrderAdapterClass.

var _encounter


func _init(p_encounter) -> void:
	_encounter = p_encounter


func get_turn_order() -> Array:
	var order: Array = _encounter.get_turn_order()
	var entries: Array = []
	for i in range(order.size()):
		entries.append({"combatant": order[i], "action_economy": _encounter.get_action_economy(i)})
	return entries
