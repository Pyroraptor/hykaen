extends GutTest
## tests/scene/test_main_scene_equipment_toggle.gd — FEAT-010 (US-011 /
## FR-010, resolves RISK-007 via a dedicated negative-case test).
##
## Covers MainScene.gd's newly-added 'E' key toggle for the FEAT-009
## EquipmentPanelUI (presentation/equipment_panel_ui.gd + scenes/
## equipment_panel.tscn), instantiated hidden under $UILayer by
## MainScene.tscn. Boots the REAL res://MainScene.tscn composition root
## headless, pinned to the prologue fixture's known-good seed (mirrors this
## project's established `_boot_main_scene()`/PROLOGUE_SEED convention —
## e.g. tests/unit/test_main_scene_canvas_layer_panels.gd,
## tests/unit/test_main_scene_panel_wiring_regression.gd), and drives the
## 'E' key exactly as MainScene._unhandled_input() consumes it (a real
## InputEventKey handed directly to _unhandled_input(), mirroring
## tests/gut/test_cancel_controller_integration.gd's identical
## Esc-key-as-a-direct-InputEventKey convention for the sibling Esc/
## right-click affordance).
##
## test_criteria covered:
##   1. test_equipment_panel_is_hidden_immediately_after_main_scene_loads()
##   2. test_pressing_e_with_selected_party_member_opens_panel_via_setup()
##   3. test_pressing_e_again_while_open_closes_it_and_calls_clear()
##   4. test_pressing_e_with_no_party_member_selected_is_a_noop()
##      (RISK-007's dedicated negative-case/null-dereference-prevention
##      test — no party member selected must never crash and must leave the
##      panel hidden.)

const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42

## The prologue party's first member (data/parties/default_party.tres /
## data/encounters/prologue_encounter.tres both author titus.tres first),
## whose combatant_id is "player_0" (infrastructure/
## resource_encounter_repository.gd's "%s_%d" % [team.to_lower(), i]
## convention) and which ExplorationModeController.boot() auto-selects by
## default (see that file's own "default selected_party_member_id to the
## FIRST seeded party member" doc) — so a fresh boot already has Titus
## selected with no test-side selection step required.
const TITUS_MAIN_HAND_ITEM_NAME: String = "Titus's Longsword"
const TITUS_OFF_HAND_ITEM_NAME: String = "Titus's Shield"


func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


## _boot_main_scene() -- instantiates the REAL res://MainScene.tscn
## composition root, pinned to PROLOGUE_SEED, and lets EXPLORATION-mode
## boot() run to completion (one process_frame). Never drives
## _on_combat_triggered() — this feature's own player-facing entry point
## ("press E to open a read-only equipment panel") is exercised in
## EXPLORATION mode, mirroring tests/unit/test_main_scene_canvas_layer_panels.gd's
## identical "boot only, no combat handoff" convention.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return null
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


## _make_e_key_event() -- a fresh (non-echo), pressed 'E' InputEventKey,
## mirroring tests/gut/test_cancel_controller_integration.gd's
## _make_esc_event()/_make_right_click_event() convention for the sibling
## Esc/right-click affordance.
func _make_e_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	return event


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — EquipmentPanelUI is hidden immediately after MainScene loads.
# ══════════════════════════════════════════════════════════════════════════

func test_equipment_panel_is_hidden_immediately_after_main_scene_loads() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_not_null(
		instance.equipment_panel_ui,
		"MainScene must expose a non-null equipment_panel_ui after boot"
	)
	if instance.equipment_panel_ui == null:
		return

	assert_false(
		instance.equipment_panel_ui.visible,
		"EquipmentPanelUI must be hidden immediately after MainScene boots"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — selecting a party member + pressing 'E' opens the panel,
# populated via setup() with that member's equipped items.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_e_with_selected_party_member_opens_panel_via_setup() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	# ExplorationModeController.boot() auto-selects the first party member
	# (Titus, "player_0") by default -- no explicit selection step needed.
	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"boot() must auto-select the first party member (Titus) by default"
	)

	instance._unhandled_input(_make_e_key_event())

	assert_true(
		instance.equipment_panel_ui.visible,
		"pressing 'E' with a party member selected must open (show) the equipment panel"
	)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME,
		"panel must be populated via setup() with the selected member's MAIN_HAND item"
	)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.OFF_HAND), TITUS_OFF_HAND_ITEM_NAME,
		"panel must be populated via setup() with the selected member's OFF_HAND item"
	)


