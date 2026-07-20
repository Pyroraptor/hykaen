## core/controllers/combine_action_controller.gd — CombineActionController
## (FEAT-004, Iteration O "Combine Selection UX"; US-004; FR-007; DEF-001).
##
## Adapter layer (Clean Architecture, ADR-001): this project's "API"
## boundary for verb controllers is the enter_selection()/execute()/
## selection_resolved contract (design notes' architecture section), so
## this file — like every other verb controller — lives under the
## adapters/infrastructure side of the dependency arrow even though it
## sits physically under core/ (mirrors design notes' own component
## layout: "ADAPTERS/INFRASTRUCTURE (core/controllers/, core/ui/,
## scripts/ — all Godot-specific code lives here)"). Depends on the
## APPLICATION layer (ValidateCombineQueueUseCase) and duck-typed ports
## (VerbRegistryPort, an ActionEconomyPort-shaped collaborator) — never the
## other way around.
##
## THIS FEATURE'S SCOPE (US-004; DEF-001) is the authoritative
## re-validation gate: execute() invokes ValidateCombineQueueUseCase as its
## FIRST statement — re-deriving verb entries from the confirmed queue and
## re-running core/domain/combine/combine_actions.gd's combine_actions()
## against FRESH VerbTraits — BEFORE any action-economy/Stamina charge.
## An illegal combo (e.g. two STRIDEs with no Repeat trait) is rejected
## with {ok: false, error_code: "VALIDATION_FAILED", actions_spent: 0,
## stamina_spent: 0} — ZERO economy spent (design notes' error_handling:
## "failure short-circuits execute() before any charge to action economy
## or Stamina"). A legal combo proceeds to `_charge_action_economy()`,
## which charges exactly one action (via the injected
## `action_economy_port`, when wired) and one Stamina (via the actor's own
## `spend_stamina()`, the SAME sole mutator core/domain/combatant.gd
## documents). The full N-length sub-action dispatch (Stride-then-Strike
## resolution) is a LATER feature layered on top of this same seam,
## without changing it.
##
## FEAT-002 (US-002; FR-001/FR-003) ADDS this controller's other
## VerbControllerPort half, enter_selection(): delegates to
## core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase to return a REAL SelectionDescriptor (ok/
## candidate_options/candidate_hexes/candidate_targets/order_index/meta) of
## legal, combinable next-pick verb candidates — fixing this controller's
## original bare {ok, queue}-only Dictionary shape.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## FEAT-297 (Iteration O; US-004/005/006; resolves DEF-NEW-002) merges the
## REAL sub-action dispatch into THIS controller's execute() — the instance
## actually invoked by the live signal chain (MultiPhaseTargetingController,
## composition-root-wired as `_core_combine_action_controller` in
## MainScene.gd). Before this feature, execute() only re-validated (DEF-001)
## and charged economy; two disconnected CombineActionController classes
## existed, and only presentation/combine_action_controller.gd's (never
## reached by the live interactive flow, per that file's own now-deprecated
## doc) actually resolved Stride-then-Strike. Now, once the DEF-001 gate
## passes, this execute() dispatches every `payload["queue"]` entry's own
## sub-action controller (looked up via the injected `controller_for`
## Callable — the SAME data-driven `verb_id -> controller` resolution seam
## presentation/combine_action_controller.gd's own `_controller_for_fn`
## established, never a hard preload/class_name reference to
## Stride/StrikeActionController), strictly in order_index order, appending
## `{"verb_id": ..., "outcome": <that sub-controller's own execute() result>}`
## onto `resolution_log`. Because dispatch is strictly sequential and each
## sub-controller mutates the SAME live actor, a queued STRIKE naturally
## observes the actor's POST-Stride position — no positional snapshot/
## threading is authored here, exactly mirroring
## presentation/combine_action_controller.gd's own established rationale.
##
## `_dispatch_sub_actions()`/`_controller()` call each resolved sub-
## controller's `execute()` via `Callable(controller, "execute").call(...)`
## rather than `await controller.execute(...)`: the REAL Stride/Strike
## controllers (presentation/stride_action_controller.gd /
## presentation/strike_action_controller.gd) are GDScript coroutines (they
## themselves `await` Opportunistic-Strike/Dodge-Step resolution), and
## `await`-ing them directly here would make THIS execute() a coroutine too
## — forcing EVERY caller across the whole call chain
## (MultiPhaseTargetingController.execute(), MainScene's own targeting-phase
## advance chain, and their existing test suites, none of which are this
## feature's own files_to_modify) to add `await` at their own call sites, a
## sweeping, out-of-scope ripple. `Callable.call()` sidesteps that: it is
## NOT statically flagged as an awaited call, so it never propagates the
## coroutine requirement upward. This is safe for every real Combine
## dispatch path in this codebase: a Combine's own sub-actions are always
## the PLAYER's, so any reaction they provoke resolves through
## infrastructure/ai_reaction_policy.gd's `enemy_reaction_chooser` — this
## project's own documented "deterministic, RNG-free, SYNCHRONOUS chooser:
## no pop-up, no `await`, no coroutine ever opens" for the enemy's reaction
## decision — so no sub-controller's `execute()` call in this dispatch path
## ever genuinely suspends. `_dispatch_sub_actions()` defensively treats a
## non-Dictionary result (i.e. the runtime DID genuinely suspend, which
## `Callable.call()` cannot correctly resume) as a hard sub-action failure
## rather than crashing or silently losing the outcome.
##
## Usage:
##   var controller := CombineActionController.new({
##       "validate_combine_queue_use_case": ValidateCombineQueueUseCase.new(),
##       "build_verb_queue_use_case": BuildVerbQueueUseCase.new(),
##       "verb_registry_port": verb_registry_port,
##       "action_economy_port": action_economy_port,
##       "controller_for": Callable(self, "_controller"),
##   })
##   var descriptor: Object = controller.enter_selection({
##       "actor_id": actor,
##       "mode": "BUILD_QUEUE",
##       "combine_context": CombineQueue.Context.TURN,
##       "queue": [],
##   })
##   # descriptor.ok == true; descriptor.candidate_options includes STRIDE/STRIKE
##
##   var result: Dictionary = controller.execute({
##       "queue": confirmed_queue.sorted_entries(),
##       "actor": actor,
##       "context": CombineQueue.Context.TURN,
##       "accumulated": {"STRIDE": stride_descriptor, "STRIKE": strike_descriptor},
##   })
##   # {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1,
##   #  "resolution_log": [{"verb_id": "STRIDE", "outcome": {...}}, {"verb_id": "STRIKE", "outcome": {...}}]}

