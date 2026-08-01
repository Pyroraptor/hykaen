## presentation/equipment_panel_ui.gd — EquipmentPanelUI (FEAT-009 / US-010)
##
## Presentation layer (Clean Architecture, ADR-003): a READ-ONLY projection
## of a CharacterResource's equipped items. Renders exactly one row per
## EquipmentSlot.ALL_SLOTS slot (core/model/equipment_slot.gd) -- slot label
## + the equipped item's display_name, or "—" when the slot is empty --
## plus a charged/uncharged indicator for any equipped item that carries a
## non-empty prepared_spell_id.
##
## setup(character) reads character.get_item_in_slot(slot)
## (core/model/character_resource.gd) directly off the Domain
## CharacterResource for every slot in EquipmentSlot.ALL_SLOTS. It NEVER
## mutates equipped_items and NEVER calls into an Application-layer use case
## (EquipItemUseCase / UnequipItemUseCase / PrepareSpellUseCase) -- per
## ADR-003, this iteration's panel is confirmed read-only, with no
## click/interaction handler wired to any row Control (see
## tests/scene/test_equipment_panel_ui.gd's source-inspection assertion).
##
## clear() resets every row back to its empty ("—", no charge indicator)
## state. Neither setup() nor clear() ever creates/destroys row nodes --
## all 15 rows are built once, lazily, the first time they're needed (so
## get_row_count() == 15 immediately after scenes/equipment_panel.tscn is
## instantiated, even before setup() is ever called), and are simply
## re-rendered in place thereafter.
class_name EquipmentPanelUI
extends Control

## Preloaded (see core/model/character_resource.gd's own preload() note)
## rather than referenced via bare global class_name, so this file's
## dependency on EquipmentSlot's constants resolves even when the
## project's global script class cache has not been regenerated between
## headless CI runs.
const _EquipmentSlot = preload("res://core/model/equipment_slot.gd")

const _EMPTY_TEXT: String = "—"
const _CHARGED_TEXT: String = "⚡ Charged"
const _UNCHARGED_TEXT: String = "○ Uncharged"

## slot (int) -> Label — the row's item-display Label, one per
## EquipmentSlot.ALL_SLOTS entry. Built once (see _build_rows()); never
## created/destroyed again by setup()/clear().
var _item_labels: Dictionary = {}

## slot (int) -> Label — the row's charge-indicator Label.
var _charge_labels: Dictionary = {}


func _ready() -> void:
	# BUGFIX-style guard (mirrors StatusPanelView/HexGridView convention):
	# this read-only panel must never swallow clicks meant for whatever it
	# overlays, and it has no interactive rows to begin with.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_rows_built()


## setup(character) -> void — renders `character`'s currently equipped
## items: for every slot in EquipmentSlot.ALL_SLOTS, looks up
## character.get_item_in_slot(slot) (a pure Domain accessor, ADR-003) and
## displays its display_name, or "—" when the slot is empty. An equipped
## item with a non-empty prepared_spell_id also gets a charged/uncharged
## indicator reflecting its is_charged field; an item with no prepared
## spell (or an empty slot) shows no indicator. Idempotent -- safe to call
## repeatedly with the same or a different character (API contract #8).
func setup(character) -> void:
	_ensure_rows_built()
	for slot in _EquipmentSlot.ALL_SLOTS:
		var item = character.get_item_in_slot(slot) if character != null else null
		_apply_row(slot, item)


## clear() -> void — resets every row back to its empty state ("—", no
## charge indicator), discarding any item data rendered by a prior setup()
## call. Never removes/recreates row nodes.
func clear() -> void:
	_ensure_rows_built()
	for slot in _EquipmentSlot.ALL_SLOTS:
		_apply_row(slot, null)


## get_row_count() -> int — number of rendered slot rows. Always 15 (one
## per EquipmentSlot.ALL_SLOTS entry) for this panel's entire lifetime,
## including immediately after instantiation, before setup() is ever
## called.
func get_row_count() -> int:
	_ensure_rows_built()
	return _item_labels.size()


## get_row_slots() -> Array — the slot constants this panel renders, in
## the exact order they were built (EquipmentSlot.ALL_SLOTS order).
func get_row_slots() -> Array:
	_ensure_rows_built()
	return _EquipmentSlot.ALL_SLOTS.duplicate()


