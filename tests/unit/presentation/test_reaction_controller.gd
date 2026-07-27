extends GutTest
## tests/unit/presentation/test_reaction_controller.gd
##
## GUT suite for FEAT-003 (US-003; FR-005/NFR-001/NFR-004; ADR-003): widens
## presentation/reaction_controller.gd's ReactionController.
## resolve_enemy_stride_opportunistic_window() -- the Callable core/combat/
## ai.gd's `_stride_reaction_resolver_fn` seam awaits for the ENEMY-mover
## Stride path -- ADDITIVELY with a 4th, OPTIONAL `stride_path: Array = []`
## parameter (mirrors presentation/stride_action_controller.gd's FEAT-002
## per-transit-hex extension of the PLAYER-mover Stride path, so both movers
## are proven symmetrically per this steel thread's own exit criteria).
##
## The existing single-hex-evaluation body is extracted, UNCHANGED, into a
## new `_single_hex_stride_os(mover, hex, reactors)` helper; the public
## method now:
##   - ALWAYS evaluates a window at `mover_start_hex` first (byte-identical
##     to the pre-extraction inline call every legacy 3-argument caller still
##     makes -- `stride_path` defaults to an empty Array).
##   - When `stride_path` is non-empty, additionally iterates
##     `stride_path.slice(1)` (every hex from index 1 onward), evaluating one
##     more window per hex, STOPPING at (and returning) the FIRST result
##     whose "stride_should_commit" comes back false.
##
## test_criteria covered:
##   1. test_legacy_three_argument_call_evaluates_only_mover_start_hex --
##      empty/omitted stride_path produces output identical to pre-change
##      (single-hex) behavior.
##   2. test_single_hex_stride_os_matches_pre_extraction_inline_call --
##      _single_hex_stride_os() alone produces the identical result Dictionary
##      the public method's legacy (stride_path-less) call produces for the
##      same hex.
##   3. test_multi_hex_stride_path_evaluates_every_hex_from_index_one --
##      a 3-reactor board, one adjacent to each of 3 stride_path hexes, is
##      resolved once per hex, mover_start_hex through the last stride_path
##      entry.
##   4. test_multi_hex_stride_path_short_circuits_on_first_lethal_hex --
##      a lethal Opportunistic Strike at the SECOND stride_path hex stops
##      iteration immediately -- the third hex's reactor is never offered a
##      window.
##   5. test_cross_path_parity_player_and_enemy_yield_identical_outcomes --
##      an identical board-state fixture (mirrored is_enemy roles) driven
##      through StrideActionController (player mover) and
##      resolve_enemy_stride_opportunistic_window() (enemy mover) yields
##      identical pass/block/OS outcomes, since both consume the SAME
##      ResolveStrideUseCase/OpportunisticStrikeEligibility contract.
##   6. Existing ReactionController GUT suite (initiative ordering,
##      dodge-step, etc.) passes with zero regressions -- covered by the full
##      suite run, not a test in this file.

const ReactionControllerClass    = preload("res://presentation/reaction_controller.gd")
const StrideActionControllerClass = preload("res://presentation/stride_action_controller.gd")
const RoundSessionHolderClass    = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass         = preload("res://core/rules/action_economy.gd")


# ══════════════════════════════════════════════════════════════════════════
# Fakes / doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeTurnController -- the minimal stand-in for ReactionController's
## injected `turn_controller`, implementing only
## resolve_opportunistic_strike_reaction() (the method
## resolve_player_opportunistic_strike_reaction() awaits). Records every call
## (reactor.display_id(), in order) and answers a scripted choice per
## reactor id (defaults to "none"/Pass).
class FakeTurnController:
	var calls: Array = []
	var choice_by_reactor_id: Dictionary = {}

	func resolve_opportunistic_strike_reaction(reactor, _context: Dictionary, _action_economy, _round_number) -> Dictionary:
		calls.append(reactor.display_id())
		return {"choice": choice_by_reactor_id.get(reactor.display_id(), "none")}