class_name CombineActionController
extends RefCounted

const ValidateCombineQueueUseCaseClass = preload("res://core/application/combine/validate_combine_queue_use_case.gd")
const BuildVerbQueueUseCaseClass = preload("res://core/application/combine/build_verb_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

## The APPLICATION-layer use case this controller's execute() routes its
## DEF-001 re-validation gate through. Defaults to a fresh instance so a
## caller need not always inject one, but a test may substitute its own
## (e.g. a spy) via `deps["validate_combine_queue_use_case"]`.
var _validate_combine_queue_use_case

## The APPLICATION-layer use case this controller's enter_selection()
## (FEAT-002; US-002; FR-001/FR-003) routes the incremental verb-queue-pick
## query through. Defaults to a fresh instance so a caller need not always
## inject one, but a test may substitute its own (e.g. a spy) via
## `deps["build_verb_queue_use_case"]`.
var _build_verb_queue_use_case

## VerbRegistryPort (or an equivalent duck-typed fake) — forwarded verbatim
## to `_validate_combine_queue_use_case.execute()` as the SOLE source fresh
## VerbTraits are re-derived from (DEF-001). Null degrades safely (the use
## case itself treats a null port as VALIDATION_FAILED).
var _verb_registry_port

## An ActionEconomyPort-shaped collaborator (duck-typed —
## core/application/ports/action_economy_port.gd's own established
## "concrete adapters simply duck-type it" convention): `spend_action(metadata)
## -> Dictionary{success/ok, ...}`. Null means no action-economy charge is
## attempted (the pre-wiring degrade path — mirrors this codebase's
## established "no resolver injected -> degrade gracefully" convention,
## e.g. presentation/combine_action_controller.gd's own
## `_controller_for_fn`).
var _action_economy_port

## _controller_for_fn — FEAT-297 (resolves DEF-NEW-002): the data-driven
## sub-action-controller resolver, `deps["controller_for"]` (a
## Callable(verb_id: String) -> VerbControllerPort-shaped/ActionController-
## shaped instance), mirroring presentation/combine_action_controller.gd's
## own `_controller_for_fn` field exactly. Defaults to an invalid/empty
## Callable when not supplied, in which case `_controller(verb_id)` returns
## null and execute() skips sub-action dispatch entirely (the pre-FEAT-297
## validate-then-charge-only contract every existing DEF-001 regression test
## in this suite already pins). The REAL composition root (MainScene.gd)
## wires this to `Callable(self, "_controller")` — the SAME
## `VERB_TABLE`-backed lookup every other verb (including the REAL
## presentation/stride_action_controller.gd / strike_action_controller.gd)
## is resolved through, never a hard preload/class_name reference.
var _controller_for_fn: Callable


func _init(deps: Dictionary = {}) -> void:
	_validate_combine_queue_use_case = deps.get("validate_combine_queue_use_case", ValidateCombineQueueUseCaseClass.new())
	_build_verb_queue_use_case = deps.get("build_verb_queue_use_case", BuildVerbQueueUseCaseClass.new())
	_verb_registry_port = deps.get("verb_registry_port")
	_action_economy_port = deps.get("action_economy_port")
	_controller_for_fn = deps.get("controller_for", Callable())


## enter_selection(context) -> Object (SelectionDescriptor) — (FEAT-002;
## US-002; FR-001/FR-003; VerbControllerPort contract, api_contracts #1).
##
## Drives the queue-builder half of this controller's VerbControllerPort
## surface (the OTHER half being execute(), above): given the queue picked
## SO FAR, delegates to core/application/combine/build_verb_queue_use_case.gd's
## BuildVerbQueueUseCase to ask `_verb_registry_port` for the actor's
## currently-available verb pool and filter it down to only the LEGAL next
## picks via core/domain/combine/combine_actions.gd's combine_actions() —
## the SAME domain service execute()'s DEF-001 gate re-runs, never a second,
## independently-maintained copy of the same-verb/Repeat rule.
##
## Returns a REAL SelectionDescriptor (core/domain/combine/
## selection_descriptor.gd — ok/candidate_options/candidate_hexes/
## candidate_targets/order_index/meta) rather than this controller's
## original bare {ok, queue}-only Dictionary shape.
##
## context — Dictionary carrying (design notes' api_contracts #1 request
##            shape; extra keys such as "mode"/"accumulated" are accepted
##            and ignored -- this controller's queue-builder step performs
##            no context-specific branching beyond what it reads below):
##   "actor_id" — the combatant picking verbs (despite the key name, this
##                is the actual actor object, not a String id — mirrors
##                every other verb controller's own `context.get("actor_id")`
##                convention, e.g. core/controllers/stride_action_controller.gd).
##                Forwarded verbatim to BuildVerbQueueUseCase; a null actor
##                degrades safely (see BuildVerbQueueUseCase's own doc)
##                rather than crashing.
##   "queue"    — Array of already-picked queue entries (VerbQueueEntry or
##                equivalent Dictionaries). Defaults to [] for the first
##                pick of a fresh Combine.
##   "combine_context" — one of CombineQueue.Context (TURN|REACTION);
##                defaults to TURN when absent.
func enter_selection(context: Dictionary = {}) -> Object:
	var actor = context.get("actor_id")
	var queue: Array = context.get("queue", [])
	var combine_context: int = context.get("combine_context", CombineQueueClass.Context.TURN)

	return _build_verb_queue_use_case.enter_selection(queue, actor, combine_context, _verb_registry_port)


## execute(payload) -> Dictionary{ok, error_code, actions_spent, stamina_spent, resolution_log}
##
## payload — Dictionary carrying:
##   "queue"   — Array of the CONFIRMED CombineQueue's entries (VerbQueueEntry
##               instances, or equivalent Dictionaries — see
##               ValidateCombineQueueUseCase's own `queue_entries` contract).
##               Defaults to [] when absent.
##   "actor"   — the combatant executing the Combine; forwarded to the
##               validation gate and, on success, charged one Stamina.
##   "context" — one of CombineQueue.Context (TURN|REACTION); defaults to
##               TURN when absent.
##
## Returns:
##   {"ok": false, "error_code": "VALIDATION_FAILED", "actions_spent": 0,
##    "stamina_spent": 0} — DEF-001 gate rejected the (re-derived) queue.
##    ZERO economy mutation ever occurs on this path (see this method's own
##    body — `_charge_action_economy()` below is never reached).
##   {"ok": true, "error_code": "", "actions_spent": <0 or 1>,
##    "stamina_spent": <0 or 1>, "resolution_log": []} — validation passed;
##    `_charge_action_economy()` ran (see its own doc for when each spend
##    actually occurs).
func execute(payload: Dictionary = {}) -> Dictionary:
	var queue: Array = payload.get("queue", [])
	var actor = payload.get("actor")
	var context: int = payload.get("context", CombineQueueClass.Context.TURN)
	var accumulated: Dictionary = payload.get("accumulated", {})

	# DEF-001 — the authoritative re-validation gate, invoked as the FIRST
	# statement of execute(), strictly before any sub-action dispatch or
	# economy charge below.
	var validation: Dictionary = _validate_combine_queue_use_case.execute(queue, actor, context, _verb_registry_port)
	if not validation.get("ok", false):
		return _rejection_result(validation.get("error_code", "VALIDATION_FAILED"))

	# FEAT-297 (resolves DEF-NEW-002) — the real Stride-then-Strike (or any
	# N-length, order_index-ordered) sub-action dispatch, now merged into
	# THIS controller (the one the live signal chain actually invokes). Runs
	# AFTER the DEF-001 gate but BEFORE the economy charge below, so a
	# failing sub-action aborts with ZERO economy spent — no orphaned spend
	# (mirrors presentation/combine_action_controller.gd's own established
	# abort-safety invariant). Skipped entirely (resolution_log stays [])
	# when no `controller_for` resolver was ever injected — see
	# `_controller_for_fn`'s own doc — so every PRE-FEAT-297 caller of this
	# controller (every existing DEF-001 regression test in this suite) is
	# completely unaffected.
	var resolution_log: Array = []
	if _controller_for_fn.is_valid():
		var dispatch: Dictionary = _dispatch_sub_actions(queue, accumulated)
		resolution_log = dispatch.get("resolution_log", [])
		if not dispatch.get("ok", false):
			return _rejection_result(dispatch.get("error_code", "SUB_ACTION_FAILED"), resolution_log)

	var result: Dictionary = _charge_action_economy(actor)
	result["resolution_log"] = resolution_log
	return result


## _charge_action_economy(actor) -> Dictionary — THE sole economy-charging
## code path execute() reaches, and ONLY once ValidateCombineQueueUseCase
## has already reported ok=true (see execute()'s own body — this method is
## never called before that gate passes). Charges exactly one action (via
## `_action_economy_port.spend_action()`, when wired) and, on that
## succeeding (or when no action_economy_port was wired at all), exactly
## one Stamina via the actor's own `spend_stamina()` — core/domain/
## combatant.gd's documented sole Stamina mutator.
func _charge_action_economy(actor) -> Dictionary:
	var actions_spent: int = 0
	if _action_economy_port != null:
		var charge: Dictionary = _action_economy_port.spend_action({"name": "COMBINE", "traits": []})
		if not charge.get("success", charge.get("ok", false)):
			return _rejection_result(charge.get("reason", "ACTION_UNAVAILABLE"))
		actions_spent = 1

	var stamina_spent: int = 0
	if actor != null and actor.has_method("spend_stamina"):
		actor.spend_stamina()
		stamina_spent = 1

	return {
		"ok": true,
		"error_code": "",
		"actions_spent": actions_spent,
		"stamina_spent": stamina_spent,
		"resolution_log": [],
	}


## _rejection_result(error_code, resolution_log) -> Dictionary — the SOLE
## failure-shape constructor this file uses, so every rejection (the
## DEF-001 gate, a failing sub-action dispatch, or an action-economy charge
## failure) reports the SAME {ok:false, actions_spent:0, stamina_spent:0}
## shape (test_criteria). `resolution_log` (FEAT-297) defaults to [] — the
## DEF-001 gate itself rejects before any sub-action is ever dispatched, so
## every pre-FEAT-297 caller of this method still observes exactly the same
## Dictionary shape it always has (an empty resolution_log is additive, not
## a breaking change to any existing assertion in this suite).
func _rejection_result(error_code: String, resolution_log: Array = []) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"actions_spent": 0,
		"stamina_spent": 0,
		"resolution_log": resolution_log,
	}


