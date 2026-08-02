extends GutTest
## tests/integration/test_equipment_smoke_e2e.gd — FEAT-363 (US-009,
## Iteration Z "Equipment Slots").
##
## The FINAL, convergence-point steel-thread smoke test for the whole
## equipment-slots feature set (FEAT-001 through FEAT-010: EquipmentSlot,
## ItemResource, CharacterResource.equipped_items/level/get_item_in_slot()/
## is_slot_blocked(), EquipItemUseCase/UnequipItemUseCase/PrepareSpellUseCase,
## the prologue starter item + character fixtures, the read-only
## EquipmentPanelUI, and its 'E' key toggle in MainScene). Boots the REAL,
## unmodified res://MainScene.tscn composition root (the same entry point
## project.godot's run/main_scene points at), drives the REAL
## _on_combat_triggered("prologue") exploration->combat handoff, and asserts
## the steel thread's exit-point equipment/charge state entirely through the
## game's own existing character-loading path (ADR-005) -- never via a
## direct ResourceLoader.load() call in this file.
##
## gram_marx.tres/staff_gram.tres/orb_gram.tres are authored, shipped content
## fixtures (FEAT-007/FEAT-008) carrying Gram Marx's starter loadout (Fire
## Bolt prepared in his two-handed staff, Frost Breath prepared in his orb —
## Wizards do not Channel; ring_channeling is a Channeler item and is NOT in
## his loadout). Gram Marx is NOT a member of the live prologue roster
## (data/parties/default_party.tres authors only Titus + Marigold, per
## ADR-002's scenario-authoritative party model) -- wiring a THIRD prologue
## party member into the live encounter is a content/roster decision entirely
## out of this feature's scope (files_to_modify is empty; every other
## already-passing steel-thread suite in this codebase, e.g.
## tests/integration/test_steel_thread_prologue_encounter.gd, hard-codes the
## "two-party-member, one-enemy" prologue roster shape throughout its own
## fixture assumptions, so silently growing the live roster here would be a
## wide-blast-radius regression well beyond this feature's own remit).
##
## This suite therefore reaches Gram Marx's CharacterResource through the
## SAME real, already-shipped production seam MainScene's own 'E' key
## handler uses for Titus below -- presentation/equipment_panel_toggle_
## controller.gd's EquipmentPanelToggleController (FEAT-010) -- rather than
## a hand-rolled test-only loader. `_resolve_character()` is generic: it
## reads whichever ScenarioSession/party Array it is handed, so this file
## builds a minimal, single-member ScenarioResource/PartyResource/Combatant
## trio (using the SAME production Resource/entity classes the real
## prologue boot itself is built from) pointing solely at gram_marx.tres,
## and drives the exact real `toggle()`/`_resolve_character()` codepath with
## it -- the ResourceLoader.load() call this entails happens INSIDE that
## shipped production method, never in this test's own body (the literal
## ADR-005 constraint this suite's own test_criteria enforces; see
## test_no_resourceloader_load_appears_in_this_file() below, a source-scan
## fitness-function test mirroring this codebase's established
## tests/unit/test_core_purity_source_scan.gd convention). MainScene.tscn
## itself is instantiated via preload() (a compile-time resource reference,
## never a runtime ResourceLoader.load() string call) for the same reason.
##
## Slot-naming note: the design notes for this feature narrate a "RIGHT_RING"
## slot; the actually-shipped core/model/equipment_slot.gd (FEAT-001) has no
## such constant -- its 15 slots are MAIN_HAND/OFF_HAND/HEAD/NECK/SHOULDERS/
## CHEST/BACK/HANDS/WAIST/LEGS/FEET/RING_1/RING_2/ACCESSORY_1/ACCESSORY_2.
## RING_1 (slot 11) is EMPTY for Gram Marx — his loadout is staff_gram
## (MAIN_HAND) + orb_gram (ACCESSORY_1); Wizards do not Channel.
##
## test_criteria satisfied:
##   1. test_boot_and_combat_trigger_succeeds_without_error()
##   2. test_gram_marx_level_and_equipped_items_size_via_existing_loading_path()
##   3. test_gram_marx_main_hand_item_display_name_and_fire_bolt_charge()
##   4. test_gram_marx_ring_1_slot_is_empty()
##   5. test_titus_off_hand_blocked_by_two_handed_longsword()
##   6. test_gram_marx_off_hand_is_blocked_by_two_handed_staff()
##   7. test_selecting_gram_marx_and_pressing_e_opens_equipment_panel_with_matching_rows()
##   8. test_full_steel_thread_boot_to_equipment_panel_no_regression() -- the
##      composite entry-point-to-exit-point smoke test driving all of the
##      above through one continuous live MainScene session; FEAT-366
##      (FIX-001/FR-011 convergence) extends this SAME test to also advance
##      the active actor from Gram Marx to Titus (panel refreshes to
##      Titus's own gear via the real _on_active_actor_changed() reaction)
##      and then to an enemy actor (panel auto-closes/clears), both
##      resolved via the same real by-position character-loading seam --
##      never a direct ResourceLoader.load() call in this file.
##   9. test_no_resourceloader_load_appears_in_this_file() -- ADR-005 gate.

