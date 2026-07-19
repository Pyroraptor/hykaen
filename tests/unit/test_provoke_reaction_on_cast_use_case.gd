extends GutTest
## tests/unit/test_provoke_reaction_on_cast_use_case.gd — FEAT-279 (US-014;
## FR-016, ADR-005)
##
## GUT suite for core/application/use_cases/
## provoke_reaction_on_cast_use_case.gd's ProvokeReactionOnCastUseCase.
## Mirrors tests/unit/core/application/use_cases/test_resolve_stride_use_case.gd's
## established "plain Dictionary combatant fixtures / recording Callable
## doubles" convention exactly — this use case is a thin wrapper around
## ResolveStrideUseCase, so its own suite focuses on proving the WRAPPING
## contract (stationary mover derived from `actor`'s own hex_coord, safe
## degrade on a positionless/null actor) rather than re-testing
## OpportunisticStrikeEligibility's adjacency/hostility/Spent/melee-reach
## predicate itself (that predicate's own dedicated suite already covers
## it exhaustively).
##
## test_criteria covered (this use case's own contribution to FEAT-279's
## boot-real criteria):
##   - An adjacent, hostile, non-Spent, melee-reach reactor is offered a
##     window (reactor_resolver_fn is awaited) when `actor` "casts" without
##     moving — the SAME eligibility ResolveStrideUseCase already proves,
##     now driven through a STATIONARY mover.
##   - A non-adjacent reactor is never offered a window.
##   - `actor`'s own current hex_coord is used as BOTH the mover and the
##     mover_start_hex passed to ResolveStrideUseCase (no relocation).
##   - A null actor / a positionless actor degrades safely to an empty,
##     no-op outcome.

const ProvokeReactionOnCastUseCaseClass = preload("res://core/application/use_cases/provoke_reaction_on_cast_use_case.gd")
const HexCoord = preload("res://core/geometry/hex_coord.gd")


func _caster() -> Dictionary:
	return {"name": "Marigold", "hex_coord": HexCoord.new(0, 0), "is_enemy": false, "weapon": {"damage_die": 4}}


func _hostile_reactor(name: String, hex_coord) -> Dictionary:
	return {"name": name, "hex_coord": hex_coord, "is_enemy": true, "weapon": {"damage_die": 6}}


## RecordingResolver — a reactor_resolver_fn double recording every call
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


# ══════════════════════════════════════════════════════════════════════════
# Criterion: an eligible, adjacent hostile reactor is offered a window when
# `actor` "casts" without moving.
# ══════════════════════════════════════════════════════════════════════════

func test_adjacent_hostile_reactor_is_offered_a_window_when_actor_casts() -> void:
	var caster = _caster()
	var skeleton = _hostile_reactor("Skeleton", HexCoord.new(1, 0))  # adjacent to (0,0)

	var resolver := RecordingResolver.new("opportunistic_strike")
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		caster, [skeleton], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["Skeleton"], "the adjacent hostile reactor must be offered exactly one window")
	assert_eq(result.get("reactions").size(), 1)
	assert_eq(result.get("reactions")[0].get("choice"), "opportunistic_strike")


func test_non_adjacent_reactor_is_never_offered_a_window() -> void:
	var caster = _caster()
	var far_skeleton = _hostile_reactor("Skeleton", HexCoord.new(5, 5))  # far from (0,0)

	var resolver := RecordingResolver.new("opportunistic_strike")
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		caster, [far_skeleton], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, [], "a non-adjacent reactor must never be offered a window")
	assert_eq(result.get("reactions"), [])


func test_a_second_continuing_cast_action_also_offers_a_window() -> void:
	# Mirrors the boot-real suite's "continuing-cast action also provokes"
	# criterion at the use-case level: nothing about this use case's own
	# behavior depends on whether the caller is a first cast or a
	# continuation -- it is invoked identically either way, so calling it
	# twice in a row (as SpellActionController does across two separate
	# CAST_SPELL executions) must offer a window both times.
	var caster = _caster()
	var skeleton = _hostile_reactor("Skeleton", HexCoord.new(1, 0))
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var first_resolver := RecordingResolver.new("none")
	var first_result: Dictionary = await use_case.execute(
		caster, [skeleton], Callable(), Callable(first_resolver, "resolve")
	)
	assert_eq(first_resolver.calls, ["Skeleton"], "the first-cast action must offer the reactor a window")

	var second_resolver := RecordingResolver.new("none")
	var second_result: Dictionary = await use_case.execute(
		caster, [skeleton], Callable(), Callable(second_resolver, "resolve")
	)
	assert_eq(second_resolver.calls, ["Skeleton"], "the continuing-cast action must ALSO offer the reactor a window")

	assert_eq(first_result.get("reactions").size(), 1)
	assert_eq(second_result.get("reactions").size(), 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion: `actor`'s own current hex_coord is used as BOTH the mover and
# the mover_start_hex -- casting never relocates the caster.
# ══════════════════════════════════════════════════════════════════════════

func test_actors_own_hex_coord_is_used_as_the_stationary_mover_start_hex() -> void:
	var caster = _caster()
	caster["hex_coord"] = HexCoord.new(3, -1)
	var adjacent_reactor = _hostile_reactor("Skeleton", HexCoord.new(4, -1))  # neighbor of (3,-1)

	var resolver := RecordingResolver.new("opportunistic_strike")
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(
		caster, [adjacent_reactor], Callable(), Callable(resolver, "resolve")
	)

	assert_eq(resolver.calls, ["Skeleton"], "eligibility must be evaluated against the caster's OWN live hex_coord, not a hardcoded origin")
	assert_eq(result.get("reactions").size(), 1)


# ══════════════════════════════════════════════════════════════════════════
# Defensive: null / positionless actor degrades safely.
# ══════════════════════════════════════════════════════════════════════════

func test_null_actor_degrades_safely_to_an_empty_outcome() -> void:
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(null, [])

	assert_eq(result, {"reactions": [], "mover_downed": false, "stride_should_commit": true})


func test_positionless_actor_degrades_safely_to_an_empty_outcome() -> void:
	var caster = {"name": "Marigold", "is_enemy": false, "weapon": {}}  # no "hex_coord" key at all
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(caster, [])

	assert_eq(result, {"reactions": [], "mover_downed": false, "stride_should_commit": true})


func test_empty_candidate_reactors_resolves_to_no_reactions() -> void:
	var caster = _caster()
	var use_case := ProvokeReactionOnCastUseCaseClass.new()

	var result: Dictionary = await use_case.execute(caster, [])

	assert_eq(result.get("reactions"), [])
	assert_true(result.get("stride_should_commit"))
