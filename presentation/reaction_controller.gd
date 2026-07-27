class_name ReactionController
extends RefCounted

## ReactionController - owns the composition root's reaction-resolution seams,
## extracted from MainScene.gd (composition-root de-bloat, 2026-07-10):
##   - the enemy target's own Dodge-Step on the player-Strikes-enemy path,
##   - the enemy-mover Stride opportunistic-strike window (the Callable
##     ai_decision_port.set_stride_reaction_resolver_fn awaits),
##   - the player-reactor and enemy-reactor opportunistic-strike halves,
##   - the reactor initiative-ordering helper + its fail-loud ordering guard.
##
## Collaborators are injected: `action_economy_fn` and `round_number_fn` are
## Callables (the live ActionEconomy lookup MainScene still owns, and the mutable
## ROUND_NUMBER, respectively - never captured stale); resolve_action_use_case /
## turn_controller / enemy_reaction_chooser / hex_grid_view are the stable
## composition-root references (set once in _ready(), never reassigned).
##
## MainScene keeps thin _resolve_*/… shims that delegate here, so the existing
## Callable(self, "…") registrations into the domain use-cases, the strike/stride
## execute call sites, and the direct-call tests all keep working unchanged.

const ResolveStrideUseCaseClass    = preload("res://core/application/use_cases/resolve_stride_use_case.gd")
const OpenReactionWindowUseCaseClass = preload("res://core/application/open_reaction_window_use_case.gd")
const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")
const AIHexChoiceResolverClass     = preload("res://infrastructure/ai_hex_choice_resolver.gd")

var _action_economy_fn: Callable
var _round_number_fn: Callable
var _resolve_action_use_case
var _turn_controller
var _enemy_reaction_chooser
var _hex_grid_view


func _init(
	action_economy_fn: Callable,
	round_number_fn: Callable,
	resolve_action_use_case,
	turn_controller,
	enemy_reaction_chooser,
	hex_grid_view
) -> void:
	_action_economy_fn = action_economy_fn
	_round_number_fn = round_number_fn
	_resolve_action_use_case = resolve_action_use_case
	_turn_controller = turn_controller
	_enemy_reaction_chooser = enemy_reaction_chooser
	_hex_grid_view = hex_grid_view


## resolve_enemy_dodge_step(target, resolve_result, attacker_hex, legal_hexes) ->
## void - FEAT-005 (US-005, ADR-004): the enemy target's own Dodge-Step on the
## player-Strikes-enemy path. A no-op unless resolve_result["defender_stepped"].
## Delegates the whole whether/how-to-relocate decision to the SAME
## ResolveDodgeStepUseCase round_session.gd's seam consumes, resolving the hex
## SYNCHRONOUSLY via AIHexChoiceResolver (no player pop-up).
func resolve_enemy_dodge_step(target, resolve_result: Dictionary, attacker_hex, legal_hexes: Array) -> void:
	if not resolve_result.get("defender_stepped", false):
		return

	# Phase C.3/C.4: `target` is the LIVE defender instance — ResolveDodgeStepUseCase
	# repositions it via move_to() by reference, so the token/hex both persist.
	var defender_id: String = target.display_id()
	var ai_hex_resolver := AIHexChoiceResolverClass.new(attacker_hex)
	var token_reposition_fn: Callable = Callable()
	if _hex_grid_view != null:
		token_reposition_fn = Callable(_hex_grid_view, "move_token")

	var use_case := ResolveDodgeStepUseCaseClass.new()
	await use_case.resolve(
		defender_id, true, legal_hexes, Callable(ai_hex_resolver, "resolve"),
		token_reposition_fn, target
	)


## is_reactor_reaction_spent(reactor) -> bool - FEAT-006 (US-006): the
## reactor_spent_fn Callable ResolveStrideUseCase awaits per candidate reactor,
## backed by the SAME live ActionEconomy lookup every other reaction seam uses.
## Defaults to "not spent" when no tracked ActionEconomy exists.
func is_reactor_reaction_spent(reactor) -> bool:
	var reactor_action_economy = _action_economy_fn.call(reactor)
	return reactor_action_economy.is_spent() if reactor_action_economy != null else false


