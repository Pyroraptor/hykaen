## core/application/combine/verb_registry_port.gd — VerbRegistryPort
## (FEAT-002, Iteration O "Combine Selection UX"; US-002; FR-001/FR-003).
##
## Application layer (Clean Architecture, ADR-001): documents the contract
## core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase depends on to resolve the pool of verbs an actor
## may pick into a CombineQueue — mirrors this project's established
## Protocol-style port pattern (core/application/ports/spell_catalog_port.gd,
## core/application/ports/reaction_window_port.gd). Depends only on domain
## (implicitly, via the VerbResource-shaped Array it returns — this port
## itself performs no domain logic) — never an adapter/infrastructure/
## presentation type.
##
## Concrete implementation (design notes' architecture section:
## "VerbResourceRepository — implements VerbRegistryPort; loads/queries
## VerbResource .tres files") is explicitly OUT of this feature's scope — a
## later feature wires a real adapter; BuildVerbQueueUseCase's own tests
## (and CombineActionController's own tests) inject a lightweight fake
## implementing this same contract in the meantime, mirroring
## core/application/ports/action_economy_port.gd's own "concrete adapters
## ... simply duck-type it" convention for lightweight collaborators.
##
## Contract (design notes' api_contracts #4):
##   get_available_verbs(actor, context) -> Array[VerbResource]
##     Every VerbResource (core/resources/verb_resource.gd) the given
##     `actor` may currently pick from, filtered by whatever legality this
##     port's own concrete adapter deems appropriate for `context` (one of
##     core/domain/combine/combine_queue.gd's CombineQueue.Context enum
##     members — TURN or REACTION). An empty Array is a VALID (not error)
##     response — BuildVerbQueueUseCase maps that to its own
##     ok=false/NO_LEGAL_OPTIONS SelectionDescriptor, never treats it as a
##     crash.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name VerbRegistryPort
extends RefCounted


## get_available_verbs(actor, context) -> Array[VerbResource] — abstract;
## concrete adapters MUST override. Returns an empty Array by default so an
## un-overridden port fails safe (no candidates) rather than crashing.
func get_available_verbs(_actor, _context) -> Array:
	push_error("VerbRegistryPort.get_available_verbs() is abstract — override in a concrete adapter")
	return []
