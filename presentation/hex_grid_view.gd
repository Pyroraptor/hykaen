## presentation/hex_grid_view.gd — HexGridView (FEAT-007 / US-005 / ADR-004;
## coordinate-transform extraction: FEAT-001 / US-001 / FR-011 / ADR-003)
##
## Presentation layer (Clean Architecture): renders the flat-top hex
## battlefield. The ADR-004 axial<->pixel translation formula itself lives in
## presentation/infrastructure/coordinate_transform.gd (Infrastructure) — NOT
## here and NOT in Domain (ADR-001: mapping a domain HexCoord to a
## screen-space Vector2 is a rendering concern, not a combat rule, so
## core/geometry/hex_math.gd stays free of any pixel/Vector2 concept).
## HexGridView depends only on the read-only domain HexCoord value object
## (core/geometry/hex_coord.gd) and never mutates domain state.
##
## Responsibilities:
##   1. Render the flat-top hex-cell grid (_draw()), covering GRID_RADIUS
##      concentric rings around the origin.
##   2. load_combatants(combatants) instantiates one CombatantTokenView
##      (presentation/combatant_token_view.gd) per combatant supplied,
##      satisfying US-005's "sees the hex battlefield with all combatants"
##      criterion. Each `combatant` is duck-typed: any object exposing
##      combatant_id/name/team/hex_coord fields (i.e. a
##      core/domain/combatant.gd Combatant instance, as returned by
##      infrastructure/resource_encounter_repository.gd).
##
## FEAT-001 (US-001 / FR-011 / ADR-003): token drawing (delegated to
## CombatantTokenView.reposition(), which itself now consumes
## CoordinateTransform directly), click-to-hex mapping (_unhandled_input()),
## and highlight rendering (_draw_hex_cell(), which computes ONE `center` per
## hex and reuses it for both the grid outline and the highlight fill) all
## resolve through the SAME presentation/infrastructure/coordinate_transform.gd
## CoordinateTransform.axial_to_pixel()/pixel_to_axial() calls — eliminating
## the Iteration D class of bug where each consumer independently recomputed
## the transform and could drift out of sync (a click on a visibly
## highlighted hex resolving to the wrong axial coordinate).
## axial_to_pixel()/pixel_to_axial() remain as `static func`s (with an
## implicit zero offset) purely for backward-compatible callers that predate
## the offset concept (e.g. tests/unit/presentation/test_hex_grid_view_mapping.gd);
## they too delegate to CoordinateTransform rather than reimplementing the
## formula, so there is exactly ONE place the flat-top axial<->pixel formula
## is implemented anywhere in Presentation.
##
## FEAT-002 (US-003 / iteration-W "Camera Panning & Collapsible Panels", W0-0):
## with a GameCamera Camera2D (FEAT-001) now the canonical view controller,
## `_origin_offset` no longer participates in ANY draw-call math -- tile/ring
## drawing (_draw_hex_cell()), path-overlay drawing (_draw_path_overlay()),
## and token positioning (load_combatants()/add_combatants()/move_token()/
## animate_token_to(), all now calling the zero-offset axial_to_pixel()
## rather than axial_to_pixel_with_offset()) all draw in PURE WORLD
## coordinates: hex (0, 0) always draws at world pixel (0, 0), regardless of
## `_origin_offset`. The camera (not this view) now owns the pan/view
## transform. `_origin_offset` itself is RETAINED as a field (back-compat;
## see set_origin_offset()/get_origin_offset()) and still drives
## axial_to_pixel_with_offset()/pixel_to_axial_with_offset() — used today
## only by click-to-hex hit-testing (_unhandled_input()/_handle_mouse_motion()),
## which a follow-on story (iteration-W W0-0's "hit-test refactor to
## get_global_mouse_position()") will migrate to a Camera2D-aware lookup.

class_name HexGridView
extends Node2D

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const CombatantTokenViewScene: PackedScene = preload("res://presentation/combatant_token_view.tscn")
const CoordinateTransformClass = preload("res://presentation/infrastructure/coordinate_transform.gd")

## Pixel radius of one hex cell (center to corner), flat-top orientation.
const HEX_SIZE: float = 48.0

## Number of concentric rings of hex cells drawn around the origin for the
## background battlefield grid — a fixed, generous bound; the prologue
## encounter's authored positions all fall well within it.
##
## FEAT-331 (resolves DEPLOY-BLOCKER-002): widened from 5 to 12 so
## larger, terrain-authored encounters (see TERRAIN_FILL_COLORS /
## set_tile_terrain() below) have room to render without hitting the grid
## edge. is_hex_in_grid_bounds() below is the single test/inspection hook
## exposing this boundary condition (a hex at cube-distance GRID_RADIUS is
## in-bounds; GRID_RADIUS + 1 is rejected) without depending on a real
## _draw() dispatch.
const GRID_RADIUS: int = 12

const GRID_LINE_COLOR: Color = Color(0.35, 0.35, 0.4, 1.0)

