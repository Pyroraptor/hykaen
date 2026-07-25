## tools/map_editor_scene.gd — runtime hex map / encounter editor
## Run: godot --scene res://tools/MapEditorScene.tscn
## Left-click = paint, Right-click = erase, Middle-drag = pan

extends Node2D

const CoordTransform = preload("res://presentation/infrastructure/coordinate_transform.gd")

const HEX_SIZE  : float = 48.0
const SIDEBAR_W : float = 220.0
var radius      : int   = 10

enum PaintMode { TERRAIN, IMPASSABLE, DIFFICULT, PARTY_POS, ENEMY_POS, TRIGGER, FEATURE }

# Floor map — tiles + shared party spawns; enemy_hex_positions unused here.
var encounter_resource : EncounterResource = null
var floor_path         : String            = ""

# Encounter groups — each group owns its own enemy spawns, trigger hexes, and save paths.
var encounter_groups   : Array = []   # Array of Dictionary (see _new_group)
var active_group_idx   : int   = -1

var paint_mode        : PaintMode = PaintMode.TERRAIN
var current_terrain   : String    = "floor"
var current_elevation : int       = 0
var current_cover     : int       = 0
var current_feature   : String    = ""
var party_slot        : int       = 0
var enemy_slot        : int       = 0

var _hovered_q : int     = 9999
var _hovered_r : int     = 9999
var _painting  : bool    = false
var _erase     : bool    = false
var _last_q    : int     = 9999
var _last_r    : int     = 9999
var _panning   : bool    = false
var _pan_from  : Vector2 = Vector2.ZERO
var _pan_base  : Vector2 = Vector2.ZERO
var _pan_offset: Vector2 = Vector2.ZERO

# UI node refs
var _sidebar          : Panel
var _status_label     : Label
var _floor_label      : Label
var _mode_btn         : OptionButton
var _terrain_row      : HBoxContainer
var _terrain_btn      : OptionButton
var _elevation_row    : HBoxContainer
var _elevation_spin   : SpinBox
var _cover_row        : HBoxContainer
var _cover_btn        : OptionButton
var _feature_row      : HBoxContainer
var _feature_edit     : LineEdit
var _slot_row         : HBoxContainer
var _slot_spin        : SpinBox
var _radius_spin      : SpinBox
var _group_list_vbox  : VBoxContainer
var _group_detail_box : VBoxContainer
var _group_name_edit  : LineEdit
var _group_enc_lbl    : Label
var _group_trg_lbl    : Label

# Reusable file dialogs — caller sets _pending_*_cb before opening.
var _open_dlg        : FileDialog
var _save_dlg        : FileDialog
var _pending_open_cb : Callable = Callable()
var _pending_save_cb : Callable = Callable()


# ── Color constants ───────────────────────────────────────────────────────────

