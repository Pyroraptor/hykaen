## scenes/battlefield/HexBattlefield.gd — HexBattlefield (FEAT-005 / US-005)
##
## Presentation layer (Clean Architecture): renders the flat-top hex
## battlefield using the EXISTING domain hex/position data
## (core/geometry/hex_coord.gd, core/domain/combatant.gd) and instantiates
## one CombatantReadout (scenes/battlefield/CombatantReadout.gd) per
## combatant, satisfying US-005's "sees the hex battlefield with all
## combatants, and each combatant's name/HP/Stamina/action budget/Spent/
## conditions" criterion in a single composed widget.
##
## The ADR-004 flat-top axial-to-pixel translation lives here (Presentation,
## NOT Domain, per ADR-001) — mapping a domain HexCoord to a screen-space
## Vector2 is a rendering concern, not a combat rule, so
## core/geometry/hex_math.gd stays free of any pixel/Vector2 concept. This
## mirrors the precedent already established by
## presentation/hex_grid_view.gd for the earlier hex-rendering feature.
##
## HexBattlefield is READ-ONLY / read-and-render only with respect to domain
## state (ADR-001):
##   - load_combatants(combatants, view_models) reads each combatant's
##     hex_coord (positional data) and, when supplied, a matching
##     name/HP/Stamina/action-budget/Spent/conditions view model -- it never
##     mutates either.
##   - on_round_event(event) is the ONE integration point this widget offers
##     for EventSinkPort round-event broadcasts (ADR-003): it forwards the
##     event, unmodified, to every instantiated CombatantReadout, each of
##     which independently decides (by name match) whether the event applies
##     to it. HexBattlefield itself never inspects an event's roll/damage/
##     hit fields -- it does no combat computation of any kind (verified by
##     tests/gut/test_hex_battlefield.gd's source-inspection guardrail and by
##     code review).

class_name HexBattlefield
extends Node2D

const CombatantReadoutClass = preload("res://scenes/battlefield/CombatantReadout.gd")

## Pixel radius of one hex cell (center to corner), flat-top orientation.
const HEX_SIZE: float = 48.0

## Number of concentric rings of hex cells drawn around the origin for the
## background battlefield grid -- a fixed, generous bound; the prologue
## encounter's authored positions all fall well within it.
const GRID_RADIUS: int = 5

const GRID_LINE_COLOR: Color = Color(0.35, 0.35, 0.4, 1.0)

## Tint applied to a readout marked selectable via
## set_selectable_combatant_ids() (FEAT-007) -- a purely visual affordance,
## computed and requested entirely by the caller (e.g. scenes/battlefield/
## StrikeInputController.gd); this file never decides selectability itself.
const _SELECTABLE_TINT: Color = Color(0.55, 1.0, 0.55, 1.0)

## Tint applied to a readout explicitly marked NOT selectable (FEAT-007).
const _NOT_SELECTABLE_TINT: Color = Color(1.0, 1.0, 1.0, 0.35)

const _DEFAULT_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

## combatant_id (String) -> {"q": int, "r": int}, populated by
## load_combatants() -- the rendered hex position for each combatant,
## exposed for test/inspection assertions (US-005 test_criteria: "rendered
## hex coordinate matches its domain HexPosition").
var _hex_by_id: Dictionary = {}

## combatant_id (String) -> the domain HexCoord instance itself (as opposed
## to _hex_by_id's plain {"q","r"} snapshot above), populated by
## load_combatants() (FEAT-007). Exposed via get_hex_coord() so a caller
## (e.g. StrikeInputController) can reuse this widget's already-loaded
## position data as its single source of truth for target-selection
## affordances, instead of requiring every candidate Dictionary to carry a
## duplicated "hex_coord" key of its own.
var _hex_coord_by_id: Dictionary = {}

## combatant_id (String) -> CombatantReadout, populated by load_combatants().
var _readouts: Dictionary = {}

## combatant_id (String) -> true, populated by set_selectable_combatant_ids()
## (FEAT-007) -- purely a display concern (which token(s) currently render as
## selectable); this file performs no computation of what SHOULD be
## selectable.
var _selectable_ids: Dictionary = {}

