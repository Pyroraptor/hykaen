## tools/map_editor_scene.gd — runtime hex map / encounter editor
## Run: godot --scene res://tools/MapEditorScene.tscn
## Left-click = paint, Right-click = erase, Middle-drag = pan

extends Node2D

const CoordTransform = preload("res://presentation/infrastructure/coordinate_transform.gd")

const HEX_SIZE  : float = 48.0
const SIDEBAR_W : float = 220.0
var radius      : int   = 10

enum PaintMode { TERRAIN, IMPASSABLE, DIFFICULT, PARTY_POS, ENEMY_POS, TRIGGER, FEATURE }

var encounter_resource : EncounterResource        = null
var trigger_resource   : ProximityTriggerResource = null
var _encounter_path    : String = ""
var _trigger_path      : String = ""

var paint_mode        : PaintMode = PaintMode.TERRAIN
var current_terrain   : String    = "floor"
var current_elevation : int       = 0
var current_cover     : int       = 0
var current_feature   : String    = ""
var party_slot        : int       = 0
var enemy_slot        : int       = 0

var _hovered_q : int = 9999
var _hovered_r : int = 9999
var _painting  : bool    = false
var _erase     : bool    = false
var _last_q    : int     = 9999
var _last_r    : int     = 9999
var _panning   : bool    = false
var _pan_from  : Vector2 = Vector2.ZERO
var _pan_base  : Vector2 = Vector2.ZERO
var _pan_offset: Vector2 = Vector2.ZERO

var _file_label     : Label
var _trigger_label  : Label
var _status_label   : Label
var _mode_btn       : OptionButton
var _terrain_row    : HBoxContainer
var _terrain_btn    : OptionButton
var _elevation_row  : HBoxContainer
var _elevation_spin : SpinBox
var _cover_row      : HBoxContainer
var _cover_btn      : OptionButton
var _feature_row    : HBoxContainer
var _feature_edit   : LineEdit
var _slot_row       : HBoxContainer
var _slot_spin      : SpinBox
var _radius_spin    : SpinBox
var _sidebar        : Panel

const _TERRAIN_COLORS = {
	# indoor / structural
	"floor":         Color(0.82, 0.82, 0.82, 0.85),
	"rubble":        Color(0.65, 0.55, 0.40, 0.88),
	"wall":          Color(0.28, 0.26, 0.26, 0.92),
	"pit":           Color(0.10, 0.08, 0.08, 0.96),
	# outdoor ground
	"grass":         Color(0.35, 0.62, 0.25, 0.85),
	"stone":         Color(0.60, 0.58, 0.54, 0.85),
	"sand":          Color(0.85, 0.78, 0.52, 0.85),
	# difficult / cover
	"forest":        Color(0.15, 0.42, 0.15, 0.90),
	"undergrowth":   Color(0.32, 0.55, 0.22, 0.85),
	"mud":           Color(0.45, 0.33, 0.18, 0.88),
	# water
	"shallow_water": Color(0.48, 0.72, 0.90, 0.82),
	"deep_water":    Color(0.10, 0.22, 0.65, 0.92),
	"water":         Color(0.25, 0.55, 0.85, 0.88),
	# hazard
	"lava":          Color(0.95, 0.35, 0.05, 0.90),
	"ice":           Color(0.80, 0.92, 0.98, 0.88),
}
const _EMPTY_COLOR    = Color(0.48, 0.48, 0.52, 0.38)
const _IMPASS_TINT    = Color(0.85, 0.22, 0.18, 0.40)
const _DIFFICULT_TINT = Color(0.88, 0.76, 0.14, 0.38)
const _COVER1_TINT    = Color(0.70, 0.88, 1.00, 0.22)
const _COVER2_TINT    = Color(0.40, 0.65, 0.95, 0.38)
const _PARTY_COLOR    = Color(0.22, 0.52, 0.95, 0.92)
const _ENEMY_COLOR    = Color(0.88, 0.22, 0.22, 0.92)
const _TRIGGER_COLOR  = Color(0.92, 0.55, 0.10, 0.38)
const _FEATURE_COLOR  = Color(0.50, 0.88, 0.50, 0.85)
const _HOVER_COLOR    = Color(1.00, 1.00, 1.00, 0.22)
const _LINE_COLOR     = Color(0.35, 0.35, 0.40, 1.00)


