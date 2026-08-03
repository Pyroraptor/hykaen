## presentation/rest_panel_controller.gd — RestPanelController (FEAT-008 /
## US-007, FEAT-009 / US-008, and FEAT-010 / US-009; FR-009/FR-010/FR-011;
## iteration AB-0, rest mechanics steel thread).
##
## Presentation layer (Clean Architecture, ADR-001): renders the Rest Panel
## opened from ExplorationHUD's Rest Button (presentation/exploration_hud.gd,
## FEAT-007). FEAT-008 implemented the Short Rest half of the panel
## (US-007) — per-member HP/Stamina rows with a "[+1 Heal]" button, and
## discharged-item rows (Mage-paradigm members) with a "[Rech]" button.
## FEAT-009 (US-008; this feature) adds the Long Rest half: a Short Rest /
## Long Rest tab toggle (MODE_SHORT_REST / MODE_LONG_REST below) and, in
## Long Rest mode, a "Confirm Long Rest" button that invokes LongRestUseCase
## over the FULL `_party` — unlike a Short Rest action, a successful Long
## Rest confirmation closes the panel (design notes' architecture section 4
## / api_contracts #2).
##
## Every action button routes through core/api/rest_action_guard.gd's
## RestActionGuard rather than calling ShortRestHealUseCase /
## ShortRestMageRechargeUseCase / LongRestUseCase directly (design notes'
## architecture section 3 / api_contracts #1) — the guard independently
## re-checks the current game mode immediately before any use-case call, so
## this controller never needs to duplicate that check itself.
##
## Belt-and-braces error handling (design notes' error_handling section):
## a button's disabled state is a UI nicety computed from the currently
## RENDERED Combatant/item snapshot; the actual button handler does NOT
## trust that disabled state — it always invokes the guard/use case, which
## independently validates every precondition and performs NO mutation on
## failure (ADR: "atomic execute()"). This means even a stale/forced press
## (e.g. a test emitting `pressed` directly on a disabled Button, bypassing
## the engine's own click-suppression) is always safe.
##
## Re-render contract: after EVERY successful or failed Short Rest action,
## the panel re-renders from the just-returned Dictionary + live Combatant/
## item state, and stays open — closing the panel is never a side effect of
## a Short Rest action (US-007 / FEAT-008 test_criteria). A Long Rest
## confirmation ALSO re-renders first (so the fully-restored state is
## reflected in the panel's public getters immediately beforehand — FEAT-009
## test_criteria #3), then closes ONLY on success (test_criteria #4); a
## guard-blocked Long Rest confirmation re-renders (a no-op re-render, since
## nothing mutated) and stays open, mirroring a rejected Short Rest action.
##
## Row identity: a party member's row is addressed by its position (index)
## in the `party` Array passed to open() — mirrors this codebase's existing
## duck-typed "Array of combatant-shaped objects" convention (LongRestUseCase
## .execute(), ExplorationHUD.needs_rest()) rather than requiring every
## combatant to carry a populated combatant_id. A discharged-item row within
## a member's row is addressed by the item reference itself (Dictionary keys
## support Object identity in GDScript), since a member's equipped_items
## list has no separate stable item-index contract.
class_name RestPanelController
extends Control

const RestActionGuardClass = preload("res://core/api/rest_action_guard.gd")
const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")
const ShortRestHealUseCaseClass = preload("res://core/application/use_cases/short_rest_heal_use_case.gd")
const ShortRestMageRechargeUseCaseClass = preload("res://core/application/use_cases/short_rest_mage_recharge_use_case.gd")
const LongRestUseCaseClass = preload("res://core/application/use_cases/long_rest_use_case.gd")

## Rest Panel modes (design notes' architecture section 4: "owns its own
## open/closed toggle state ... defaults to Short Rest mode on open").
## MODE_SHORT_REST renders per-member Heal/Recharge action rows (FEAT-008);
## MODE_LONG_REST renders the SAME read-only per-member rows plus the
## "Confirm Long Rest" button (FEAT-009) — switched between via the
## Short Rest / Long Rest tab buttons wired in _ready().
const MODE_SHORT_REST: int = 0
const MODE_LONG_REST: int = 1

