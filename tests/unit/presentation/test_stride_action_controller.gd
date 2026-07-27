extends GutTest
## tests/unit/presentation/test_stride_action_controller.gd
##
## GUT suite for FEAT-002 (US-002; FR-002/NFR-001/NFR-004/NFR-005; ADR-001/
## ADR-002/ADR-004): presentation/stride_action_controller.gd's
## StrideActionController.execute() — widened from "evaluate Opportunistic
## Strike once at the mover's pre-Stride hex" to "compute a full path via an
## optional injected `pathfinder_fn`, evaluate Opportunistic Strike once per
## TRANSIT hex (every path hex except the final goal), and animate the token
## through each subsequent hex via an optional injected `hex_grid_view` —
## all while preserving byte-identical legacy behavior when either seam is
## left unwired.
##
## Mirrors tests/unit/test_combine_abort_illegal_stride.gd's established
## "real fake session + real ActionEconomy, no MainScene.tscn boot required"
## convention, plus tests/unit/core/application/use_cases/
## test_resolve_stride_use_case.gd's FakeStrikeUseCase/FakeReactorActionEconomy
## doubles (reused here so a lethal Opportunistic Strike can be scripted end
## to end through the REAL ResolveStrideUseCase this controller drives).
##
## Fixture geometry: a straight 3-hex path start=(0,0) -> h1=(1,0) ->
## goal=(2,0). Three reactor hexes are picked so each is adjacent to EXACTLY
## one of the three path hexes (never two), so a resolver call against a
## given reactor unambiguously proves OS was evaluated at that reactor's
## own adjacent hex:
##   reactor_start_only @ (-1,0) — adjacent to (0,0) only
##   reactor_h1_only    @ (2,-1) — adjacent to (1,0) only
##   reactor_goal_only  @ (3,0)  — adjacent to (2,0) only
##
## test_criteria covered:
##   1. OS is evaluated once per transit hex (not only at start hex) using a
##      fake pathfinder_fn returning a multi-hex path.
##   2. Mover downed at the first transit hex aborts stride without calling
##      stride_to()/commit and returns {ok:false, resolved:false,
##      error:'ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE'}.
##   3. Path falls back to direct [start, goal] when pathfinder_fn is unwired
##      or returns size<2.
##   4. animate_token_to is called once per transit hex, in order, using a
##      deterministic stub (no real Tween/timers).
##   5. Byte-identical legacy behavior confirmed when pathfinder_fn/
##      hex_grid_view are not wired at all.
##   6. Self-spend suppression on the final stride_to() commit is preserved.

const StrideActionControllerClass = preload("res://presentation/stride_action_controller.gd")
const RoundSessionHolderClass     = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass          = preload("res://core/rules/action_economy.gd")


# ══════════════════════════════════════════════════════════════════════════
# Fakes / doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeSession — mirrors tests/unit/test_combine_abort_illegal_stride.gd's
## established minimal double satisfying the current_actor()/
## current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's base class reads through the
## injected session_holder.
class FakeSession:
	var _actor
	var _economy

	func _init(actor, economy) -> void:
		_actor = actor
		_economy = economy

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return _economy


## FakeMovementInputController — records every stride_to() call (the
## selection it was handed, and whether the actor's live ActionEconomy was
## self-spend-suppressed AT THE MOMENT of the call) and answers a scripted
## result Dictionary. get_selectable_stride_hexes() is unused by execute()
## itself (only by availability()/enter_selection(), not under test here)
## but is implemented anyway so this double stays a complete stand-in.
class FakeMovementInputController:
	var stride_to_calls: Array = []
	var suppressed_at_call_time: Array = []
	var result_to_return: Dictionary = {"ok": true}
	var _economy

	func _init(economy = null) -> void:
		_economy = economy

	func get_selectable_stride_hexes() -> Array:
		return []

	func stride_to(destination_hex) -> Dictionary:
		stride_to_calls.append(destination_hex)
		suppressed_at_call_time.append(_economy.is_self_spend_suppressed() if _economy != null else false)
		return result_to_return


