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
## resolution) and enter_selection()'s own queue-builder wiring are LATER
## features layered on top of this same seam, without changing it.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage:
##   var controller := CombineActionController.new({
##       "validate_combine_queue_use_case": ValidateCombineQueueUseCase.new(),
##       "verb_registry_port": verb_registry_port,
##       "action_economy_port": action_economy_port,
##   })
##   var result: Dictionary = controller.execute({
##       "queue": confirmed_queue.sorted_entries(),
##       "actor": actor,
##       "context": CombineQueue.Context.TURN,
##   })
##   # {"ok": true, "error_code": "", "actions_spent": 1, "stamina_spent": 1, "resolution_log": []}

class_name CombineActionController
extends RefCounted

const ValidateCombineQueueUseCaseClass = preload("res://core/application/combine/validate_combine_queue_use_case.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

## The APPLICATION-layer use case this controller's execute() routes its
## DEF-001 re-validation gate through. Defaults to a fresh instance so a
## caller need not always inject one, but a test may substitute its own
## (e.g. a spy) via `deps["validate_combine_queue_use_case"]`.
var _validate_combine_queue_use_case

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


func _init(deps: Dictionary = {}) -> void:
	_validate_combine_queue_use_case = deps.get("validate_combine_queue_use_case", ValidateCombineQueueUseCaseClass.new())
	_verb_registry_port = deps.get("verb_registry_port")
	_action_economy_port = deps.get("action_economy_port")


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

	# DEF-001 — the authoritative re-validation gate, invoked as the FIRST
	# statement of execute(), strictly before any economy charge below.
	var validation: Dictionary = _validate_combine_queue_use_case.execute(queue, actor, context, _verb_registry_port)
	if not validation.get("ok", false):
		return _rejection_result(validation.get("error_code", "VALIDATION_FAILED"))

	return _charge_action_economy(actor)


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


## _rejection_result(error_code) -> Dictionary — the SOLE failure-shape
## constructor this file uses, so every rejection (the DEF-001 gate above,
## or an action-economy charge failure) reports the SAME
## {ok:false, actions_spent:0, stamina_spent:0} shape (test_criteria).
func _rejection_result(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"actions_spent": 0,
		"stamina_spent": 0,
	}
