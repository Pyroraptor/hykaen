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
##   emit(event) -> void
##     Appends a structured event to the sink, in the order emitted.
##     FEAT-099/FIND-096: `event` is one of the TYPED value objects declared
##     in core/rules/round_events.gd (RoundEvents.AttackBroadcast /
##     RoundEvents.CombatantDefeatedEvent / RoundEvents.EncounterResultEvent /
##     RoundEvents.TurnAdvancedEvent / RoundEvents.ReactionWindowOpenedEvent /
##     RoundEvents.ReactionResolvedBroadcast — the latter two added by FEAT-009 /
##     US-009 / FR-005 / ADR-014 for core/application/reaction_window.gd's
##     pausable reaction-window architecture) — never a raw Dictionary. The
##     parameter is intentionally left untyped (no `: Dictionary` hint) so
##     any of these RefCounted value objects can be passed without a
##     static-type mismatch; concrete adapter overrides MUST likewise avoid
##     a `: Dictionary` parameter type hint. Each typed event's fields
##     mirror the pre-FEAT-099 Dictionary contract exactly (see
##     core/rules/round_events.gd for the authoritative field list per
##     event type) and each also exposes a to_dict() method for callers
##     that still want a Dictionary snapshot.
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd.
##
## Usage example:
##   const RoundEventsClass = preload("res://core/rules/round_events.gd")
##   var sink: EventSinkPort = _EventSinkAdapter.new(round_events_array)
##   sink.emit(RoundEventsClass.AttackBroadcast.new(1, "Titus", "Goblin", 17, "ac", 14, true, false, 6))

class_name EventSinkPort
extends RefCounted


## emit(event) -> void — abstract; concrete adapters MUST override.
## The base implementation exists only to document the contract and to
## fail loudly if a caller is ever handed a bare EventSinkPort instead of
## a concrete adapter.
func emit(event) -> void:
	push_error("EventSinkPort.emit() is abstract — override in a concrete adapter")
