extends GutTest
## tests/unit/core/geometry/test_hex_pathfinder.gd
##
## GUT test suite for FEAT-001 / US-001 / FR-001 — HexPathfinder.find_path()
## static A* domain service (core/geometry/hex_pathfinder.gd).
##
## Verifies (per this feature's test_criteria):
##   1. Straight-line path between two reachable hexes returns the
##      minimal-length inclusive HexCoord array.
##   2. Detour-around-obstacle scenario returns a valid path avoiding the
##      impassable hex.
##   3. Impassable goal hex returns an empty array (never throws).
##   4. Fully-surrounded goal hex returns an empty array.
##   5. Difficult-terrain scenario returns the path with minimal total
##      move_cost, verified against a brute-force/Dijkstra baseline
##      (RISK-004) implemented independently in this test file.
##   6. Heuristic non-overestimation (admissibility) assertion vs the same
##      Dijkstra baseline on a small grid (RISK-004, NFR-006).
##   7. start == goal returns a single-element array containing start.
##   8. FEAT-326 (DEF-003): a long U-shaped wall detour whose farthest
##      required hex from `start` sits just UNDER the documented
##      _SEARCH_RADIUS_MARGIN-derived search bound still returns a valid,
##      connected path.
##   9. FEAT-326 (DEF-003): the same U-shaped wall shape, stretched just
##      OVER that bound, correctly (and silently) returns an empty array,
##      pinning the intentional/accepted boundary limitation rather than
##      leaving it unverified.
##
## The architecture-purity check (RISK-006, NFR-002) lives in its own file,
## tests/unit/core/geometry/test_architecture_purity.gd, per this feature's
## files_to_create list.

const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")
const HexMathClass: GDScript = preload("res://core/geometry/hex_math.gd")
const HexPathfinderClass: GDScript = preload("res://core/geometry/hex_pathfinder.gd")

var _ALWAYS_PASSABLE: Callable = func(_hex): return true
var _UNIT_COST: Callable = func(_hex): return 1.0


# ── Shared helpers ────────────────────────────────────────────────────────────

func _key(hex_coord) -> String:
	return "%d,%d" % [hex_coord.q, hex_coord.r]


## _assert_valid_path(path, start, goal, is_passable) — common structural
## assertions reused across scenarios: non-empty, starts at `start`, ends
## at `goal`, every consecutive pair is adjacent (distance 1), and every
## hex in the path (per is_passable) is passable.
func _assert_valid_path(path: Array, start, goal, is_passable: Callable) -> void:
	assert_false(path.is_empty(), "path must not be empty for a reachable goal")
	if path.is_empty():
		return
	assert_true(path[0].equals(start), "path must start at the start hex")
	assert_true(path[path.size() - 1].equals(goal), "path must end at the goal hex")
	for i in range(1, path.size()):
		assert_eq(
			HexMathClass.hex_distance(path[i - 1], path[i]), 1,
			"consecutive path hexes must be adjacent (distance 1)"
		)
	for hex_coord in path:
		assert_true(
			is_passable.call(hex_coord),
			"every hex in the returned path must be passable"
		)


## _path_cost(path, move_cost) → float — total move_cost of a path,
## excluding the start hex (no cost is incurred to "enter" the hex the
## mover already occupies).
func _path_cost(path: Array, move_cost: Callable) -> float:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += float(move_cost.call(path[i]))
	return total


## _dijkstra_costs(start, is_passable, move_cost, bound_radius) → Dictionary
## key -> float — an independently-implemented (from HexPathfinder)
## brute-force Dijkstra shortest-cost-from-`start` search, restricted to
## hexes within `bound_radius` of `start` so it always terminates on the
## unbounded domain hex grid. Used as this suite's ground-truth baseline
## (RISK-004) for both "minimal total move_cost" and "heuristic never
## overestimates" assertions.
func _dijkstra_costs(start, is_passable: Callable, move_cost: Callable, bound_radius: int) -> Dictionary:
	var costs: Dictionary = {}
	var coords_by_key: Dictionary = {}
	var visited: Dictionary = {}

	var start_key: String = _key(start)
	costs[start_key] = 0.0
	coords_by_key[start_key] = start

	while true:
		var current_key: String = ""
		var current_cost: float = INF
		for k in costs.keys():
			if visited.has(k):
				continue
			if costs[k] < current_cost:
				current_cost = costs[k]
				current_key = k

		if current_key == "":
			break
		visited[current_key] = true
		var current = coords_by_key[current_key]

		for neighbor in HexMathClass.hex_neighbors(current):
			if HexMathClass.hex_distance(start, neighbor) > bound_radius:
				continue
			if not is_passable.call(neighbor):
				continue
			var neighbor_key: String = _key(neighbor)
			var candidate_cost: float = current_cost + float(move_cost.call(neighbor))
			if candidate_cost < costs.get(neighbor_key, INF):
				costs[neighbor_key] = candidate_cost
				coords_by_key[neighbor_key] = neighbor

	return costs