## resolve_enemy_stride_opportunistic_window(mover, mover_start_hex,
## candidate_reactors, stride_path: Array = []) -> Dictionary - FEAT-006
## (US-006, ADR-004); widened additively by FEAT-003 (US-003; FR-005/
## NFR-001/NFR-004; ADR-003) with the 4th, OPTIONAL `stride_path` parameter.
## The Callable ai.gd's _stride_reaction_resolver_fn seam awaits for the
## ENEMY-mover Stride path.
##
## FEAT-003: mirrors presentation/stride_action_controller.gd's FEAT-002
## per-transit-hex extension of the PLAYER-mover path, so both movers are
## proven symmetrically per this steel thread's own exit criteria -- BOTH
## paths ultimately drive the SAME ResolveStrideUseCase/
## OpportunisticStrikeEligibility contract via _single_hex_stride_os() below.
## ALWAYS evaluates a window at `mover_start_hex` first (byte-identical to
## every legacy 3-argument caller's pre-existing single-hex behavior --
## `stride_path` defaults to an empty Array, in which case this method
## returns exactly that one evaluation, unchanged). When `stride_path` is
## non-empty, iterates stride_path indices 1 through size()-2 inclusive
## (index 0 is presumed equal to `mover_start_hex`, already evaluated;
## the LAST element is the destination the mover ARRIVES at and is NOT
## evaluated -- OS fires only when LEAVING a hex, not when arriving),
## evaluating one more window per hex and STOPPING immediately at (and
## returning) the FIRST result whose "stride_should_commit" comes back
## false -- mirroring core/application/use_cases/resolve_stride_use_case.gd's
## own per-reactor short-circuit contract one level up, at the per-hex
## granularity. Callers (ai.gd) pass the FULL pathfinder path including the
## destination; the slice(1,-1) loop here handles the skip.
func resolve_enemy_stride_opportunistic_window(mover, mover_start_hex, candidate_reactors: Array, stride_path: Array = []) -> Dictionary:
	var actor_id: String = mover.display_id() if mover.has_method("display_id") else ""

	# Evaluate OS at the mover's start hex — mover is already there, no animation needed.
	var result: Dictionary = await _single_hex_stride_os(mover, mover_start_hex, candidate_reactors)
	if not result.get("stride_should_commit", true):
		return result

	# For each transit hex: animate the token there first so the player sees
	# where the enemy is, then open the OS window.  If the mover is downed, stop
	# immediately and return without animating further (caller holds the token at
	# the downed hex).
	for i in range(1, stride_path.size() - 1):
		if _hex_grid_view != null and actor_id != "":
			await _hex_grid_view.animate_token_to(actor_id, stride_path[i])
		result = await _single_hex_stride_os(mover, stride_path[i], candidate_reactors)
		if not result.get("stride_should_commit", true):
			return result

	# All OS windows cleared — animate to the final destination and signal that
	# the full path has already been animated so round_session skips re-animation.
	if _hex_grid_view != null and actor_id != "" and stride_path.size() >= 2:
		await _hex_grid_view.animate_token_to(actor_id, stride_path[stride_path.size() - 1])
		result["animation_complete"] = true

	return result


## _single_hex_stride_os(mover, hex, candidate_reactors) -> Dictionary -
## FEAT-003 (US-003, ADR-003): the single-hex Opportunistic Strike evaluation
## extracted UNCHANGED from resolve_enemy_stride_opportunistic_window()'s own
## pre-FEAT-003 inline body, so BOTH the mover_start_hex evaluation and every
## additional stride_path hex share the exact same, single, tested code path
## -- drives ResolveStrideUseCase.execute() with per-reactor spent/resolver
## Callables, routing the PLAYER reactor to resolve_player_opportunistic_strike_
## reaction() (the real, awaited pop-up).
func _single_hex_stride_os(mover, hex, candidate_reactors: Array) -> Dictionary:
	var use_case := ResolveStrideUseCaseClass.new()
	return await use_case.execute(
		mover, hex, candidate_reactors,
		Callable(self, "is_reactor_reaction_spent"),
		Callable(self, "resolve_player_opportunistic_strike_reaction"),
		_resolve_action_use_case,
		_action_economy_fn,
		_round_number_fn.call(),
		0
	)


