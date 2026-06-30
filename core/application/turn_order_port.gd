## core/application/turn_order_port.gd — TurnOrderPort (FEAT-098 / US-004)
##
## Application layer (Clean Architecture): defines the contract RunRoundUseCase
## depends on to obtain the ordered sequence of combatants (and their paired
## per-round ActionEconomy) for a round, decoupling the cycle algorithm from
## however turn order is actually stored (an in-memory Array on
## core/combat/encounter.gd today; a future iteration could swap in a
## different storage strategy without touching RunRoundUseCase).
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides an abstract get_turn_order() that
## concrete adapters MUST override. Concrete adapters extend this script
## directly (`extends "res://core/application/turn_order_port.gd"`).
##
## Contract:
##   get_turn_order() -> Array
##     Returns an ordered Array of TurnOrderEntry-shaped Dictionaries:
##       {"combatant": Dictionary, "action_economy": ActionEconomy}
##     "combatant" is a combatant Dictionary (name, hp_current, weapon, ...,
##     plus the "_is_enemy"/"_initiative_roll" tags set during initiative
##     rolling). "action_economy" is the ActionEconomy instance paired with
##     that combatant for the round (CR-001 AC-1/AC-2/AC-3 budget owner).
##     The Array order IS the initiative/turn order — descending by
##     initiative roll, established once per encounter and stable across
##     every call within that encounter's lifetime.
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd.
##
## Usage example:
##   var port: TurnOrderPort = _TurnOrderAdapter.new(turn_order, action_economies)
##   for entry in port.get_turn_order():
##       var combatant = entry["combatant"]
##       var ae        = entry["action_economy"]

class_name TurnOrderPort
extends RefCounted


## get_turn_order() -> Array — abstract; concrete adapters MUST override.
## The base implementation exists only to document the contract and to
## fail loudly (rather than silently returning a usable-looking empty
## result) if a caller is ever handed a bare TurnOrderPort instead of a
## concrete adapter.
func get_turn_order() -> Array:
	push_error("TurnOrderPort.get_turn_order() is abstract — override in a concrete adapter")
	return []