# ── Criterion 1: straight-line minimal-length path ───────────────────────────

func test_straight_line_path_returns_minimal_length_inclusive_array() -> void:
	var start = HexCoordClass.new(0, 0)
	var goal = HexCoordClass.new(3, 0)

	var path: Array = HexPathfinderClass.find_path(start, goal, _ALWAYS_PASSABLE, _UNIT_COST)

	_assert_valid_path(path, start, goal, _ALWAYS_PASSABLE)
	var expected_length: int = HexMathClass.hex_distance(start, goal) + 1
	assert_eq(path.size(), expected_length, "an open-field path must be exactly hex_distance + 1 hexes long")


# ── Criterion 2: detour around an impassable obstacle ────────────────────────

func test_detour_around_obstacle_avoids_impassable_hex() -> void:
	var start = HexCoordClass.new(0, 0)
	var goal = HexCoordClass.new(2, 0)
	var blocked = HexCoordClass.new(1, 0)

	var is_passable := func(hex_coord): return not hex_coord.equals(blocked)

	var path: Array = HexPathfinderClass.find_path(start, goal, is_passable, _UNIT_COST)

	_assert_valid_path(path, start, goal, is_passable)
	for hex_coord in path:
		assert_false(hex_coord.equals(blocked), "path must never route through the impassable hex")


# ── Criterion 3: impassable goal hex ─────────────────────────────────────────

func test_impassable_goal_returns_empty_array() -> void:
	var start = HexCoordClass.new(0, 0)
	var goal = HexCoordClass.new(2, 0)

	var is_passable := func(hex_coord): return not hex_coord.equals(goal)

	var path: Array = HexPathfinderClass.find_path(start, goal, is_passable, _UNIT_COST)

	assert_true(path.is_empty(), "an impassable goal must yield an empty array, never a crash")


# ── Criterion 4: fully-surrounded goal hex ───────────────────────────────────

func test_fully_surrounded_goal_returns_empty_array() -> void:
	var start = HexCoordClass.new(0, 0)
	var goal = HexCoordClass.new(5, -5)

	var surrounding_keys: Dictionary = {}
	for neighbor in HexMathClass.hex_neighbors(goal):
		surrounding_keys[_key(neighbor)] = true

	var is_passable := func(hex_coord): return not surrounding_keys.has(_key(hex_coord))

	var path: Array = HexPathfinderClass.find_path(start, goal, is_passable, _UNIT_COST)

	assert_true(path.is_empty(), "a goal with every neighbor impassable must be unreachable -> empty array")


# ── Criterion 5: difficult terrain minimizes total move_cost (RISK-004) ─────

## _difficult_terrain_move_cost — hexes (1,0), (2,0), (3,0) cost 5.0 to
## enter ("difficult terrain" directly between start and goal); every other
## hex costs 1.0. A route that detours through row r=-1 is longer in hex
## count but far cheaper in total move_cost, so the minimal-cost path is
## NOT the minimal-length path — the scenario this criterion exists to
## catch (a pathfinder that greedily minimizes step count instead of cost).
func _difficult_terrain_move_cost(hex_coord) -> float:
	if hex_coord.r == 0 and hex_coord.q >= 1 and hex_coord.q <= 3:
		return 5.0
	return 1.0


func test_difficult_terrain_path_has_minimal_total_move_cost_vs_dijkstra_baseline() -> void:
	var start = HexCoordClass.new(0, 0)
	var goal = HexCoordClass.new(4, 0)
	var move_cost := func(hex_coord): return _difficult_terrain_move_cost(hex_coord)

	var path: Array = HexPathfinderClass.find_path(start, goal, _ALWAYS_PASSABLE, move_cost)
	_assert_valid_path(path, start, goal, _ALWAYS_PASSABLE)

	var baseline_costs: Dictionary = _dijkstra_costs(start, _ALWAYS_PASSABLE, move_cost, 8)
	var baseline_goal_cost: float = baseline_costs[_key(goal)]

	var actual_cost: float = _path_cost(path, move_cost)
	assert_almost_eq(
		actual_cost, baseline_goal_cost, 0.001,
		"HexPathfinder's total move_cost must match the independent Dijkstra baseline's minimal cost"
	)

	# Sanity-check the scenario itself actually exercises the cost-vs-length
	# tradeoff: the naive straight-line route (cost 5+5+5+1=16) must NOT be
	# what's returned; the cheaper detour (cost 5) must be.
	var direct_route_cost: float = 5.0 + 5.0 + 5.0 + 1.0
	assert_true(
		actual_cost < direct_route_cost,
		"minimal-cost path must be cheaper than the naive straight-line route through difficult terrain"
	)