## FakeReaction — a minimal stand-in for the injected ReactionController,
## implementing only the four methods StrideActionController.execute() ever
## calls on it. `resolver_calls` records (reactor.display_id(), transit
## context) so a test can assert exactly WHICH reactor got a window opened
## and how many times — proving OS was (or was not) evaluated at a given
## transit hex. `choice_by_reactor_id` scripts each reactor's own resolved
## choice (defaults to "none"/Pass when absent).
class FakeReaction:
	var resolver_calls: Array = []
	var choice_by_reactor_id: Dictionary = {}
	var spent_reactor_ids: Dictionary = {}

	func order_candidate_reactors_by_initiative(candidates: Array) -> Array:
		return candidates

	func assert_candidate_reactors_ordering(_ordered_candidates: Array, _turn_order) -> bool:
		return true

	func is_reactor_reaction_spent(reactor) -> bool:
		return bool(spent_reactor_ids.get(reactor.display_id(), false))

	func resolve_enemy_opportunistic_strike_reaction(reactor, _context: Dictionary) -> Dictionary:
		resolver_calls.append(reactor.display_id())
		return {"choice": choice_by_reactor_id.get(reactor.display_id(), "none")}


## FakeStrikeUseCase — mirrors tests/unit/core/application/use_cases/
## test_resolve_stride_use_case.gd's identically-named/purposed double: a
## duck-typed resolve_action_use_case.gd stand-in whose resolve() reports
## target_defeated per a scripted, call-indexed list (defaults false/non-
## lethal beyond the scripted list), mutating target.hp_current to 0 on a
## scripted defeat (mirrors the real use case's own contract).
class FakeStrikeUseCase:
	var calls: Array = []
	var defeats_by_call_index: Array = []

	func resolve(combatant, _action_economy, target, action_name: String, round_number: int, cycle_index: int) -> Dictionary:
		var index: int = calls.size()
		calls.append({"reactor_id": combatant.display_id(), "action_name": action_name, "round_number": round_number, "cycle_index": cycle_index})
		var defeated: bool = defeats_by_call_index[index] if index < defeats_by_call_index.size() else false
		if defeated:
			target.hp_current = 0
		return {"resolved": true, "ok": true, "target_defeated": defeated, "damage_final": 5}


## FakeReactorActionEconomy — the minimal duck-typed surface
## core/application/ports/action_economy_port.gd's ReactionPaidActionEconomy
## wraps (spend_reaction()/is_spent()/get_remaining()).
class FakeReactorActionEconomy:
	func spend_reaction() -> Dictionary:
		return {"success": true}

	func is_spent() -> bool:
		return false

	func get_remaining() -> int:
		return 5


## FakeHexGridView — a DETERMINISTIC animation-adapter stub (RISK-002
## mitigation: no real Tween/timers). animate_token_to() records
## (combatant_id, target_hex) and returns null (a plain, non-Signal value) —
## `await`ing a non-Signal/non-coroutine value in GDScript resolves
## immediately without suspending, so this stub never actually waits a
## frame.
class FakeHexGridView:
	var animate_calls: Array = []

	func animate_token_to(combatant_id: String, target_hex):
		animate_calls.append({"combatant_id": combatant_id, "target_hex": target_hex})
		return null


func _actor() -> CombatantClass:
	var c := CombatantClass.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	c.is_enemy = false
	c.weapon = {"name": "Sword"}
	c.hp_current = 10
	c.hp_max = 10
	return c