## combatant_id (String) -> true, populated by set_selectable_combatant_ids()
## (FEAT-007) -- tokens explicitly flagged as not-currently-selectable (e.g.
## a candidate target too far away this turn), rendered dimmed so the UI
## visibly communicates they cannot be chosen.
var _not_selectable_ids: Dictionary = {}


func _draw() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s: int = -q - r
			if absi(s) <= GRID_RADIUS:
				_draw_hex_cell(q, r)


func _draw_hex_cell(q: int, r: int) -> void:
	var center: Vector2 = axial_to_pixel_qr(q, r, HEX_SIZE)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		points.append(center + _hex_corner_offset(HEX_SIZE, i % 6))
	draw_polyline(points, GRID_LINE_COLOR, 1.0)


## _hex_corner_offset(size, corner_index) → Vector2 — the offset of one of
## the 6 corners of a flat-top hexagon of the given size, relative to its
## center. Flat-top corners sit at 0°, 60°, 120°, ... (no angular offset,
## unlike pointy-top's -30° offset).
static func _hex_corner_offset(size: float, corner_index: int) -> Vector2:
	var angle_rad: float = deg_to_rad(60.0 * corner_index)
	return Vector2(size * cos(angle_rad), size * sin(angle_rad))


## axial_to_pixel(hex_coord, hex_size) → Vector2 — ADR-004 flat-top axial
## coordinate to screen-pixel translation:
##   x = hex_size * (3/2 * q)
##   y = hex_size * (sqrt(3)/2 * q + sqrt(3) * r)
## `hex_coord` is duck-typed: any object exposing integer q/r fields (i.e. a
## core/geometry/hex_coord.gd HexCoord instance).
static func axial_to_pixel(hex_coord, hex_size: float = HEX_SIZE) -> Vector2:
	return axial_to_pixel_qr(hex_coord.q, hex_coord.r, hex_size)


## axial_to_pixel_qr(q, r, hex_size) → Vector2 — the same ADR-004 formula as
## axial_to_pixel(), taking raw q/r ints directly (used internally by
## _draw_hex_cell() for grid-cell centers, which have no HexCoord instance).
static func axial_to_pixel_qr(q: int, r: int, hex_size: float = HEX_SIZE) -> Vector2:
	var x: float = hex_size * (1.5 * q)
	var y: float = hex_size * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)
	return Vector2(x, y)


## _is_within_grid_radius(hex_coord) → bool — FEAT-157 / FIND-150: true iff
## `hex_coord`'s axial position falls within this battlefield's rendered
## GRID_RADIUS ring (the same q/r/s bound _draw() already enforces for the
## background grid cells). A latent domain bug that hands load_combatants()
## or move_token() an out-of-radius HexPosition must never silently
## reposition/render a CombatantReadout off-screen with no indication --
## move_token() and load_combatants() both consult this guard before trusting
## a hex_coord for rendering, logging a push_warning() and skipping the
## render instead.
static func _is_within_grid_radius(hex_coord) -> bool:
	if hex_coord == null or not ("q" in hex_coord) or not ("r" in hex_coord):
		return false
	var q: int = hex_coord.q
	var r: int = hex_coord.r
	var s: int = -q - r
	return absi(q) <= GRID_RADIUS and absi(r) <= GRID_RADIUS and absi(s) <= GRID_RADIUS