## _dispatch_sub_actions(queue, accumulated) -> Dictionary{ok, resolution_log}
## — FEAT-297 (resolves DEF-NEW-002): the real, order_index-ordered
## sub-action dispatch loop. Sorts `queue` via `_sorted_by_order_index()`
## (order_index, never insertion/array position, is authoritative — mirrors
## ValidateCombineQueueUseCase's own identically-named/purposed helper) and,
## for each entry, resolves its controller via `_controller(verb_id)` (never
## a hard preload/class_name reference), derives that sub-action's targeting
## payload from `accumulated` (`_targeting_payload_for()` below), and
## dispatches `controller.execute(payload, true)` — `true` is the SAME
## no-self-spend-execution flag presentation/combine_action_controller.gd's
## own `_sub_action_resolver()` already establishes: each sub-controller's
## OWN game effect (the move, the attack) still applies exactly as it would
## standalone, but its own action-economy self-charge becomes a no-op for
## the duration of the call — this controller's own `_charge_action_economy()`
## is the ONE real action/Stamina charge, applied once execute() reaches it.
##
## Stops at the first entry whose sub-controller reports ok=false (no
## further entries are dispatched — no orphaned spend past an aborted
## sub-action), returning {ok:false, resolution_log: <every entry resolved
## so far, INCLUDING the failing one>}. When every entry dispatches ok=true,
## returns {ok:true, resolution_log: <every entry, in order_index order>}
## with each entry shaped {"verb_id": <the entry's own verb_id>, "outcome":
## <that sub-controller's own execute() return Dictionary, verbatim>}
## (test_criteria: "resolution_log ... contains {verb_id:'STRIDE',
## outcome:...} followed by {verb_id:'STRIKE', outcome:...}").
func _dispatch_sub_actions(queue: Array, accumulated: Dictionary) -> Dictionary:
	var resolution_log: Array = []
	for entry in _sorted_by_order_index(queue):
		var verb_id: String = _verb_id_of(entry)
		var controller = _controller(verb_id)
		if controller == null:
			resolution_log.append({"verb_id": verb_id, "outcome": {"ok": false, "error_code": "ERR_CONTROLLER_NOT_FOUND"}})
			return {"ok": false, "resolution_log": resolution_log}

		var targeting_payload = _targeting_payload_for(verb_id, accumulated)
		# See this file's own FEAT-297 doc (above `_init()`) for why this is
		# `Callable.call()` rather than `await controller.execute(...)`.
		var outcome = Callable(controller, "execute").call(targeting_payload, true)
		if typeof(outcome) != TYPE_DICTIONARY:
			outcome = {"ok": false, "error_code": "ERR_SUB_ACTION_DID_NOT_RESOLVE_SYNCHRONOUSLY"}

		resolution_log.append({"verb_id": verb_id, "outcome": outcome})
		if not outcome.get("ok", false):
			return {"ok": false, "resolution_log": resolution_log}

	return {"ok": true, "resolution_log": resolution_log}