func _ready() -> void:
	DisplayServer.window_set_title("Hykaen Map Editor")
	DisplayServer.window_set_size(Vector2i(1100, 700))
	_build_ui()
	_new_encounter()
	call_deferred("_finalize_layout")

func _finalize_layout() -> void:
	var vp := get_viewport_rect().size
	_pan_offset = Vector2((vp.x - SIDEBAR_W) * 0.5, vp.y * 0.5)
	if _sidebar != null:
		_sidebar.position = Vector2(vp.x - SIDEBAR_W, 0)
		_sidebar.size     = Vector2(SIDEBAR_W, vp.y)
		_resize_scroll_child()
	queue_redraw()

func _resize_scroll_child() -> void:
	var vp := get_viewport_rect().size
	if _sidebar == null: return
	var scroll := _sidebar.get_child(0) as ScrollContainer
	if scroll == null: return
	scroll.size = Vector2(SIDEBAR_W, vp.y)


# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if event.pressed:
					_pan_from = event.position
					_pan_base = _pan_offset
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_painting = true
					_erase = (event.button_index == MOUSE_BUTTON_RIGHT)
					_last_q = 9999; _last_r = 9999
					_try_paint(event.position)
				else:
					_painting = false
					_last_q = 9999; _last_r = 9999

	elif event is InputEventMouseMotion:
		if _panning:
			_pan_offset = _pan_base + (event.position - _pan_from)
			queue_redraw()
		var hex = CoordTransform.pixel_to_axial(event.position, HEX_SIZE, _pan_offset)
		if hex.q != _hovered_q or hex.r != _hovered_r:
			_hovered_q = hex.q; _hovered_r = hex.r
			queue_redraw()
		if _painting:
			_try_paint(event.position)


func _try_paint(screen_pos: Vector2) -> void:
	var hex = CoordTransform.pixel_to_axial(screen_pos, HEX_SIZE, _pan_offset)
	if absi(hex.q) > radius or absi(hex.r) > radius or absi(-hex.q - hex.r) > radius:
		return
	if hex.q == _last_q and hex.r == _last_r:
		return
	_paint(hex.q, hex.r, _erase)
	_last_q = hex.q; _last_r = hex.r


# ── Draw ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if absi(-q - r) <= radius:
				_draw_hex(q, r)
	_draw_legend()