## _reactor(id, hex) -> Combatant — a melee-armed, hostile-to-the-player
## reactor at the given hex (OpportunisticStrikeEligibility's adjacent &&
## hostile && !Spent && melee-reach predicate).
func _reactor(id: String, hex: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Enemy", hex)
	c.is_enemy = true
	c.weapon = {"name": "Claw"}
	c.hp_current = 5
	c.hp_max = 5
	return c


func _economy() -> ActionEconomyClass:
	var economy := ActionEconomyClass.new()
	economy.start_of_turn()
	return economy


## _deps(...) -> Dictionary — assembles a full StrideActionController deps
## Dictionary. `extra` merges/overrides additional keys (e.g.
## "pathfinder_fn", "hex_grid_view", "resolve_action_use_case").
func _deps(actor, economy, movement_input_controller, reaction, living_enemy_reactors: Array, extra: Dictionary = {}) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor, economy))
	var base: Dictionary = {
		"session_holder": holder,
		"movement_input_controller": movement_input_controller,
		"status_panel_view": null,
		"resolve_action_use_case": null,
		"reaction": reaction,
		"action_economy_for": func(_reactor_entity): return null,
		"current_round_number": func(): return 1,
		"after_successful_move": func(): pass,
		"living_enemy_reactors": func(): return living_enemy_reactors,
		"current_turn_order": func(): return null,
	}
	for key in extra:
		base[key] = extra[key]
	return base


## _straight_path_pathfinder_fn(hexes: Array) -> Callable — a fake
## pathfinder_fn double that ignores its (start, goal) arguments and always
## answers the SAME scripted path Array, recording every call it receives.
class _ScriptedPathfinder:
	var path_to_return: Array
	var calls: Array = []

	func _init(path: Array) -> void:
		path_to_return = path

	func find_path(start, goal):
		calls.append({"start": start, "goal": goal})
		return path_to_return


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — OS evaluated once per transit hex (not only at start hex).
# ══════════════════════════════════════════════════════════════════════════

func test_os_evaluated_at_each_transit_hex_not_only_start() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(2, -1))
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [reactor_h1_only],
		{"pathfinder_fn": Callable(pathfinder, "find_path")}
	))

	var result: Dictionary = await controller.execute(goal)

	assert_eq(reaction.resolver_calls, ["reactor_h1"],
		"a reactor adjacent ONLY to the intermediate transit hex must be offered a window exactly once -- proving OS is evaluated past the start hex")
	assert_true(result.get("ok", false), "a non-lethal multi-hex Stride must still commit")
	assert_eq(movement.stride_to_calls, [goal], "the final commit must still target the original goal selection")


func test_os_evaluated_exactly_once_per_transit_hex_across_a_three_hex_path() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0))
	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(2, -1))
	var reactor_goal_only := _reactor("reactor_goal", HexCoordClass.new(3, 0))
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction,
		[reactor_start_only, reactor_h1_only, reactor_goal_only],
		{"pathfinder_fn": Callable(pathfinder, "find_path")}
	))

	await controller.execute(goal)

	# Transit hexes are every path hex EXCEPT the final goal -- start and h1
	# only -- so reactor_start and reactor_h1 are each offered exactly one
	# window, while reactor_goal (adjacent only to the un-transited final
	# goal hex) never is.
	assert_eq(reaction.resolver_calls.count("reactor_start"), 1, "reactor adjacent to the start hex must be offered exactly one window")
	assert_eq(reaction.resolver_calls.count("reactor_h1"), 1, "reactor adjacent to the h1 transit hex must be offered exactly one window")
	assert_eq(reaction.resolver_calls.count("reactor_goal"), 0, "reactor adjacent only to the final (non-transit) goal hex must never be offered a window")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — mover downed at a transit hex aborts without commit.
# ══════════════════════════════════════════════════════════════════════════

