## tools/map_editor.gd — @tool hex map / encounter editor
##
## Usage:
##   1. Open tools/MapEditor.tscn in Godot's 2D editor.
##   2. In the Inspector, drag your .tres resource into the relevant slot.
##   3. Select a paint mode, then click / drag in the 2D viewport.
##
##   Left-click  = paint / place / add
##   Right-click = erase / remove
##   Drag        = paint continuously across hexes
##
## Modes:
##   TERRAIN       — writes current_terrain to a HexTileDataResource in tiles[]
##   IMPASSABLE    — left=impassable, right=restore passable
##   DIFFICULT     — left=difficult, right=clear difficult
##   PARTY_POS     — places party_slot index at clicked hex
##   ENEMY_POS     — places enemy_slot index at clicked hex
##   TRIGGER       — adds/removes hex from ProximityTriggerResource.trigger_hexes
##
## Auto-saves: after every painted hex, ResourceSaver writes back each .tres.

@tool
extends Node2D

const CoordTransform = preload("res://presentation/infrastructure/coordinate_transform.gd")

const HEX_SIZE: float = 48.0
const RADIUS: int = 5

enum PaintMode {
	TERRAIN,
	IMPASSABLE,
	DIFFICULT,
	PARTY_POS,
	ENEMY_POS,
	TRIGGER,
}

@export var encounter_resource: EncounterResource:
	set(v):
		encounter_resource = v
		queue_redraw()

@export var trigger_resource: ProximityTriggerResource:
	set(v):
		trigger_resource = v
		queue_redraw()

@export var paint_mode: PaintMode = PaintMode.TERRAIN:
	set(v):
		paint_mode = v
		queue_redraw()

## Terrain string written in TERRAIN mode. Built-ins: floor, rubble, water, wall, pit.
@export var current_terrain: String = "floor":
	set(v):
		current_terrain = v
		queue_redraw()

## Party slot index placed in PARTY_POS mode (0-indexed, parallel to party_resource_paths).
@export var party_slot: int = 0

## Enemy slot index placed in ENEMY_POS mode (0-indexed, parallel to enemy_resource_paths).
@export var enemy_slot: int = 0

# ── Colors ──────────────────────────────────────────────────────────────────
const _TERRAIN_COLORS: Dictionary = {
	"floor":  Color(0.82, 0.82, 0.82, 0.85),
	"rubble": Color(0.65, 0.55, 0.40, 0.88),
	"water":  Color(0.25, 0.55, 0.85, 0.88),
	"wall":   Color(0.28, 0.26, 0.26, 0.92),
	"pit":    Color(0.10, 0.08, 0.08, 0.96),
}
const _EMPTY_COLOR:    Color = Color(0.48, 0.48, 0.52, 0.38)
const _IMPASS_TINT:    Color = Color(0.85, 0.22, 0.18, 0.40)
const _DIFFICULT_TINT: Color = Color(0.88, 0.76, 0.14, 0.38)
const _PARTY_COLOR:    Color = Color(0.22, 0.52, 0.95, 0.92)
const _ENEMY_COLOR:    Color = Color(0.88, 0.22, 0.22, 0.92)
const _TRIGGER_COLOR:  Color = Color(0.92, 0.55, 0.10, 0.38)
const _HOVER_COLOR:    Color = Color(1.00, 1.00, 1.00, 0.22)
const _LINE_COLOR:     Color = Color(0.35, 0.35, 0.40, 1.00)

var _hovered_q: int = 9999
var _hovered_r: int = 9999
# Track last-painted hex so drag doesn't repaint the same hex every frame.
var _last_painted_q: int = 9999
var _last_painted_r: int = 9999


# ── Process (handles hover + paint — bypasses editor event interception) ──────

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	var local_mouse: Vector2 = get_local_mouse_position()
	var hex = CoordTransform.pixel_to_axial(local_mouse)

	# Update hover highlight.
	if hex.q != _hovered_q or hex.r != _hovered_r:
		_hovered_q = hex.q
		_hovered_r = hex.r
		queue_redraw()

	# Only paint within the grid.
	if absi(-hex.q - hex.r) > RADIUS:
		_last_painted_q = 9999
		return

	var left: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# Paint once per hex entry while a button is held (supports drag-paint).
	if (left or right) and (hex.q != _last_painted_q or hex.r != _last_painted_r):
		_paint(hex.q, hex.r, right)
		_last_painted_q = hex.q
		_last_painted_r = hex.r
	elif not left and not right:
		_last_painted_q = 9999  # Reset on button release so same hex can be re-painted.


