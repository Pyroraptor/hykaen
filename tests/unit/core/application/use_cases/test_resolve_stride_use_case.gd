extends GutTest
## tests/unit/core/application/use_cases/test_resolve_stride_use_case.gd
##
## GUT test suite for iteration K FEAT-006 (US-006): core/application/
## use_cases/resolve_stride_use_case.gd's ResolveStrideUseCase — the
## Application-layer use case that filters OpportunisticStrike-eligible
## reactors (core/domain/opportunistic_strike_eligibility.gd) and drives
## their resolution via caller-injected Callables, BEFORE a Stride commits.
##
## Verifies:
##   1. An eligible reactor is offered a window (reactor_resolver_fn is
##      awaited exactly once) and its resolved choice is reported back.
##   2. An ineligible reactor (non-adjacent) is never offered a window —
##      reactor_resolver_fn is never called for it.
##   3. reactor_spent_fn is consulted per-candidate and a reactor it reports
##      Spent for is filtered out (never offered a window).
##   4. Reactors are resolved in the exact order supplied (initiative order),
##      never re-sorted.
##   5. An unwired reactor_resolver_fn degrades safely (no crash, reactor
##      simply never appears in the result) even for an otherwise-eligible
##      reactor.
##   6. Default-safety: omitting reactor_spent_fn entirely treats every
##      candidate as never Spent.
##
## iteration K FEAT-008 (US-008 / "Opportunistic Strike ordering, interrupt,
## and initiative semantics") additionally verifies:
##   7. A LETHAL Opportunistic Strike (strike_use_case reports
##      target_defeated=true) sets both "mover_downed" AND the caller-facing
##      "stride_should_commit" to true/false respectively — the Stride MUST
##      be cancelled.
##   8. A NON-lethal Opportunistic Strike leaves "stride_should_commit" true
##      — the Stride may complete.
##   9. Two eligible reactors both resolve their Strike EFFECT (not merely
##      their choice) in strict initiative (supplied) order.
##   10. The FIRST lethal reactor in initiative order stops the SECOND
##       reactor from ever being offered a window at all (no wasted/no-op
##       Strike against an already-downed mover).

const ResolveStrideUseCaseClass = preload("res://core/application/use_cases/resolve_stride_use_case.gd")
const HexCoord = preload("res://core/geometry/hex_coord.gd")


func _mover() -> Dictionary:
	return {"name": "Skeleton", "hex_coord": HexCoord.new(0, 0), "is_enemy": true, "weapon": {"damage_die": 6}}


func _reactor(name: String, hex_coord) -> Dictionary:
	return {"name": name, "hex_coord": hex_coord, "is_enemy": false, "weapon": {"damage_die": 6}}


## RecordingResolver -- a reactor_resolver_fn double recording every call
## (reactor name, in order) and always answering with a fixed choice.
class RecordingResolver:
	extends RefCounted

	var choice_to_return: String
	var calls: Array = []

	func _init(choice: String) -> void:
		choice_to_return = choice

	func resolve(reactor, _context: Dictionary) -> Dictionary:
		calls.append(reactor.name)
		return {"choice": choice_to_return}


## FakeStrikeUseCase -- iteration K FEAT-008: a duck-typed
## resolve_action_use_case.gd double, recording every call (reactor name,
## mover/target name, action_name, round_number, cycle_index) IN ORDER, so
## this suite can assert both WHICH reactors actually resolved a Strike
## EFFECT (not merely a recorded choice) and the STRICT order they resolved
## in. `defeats_by_call_index` scripts whether the Nth call (0-indexed)
## defeats the target (mutates target.hp_current to 0, mirroring
## resolve_action_use_case.gd's own real target_defeated contract) --
## defaults to false (non-lethal) for any call beyond the scripted list.
class FakeStrikeUseCase:
	extends RefCounted

	var calls: Array = []
	var defeats_by_call_index: Array = []

	func resolve(combatant, _action_economy, target, action_name: String, round_number: int, cycle_index: int) -> Dictionary:
		var index: int = calls.size()
		calls.append({
			"reactor_name": combatant.name,
			"mover_name":   target.name,
			"action_name":  action_name,
			"round_number": round_number,
			"cycle_index":  cycle_index,
		})
		var defeated: bool = defeats_by_call_index[index] if index < defeats_by_call_index.size() else false
		if defeated:
			target.hp_current = 0
		return {"resolved": true, "ok": true, "target_defeated": defeated, "damage_final": 5}


