class_name TurnPresentationController
extends RefCounted

## TurnPresentationController — owns the "a new actor's turn just started"
## presentation reaction that used to live inline in MainScene.gd (FEAT-006 /
## US-006, ADR-004; the design notes' API contract #1 "turn_started", which this
## codebase realizes as TurnController.active_actor_changed). On each settled
## active actor it: reconfigures the movement_input_controller for that actor,
## re-highlights the legal Step/Stride union on the hex grid, re-gates the verb
## bar, and re-pushes every combatant's action budget to the status panel.
##
## Composition-root de-bloat (2026-07-10): extracted from MainScene.gd. All
## collaborators are injected ONCE at construction. The live per-round
## RoundSession is reached through the stable RoundSessionHolder
## (infrastructure/round_session_holder.gd) rather than a raw reference, so this
## controller keeps working across round rollovers without re-injection. The
## roster query MainScene owns (_other_living_combatants) is injected as a
## Callable, following this codebase's established set_*_fn injection idiom.
## MainScene retains a thin _on_active_actor_changed() shim that delegates here
## (the TurnController signal and integration tests drive that seam).

var _session_holder
var _movement_input_controller
var _hex_grid_view
var _verb_bar_view
var _status_panel_view
var _other_living_combatants_fn: Callable

## The most recent structured highlight debug line (observability requirement,
## FEAT-006): recorded here so GUT tests can assert on it directly, since stdout
## itself is not readily interceptable from a headless GUT run.
var last_highlight_debug_log: String = ""


func _init(
	session_holder,
	movement_input_controller,
	hex_grid_view,
	verb_bar_view,
	status_panel_view,
	other_living_combatants_fn: Callable
) -> void:
	_session_holder = session_holder
	_movement_input_controller = movement_input_controller
	_hex_grid_view = hex_grid_view
	_verb_bar_view = verb_bar_view
	_status_panel_view = status_panel_view
	_other_living_combatants_fn = other_living_combatants_fn


## on_active_actor_changed(combatant) -> void — TurnController emits its
## active_actor_changed once it settles on a new (player) current actor, whether
## at boot or after auto-driving a run of Enemy turns. Reconfigures the
## movement_input_controller with the live actor/action-economy/live-target data
## TurnController itself does not own, so its Step/Stride affordance stays live
## for whichever combatant's turn it now is.
func on_active_actor_changed(combatant: Dictionary) -> void:
	var session = _session_holder.get_current()
	if session == null:
		return
	var action_economy = session.current_action_economy()
	var active_combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))

	_movement_input_controller.configure(
		combatant,
		_other_living_combatants_fn.call(combatant),
		_hex_grid_view,
		active_combatant_id,
		action_economy
	)

	highlight_legal_moves(combatant, active_combatant_id)

	# Re-gate the Layer 1 verb bar for whoever the turn now belongs to -- the
	# movement_input_controller above is now configured for the NEW actor, and
	# STRIKE's closures read the session/enemies live, so is_available() reflects
	# current state, never a stale prior-actor's gating.
	if _verb_bar_view != null:
		_verb_bar_view.refresh_availability()

	# Re-push EVERY combatant's action budget now that control has settled back on
	# a player after any auto-driven Enemy turn(s). An Enemy Stride/WAIT spends a
	# budget action while emitting no event, so the enemy row's Actions/Spent
	# readout would otherwise stay stale.
	refresh_all_action_budgets()


## refresh_all_action_budgets() -> void — pushes each combatant's current
## Actions-remaining/Spent state to the status panel from the live session's
## action_budget_snapshot(). Idempotent; only READS the live economies and
## forwards them through StatusPanelView's existing per-combatant update
## contract. A no-op when no session/panel is wired.
func refresh_all_action_budgets() -> void:
	var session = _session_holder.get_current()
	if session == null or _status_panel_view == null:
		return
	for row in session.action_budget_snapshot():
		_status_panel_view.on_verb_action_budget_changed(
			row["combatant_id"], row["remaining"], row["spent"]
		)


## highlight_legal_moves(combatant, active_combatant_id) -> void — computes
## union(get_selectable_step_hexes(), get_selectable_stride_hexes()) for the
## now-configured actor and pushes it to hex_grid_view.set_selectable_hexes().
## For a non-player (enemy) turn no highlight may be shown, so an empty set is
## pushed instead. Records a structured debug line either way.
func highlight_legal_moves(combatant: Dictionary, active_combatant_id: String) -> void:
	var is_enemy_turn: bool = combatant.get("_is_enemy", false)

	if is_enemy_turn:
		if _hex_grid_view != null:
			_hex_grid_view.set_selectable_hexes([])
		last_highlight_debug_log = (
			"DEBUG: highlight_legal_moves combatant_id=" + active_combatant_id
			+ " step_hex_count=0 stride_hex_count=0 (non-player turn, highlight suppressed)"
		)
		print(last_highlight_debug_log)
		return

	var step_hexes: Array = _movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = _movement_input_controller.get_selectable_stride_hexes()
	var union_hexes: Array = _union_hexes(step_hexes, stride_hexes)

	if _hex_grid_view != null:
		_hex_grid_view.set_selectable_hexes(union_hexes)

	last_highlight_debug_log = (
		"DEBUG: highlight_legal_moves combatant_id=" + active_combatant_id
		+ " step_hex_count=" + str(step_hexes.size())
		+ " stride_hex_count=" + str(stride_hexes.size())
	)
	print(last_highlight_debug_log)


## _union_hexes(step_hexes, stride_hexes) -> Array — the deduplicated union of
## two HexCoord arrays, compared via core/geometry/hex_coord.gd's equals(). Every
## legal Step destination is currently also a legal Stride destination, so this
## reduces to stride_hexes today -- but is computed as an explicit union so it
## stays correct if that relationship between the two rules ever changes.
func _union_hexes(step_hexes: Array, stride_hexes: Array) -> Array:
	var union_hexes: Array = []
	for hex_coord in step_hexes:
		union_hexes.append(hex_coord)
	for hex_coord in stride_hexes:
		var already_included: bool = false
		for existing in union_hexes:
			if existing.equals(hex_coord):
				already_included = true
				break
		if not already_included:
			union_hexes.append(hex_coord)
	return union_hexes
