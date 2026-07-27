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
##
## FEAT-002 (US-002; FR-002/NFR-001/NFR-004/NFR-005; ADR-001/ADR-002): two
## ADDITIVE, OPTIONAL ports widen execute() from "evaluate Opportunistic
## Strike once at the mover's pre-Stride hex" to "evaluate it once per transit
## hex along the full Stride path, animating the token through each hex in
## order":
##   `pathfinder_fn`  — Callable(start: HexCoord, goal: HexCoord) ->
##                       Array[HexCoord], the SAME port shape core/geometry/
##                       hex_pathfinder.gd's HexPathfinder.find_path()
##                       fulfils (composition root wires the concrete
##                       adapter later; this controller only ever calls the
##                       injected Callable, never HexPathfinder directly —
##                       ADR-002 Dependency Inversion). Left an invalid
##                       (unbound) Callable by default.
##   `hex_grid_view`   — the presentation animation adapter (duck-typed:
##                        only `animate_token_to(combatant_id, target_hex) ->
##                        Signal` is ever called on it). Left null by default.
## Both degrade safely per this codebase's established "unwired seam ->
## legacy behavior, never a crash" convention (see this file's other
## Callable fields above): when `pathfinder_fn` is unwired, OR it answers a
## path shorter than 2 hexes (no route / start==goal), execute() falls back
## to the direct 2-hex path `[mover_start_hex, selection]` — the EXACT path
## shape every pre-existing caller implicitly walked (a single Opportunistic
## Strike window at the start hex, then an unconditional commit) — so every
## regression test written before this feature, and every real caller that
## has not yet been wired to a live pathfinder (per MainScene's own
## composition-root rewiring, a LATER feature), observes byte-identical
## behavior. When `hex_grid_view` is unwired, no animate_token_to() call is
## ever made — `_movement_input_controller.stride_to()` (below) already owns
## resyncing the token's rendered position once the Stride commits, exactly
## as it did before this feature.
##
## NFR-005 known limitation (ADR-004, documented per this feature's own
## error_handling design note, NOT silently worked around): the passability/
## occupancy snapshot `pathfinder_fn`'s underlying adapter closes over is
## taken at MainScene composition/rewire time, not refreshed per transit hex
## as THIS loop below evaluates Opportunistic Strike and repositions
## combatants — a combatant who dies or moves mid-Stride (e.g. a reactor
## downed by an earlier transit hex's own Opportunistic Strike, or another
## actor's move resolving concurrently) can leave the remaining path stale.
## This is an accepted, presentation/pathing-only inconvenience, never a
## domain-integrity risk: core/rules/movement.gd's Movement.stride() (invoked
## via `_movement_input_controller.stride_to()` below, strictly AFTER this
## whole per-hex loop completes) independently re-validates the actor's
## FINAL destination against the CURRENT live occupancy/passability state
## before ever mutating hex_coord — a stale path can misroute the visual
## walk, but can never commit an illegal domain move.

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
var _pathfinder_fn: Callable
var _hex_grid_view


## Reads (data-driven verb table, 2026-07-11 — see action_controller.gd's _init
## doc): `movement_input_controller`, `status_panel_view`, `resolve_action_use_case`,
## the shared `reaction` ReactionController (also used by Strike), and the Callables
## `action_economy_for`, `current_round_number`, `after_successful_move`,
## `living_enemy_reactors`, `current_turn_order`. `session_holder` is consumed by
## super(). FEAT-002 additionally reads the OPTIONAL `pathfinder_fn` Callable
## and `hex_grid_view` duck-typed adapter — see the class-level FEAT-002 doc
## above for their full contract; both default to an unwired/absent state so
## every pre-existing caller (that never supplies these two keys) is
## unaffected.
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
	_pathfinder_fn = deps.get("pathfinder_fn", Callable())
	_hex_grid_view = deps.get("hex_grid_view", null)


func availability() -> bool:
	var action_economy = current_action_economy()
	if action_economy != null and not action_economy.can_take_movement_action():
		return false
	var can_act: bool = action_economy.can_take_action() if action_economy != null else false
	return can_act and _movement_input_controller.get_selectable_stride_hexes().size() > 0


func enter_selection() -> Dictionary:
	return {"verb_id": "STRIDE", "candidate_hexes": _movement_input_controller.get_selectable_stride_hexes(), "candidate_targets": []}


