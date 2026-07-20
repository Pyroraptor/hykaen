## core/application/combine/build_verb_queue_use_case.gd —
## BuildVerbQueueUseCase (FEAT-002, Iteration O "Combine Selection UX";
## US-002; FR-001/FR-003).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combine/combine_actions.gd's CombineActions,
## core/domain/combine/verb_traits.gd's VerbTraits, core/domain/combine/
## selection_descriptor.gd's SelectionDescriptor) and its own sibling
## application-layer port (VerbRegistryPort) — never an adapter/
## infrastructure/presentation type, and never the engine scene tree.
## `verb_registry_port` is injected per call (duck-typed — no static port
## type annotation on the parameter, mirroring core/application/use_cases/
## begin_cast_use_case.gd's own `spell_catalog_port`/`round_energy_pool_port`
## convention), so a caller may substitute a fake in a unit test without
## needing a concrete adapter.
##
## Drives the FIRST half of the Iteration O queue-builder flow (design
## notes' architecture section, P0-1 "Verb queue builder (Layer 2a) —
## incremental verb picking"): given the queue picked SO FAR, ask
## VerbRegistryPort for the actor's currently-available verb pool, then
## filter it down to only the LEGAL next picks via
## core/domain/combine/combine_actions.gd's combine_actions() — the SAME
## domain service a later feature's execute()-time DEF-001 gate re-runs, so
## this use case never re-derives its own copy of the same-verb/Repeat rule.
##
## THIS FEATURE'S SCOPE (US-002) was the candidate_options-filtering pick
## step only; FEAT-003 (US-003; FR-002) now layers the Confirm sentinel on
## top of this SAME seam, without changing its shape: once
## core/domain/combine/combine_queue.gd's CombineQueue.meets_confirm_minimum()
## reports the context-specific minimum queue length is met,
## candidate_options also carries a {"id": CONFIRM_SENTINEL_ID, "label":
## "Confirm", "kind": "CONFIRM"} entry alongside whatever compatible verbs
## remain legal. This use case never re-derives its own copy of the
## minimum-length rule -- it is the SAME static domain rule
## ConfirmQueueUseCase's own command-time gate re-evaluates (query-time and
## command-time both route through ONE domain rule, never two independently
## maintained copies -- mirrors combine_actions()'s own established
## convention for the same-verb/Repeat rule). The full REACTION-context
## composition rule (design notes' P1-3) remains a later feature layered on
## top of this same seam.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name BuildVerbQueueUseCase
extends RefCounted

const CombineActionsClass = preload("res://core/domain/combine/combine_actions.gd")
const VerbTraitsClass = preload("res://core/domain/combine/verb_traits.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

## The Confirm sentinel's candidate_options "id" (FEAT-003; US-003).
## Selecting this option is the SelectionOverlay-driven trigger a later
## feature's composition-root wiring routes into ConfirmQueueUseCase.execute()
## -- this use case only ever OFFERS the sentinel, never itself invokes
## ConfirmQueueUseCase.
const CONFIRM_SENTINEL_ID: String = "CONFIRM"

## SelectionDescriptorScript — the domain-layer SelectionDescriptor value
## object (core/domain/combine/selection_descriptor.gd) this use case
## returns. That file deliberately carries NO `class_name` (it would
## collide with core/application/selection_descriptor.gd's own global
## `SelectionDescriptor` class — see that file's own NAMING NOTE), so every
## consumer, including this one, MUST reach it via preload() rather than a
## bare `SelectionDescriptor` identifier.
const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")


## enter_selection(queue, actor, context, verb_registry_port) -> SelectionDescriptor
##
## queue              — Array of already-picked queue entries (see
##                       core/domain/combine/combine_actions.gd's own
##                       `queue` contract for the accepted entry shapes).
##                       Empty for the first pick of a fresh Combine.
## actor              — the combatant picking verbs; forwarded verbatim to
##                       `verb_registry_port.get_available_verbs()`. A null
##                       actor degrades safely (see below) rather than
##                       crashing.
## context            — one of core/domain/combine/combine_queue.gd's
##                       CombineQueue.Context enum members (TURN|REACTION),
##                       forwarded verbatim to `verb_registry_port` so it
##                       can filter its own pool accordingly (this use case
##                       itself performs no context-specific filtering
##                       beyond forwarding — the REACTION-context Confirm
##                       composition rule is a later feature, P1-3).
## verb_registry_port — a VerbRegistryPort implementation (or a duck-typed
##                       fake exposing the same get_available_verbs(actor,
##                       context) -> Array[VerbResource] contract). A null
##                       port degrades safely rather than crashing.
##
## Returns a SelectionDescriptor whose `candidate_options` is the subset of
## `verb_registry_port`'s returned pool — filtered to `combinable == true`
## VerbResources — that combine_actions() reports legal to append to
## `queue`, each shaped {"id": verb_id, "label": label, "kind": "VERB"}
## (design notes' data_model, SelectionDescriptor.candidate_options
## contract), PLUS (FEAT-003) a trailing {"id": CONFIRM_SENTINEL_ID,
## "label": "Confirm", "kind": "CONFIRM"} entry once
## CombineQueue.meets_confirm_minimum(context, queue.size()) reports the
## context-specific minimum queue length is met. `ok` is false (design
## notes' error_handling: "empty candidates must be an explicit error state,
## never an implicit auto-fire") when the resulting candidate_options list
## is empty — whether because the pool itself was empty, every pooled verb
## was excluded by combine_actions(), or `actor`/`verb_registry_port` was
## null; the Confirm sentinel alone (with zero legal verbs remaining) still
## counts as a non-empty, ok=true candidate set. `order_index` mirrors
## `queue`'s current length (design notes' data_model: "which sub-action
## within a CombineQueue this descriptor is for").
func enter_selection(queue: Array, actor, context: int, verb_registry_port) -> Object:
	var candidate_options: Array = []

	if actor != null and verb_registry_port != null:
		var pool: Array = verb_registry_port.get_available_verbs(actor, context)
		for verb_resource in pool:
			if verb_resource == null or not verb_resource.combinable:
				continue
			var candidate: Dictionary = {
				"verb_id": verb_resource.verb_id,
				"traits": VerbTraitsClass.from_verb_resource(verb_resource),
			}
			var verdict: Dictionary = CombineActionsClass.combine_actions(queue, candidate)
			if verdict.get("legal", false):
				candidate_options.append({
					"id": verb_resource.verb_id,
					"label": verb_resource.label,
					"kind": "VERB",
				})

	if CombineQueueClass.meets_confirm_minimum(context, queue.size()):
		candidate_options.append({
			"id": CONFIRM_SENTINEL_ID,
			"label": "Confirm",
			"kind": "CONFIRM",
		})

	var ok: bool = not candidate_options.is_empty()
	var meta: Dictionary = {} if ok else {"error_code": "NO_LEGAL_OPTIONS"}
	return SelectionDescriptorScript.new(ok, candidate_options, [], [], queue.size(), meta)