## _targeting_payload_for(verb_id, accumulated) -> Variant — derives the
## concrete value (a HexCoord for STRIDE, a target_id String for STRIKE) a
## real sub-controller's own `execute(selection, ...)` expects, from that
## verb_id's already-resolved SelectionDescriptor in `accumulated` (the SAME
## `accumulated` Dictionary MultiPhaseTargetingController.execute() builds
## and forwards verbatim onto this controller's own execute() payload).
## Prefers an explicitly-resolved value on the descriptor's own `meta`
## (`meta.chosen_hex`/`meta.chosen_target` — the field
## core/controllers/stride_action_controller.gd's own enter_selection()
## already writes when a Stride selection has been resolved), falling back
## to the first candidate this phase's own descriptor already offers
## (`candidate_targets`/`candidate_hexes`, e.g. StrikeActionController's own
## POST-move-aware reach computation, ADR-006) when no explicit chosen value
## was recorded — so a real Strike dispatch still targets a genuinely
## in-reach, post-move-computed candidate (test_criteria: "real post-move-
## aware Strike targeting honored"), never a stale/pre-move one. Returns
## null (a sub-controller's own `execute(null, ...)` fails safe, never
## crashes) when `accumulated` carries nothing at all for `verb_id`.
func _targeting_payload_for(verb_id: String, accumulated: Dictionary):
	if not accumulated.has(verb_id):
		return null
	var descriptor = accumulated[verb_id]
	if descriptor == null:
		return null

	var meta: Dictionary = descriptor.get("meta", {}) if descriptor is Dictionary else descriptor.meta
	if meta.has("chosen_hex"):
		return meta["chosen_hex"]
	if meta.has("chosen_target"):
		return meta["chosen_target"]

	var candidate_targets: Array = descriptor.get("candidate_targets", []) if descriptor is Dictionary else descriptor.candidate_targets
	if candidate_targets.size() > 0:
		return candidate_targets[0]

	var candidate_hexes: Array = descriptor.get("candidate_hexes", []) if descriptor is Dictionary else descriptor.candidate_hexes
	if candidate_hexes.size() > 0:
		return candidate_hexes[0]

	return null