## resolve_player_opportunistic_strike_reaction(reactor, context) -> Dictionary -
## FEAT-006 (US-006): the player-reactor half. Delegates to
## turn_controller.resolve_opportunistic_strike_reaction() (a genuinely blocking
## pop-up). Degrades to Pass ({"choice": "none"}) when turn_controller is unwired.
func resolve_player_opportunistic_strike_reaction(reactor, context: Dictionary) -> Dictionary:
	if _turn_controller == null:
		return {"choice": "none"}

	return await _turn_controller.resolve_opportunistic_strike_reaction(
		reactor, context, _action_economy_fn.call(reactor), _round_number_fn.call()
	)


## resolve_enemy_opportunistic_strike_reaction(reactor, context) -> Dictionary -
## FEAT-006 (US-006): the enemy-reactor half, consulted for the PLAYER-mover
## Stride path. Synchronous end to end (OpenReactionWindowUseCase.open() never
## awaits, and the AIReactionPolicy chooser never suspends), so NO pop-up opens.
func resolve_enemy_opportunistic_strike_reaction(reactor, context: Dictionary) -> Dictionary:
	var reaction_context: Dictionary = context.duplicate()
	var reactor_action_economy = _action_economy_fn.call(reactor)
	if reactor_action_economy != null:
		reaction_context["action_current"] = reactor_action_economy.get_remaining()

	var open_use_case := OpenReactionWindowUseCaseClass.new()
	var choice: String = open_use_case.open(
		OpenReactionWindowUseCaseClass.WINDOW_OPPORTUNISTIC_STRIKE,
		OpenReactionWindowUseCaseClass.legal_opportunistic_strike_reactions(),
		reaction_context,
		_enemy_reaction_chooser
	)
	return {"choice": choice}


## order_candidate_reactors_by_initiative(candidates) -> Array - FEAT-228: orders
## candidate reactors by rolled initiative (descending), ties broken by spawn
## order, so Opportunistic Strikes resolve in initiative order.
func order_candidate_reactors_by_initiative(candidates: Array) -> Array:
	var indexed: Array = []
	for i in range(candidates.size()):
		indexed.append({"candidate": candidates[i], "spawn_index": i})

	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Phase C.3/C.4: candidates are Combatant instances — read initiative_roll
		# (the entity field) rather than the "_initiative_roll" dict key.
		var roll_a: int = a["candidate"].initiative_roll
		var roll_b: int = b["candidate"].initiative_roll
		if roll_a == roll_b:
			return a["spawn_index"] < b["spawn_index"]
		return roll_a > roll_b
	)

	var ordered: Array = []
	for entry in indexed:
		ordered.append(entry["candidate"])
	return ordered


## assert_candidate_reactors_ordering(ordered_candidates, turn_order) -> bool -
## FEAT-228 (resolves FIND-224): the fail-loud guard that fires if the resolved
## ordering is ever inconsistent with encounter.get_turn_order()'s rolled
## initiative table. Returns true when consistent; on a violation, a real
## assert() fires AND push_error() logs (defense-in-depth), then returns false so
## a GUT test can observe the violation via the return value.
func assert_candidate_reactors_ordering(ordered_candidates: Array, turn_order: Array) -> bool:
	var turn_order_index: Dictionary = {}
	for i in range(turn_order.size()):
		var entry_id: String = turn_order[i].display_id()
		turn_order_index[entry_id] = i

	var last_index: int = -1
	for candidate in ordered_candidates:
		var candidate_id: String = candidate.display_id()

		if not turn_order_index.has(candidate_id):
			var missing_message: String = (
				"ReactionController: Opportunistic Strike candidate reactor '%s' is absent from encounter.get_turn_order() -- ordering cannot be verified against the rolled initiative table"
				% candidate_id
			)
			assert(false, missing_message)
			push_error(missing_message)
			return false

		var index: int = turn_order_index[candidate_id]
		if index < last_index:
			var order_message: String = (
				"ReactionController: Opportunistic Strike candidate_reactors ordering violates the rolled initiative table -- '%s' (turn_order index %d) resolved out of initiative order (previous candidate's turn_order index %d)"
				% [candidate_id, index, last_index]
			)
			assert(false, order_message)
			push_error(order_message)
			return false

		last_index = index

	return true
