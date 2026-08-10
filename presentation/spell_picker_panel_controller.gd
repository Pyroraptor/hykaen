## presentation/spell_picker_panel_controller.gd — SpellPickerPanelController
## (FEAT-008 / US-007 / FR-002).
##
## Presentation layer (Clean Architecture): a leaf UI controller for the
## floating spell-picker panel shown during Layer-2a spell selection (i.e.
## while `selection_overlay.is_awaiting_option()` is true — see presentation/
## selection_overlay.gd). Extracted verbatim from MainScene.gd's own former
## `_setup_spell_picker_panel()` / `_show_spell_picker()` /
## `_on_spell_option_pressed()` / `_hide_spell_picker()` quartet (FEAT-008's
## "four spell-picker-panel functions") — the ALGORITHM is unchanged: one
## Button per candidate option, clicking a button hides the panel and invokes
## the caller-supplied selection callback. Only the composition-root-owned
## Panel *node* itself (created/add_child()ed by MainScene.gd, the
## scene-tree-wiring concern) is NOT owned by this controller — it is
## injected via setup(panel_node), mirroring cancel_controller.gd's/
## movement_input_controller.gd's own "plain RefCounted adapter, configured
## with an already-instantiated collaborator" precedent.
##
## Public surface (exactly three methods, per this feature's spec):
##   setup(panel_node: Panel) -> void
##   show(options: Array, on_selected: Callable) -> void
##   hide() -> void
##
## `on_selected` (new vs. the pre-extraction code, which hardcoded a call to
## `selection_overlay.choose_option(option)`) decouples this controller from
## SelectionOverlay entirely — it holds NO reference to selection_overlay,
## `_verb_registry`, or any Application-layer port; the caller (MainScene.gd,
## or combine_queue_build_session.gd/combine_targeting_session.gd via the
## `show_spell_picker_fn`/`hide_spell_picker_fn` Callable deps they already
## accept) decides what a chosen option means. This mirrors cancel_controller.
## gd's file-level doc: a presentation leaf with no game-state mutation
## authority of its own.
##
## `_on_spell_option_pressed` (the former MainScene.gd method of the same
## name) is PRIVATE here — a single leading underscore, this codebase's
## established private-method convention (mirrors MainScene.gd's own
## `_on_combine_queue_built`/`_on_verb_bar_selection_entered`/etc.). It is
## reachable only via a Button's own `pressed` signal (wired inside show()),
## never called directly by any other file — see
## tests/gut/test_spell_picker_panel_controller.gd's own
## test_on_spell_option_pressed_is_private_and_not_part_of_the_public_api()
## for the static-surface assertion covering this feature's own test_criteria
## ("_on_spell_option_pressed is private").

class_name SpellPickerPanelController
extends RefCounted

## Name of the VBoxContainer child setup() creates inside the injected panel
## node — mirrors the pre-extraction code's own "SpellList" node name.
const _SPELL_LIST_NODE_NAME: String = "SpellList"

## The composition-root-owned Panel node injected via setup(). This
## controller never creates or add_child()s the panel itself (MainScene.gd
## remains the SceneTree node that owns it — see file-level doc), only its
## "SpellList" VBoxContainer child + that child's Button children.
var _panel: Panel = null


## create_and_add_to(parent) -> void — creates the Panel node, add_child()s
## it into `parent`, and calls setup().  Lets the composition root delegate
## both the node construction and the controller wiring to a single call
## rather than 15 individual property-assignment lines.
func create_and_add_to(parent: Node) -> void:
	var panel := Panel.new()
	panel.name = "SpellPickerPanel"
	panel.visible = false
	panel.custom_minimum_size = Vector2(180, 40)
	panel.anchor_left = 0.0; panel.anchor_right = 0.0
	panel.anchor_top  = 0.0; panel.anchor_bottom = 0.0
	panel.offset_left = 156; panel.offset_right  = 336
	panel.offset_top  = 8;   panel.offset_bottom = 208
	parent.add_child(panel)
	setup(panel)


## setup(panel_node) -> void — injects the already-created, already-
## add_child()ed Panel this controller populates/shows/hides. Idempotent-safe
## to call again (e.g. a future encounter reload) — re-uses the existing
## "SpellList" child instead of creating a duplicate if one is already
## present. Safe to call with a panel_node that has no "SpellList" child yet
## (the normal, first-boot case): creates it once here.
func setup(panel_node: Panel) -> void:
	_panel = panel_node
	if _panel == null:
		push_error("SpellPickerPanelController.setup(): panel_node must not be null")
		return
	if _panel.has_node(_SPELL_LIST_NODE_NAME):
		return
	var vbox := VBoxContainer.new()
	vbox.name = _SPELL_LIST_NODE_NAME
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	_panel.add_child(vbox)


## show(options, on_selected) -> void — populates the panel with one Button
## per option (label = option["label"], falling back to option["id"], then
## "?" — UNCHANGED from the pre-extraction code) and makes the panel visible.
## Clicking a button hides the panel then invokes `on_selected.call(option)`
## with the option that was pressed — the ONLY way `on_selected` is ever
## invoked (never called eagerly, never called for an option that was not
## actually clicked). Guarded: a no-op (with push_error) if setup(panel_node)
## has not been called yet.
func show(options: Array, on_selected: Callable) -> void:
	if _panel == null:
		push_error("SpellPickerPanelController.show(): setup(panel_node) must be called first")
		return
	var vbox: VBoxContainer = _panel.get_node(_SPELL_LIST_NODE_NAME)
	for child in vbox.get_children():
		child.queue_free()
	for option in options:
		var btn := Button.new()
		btn.text = option.get("label", option.get("id", "?"))
		btn.pressed.connect(_on_spell_option_pressed.bind(option, on_selected))
		vbox.add_child(btn)
	_panel.visible = true


## hide() -> void — hides the panel. A safe no-op if setup(panel_node) has
## not been called yet (UNCHANGED "guard, don't crash" discipline from the
## pre-extraction code's own `if _spell_picker_panel != null` guard).
func hide() -> void:
	if _panel != null:
		_panel.visible = false


## _on_spell_option_pressed(option, on_selected) -> void — PRIVATE (see
## file-level doc). The Button `pressed` handler bound (with the pressed
## option + the show()-time on_selected Callable) inside show() above.
## Hides the panel FIRST, then invokes on_selected — UNCHANGED ordering from
## the pre-extraction `_on_spell_option_pressed()` (`_hide_spell_picker()`
## before `selection_overlay.choose_option(option)`), so any side effect
## `on_selected` triggers (e.g. SelectionOverlay entering Layer-2b targeting)
## never races a still-visible spell-picker panel.
func _on_spell_option_pressed(option: Dictionary, on_selected: Callable) -> void:
	hide()
	if on_selected.is_valid():
		on_selected.call(option)
