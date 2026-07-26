## core/geometry/hex_pathfinder.gd — HexPathfinder.find_path() static A* search
## (FEAT-001 / US-001 / FR-001, NFR-002, NFR-006; RISK-004, RISK-006)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. Like
## core/geometry/hex_math.gd, this is a stateless namespace of `static
## func`s only (no instance state, no `_init`) so it can never accumulate
## per-instance state across calls and can never accidentally import an
## engine/Node dependency through an instance field — this is the concrete
## mitigation for RISK-006 ("pathfinder architecture drifts out of the
## domain layer"), verified mechanically by
## tests/unit/core/geometry/test_architecture_purity.gd.
##
## find_path(start, goal, is_passable, move_cost) → Array[HexCoord] — an A*
## search over the (unbounded) hex grid defined by core/geometry/hex_math.gd's
## hex_neighbors(). `is_passable` and `move_cost` are caller-supplied
## Callables (the "PassabilityQuery"/"MoveCostQuery" application-layer port
## shape, per this feature's design notes) — this file never imports or
## references any concrete tile/resource type, so it stays decoupled from
## whatever data source ultimately answers those questions:
##   is_passable: Callable(HexCoord) -> bool
##   move_cost:   Callable(HexCoord) -> float   (expected >= 1.0 per hex, so
##                the hex cube-distance heuristic below stays admissible/
##                consistent — NFR-006)
##
## Total function, never throws (per this feature's api_contracts):
##   - start == goal (by HexCoord.equals)      -> [start]  (single-element)
##   - goal is impassable                      -> []  (empty Array)
##   - goal is unreachable (blocked/surrounded) -> []  (empty Array)
##   - otherwise                                -> an inclusive, minimal
##     total-move_cost path [start, ..., goal]
##
## Usage:
##   var path: Array = HexPathfinder.find_path(
##       start, goal,
##       func(hex_coord): return hex_coord.q != 3,
##       func(hex_coord): return 1.0
##   )

class_name HexPathfinder

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## _SEARCH_RADIUS_MARGIN / _MIN_SEARCH_RADIUS — core/geometry/hex_math.gd's
## domain hex grid is deliberately UNBOUNDED (no board/map-size concept).
## That means a genuinely unreachable goal (blocked path, or a goal with
## every neighbor impassable) has an infinite reachable region around it on
## an unbounded plane — a plain A*/Dijkstra search only concludes
## "unreachable" by exhausting every reachable node, which would never
## terminate on an infinite plane. Every real caller of this domain service
## works against a finite, authored map (EncounterResource's finite tile
## set), so bounding the search to a generous disk around `start` — well
## beyond any plausible detour — preserves correctness for every reachable
## goal while guaranteeing find_path() always terminates for an
## unreachable one, per this feature's "never throws" contract.
const _SEARCH_RADIUS_MARGIN: int = 24
const _MIN_SEARCH_RADIUS: int = 24


## find_path(start, goal, is_passable, move_cost) → Array[HexCoord] — see
## file header for the full contract. Uses A* with HexMath.hex_distance as
## the heuristic (admissible/consistent as long as `move_cost` never
## returns less than 1.0 for any hex, per NFR-006).
static func find_path(start, goal, is_passable: Callable, move_cost: Callable) -> Array:
	if start.equals(goal):
		return [start]

	if not is_passable.call(goal):
		return []

	var max_search_radius: int = max(
		HexMathClass.hex_distance(start, goal) + _SEARCH_RADIUS_MARGIN, _MIN_SEARCH_RADIUS
	)

	var open_set: Array = [start]
	var open_keys: Dictionary = {_key(start): true}
	var closed_keys: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {_key(start): 0.0}
	var f_score: Dictionary = {_key(start): float(HexMathClass.hex_distance(start, goal))}

	while not open_set.is_empty():
		var current_index: int = _lowest_f_score_index(open_set, f_score)
		var current = open_set[current_index]
		var current_key: String = _key(current)

		if current.equals(goal):
			return _reconstruct_path(came_from, current)

		open_set.remove_at(current_index)
		open_keys.erase(current_key)
		closed_keys[current_key] = true

		for neighbor in HexMathClass.hex_neighbors(current):
			var neighbor_key: String = _key(neighbor)
			if closed_keys.has(neighbor_key):
				continue
			# Bound the search to a finite disk around `start` (see
			# _SEARCH_RADIUS_MARGIN doc above) so an unreachable goal on
			# this unbounded domain grid still terminates.
			if HexMathClass.hex_distance(start, neighbor) > max_search_radius:
				continue
			if not is_passable.call(neighbor):
				continue

			var tentative_g: float = g_score[current_key] + float(move_cost.call(neighbor))
			if tentative_g < g_score.get(neighbor_key, INF):
				came_from[neighbor_key] = current
				g_score[neighbor_key] = tentative_g
				f_score[neighbor_key] = tentative_g + float(HexMathClass.hex_distance(neighbor, goal))
				if not open_keys.has(neighbor_key):
					open_set.append(neighbor)
					open_keys[neighbor_key] = true

	# open_set exhausted without ever popping `goal` — unreachable (blocked
	# path or a fully-surrounded goal).
	return []


## _lowest_f_score_index(open_set, f_score) → int — index within `open_set`
## of the HexCoord with the smallest known f_score. Linear scan (no binary
## heap) — deliberately simple, matching the small-grid scope of this
## steel thread (RISK-004's brute-force/Dijkstra baseline tests exercise
## grids far too small for this to matter).
static func _lowest_f_score_index(open_set: Array, f_score: Dictionary) -> int:
	var best_index: int = 0
	var best_score: float = f_score.get(_key(open_set[0]), INF)
	for i in range(1, open_set.size()):
		var candidate_score: float = f_score.get(_key(open_set[i]), INF)
		if candidate_score < best_score:
			best_score = candidate_score
			best_index = i
	return best_index


## _reconstruct_path(came_from, current) → Array[HexCoord] — walks
## `came_from` backwards from `current` (expected to be `goal`) to `start`,
## returning the inclusive forward-ordered path.
static func _reconstruct_path(came_from: Dictionary, current) -> Array:
	var path: Array = [current]
	var current_key: String = _key(current)
	while came_from.has(current_key):
		current = came_from[current_key]
		current_key = _key(current)
		path.insert(0, current)
	return path


## _key(hex_coord) → String — a stable Dictionary key for a HexCoord's
## (q, r) pair, matching the convention established by
## core/application/selection_resolution_use_case.gd's `_hex_key`. Never
## surfaced outside this file.
static func _key(hex_coord) -> String:
	return "%d,%d" % [hex_coord.q, hex_coord.r]
