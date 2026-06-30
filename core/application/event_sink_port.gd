## core/application/event_sink_port.gd — EventSinkPort (FEAT-098 / US-004/US-005)
##
## Application layer (Clean Architecture): defines the contract
## RunRoundUseCase/ResolveActionUseCase depend on to emit observability
## events ('attack' / 'combatant_defeated' / 'encounter_result') without
## knowing how/where those events are collected — abstracting the
## _round_events Array currently owned by core/combat/encounter.gd.
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides an abstract emit() that concrete
## adapters MUST override. Concrete adapters extend this script directly
## (`extends "res://core/application/event_sink_port.gd"`).
##
## Contract:
##   emit(event: Dictionary) -> void
##     Appends a structured event Dictionary to the sink, in the order
##     emitted. Event shapes (unchanged from the pre-extraction contract —
##     see core/rules/round_events.gd for the typed value-object
##     equivalents of these same fields):
##       {type:'attack', round:int, attacker_name:String, target_name:String,
##        roll:int, defense_type:String, defense_value:int, hit:bool,
##        crit:bool, damage_final:int}
##       {type:'combatant_defeated', round:int, name:String, defeated_by:String}
##       {type:'encounter_result', round:int, outcome:String}
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd.
##
## Usage example:
##   var sink: EventSinkPort = _EventSinkAdapter.new(round_events_array)
##   sink.emit({"type": "attack", "round": 1, ...})

class_name EventSinkPort
extends RefCounted


## emit(event) -> void — abstract; concrete adapters MUST override.
## The base implementation exists only to document the contract and to
## fail loudly if a caller is ever handed a bare EventSinkPort instead of
## a concrete adapter.
func emit(event: Dictionary) -> void:
	push_error("EventSinkPort.emit() is abstract — override in a concrete adapter")
