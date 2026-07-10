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

const ResolveStrideUseCaseClass = preload("res://core/application/use_cases/resolve_stride_use_case.gd")
const HexCoord = preload("res://core/geometry/hex_coord.gd")


func _mover() -> Dictionary:
	return {"name": "Skeleton", "hex_coord": HexCoord.new(0, 0), "_is_enemy": true, "weapon": {"damage_die": 6}}


func _reactor(name: String, hex_coord) -> Dictionary:
	return {"name": name, "hex_coord": hex_coord, "_is_enemy": false, "weapon": {"damage_die": 6}}


## RecordingResolver -- a reactor_resolver_fn double recording every call
## (reactor name, in order) and always answering with a fixed choice.
class RecordingResolver:
	extends RefCounted

	var choice_to_return: String
	var calls: Array = []

	func _init(choice: String) -> void:
		choice_to_return = choice

	func resolve(reactor: Dictionary, _context: Dictionary) -> Dictionary:
		calls.append(reactor.get("name", ""))
		return {"choice": choice_to_return}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: an eligible reactor is offered a window and resolved
# ══════════════════════════════════════════════════════════════════════════

func test_eligible_reactor_is_offered_a_window_and_resolved() -> void:
	var mover: Dictionary = _mover()
	var titus: Dictionary = _reactor("Titus", HexCoord.new(1, 0))  # adjacent to (0,0)

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
	var mover: Dictionary = _mover()
	var far_away: Dictionary = _reactor("Far Away", HexCoord.new(9, 9))

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
	var mover: Dictionary = _mover()
	var titus: Dictionary = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	var always_spent := func(_reactor: Dictionary) -> bool:
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
	var mover: Dictionary = _mover()
	var second: Dictionary = _reactor("Second", HexCoord.new(-1, 0))
	var first: Dictionary = _reactor("First", HexCoord.new(1, 0))

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
	var mover: Dictionary = _mover()
	var titus: Dictionary = _reactor("Titus", HexCoord.new(1, 0))

	var use_case := ResolveStrideUseCaseClass.new()
	var result: Dictionary = await use_case.execute(mover, mover["hex_coord"], [titus])

	assert_eq(result["reactions"].size(), 0, "an unwired resolver must never crash, and the eligible reactor is simply skipped")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6: omitting reactor_spent_fn treats every candidate as not Spent
# ══════════════════════════════════════════════════════════════════════════

func test_omitted_reactor_spent_fn_treats_every_candidate_as_not_spent() -> void:
	var mover: Dictionary = _mover()
	var titus: Dictionary = _reactor("Titus", HexCoord.new(1, 0))

	var resolver := RecordingResolver.new("none")
	var use_case := ResolveStrideUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		mover, mover["hex_coord"], [titus], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["Titus"], "an omitted reactor_spent_fn must default to 'never Spent'")
	assert_eq(result["reactions"].size(), 1)