# ── Draw ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	for q in range(-RADIUS, RADIUS + 1):
		for r in range(-RADIUS, RADIUS + 1):
			if absi(-q - r) <= RADIUS:
				_draw_hex(q, r)
	_draw_legend()


func _draw_hex(q: int, r: int) -> void:
	var center: Vector2 = _center(q, r)
	var poly: PackedVector2Array = _poly(center)

	# Terrain fill.
	draw_colored_polygon(poly, _fill_color(q, r))

	# Hover highlight.
	if q == _hovered_q and r == _hovered_r:
		draw_colored_polygon(poly, _HOVER_COLOR)

	# Passable / difficult tint.
	var tile = _tile(q, r)
	if tile != null:
		if not tile.passable:
			draw_colored_polygon(poly, _IMPASS_TINT)
		elif tile.difficult:
			draw_colored_polygon(poly, _DIFFICULT_TINT)

	# Trigger zone fill.
	if trigger_resource != null:
		if _arr_has(trigger_resource.trigger_hexes, q, r):
			draw_colored_polygon(poly, _TRIGGER_COLOR)

	# Party / enemy position circles.
	if encounter_resource != null:
		var party_pos: Array = encounter_resource.party_hex_positions
		for i in party_pos.size():
			var p = party_pos[i]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, _PARTY_COLOR)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 5),
					"P%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

		var enemy_pos: Array = encounter_resource.enemy_hex_positions
		for i in enemy_pos.size():
			var p = enemy_pos[i]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, _ENEMY_COLOR)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 5),
					"E%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	# Hex coordinate label on hovered hex.
	if q == _hovered_q and r == _hovered_r:
		draw_string(ThemeDB.fallback_font, center + Vector2(-14, -4),
			"(%d,%d)" % [q, r], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0.6, 0.9))

	# Outline.
	var outline: PackedVector2Array = PackedVector2Array()
	for i in range(7):
		var a: float = deg_to_rad(60.0 * (i % 6))
		outline.append(center + Vector2(HEX_SIZE * cos(a), HEX_SIZE * sin(a)))
	draw_polyline(outline, _LINE_COLOR, 1.5)


func _draw_legend() -> void:
	var font = ThemeDB.fallback_font
	var lx: float = RADIUS * HEX_SIZE * 1.5 + HEX_SIZE * 1.6
	var ly: float = -RADIUS * HEX_SIZE * sqrt(3.0) * 0.5

	var labels: Array = ["TERRAIN", "IMPASSABLE", "DIFFICULT", "PARTY_POS", "ENEMY_POS", "TRIGGER"]
	var colors: Array = [
		_TERRAIN_COLORS.get(current_terrain, _EMPTY_COLOR),
		_IMPASS_TINT, _DIFFICULT_TINT, _PARTY_COLOR, _ENEMY_COLOR, _TRIGGER_COLOR,
	]

	for i in labels.size():
		var ry: float = ly + i * 26.0
		draw_rect(Rect2(Vector2(lx, ry), Vector2(18, 18)), colors[i])
		var prefix: String = "▶ " if paint_mode == i else "  "
		draw_string(font, Vector2(lx + 22, ry + 14), prefix + labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var info_y: float = ly + labels.size() * 26.0 + 10.0
	draw_string(font, Vector2(lx, info_y),
		"terrain: " + current_terrain, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.55))
	draw_string(font, Vector2(lx, info_y + 18.0),
		"party slot: %d  enemy slot: %d" % [party_slot, enemy_slot],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
	if _hovered_q != 9999:
		draw_string(font, Vector2(lx, info_y + 36.0),
			"hover: (%d, %d)" % [_hovered_q, _hovered_r],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 0.6))


# ── Paint ─────────────────────────────────────────────────────────────────────

