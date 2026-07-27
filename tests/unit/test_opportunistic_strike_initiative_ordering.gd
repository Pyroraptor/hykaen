extends GutTest
## tests/unit/test_opportunistic_strike_initiative_ordering.gd
##
## GUT test suite for FEAT-228 (US-008, resolves FIND-224 / FR-007): guards
## MainScene.gd's `_verb_bar_stride_execute()` — which builds its
## `candidate_reactors` Array via `_living_combatants(_enemies)` — against
## FIND-224's finding that `_enemies` retains plain ENCOUNTER SPAWN ORDER
## (fixed at boot, before `encounter.initialize()` ever rolls initiative),
## while core/application/use_cases/resolve_stride_use_case.gd's
## ResolveStrideUseCase.execute() explicitly documents that it "resolves
## reactors strictly in the order given, never re-sorting them itself" —
## making the CALLER (MainScene.gd) solely responsible for supplying real
## initiative order. Prior to FEAT-228, no such reordering (nor any
## defensive check) existed, so an enemy roster whose spawn order diverged
## from its rolled initiative order would silently resolve Opportunistic
## Strikes out of turn order, violating this project's deterministic-replay
## ADR.
##
## Mirrors tests/unit/test_build_enemy_combatant_weapon_defense.gd's
## established pattern: a freshly `.new()`-constructed (NOT scene-tree-
## booted) MainScene instance, so the new private helpers this feature adds
## (`_order_candidate_reactors_by_initiative()` /
## `_assert_candidate_reactors_ordering()`) can be exercised directly without
## paying for a full scene boot.
##
## Verifies (this feature's test_criteria):
##   1. test_candidate_reactors_ordered_by_rolled_initiative_not_spawn_order —
##      given candidates in SPAWN order that contradicts their rolled
##      "_initiative_roll", _order_candidate_reactors_by_initiative() returns
##      them sorted DESCENDING by rolled initiative, not spawn order.
##   2. test_ordering_violation_triggers_fail_loud_assertion —
##      _assert_candidate_reactors_ordering() returns false (the fail-loud
##      signal GUT can observe — this project's Godot 4.3 engine cannot
##      capture assert()/push_error() output directly, mirroring
##      core/application/reaction_window.gd's own
##      assert_reaction_budget_delta() convention) when handed an ordering
##      that is inconsistent with encounter.get_turn_order()'s (the rolled
##      initiative table) own order, and returns true for a consistent one.
##   3. test_two_eligible_reactors_resolve_in_initiative_order (regression
##      against US-008's ResolveStrideUseCase ordering contract) — feeding
##      _order_candidate_reactors_by_initiative()'s output (built from
##      candidates in SPAWN order) into the REAL
##      core/application/use_cases/resolve_stride_use_case.gd
##      ResolveStrideUseCase.execute() resolves the two eligible reactors in
##      INITIATIVE order, not the spawn order they were originally supplied
##      in — proving FIND-224's actual downstream gameplay effect is fixed,
##      not merely that a helper function sorts correctly in isolation.