# ── Criterion 6: heuristic never overestimates (admissibility, NFR-006) ─────

func test_heuristic_never_overestimates_dijkstra_baseline_cost() -> void:
	var goal = HexCoordClass.new(4, 0)
	var move_cost := func(hex_coord): return _difficult_terrain_move_cost(hex_coord)

	var candidate_nodes: Array = [
		HexCoordClass.new(0, 0),
		HexCoordClass.new(2, -1),
		HexCoordClass.new(3, -1),
		HexCoordClass.new(2, 0),
		HexCoordClass.new(1, 1),
	]

	for node in candidate_nodes:
		var costs_from_node: Dictionary = _dijkstra_costs(node, _ALWAYS_PASSABLE, move_cost, 8)
		var goal_key: String = _key(goal)
		assert_true(
			costs_from_node.has(goal_key),
			"goal must be reachable from every candidate node in this open-field scenario"
		)
		if not costs_from_node.has(goal_key):
			continue
		var actual_cost_to_goal: float = costs_from_node[goal_key]
		var heuristic_estimate: int = HexMathClass.hex_distance(node, goal)
		assert_true(
			heuristic_estimate <= actual_cost_to_goal + 0.001,
			"heuristic hex_distance(%s, goal) = %d must never exceed the true Dijkstra cost %f" % [
				node, heuristic_estimate, actual_cost_to_goal
			]
		)


# ── Criterion 7: start == goal ───────────────────────────────────────────────

func test_start_equals_goal_returns_single_element_array() -> void:
	var start = HexCoordClass.new(2, -3)
	var goal = HexCoordClass.new(2, -3)

	var path: Array = HexPathfinderClass.find_path(start, goal, _ALWAYS_PASSABLE, _UNIT_COST)

	assert_eq(path.size(), 1, "start == goal must return a single-element array")
	if path.size() == 1:
		assert_true(path[0].equals(start), "the single element must be the start hex")


func test_start_equals_goal_does_not_require_start_to_be_passable() -> void:
	# The mover always occupies `start` already, so find_path must not
	# consult is_passable for the start==goal case -- a party member
	# standing on a hex must always be able to "path" to their own hex.
	var start = HexCoordClass.new(1, 1)
	var goal = HexCoordClass.new(1, 1)
	var is_passable := func(_hex): return false

	var path: Array = HexPathfinderClass.find_path(start, goal, is_passable, _UNIT_COST)

	assert_eq(path.size(), 1, "start == goal must short-circuit before any is_passable check")


# ── FEAT-326 (DEF-003): pin the _SEARCH_RADIUS_MARGIN boundary behavior ─────
##
## HexPathfinder.find_path() bounds its search to a finite disk around
## `start` -- max(hex_distance(start, goal) + _SEARCH_RADIUS_MARGIN,
## _MIN_SEARCH_RADIUS) hexes -- so that a genuinely unreachable goal on the
## domain's unbounded grid still terminates (see hex_pathfinder.gd's header
## comment). That bound is an intentional, documented tradeoff: any real
## detour that would require straying further than the margin from `start`
## is treated as unreachable, even if a path technically exists on the
## unbounded plane. No prior test in this suite exercised a detour anywhere
## near that boundary, so a regression that silently shrunk the margin (or
## widened it) would go undetected -- that's DEF-003.
##
## _make_u_wall_is_passable(arm_length, q_left) builds a U-shaped wall
## (an infinite base wall along r == 0 for every q >= q_left, closed off
## by a single left arm at q == q_left spanning r in [-arm_length, -1]):
##
##                      ...wall (r=0, q>=q_left) is infinite to the right...
##      r=0    ##########################################################>
##      r=-1   #    <-- pocket interior (q > q_left) -->
##      ...    #
##      r=-arm_length
##             #
##      r=-(arm_length+1)   <-- only unwalled row at q=q_left; the sole exit
##
## `start` sits inside the pocket just south of the base wall; `goal` sits
## just north of it, straight-line distance 2 away, but the base wall is
## impassable directly between them. The ONLY route from start to goal is:
## south inside the pocket to r <= -(arm_length+1), west past q_left to
## q <= q_left-1 (the only column never walled), north across r=0 (open
## once q < q_left), then back east to goal. Every other row/column is
## open, so this is a forced, single detour route (no shorter alternative
## exists). Note the hex grid's diagonal step lets the route "cut the
## corner" when crossing from q_left back to q_left-1 (one step both
## decrements q and increments r), so the detour's farthest hex from
## `start` is empirically/analytically hex_distance arm_length + 2 away
## from start -- NOT arm_length + 3, as a naive "go straight down, straight
## across, straight up" reading of the ASCII diagram above would suggest.
## This exact constant (+2) was derived by brute-force search (an
## independent Dijkstra sweep over arm_length, see this feature's
## development notes) and is re-verified implicitly every time these two
## tests run, since both assert the expected reachable/unreachable outcome
## at the boundary computed from it.
func _make_u_wall_is_passable(arm_length: int, q_left: int) -> Callable:
	return func(hex_coord):
		if hex_coord.r == 0 and hex_coord.q >= q_left:
			return false
		if hex_coord.q == q_left and hex_coord.r >= -arm_length and hex_coord.r <= -1:
			return false
		return true