func _draw_hex(q: int, r: int) -> void:
	var center := Vector2(
		HEX_SIZE * 1.5 * q,
		HEX_SIZE * (sqrt(3.0) * 0.5 * q + sqrt(3.0) * r)
	) + _pan_offset
	var poly := _hex_poly(center)

	draw_colored_polygon(poly, _fill_color(q, r))
	if q == _hovered_q and r == _hovered_r:
		draw_colored_polygon(poly, _HOVER_COLOR)

	var tile = _tile(q, r)
	if tile != null:
		if not tile.passable:
			draw_colored_polygon(poly, _IMPASS_TINT)
		elif tile.difficult:
			draw_colored_polygon(poly, _DIFFICULT_TINT)
		if tile.cover == 1:
			draw_colored_polygon(poly, _COVER1_TINT)
		elif tile.cover == 2:
			draw_colored_polygon(poly, _COVER2_TINT)

	if trigger_resource != null and _arr_has(trigger_resource.trigger_hexes, q, r):
		draw_colored_polygon(poly, _TRIGGER_COLOR)

	if encounter_resource != null:
		for i in encounter_resource.party_hex_positions.size():
			var p = encounter_resource.party_hex_positions[i]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, _PARTY_COLOR)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 5),
					"P%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		for i in encounter_resource.enemy_hex_positions.size():
			var p = encounter_resource.enemy_hex_positions[i]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, _ENEMY_COLOR)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 5),
					"E%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	if tile != null:
		if tile.elevation != 0:
			draw_string(ThemeDB.fallback_font, center + Vector2(14, -14),
				"%+d" % tile.elevation, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.4, 0.9))
		if not tile.feature.is_empty():
			draw_string(ThemeDB.fallback_font, center + Vector2(-10, 20),
				tile.feature.left(6), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.85, 1.0, 0.5, 0.9))

	if q == _hovered_q and r == _hovered_r:
		draw_string(ThemeDB.fallback_font, center + Vector2(-14, -4),
			"(%d,%d)" % [q, r], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0.6, 0.9))

	var outline := PackedVector2Array()
	for i in range(7):
		var a := deg_to_rad(60.0 * (i % 6))
		outline.append(center + Vector2(HEX_SIZE * cos(a), HEX_SIZE * sin(a)))
	draw_polyline(outline, _LINE_COLOR, 1.5)


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var lx := 8.0; var ly := 8.0
	var labels := ["TERRAIN", "IMPASSABLE", "DIFFICULT", "PARTY POS", "ENEMY POS", "TRIGGER", "FEATURE"]
	var colors := [_TERRAIN_COLORS.get(current_terrain, _EMPTY_COLOR),
		_IMPASS_TINT, _DIFFICULT_TINT, _PARTY_COLOR, _ENEMY_COLOR, _TRIGGER_COLOR, _FEATURE_COLOR]
	for i in labels.size():
		var ry := ly + i * 22.0
		draw_rect(Rect2(Vector2(lx, ry), Vector2(14, 14)), colors[i])
		var prefix := "▶ " if paint_mode == i else "  "
		draw_string(font, Vector2(lx + 18, ry + 12),
			prefix + labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


# ── Paint ─────────────────────────────────────────────────────────────────────

func _paint(q: int, r: int, erase: bool) -> void:
	match paint_mode:
		PaintMode.TERRAIN:
			if encounter_resource == null: return
			var t := _get_or_create_tile(q, r)
			if erase:
				t.terrain_type = "floor"
				t.elevation = 0; t.cover = 0
			else:
				t.terrain_type = current_terrain
				t.elevation = current_elevation
				t.cover = current_cover

		PaintMode.IMPASSABLE:
			if encounter_resource == null: return
			_get_or_create_tile(q, r).passable = erase

		PaintMode.DIFFICULT:
			if encounter_resource == null: return
			_get_or_create_tile(q, r).difficult = not erase

		PaintMode.PARTY_POS:
			if encounter_resource == null: return
			if erase: _arr_remove(encounter_resource.party_hex_positions, q, r)
			else:     _arr_place(encounter_resource.party_hex_positions, party_slot, q, r)

		PaintMode.ENEMY_POS:
			if encounter_resource == null: return
			if erase: _arr_remove(encounter_resource.enemy_hex_positions, q, r)
			else:     _arr_place(encounter_resource.enemy_hex_positions, enemy_slot, q, r)

		PaintMode.TRIGGER:
			if trigger_resource == null:
				trigger_resource = ProximityTriggerResource.new()
				_update_trigger_label()
			if erase or _arr_has(trigger_resource.trigger_hexes, q, r):
				_arr_remove(trigger_resource.trigger_hexes, q, r)
			else:
				trigger_resource.trigger_hexes.append({"q": q, "r": r})

		PaintMode.FEATURE:
			if encounter_resource == null: return
			var t := _get_or_create_tile(q, r)
			t.feature = "" if erase else current_feature

	queue_redraw()


# ── File ops ─────────────────────────────────────────────────────────────────

func _new_encounter() -> void:
	encounter_resource = EncounterResource.new()
	trigger_resource   = null
	_encounter_path    = ""
	_trigger_path      = ""
	_update_labels()
	_status("New encounter — paint terrain, then Save As.")
	queue_redraw()


func _save_encounter() -> void:
	if encounter_resource == null: return
	if _encounter_path.is_empty():
		_show_dialog("save_enc")
		return
	ResourceSaver.save(encounter_resource, _encounter_path)
	_status("Saved: " + _encounter_path.get_file())


func _save_trigger() -> void:
	if trigger_resource == null:
		_status("No trigger data — paint some TRIGGER hexes first.")
		return
	if _trigger_path.is_empty():
		_show_dialog("save_trg")
		return
	ResourceSaver.save(trigger_resource, _trigger_path)
	_status("Trigger saved: " + _trigger_path.get_file())


func _on_enc_loaded(path: String) -> void:
	var res = ResourceLoader.load(path)
	if not res is EncounterResource:
		_status("Not an EncounterResource: " + path.get_file()); return
	encounter_resource = res
	_encounter_path = path
	_update_labels()
	_status("Loaded: " + path.get_file())
	queue_redraw()


func _on_enc_saved(path: String) -> void:
	_encounter_path = path if path.ends_with(".tres") else path + ".tres"
	_save_encounter()


func _on_trg_loaded(path: String) -> void:
	var res = ResourceLoader.load(path)
	if not res is ProximityTriggerResource:
		_status("Not a ProximityTriggerResource: " + path.get_file()); return
	trigger_resource = res
	_trigger_path = path
	_update_labels()
	_status("Trigger loaded: " + path.get_file())
	queue_redraw()


func _on_trg_saved(path: String) -> void:
	_trigger_path = path if path.ends_with(".tres") else path + ".tres"
	_save_trigger()


# ── Resource helpers ──────────────────────────────────────────────────────────

func _tile(q: int, r: int):
	if encounter_resource == null: return null
	for t in encounter_resource.tiles:
		if t != null and t.q == q and t.r == r: return t
	return null


func _get_or_create_tile(q: int, r: int):
	var existing = _tile(q, r)
	if existing != null: return existing
	var t := HexTileDataResource.new()
	t.q = q; t.r = r
	encounter_resource.tiles.append(t)
	return t


func _fill_color(q: int, r: int) -> Color:
	var t = _tile(q, r)
	return _EMPTY_COLOR if t == null else _TERRAIN_COLORS.get(t.terrain_type, _EMPTY_COLOR)


func _arr_has(arr: Array, q: int, r: int) -> bool:
	for p in arr:
		if p is Dictionary and p.get("q") == q and p.get("r") == r: return true
	return false


func _arr_remove(arr: Array, q: int, r: int) -> void:
	for i in arr.size():
		if arr[i] is Dictionary and arr[i].get("q") == q and arr[i].get("r") == r:
			arr.remove_at(i); return


func _arr_place(arr: Array, slot: int, q: int, r: int) -> void:
	while arr.size() <= slot: arr.append({"q": 0, "r": 0})
	arr[slot] = {"q": q, "r": r}


func _hex_poly(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(center + Vector2(HEX_SIZE * cos(a), HEX_SIZE * sin(a)))
	return pts


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	# Panel (not PanelContainer) so it never auto-resizes to fit children.
	# Position and size are set in _finalize_layout() once the viewport is ready.
	_sidebar = Panel.new()
	cl.add_child(_sidebar)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(SIDEBAR_W - 20, 0)
	vbox.add_theme_constant_override("separation", 5)
	scroll.add_child(vbox)

	_add_head(vbox, "ENCOUNTER")
	_file_label = _add_lbl(vbox, "(new)")
	_add_btn(vbox, "New",         _new_encounter)
	_add_btn(vbox, "Load…",       func(): _show_dialog("load_enc"))
	_add_btn(vbox, "Save",        _save_encounter)
	_add_btn(vbox, "Save As…",    func(): _show_dialog("save_enc"))

	_add_head(vbox, "TRIGGER")
	_trigger_label = _add_lbl(vbox, "(none)")
	_add_btn(vbox, "Load trigger…", func(): _show_dialog("load_trg"))
	_add_btn(vbox, "Save trigger",  _save_trigger)
	_add_btn(vbox, "Save trigger As…", func(): _show_dialog("save_trg"))

	_add_head(vbox, "MAP SIZE")
	var radius_row := HBoxContainer.new()
	_add_lbl_to(radius_row, "Radius:")
	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 3; _radius_spin.max_value = 24; _radius_spin.value = radius
	_radius_spin.value_changed.connect(func(v: float) -> void:
		radius = int(v); queue_redraw())
	radius_row.add_child(_radius_spin)
	vbox.add_child(radius_row)

	_add_head(vbox, "PAINT MODE")
	_mode_btn = OptionButton.new()
	for label in ["Terrain","Impassable","Difficult","Party Pos","Enemy Pos","Trigger","Feature"]:
		_mode_btn.add_item(label)
	_mode_btn.item_selected.connect(func(i: int) -> void:
		paint_mode = i as PaintMode
		_refresh_context_rows()
		queue_redraw())
	vbox.add_child(_mode_btn)

	_terrain_row = HBoxContainer.new()
	_add_lbl_to(_terrain_row, "Type:")
	_terrain_btn = OptionButton.new()
	for t in ["floor","rubble","wall","pit","grass","stone","sand",
			  "forest","undergrowth","mud","shallow_water","deep_water",
			  "water","lava","ice"]:
		_terrain_btn.add_item(t)
	_terrain_btn.item_selected.connect(func(i: int) -> void:
		current_terrain = _terrain_btn.get_item_text(i)
		queue_redraw())
	_terrain_row.add_child(_terrain_btn)
	vbox.add_child(_terrain_row)

	_elevation_row = HBoxContainer.new()
	_add_lbl_to(_elevation_row, "Elev:")
	_elevation_spin = SpinBox.new()
	_elevation_spin.min_value = -5; _elevation_spin.max_value = 5; _elevation_spin.value = 0
	_elevation_spin.value_changed.connect(func(v: float) -> void: current_elevation = int(v))
	_elevation_row.add_child(_elevation_spin)
	vbox.add_child(_elevation_row)

	_cover_row = HBoxContainer.new()
	_add_lbl_to(_cover_row, "Cover:")
	_cover_btn = OptionButton.new()
	for c in ["None","Partial","Full"]: _cover_btn.add_item(c)
	_cover_btn.item_selected.connect(func(i: int) -> void: current_cover = i)
	_cover_row.add_child(_cover_btn)
	vbox.add_child(_cover_row)

	_feature_row = HBoxContainer.new()
	_add_lbl_to(_feature_row, "Feature:")
	_feature_edit = LineEdit.new()
	_feature_edit.placeholder_text = "door, chest…"
	_feature_edit.custom_minimum_size = Vector2(100, 0)
	_feature_edit.text_changed.connect(func(s: String) -> void: current_feature = s)
	_feature_row.add_child(_feature_edit)
	vbox.add_child(_feature_row)

	_slot_row = HBoxContainer.new()
	_add_lbl_to(_slot_row, "Slot:")
	_slot_spin = SpinBox.new()
	_slot_spin.min_value = 0; _slot_spin.max_value = 8
	_slot_spin.value_changed.connect(func(v: float) -> void:
		if paint_mode == PaintMode.PARTY_POS: party_slot = int(v)
		else: enemy_slot = int(v))
	_slot_row.add_child(_slot_spin)
	vbox.add_child(_slot_row)

	_add_head(vbox, "")
	_add_lbl(vbox, "Left-click: paint\nRight-click: erase\nMiddle-drag: pan")
	_add_head(vbox, "")
	_status_label = _add_lbl(vbox, "Ready")

	_refresh_context_rows()

	# File dialogs — one node, four uses distinguished by a tag
	for tag in ["load_enc", "save_enc", "load_trg", "save_trg"]:
		var dlg := FileDialog.new()
		dlg.name = tag
		dlg.access = FileDialog.ACCESS_RESOURCES
		dlg.add_filter("*.tres", "Resource Files")
		dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE if (tag as String).begins_with("save") \
			else FileDialog.FILE_MODE_OPEN_FILE
		var cb: Callable
		match tag:
			"save_enc": cb = _on_enc_saved
			"load_enc": cb = _on_enc_loaded
			"save_trg": cb = _on_trg_saved
			_:          cb = _on_trg_loaded
		dlg.file_selected.connect(cb)
		add_child(dlg)


func _show_dialog(tag: String) -> void:
	var dlg := get_node_or_null(tag) as FileDialog
	if dlg == null: return
	var base := "res://data/encounters" if "enc" in tag else "res://data/triggers"
	dlg.current_dir = base
	dlg.popup_centered(Vector2i(700, 500))


func _refresh_context_rows() -> void:
	var is_terrain := (paint_mode == PaintMode.TERRAIN)
	_terrain_row.visible   = is_terrain
	_elevation_row.visible = is_terrain
	_cover_row.visible     = is_terrain
	_feature_row.visible   = (paint_mode == PaintMode.FEATURE)
	_slot_row.visible = (paint_mode == PaintMode.PARTY_POS or paint_mode == PaintMode.ENEMY_POS)


func _update_labels() -> void:
	if _file_label != null:
		_file_label.text = _encounter_path.get_file() if _encounter_path else "(new)"
	_update_trigger_label()


func _update_trigger_label() -> void:
	if _trigger_label == null: return
	if _trigger_path:
		_trigger_label.text = _trigger_path.get_file()
	elif trigger_resource != null:
		_trigger_label.text = "(unsaved)"
	else:
		_trigger_label.text = "(none)"


func _status(msg: String) -> void:
	if _status_label != null: _status_label.text = msg


# ── UI helpers ────────────────────────────────────────────────────────────────

func _add_head(parent: Control, text: String) -> void:
	var sep := HSeparator.new(); parent.add_child(sep)
	if text.is_empty(): return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)


func _add_lbl(parent: Control, text: String) -> Label:
	var lbl := Label.new(); lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl); return lbl


func _add_lbl_to(parent: Control, text: String) -> void:
	var lbl := Label.new(); lbl.text = text; parent.add_child(lbl)


func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var btn := Button.new(); btn.text = text; btn.pressed.connect(cb); parent.add_child(btn)