## get_slot_label_text(slot) -> String — the human-readable slot label
## rendered for `slot` (e.g. "Main Hand"), or "" if `slot` is not one of
## the 15 rendered rows.
func get_slot_label_text(slot: int) -> String:
	_ensure_rows_built()
	if not _item_labels.has(slot):
		return ""
	return _EquipmentSlot.slot_name(slot)


## get_item_text(slot) -> String — the currently displayed item text for
## `slot`: an equipped item's display_name, or "—" when the slot is
## empty/unrendered.
func get_item_text(slot: int) -> String:
	_ensure_rows_built()
	var label: Label = _item_labels.get(slot, null)
	return label.text if label != null else _EMPTY_TEXT


## get_charge_indicator_text(slot) -> String — "" when `slot` has no
## equipped item or its item has an empty prepared_spell_id; otherwise
## "⚡ Charged" / "○ Uncharged" reflecting the item's is_charged field.
func get_charge_indicator_text(slot: int) -> String:
	_ensure_rows_built()
	var label: Label = _charge_labels.get(slot, null)
	return label.text if label != null else ""


## has_charge_indicator(slot) -> bool — true iff `slot` currently displays
## a charged/uncharged indicator (i.e. its equipped item has a non-empty
## prepared_spell_id).
func has_charge_indicator(slot: int) -> bool:
	return get_charge_indicator_text(slot) != ""


# ── Internal helpers ─────────────────────────────────────────────────────

## _rows_container() -> Node — the "Rows" VBoxContainer declared by
## scenes/equipment_panel.tscn, when this script is running as part of
## that scene; falls back to `self` (e.g. a bare EquipmentPanelUI.new() in
## a unit test with no scene tree). Node lookups by relative path work as
## soon as the node subtree exists, independent of whether this Control
## has actually entered the SceneTree yet -- so rows can be built the
## first time they're needed, not only from _ready().
func _rows_container() -> Node:
	var container := get_node_or_null("Rows")
	return container if container != null else self


func _ensure_rows_built() -> void:
	if _item_labels.is_empty():
		_build_rows()


## _build_rows() -> void — creates the 15 row Controls (one per
## EquipmentSlot.ALL_SLOTS entry, in order), each a plain HBoxContainer of
## three Labels (slot name / item text / charge indicator). No Button, no
## input-handling Control, and no signal is ever connected on any row --
## this panel is confirmed read-only (see this file's class doc and
## tests/scene/test_equipment_panel_ui.gd's source-inspection assertion).
func _build_rows() -> void:
	var container: Node = _rows_container()
	for slot in _EquipmentSlot.ALL_SLOTS:
		var row := HBoxContainer.new()
		row.name = "Row_%d" % slot
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var slot_label := Label.new()
		slot_label.name = "SlotLabel"
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_label.text = _EquipmentSlot.slot_name(slot)
		row.add_child(slot_label)

		var item_label := Label.new()
		item_label.name = "ItemLabel"
		item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_label.text = _EMPTY_TEXT
		row.add_child(item_label)

		var charge_label := Label.new()
		charge_label.name = "ChargeLabel"
		charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charge_label.text = ""
		row.add_child(charge_label)

		container.add_child(row)

		_item_labels[slot] = item_label
		_charge_labels[slot] = charge_label


## _apply_row(slot, item) -> void — renders `item` (an ItemResource, or
## null for an empty slot) onto `slot`'s already-built row Labels. Pure
## presentation logic: reads item.display_name / item.prepared_spell_id /
## item.is_charged, never mutates the item.
func _apply_row(slot: int, item) -> void:
	var item_label: Label = _item_labels.get(slot, null)
	var charge_label: Label = _charge_labels.get(slot, null)
	if item_label == null or charge_label == null:
		return

	if item == null:
		item_label.text = _EMPTY_TEXT
		charge_label.text = ""
		return

	item_label.text = item.display_name
	if item.prepared_spell_id != "":
		charge_label.text = _CHARGED_TEXT if item.is_charged else _UNCHARGED_TEXT
	else:
		charge_label.text = ""