func test_mover_downed_at_first_transit_hex_aborts_without_calling_stride_to() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0))
	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(2, -1))
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	reaction.choice_by_reactor_id["reactor_start"] = "opportunistic_strike"
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [true]
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])
	var hex_grid_view := FakeHexGridView.new()

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction,
		[reactor_start_only, reactor_h1_only],
		{
			"pathfinder_fn": Callable(pathfinder, "find_path"),
			"hex_grid_view": hex_grid_view,
			"resolve_action_use_case": strike_use_case,
			"action_economy_for": func(_reactor_entity): return FakeReactorActionEconomy.new(),
		}
	))

	var result: Dictionary = await controller.execute(goal)

	assert_eq(result, {"ok": false, "resolved": false, "error": "ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE"},
		"a mover downed at a transit hex must abort with the documented error shape")
	assert_eq(movement.stride_to_calls, [], "stride_to()/commit must never be called once the mover is downed mid-path")
	assert_eq(hex_grid_view.animate_calls, [], "no animate_token_to() call may fire for the aborted transit hex")
	assert_eq(reaction.resolver_calls, ["reactor_start"],
		"the loop must stop at the FIRST lethal transit hex -- the h1 reactor must never even be offered a window")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — path fallback to direct [start, goal].
# ══════════════════════════════════════════════════════════════════════════

func test_path_falls_back_to_direct_start_goal_when_pathfinder_fn_unwired() -> void:
	var actor := _actor()
	var economy := _economy()
	var goal := HexCoordClass.new(2, 0)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0))
	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(2, -1))
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()

	# No "pathfinder_fn" key supplied at all -- _pathfinder_fn defaults to an
	# invalid Callable.
	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [reactor_start_only, reactor_h1_only]
	))

	var result: Dictionary = await controller.execute(goal)

	assert_true(result.get("ok", false), "an unwired pathfinder_fn must still resolve a normal Stride")
	assert_eq(reaction.resolver_calls, ["reactor_start"],
		"an unwired pathfinder_fn must fall back to the direct [start, goal] path -- only the start-hex reactor is ever offered a window, exactly like the pre-FEAT-002 single-hex call")


func test_path_falls_back_to_direct_start_goal_when_pathfinder_fn_returns_short_path() -> void:
	var actor := _actor()
	var economy := _economy()
	# Reuse the actor's OWN hex_coord instance (rather than constructing a
	# fresh, distinct HexCoord for the same q/r) so the pathfinder.calls[0]
	# assertion below compares by object identity, avoiding a false failure
	# from HexCoord's lack of an == operator overload (only .equals() does
	# value comparison -- see core/geometry/hex_coord.gd).
	var start = actor.hex_coord
	var goal := HexCoordClass.new(2, 0)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0))
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	# size<2 (unreachable / no route) per HexPathfinder.find_path()'s own
	# "no path" contract.
	var pathfinder := _ScriptedPathfinder.new([])

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [reactor_start_only],
		{"pathfinder_fn": Callable(pathfinder, "find_path")}
	))

	var result: Dictionary = await controller.execute(goal)

	assert_eq(pathfinder.calls.size(), 1, "pathfinder_fn must still be consulted once")
	assert_eq(pathfinder.calls[0], {"start": start, "goal": goal}, "pathfinder_fn must be called with (mover_start_hex, selection)")
	assert_true(result.get("ok", false), "a size<2 pathfinder_fn result must still resolve a normal Stride via the fallback")
	assert_eq(reaction.resolver_calls, ["reactor_start"], "a size<2 pathfinder_fn result must degrade to the direct [start, goal] path")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — animate_token_to called once per transit hex, in order.
# ══════════════════════════════════════════════════════════════════════════

func test_animate_token_to_called_once_per_transit_hex_in_order() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])
	var hex_grid_view := FakeHexGridView.new()

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [],
		{"pathfinder_fn": Callable(pathfinder, "find_path"), "hex_grid_view": hex_grid_view}
	))

	var result: Dictionary = await controller.execute(goal)

	assert_true(result.get("ok", false))
	assert_eq(hex_grid_view.animate_calls.size(), 2, "animate_token_to() must be called once per transit hex (path.size() - 1)")
	assert_eq(hex_grid_view.animate_calls[0], {"combatant_id": "player_0", "target_hex": h1}, "the first animate call must target h1, in order")
	assert_eq(hex_grid_view.animate_calls[1], {"combatant_id": "player_0", "target_hex": goal}, "the second animate call must target the final goal, in order")