## load_combatants(combatants, view_models) → void — instantiates one
## CombatantReadout per entry in `combatants`, positioned at that
## combatant's mapped screen position (axial_to_pixel(hex_coord)). Clears
## any previously-instantiated readouts first, so a repeated call (e.g. a
## future encounter reload) never leaks duplicate children.
##
## `combatants` is an Array of duck-typed objects exposing combatant_id/
## name/hex_coord (i.e. core/domain/combatant.gd Combatant instances, as
## returned by infrastructure/resource_encounter_repository.gd).
##
## `view_models` (optional) is an Array of Dictionaries carrying the fuller
## name/HP/Stamina/action-budget/Spent/conditions snapshot for each
## combatant (the same shape presentation/status_panel_view.gd's
## load_combatants() accepts) -- matched to `combatants` by combatant_id.
## A combatant with no matching view model still gets a readout, seeded with
## just its combatant_id/name (HP/Stamina/etc. default to 0/empty) so this
## widget behaves correctly even before HP/Stamina view models exist for a
## given caller.
func load_combatants(combatants: Array, view_models: Array = []) -> void:
	for existing_readout in _readouts.values():
		existing_readout.queue_free()
	_readouts.clear()
	_hex_by_id.clear()
	_hex_coord_by_id.clear()
	_selectable_ids.clear()
	_not_selectable_ids.clear()

	var view_model_by_id: Dictionary = {}
	for view_model in view_models:
		view_model_by_id[view_model.get("combatant_id", "")] = view_model

	for combatant in combatants:
		if not _is_within_grid_radius(combatant.hex_coord):
			push_warning(
				"HexBattlefield.load_combatants: combatant '%s' hex_coord (q=%d, r=%d) is outside GRID_RADIUS=%d -- skipping readout to avoid silently rendering it off-screen (FEAT-157/FIND-150)"
				% [combatant.combatant_id, combatant.hex_coord.q, combatant.hex_coord.r, GRID_RADIUS]
			)
			continue

		_hex_by_id[combatant.combatant_id] = {"q": combatant.hex_coord.q, "r": combatant.hex_coord.r}
		_hex_coord_by_id[combatant.combatant_id] = combatant.hex_coord

		var readout := CombatantReadoutClass.new()
		add_child(readout)
		readout.position = axial_to_pixel(combatant.hex_coord)
		readout.initialize(view_model_by_id.get(combatant.combatant_id, {
			"combatant_id": combatant.combatant_id,
			"name": combatant.name,
		}))
		_readouts[combatant.combatant_id] = readout

	queue_redraw()


## get_hex_position(combatant_id) → Dictionary — the rendered {"q", "r"} for
## the given combatant, or an empty Dictionary if combatant_id is unknown.
func get_hex_position(combatant_id: String) -> Dictionary:
	return _hex_by_id.get(combatant_id, {})


## get_hex_coord(combatant_id) → HexCoord or null — the actual domain
## HexCoord instance (core/geometry/hex_coord.gd) this widget positioned
## `combatant_id` at, or null if unknown (FEAT-007). Lets a caller (e.g.
## scenes/battlefield/StrikeInputController.gd) reuse this widget's
## already-loaded position data instead of duplicating it.
func get_hex_coord(combatant_id: String):
	return _hex_coord_by_id.get(combatant_id, null)


## set_selectable_combatant_ids(selectable_ids, not_selectable_ids) → void —
## a purely visual affordance (FEAT-007): tints every currently-instantiated
## readout named in `selectable_ids`, dims every readout named in
## `not_selectable_ids`, and resets any other readout to its default tint.
## This widget computes NONE of this itself -- both Arrays are supplied
## verbatim by the caller (e.g. StrikeInputController, which alone decides
## what is in-range for the current actor); HexBattlefield only reflects
## that decision visually (ADR-001: read-and-render only).
func set_selectable_combatant_ids(selectable_ids: Array, not_selectable_ids: Array = []) -> void:
	_selectable_ids.clear()
	_not_selectable_ids.clear()
	for id in selectable_ids:
		_selectable_ids[id] = true
	for id in not_selectable_ids:
		_not_selectable_ids[id] = true
	_refresh_selection_tints()


## is_selectable(combatant_id) → bool — true iff `combatant_id` was named in
## the most recent set_selectable_combatant_ids() call's `selectable_ids`.
func is_selectable(combatant_id: String) -> bool:
	return _selectable_ids.has(combatant_id)


## is_marked_not_selectable(combatant_id) → bool — true iff `combatant_id`
## was named in the most recent set_selectable_combatant_ids() call's
## `not_selectable_ids`.
func is_marked_not_selectable(combatant_id: String) -> bool:
	return _not_selectable_ids.has(combatant_id)


func _refresh_selection_tints() -> void:
	for id in _readouts.keys():
		var readout = _readouts[id]
		if _selectable_ids.has(id):
			readout.modulate = _SELECTABLE_TINT
		elif _not_selectable_ids.has(id):
			readout.modulate = _NOT_SELECTABLE_TINT
		else:
			readout.modulate = _DEFAULT_TINT


## get_readout(combatant_id) → CombatantReadout or null — test/inspection helper.
func get_readout(combatant_id: String):
	return _readouts.get(combatant_id, null)


## get_combatant_count() → int — number of currently instantiated readouts.
func get_combatant_count() -> int:
	return _readouts.size()