## FakeStrikeUseCase -- mirrors tests/unit/core/application/use_cases/
## test_resolve_stride_use_case.gd's / tests/unit/presentation/
## test_stride_action_controller.gd's identically-purposed doubles: a
## duck-typed resolve_action_use_case.gd stand-in whose resolve() reports
## target_defeated per a scripted, call-indexed list, mutating
## target.hp_current to 0 on a scripted defeat.
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


## FakeReactorActionEconomy -- the minimal duck-typed surface
## core/application/ports/action_economy_port.gd's ReactionPaidActionEconomy
## wraps.
class FakeReactorActionEconomy:
	func spend_reaction() -> Dictionary:
		return {"success": true}

	func is_spent() -> bool:
		return false

	func get_remaining() -> int:
		return 5


## FakeSession/FakeMovementInputController/FakeReaction -- reused, minimal
## presentation/stride_action_controller.gd doubles (see
## tests/unit/presentation/test_stride_action_controller.gd's identically
## purposed/shaped classes) so the cross-path parity test can drive the REAL
## StrideActionController for the player-mover half of the comparison.
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


class FakeMovementInputController:
	var stride_to_calls: Array = []
	var result_to_return: Dictionary = {"ok": true}

	func get_selectable_stride_hexes() -> Array:
		return []

	func stride_to(destination_hex) -> Dictionary:
		stride_to_calls.append(destination_hex)
		return result_to_return


class FakeReaction:
	var resolver_calls: Array = []
	var choice_by_reactor_id: Dictionary = {}

	func order_candidate_reactors_by_initiative(candidates: Array) -> Array:
		return candidates

	func assert_candidate_reactors_ordering(_ordered_candidates: Array, _turn_order) -> bool:
		return true

	func is_reactor_reaction_spent(_reactor) -> bool:
		return false

	func resolve_enemy_opportunistic_strike_reaction(reactor, _context: Dictionary) -> Dictionary:
		resolver_calls.append(reactor.display_id())
		return {"choice": choice_by_reactor_id.get(reactor.display_id(), "none")}


class _ScriptedPathfinder:
	var path_to_return: Array

	func _init(path: Array) -> void:
		path_to_return = path

	func find_path(_start, _goal):
		return path_to_return


# ══════════════════════════════════════════════════════════════════════════
# Fixture helpers
# ══════════════════════════════════════════════════════════════════════════

func _mover(id: String, hex, is_enemy: bool) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Team", hex)
	c.is_enemy = is_enemy
	c.weapon = {"name": "Sword"}
	c.hp_current = 10
	c.hp_max = 10
	return c


func _reactor(id: String, hex, is_enemy: bool) -> CombatantClass:
	var c := CombatantClass.new(id, id, "Team", hex)
	c.is_enemy = is_enemy
	c.weapon = {"name": "Claw"}
	c.hp_current = 5
	c.hp_max = 5
	return c


