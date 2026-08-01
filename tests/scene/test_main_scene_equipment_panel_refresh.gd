extends GutTest
## tests/scene/test_main_scene_equipment_panel_refresh.gd — FEAT-365 (US-011
## / FR-011, resolves peer-review BLOCKER PR-001).
##
## Closes the gap called out in prior peer review: FEAT-010 wired the 'E' key
## open/close toggle for the read-only EquipmentPanelUI (FEAT-009), but
## MainScene._on_active_actor_changed() never touched the panel at all, so a
## panel left open while browsing one party member's gear would silently show
## STALE data once combat moved on to a different actor's turn (or an enemy's
## turn). This suite covers this feature's own test_criteria:
##
##   1. Panel open + active actor changes to a DIFFERENT player-team party
##      member -> panel refreshes via setup(new_actor), rendering the newly
##      active member's own equipped_items instead of the previous member's.
##   2. Panel open + active actor changes to a non-player-team actor (enemy
##      turn) -> panel auto-hides AND clear() is called, leaving no leftover
##      row data from whoever was previously displayed.
##   3. Panel already closed/hidden -> _on_active_actor_changed() (player or
##      enemy) must NOT auto-open it.
##   4. _on_active_actor_changed(null) is a no-op: panel visibility/row state
##      unchanged, no crash.
##   5. FEAT-010's pre-existing 'E'-key toggle tests
##      (tests/scene/test_main_scene_equipment_toggle.gd) continue to pass
##      unmodified (verified by running the full suite, not duplicated here).
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless,
## pinned to the prologue fixture's PROLOGUE_SEED, mirroring both
## tests/scene/test_main_scene_equipment_toggle.gd's 'E'-key-open convention
## AND tests/integration/test_active_actor_selection.gd's "drive
## _on_active_actor_changed() directly with real, live Combatant instances
## drawn from the booted instance's own `_party`/`_enemies` arrays" technique
## (TurnController's own auto-drive loop never emits mid-Enemy-run, so this is
## the deterministic way to exercise an enemy-turn transition).

const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant, and tests/scene/test_main_scene_equipment_toggle.gd's own
## use of it).
const PROLOGUE_SEED: int = 42

const TITUS_MAIN_HAND_ITEM_NAME: String = "Titus's Longsword"
const MARIGOLD_MAIN_HAND_ITEM_NAME: String = "Marigold's Shortsword"


func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


## _boot_main_scene() -- instantiates the REAL res://MainScene.tscn
## composition root, pinned to PROLOGUE_SEED, and drives the real
## exploration->combat handoff via _on_combat_triggered("prologue")
## (mirrors tests/integration/test_active_actor_selection.gd's identical
## boot convention) so a live 'enemy_0' (Skeleton) is seated in `_enemies`
## for this feature's enemy-turn criteria. The 'E' key toggle and this
## feature's refresh/auto-close reaction both work off `_party`/
## `scenario_session`, which stay live and unchanged in shape across the
## EXPLORATION->COMBAT handoff (exploration.selected_party_member_id is
## untouched by the handoff, per tests/scene/test_main_scene_equipment_toggle.gd's
## own "player_0" auto-selection assumption still holding after boot).
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

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _make_e_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	return event


## _find_combatant_by_id(instance, combatant_id) -> Combatant or null.
## Mirrors tests/integration/test_active_actor_selection.gd's identical
## helper -- `_party` and `_enemies` are populated at boot even in
## EXPLORATION mode (session.get("party", []) at _ready()-time).
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _open_panel_on_titus(instance) -> void — opens the panel via the real 'E'
## key path with Titus ("player_0") selected, the same auto-selected-by-
## default party member tests/scene/test_main_scene_equipment_toggle.gd
## relies on.
func _open_panel_on_titus(instance) -> void:
	assert_eq(instance._exploration.selected_party_member_id, "player_0")
	instance._unhandled_input(_make_e_key_event())
	assert_true(instance.equipment_panel_ui.visible, "fixture assumption: 'E' with Titus selected opens the panel")
	assert_eq(instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — panel open + active actor changes to a DIFFERENT player-team
# party member -> refreshed via setup(new_actor).
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_change_to_different_player_team_member_refreshes_panel_via_setup() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	_open_panel_on_titus(instance)

	var marigold = _find_combatant_by_id(instance, "player_1")
	assert_not_null(marigold, "fixture assumption: default_party.tres seats 'player_1' (Marigold)")
	assert_false(marigold.is_enemy, "fixture assumption: 'player_1' is on the Player team")

	instance._on_active_actor_changed(marigold)

	assert_true(
		instance.equipment_panel_ui.visible,
		"the panel must stay OPEN when the active actor changes to another player-team member"
	)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), MARIGOLD_MAIN_HAND_ITEM_NAME,
		"the panel must be refreshed via setup(marigold) -- Marigold's own MAIN_HAND item, not Titus's"
	)
	assert_true(
		instance.equipment_panel_toggle_controller.is_open(),
		"the panel's open/closed toggle state must remain OPEN after a refresh"
	)