## _controller(verb_id) -> ActionController/VerbControllerPort or null —
## FEAT-297: the SAME data-driven table-lookup seam
## presentation/combine_action_controller.gd's own `_controller(verb_id)`
## already established, delegating entirely to the injected
## `_controller_for_fn` Callable rather than ever preloading/hard-
## referencing a concrete controller class. Returns null when no resolver
## was ever injected — `_dispatch_sub_actions()` treats that as "sub-action
## controller unavailable", never crashes.
func _controller(verb_id: String):
	if not _controller_for_fn.is_valid():
		return null
	return _controller_for_fn.call(verb_id)


## _verb_id_of(entry) / _order_index_of(entry) / _sorted_by_order_index(entries)
## — duck-typed accessors mirroring
## core/application/combine/validate_combine_queue_use_case.gd's own
## identically-named/purposed helpers exactly, so this controller accepts
## the SAME entry shapes (VerbQueueEntry or an equivalent {"verb_id":...,
## "order_index":...} Dictionary) that use case does, and resolves sub-
## actions in the SAME order_index-authoritative order DEF-001 re-validated
## them in.
func _verb_id_of(entry) -> String:
	if entry is Dictionary:
		return entry.get("verb_id", "")
	return entry.verb_id


func _order_index_of(entry) -> int:
	if entry is Dictionary:
		return entry.get("order_index", 0)
	return entry.order_index


func _sorted_by_order_index(entries: Array) -> Array:
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(func(a, b): return _order_index_of(a) < _order_index_of(b))
	return ordered