func test_animate_token_to_never_called_when_hex_grid_view_unwired() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])

	# No "hex_grid_view" key supplied -- _hex_grid_view defaults to null.
	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [],
		{"pathfinder_fn": Callable(pathfinder, "find_path")}
	))

	var result: Dictionary = await controller.execute(goal)

	assert_true(result.get("ok", false))
	assert_eq(movement.stride_to_calls, [goal], "the Stride must still commit normally with an unwired hex_grid_view")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — byte-identical legacy behavior when both seams are unwired.
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_behavior_unaffected_when_pathfinder_fn_and_hex_grid_view_absent() -> void:
	var actor := _actor()
	var economy := _economy()
	var goal := HexCoordClass.new(2, 0)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0))
	var movement := FakeMovementInputController.new(economy)
	movement.result_to_return = {"ok": true, "resolved": true, "destination": goal}
	var reaction := FakeReaction.new()

	# Neither "pathfinder_fn" nor "hex_grid_view" is present in deps at all.
	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [reactor_start_only]
	))

	var result: Dictionary = await controller.execute(goal)

	assert_eq(result, {"ok": true, "resolved": true, "destination": goal}, "execute() must return movement_input_controller.stride_to()'s result Dictionary verbatim")
	assert_eq(movement.stride_to_calls, [goal], "stride_to() must be called exactly once, with the original selection")
	assert_eq(reaction.resolver_calls, ["reactor_start"], "exactly one Opportunistic Strike window (at the start hex) must be evaluated, matching pre-FEAT-002 behavior")


func test_legacy_behavior_null_actor_still_commits_without_any_os_evaluation() -> void:
	var economy := _economy()
	var goal := HexCoordClass.new(2, 0)
	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()

	var controller := StrideActionControllerClass.new(_deps(
		null, economy, movement, reaction, []
	))

	var result: Dictionary = await controller.execute(goal)

	assert_true(result.get("ok", false), "a null current actor must still forward straight to stride_to() unaffected")
	assert_eq(reaction.resolver_calls, [], "no Opportunistic Strike window may be evaluated without a live actor/mover_start_hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — self-spend suppression on the final commit is preserved.
# ══════════════════════════════════════════════════════════════════════════

func test_self_spend_suppression_preserved_on_final_commit_with_multi_hex_path() -> void:
	var actor := _actor()
	var economy := _economy()
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)

	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])
	var budget_before: int = economy.get_remaining()

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, [],
		{"pathfinder_fn": Callable(pathfinder, "find_path")}
	))

	var result: Dictionary = await controller.execute(goal, true)

	assert_true(result.get("ok", false))
	assert_eq(movement.suppressed_at_call_time, [true], "the live ActionEconomy must be self-spend-suppressed at the exact moment stride_to() is invoked")
	assert_false(economy.is_self_spend_suppressed(), "the suppression flag must never leak past a completed execute() call")
	assert_eq(economy.get_remaining(), budget_before, "no-self-spend execution must leave the shared action-economy budget completely untouched")


func test_self_spend_suppression_not_engaged_when_no_self_spend_execution_is_false() -> void:
	var actor := _actor()
	var economy := _economy()
	var goal := HexCoordClass.new(2, 0)

	var movement := FakeMovementInputController.new(economy)
	var reaction := FakeReaction.new()

	var controller := StrideActionControllerClass.new(_deps(
		actor, economy, movement, reaction, []
	))

	await controller.execute(goal)

	assert_eq(movement.suppressed_at_call_time, [false], "the default (no_self_spend_execution=false) path must never suppress the live ActionEconomy")
