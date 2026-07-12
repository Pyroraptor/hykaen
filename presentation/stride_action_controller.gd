extends "res://presentation/action_controller.gd"

## StrideActionController — the STRIDE verb (FEAT-002/007/178; iteration K
## FEAT-006/008/228). Availability mirrors Step but additionally requires an
## action to remain (can_take_action(), so STRIDE greys the instant this turn's
## one action is spent). execute() opens an OpportunisticStrike reaction window
## for every eligible hostile reactor BEFORE the player's Stride commits (routed
## synchronously through the injected ReactionController), cancelling the Stride
## if a lethal opportunistic Strike downs the mover; otherwise it forwards to
## movement_input_controller.stride_to() and pushes the post-Stride action-budget
## snapshot to the status panel (a Stride emits no event of its own).
##
## Concrete ActionController subclass (presentation/action_controller.gd),
## extracted from MainScene's _verb_bar_stride_* methods (composition-root
## de-bloat, 2026-07-10). Reactor ordering + its fail-loud guard, and the
## per-reactor spent/enemy-reaction Callables, are delegated to the injected
## ReactionController; the initiative table and the living-enemy reactor pool are
## injected as Callables (MainScene still owns encounter/_enemies). MainScene
## keeps thin delegating shims.

const ResolveStrideUseCaseClass = preload("res://core/application/use_cases/resolve_stride_use_case.gd")

var _movement_input_controller
var _status_panel_view
var _resolve_action_use_case
var _reaction
var _action_economy_fn: Callable
var _round_number_fn: Callable
var _after_successful_move_fn: Callable
var _living_enemy_reactors_fn: Callable
var _turn_order_fn: Callable


## Reads (data-driven verb table, 2026-07-11 — see action_controller.gd's _init
## doc): `movement_input_controller`, `status_panel_view`, `resolve_action_use_case`,
## the shared `reaction` ReactionController (also used by Strike), and the Callables
## `action_economy_for`, `current_round_number`, `after_successful_move`,
## `living_enemy_reactors`, `current_turn_order`. `session_holder` is consumed by
## super().
func _init(deps: Dictionary) -> void:
	super(deps)
	_movement_input_controller = deps.get("movement_input_controller", null)
	_status_panel_view = deps.get("status_panel_view", null)
	_resolve_action_use_case = deps.get("resolve_action_use_case", null)
	_reaction = deps.get("reaction", null)
	_action_economy_fn = deps.get("action_economy_for", Callable())
	_round_number_fn = deps.get("current_round_number", Callable())
	_after_successful_move_fn = deps.get("after_successful_move", Callable())
	_living_enemy_reactors_fn = deps.get("living_enemy_reactors", Callable())
	_turn_order_fn = deps.get("current_turn_order", Callable())


func availability() -> bool:
	var action_economy = current_action_economy()
	if action_economy != null and not action_economy.can_take_movement_action():
		return false
	var can_act: bool = action_economy.can_take_action() if action_economy != null else false
	return can_act and _movement_input_controller.get_selectable_stride_hexes().size() > 0


func enter_selection() -> Dictionary:
	return {"verb_id": "STRIDE", "candidate_hexes": _movement_input_controller.get_selectable_stride_hexes(), "candidate_targets": []}


func execute(selection = null) -> Dictionary:
	var actor: Dictionary = current_actor()
	var actor_id: String = actor.get("combatant_id", "")
	var action_economy = current_action_economy()

	var mover_start_hex = actor.get("hex_coord", null)
	if not actor.is_empty() and mover_start_hex != null:
		var candidate_reactors: Array = _reaction.order_candidate_reactors_by_initiative(_living_enemy_reactors_fn.call())
		var turn_order = _turn_order_fn.call()
		if turn_order != null:
			_reaction.assert_candidate_reactors_ordering(candidate_reactors, turn_order)
		var use_case := ResolveStrideUseCaseClass.new()
		var opportunistic_result: Dictionary = await use_case.execute(
			actor, mover_start_hex, candidate_reactors,
			Callable(_reaction, "is_reactor_reaction_spent"),
			Callable(_reaction, "resolve_enemy_opportunistic_strike_reaction"),
			_resolve_action_use_case,
			_action_economy_fn,
			_round_number_fn.call(),
			0
		)
		if not opportunistic_result.get("stride_should_commit", true):
			return {"ok": false, "resolved": false, "error": "ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE"}

	var result: Dictionary = _movement_input_controller.stride_to(selection)
	if result.get("ok", false):
		_after_successful_move_fn.call()
		if _status_panel_view != null and actor_id != "" and action_economy != null:
			_status_panel_view.on_verb_action_budget_changed(
				actor_id, action_economy.get_remaining(), action_economy.is_spent()
			)
	return result
