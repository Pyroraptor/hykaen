extends "res://presentation/action_controller.gd"

## StepActionController — the STEP verb (FEAT-002/FEAT-007). Available when the
## actor may still take a movement action this turn AND at least one legal Step
## destination exists; execute() forwards the picked destination to the injected,
## reused movement_input_controller.step_to() (the SOLE Step entry point) and, on
## success, runs MainScene's post-move refresh via the injected Callable.
##
## Concrete ActionController subclass (presentation/action_controller.gd),
## extracted from MainScene's _verb_bar_step_* methods (composition-root de-bloat,
## 2026-07-10). MainScene keeps thin delegating shims.

var _movement_input_controller
var _after_successful_move_fn: Callable


## Reads `deps["movement_input_controller"]` and the `deps["after_successful_move"]`
## Callable (data-driven verb table, 2026-07-11 — see action_controller.gd's _init
## doc). `session_holder` is consumed by super().
func _init(deps: Dictionary) -> void:
	super(deps)
	_movement_input_controller = deps.get("movement_input_controller", null)
	_after_successful_move_fn = deps.get("after_successful_move", Callable())


func availability() -> bool:
	var action_economy = current_action_economy()
	if action_economy != null and not action_economy.can_take_movement_action():
		return false
	return _movement_input_controller.get_selectable_step_hexes().size() > 0


func enter_selection() -> Dictionary:
	return {"verb_id": "STEP", "candidate_hexes": _movement_input_controller.get_selectable_step_hexes(), "candidate_targets": []}


func execute(selection = null) -> Dictionary:
	var result: Dictionary = _movement_input_controller.step_to(selection)
	if result.get("ok", false):
		_after_successful_move_fn.call()
	return result