func _paint(q: int, r: int, erase: bool) -> void:
	_ensure_arrays_writable()
	match paint_mode:
		PaintMode.TERRAIN:
			if encounter_resource == null:
				return
			var t = _get_or_create_tile(q, r)
			t.terrain_type = "floor" if erase else current_terrain

		PaintMode.IMPASSABLE:
			if encounter_resource == null:
				return
			var t = _get_or_create_tile(q, r)
			t.passable = erase  # right-click = passable; left-click = impassable

		PaintMode.DIFFICULT:
			if encounter_resource == null:
				return
			var t = _get_or_create_tile(q, r)
			t.difficult = not erase  # right-click = clear; left-click = set

		PaintMode.PARTY_POS:
			if encounter_resource == null:
				return
			if erase:
				_arr_remove(encounter_resource.party_hex_positions, q, r)
			else:
				_arr_place(encounter_resource.party_hex_positions, party_slot, q, r)

		PaintMode.ENEMY_POS:
			if encounter_resource == null:
				return
			if erase:
				_arr_remove(encounter_resource.enemy_hex_positions, q, r)
			else:
				_arr_place(encounter_resource.enemy_hex_positions, enemy_slot, q, r)

		PaintMode.TRIGGER:
			if trigger_resource == null:
				push_warning("MapEditor: assign trigger_resource before painting triggers")
				return
			if erase or _arr_has(trigger_resource.trigger_hexes, q, r):
				_arr_remove(trigger_resource.trigger_hexes, q, r)
			else:
				trigger_resource.trigger_hexes.append({"q": q, "r": r})

	queue_redraw()
	_save()


# ── Resource helpers ──────────────────────────────────────────────────────────

# Godot freezes resource arrays in the editor (undo/redo). Duplicate and
# reassign any read-only arrays before every paint operation.
func _ensure_arrays_writable() -> void:
	if encounter_resource != null:
		if encounter_resource.tiles.is_read_only():
			var t: Array[HexTileDataResource] = []
			t.assign(encounter_resource.tiles)
			encounter_resource.tiles = t
		if encounter_resource.party_hex_positions.is_read_only():
			encounter_resource.party_hex_positions = encounter_resource.party_hex_positions.duplicate()
		if encounter_resource.enemy_hex_positions.is_read_only():
			encounter_resource.enemy_hex_positions = encounter_resource.enemy_hex_positions.duplicate()
	if trigger_resource != null and trigger_resource.trigger_hexes.is_read_only():
		trigger_resource.trigger_hexes = trigger_resource.trigger_hexes.duplicate()


func _tile(q: int, r: int):
	if encounter_resource == null:
		return null
	for t in encounter_resource.tiles:
		if t == null:
			continue
		if t.q == q and t.r == r:
			return t
	return null


func _get_or_create_tile(q: int, r: int):
	var existing = _tile(q, r)
	if existing != null:
		return existing
	var t = HexTileDataResource.new()
	t.q = q
	t.r = r
	encounter_resource.tiles.append(t)
	return t


func _fill_color(q: int, r: int) -> Color:
	var t = _tile(q, r)
	if t == null:
		return _EMPTY_COLOR
	return _TERRAIN_COLORS.get(t.terrain_type, _EMPTY_COLOR)


func _arr_has(arr: Array, q: int, r: int) -> bool:
	for p in arr:
		if p is Dictionary and p.get("q") == q and p.get("r") == r:
			return true
	return false


func _arr_remove(arr: Array, q: int, r: int) -> void:
	for i in arr.size():
		var p = arr[i]
		if p is Dictionary and p.get("q") == q and p.get("r") == r:
			arr.remove_at(i)
			return


func _arr_place(arr: Array, slot: int, q: int, r: int) -> void:
	while arr.size() <= slot:
		arr.append({"q": 0, "r": 0})
	arr[slot] = {"q": q, "r": r}


func _save() -> void:
	if encounter_resource != null and not encounter_resource.resource_path.is_empty():
		ResourceSaver.save(encounter_resource, encounter_resource.resource_path)
	if trigger_resource != null and not trigger_resource.resource_path.is_empty():
		ResourceSaver.save(trigger_resource, trigger_resource.resource_path)


# ── Geometry ──────────────────────────────────────────────────────────────────

func _center(q: int, r: int) -> Vector2:
	return Vector2(
		HEX_SIZE * 1.5 * q,
		HEX_SIZE * (sqrt(3.0) * 0.5 * q + sqrt(3.0) * r)
	)


func _poly(center: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(center + Vector2(HEX_SIZE * cos(a), HEX_SIZE * sin(a)))
	return pts