## _controller(...) -> ReactionController -- builds a real ReactionController
## wired with a FakeTurnController (so resolve_enemy_stride_opportunistic_
## window()'s reactor_resolver_fn -- resolve_player_opportunistic_strike_
## reaction() -- routes to a scriptable double rather than a real pop-up) and
## optionally a FakeStrikeUseCase (so a scripted reactor choice can resolve a
## lethal Strike end to end through the REAL ResolveStrideUseCase).
func _controller(turn_controller, strike_use_case = null, round_number: int = 1) -> ReactionControllerClass:
	var action_economy_fn := func(_reactor_entity):
		return FakeReactorActionEconomy.new() if strike_use_case != null else null
	var round_number_fn := func(): return round_number
	return ReactionControllerClass.new(
		action_economy_fn, round_number_fn, strike_use_case, turn_controller, null, null
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- legacy 3-argument call (empty/omitted stride_path).
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_three_argument_call_evaluates_only_mover_start_hex() -> void:
	var start := HexCoordClass.new(0, 0)
	var mover := _mover("mover", start, true)
	var reactor_at_start := _reactor("reactor_start", HexCoordClass.new(-1, 0), false)

	var turn_controller := FakeTurnController.new()
	var controller := _controller(turn_controller)

	var result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(
		mover, start, [reactor_at_start]
	)

	assert_eq(turn_controller.calls, ["reactor_start"], "a legacy 3-argument call must evaluate exactly one window, at mover_start_hex")
	assert_eq(result, {"reactions": [{"reactor": reactor_at_start, "choice": "none"}], "mover_downed": false, "stride_should_commit": true},
		"the legacy call's result shape must be byte-identical to pre-change (single-hex) behavior")


func test_legacy_call_with_explicit_empty_stride_path_matches_omitted_argument() -> void:
	var start := HexCoordClass.new(0, 0)
	var mover := _mover("mover", start, true)
	var reactor_at_start := _reactor("reactor_start", HexCoordClass.new(-1, 0), false)

	var turn_controller := FakeTurnController.new()
	var controller := _controller(turn_controller)

	var omitted_result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(
		mover, start, [reactor_at_start]
	)
	turn_controller.calls.clear()
	var explicit_empty_result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(
		mover, start, [reactor_at_start], []
	)

	assert_eq(explicit_empty_result, omitted_result, "an explicit empty stride_path Array must match the omitted-4th-argument legacy call exactly")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- _single_hex_stride_os() matches the pre-extraction inline
# call.
# ══════════════════════════════════════════════════════════════════════════

func test_single_hex_stride_os_matches_pre_extraction_inline_call() -> void:
	var start := HexCoordClass.new(0, 0)
	var mover := _mover("mover", start, true)
	var reactor_at_start := _reactor("reactor_start", HexCoordClass.new(-1, 0), false)

	var turn_controller := FakeTurnController.new()
	var controller := _controller(turn_controller)

	var direct_result: Dictionary = await controller._single_hex_stride_os(mover, start, [reactor_at_start])
	turn_controller.calls.clear()
	var legacy_result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(mover, start, [reactor_at_start])

	assert_eq(direct_result, legacy_result, "_single_hex_stride_os() called directly must produce the identical result Dictionary the public method's legacy single-hex evaluation produces")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- multi-hex stride_path evaluates every hex from index 1.
# ══════════════════════════════════════════════════════════════════════════

func test_multi_hex_stride_path_evaluates_every_hex_from_index_one() -> void:
	# A BENT 3-hex path (start -> h1 -> h2, turning at h1) -- a straight
	# collinear 3-hex run shares too many neighbor hexes between consecutive
	# steps to isolate a reactor to exactly one of the three, so this fixture
	# turns instead (mirrors this file's own parity-test fixture, which only
	# ever evaluates 2 transit hexes and so doesn't hit this overlap).
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var h2 := HexCoordClass.new(2, -1)
	var mover := _mover("mover", start, true)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0), false)
	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(1, 1), false)
	var reactor_h2_only := _reactor("reactor_h2", HexCoordClass.new(2, -2), false)

	var turn_controller := FakeTurnController.new()
	var controller := _controller(turn_controller)

	var result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(
		mover, start, [reactor_start_only, reactor_h1_only, reactor_h2_only], [start, h1, h2]
	)

	assert_eq(turn_controller.calls, ["reactor_start", "reactor_h1", "reactor_h2"],
		"every stride_path hex (mover_start_hex plus index 1 onward) must be evaluated exactly once, in order")
	assert_true(result.get("stride_should_commit", false), "a fully non-lethal multi-hex path must still allow the Stride to commit")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- short-circuit on the first stride_should_commit:false hex.
# ══════════════════════════════════════════════════════════════════════════