const MainSceneClass = preload("res://MainScene.gd")
const ReactionControllerClass = preload("res://presentation/reaction_controller.gd")
const ResolveStrideUseCaseClass = preload("res://core/application/use_cases/resolve_stride_use_case.gd")
const HexCoord = preload("res://core/geometry/hex_coord.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

var _instance = null


func before_each() -> void:
	_instance = MainSceneClass.new()
	_instance._reaction_instance = ReactionControllerClass.new(
		Callable(), Callable(), null, null, null, null
	)


func after_each() -> void:
	if _instance != null:
		_instance.free()
	_instance = null


## _reactor(name, initiative_roll, hex_coord) -- a hostile (enemy) melee
## reactor Dictionary, mirroring tests/unit/core/application/use_cases/
## test_resolve_stride_use_case.gd's own `_reactor()` fixture shape plus the
## "_initiative_roll"/"combatant_id" fields core/combat/encounter.gd's
## initialize() stamps onto every combatant Dictionary in real play.
func _reactor(name: String, initiative_roll: int, hex_coord):
	return CombatantClass.from_dict({
		"name": name,
		"combatant_id": name,
		"hex_coord": hex_coord,
		"hp_current": 10,
		"_is_enemy": true,
		"_initiative_roll": initiative_roll,
		"weapon": {"damage_die": 6},
	})


## _mover() -- the (player) Stride actor, starting at (0, 0), hostile to
## every `_reactor()` fixture above.
func _mover():
	return CombatantClass.from_dict({"name": "Titus", "combatant_id": "titus", "hex_coord": HexCoord.new(0, 0), "_is_enemy": false, "weapon": {"damage_die": 6}})


## RecordingResolver -- a reactor_resolver_fn double recording every call
## (reactor name, in order) and always answering "opportunistic_strike",
## mirroring test_resolve_stride_use_case.gd's own identically-named double.
class RecordingResolver:
	extends RefCounted

	var calls: Array = []

	func resolve(reactor, _context: Dictionary) -> Dictionary:
		calls.append(reactor.name)
		return {"choice": "opportunistic_strike"}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: candidate_reactors ordered by rolled initiative, not spawn
# order.
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_reactors_ordered_by_rolled_initiative_not_spawn_order() -> void:
	# Spawn order (mirrors _enemies' own Array order, i.e. enemy_resource_paths
	# order): the LOW-initiative reactor was authored/spawned FIRST, the
	# HIGH-initiative reactor SECOND -- the exact spawn-order-vs-initiative
	# divergence FIND-224 identified.
	var low_roll_spawned_first = _reactor("EarlySpawnLowRoll", 5, HexCoord.new(1, 0))
	var high_roll_spawned_second = _reactor("LateSpawnHighRoll", 20, HexCoord.new(-1, 0))

	var spawn_order: Array = [low_roll_spawned_first, high_roll_spawned_second]

	var ordered: Array = _instance._order_candidate_reactors_by_initiative(spawn_order)

	assert_eq(
		ordered, [high_roll_spawned_second, low_roll_spawned_first],
		"candidate_reactors must be ordered by rolled initiative (descending), not encounter spawn order"
	)
	# The input Array itself must never be mutated in place.
	assert_eq(spawn_order, [low_roll_spawned_first, high_roll_spawned_second], "_order_candidate_reactors_by_initiative() must not mutate its input Array")


func test_ordering_is_stable_for_equal_initiative_rolls() -> void:
	var first = _reactor("First", 10, HexCoord.new(1, 0))
	var second = _reactor("Second", 10, HexCoord.new(-1, 0))

	var ordered: Array = _instance._order_candidate_reactors_by_initiative([first, second])

	assert_eq(ordered, [first, second], "equal rolled-initiative candidates must preserve their original (spawn) relative order -- a stable sort")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: an ordering violation triggers the fail-loud assertion.
# ══════════════════════════════════════════════════════════════════════════

func test_ordering_violation_triggers_fail_loud_assertion() -> void:
	var low_roll = _reactor("EarlySpawnLowRoll", 5, HexCoord.new(1, 0))
	var high_roll = _reactor("LateSpawnHighRoll", 20, HexCoord.new(-1, 0))

	# The rolled initiative table (encounter.get_turn_order()'s own shape --
	# descending, one entry per combatant) says high_roll acts before
	# low_roll.
	var turn_order: Array = [high_roll, low_roll]

	# A caller that (incorrectly) hands the assertion candidates still in
	# spawn order -- the exact FIND-224 regression this method exists to
	# catch.
	var inconsistent_order: Array = [low_roll, high_roll]

	assert_false(
		_instance._assert_candidate_reactors_ordering(inconsistent_order, turn_order),
		"an ordering inconsistent with encounter.get_turn_order() must fail loud (return false)"
	)


func test_ordering_violation_reports_true_when_a_candidate_is_absent_from_turn_order() -> void:
	var low_roll = _reactor("EarlySpawnLowRoll", 5, HexCoord.new(1, 0))
	var high_roll = _reactor("LateSpawnHighRoll", 20, HexCoord.new(-1, 0))

	# turn_order is missing `low_roll` entirely -- ordering can never be
	# verified against the table, which must also fail loud.
	var turn_order: Array = [high_roll]

	assert_false(
		_instance._assert_candidate_reactors_ordering([high_roll, low_roll], turn_order),
		"a candidate absent from encounter.get_turn_order() must fail loud (return false)"
	)


func test_consistent_ordering_does_not_trigger_the_assertion() -> void:
	var low_roll = _reactor("EarlySpawnLowRoll", 5, HexCoord.new(1, 0))
	var high_roll = _reactor("LateSpawnHighRoll", 20, HexCoord.new(-1, 0))

	var turn_order: Array = [high_roll, low_roll]
	var consistent_order: Array = [high_roll, low_roll]

	assert_true(
		_instance._assert_candidate_reactors_ordering(consistent_order, turn_order),
		"an ordering consistent with encounter.get_turn_order() must NOT fail loud (must return true)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (regression against US-008's ResolveStrideUseCase ordering
# contract): two eligible reactors resolve their Opportunistic Strike in
# initiative order, not spawn order.
# ══════════════════════════════════════════════════════════════════════════

func test_two_eligible_reactors_resolve_in_initiative_order() -> void:
	var mover = _mover()

	# Both reactors are adjacent to mover's start hex (0, 0) and melee-armed
	# -- both OpportunisticStrikeEligibility-eligible. Spawn order (the
	# pre-FEAT-228 buggy candidate_reactors order) is
	# [EarlySpawnLowRoll, LateSpawnHighRoll] -- the LOWER-initiative reactor
	# spawned first.
	var early_spawn_low_roll = _reactor("EarlySpawnLowRoll", 5, HexCoord.new(1, 0))
	var late_spawn_high_roll = _reactor("LateSpawnHighRoll", 20, HexCoord.new(-1, 0))
	var spawn_order: Array = [early_spawn_low_roll, late_spawn_high_roll]

	# This is FEAT-228's actual fix, exercised exactly as
	# _verb_bar_stride_execute() now calls it: reorder BEFORE handing
	# candidate_reactors to ResolveStrideUseCase.execute().
	var candidate_reactors: Array = _instance._order_candidate_reactors_by_initiative(spawn_order)

	var resolver := RecordingResolver.new()
	var use_case := ResolveStrideUseCaseClass.new()

	await use_case.execute(
		mover, mover.hex_coord, candidate_reactors, Callable(), Callable(resolver, "resolve")
	)

	assert_eq(
		resolver.calls, ["LateSpawnHighRoll", "EarlySpawnLowRoll"],
		"reactors must resolve in ROLLED INITIATIVE order (high roll first), never encounter spawn order"
	)