const HEAL_BUTTON_TEXT: String = "[+1 Heal]"
const RECHARGE_BUTTON_TEXT: String = "[Rech]"
const CONFIRM_LONG_REST_BUTTON_TEXT: String = "Confirm Long Rest"

## The live party this panel renders — duck-typed entries (real
## core/domain/combatant.gd Combatant instances in production; plain
## test doubles in tests), mirroring ExplorationHUD's `_party` convention.
## Never reassigned except by open().
var _party: Array = []

## Pure UI state (ADR-006): whether the panel is currently open. Toggled
## ONLY by open()/close() — a Short Rest action never touches this.
var _is_open: bool = false

## Current tab/mode (see MODE_SHORT_REST/MODE_LONG_REST above). Reset to
## MODE_SHORT_REST every time open() is called.
var _mode: int = MODE_SHORT_REST

var _game_mode_reader = GameModeReaderClass.new()

## The current game mode, resolved through the SAME shared GameModeReader
## ExplorationHUD/RestActionGuard already use (RISK-007 mitigation) —
## defaults to EXPLORATION so a panel driven with no explicit
## set_game_mode() call (e.g. most of this feature's own tests) behaves as
## if opened from exploration, matching how the panel can only be reached
## in the first place (the Rest Button is hidden in COMBAT).
var _game_mode: int = GameModeReaderClass.EXPLORATION

var _guard = RestActionGuardClass.new()
var _heal_use_case = ShortRestHealUseCaseClass.new()
var _recharge_use_case = ShortRestMageRechargeUseCaseClass.new()
var _long_rest_use_case = LongRestUseCaseClass.new()

## The most recent action's returned Dictionary (guard-wrapped use-case
## result), for callers/tests that want to branch on it directly rather
## than re-deriving state from the re-rendered rows. {} before any action.
var _last_action_result: Dictionary = {}

## member_index -> {"heal_button": Button, "info_label": Label,
## "item_rows": Array of {"item": <duck-typed item>, "button": Button,
## "label": Label}}. Rebuilt wholesale by every _render() call.
var _rows: Array = []

@onready var _members_container: VBoxContainer = $MembersContainer
@onready var _short_rest_tab_button: Button = $TabsContainer/ShortRestTabButton
@onready var _long_rest_tab_button: Button = $TabsContainer/LongRestTabButton
@onready var _confirm_long_rest_button: Button = $ConfirmLongRestButton
@onready var _close_button: Button = $CloseButton


func _ready() -> void:
	visible = _is_open
	_short_rest_tab_button.pressed.connect(_on_short_rest_tab_pressed)
	_long_rest_tab_button.pressed.connect(_on_long_rest_tab_pressed)
	_confirm_long_rest_button.text = CONFIRM_LONG_REST_BUTTON_TEXT
	_confirm_long_rest_button.pressed.connect(_on_confirm_long_rest_pressed)
	_close_button.pressed.connect(_on_close_button_pressed)
	_update_mode_visibility()


## open(party, game_mode = null) -> void — (re)opens the panel against
## `party`, always resetting to Short Rest mode (design notes' architecture
## section 4). `game_mode`, when supplied, is forwarded to set_game_mode()
## so RestActionGuard's out-of-combat check reflects the panel's actual
## opening context; omitted, the previously-set (or default EXPLORATION)
## game mode is kept.
func open(party: Array, game_mode = null) -> void:
	_party = party
	if game_mode != null:
		set_game_mode(game_mode)
	_mode = MODE_SHORT_REST
	_is_open = true
	visible = true
	_render()


## close() -> void — closes the panel. Never called by a Short Rest action
## (US-007's "panel stays open" contract). Called automatically by
## _on_confirm_long_rest_pressed() on a successful Long Rest confirmation
## (FEAT-009 / US-008 test_criteria #4). Also the target of the explicit ✕
## Close Button (FEAT-010 / US-009 / ADR-006, wired in _ready()) and of
## toggle_open() below — a safe no-op when already closed (idempotent).
func close() -> void:
	_is_open = false
	visible = false


func is_open() -> bool:
	return _is_open