## on_round_event(event) → void — forwards `event`, unmodified, to every
## instantiated CombatantReadout (ADR-003). Each readout independently
## decides whether the event names it; HexBattlefield performs no
## event-field inspection or combat computation of its own.
func on_round_event(event) -> void:
	for readout in _readouts.values():
		readout.on_round_event(event)


## move_token(combatant_id, new_hex_coord) → void — FEAT-138 / DEF-006:
## repositions the already-instantiated CombatantReadout for `combatant_id`
## to `new_hex_coord`'s mapped screen position (axial_to_pixel()), mirroring
## presentation/hex_grid_view.gd's move_token() (the SAME method name/
## signature -- so both renderers offer an identical, duck-typed contract
## and a caller such as presentation/movement_input_controller.gd, which
## only ever calls `<collaborator>.move_token(actor_id, destination_hex)` on
## whichever renderer it was configured with, can resync EITHER renderer, or
## both, after a Step or a Stride, without HexBattlefield needing its own
## bespoke resync API).
##
## Also refreshes `_hex_by_id`/`_hex_coord_by_id` so get_hex_position()/
## get_hex_coord() immediately reflect the new position too -- otherwise
## those two accessors would keep returning the STALE hex seeded by
## load_combatants() forever, which is exactly DEF-006's defect (HexBattlefield
## never repositioned its combatants after a Step/Stride, so it could disagree
## with presentation/hex_grid_view.gd about a combatant's current hex).
##
## A no-op when no readout is on record for `combatant_id` (e.g.
## load_combatants() was never called, or the id is unknown) -- this widget
## never crashes on a stale/unknown id, matching HexGridView's move_token()
## contract exactly.
##
## Also a no-op -- logging a push_warning() first -- when `new_hex_coord`
## falls outside GRID_RADIUS (FEAT-157/FIND-150): a latent domain bug
## upstream (e.g. movement.gd producing an out-of-grid HexPosition) must
## never silently reposition this combatant's CombatantReadout off-screen;
## the readout instead stays put at its last known-good position.
func move_token(combatant_id: String, new_hex_coord) -> void:
	# Defensive guard (mirrors the combatant_id no-op below): a null or
	# malformed coord (missing q/r) is a no-op rather than a crash, so a stray
	# call from a resync path can never throw (FEAT-138).
	if new_hex_coord == null or not ("q" in new_hex_coord) or not ("r" in new_hex_coord):
		return
	var readout = _readouts.get(combatant_id, null)
	if readout == null:
		return

	if not _is_within_grid_radius(new_hex_coord):
		push_warning(
			"HexBattlefield.move_token: combatant '%s' hex_coord (q=%d, r=%d) is outside GRID_RADIUS=%d -- skipping reposition to avoid silently rendering it off-screen (FEAT-157/FIND-150)"
			% [combatant_id, new_hex_coord.q, new_hex_coord.r, GRID_RADIUS]
		)
		return

	_hex_by_id[combatant_id] = {"q": new_hex_coord.q, "r": new_hex_coord.r}
	_hex_coord_by_id[combatant_id] = new_hex_coord
	readout.position = axial_to_pixel(new_hex_coord)
	queue_redraw()


## _turn_order_widget — this widget's nested TurnOrderWidget child
## (scenes/battlefield/TurnOrderWidget.gd, FEAT-006), instanced as
## "TurnOrderWidget" in HexBattlefield.tscn. Resolved defensively
## (get_node_or_null) so a HexBattlefield instantiated without that scene
## structure (e.g. a bare .new(), never used in practice by this codebase's
## own tests/composition root, both of which always go through
## HexBattlefield.tscn) never errors -- it simply has no turn-order widget to
## expose.
@onready var _turn_order_widget = get_node_or_null("TurnOrderWidget")


## get_turn_order_widget() → TurnOrderWidget or null — exposes this widget's
## nested TurnOrderWidget child (FEAT-008) so a caller (e.g. the composition
## root, MainScene.gd) can obtain it through HexBattlefield's own API instead
## of a hardcoded `$HexBattlefield/TurnOrderWidget` node-path lookup --
## reusing this widget's already-instanced child rather than requiring a
## second, independently-resolved reference to the same node.
func get_turn_order_widget():
	return _turn_order_widget