## FakeReactorActionEconomy -- iteration K FEAT-008: the minimal duck-typed
## surface core/application/ports/action_economy_port.gd's
## ReactionPaidActionEconomy wraps (spend_reaction()/is_spent()/
## get_remaining()) -- this suite never asserts on ITS state directly (that
## is core/application/ports/action_economy_port.gd's own test's job), it
## exists purely so `reactor_action_economy_fn` has a non-null instance to
## hand back per reactor.
class FakeReactorActionEconomy:
	extends RefCounted

	func spend_reaction() -> Dictionary:
		return {"success": true}

	func is_spent() -> bool:
		return false

	func get_remaining() -> int:
		return 5


## _reactor_action_economy_fn() -> Callable -- a reactor_action_economy_fn
## double answering a FRESH FakeReactorActionEconomy per call (mirrors
## MainScene.gd's real `_action_economy_for()` shape: Callable(reactor) ->
## ActionEconomy-like).
func _reactor_action_economy_fn() -> Callable:
	return func(_reactor):
		return FakeReactorActionEconomy.new()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: an eligible reactor is offered a window and resolved
# ══════════════════════════════════════════════════════════════════════════

func test_eligible_reactor_is_offered_a_window_and_resolved() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))  # adjacent to (0,0)

	var resolver := RecordingResolver.new("opportunistic_strike")
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["Titus"], "the eligible reactor must be offered exactly one window")
	assert_eq(result["reactions"].size(), 1)
	assert_eq(result["reactions"][0]["choice"], "opportunistic_strike")
	assert_eq(result["reactions"][0]["reactor"], titus)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: an ineligible (non-adjacent) reactor is never offered a window
# ══════════════════════════════════════════════════════════════════════════

func test_non_adjacent_reactor_never_offered_a_window() -> void:
	var mover = _mover()
	var far_away = _reactor("Far Away", HexCoord.new(9, 9))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [far_away], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, [], "a non-adjacent reactor must never be offered a window")
	assert_eq(result["reactions"].size(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: reactor_spent_fn filters a Spent reactor out
# ══════════════════════════════════════════════════════════════════════════

func test_spent_reactor_is_filtered_out_via_reactor_spent_fn() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	var always_spent := func(_reactor) -> bool:
		return true

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], always_spent, Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, [], "a Spent reactor must never be offered a window")
	assert_eq(result["reactions"].size(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: reactors are resolved strictly in the order supplied
# ══════════════════════════════════════════════════════════════════════════

func test_reactors_resolved_in_the_order_supplied() -> void:
	var mover = _mover()
	var second = _reactor("Second", HexCoord.new(-1, 0))
	var first = _reactor("First", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	await use_case.execute(
		mover, mover["hex_coord"], [first, second], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["First", "Second"], "reactors must be resolved strictly in the supplied (initiative) order")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: an unwired reactor_resolver_fn degrades safely
# ══════════════════════════════════════════════════════════════════════════

func test_unwired_resolver_fn_degrades_safely() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))

	var use_case := ResolveStrideUseCaseClass.new()
	var result: Dictionary = await use_case.execute(mover, mover["hex_coord"], [titus])

	assert_eq(result["reactions"].size(), 0, "an unwired resolver must never crash, and the eligible reactor is simply skipped")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: omitting reactor_spent_fn treats every candidate as not Spent
# ══════════════════════════════════════════════════════════════════════════

func test_omitted_reactor_spent_fn_treats_every_candidate_as_not_spent() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["Titus"], "an omitted reactor_spent_fn must default to 'never Spent'")
	assert_eq(result["reactions"].size(), 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 (FEAT-008): a LETHAL Opportunistic Strike sets mover_downed
# true and stride_should_commit false — the caller MUST cancel the Stride.
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_opportunistic_strike_cancels_stride() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("opportunistic_strike")
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [true]
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], Callable(), Callable(resolver, "resolve"),
		strike_use_case, _reactor_action_economy_fn()
	)

	assert_eq(strike_use_case.calls.size(), 1, "the lethal reactor's Strike EFFECT must actually resolve, not merely be recorded as a choice")
	assert_true(result["mover_downed"], "a lethal Opportunistic Strike must set mover_downed true")
	assert_false(result["stride_should_commit"], "a lethal Opportunistic Strike must set stride_should_commit false -- the caller must cancel the Stride")
	assert_true(mover["hex_coord"].equals(HexCoord.new(0, 0)), "this use case itself never mutates mover.hex_coord -- the mover 'remains at its start hex' is the caller's own no-commit contract, but the domain hex_coord here proves this use case made no move of its own")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 8 (FEAT-008): a NON-lethal Opportunistic Strike leaves