func test_active_actor_change_to_same_player_actor_still_refreshes_via_setup() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	_open_panel_on_titus(instance)

	var titus = _find_combatant_by_id(instance, "player_0")
	assert_not_null(titus, "fixture assumption: default_party.tres seats 'player_0' (Titus)")

	instance._on_active_actor_changed(titus)

	assert_true(instance.equipment_panel_ui.visible, "the panel must remain open")
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME,
		"re-affirming the same active player actor must still render that actor's own gear"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — panel open + active actor changes to a non-player-team actor
# -> auto-hides AND clear() is called (no leftover row data).
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_change_to_enemy_hides_panel_and_clears_rows() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	_open_panel_on_titus(instance)

	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	assert_not_null(enemy_actor, "fixture assumption: prologue_encounter.tres seats a live 'enemy_0' (Skeleton)")
	assert_true(enemy_actor.is_enemy, "fixture assumption: 'enemy_0' is on the Enemy team")

	instance._on_active_actor_changed(enemy_actor)

	assert_false(
		instance.equipment_panel_ui.visible,
		"the panel must auto-hide when the active actor becomes a non-player-team actor"
	)
	assert_false(
		instance.equipment_panel_toggle_controller.is_open(),
		"the toggle controller's open/closed state must flip to CLOSED on an enemy turn"
	)
	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(
			instance.equipment_panel_ui.get_item_text(slot), "—",
			"clear() must reset every row back to '—' -- no leftover gear data from Titus (slot %d)" % slot
		)
		assert_false(
			instance.equipment_panel_ui.has_charge_indicator(slot),
			"clear() must remove any charge indicator left over from Titus (slot %d)" % slot
		)


func test_active_actor_change_to_enemy_then_back_to_player_reopens_via_e_key() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	_open_panel_on_titus(instance)

	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	instance._on_active_actor_changed(enemy_actor)
	assert_false(instance.equipment_panel_ui.visible, "sanity check: the enemy turn auto-closed the panel")

	# A subsequent player active-actor change must NOT itself re-open the
	# panel (criterion 3) -- but the ordinary 'E' key affordance must still
	# work normally afterward, proving the auto-close left no corrupted state.
	var titus = _find_combatant_by_id(instance, "player_0")
	instance._on_active_actor_changed(titus)
	assert_false(
		instance.equipment_panel_ui.visible,
		"an active-actor change to a player must not, by itself, re-open an already-closed panel"
	)

	instance._unhandled_input(_make_e_key_event())
	assert_true(instance.equipment_panel_ui.visible, "the 'E' key must still open the panel normally afterward")
	assert_eq(instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — panel already closed/hidden -> _on_active_actor_changed()
# does NOT auto-open it, for either a player or an enemy actor.
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_change_with_panel_closed_does_not_auto_open_for_player_actor() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_false(instance.equipment_panel_ui.visible, "fixture assumption: the panel starts closed/hidden")

	var marigold = _find_combatant_by_id(instance, "player_1")
	instance._on_active_actor_changed(marigold)

	assert_false(
		instance.equipment_panel_ui.visible,
		"a player-team active-actor change must NOT auto-open an already-closed panel"
	)
	assert_false(instance.equipment_panel_toggle_controller.is_open())


func test_active_actor_change_with_panel_closed_does_not_auto_open_for_enemy_actor() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_false(instance.equipment_panel_ui.visible, "fixture assumption: the panel starts closed/hidden")

	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	instance._on_active_actor_changed(enemy_actor)

	assert_false(
		instance.equipment_panel_ui.visible,
		"an enemy active-actor change must NOT auto-open an already-closed panel"
	)
	assert_false(instance.equipment_panel_toggle_controller.is_open())


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — _on_active_actor_changed(null) is a no-op: panel visibility
# and row state unchanged, no error/crash occurs.
# ══════════════════════════════════════════════════════════════════════════

func test_active_actor_changed_null_with_panel_closed_is_a_noop_and_does_not_crash() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_false(instance.equipment_panel_ui.visible)

	instance._on_active_actor_changed(null)

	assert_false(
		instance.equipment_panel_ui.visible,
		"_on_active_actor_changed(null) with the panel closed must remain a no-op (still hidden)"
	)
	assert_false(instance.equipment_panel_toggle_controller.is_open())


func test_active_actor_changed_null_with_panel_open_is_a_noop_and_does_not_crash() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	_open_panel_on_titus(instance)

	instance._on_active_actor_changed(null)

	assert_true(
		instance.equipment_panel_ui.visible,
		"_on_active_actor_changed(null) with the panel open must leave it open (no visibility change)"
	)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), TITUS_MAIN_HAND_ITEM_NAME,
		"_on_active_actor_changed(null) must not alter the panel's currently rendered row data"
	)
	assert_true(instance.equipment_panel_toggle_controller.is_open())
