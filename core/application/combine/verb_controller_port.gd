## core/application/combine/verb_controller_port.gd — VerbControllerPort
## (FEAT-005, Iteration O "Combine Selection UX"; US-005; FR-004/FR-013;
## NFR-002/NFR-003; ADR-002).
##
## Application layer (Clean Architecture, ADR-001): documents the SAME
## contract this project's "API" boundary for verb controllers already is
## (design notes' architecture section: "the 'API' boundary in this
## codebase is the enter_selection()/execute()/selection_resolved contract
## between controllers and the SelectionOverlay") — mirrors this project's
## established Protocol-style port pattern
## (core/application/combine/verb_registry_port.gd,
## core/application/ports/action_economy_port.gd): a base class documenting
## the contract; concrete adapters `extends` it (or simply duck-type it,
## this project's established fallback for lightweight adapters — see
## verb_registry_port.gd's own file-level doc for the precedent this
## mirrors).
##
## Consumed by core/application/combine/multi_phase_targeting_controller.gd's
## MultiPhaseTargetingController (ADR-002 contract check, this feature's own
## test_criteria: "registered controllers expose both enter_selection and
## execute"): every entry in a MultiPhaseTargetingController's injected
## verb_id -> controller registry MUST satisfy this SAME contract, whether
## it does so by extending this file or by structurally duck-typing it (a
## GDScript `extends VerbControllerPort` is NOT required for a concrete
## controller to be accepted — MultiPhaseTargetingController itself never
## static-type-checks against this class, only calls the two methods by
## name, exactly like every other duck-typed port in this codebase).
##
## Concrete implementations (design notes' architecture section:
## "CombineActionController ... StrideActionController /
## StrikeActionController ... implement VerbControllerPort") are explicitly
## OUT of this feature's scope — a later feature wires enter_selection()
## bodies on those controllers; this feature's own test suite
## (tests/unit/application/combine/test_multi_phase_targeting_controller.gd)
## injects lightweight fakes implementing this same contract in the
## meantime, mirroring verb_registry_port.gd's own precedent.
##
## Contract (design notes' api_contracts #1 and #3):
##   enter_selection(context: Dictionary) -> Object (a SelectionDescriptor —
##     core/domain/combine/selection_descriptor.gd's ok/candidate_options/
##     candidate_hexes/candidate_targets/order_index/meta value object;
##     returned as an untyped Object here, NOT statically typed
##     `SelectionDescriptor`, because that bare identifier already resolves
##     project-wide to core/application/selection_descriptor.gd's DIFFERENT
##     global class — see that domain file's own NAMING NOTE for why every
##     consumer reaches it via preload() rather than a bare identifier).
##     `context` carries {actor_id, mode, combine_context, queue,
##     accumulated} per the design notes' request shape.
##   execute(payload: Dictionary) -> Dictionary (an ExecutionResult-shaped
##     {ok, error_code, actions_spent, stamina_spent, resolution_log} —
##     the SAME shape core/controllers/combine_action_controller.gd's
##     CombineActionController.execute() already returns).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name VerbControllerPort
extends RefCounted


## enter_selection(context) -> Object (SelectionDescriptor-shaped) —
## abstract; concrete adapters MUST override. Returns null by default so an
## un-overridden port fails loud via push_error() rather than silently
## offering candidates.
func enter_selection(_context: Dictionary) -> Object:
	push_error("VerbControllerPort.enter_selection() is abstract — override in a concrete adapter")
	return null


## execute(payload) -> Dictionary{ok, error_code, actions_spent,
## stamina_spent, resolution_log} — abstract; concrete adapters MUST
## override. Returns a failure shape by default so an un-overridden port
## fails safe (no economy charged) rather than crashing.
func execute(_payload: Dictionary) -> Dictionary:
	push_error("VerbControllerPort.execute() is abstract — override in a concrete adapter")
	return {
		"ok": false,
		"error_code": "NOT_IMPLEMENTED",
		"actions_spent": 0,
		"stamina_spent": 0,
		"resolution_log": [],
	}