# stride_should_commit true — the Stride may complete.
# ══════════════════════════════════════════════════════════════════════════

func test_non_lethal_opportunistic_strike_allows_stride_to_complete() -> void:
	var mover = _mover()
	var titus = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("opportunistic_strike")
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [false]
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], Callable(), Callable(resolver, "resolve"),
		strike_use_case, _reactor_action_economy_fn()
	)

	assert_eq(strike_use_case.calls.size(), 1, "the reactor's non-lethal Strike EFFECT must still actually resolve")
	assert_false(result["mover_downed"], "a non-lethal Opportunistic Strike must never set mover_downed")
	assert_true(result["stride_should_commit"], "a non-lethal Opportunistic Strike must leave stride_should_commit true -- the Stride may complete")
	assert_true(result["reactions"][0]["strike_result"].get("resolved", false), "the resolved strike_result must be reported back to the caller")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 9 (FEAT-008): two eligible reactors resolve their Strike EFFECT
# in strict initiative (supplied) order.
# ══════════════════════════════════════════════════════════════════════════

func test_two_eligible_reactors_resolve_strikes_in_strict_initiative_order() -> void:
	var mover = _mover()
	var first = _reactor("First", HexCoord.new(1, 0))
	var second = _reactor("Second", HexCoord.new(-1, 0))

	var resolver := RecordingResolver.new("opportunistic_strike")
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [false, false]  # neither is lethal
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [first, second], Callable(), Callable(resolver, "resolve"),
		strike_use_case, _reactor_action_economy_fn()
	)

	assert_eq(resolver.calls, ["First", "Second"], "the reaction CHOICE must be asked in strict initiative order")
	assert_eq(strike_use_case.calls.size(), 2, "BOTH reactors' Strike effects must resolve when neither is lethal")
	assert_eq(strike_use_case.calls[0]["reactor_name"], "First", "the FIRST reactor's Strike effect must resolve before the second's")
	assert_eq(strike_use_case.calls[1]["reactor_name"], "Second", "the SECOND reactor's Strike effect must resolve strictly after the first's")
	assert_eq(result["reactions"].size(), 2)
	assert_eq(result["reactions"][0]["reactor"], first)
	assert_eq(result["reactions"][1]["reactor"], second)
	assert_true(result["stride_should_commit"], "the Stride may complete when neither reactor's strike was lethal")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 10 (FEAT-008): the FIRST lethal reactor in initiative order
# stops the SECOND reactor from ever being offered a window.
# ══════════════════════════════════════════════════════════════════════════

func test_first_lethal_reactor_in_initiative_order_stops_the_second_reactor() -> void:
	var mover = _mover()
	var first = _reactor("First", HexCoord.new(1, 0))
	var second = _reactor("Second", HexCoord.new(-1, 0))

	var resolver := RecordingResolver.new("opportunistic_strike")
	var strike_use_case := FakeStrikeUseCase.new()
	strike_use_case.defeats_by_call_index = [true]  # the FIRST reactor's strike is lethal
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [first, second], Callable(), Callable(resolver, "resolve"),
		strike_use_case, _reactor_action_economy_fn()
	)

	assert_eq(resolver.calls, ["First"], "the second reactor in initiative order must never even be asked its choice once the first's Strike is lethal")
	assert_eq(strike_use_case.calls.size(), 1, "the second reactor's Strike effect must never resolve against an already-downed mover")
	assert_eq(result["reactions"].size(), 1)
	assert_true(result["mover_downed"])
	assert_false(result["stride_should_commit"])