func test_pressing_e_after_selecting_a_different_party_member_reflects_that_selection() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	# Marigold is the prologue party's second member ("player_1"). Selecting
	# her directly (mirroring this codebase's established test convention of
	# writing straight to ExplorationModeController's own settable public
	# field) proves setup() renders whichever member is CURRENTLY selected,
	# not merely a hardcoded first-party-member assumption.
	instance._exploration.selected_party_member_id = "player_1"

	instance._unhandled_input(_make_e_key_event())

	assert_true(instance.equipment_panel_ui.visible)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), "Marigold's Shortsword",
		"panel must reflect the CURRENTLY selected party member's own equipped items"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — pressing 'E' again while open closes it and calls clear().
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_e_again_while_open_closes_it_and_calls_clear() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	instance._unhandled_input(_make_e_key_event())
	assert_true(instance.equipment_panel_ui.visible, "panel must be open after the first 'E' press")

	instance._unhandled_input(_make_e_key_event())

	assert_false(
		instance.equipment_panel_ui.visible,
		"pressing 'E' again while open must close (hide) the panel"
	)
	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(
			instance.equipment_panel_ui.get_item_text(slot), "—",
			"clear() must reset every row back to '—' when the panel is closed"
		)
		assert_false(
			instance.equipment_panel_ui.has_charge_indicator(slot),
			"clear() must remove any charge indicator when the panel is closed"
		)


func test_pressing_e_three_times_reopens_the_panel_correctly() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	instance._unhandled_input(_make_e_key_event())  # open
	instance._unhandled_input(_make_e_key_event())  # close
	instance._unhandled_input(_make_e_key_event())  # open again

	assert_true(instance.equipment_panel_ui.visible, "a third 'E' press must re-open the panel")
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME,
		"re-opening must re-render the currently selected member's equipped items"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (RISK-007) — pressing 'E' with no party member selected is a
# no-op: panel remains hidden, no error/crash occurs.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_e_with_no_party_member_selected_is_a_noop() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	# Clear the exploration-mode selection entirely -- the "no party member
	# selected" precondition US-011 requires this handler to guard against
	# (the primary null-dereference-prevention input-validation surface per
	# this feature's design notes' security section).
	instance._exploration.selected_party_member_id = ""

	instance._unhandled_input(_make_e_key_event())

	assert_false(
		instance.equipment_panel_ui.visible,
		"pressing 'E' with no party member selected must be a no-op -- the panel must stay hidden"
	)
	assert_false(
		instance.equipment_panel_toggle_controller.is_open(),
		"pressing 'E' with no party member selected must not flip the open/closed toggle state"
	)


func test_pressing_e_with_no_selection_does_not_crash_and_a_later_valid_press_still_works() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	instance._exploration.selected_party_member_id = ""
	instance._unhandled_input(_make_e_key_event())
	assert_false(instance.equipment_panel_ui.visible)

	# Re-select a party member afterward: the earlier no-op 'E' press must
	# not have left the toggle state corrupted (e.g. stuck "open" with
	# nothing rendered) -- a subsequent valid press must still open normally.
	instance._exploration.selected_party_member_id = "player_0"
	instance._unhandled_input(_make_e_key_event())

	assert_true(
		instance.equipment_panel_ui.visible,
		"a valid 'E' press after an earlier no-selection no-op must still open the panel"
	)
	assert_eq(instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME)