## FEAT-331 (resolves DEPLOY-BLOCKER-002): terrain_type (String, matching
## data/tiles/hex_tile_data_resource.gd's `terrain_type` field convention,
## e.g. "floor"/"water"/"wall") -> fill Color, the single lookup table
## _draw_hex_cell() consults for a hex's terrain fill (via
## get_tile_fill_color(), see set_tile_terrain() below). Mirrors the
## naming/color convention already established by tools/map_editor_scene.gd's
## `_TERRAIN_COLORS` (this view intentionally does not import that tool
## script — Presentation stays independent of the authoring tool — but
## reuses the same String-keyed Dictionary(String -> Color) shape and the
## same terrain vocabulary so an authored .tres's terrain_type values
## resolve to a consistent color both in the editor tool and here at
## runtime).
const TERRAIN_FILL_COLORS: Dictionary = {
	"floor":         Color(0.82, 0.82, 0.82, 0.85),
	"rubble":        Color(0.65, 0.55, 0.40, 0.88),
	"wall":          Color(0.28, 0.26, 0.26, 0.92),
	"pit":           Color(0.10, 0.08, 0.08, 0.96),
	"grass":         Color(0.35, 0.62, 0.25, 0.85),
	"stone":         Color(0.60, 0.58, 0.54, 0.85),
	"sand":          Color(0.85, 0.78, 0.52, 0.85),
	"forest":        Color(0.15, 0.42, 0.15, 0.90),
	"undergrowth":   Color(0.32, 0.55, 0.22, 0.85),
	"mud":           Color(0.45, 0.33, 0.18, 0.88),
	"shallow_water": Color(0.48, 0.72, 0.90, 0.82),
	"deep_water":    Color(0.10, 0.22, 0.65, 0.92),
	"water":         Color(0.25, 0.55, 0.85, 0.88),
	"lava":          Color(0.95, 0.35, 0.05, 0.90),
	"ice":           Color(0.80, 0.92, 0.98, 0.88),
}

## FEAT-331: fill color resolved for a hex with no assigned terrain type
## (get_tile_terrain() returns "" — set_tile_terrain() was never called for
## it) or an unrecognized terrain_type string not present in
## TERRAIN_FILL_COLORS. Fully transparent so _draw_hex_cell() draws no
## terrain fill at all for such a hex (matching this view's pre-FEAT-331
## rendering exactly — an untouched hex renders as just its grid outline,
## same as before this feature existed).
const NO_TERRAIN_FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.0)

## FEAT-013 / US-013: fill color for hexes currently reported as selectable
## Step destinations (via set_selectable_hexes()) -- a purely visual
## affordance, never a source of movement-rule truth (core/rules/movement.gd
## remains that source; this view only reads/derives from it, ADR-001).
const SELECTABLE_HEX_FILL_COLOR: Color = Color(0.35, 0.75, 0.35, 0.35)

## combatant_id (String) -> CombatantTokenView, populated by load_combatants().
var _tokens: Dictionary = {}

## FEAT-001 (US-001 / FR-011 / ADR-003) / FEAT-002 (US-003, iteration-W
## W0-0): the screen-space origin offset — see set_origin_offset().
## Defaults to Vector2.ZERO.
##
## FEAT-002: as of iteration-W's W0-0 (GameCamera Camera2D now the canonical
## view controller), this field is RETAINED purely for API back-compat and
## for click-to-hex hit-testing (axial_to_pixel_with_offset()/
## pixel_to_axial_with_offset(), consumed by _unhandled_input()/
## _handle_mouse_motion()) — it NO LONGER participates in any draw-call math
## (tile/ring drawing, path-overlay drawing, or token positioning all draw
## in pure world coordinates now; see this file's file-level FEAT-002 doc).
var _origin_offset: Vector2 = Vector2.ZERO

## FEAT-003 (US-004 / FR-004, ADR-001, Contract 1): typed reference to the
## sibling GameCamera Camera2D node (added under the SAME parent/"world
## layer" as this view by FEAT-001; see MainScene.tscn) that now drives the
## view/pan transform. Resolved lazily via `@onready` from `../GameCamera`
## relative to this view's own parent -- i.e. a NODE SIBLING, never a child
## of this view (per this iteration's design notes: "GameCamera is a sibling
## node, not a child, of HexGridView"). `get_node_or_null()` (never a plain
## `get_node()`) so this stays `null` -- rather than throwing -- whenever
## HexGridView is instantiated standalone (e.g. this view's own .tscn in
## isolation, as most of this file's unit tests do) or before GameCamera has
## otherwise resolved into the scene tree; set_origin_offset() below guards
## on this being non-null before touching it (Contract 1's "graceful
## degradation", not a crash).
@onready var _camera: Camera2D = get_node_or_null("../GameCamera")