func test_multi_hex_stride_path_short_circuits_on_first_lethal_hex() -> void:
	# Same bent 3-hex fixture as the preceding test (see its own comment).
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var h2 := HexCoordClass.new(2, -1)
	var mover := _mover("mover", start, true)

	var reactor_start_only := _reactor("reactor_start", HexCoordClass.new(-1, 0), false)
	var reactor_h1_only := _reactor("reactor_h1", HexCoordClass.new(1, 1), false)
	var reactor_h2_only := _reactor("reactor_h2", HexCoordClass.new(2, -2), false)

	var turn_controller := FakeTurnController.new()
	turn_controller.choice_by_reactor_id["reactor_h1"] = "opportunistic_strike"
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [true]
	var controller := _controller(turn_controller, strike_use_case)

	var result: Dictionary = await controller.resolve_enemy_stride_opportunistic_window(
		mover, start, [reactor_start_only, reactor_h1_only, reactor_h2_only], [start, h1, h2]
	)

	assert_eq(turn_controller.calls, ["reactor_start", "reactor_h1"],
		"iteration must stop at the FIRST lethal hex -- reactor_h2 must never be offered a window")
	assert_true(result.get("mover_downed", false), "a lethal Opportunistic Strike at a transit hex must set mover_downed")
	assert_false(result.get("stride_should_commit", true), "a lethal Opportunistic Strike at a transit hex must clear stride_should_commit")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- cross-path parity (RISK-006 mitigation): identical
# board-state fixture, player mover vs enemy mover, identical outcomes.
# ══════════════════════════════════════════════════════════════════════════

func _economy() -> ActionEconomyClass:
	var economy := ActionEconomyClass.new()
	economy.start_of_turn()
	return economy


func test_cross_path_parity_player_and_enemy_yield_identical_pass_outcomes() -> void:
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)
	var start_reactor_hex := HexCoordClass.new(-1, 0)
	var h1_reactor_hex := HexCoordClass.new(2, -1)
	var goal_reactor_hex := HexCoordClass.new(3, 0)

	# --- Player-mover half: StrideActionController + FakeReaction. ---
	var player := _mover("player", start, false)
	var player_economy := _economy()
	var player_reactor_start := _reactor("reactor_start", start_reactor_hex, true)
	var player_reactor_h1 := _reactor("reactor_h1", h1_reactor_hex, true)
	var player_reactor_goal := _reactor("reactor_goal", goal_reactor_hex, true)
	var movement := FakeMovementInputController.new()
	var fake_reaction := FakeReaction.new()
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(player, player_economy))
	var stride_controller := StrideActionControllerClass.new({
		"session_holder": holder,
		"movement_input_controller": movement,
		"status_panel_view": null,
		"resolve_action_use_case": null,
		"reaction": fake_reaction,
		"action_economy_for": func(_r): return null,
		"current_round_number": func(): return 1,
		"after_successful_move": func(): pass,
		"living_enemy_reactors": func(): return [player_reactor_start, player_reactor_h1, player_reactor_goal],
		"current_turn_order": func(): return null,
		"pathfinder_fn": Callable(pathfinder, "find_path"),
	})

	var player_result: Dictionary = await stride_controller.execute(goal)

	# --- Enemy-mover half: ReactionController.resolve_enemy_stride_
	# opportunistic_window(), mirrored is_enemy roles, transit-only
	# stride_path (start, h1 -- excludes the final goal, exactly like the
	# player half's own transit-hex loop). ---
	var enemy := _mover("enemy", start, true)
	var enemy_reactor_start := _reactor("reactor_start", start_reactor_hex, false)
	var enemy_reactor_h1 := _reactor("reactor_h1", h1_reactor_hex, false)
	var enemy_reactor_goal := _reactor("reactor_goal", goal_reactor_hex, false)
	var turn_controller := FakeTurnController.new()
	var reaction_controller := _controller(turn_controller)

	var enemy_result: Dictionary = await reaction_controller.resolve_enemy_stride_opportunistic_window(
		enemy, start, [enemy_reactor_start, enemy_reactor_h1, enemy_reactor_goal], [start, h1]
	)

	# Identical OUTCOME: both movers survive, both commit, and in BOTH cases
	# exactly the start-hex and h1-hex reactors were offered a window while
	# the goal-hex-only reactor never was.
	assert_true(player_result.get("ok", false), "the player-mover Stride must commit (non-lethal fixture)")
	assert_true(enemy_result.get("stride_should_commit", false), "the enemy-mover Stride must be free to commit (non-lethal fixture)")
	assert_eq(fake_reaction.resolver_calls, ["reactor_start", "reactor_h1"], "the player path must offer a window to exactly the start-hex and h1-hex reactors")
	assert_eq(turn_controller.calls, ["reactor_start", "reactor_h1"], "the enemy path must offer a window to exactly the start-hex and h1-hex reactors -- identical to the player path")