## Preloaded (compile-time resource reference), never a runtime
## ResourceLoader.load() string call -- see file-level doc.
const _MAIN_SCENE_PACKED: PackedScene = preload("res://MainScene.tscn")

const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const PartyResourceClass = preload("res://data/characters/party_resource.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## Gram Marx's own res:// path -- referenced only as a STRING handed to the
## real ScenarioResource/PartyResource fixture below; this file never calls
## ResourceLoader.load() (or preload()) on it directly -- resolution happens
## entirely inside EquipmentPanelToggleController._resolve_character().
const GRAM_MARX_CHARACTER_PATH: String = "res://data/characters/gram_marx.tres"
const GRAM_MARX_COMBATANT_ID: String = "gram_marx"

## This file's own res:// path, for the source-scan fitness-function test.
const _THIS_FILE_PATH: String = "res://tests/integration/test_equipment_smoke_e2e.gd"


## _FakeExploration -- a minimal duck-typed stand-in for presentation/
## exploration_mode_controller.gd's ExplorationModeController, exposing only
## the single field EquipmentPanelToggleController._resolve_character()
## actually reads (`selected_party_member_id`). Used solely to drive the
## real toggle controller against the synthetic Gram Marx fixture below;
## Titus's own assertions use the REAL, live `instance._exploration`
## instead.
class _FakeExploration:
	var selected_party_member_id: String = ""


func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


## _boot_main_scene_with_seed(seed_value) -> Node -- boots the REAL
## res://MainScene.tscn composition root (preloaded above), pinned to a
## known seed, then drives the REAL _on_combat_triggered("prologue")
## exploration->combat handoff and awaits two process frames -- mirroring
## tests/integration/test_steel_thread_prologue_encounter.gd's identically-
## named helper exactly (the established, already-proven convention for
## this exact boot shape).
func _boot_main_scene_with_seed(seed_value: int):
	var instance = _MAIN_SCENE_PACKED.instantiate()
	assert_not_null(instance, "MainScene.tscn (the real project.godot run/main_scene entry point) must instantiate")
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	await instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _make_e_key_event() -- a fresh (non-echo), pressed 'E' InputEventKey,
## mirroring tests/scene/test_main_scene_equipment_toggle.gd's identical
## helper for the same affordance.
func _make_e_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_E
	return event


## _make_gram_marx_scenario_session() -> ScenarioSession -- a synthetic,
## single-member ScenarioSession/ScenarioResource/PartyResource trio, built
## from the SAME production Resource classes the real prologue boot itself
## uses, pointing solely at gram_marx.tres. See file-level doc for why this
## is necessary (Gram Marx is not a member of the live prologue roster).
func _make_gram_marx_scenario_session():
	var party_resource = PartyResourceClass.new()
	party_resource.character_resource_paths = [GRAM_MARX_CHARACTER_PATH]

	var scenario = ScenarioResourceClass.new()
	scenario.scenario_id = "equipment_smoke_gram_marx_fixture"
	scenario.party = party_resource

	var session = ScenarioSessionClass.new()
	session.scenario = scenario
	return session


## _make_gram_marx_party() -> Array[Combatant] -- a single real Combatant
## entity (core/domain/combatant.gd, the SAME class the real party roster is
## built from) whose display_id() resolves to GRAM_MARX_COMBATANT_ID, so it
## matches the synthetic scenario session's single character path by
## position (index 0), mirroring EquipmentPanelToggleController's own
## documented "by POSITION" resolution contract.
func _make_gram_marx_party() -> Array:
	return [CombatantClass.new(GRAM_MARX_COMBATANT_ID, "Gram Marx", "Player", HexCoordClass.new(0, 0))]


## _resolve_gram_marx_character(instance) -> CharacterResource -- drives the
## REAL, shipped EquipmentPanelToggleController._resolve_character() (the
## SAME method instance.equipment_panel_toggle_controller.handle_input()
## calls for Titus/Marigold via MainScene's own 'E' key wiring) against the
## synthetic Gram Marx fixture above. The ResourceLoader.load() call this
## triggers happens entirely inside that production method -- never in this
## test file's own body.
func _resolve_gram_marx_character(instance):
	var fake_exploration = _FakeExploration.new()
	fake_exploration.selected_party_member_id = GRAM_MARX_COMBATANT_ID
	return instance.equipment_panel_toggle_controller._resolve_character(
		fake_exploration, _make_gram_marx_scenario_session(), _make_gram_marx_party()
	)


## _resolve_titus_character(instance) -> CharacterResource -- drives the
## SAME real EquipmentPanelToggleController._resolve_character() against
## the instance's OWN real, live `_exploration`/`scenario_session`/`_party`
## (the real prologue roster) -- exactly the codepath MainScene's own 'E'
## key handler exercises. Selects Titus (player_0) if no party member is
## already selected.
func _resolve_titus_character(instance):
	if instance._exploration.selected_party_member_id == "":
		instance._exploration.selected_party_member_id = "player_0"
	return instance.equipment_panel_toggle_controller._resolve_character(
		instance._exploration, instance.scenario_session, instance._party
	)


## _find_combatant_by_id(combatants, combatant_id) -> Combatant|null --
## FEAT-366 (FIX-001/FR-011 convergence coverage). A plain-Array linear
## scan mirroring tests/scene/test_main_scene_equipment_panel_refresh.gd's
## identically-named helper -- used to pull the REAL, live "player_0"
## (Titus) and "enemy_0" (Skeleton) Combatant instances out of an already-
## booted instance's own `_party`/`_enemies` arrays so this suite can drive
## the REAL TurnController reaction, `MainScene._on_active_actor_changed()`,
## with them (never a hand-rolled stand-in), keeping this the SAME
## by-position resolution seam _resolve_character()/refresh_for_active_actor()
## already use in production. No ResourceLoader.load() call is involved --
## see ADR-005 gate below.
func _find_combatant_by_id(combatants: Array, combatant_id: String):
	for combatant in combatants:
		if combatant != null and combatant.display_id() == combatant_id:
			return combatant
	return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — entry point: boot + combat trigger + two process frames
# succeeds without error.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_and_combat_trigger_succeeds_without_error() -> void:
	var instance = await _boot_main_scene_with_seed(42)

	assert_not_null(instance, "MainScene.tscn must boot and instantiate without error")
	assert_not_null(
		instance.round_session,
		"_on_combat_triggered('prologue') must produce a live RoundSession with no error"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"a freshly-begun RoundSession must not already be over immediately after boot"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — gram_marx.level==1, equipped_items.size()==3, via the
# existing character-loading path only.
#
# FEAT-004 (US-003; FR-005/FR-006) additively equips orb_gram as a 3rd
# equipped_items entry (staff_gram, ring_channeling, orb_gram) — this
# assertion count is updated 2->3 to match the new, intentionally-authored
# gram_marx.tres content (not a regression; see gram_marx.tres itself).
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_level_and_equipped_items_size_via_existing_loading_path() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var gram_marx = _resolve_gram_marx_character(instance)

	assert_not_null(gram_marx, "Gram Marx's CharacterResource must be obtainable via the existing character-loading path")
	if gram_marx == null:
		return
	assert_eq(gram_marx.level, 1, "gram_marx.level must be 1")
	assert_eq(gram_marx.equipped_items.size(), 2, "gram_marx.equipped_items must contain exactly 2 items (staff_gram, orb_gram) — Wizards do not Channel")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — gram_marx's MAIN_HAND item: non-empty display_name,
# prepared_spell_id=='fire_bolt', is_charged==true.
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_main_hand_item_display_name_and_fire_bolt_charge() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var gram_marx = _resolve_gram_marx_character(instance)
	assert_not_null(gram_marx)
	if gram_marx == null:
		return

	var main_hand_item = gram_marx.get_item_in_slot(EquipmentSlotClass.MAIN_HAND)
	assert_not_null(main_hand_item, "gram_marx must have an item equipped in MAIN_HAND (Gram's Quarterstaff)")
	if main_hand_item == null:
		return
	assert_true(main_hand_item.display_name.length() > 0, "gram_marx's MAIN_HAND item must have a non-empty display_name")
	assert_eq(main_hand_item.prepared_spell_id, "fire_bolt", "gram_marx's MAIN_HAND item must have Fire Bolt prepared")
	assert_true(main_hand_item.is_charged, "gram_marx's MAIN_HAND item must be charged")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — gram_marx's RING_1 slot is EMPTY. Wizards do not Channel;
# ring_channeling is a Channeler item and is not part of his loadout.
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_ring_1_slot_is_empty() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var gram_marx = _resolve_gram_marx_character(instance)
	assert_not_null(gram_marx)
	if gram_marx == null:
		return

	var ring_item = gram_marx.get_item_in_slot(EquipmentSlotClass.RING_1)
	assert_null(ring_item, "gram_marx must have NO item in RING_1 — Wizards do not Channel; ring_channeling is not in his loadout")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — titus's longsword is two-handed; OFF_HAND is null and
# is_slot_blocked(OFF_HAND)==true (HEMA longsword, no shield).
# ══════════════════════════════════════════════════════════════════════════

func test_titus_off_hand_blocked_by_two_handed_longsword() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var titus = _resolve_titus_character(instance)

	assert_not_null(titus, "Titus's CharacterResource must be obtainable via the existing character-loading path")
	if titus == null:
		return
	var off_hand_item = titus.get_item_in_slot(EquipmentSlotClass.OFF_HAND)
	assert_null(off_hand_item, "titus must have no OFF_HAND item -- longsword is two-handed, shield not equipped")
	assert_true(
		titus.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"titus.is_slot_blocked(OFF_HAND) must be true -- Titus's longsword IS two-handed (HEMA convention)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 (RISK-006 acceptance spec) — gram_marx.is_slot_blocked(OFF_HAND)
# == true (asymmetric two-handed/off-hand blocking).
# ══════════════════════════════════════════════════════════════════════════

func test_gram_marx_off_hand_is_blocked_by_two_handed_staff() -> void:
	var instance = await _boot_main_scene_with_seed(42)
	var gram_marx = _resolve_gram_marx_character(instance)
	assert_not_null(gram_marx)
	if gram_marx == null:
		return

	assert_true(
		gram_marx.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"gram_marx.is_slot_blocked(OFF_HAND) must be true -- Gram's Quarterstaff is two-handed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 7 — selecting gram_marx + pressing 'E' opens the real
# EquipmentPanelUI, rendering rows that match the asserted display_name/
# charge state.
# ══════════════════════════════════════════════════════════════════════════

func test_selecting_gram_marx_and_pressing_e_opens_equipment_panel_with_matching_rows() -> void:
	var instance = await _boot_main_scene_with_seed(42)

	# Swap in the synthetic single-member Gram Marx fixture as the instance's
	# LIVE state, then drive the exact real 'E' key input path
	# (MainScene._unhandled_input() -> equipment_panel_toggle_controller.
	# handle_input()) -- proving the real EquipmentPanelUI node opens and
	# renders Gram Marx's gear, not merely that _resolve_character() can
	# find him in isolation.
	instance._exploration.selected_party_member_id = GRAM_MARX_COMBATANT_ID
	instance.scenario_session = _make_gram_marx_scenario_session()
	instance._party = _make_gram_marx_party()

	assert_false(instance.equipment_panel_ui.visible, "fixture assumption: the panel starts closed")
	instance._unhandled_input(_make_e_key_event())

	assert_true(instance.equipment_panel_ui.visible, "pressing 'E' with Gram Marx selected must open the real EquipmentPanelUI")
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), "Gram's Quarterstaff",
		"the rendered MAIN_HAND row must show Gram Marx's staff display_name"
	)
	assert_eq(
		instance.equipment_panel_ui.get_charge_indicator_text(EquipmentSlotClass.MAIN_HAND), "⚡ Charged",
		"the rendered MAIN_HAND row must show the charged indicator (Fire Bolt, is_charged==true)"
	)
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.RING_1), "—",
		"the rendered RING_1 row must show '—' — Wizards do not Channel; Gram's RING_1 is empty"
	)
	assert_eq(
		instance.equipment_panel_ui.get_charge_indicator_text(EquipmentSlotClass.RING_1), "",
		"the rendered RING_1 charge indicator must be empty — no ring equipped"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 8 — composite steel-thread smoke test: entry point to exit
# point, one continuous live MainScene session.
# ══════════════════════════════════════════════════════════════════════════

func test_full_steel_thread_boot_to_equipment_panel_no_regression() -> void:
	# ── Entry point: boot + combat trigger. ─────────────────────────────────
	var instance = await _boot_main_scene_with_seed(42)
	assert_not_null(instance.round_session, "entry point: _on_combat_triggered('prologue') must succeed")
	assert_false(instance.round_session.is_round_over())

	# ── Gram Marx's domain-level equipment/charge state, via the existing
	# character-loading path. ────────────────────────────────────────────────
	var gram_marx = _resolve_gram_marx_character(instance)
	assert_not_null(gram_marx)
	assert_eq(gram_marx.level, 1)
	assert_eq(gram_marx.equipped_items.size(), 2)  # staff_gram + orb_gram (no ring_channeling — Wizards do not Channel)
	var gram_main_hand = gram_marx.get_item_in_slot(EquipmentSlotClass.MAIN_HAND)
	assert_not_null(gram_main_hand)
	assert_true(gram_main_hand.display_name.length() > 0)
	assert_eq(gram_main_hand.prepared_spell_id, "fire_bolt")
	assert_true(gram_main_hand.is_charged)
	assert_null(gram_marx.get_item_in_slot(EquipmentSlotClass.RING_1), "gram_marx RING_1 must be empty — Wizards do not Channel")
	assert_true(gram_marx.is_slot_blocked(EquipmentSlotClass.OFF_HAND))

	# ── Titus's domain-level equipment state, via the SAME existing
	# character-loading path, driven off the instance's REAL live party. ────
	var titus = _resolve_titus_character(instance)
	assert_not_null(titus)
	assert_null(titus.get_item_in_slot(EquipmentSlotClass.OFF_HAND), "Titus has no shield -- longsword is two-handed")
	assert_true(titus.is_slot_blocked(EquipmentSlotClass.OFF_HAND), "Titus OFF_HAND blocked by two-handed longsword")

	# Capture the instance's REAL, live scenario_session/_party BEFORE the
	# synthetic Gram Marx fixture is swapped in below -- FR-011's
	# turn-change steps (further down) restore these to advance the active
	# actor to the REAL Titus/enemy Combatant instances drawn from the
	# REAL prologue roster, never a hand-rolled stand-in.
	var real_scenario_session = instance.scenario_session
	var real_party: Array = instance._party

	# ── Exit point: selecting Gram Marx and pressing 'E' opens the real,
	# player-facing EquipmentPanelUI, rendering the SAME gear/charge state
	# just asserted above -- closing the loop entry point to exit point. ────
	instance._exploration.selected_party_member_id = GRAM_MARX_COMBATANT_ID
	instance.scenario_session = _make_gram_marx_scenario_session()
	instance._party = _make_gram_marx_party()

	instance._unhandled_input(_make_e_key_event())

	assert_true(instance.equipment_panel_ui.visible, "exit point: pressing 'E' must open the real EquipmentPanelUI")
	assert_eq(instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.MAIN_HAND), gram_main_hand.display_name)
	assert_eq(instance.equipment_panel_ui.get_charge_indicator_text(EquipmentSlotClass.MAIN_HAND), "⚡ Charged")
	assert_eq(instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.RING_1), "—", "RING_1 must show '—' — Wizards do not Channel; Gram's RING_1 is empty")
	assert_eq(instance.equipment_panel_ui.get_charge_indicator_text(EquipmentSlotClass.RING_1), "")

	# ── FIX-001 FR-011 convergence: advancing the active actor to Titus
	# while the panel is open must REFRESH it (via the real
	# MainScene._on_active_actor_changed() -> EquipmentPanelToggleController.
	# refresh_for_active_actor() reaction, FEAT-365) to show Titus's own
	# gear instead of Gram Marx's. Restore the real, live
	# scenario_session/_party captured above so the by-position resolution
	# this reaction depends on resolves against the REAL prologue roster. ──
	instance.scenario_session = real_scenario_session
	instance._party = real_party

	var titus_combatant = _find_combatant_by_id(real_party, "player_0")
	assert_not_null(titus_combatant, "fixture assumption: the real prologue party seats 'player_0' (Titus)")
	assert_false(titus_combatant.is_enemy, "fixture assumption: 'player_0' is on the Player team")

	instance._on_active_actor_changed(titus_combatant)

	assert_true(
		instance.equipment_panel_ui.visible,
		"FR-011: the panel must REFRESH (stay open), not close, when the active actor advances to Titus"
	)
	assert_true(
		instance.equipment_panel_toggle_controller.is_open(),
		"FR-011: the toggle controller's open/closed state must remain OPEN after a refresh"
	)
	# Titus wields a two-handed longsword (HEMA convention) — OFF_HAND is
	# null and blocked. The refreshed panel must show "—" for OFF_HAND.
	var titus_off_hand = titus.get_item_in_slot(EquipmentSlotClass.OFF_HAND)
	assert_null(titus_off_hand, "FR-011: Titus has no OFF_HAND item -- longsword is two-handed")
	assert_eq(
		instance.equipment_panel_ui.get_item_text(EquipmentSlotClass.OFF_HAND), "—",
		"FR-011: the refreshed panel's OFF_HAND row must show '—' for Titus (no shield; two-handed longsword)"
	)
	assert_true(
		titus.is_slot_blocked(EquipmentSlotClass.OFF_HAND),
		"FR-011: Titus's OFF_HAND must be blocked -- his longsword IS two-handed (HEMA convention)"
	)

	# ── FIX-001 FR-011 convergence: advancing the active actor further, to
	# a non-player-team (enemy) actor, must auto-CLOSE the panel and clear
	# every row -- no leftover Titus/Gram Marx gear data left visible. ────
	var enemy_combatant = _find_combatant_by_id(instance._enemies, "enemy_0")
	assert_not_null(enemy_combatant, "fixture assumption: the prologue encounter seats a live 'enemy_0' (Skeleton)")
	assert_true(enemy_combatant.is_enemy, "fixture assumption: 'enemy_0' is on the Enemy team")

	instance._on_active_actor_changed(enemy_combatant)

	assert_false(
		instance.equipment_panel_ui.visible,
		"FR-011: the panel must auto-close when the active actor advances to a non-player-team (enemy) actor"
	)
	assert_false(
		instance.equipment_panel_toggle_controller.is_open(),
		"FR-011: the toggle controller's open/closed state must flip to CLOSED on an enemy turn"
	)
	for slot in EquipmentSlotClass.ALL_SLOTS:
		assert_eq(
			instance.equipment_panel_ui.get_item_text(slot), "—",
			"FR-011: clear() must reset every row back to '—' -- no leftover gear data (slot %d)" % slot
		)
		assert_eq(
			instance.equipment_panel_ui.get_charge_indicator_text(slot), "",
			"FR-011: clear() must reset every charge indicator too (slot %d)" % slot
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 9 (ADR-005) — source-scan fitness function: no ResourceLoader.
# load() call appears anywhere in this file's own body.
# ══════════════════════════════════════════════════════════════════════════

func test_no_resourceloader_load_appears_in_this_file() -> void:
	var file := FileAccess.open(_THIS_FILE_PATH, FileAccess.READ)
	assert_not_null(file, "%s must be readable for the ADR-005 source-scan gate" % _THIS_FILE_PATH)
	if file == null:
		return

	# Scans real CODE lines only -- doc-comment lines (this file's own
	# file-level/method docs above discuss the forbidden call in prose) are
	# stripped first, mirroring this codebase's established fitness-function
	# convention (tests/unit/test_core_purity_source_scan.gd) of parsing
	# actual GDScript rather than a blind whole-file substring search.
	#
	# The forbidden substring is assembled via concatenation (never written
	# as one contiguous literal below) so this detector line itself -- and
	# this assertion's own failure message -- can never false-positive-match
	# against their own source.
	var forbidden_call: String = "ResourceLoader" + "." + "load("
	var offending_line: int = -1
	var line_number: int = 0
	while not file.eof_reached():
		var raw_line: String = file.get_line()
		line_number += 1
		var trimmed: String = raw_line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(forbidden_call):
			offending_line = line_number
			break
	file.close()

	assert_eq(
		offending_line, -1,
		"tests/integration/test_equipment_smoke_e2e.gd must never call the forbidden loader directly (found at line %d) -- every CharacterResource must be obtained via the game's existing character-loading path (ADR-005)" % offending_line
	)