## FEAT-013 / US-013: the hexes currently highlighted as legal Step
## destinations (an Array of core/geometry/hex_coord.gd HexCoord instances),
## set via set_selectable_hexes() -- normally handed in verbatim from
## presentation/movement_input_controller.gd's
## Movement.get_step_destinations()-derived selectable set.
var _selectable_hexes: Array = []

## FEAT-331 (resolves DEPLOY-BLOCKER-002): "q,r" String key (see
## _tile_terrain_key()) -> terrain_type String, populated by
## set_tile_terrain(). A HexCoord itself is not used directly as the
## Dictionary key -- two distinct HexCoord instances with the same (q, r)
## are not `==` to each other (RefCounted identity, no operator overload),
## so a String key derived from the coordinate value is what actually
## gives value-equality lookup semantics here (mirrors the value-equality
## HexCoord.equals() already provides for the Array-based
## _selectable_hexes above, just Dictionary-keyed instead of scanned).
var _tile_terrain: Dictionary = {}

## FEAT-005 / US-005: the exploration path currently overlaid on the grid
## (an Array of core/geometry/hex_coord.gd HexCoord instances, in walk
## order), set via set_path_overlay() and rendered in _draw() as a 3px line
## between the pixel centers of every consecutive pair. Empty by default —
## nothing is drawn until a caller (e.g. presentation/
## exploration_mode_controller.gd) supplies a path via set_path_overlay().
var _path_overlay: Array = []

