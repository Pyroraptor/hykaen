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
##
## FEAT-006 (US-006; FR-003/NFR-001; ADR-001): a single ADDITIVE, OPTIONAL
## port widens execute() from "commit the step, then refresh" to "commit the
## step, animate the token to the destination, THEN refresh":
##   `hex_grid_view` — the presentation animation adapter (duck-typed: only
##                      `animate_token_to(combatant_id, target_hex) ->
##                      Signal` is ever called on it), the SAME seam
##                      StrideActionController (FEAT-002) consumes. Left
##                      null by default.
## Degrades exactly per this codebase's established "unwired seam -> legacy
## behavior, never a crash" convention (see presentation/
## stride_action_controller.gd's own FEAT-002 doc): when `hex_grid_view` is
## unwired, no animate_token_to() call is ever made and execute() behaves
## byte-identically to pre-FEAT-006.

var _movement_input_controller
var _after_successful_move_fn: Callable
var _hex_grid_view


## Reads `deps["movement_input_controller"]` and the `deps["after_successful_move"]`
## Callable (data-driven verb table, 2026-07-11 — see action_controller.gd's _init
## doc). `session_holder` is consumed by super(). FEAT-006 additionally reads
## the OPTIONAL `hex_grid_view` duck-typed adapter — see the class-level
## FEAT-006 doc above for its full contract; it defaults to null so every
## pre-existing caller (that never supplies this key) is unaffected.
func _init(deps: Dictionary) -> void:
	super(deps)
	_movement_input_controller = deps.get("movement_input_controller", null)
	_after_successful_move_fn = deps.get("after_successful_move", Callable())
	_hex_grid_view = deps.get("hex_grid_view", null)


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
		# FEAT-006: animate the single-hop token move to the destination
		# BEFORE the post-move refresh runs -- mirrors
		# StrideActionController's own per-hex animate_token_to() call
		# (FEAT-002). A no-op when `_hex_grid_view` is unwired (legacy-
		# behavior contract).
		if _hex_grid_view != null:
			var actor = current_actor()
			var actor_id: String = actor.get("combatant_id", "") if actor != null else ""
			await _hex_grid_view.animate_token_to(actor_id, selection)
		_after_successful_move_fn.call()
	return result