## toggle_open(party, game_mode = null) -> void — FEAT-010 (US-009; FR-011;
## ADR-006): the panel's own open/closed TOGGLE, driven by ExplorationHUD's
## Rest Button (presentation/exploration_hud.gd's set_rest_panel() wiring).
## Closed -> open() against `party` (re-render from current state, always
## resetting to Short Rest mode per open()'s own contract); already open ->
## close(). This is the ONLY place a "press the same button again to close"
## decision is made, and it is made entirely from this controller's own
## `_is_open` field (ADR-006: pure UI state, never read from or written to
## any Combatant/domain/application object).
func toggle_open(party: Array, game_mode = null) -> void:
	if _is_open:
		close()
	else:
		open(party, game_mode)


## get_mode() -> int — the currently active tab (MODE_SHORT_REST /
## MODE_LONG_REST). Always MODE_SHORT_REST immediately after open().
func get_mode() -> int:
	return _mode


## get_short_rest_tab_button() -> Button — the "Short Rest" tab/toggle
## Button; pressing it switches the panel to MODE_SHORT_REST.
func get_short_rest_tab_button() -> Button:
	return _short_rest_tab_button


## get_long_rest_tab_button() -> Button — the "Long Rest" tab/toggle Button;
## pressing it switches the panel to MODE_LONG_REST.
func get_long_rest_tab_button() -> Button:
	return _long_rest_tab_button


## get_confirm_long_rest_button() -> Button — the "Confirm Long Rest"
## Button. Only `.visible` while the panel is in MODE_LONG_REST (see
## _update_mode_visibility()); its `pressed` signal is connected regardless
## of mode, mirroring every other action button's "handler never trusts
## disabled/visible state" discipline (file header).
func get_confirm_long_rest_button() -> Button:
	return _confirm_long_rest_button


## get_close_button() -> Button — the rendered explicit ✕ Close Button
## (FEAT-010 / US-009). Pressing it always closes the panel (see
## _on_close_button_pressed()), regardless of which tab/mode is currently
## active — unlike open()/close(), it does not depend on `_mode` at all.
func get_close_button() -> Button:
	return _close_button


## set_game_mode(mode) -> void — resolves `mode` through the shared
## GameModeReader (see core/api/game_mode_reader.gd's own duck-typed
## contract) and stores it as the game mode RestActionGuard.invoke() checks
## on every subsequent action.
func set_game_mode(mode) -> void:
	_game_mode = _game_mode_reader.read(mode)


## get_member_count() -> int — number of currently rendered party-member
## rows.
func get_member_count() -> int:
	return _rows.size()


## get_info_text(member_index) -> String — the exact text rendered on
## `member_index`'s HP/Stamina Label, or "" for an out-of-range index.
func get_info_text(member_index: int) -> String:
	var label: Label = _row_field(member_index, "info_label")
	return label.text if label != null else ""


## get_heal_button(member_index) -> Button — the rendered "[+1 Heal]"
## Button for `member_index`, or null for an out-of-range index.
func get_heal_button(member_index: int) -> Button:
	return _row_field(member_index, "heal_button")


## get_recharge_item_count(member_index) -> int — number of currently
## rendered discharged-item rows for `member_index` (0 for a non-Mage
## member, or a Mage member with every dischargeable item already charged).
func get_recharge_item_count(member_index: int) -> int:
	var item_rows: Array = _row_field(member_index, "item_rows")
	return item_rows.size() if item_rows != null else 0


## get_recharge_items(member_index) -> Array — the item references
## currently rendered as discharged-item rows for `member_index`, in
## render order.
func get_recharge_items(member_index: int) -> Array:
	var item_rows: Array = _row_field(member_index, "item_rows")
	if item_rows == null:
		return []
	var items: Array = []
	for row in item_rows:
		items.append(row["item"])
	return items


## get_recharge_button(member_index, item) -> Button — the rendered
## "[Rech]" Button for `item` within `member_index`'s discharged-item rows,
## or null when `item` currently has no rendered row (out-of-range index,
## unknown item, or an item that is not/no-longer discharged-and-
## dischargeable).
func get_recharge_button(member_index: int, item) -> Button:
	var item_rows: Array = _row_field(member_index, "item_rows")
	if item_rows == null:
		return null
	for row in item_rows:
		if row["item"] == item:
			return row["button"]
	return null