## FEAT-005 / US-005: the color the currently-stored `_path_overlay` is
## drawn with. Defaults to white purely so an (unlikely) accidental draw
## before set_path_overlay() is ever called renders visibly rather than
## invisibly transparent; set_path_overlay() always overwrites this before
## any real overlay is drawn.
var _path_overlay_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Line width (px) the path overlay is drawn with (US-005/FR-005: "a 3px
## line between consecutive hex pixel centers").
const PATH_OVERLAY_WIDTH: float = 3.0

## hex_clicked(hex_coord) -- FEAT-013 / US-013: emitted whenever the player
## left-clicks anywhere on this view, carrying the HexCoord the click maps
## to (pixel_to_axial()). This view performs NO movement-rule validation of
## its own -- it is the caller's (e.g. MainScene.gd's, forwarding to a
## configured presentation/movement_input_controller.gd) responsibility to
## decide whether the clicked hex is actually a legal Step destination.
signal hex_clicked(hex_coord)

## hex_hovered(hex_coord) -- FEAT-007 (US-007 / FR-009): mirrors hex_clicked's
## contract/shape (a single HexCoord parameter, no movement-rule validation
## of its own -- ADR-001), but fires on mouse MOTION rather than a click, and
## ONLY when the hovered hex actually changes (see _last_hovered_hex below)
## -- never once per motion-event/frame, so a caller wiring this straight
## into a per-hover pathfinding call (e.g. presentation/
## exploration_mode_controller.gd's ExplorationModeController) never
## recomputes a path redundantly while the mouse sits still within the same
## hex.
##
## `hex_coord` is `null` exactly once per hover-then-leave gesture -- the
## "mouse left this view" case (this view's NOTIFICATION_WM_MOUSE_EXIT
## handler, see _notification() below, and the directly-callable
## notify_mouse_exited() test/inspection hook) -- so a consumer can treat a
## single signal as BOTH "hovering this hex" (non-null) and "no longer
## hovering anything" (null) without a second, separate signal.
signal hex_hovered(hex_coord)

## token_move_failed(combatant_id) -- FEAT-226 / US-005 (resolves FIND-222):
## emitted by move_token() whenever `combatant_id` has no on-screen token on
## record (e.g. load_combatants() was never called, or the id is unknown/
## stale). A purely observational signal for callers/tests that watch signals
## rather than (or in addition to) checking move_token()'s own bool return
## value -- see move_token()'s own doc for the full TOKEN_NOT_FOUND contract.
signal token_move_failed(combatant_id)

## FEAT-007 (US-007 / FR-009): the HexCoord most recently emitted via
## hex_hovered (null when no hex is currently considered "hovered", i.e.
## before the first motion event or after a mouse-leave). Used purely to
## de-duplicate hex_hovered emissions ("on every hover-target CHANGE", not
## on every motion event/frame) -- never read by any caller.
var _last_hovered_hex = null


func _draw() -> void:
	for q in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var coord = HexCoordClass.new(q, r)
			if is_hex_in_grid_bounds(coord):
				_draw_hex_cell(coord)
	_draw_path_overlay()


## _draw_path_overlay() → void — FEAT-005 / US-005: draws a
## PATH_OVERLAY_WIDTH-px line between the pixel centers of every consecutive
## pair of hexes in `_path_overlay`, in `_path_overlay_color`. Safe (draws
## nothing, never crashes) when `_path_overlay` is empty or holds a single
## hex — there is no "consecutive pair" to draw a segment for in either case.
## FEAT-002 (US-003 / iteration-W W0-0): draws in PURE world coordinates --
## no `_origin_offset` participates in this computation. With the GameCamera
## Camera2D (FEAT-001) now the canonical view controller, the view transform
## (pan) is the camera's job, not this view's draw math -- hex (0,0) always
## draws at world pixel (0,0), regardless of `_origin_offset`.
func _draw_path_overlay() -> void:
	if _path_overlay.size() < 2:
		return
	for i in range(_path_overlay.size() - 1):
		var from_center: Vector2 = axial_to_pixel(_path_overlay[i])
		var to_center: Vector2 = axial_to_pixel(_path_overlay[i + 1])
		draw_line(from_center, to_center, _path_overlay_color, PATH_OVERLAY_WIDTH)


## FEAT-002 (US-003 / iteration-W W0-0): draws in PURE world coordinates --
## see _draw_path_overlay()'s doc immediately above for why `_origin_offset`
## no longer participates here (the GameCamera Camera2D now owns the view
## transform).
func _draw_hex_cell(coord) -> void:
	# FEAT-001: ONE center Vector2, reused for BOTH the grid outline AND
	# (when selectable/terrain-painted) the highlight/fill below --
	# highlight/terrain rendering has no separate transform of its own to
	# drift out of sync. FEAT-002: this is now a pure world-space center --
	# no screen-space draw-origin shift is applied here; the camera handles
	# panning.
	var center: Vector2 = axial_to_pixel(coord)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		points.append(center + _hex_corner_offset(HEX_SIZE, i % 6))
	# FEAT-331 (resolves DEPLOY-BLOCKER-002): draw the terrain fill (if any)
	# FIRST, so the FEAT-013 selectable-hex highlight below still layers
	# visibly on top of it -- terrain is the "background" a Step-
	# destination highlight overlays, never the other way around.
	var terrain_fill_color: Color = get_tile_fill_color(coord)
	if terrain_fill_color.a > 0.0:
		draw_colored_polygon(points, terrain_fill_color)
	if _is_selectable_hex(coord):
		draw_colored_polygon(points, SELECTABLE_HEX_FILL_COLOR)
	draw_polyline(points, GRID_LINE_COLOR, 1.0)


func _is_selectable_hex(coord) -> bool:
	for hex_coord in _selectable_hexes:
		if hex_coord.equals(coord):
			return true
	return false


## _unhandled_input(event) -> void -- FEAT-013 / US-013: translates a
## left-click anywhere on this view into hex_clicked(hex_coord), via
## pixel_to_axial(). Purely an input-translation concern (ADR-001: no
## movement rule is evaluated here).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hex_clicked.emit(pixel_to_axial_with_offset(get_local_mouse_position()))
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


## _handle_mouse_motion(event) -> void -- FEAT-007 (US-007 / FR-009): decodes
## the CURRENT mouse position into a HexCoord (pixel_to_axial_with_offset()
## applied to get_local_mouse_position() -- the SAME offset-aware transform
## + local-position convention _unhandled_input()'s click handling already
## uses above, so a hover and a click over the same on-screen point always
## resolve to the same hex) and delegates the "did the hovered hex actually
## change" decision to _report_hovered_hex() below.
func _handle_mouse_motion(_event: InputEventMouseMotion) -> void:
	_report_hovered_hex(pixel_to_axial_with_offset(get_local_mouse_position()))


## _report_hovered_hex(hovered_hex) -> void -- FEAT-007 (US-007 / FR-009):
## emits hex_hovered(hovered_hex) ONLY when `hovered_hex` differs from
## `_last_hovered_hex` -- de-duplicating so a caller wiring hex_hovered
## straight into a per-hover pathfinding call never recomputes on every
## motion event/frame while the mouse sits still within the same hex.
## Factored out from _handle_mouse_motion() specifically so this
## de-duplication rule is directly unit-testable against an explicit
## HexCoord, without depending on this view's real (headless-unreliable)
## get_local_mouse_position() -- mirrors this codebase's established
## "call the handler directly" test convention (e.g. tests/boot/
## test_exploration_click_to_move.gd calling `_on_exploration_hex_clicked()`
## directly rather than simulating a real OS click).
func _report_hovered_hex(hovered_hex) -> void:
	if _last_hovered_hex != null and hovered_hex.equals(_last_hovered_hex):
		return
	_last_hovered_hex = hovered_hex
	hex_hovered.emit(hovered_hex)


## _notification(what) -> void -- FEAT-007 (US-007 / FR-009): on
## NOTIFICATION_WM_MOUSE_EXIT (the mouse leaving the game window), emits
## hex_hovered(null) -- see hex_hovered's own doc for why `null` is this
## signal's "no longer hovering anything" case -- and resets
## `_last_hovered_hex` so the very next motion event (even one that maps
## back to the same hex the mouse was over before it left) is treated as a
## genuine hover-target change and re-emitted. Delegates to
## notify_mouse_exited() so both the real engine notification AND a direct,
## test/inspection-friendly call site share exactly one implementation
## (ADR-006, no duplicated seam).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		notify_mouse_exited()


## notify_mouse_exited() -> void -- FEAT-007 (US-007 / FR-009): the
## directly-callable counterpart to _notification()'s
## NOTIFICATION_WM_MOUSE_EXIT handling (ADR-006 shared-callable pattern) --
## always safe to call, idempotent (a second call with no intervening
## hover is a harmless re-emission of hex_hovered(null)).
func notify_mouse_exited() -> void:
	_last_hovered_hex = null
	hex_hovered.emit(null)


## _hex_corner_offset(size, corner_index) → Vector2 — the offset of one of
## the 6 corners of a flat-top hexagon of the given size, relative to its
## center. Flat-top corners sit at 0°, 60°, 120°, ... (no angular offset,
## unlike pointy-top's -30° offset).
static func _hex_corner_offset(size: float, corner_index: int) -> Vector2:
	var angle_rad: float = deg_to_rad(60.0 * corner_index)
	return Vector2(size * cos(angle_rad), size * sin(angle_rad))


## axial_to_pixel(hex_coord, hex_size) → Vector2 — ADR-004 flat-top axial
## coordinate to screen-pixel translation, delegated to
## presentation/infrastructure/coordinate_transform.gd (FEAT-001) with an
## implicit zero origin offset. Kept as a `static func` for
## backward-compatible callers that predate the offset concept (e.g.
## CombatantTokenView's default-offset path, existing tests); instance
## callers that must honor this view's configured `_origin_offset` (drawing,
## click mapping, highlight rendering) use axial_to_pixel_with_offset()
## instead. `hex_coord` is duck-typed: any object exposing integer q/r
## fields (i.e. a core/geometry/hex_coord.gd HexCoord instance).
static func axial_to_pixel(hex_coord, hex_size: float = HEX_SIZE) -> Vector2:
	return CoordinateTransformClass.axial_to_pixel(hex_coord, hex_size, Vector2.ZERO)


## pixel_to_axial(pixel, hex_size) → HexCoord — FEAT-013 / US-013: the
## inverse of axial_to_pixel(), delegated to CoordinateTransform (FEAT-001)
## with an implicit zero origin offset. See axial_to_pixel()'s doc for why
## this remains a `static func` alongside the offset-aware
## pixel_to_axial_with_offset() instance method.
static func pixel_to_axial(pixel: Vector2, hex_size: float = HEX_SIZE):
	return CoordinateTransformClass.pixel_to_axial(pixel, hex_size, Vector2.ZERO)


## set_origin_offset(offset) → void — FEAT-001 (US-001 / FR-011 / ADR-003):
## configures `_origin_offset`. Defaults to Vector2.ZERO.
##
## FEAT-002 (US-003, iteration-W W0-0): as of the GameCamera Camera2D
## refactor, this offset is consumed ONLY by click mapping
## (pixel_to_axial_with_offset(), used by _unhandled_input()/
## _handle_mouse_motion()) — it no longer affects grid/highlight drawing or
## token positioning, which now draw in pure world coordinates (see this
## file's file-level FEAT-002 doc).
##
## FEAT-003 (US-004 / FR-004, ADR-001, Contract 1): re-implemented to drive
## the sibling GameCamera (see `_camera` above) instead of a draw-offset --
## `_camera.position` is set to `-offset` whenever `_camera` has resolved,
## so panning is now genuinely the camera's job (positive `offset` still
## means "shift the rendered world so that world-point now appears at the
## viewport's origin," matching this method's pre-existing contract, only
## realized via the camera's inverse position rather than a per-draw-call
## subtraction). `_origin_offset` itself is STILL updated unconditionally,
## every call, preserving this method's public back-compat contract (every
## pre-existing caller reading it back via get_origin_offset(), or relying on
## it for click-to-hex hit-testing via axial_to_pixel_with_offset()/
## pixel_to_axial_with_offset(), continues to see exactly the same value it
## always has). When `_camera` is still `null` (e.g. this view instantiated
## standalone, ahead of `_ready()`, or in a scene with no GameCamera sibling)
## this method does NOT throw -- it silently degrades to updating
## `_origin_offset` only, per Contract 1's documented graceful-degradation
## behaviour, to be reconciled once `_camera` itself resolves. Still triggers
## a redraw so any state `_origin_offset` continues to drive (click mapping)
## reflects the change immediately.
func set_origin_offset(offset: Vector2) -> void:
	_origin_offset = offset
	if _camera != null:
		_camera.position = -offset
	queue_redraw()


## get_origin_offset() → Vector2 — the origin offset most recently configured
## via set_origin_offset() (Vector2.ZERO if never called).
func get_origin_offset() -> Vector2:
	return _origin_offset


## axial_to_pixel_with_offset(hex_coord) → Vector2 — axial_to_pixel(), using
## THIS view's currently configured `_origin_offset` (FEAT-001). The single
## call site both _draw_hex_cell() (grid + highlight rendering) and
## CombatantTokenView (token drawing, via the offset this view passes it)
## are ultimately derived from.
func axial_to_pixel_with_offset(hex_coord) -> Vector2:
	return CoordinateTransformClass.axial_to_pixel(hex_coord, HEX_SIZE, _origin_offset)


## pixel_to_axial_with_offset(pixel) → HexCoord — pixel_to_axial(), using
## THIS view's currently configured `_origin_offset` (FEAT-001). Used by
## _unhandled_input() so a click is always decoded with the SAME offset the
## grid/highlights/tokens were drawn with.
func pixel_to_axial_with_offset(pixel: Vector2):
	return CoordinateTransformClass.pixel_to_axial(pixel, HEX_SIZE, _origin_offset)


## set_selectable_hexes(hexes) → void — FEAT-013 / US-013: highlights the
## given Array of HexCoords (normally handed in verbatim from
## presentation/movement_input_controller.gd's currently-legal Step
## destinations) on the next _draw(). A purely visual affordance — this view
## never decides which hexes ARE legal Step destinations, it only renders
## whichever set it is told about (ADR-001).
##
## FEAT-242 / US-011: this SAME entry point is also the sole highlight path
## presentation/selection_overlay.gd reuses for an AREA_SET verb's
## origin-hex candidates AND its computed affected-hex-set preview (via
## core/application/selection_resolution_use_case.gd's affected_set(),
## itself a pure consumer of core/geometry) — no separate/forked
## AREA-highlight rendering exists here or anywhere else. Whether `hexes`
## is a handful of Step destinations or a whole AREA_SET-computed blast
## radius, this view treats it identically: it only renders whichever set
## it is told about.
func set_selectable_hexes(hexes: Array) -> void:
	_selectable_hexes = hexes
	queue_redraw()


## set_path_overlay(path, color) → void — FEAT-005 / US-005 (FR-005): stores
## `path` (an Array of HexCoord, in walk order) and `color` as this view's
## current path overlay and queues a redraw, so _draw() renders a
## PATH_OVERLAY_WIDTH-px line between every consecutive pair of hexes' pixel
## centers (via axial_to_pixel_with_offset(), honoring this view's currently
## configured origin offset -- ADR-003, matching every other drawing path on
## this view). Always succeeds -- no error path (API contract #6): an empty
## `path` or a single-hex `path` is stored exactly as given and simply draws
## nothing (there is no consecutive pair to draw a segment for), never a
## crash. Normally called by presentation/exploration_mode_controller.gd
## with a HexPathfinder.find_path() result ahead of animating a party token
## along it.
func set_path_overlay(path: Array, color: Color) -> void:
	_path_overlay = path
	_path_overlay_color = color
	queue_redraw()


## clear_overlays() → void — FEAT-005 / US-005: resets the stored path
## overlay to empty (so a subsequent _draw() renders no path-overlay
## segment) and queues a redraw. Idempotent/safe to call even when no
## overlay was ever set (API contract #6: always succeeds, no error path).
## Normally called by presentation/exploration_mode_controller.gd once,
## before starting a new navigate_party_member() walk, so a stale overlay
## from a prior click never lingers alongside (or after) the new one.
func clear_overlays() -> void:
	_path_overlay = []
	queue_redraw()


## get_path_overlay() → Array — test/inspection helper: the HexCoord path
## most recently supplied to set_path_overlay() (empty if never called, or
## after clear_overlays()).
func get_path_overlay() -> Array:
	return _path_overlay


## get_path_overlay_color() → Color — test/inspection helper: the color most
## recently supplied to set_path_overlay() (Color(1,1,1,1) if never called).
func get_path_overlay_color() -> Color:
	return _path_overlay_color


## is_hex_in_grid_bounds(hex_coord) → bool — FEAT-331 (resolves
## DEPLOY-BLOCKER-002): true when `hex_coord`'s cube-coordinate distance
## from the origin (0, 0) is within GRID_RADIUS — the SAME bound _draw()
## uses to decide which hex cells to render (the loop above delegates to
## THIS method rather than re-deriving the check, so there is exactly one
## place the boundary condition is expressed). Exposed as a public
## test/inspection hook so the GRID_RADIUS boundary (cube-distance
## GRID_RADIUS is in-bounds/renderable, GRID_RADIUS + 1 is rejected) is
## directly unit-testable without depending on a real _draw() dispatch.
## `hex_coord` is duck-typed: any object exposing integer q/r fields and a
## get_s() method (i.e. a core/geometry/hex_coord.gd HexCoord instance).
func is_hex_in_grid_bounds(hex_coord) -> bool:
	return (
		absi(hex_coord.q) <= GRID_RADIUS
		and absi(hex_coord.r) <= GRID_RADIUS
		and absi(hex_coord.get_s()) <= GRID_RADIUS
	)


## _tile_terrain_key(hex_coord) → String — the "q,r" String key
## _tile_terrain is keyed by (see _tile_terrain's own doc for why a String
## key, rather than the HexCoord object itself, is used).
static func _tile_terrain_key(hex_coord) -> String:
	return "%d,%d" % [hex_coord.q, hex_coord.r]


## set_tile_terrain(hex_coord, terrain_type) → void — FEAT-331 (resolves
## DEPLOY-BLOCKER-002): assigns `terrain_type` (a String, matching
## data/tiles/hex_tile_data_resource.gd's `terrain_type` field convention)
## to `hex_coord` and queues a redraw, so _draw_hex_cell() renders that
## hex filled with TERRAIN_FILL_COLORS[terrain_type] (or
## NO_TERRAIN_FILL_COLOR — no fill drawn — for a terrain_type not present
## in TERRAIN_FILL_COLORS). A second call for the same hex_coord overwrites
## (never appends to) the previously assigned terrain type. Always
## succeeds — no error path, matching this view's established
## set_path_overlay()/set_selectable_hexes() convention (ADR-001: this
## view never validates gameplay-rule terrain data, it only renders
## whichever terrain type it is told about).
func set_tile_terrain(hex_coord, terrain_type: String) -> void:
	_tile_terrain[_tile_terrain_key(hex_coord)] = terrain_type
	queue_redraw()


## get_tile_terrain(hex_coord) → String — test/inspection helper: the
## terrain_type String most recently supplied to set_tile_terrain() for
## `hex_coord` ("" — no defined terrain type maps to an empty string here —
## if set_tile_terrain() was never called for that hex).
func get_tile_terrain(hex_coord) -> String:
	return _tile_terrain.get(_tile_terrain_key(hex_coord), "")


## get_tile_fill_color(hex_coord) → Color — the fill Color _draw_hex_cell()
## resolves for `hex_coord`: TERRAIN_FILL_COLORS[get_tile_terrain(hex_coord)]
## when that terrain type is a recognized TERRAIN_FILL_COLORS key,
## NO_TERRAIN_FILL_COLOR (fully transparent — no fill drawn) otherwise
## (no terrain assigned, or an assigned terrain_type not present in
## TERRAIN_FILL_COLORS). The single source of truth both _draw_hex_cell()
## and this feature's tests read from, so rendering and test assertions
## can never drift out of sync (mirrors get_path_overlay()/
## get_path_overlay_color()'s established "read back exactly what
## _draw() itself reads" convention).
func get_tile_fill_color(hex_coord) -> Color:
	var terrain_type: String = get_tile_terrain(hex_coord)
	return TERRAIN_FILL_COLORS.get(terrain_type, NO_TERRAIN_FILL_COLOR)


## move_token(combatant_id, new_hex_coord) → bool — FEAT-013 / US-013:
## repositions the already-instantiated CombatantTokenView for
## `combatant_id` (via its existing reposition() hook — see
## combatant_token_view.gd's file-level doc, which was built specifically
## for this purpose) to `new_hex_coord`. Still never crashes on a stale/
## unknown id — this view never raises/throws.
##
## FEAT-226 / US-005 (resolves FIND-222): previously a SILENT no-op on an
## unknown `combatant_id`, which let callers (e.g. core/application/
## resolve_dodge_step_use_case.gd) mutate Combatant.hex_coord even though the
## on-screen token never actually moved, desyncing the two with no signal at
## all. Now returns `true` when the token was found and repositioned, `false`
## (TOKEN_NOT_FOUND) when no token is on record for `combatant_id` — and
## additionally emits `token_move_failed(combatant_id)` on that same `false`
## path, so a caller wired only via signal (rather than checking the return
## value) can still observe the failure. ResolveDodgeStepUseCase.resolve()
## checks this return value (see its own FEAT-226 doc) and skips the
## Combatant.hex_coord mutation whenever it is `false`, closing the desync.
## FEAT-002 (US-003 / iteration-W W0-0): repositions in PURE world
## coordinates -- `_origin_offset` is never forwarded to the token (the
## GameCamera Camera2D, not a per-token draw offset, now owns the view
## transform).
func move_token(combatant_id: String, new_hex_coord) -> bool:
	var token = _tokens.get(combatant_id, null)
	if token != null:
		token.reposition(new_hex_coord)
		return true
	token_move_failed.emit(combatant_id)
	return false


## load_combatants(combatants) → void — instantiates one CombatantTokenView
## per entry in `combatants`, positioned at that combatant's hex_coord (via
## CombatantTokenView.set_combatant(), which applies axial_to_pixel()).
## Clears any previously-instantiated tokens first, so a repeated call (e.g.
## a future encounter reload) never leaks duplicate children.
## FEAT-002 (US-003 / iteration-W W0-0): tokens are positioned in PURE world
## coordinates -- `_origin_offset` is never forwarded here (see
## move_token()'s own doc immediately above for why).
func load_combatants(combatants: Array) -> void:
	for existing_token in _tokens.values():
		existing_token.queue_free()
	_tokens.clear()

	for combatant in combatants:
		var token = CombatantTokenViewScene.instantiate()
		add_child(token)
		token.set_combatant(combatant)
		_tokens[combatant.combatant_id] = token


## add_combatants(combatants) → void — FEAT-008 (US-007 / FR-006): places one
## CombatantTokenView per entry in `combatants` WITHOUT clearing any
## previously-instantiated tokens (unlike load_combatants(), which resets the
## whole battlefield first). Used for an incremental token placement such as
## an exploration-to-combat handoff, where party tokens already rendered at
## their exploration positions must be preserved untouched (ADR-001) while
## enemy tokens for the newly-assembled encounter are added alongside them on
## the SAME, unreset grid. If a token already exists for a given
## combatant.combatant_id, it is refreshed/repositioned in place
## (set_combatant()) rather than duplicated — mirrors load_combatants()'s own
## "never leak duplicate children" contract.
## FEAT-002 (US-003 / iteration-W W0-0): tokens are positioned in PURE world
## coordinates -- `_origin_offset` is never forwarded here (see
## move_token()'s own doc for why).
func add_combatants(combatants: Array) -> void:
	for combatant in combatants:
		var existing = _tokens.get(combatant.combatant_id, null)
		if existing != null:
			existing.set_combatant(combatant)
			continue
		var token = CombatantTokenViewScene.instantiate()
		add_child(token)
		token.set_combatant(combatant)
		_tokens[combatant.combatant_id] = token


## remove_combatants(combatant_ids) → void — FEAT-009 (US-008 / FR-007):
## frees and forgets the CombatantTokenView instances for every id in
## `combatant_ids`, WITHOUT touching any other on-screen token (the mirror
## operation to add_combatants(), used by the post-combat
## exploration-return handoff to strip a just-won encounter's enemy tokens
## off the SAME, unreset battlefield the surviving party tokens remain
## rendered on -- ADR-001). Silently skips any id with no on-screen token on
## record (never crashes on a stale/unknown id, matching this view's
## established "never raises/throws" convention -- see move_token()'s own
## doc).
func remove_combatants(combatant_ids: Array) -> void:
	for combatant_id in combatant_ids:
		var token = _tokens.get(combatant_id, null)
		if token != null:
			token.queue_free()
			_tokens.erase(combatant_id)


## TOKEN_MOVE_DURATION -- FEAT-006 (US-006 / FR-011 / NFR-005): the SINGLE
## source of animation duration for animate_token_to()'s tween, in seconds
## per hex step. Every call site (exploration path execution, combat
## movement) drives its tween off THIS constant -- never a second/duplicate
## hardcoded duration literal anywhere else; retune movement animation speed
## by changing this one value.
const TOKEN_MOVE_DURATION: float = 0.12


## animate_token_to(combatant_id, target_hex) → Signal — FEAT-006 (US-006 /
## FR-011, ADR-005, mitigates RISK-002): tweens the already-instantiated
## CombatantTokenView for `combatant_id` from its current pixel position to
## axial_to_pixel_with_offset(target_hex) over TOKEN_MOVE_DURATION seconds.
## Domain-side state is finalized via move_token() ONLY once the tween
## genuinely completes -- never eagerly/synchronously -- so this view's
## authoritative hex-space position (ADR-005) and its transiently-animating
## pixel position can only diverge DURING the tween, never after a caller
## observes completion.
##
## Returns the tween's `finished` Signal so callers (e.g. presentation/
## exploration_mode_controller.gd, per S0-5/S0-9) can `await` genuine
## completion rather than a fixed delay -- this is the RISK-008 test-
## flakiness mitigation: both this method's own tests and its callers assert
## on a real Signal firing, never a sleep/frame-count guess.
##
## Known gap (documented, not hardened this iteration, matching this view's
## existing move_token()/get_token() convention): `combatant_id` with no
## matching on-screen token is an unguarded programmer-error lookup failure,
## not defended against here -- see move_token()'s own doc for the analogous,
## already-accepted precedent.
## FEAT-002 (US-003 / iteration-W W0-0): tweens to a PURE world-space
## target position -- `_origin_offset` no longer participates (see
## move_token()'s own doc for why).
func animate_token_to(combatant_id: String, target_hex) -> Signal:
	var token = _tokens.get(combatant_id, null)
	var target_position: Vector2 = axial_to_pixel(target_hex)
	var tween: Tween = create_tween()
	tween.tween_property(token, "position", target_position, TOKEN_MOVE_DURATION)
	tween.finished.connect(func() -> void: move_token(combatant_id, target_hex))
	return tween.finished


## get_token(combatant_id) → CombatantTokenView or null — test/inspection helper.
func get_token(combatant_id: String):
	return _tokens.get(combatant_id, null)


## get_token_count() → int — number of currently instantiated tokens.
func get_token_count() -> int:
	return _tokens.size()