const _TERRAIN_COLORS = {
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
const _EMPTY_COLOR    = Color(0.48, 0.48, 0.52, 0.38)
const _IMPASS_TINT    = Color(0.85, 0.22, 0.18, 0.40)
const _DIFFICULT_TINT = Color(0.88, 0.76, 0.14, 0.38)
const _COVER1_TINT    = Color(0.70, 0.88, 1.00, 0.22)
const _COVER2_TINT    = Color(0.40, 0.65, 0.95, 0.38)
const _PARTY_COLOR    = Color(0.22, 0.52, 0.95, 0.92)
const _FEATURE_COLOR  = Color(0.50, 0.88, 0.50, 0.85)
const _HOVER_COLOR    = Color(1.00, 1.00, 1.00, 0.22)
const _LINE_COLOR     = Color(0.35, 0.35, 0.40, 1.00)

# Per-group colors (up to 6 groups before wrapping).
const _GROUP_TRIG_COLORS = [
	Color(0.92, 0.55, 0.10, 0.42),
	Color(0.85, 0.12, 0.85, 0.42),
	Color(0.10, 0.82, 0.82, 0.42),
	Color(0.82, 0.82, 0.10, 0.42),
	Color(0.12, 0.80, 0.12, 0.42),
	Color(0.12, 0.12, 0.82, 0.42),
]
const _GROUP_ENEMY_COLORS = [
	Color(0.95, 0.42, 0.10, 0.92),
	Color(0.90, 0.12, 0.90, 0.92),
	Color(0.10, 0.88, 0.88, 0.92),
	Color(0.88, 0.88, 0.10, 0.92),
	Color(0.12, 0.85, 0.12, 0.92),
	Color(0.12, 0.12, 0.85, 0.92),
]


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	DisplayServer.window_set_title("Hykaen Map Editor")
	DisplayServer.window_set_size(Vector2i(1100, 700))
	_build_ui()
	_new_floor()
	call_deferred("_finalize_layout")


func _finalize_layout() -> void:
	var vp := get_viewport_rect().size
	_pan_offset = Vector2((vp.x - SIDEBAR_W) * 0.5, vp.y * 0.5)
	if _sidebar != null:
		_sidebar.position = Vector2(vp.x - SIDEBAR_W, 0)
		_sidebar.size     = Vector2(SIDEBAR_W, vp.y)
		var scroll := _sidebar.get_child(0) as ScrollContainer
		if scroll != null:
			scroll.size = Vector2(SIDEBAR_W, vp.y)
	queue_redraw()


# ── Input ─────────────────────────────────────────────────────────────────────

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


# ── Draw ──────────────────────────────────────────────────────────────────────

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

	# Trigger hexes — all groups, inactive dimmed.
	for gi in encounter_groups.size():
		var g = encounter_groups[gi]
		if _arr_has(g.trigger_hexes, q, r):
			var tc : Color = _GROUP_TRIG_COLORS[gi % _GROUP_TRIG_COLORS.size()]
			if gi != active_group_idx:
				tc = Color(tc.r, tc.g, tc.b, tc.a * 0.45)
			draw_colored_polygon(poly, tc)

	# Party positions (shared across floor).
	if encounter_resource != null:
		for i in encounter_resource.party_hex_positions.size():
			var p = encounter_resource.party_hex_positions[i]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, _PARTY_COLOR)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 5),
					"P%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	# Enemy positions — all groups, inactive dimmed, labeled G·slot.
	for gi in encounter_groups.size():
		var g = encounter_groups[gi]
		var ec : Color = _GROUP_ENEMY_COLORS[gi % _GROUP_ENEMY_COLORS.size()]
		if gi != active_group_idx:
			ec = Color(ec.r, ec.g, ec.b, ec.a * 0.40)
		for si in g.enemy_positions.size():
			var p = g.enemy_positions[si]
			if p is Dictionary and p.get("q") == q and p.get("r") == r:
				draw_circle(center, 16.0, ec)
				draw_string(ThemeDB.fallback_font, center + Vector2(-9, 5),
					"E%d·%d" % [gi, si], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

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
	var gi := active_group_idx
	var trig_c  = _GROUP_TRIG_COLORS[gi % _GROUP_TRIG_COLORS.size()]   if gi >= 0 else Color(0.92, 0.55, 0.10, 0.42)
	var enemy_c = _GROUP_ENEMY_COLORS[gi % _GROUP_ENEMY_COLORS.size()] if gi >= 0 else Color(0.88, 0.22, 0.22, 0.92)
	var labels := ["TERRAIN", "IMPASSABLE", "DIFFICULT", "PARTY POS", "ENEMY POS", "TRIGGER", "FEATURE"]
	var colors  := [_TERRAIN_COLORS.get(current_terrain, _EMPTY_COLOR),
		_IMPASS_TINT, _DIFFICULT_TINT, _PARTY_COLOR, enemy_c, trig_c, _FEATURE_COLOR]
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
				t.terrain_type = "floor"; t.elevation = 0; t.cover = 0
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
			if active_group_idx < 0:
				_status("Add an encounter group first."); return
			var g = encounter_groups[active_group_idx]
			if erase: _arr_remove(g.enemy_positions, q, r)
			else:     _arr_place(g.enemy_positions, enemy_slot, q, r)

		PaintMode.TRIGGER:
			if active_group_idx < 0:
				_status("Add an encounter group first."); return
			var g = encounter_groups[active_group_idx]
			if erase or _arr_has(g.trigger_hexes, q, r):
				_arr_remove(g.trigger_hexes, q, r)
			else:
				g.trigger_hexes.append({"q": q, "r": r})

		PaintMode.FEATURE:
			if encounter_resource == null: return
			var t := _get_or_create_tile(q, r)
			t.feature = "" if erase else current_feature

	queue_redraw()


# ── Floor ops ─────────────────────────────────────────────────────────────────

func _new_floor() -> void:
	encounter_resource = EncounterResource.new()
	encounter_groups   = []
	active_group_idx   = -1
	floor_path         = ""
	_rebuild_group_list()
	_refresh_active_group_ui()
	_update_floor_label()
	_status("New floor — paint terrain, then add encounter groups.")
	queue_redraw()


func _load_floor(path: String) -> void:
	var res = ResourceLoader.load(path)
	if not res is EncounterResource:
		_status("Not an EncounterResource: " + path.get_file()); return
	encounter_resource = res
	encounter_resource.enemy_hex_positions.clear()
	floor_path = path
	_update_floor_label()
	_status("Floor loaded: " + path.get_file())
	queue_redraw()


# ── Group ops ─────────────────────────────────────────────────────────────────

func _new_group(name: String) -> Dictionary:
	return { "name": name, "enemy_positions": [], "trigger_hexes": [], "enc_path": "", "trg_path": "" }


func _add_group() -> void:
	encounter_groups.append(_new_group("Encounter %d" % (encounter_groups.size() + 1)))
	active_group_idx = encounter_groups.size() - 1
	_rebuild_group_list()
	_refresh_active_group_ui()
	queue_redraw()


func _delete_group(idx: int) -> void:
	encounter_groups.remove_at(idx)
	active_group_idx = clampi(active_group_idx, 0, encounter_groups.size() - 1) \
		if not encounter_groups.is_empty() else -1
	_rebuild_group_list()
	_refresh_active_group_ui()
	queue_redraw()


func _select_group(idx: int) -> void:
	active_group_idx = idx
	_rebuild_group_list()
	_refresh_active_group_ui()
	queue_redraw()


func _rebuild_group_list() -> void:
	for c in _group_list_vbox.get_children():
		c.queue_free()
	for i in encounter_groups.size():
		var g = encounter_groups[i]
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = ("▶ " if i == active_group_idx else "   ") + g.name
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var snap := i
		btn.pressed.connect(func() -> void: _select_group(snap))
		row.add_child(btn)
		var del := Button.new()
		del.text = "×"
		del.custom_minimum_size = Vector2(22, 0)
		del.pressed.connect(func() -> void: _delete_group(snap))
		row.add_child(del)
		_group_list_vbox.add_child(row)


func _refresh_active_group_ui() -> void:
	var has := active_group_idx >= 0 and active_group_idx < encounter_groups.size()
	_group_detail_box.visible = has
	if not has: return
	var g = encounter_groups[active_group_idx]
	_group_name_edit.text  = g.name
	_group_enc_lbl.text    = (g.enc_path as String).get_file() if g.enc_path else "(unsaved)"
	_group_trg_lbl.text    = (g.trg_path as String).get_file() if g.trg_path else "(unsaved)"


# ── Save ops ──────────────────────────────────────────────────────────────────

func _save_group_enc(idx: int) -> void:
	if idx < 0 or idx >= encounter_groups.size(): return
	if encounter_resource == null: _status("No floor map."); return
	var g = encounter_groups[idx]
	if (g.enc_path as String).is_empty():
		var snap := idx
		_pending_save_cb = func(path: String) -> void:
			encounter_groups[snap].enc_path = path if path.ends_with(".tres") else path + ".tres"
			_save_group_enc(snap)
		_show_save("res://data/encounters"); return
	_do_save_group_enc(idx)
	_refresh_active_group_ui()
	_status("Saved enc: " + (g.enc_path as String).get_file())


func _save_group_trg(idx: int) -> void:
	if idx < 0 or idx >= encounter_groups.size(): return
	var g = encounter_groups[idx]
	if (g.trg_path as String).is_empty():
		var snap := idx
		_pending_save_cb = func(path: String) -> void:
			encounter_groups[snap].trg_path = path if path.ends_with(".tres") else path + ".tres"
			_save_group_trg(snap)
		_show_save("res://data/triggers"); return
	_do_save_group_trg(idx)
	_refresh_active_group_ui()
	_status("Saved trg: " + (g.trg_path as String).get_file())


func _do_save_group_enc(idx: int) -> void:
	var g = encounter_groups[idx]
	var enc := EncounterResource.new()
	enc.tiles = encounter_resource.tiles.duplicate(true)
	enc.party_hex_positions = encounter_resource.party_hex_positions.duplicate()
	enc.enemy_hex_positions = (g.enemy_positions as Array).duplicate()
	ResourceSaver.save(enc, g.enc_path)


func _do_save_group_trg(idx: int) -> void:
	var g = encounter_groups[idx]
	var trg := ProximityTriggerResource.new()
	trg.trigger_hexes = (g.trigger_hexes as Array).duplicate()
	ResourceSaver.save(trg, g.trg_path)


func _save_all() -> void:
	if encounter_groups.is_empty():
		_status("No encounter groups to save."); return
	var skipped: Array[String] = []
	for i in encounter_groups.size():
		var g = encounter_groups[i]
		if (g.enc_path as String).is_empty() or (g.trg_path as String).is_empty():
			skipped.append(g.name as String)
		else:
			_do_save_group_enc(i)
			_do_save_group_trg(i)
	var saved_count := encounter_groups.size() - skipped.size()
	if skipped.is_empty():
		_status("All %d groups saved." % saved_count)
	else:
		_status("%d saved. Need paths for: %s" % [saved_count, ", ".join(skipped)])


# ── Resource helpers ──────────────────────────────────────────────────────────

func _tile(q: int, r: int):
	if encounter_resource == null: return null
	for t in encounter_resource.tiles:
		if t != null and t.q == q and t.r == r: return t
	return null


func _get_or_create_tile(q: int, r: int) -> HexTileDataResource:
	var existing = _tile(q, r)
	if existing != null: return existing as HexTileDataResource
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

	_sidebar = Panel.new()
	cl.add_child(_sidebar)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(SIDEBAR_W - 20, 0)
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# ── FLOOR MAP ──
	_add_head(vbox, "FLOOR MAP")
	_floor_label = _add_lbl(vbox, "(new)")
	_add_btn(vbox, "New Floor", _new_floor)
	_add_btn(vbox, "Load Floor…", func() -> void:
		_pending_open_cb = _load_floor
		_show_open("res://data/encounters"))

	# ── ENCOUNTER GROUPS ──
	_add_head(vbox, "ENCOUNTER GROUPS")

	var grp_hdr := HBoxContainer.new()
	var grp_lbl := Label.new()
	grp_lbl.text = "Groups"
	grp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grp_hdr.add_child(grp_lbl)
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(26, 0)
	add_btn.pressed.connect(_add_group)
	grp_hdr.add_child(add_btn)
	vbox.add_child(grp_hdr)

	_group_list_vbox = VBoxContainer.new()
	vbox.add_child(_group_list_vbox)

	# Active-group detail section (hidden when no group selected).
	_group_detail_box = VBoxContainer.new()
	_group_detail_box.visible = false
	vbox.add_child(_group_detail_box)

	_add_head(_group_detail_box, "")

	var name_row := HBoxContainer.new()
	_add_lbl_to(name_row, "Name:")
	_group_name_edit = LineEdit.new()
	_group_name_edit.custom_minimum_size = Vector2(110, 0)
	_group_name_edit.text_changed.connect(func(s: String) -> void:
		if active_group_idx >= 0:
			encounter_groups[active_group_idx].name = s
			_rebuild_group_list())
	name_row.add_child(_group_name_edit)
	_group_detail_box.add_child(name_row)

	_group_enc_lbl = _add_lbl(_group_detail_box, "(unsaved)")
	var enc_row := HBoxContainer.new()
	_add_btn(enc_row, "Save Enc", func() -> void: _save_group_enc(active_group_idx))
	_add_btn(enc_row, "Save As…", func() -> void:
		if active_group_idx < 0: return
		var snap := active_group_idx
		_pending_save_cb = func(p: String) -> void:
			encounter_groups[snap].enc_path = p if p.ends_with(".tres") else p + ".tres"
			_do_save_group_enc(snap)
			_refresh_active_group_ui()
			_status("Saved enc: " + (encounter_groups[snap].enc_path as String).get_file())
		_show_save("res://data/encounters"))
	_group_detail_box.add_child(enc_row)

	_add_btn(_group_detail_box, "Load Enc…", func() -> void:
		if active_group_idx < 0: return
		var snap := active_group_idx
		_pending_open_cb = func(p: String) -> void:
			var res = ResourceLoader.load(p)
			if not res is EncounterResource: _status("Not an EncounterResource."); return
			encounter_groups[snap].enemy_positions = res.enemy_hex_positions.duplicate()
			encounter_groups[snap].enc_path = p
			_refresh_active_group_ui()
			_status("Loaded enc for '%s'." % encounter_groups[snap].name)
			queue_redraw()
		_show_open("res://data/encounters"))

	_group_trg_lbl = _add_lbl(_group_detail_box, "(unsaved)")
	var trg_row := HBoxContainer.new()
	_add_btn(trg_row, "Save Trg", func() -> void: _save_group_trg(active_group_idx))
	_add_btn(trg_row, "Save As…", func() -> void:
		if active_group_idx < 0: return
		var snap := active_group_idx
		_pending_save_cb = func(p: String) -> void:
			encounter_groups[snap].trg_path = p if p.ends_with(".tres") else p + ".tres"
			_do_save_group_trg(snap)
			_refresh_active_group_ui()
			_status("Saved trg: " + (encounter_groups[snap].trg_path as String).get_file())
		_show_save("res://data/triggers"))
	_group_detail_box.add_child(trg_row)

	_add_btn(_group_detail_box, "Load Trg…", func() -> void:
		if active_group_idx < 0: return
		var snap := active_group_idx
		_pending_open_cb = func(p: String) -> void:
			var res = ResourceLoader.load(p)
			if not res is ProximityTriggerResource: _status("Not a ProximityTriggerResource."); return
			encounter_groups[snap].trigger_hexes = res.trigger_hexes.duplicate()
			encounter_groups[snap].trg_path = p
			_refresh_active_group_ui()
			_status("Loaded trg for '%s'." % encounter_groups[snap].name)
			queue_redraw()
		_show_open("res://data/triggers"))

	_add_head(vbox, "")
	_add_btn(vbox, "Save All", _save_all)

	# ── MAP SIZE ──
	_add_head(vbox, "MAP SIZE")
	var rad_row := HBoxContainer.new()
	_add_lbl_to(rad_row, "Radius:")
	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 3; _radius_spin.max_value = 24; _radius_spin.value = radius
	_radius_spin.value_changed.connect(func(v: float) -> void:
		radius = int(v); queue_redraw())
	rad_row.add_child(_radius_spin)
	vbox.add_child(rad_row)

	# ── PAINT MODE ──
	_add_head(vbox, "PAINT MODE")
	_mode_btn = OptionButton.new()
	for lbl in ["Terrain","Impassable","Difficult","Party Pos","Enemy Pos","Trigger","Feature"]:
		_mode_btn.add_item(lbl)
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
		current_terrain = _terrain_btn.get_item_text(i); queue_redraw())
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

	# Two reusable file dialogs; caller sets _pending_*_cb before showing.
	_open_dlg = FileDialog.new()
	_open_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dlg.access    = FileDialog.ACCESS_RESOURCES
	_open_dlg.add_filter("*.tres", "Resource Files")
	_open_dlg.file_selected.connect(func(p: String) -> void:
		if _pending_open_cb.is_valid(): _pending_open_cb.call(p)
		_pending_open_cb = Callable())
	add_child(_open_dlg)

	_save_dlg = FileDialog.new()
	_save_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dlg.access    = FileDialog.ACCESS_RESOURCES
	_save_dlg.add_filter("*.tres", "Resource Files")
	_save_dlg.file_selected.connect(func(p: String) -> void:
		if _pending_save_cb.is_valid(): _pending_save_cb.call(p)
		_pending_save_cb = Callable())
	add_child(_save_dlg)


func _show_open(dir: String) -> void:
	_open_dlg.current_dir = dir
	_open_dlg.popup_centered(Vector2i(700, 500))


func _show_save(dir: String) -> void:
	_save_dlg.current_dir = dir
	_save_dlg.popup_centered(Vector2i(700, 500))


func _refresh_context_rows() -> void:
	var is_terrain := (paint_mode == PaintMode.TERRAIN)
	_terrain_row.visible   = is_terrain
	_elevation_row.visible = is_terrain
	_cover_row.visible     = is_terrain
	_feature_row.visible   = (paint_mode == PaintMode.FEATURE)
	_slot_row.visible = (paint_mode == PaintMode.PARTY_POS or paint_mode == PaintMode.ENEMY_POS)


func _update_floor_label() -> void:
	if _floor_label != null:
		_floor_label.text = floor_path.get_file() if floor_path else "(new)"


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