## get_last_action_result() -> Dictionary — the Dictionary returned by the
## most recently invoked action (already passed through RestActionGuard),
## or {} if no action has been performed yet.
func get_last_action_result() -> Dictionary:
	return _last_action_result


# ── Internal: rendering ─────────────────────────────────────────────────────

func _row_field(member_index: int, field: String):
	if member_index < 0 or member_index >= _rows.size():
		return null
	return _rows[member_index].get(field, null)


## _render() -> void — rebuilds every member row from the CURRENT `_party`
## state (live Combatant/item field reads). Called once by open() and again
## after every action, per this feature's "re-renders from the just-returned
## Dictionary + live Combatant state after each action" contract.
func _render() -> void:
	_clear_rows()
	for index in range(_party.size()):
		_build_row(index, _party[index])
	_update_mode_visibility()


## _update_mode_visibility() -> void — toggles which controls are visible
## for the CURRENT `_mode` (FEAT-009): the "Confirm Long Rest" button is
## visible ONLY in MODE_LONG_REST; each row's Short-Rest-only action buttons
## ("[+1 Heal]" / "[Rech]") are visible ONLY in MODE_SHORT_REST. This is a
## display-only toggle (mirrors the file header's "disabled state is a UI
## nicety" discipline) — it never disconnects a signal or alters use-case
## routing, so RestActionGuard remains the single place any precondition is
## actually enforced.
func _update_mode_visibility() -> void:
	var long_rest_active: bool = _mode == MODE_LONG_REST
	_confirm_long_rest_button.visible = long_rest_active
	for row in _rows:
		row["heal_button"].visible = not long_rest_active
		for item_row in row["item_rows"]:
			item_row["button"].visible = not long_rest_active


## _clear_rows() -> void — detaches (remove_child, NOT a synchronous free())
## every previously-built row container immediately, then queue_frees it.
## Detaching immediately (rather than only queue_free()-ing, which merely
## schedules removal for the next idle frame) guarantees `_members_container`
## has zero stale children the instant a fresh _render() starts building
## new rows — otherwise two successive same-frame renders (e.g. several
## rapid button presses in one test/frame) would leave duplicate old+new
## rows visible until the deferred frees actually ran. Using queue_free()
## (rather than an immediate free()) for the actual deallocation keeps this
## safe to call from INSIDE a row Button's own `pressed` handler -- freeing
## a Node synchronously while it is still emitting one of its own signals is
## unsafe; queue_free() defers that destruction to a safe point.
func _clear_rows() -> void:
	for child in _members_container.get_children():
		_members_container.remove_child(child)
		child.queue_free()
	_rows.clear()


func _build_row(index: int, combatant) -> void:
	var row_container := VBoxContainer.new()
	row_container.name = "Member_%d" % index
	_members_container.add_child(row_container)

	var info_label := Label.new()
	info_label.name = "InfoLabel"
	row_container.add_child(info_label)

	var hp_current: int = int(_duck_get(combatant, "hp_current", 0))
	var hp_max: int = int(_duck_get(combatant, "hp_max", 0))
	var stamina: int = int(_duck_get(combatant, "stamina", 0))
	var name_text: String = String(_duck_get(combatant, "name", ""))
	var budget_remaining: int = int(_duck_get(combatant, "mage_recharge_budget_remaining", 0))
	info_label.text = "%s — HP %d/%d | Stamina %d | Budget %d" % [name_text, hp_current, hp_max, stamina, budget_remaining]

	var heal_button := Button.new()
	heal_button.name = "HealButton"
	heal_button.text = HEAL_BUTTON_TEXT
	heal_button.disabled = stamina == 0 or hp_current == hp_max
	row_container.add_child(heal_button)
	heal_button.pressed.connect(_on_heal_pressed.bind(index))

	var item_rows: Array = []
	var equipped_items: Array = _duck_get(combatant, "equipped_items", [])
	for item in equipped_items:
		if item == null:
			continue
		var is_charged: bool = bool(_duck_get(item, "is_charged", true))
		var energy_cost: int = int(_duck_get(item, "energy_cost", 0))
		# Discharged-item row contract (US-007): rendered ONLY for a
		# currently-discharged, dischargeable item — mirrors
		# ShortRestMageRechargeUseCase's own precondition shape (an
		# already-charged or never-dischargeable item has nothing
		# actionable to offer here).
		if is_charged or energy_cost <= 0:
			continue

		var item_row := HBoxContainer.new()
		item_row.name = "Item_%d" % item_rows.size()
		row_container.add_child(item_row)

		var item_label := Label.new()
		item_label.name = "ItemLabel"
		var item_name: String = String(_duck_get(item, "display_name", String(_duck_get(item, "item_id", "Item"))))
		item_label.text = item_name
		item_row.add_child(item_label)

		var recharge_button := Button.new()
		recharge_button.name = "RechargeButton"
		recharge_button.text = RECHARGE_BUTTON_TEXT
		recharge_button.disabled = budget_remaining == 0
		item_row.add_child(recharge_button)
		recharge_button.pressed.connect(_on_recharge_pressed.bind(index, item))

		item_rows.append({"item": item, "label": item_label, "button": recharge_button})

	_rows.append({
		"info_label": info_label,
		"heal_button": heal_button,
		"item_rows": item_rows,
	})