## _u_wall_detour_scenario(arm_length) → Dictionary{start, goal, is_passable}
## — shared scenario builder for both margin-boundary tests below. `q_left`
## is fixed at -2 so the forced detour's farthest hex from `start` is
## always exactly (arm_length + 2) away (see derivation above).
func _u_wall_detour_scenario(arm_length: int) -> Dictionary:
	var q_left: int = -2
	return {
		"start": HexCoordClass.new(0, -1),
		"goal": HexCoordClass.new(0, 1),
		"is_passable": _make_u_wall_is_passable(arm_length, q_left),
	}


func test_u_shaped_wall_detour_just_under_search_radius_margin_still_finds_path() -> void:
	var margin: int = HexPathfinderClass._SEARCH_RADIUS_MARGIN
	var min_radius: int = HexPathfinderClass._MIN_SEARCH_RADIUS

	var probe = _u_wall_detour_scenario(0)
	var distance: int = HexMathClass.hex_distance(probe.start, probe.goal)
	var max_search_radius: int = max(distance + margin, min_radius)

	# Choose arm_length so the detour's farthest required hex from `start`
	# (arm_length + 2, see header derivation) lands exactly ONE hex UNDER
	# max_search_radius -- as close to the documented margin boundary as
	# possible while still being guaranteed reachable.
	var arm_length: int = max_search_radius - 1 - 2
	var scenario = _u_wall_detour_scenario(arm_length)

	var farthest_required_distance: int = arm_length + 2
	assert_true(
		farthest_required_distance < max_search_radius,
		"test setup sanity check: the detour must require straying just UNDER max_search_radius"
	)

	var path: Array = HexPathfinderClass.find_path(
		scenario.start, scenario.goal, scenario.is_passable, _UNIT_COST
	)

	_assert_valid_path(path, scenario.start, scenario.goal, scenario.is_passable)


func test_u_shaped_wall_detour_beyond_search_radius_margin_returns_empty_array() -> void:
	var margin: int = HexPathfinderClass._SEARCH_RADIUS_MARGIN
	var min_radius: int = HexPathfinderClass._MIN_SEARCH_RADIUS

	var probe = _u_wall_detour_scenario(0)
	var distance: int = HexMathClass.hex_distance(probe.start, probe.goal)
	var max_search_radius: int = max(distance + margin, min_radius)

	# Choose arm_length so the detour's farthest required hex from `start`
	# (arm_length + 2) lands exactly ONE hex BEYOND max_search_radius --
	# a detour that is, on the unbounded plane, still perfectly reachable,
	# but falls just outside this domain service's documented, accepted
	# search-bound tradeoff. This must return [] (never throw), pinning the
	# current intentional limitation rather than treating it as a bug.
	var arm_length: int = max_search_radius + 1 - 2
	var scenario = _u_wall_detour_scenario(arm_length)

	var farthest_required_distance: int = arm_length + 2
	assert_true(
		farthest_required_distance > max_search_radius,
		"test setup sanity check: the detour must require straying just BEYOND max_search_radius"
	)

	var path: Array = HexPathfinderClass.find_path(
		scenario.start, scenario.goal, scenario.is_passable, _UNIT_COST
	)

	assert_true(
		path.is_empty(),
		"a detour just beyond the documented _SEARCH_RADIUS_MARGIN bound must return [] (never throw), " +
		"pinning the accepted search-radius limitation rather than silently changing behavior"
	)
