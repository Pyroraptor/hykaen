## core/application/selection_resolution_use_case.gd —
## SelectionResolutionUseCase (FEAT-008 / US-008)
##
## Application layer (Clean Architecture): depends only on domain
## (core/geometry's pure HexMath/HexCoord) and sibling application-layer
## data types (core/application/selection_descriptor.gd,
## core/application/resolved_selection.gd) — never an adapter/
## infrastructure/presentation type. No ports are introduced by this
## feature (design notes: "no new ports beyond the applier seam").
##
## api_contracts #4: resolve(descriptor, picks) -> ResolvedSelection.
## `picks` is a plain Dictionary carrying whatever raw selection input has
## already been made for `descriptor`'s resolution_mode — this use case
## does NOT itself drive hex-click input (that remains
## presentation/selection_overlay.gd's job, unchanged and out of this
## feature's scope); it only validates a descriptor and packages/derives
## the final ResolvedSelection from picks already gathered:
##   SCALAR              -> picks["scalar_target"]: the same raw target_id/
##                           hex value presentation/selection_overlay.gd's
##                           existing click-matching logic already resolves
##                           today (a String target_id or a HexCoord) —
##                           passed through UNCHANGED, so SCALAR mode's
##                           resolution behavior is byte-identical to legacy
##                           first-hex-clicked behavior (zero regression
##                           surface, US-013).
##   OPTION_THEN_TARGET   -> picks["option"] (the Layer-2a pick) and
##                           picks["scalar_target"] (the Layer-2b pick).
##   AREA_SET             -> picks["origin"] (a HexCoord): this use case
##                           computes the full affected-hex set FROM
##                           `origin` via core/geometry (HexMath), using
##                           descriptor.geometry_rule to parametrize the
##                           shape (currently: {"radius": N}, a BFS
##                           expansion over HexMath.hex_neighbors() —
##                           "core/geometry... reused, not modified": no
##                           new core/geometry file/function is introduced,
##                           this use case is purely a CONSUMER of the
##                           existing pure hex-neighbor primitive).
##
## Validation happens BEFORE any resolution/geometry computation is
## attempted (error_handling policy #4): a null descriptor, an
## AREA_SET descriptor with no bound geometry_rule, or a missing required
## pick for the descriptor's mode all short-circuit straight to
## ResolvedSelection.rejected(reason) — no HexMath call, no UI highlighting
## implied, ever occurs for a malformed request.
##
## Usage:
##   var use_case := SelectionResolutionUseCase.new()
##
##   # SCALAR (default, unchanged for Strike/Step/Stride/End Turn):
##   var strike_descriptor := SelectionDescriptor.new("STRIKE", [], ["enemy_0"], true)
##   use_case.resolve(strike_descriptor, {"scalar_target": "enemy_0"}).scalar_target  # "enemy_0"
##
##   # AREA_SET:
##   var blast_descriptor := SelectionDescriptor.new(
##       "BLAST", [], [], true, null,
##       SelectionDescriptor.ResolutionMode.AREA_SET, {"radius": 1}
##   )
##   var resolved := use_case.resolve(blast_descriptor, {"origin": HexCoord.new(0, 0)})
##   resolved.target_set   # origin + its 6 neighbors (7 HexCoords)

class_name SelectionResolutionUseCase
extends RefCounted

const SelectionDescriptorClass = preload("res://core/application/selection_descriptor.gd")
const ResolvedSelectionClass = preload("res://core/application/resolved_selection.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")


## resolve(descriptor, picks) -> ResolvedSelection — see file-level doc for
## the full per-mode contract. `picks` defaults to an empty Dictionary
## (every key absent -> treated as an unset pick, which rejects for every
## mode except a pathological SCALAR call with no pick at all).
func resolve(descriptor, picks: Dictionary = {}) -> ResolvedSelectionClass:
	if descriptor == null:
		return ResolvedSelectionClass.rejected("descriptor must not be null")

	var mode: int = descriptor.resolution_mode

	# AREA_SET's geometry_rule requirement is validated FIRST, ahead of
	# even looking at `picks` -- a malformed descriptor is rejected before
	# any resolution (including reading an origin pick) begins.
	if mode == SelectionDescriptorClass.ResolutionMode.AREA_SET and descriptor.geometry_rule == null:
		return ResolvedSelectionClass.rejected(
			"AREA_SET descriptor '%s' requires a bound geometry_rule" % descriptor.verb_id
		)

	match mode:
		SelectionDescriptorClass.ResolutionMode.SCALAR:
			return _resolve_scalar(picks)
		SelectionDescriptorClass.ResolutionMode.OPTION_THEN_TARGET:
			return _resolve_option_then_target(picks)
		SelectionDescriptorClass.ResolutionMode.AREA_SET:
			return _resolve_area_set(picks, descriptor.geometry_rule)
		_:
			return ResolvedSelectionClass.rejected("unrecognized resolution_mode: %s" % mode)


## affected_set(origin, geometry_rule) -> Array[HexCoord] — every hex
## affected by an AREA_SET verb centered on `origin`, computed purely via
## core/geometry's HexMath.hex_neighbors() (BFS ring expansion), never a
## re-derived/forked notion of adjacency. `geometry_rule` is a Dictionary
## shaped {"radius": N} (N >= 0); `origin` itself is always included (a
## radius-0 rule affects only `origin`). Exposed as a public method (not
## just a private helper) so a future consumer (e.g. presentation preview/
## highlight, US-011) can call it directly against a candidate origin
## without going through a full resolve() + picks Dictionary.
func affected_set(origin, geometry_rule: Dictionary) -> Array:
	var radius: int = int(geometry_rule.get("radius", 0))
	var visited: Dictionary = {}
	visited[_hex_key(origin)] = origin
	var frontier: Array = [origin]

	for _step in range(radius):
		var next_frontier: Array = []
		for hex_coord in frontier:
			for neighbor in HexMathClass.hex_neighbors(hex_coord):
				var key: String = _hex_key(neighbor)
				if not visited.has(key):
					visited[key] = neighbor
					next_frontier.append(neighbor)
		frontier = next_frontier

	return visited.values()


# ── Internal helpers ─────────────────────────────────────────────────────

func _resolve_scalar(picks: Dictionary) -> ResolvedSelectionClass:
	var value = picks.get("scalar_target")
	if value == null:
		return ResolvedSelectionClass.rejected("SCALAR resolution requires a scalar_target pick")
	return ResolvedSelectionClass.scalar(value)


func _resolve_option_then_target(picks: Dictionary) -> ResolvedSelectionClass:
	var chosen_option = picks.get("option")
	var value = picks.get("scalar_target")
	if chosen_option == null or value == null:
		return ResolvedSelectionClass.rejected(
			"OPTION_THEN_TARGET resolution requires both an option and a scalar_target pick"
		)
	return ResolvedSelectionClass.option_then_target(chosen_option, value)


func _resolve_area_set(picks: Dictionary, geometry_rule: Dictionary) -> ResolvedSelectionClass:
	var origin = picks.get("origin")
	if origin == null:
		return ResolvedSelectionClass.rejected("AREA_SET resolution requires an origin hex pick")
	return ResolvedSelectionClass.area_set(affected_set(origin, geometry_rule))


## _hex_key(hex_coord) -> String — a stable Dictionary key for a HexCoord's
## (q, r) pair, used only for BFS visited-set membership (never surfaced
## outside this file).
func _hex_key(hex_coord) -> String:
	return "%d,%d" % [hex_coord.q, hex_coord.r]