# ── Internal: action handlers ───────────────────────────────────────────────

func _on_heal_pressed(member_index: int) -> void:
	if member_index < 0 or member_index >= _party.size():
		return
	var combatant = _party[member_index]
	var use_case = _heal_use_case
	_last_action_result = _guard.invoke(_game_mode, func(): return use_case.execute(combatant, 1))
	if _is_open:
		_render()


func _on_recharge_pressed(member_index: int, item) -> void:
	if member_index < 0 or member_index >= _party.size():
		return
	var combatant = _party[member_index]
	var use_case = _recharge_use_case
	_last_action_result = _guard.invoke(_game_mode, func(): return use_case.execute(combatant, item))
	if _is_open:
		_render()


## _on_short_rest_tab_pressed() / _on_long_rest_tab_pressed() -> void — the
## Short Rest / Long Rest tab toggle (FEAT-009 test_criteria #1). A pure UI
## mode switch: no use case is invoked, no guard check happens — only
## _render() (via _update_mode_visibility()) reacts to the new `_mode`.
func _on_short_rest_tab_pressed() -> void:
	_mode = MODE_SHORT_REST
	_render()


func _on_long_rest_tab_pressed() -> void:
	_mode = MODE_LONG_REST
	_render()


## _on_close_button_pressed() -> void — FEAT-010 (US-009; test_criteria #3):
## the explicit ✕ Close Button always closes the panel, independent of
## `_mode` or prior open state — no guard/use-case call, no re-render (a
## closed panel has nothing to render).
func _on_close_button_pressed() -> void:
	close()


## _on_confirm_long_rest_pressed() -> void — FEAT-009 (US-008; FR-010):
## invokes LongRestUseCase, via RestActionGuard, against the FULL `_party`
## (api_contracts #2 / test_criteria #2). Mirrors _on_heal_pressed()'s /
## _on_recharge_pressed()'s "re-render from the just-returned Dictionary +
## live Combatant/item state" contract FIRST (test_criteria #3: every
## restored field must be reflected in the rendered UI immediately before
## close) -- close() is called ONLY when the guard/use case reports success
## (test_criteria #4); a guard-blocked confirmation (COMBAT mode) re-renders
## a no-op (nothing mutated) and leaves the panel open, mirroring a rejected
## Short Rest action.
func _on_confirm_long_rest_pressed() -> void:
	var use_case = _long_rest_use_case
	var party = _party
	_last_action_result = _guard.invoke(_game_mode, func(): return use_case.execute(party))
	if _is_open:
		_render()
	if bool(_last_action_result.get("success", false)):
		close()


# ── Internal helpers ─────────────────────────────────────────────────────

## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established throughout this iteration (LongRestUseCase
## ._duck_get() / ShortRestHealUseCase._duck_get() / ExplorationHUD
## ._duck_get()): tolerates `obj` being a Dictionary (`.get(key, default)`),
## an Object exposing `key` as a real property (`Object.get(key)`, itself
## null-safe for an undeclared property), or null (falls back to
## `default`) — never raises.
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
