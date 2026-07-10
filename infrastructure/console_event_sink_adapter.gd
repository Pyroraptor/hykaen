extends "res://core/application/event_sink_port.gd"

## ConsoleEventSinkAdapter - concrete EventSinkPort adapter (ADR-006): mirrors
## every emitted round event to stdout via print() AND forwards it to every
## Presentation projection registered in `forward_to` (FEAT-123) - the ONE
## integration point between the Application-layer round events the composition
## root's use cases emit and every subscribed Presentation projection
## (StatusPanelView/InitiativeView/EventLogView/ResultScreenView), whether the
## event happens synchronously at boot or later from live player/AI input.
##
## Composition-root de-bloat (2026-07-10): extracted from a MainScene.gd inner
## class; still wired ONLY by MainScene._ready() (ADR-002/G2), referenced via a
## preload const (ConsoleEventSinkAdapterClass) rather than a global class_name
## so it stays out of the global class namespace.

var log: Array = []

## forward_to - Presentation nodes exposing on_round_event(event); set by the
## composition root once every subscriber has been instantiated.
var forward_to: Array = []


func emit(event) -> void:
	log.append(event)
	if event.has_method("to_dict"):
		print("INFO: round event ", event.to_dict())
	else:
		print("INFO: round event ", event)
	for target in forward_to:
		if target != null:
			target.on_round_event(event)