## execute(selection, no_self_spend_execution) -> Dictionary
##
## no_self_spend_execution — FEAT-008 (US-008; FR-007; ADR-003): the
## no-self-spend execution-mode flag. Defaults to false, so every
## PRE-EXISTING caller (MainScene's own `_verb_bar_stride_execute()` shim,
## and every standalone/verb-bar Stride) is completely unaffected and still
## self-charges exactly one action from the actor's live ActionEconomy,
## exactly as before this feature. presentation/combine_action_controller.gd
## passes true ONLY when resolving this controller AS a Combine sub-action
## (see that file's own `_sub_action_resolver()` doc): while true, this
## Stride's own game effect (the actual move, via
## `_movement_input_controller.stride_to()`) still applies, but the SAME
## shared per-round action-economy budget/gates are left completely
## untouched (core/rules/action_economy.gd's
## begin_self_spend_suppression()/end_self_spend_suppression() — see that
## file's own FEAT-008 doc) — Combine charges the ONE real action (and the
## Movement-trait lockout) once, at the Combine level, after its whole
## sub-action queue resolves.
##
## FEAT-002 path/per-hex-OS extension (US-002; FR-002/NFR-001/NFR-004/
## NFR-005; ADR-001/ADR-002): `mover_start_hex`..`selection` is walked as a
## PATH (via `_pathfinder_fn`, falling back to the direct 2-hex
## `[mover_start_hex, selection]` — see this file's class-level FEAT-002 doc
## for the full fallback contract), and ResolveStrideUseCaseClass.execute()
## (ADR-002: the SAME application-layer use case, reused unforked — never a
## second/duplicated Opportunistic Strike resolution path) is awaited ONCE
## PER TRANSIT HEX (every path hex except the final goal — the hex the mover
## is LEAVING at that step, mirroring the pre-existing single-hex call's own
## "evaluate at the hex about to be departed" semantics). The FIRST transit
## hex whose window downs the mover aborts the WHOLE Stride immediately —
## no further transit hex is evaluated, `_hex_grid_view.animate_token_to()`
## is never called for the aborted step, and
## `_movement_input_controller.stride_to()` (the actual commit, below) is
## never reached — the actor's domain position stays exactly where it was
## before this execute() call began.
func execute(selection = null, no_self_spend_execution: bool = false) -> Dictionary:
	# Phase C.3/C.4: the mover is the LIVE actor instance — it is passed straight
	# into ResolveStrideUseCase.execute(), where an Opportunistic Strike against
	# the mover applies take_damage() by reference; a to_dict() copy here would
	# silently drop that damage (the mover-downed gate would never fire).
	var actor = current_actor_entity()
	var actor_id: String = actor.display_id() if actor != null else ""
	var action_economy = current_action_economy()

	var mover_start_hex = actor.hex_coord if actor != null else null
	if actor != null and mover_start_hex != null:
		var candidate_reactors: Array = _reaction.order_candidate_reactors_by_initiative(_living_enemy_reactors_fn.call())
		var turn_order = _turn_order_fn.call()
		if turn_order != null:
			_reaction.assert_candidate_reactors_ordering(candidate_reactors, turn_order)

		# Path-degradation ladder (ADR-001/error_handling design note): an
		# unwired `_pathfinder_fn`, or one that answers a path shorter than 2
		# hexes (no route found, or start==goal), falls back to the direct
		# 2-hex path -- the EXACT shape every pre-FEAT-002 caller/test walked,
		# preserving byte-identical legacy behavior for every currently-live
		# call site (none of which wire `pathfinder_fn` yet).
		var path: Array = []
		if _pathfinder_fn.is_valid():
			var pathfinder_result = _pathfinder_fn.call(mover_start_hex, selection)
			if pathfinder_result is Array:
				path = pathfinder_result
		if path.size() < 2:
			path = [mover_start_hex, selection]

		for i in range(path.size() - 1):
			var transit_hex = path[i]
			var use_case := ResolveStrideUseCaseClass.new()
			var opportunistic_result: Dictionary = await use_case.execute(
				actor, transit_hex, candidate_reactors,
				Callable(_reaction, "is_reactor_reaction_spent"),
				Callable(_reaction, "resolve_enemy_opportunistic_strike_reaction"),
				_resolve_action_use_case,
				_action_economy_fn,
				_round_number_fn.call(),
				0
			)
			if not opportunistic_result.get("stride_should_commit", true):
				return {"ok": false, "resolved": false, "error": "ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE"}

			# NFR-001/NFR-004: the visual per-hex walk. `path[i]`'s window has
			# just cleared (mover survives leaving it), so it is now safe to
			# animate the token INTO the next hex in the path, in order, one
			# hop at a time -- mirrors presentation/exploration_mode_
			# controller.gd's own _execute_exploration_path() step-then-
			# animate convention. A no-op when `_hex_grid_view` is unwired
			# (RISK-002 / legacy-behavior contract).
			if _hex_grid_view != null:
				await _hex_grid_view.animate_token_to(actor_id, path[i + 1])

	# FEAT-008: brackets ONLY the actual self-charge point
	# (`_movement_input_controller.stride_to()` -> core/rules/movement.gd's
	# Stride() -> action_economy.spend_action()) — the SAME live actor
	# ActionEconomy instance `_movement_input_controller` was configure()d
	# with (session.current_action_economy(), per
	# presentation/turn_presentation_controller.gd's own
	# on_active_actor_changed()), so suppressing it here reaches the exact
	# instance the self-charge would otherwise mutate.
	if no_self_spend_execution and action_economy != null:
		action_economy.begin_self_spend_suppression()
	var result: Dictionary = _movement_input_controller.stride_to(selection)
	if no_self_spend_execution and action_economy != null:
		action_economy.end_self_spend_suppression()
	if result.get("ok", false):
		_after_successful_move_fn.call()
		if _status_panel_view != null and actor_id != "" and action_economy != null:
			_status_panel_view.on_verb_action_budget_changed(
				actor_id, action_economy.get_remaining(), action_economy.is_spent()
			)
	return result