func test_cross_path_parity_player_and_enemy_yield_identical_block_outcomes() -> void:
	var start := HexCoordClass.new(0, 0)
	var h1 := HexCoordClass.new(1, 0)
	var goal := HexCoordClass.new(2, 0)
	var start_reactor_hex := HexCoordClass.new(-1, 0)
	var h1_reactor_hex := HexCoordClass.new(2, -1)

	# --- Player-mover half: a LETHAL Opportunistic Strike at the h1 transit
	# hex (the SECOND transit hex -- proving the multi-hex extension, not
	# merely the legacy start-hex evaluation, is what's exercised on both
	# sides). ---
	var player := _mover("player", start, false)
	var player_economy := _economy()
	var player_reactor_start := _reactor("reactor_start", start_reactor_hex, true)
	var player_reactor_h1 := _reactor("reactor_h1", h1_reactor_hex, true)
	var movement := FakeMovementInputController.new()
	var fake_reaction := FakeReaction.new()
	fake_reaction.choice_by_reactor_id["reactor_h1"] = "opportunistic_strike"
	var player_strike_use_case := FakeStrikeUseCase.new()
	player_strike_use_case.defeats_by_call_index = [true]
	var pathfinder := _ScriptedPathfinder.new([start, h1, goal])
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(player, player_economy))
	var stride_controller := StrideActionControllerClass.new({
		"session_holder": holder,
		"movement_input_controller": movement,
		"status_panel_view": null,
		"resolve_action_use_case": player_strike_use_case,
		"reaction": fake_reaction,
		"action_economy_for": func(_r): return FakeReactorActionEconomy.new(),
		"current_round_number": func(): return 1,
		"after_successful_move": func(): pass,
		"living_enemy_reactors": func(): return [player_reactor_start, player_reactor_h1],
		"current_turn_order": func(): return null,
		"pathfinder_fn": Callable(pathfinder, "find_path"),
	})

	var player_result: Dictionary = await stride_controller.execute(goal)

	# --- Enemy-mover half: mirrored roles/geometry, transit-only stride_path
	# (start, h1). ---
	var enemy := _mover("enemy", start, true)
	var enemy_reactor_start := _reactor("reactor_start", start_reactor_hex, false)
	var enemy_reactor_h1 := _reactor("reactor_h1", h1_reactor_hex, false)
	var turn_controller := FakeTurnController.new()
	turn_controller.choice_by_reactor_id["reactor_h1"] = "opportunistic_strike"
	var enemy_strike_use_case := FakeStrikeUseCase.new()
	enemy_strike_use_case.defeats_by_call_index = [true]
	var reaction_controller := _controller(turn_controller, enemy_strike_use_case)

	var enemy_result: Dictionary = await reaction_controller.resolve_enemy_stride_opportunistic_window(
		enemy, start, [enemy_reactor_start, enemy_reactor_h1], [start, h1]
	)

	# Identical BLOCK outcome on both sides: the mover is downed at the h1
	# transit hex, the Stride must NOT commit, and NO further hex is ever
	# evaluated.
	assert_eq(player_result, {"ok": false, "resolved": false, "error": "ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE"},
		"the player-mover Stride must abort with the documented error shape")
	assert_eq(movement.stride_to_calls, [], "the player-mover Stride must never commit once downed mid-path")
	assert_true(enemy_result.get("mover_downed", false), "the enemy mover must be reported downed -- identical to the player path's abort")
	assert_false(enemy_result.get("stride_should_commit", true), "the enemy-mover Stride must not be free to commit -- identical to the player path's abort")
	assert_eq(fake_reaction.resolver_calls, ["reactor_start", "reactor_h1"], "the player path must have evaluated exactly the start and h1 reactors before aborting")
	assert_eq(turn_controller.calls, ["reactor_start", "reactor_h1"], "the enemy path must have evaluated exactly the start and h1 reactors before aborting -- identical to the player path")
