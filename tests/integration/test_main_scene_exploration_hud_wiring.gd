extends GutTest
## tests/integration/test_main_scene_exploration_hud_wiring.gd — FEAT-381
## (US-006; FR-008; resolves DEF-002 for the rest-mechanics steel thread).
##
## Boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirrors tests/integration/test_exploration_status_panel_wiring.gd's
## `_boot_main_scene()` fixture convention) and proves ExplorationHUD
## (presentation/exploration_hud.tscn, containing the Rest Button) is
## actually instanced under MainScene.tscn's UILayer and wired to MainScene's
## REAL _game_mode / _party state -- closing the composition-root gap
## DEF-002 identified for FR-008 (the HUD was fully built and unit/UI
## tested in isolation in tests/ui/test_exploration_hud_rest_button.gd, but
## never instanced under MainScene, so no real player could ever see or
## press it).
##
## Covers all four test_criteria from the feature spec:
##   1. Boot MainScene.tscn headlessly (PackedScene.instantiate() of the
##      real res://MainScene.tscn, not exploration_hud.tscn directly) and
##      confirm an ExplorationHUD/Rest Button node exists under UILayer in
##      the live scene tree.
##   2. Rest Button is visible when MainScene's real _game_mode ==
##      EXPLORATION and hidden when == COMBAT, driven by the real MainScene
##      state (not a re-implemented duplicate check) -- proven by driving
##      the REAL _on_combat_triggered()/_on_combat_won() transitions and
##      reading exploration_hud.get_rest_button().visible.
##   3. Rest Button enabled/disabled state reflects MainScene's real _party
##      rest-need scan (HP<max OR stamina<max OR any discharged Mage item)
##      -- proven by mutating a REAL party Combatant's hp_current and
##      confirming the live ExplorationHUD.needs_rest() scan (never
##      duplicated in this file) picks it up.
##   4. tests/ui/test_exploration_hud_rest_button.gd is left completely
##      unmodified by this feature -- its continued, unmodified pass is
##      verified by the same CI run, not re-asserted here.

const MainSceneClass = preload("res://MainScene.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_exploration_status_panel_wiring.gd's
## identically-valued constant).
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"


## before_each()/after_each() — reseed CurrentGameState.data with a fresh
## GameStateDataClass instance so no test in this file (or any test that
## runs before/after it in the full suite) can leak scenario_path/session
## state across test boundaries (mirrors tests/integration/
## test_exploration_status_panel_wiring.gd's established ADR-008
## convention).
func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — ExplorationHUD/Rest Button exists under UILayer at boot.
# ══════════════════════════════════════════════════════════════════════════

func test_exploration_hud_is_instanced_under_uilayer() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var hud = instance.get_node_or_null("UILayer/ExplorationHUD")
	assert_not_null(hud, "MainScene.tscn's UILayer must contain an ExplorationHUD instance (composition-root wiring for DEF-002)")
	assert_not_null(hud.get_rest_button(), "the live ExplorationHUD instance must expose a real Rest Button")
	assert_eq(
		instance.exploration_hud, hud,
		"MainScene.gd's exploration_hud onready var must resolve to the same live UILayer/ExplorationHUD node"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Rest Button visibility tracks MainScene's real _game_mode.
# ══════════════════════════════════════════════════════════════════════════

func test_rest_button_visible_in_exploration_mode_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: MainScene boots into EXPLORATION")
	assert_true(
		instance.exploration_hud.get_rest_button().visible,
		"Rest Button must be visible when the real, live MainScene is in EXPLORATION mode"
	)


func test_rest_button_hidden_after_real_combat_triggered() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real exploration->combat handoff must have succeeded")
	assert_false(
		instance.exploration_hud.get_rest_button().visible,
		"Rest Button must be hidden once the real, live MainScene transitions to COMBAT mode"
	)


func test_rest_button_visible_again_after_real_combat_won() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real exploration->combat handoff must have succeeded")

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))

	instance._on_combat_won()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: _on_combat_won() must return MainScene to EXPLORATION")
	assert_true(
		instance.exploration_hud.get_rest_button().visible,
		"Rest Button must become visible again once the real, live MainScene returns to EXPLORATION mode"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Rest Button enabled/disabled reflects MainScene's real
# _party rest-need scan (HP<max OR stamina<max OR any discharged Mage item).
# ══════════════════════════════════════════════════════════════════════════

func test_rest_button_disabled_when_real_party_is_fully_rested_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._party.size() > 0, "fixture assumption: the prologue party is non-empty")
	for combatant in instance._party:
		assert_eq(combatant.hp_current, combatant.hp_max, "fixture assumption: the prologue party boots at full HP")

	assert_true(
		instance.exploration_hud.get_rest_button().disabled,
		"Rest Button must be disabled when MainScene's real, live party needs no rest"
	)


func test_rest_button_enabled_after_real_party_member_takes_damage_and_state_refreshes() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._party.size() > 0, "fixture assumption: the prologue party is non-empty")
	assert_true(
		instance.exploration_hud.get_rest_button().disabled,
		"fixture assumption: the Rest Button starts disabled (fully-rested party at boot)"
	)

	instance._party[0].hp_current = max(instance._party[0].hp_current - 1, 0)
	instance._refresh_off_guard_conditions()  # the codebase's existing "party state changed" hook, now also re-syncs ExplorationHUD

	assert_false(
		instance.exploration_hud.get_rest_button().disabled,
		"Rest Button must become enabled once MainScene's real _party rest-need scan (via ExplorationHUD.needs_rest(), not re-implemented here) sees a damaged party member"
	)


func test_rest_button_disabled_state_reflects_real_party_not_a_stale_snapshot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._party[0].hp_current = max(instance._party[0].hp_current - 1, 0)
	instance._refresh_off_guard_conditions()
	assert_false(instance.exploration_hud.get_rest_button().disabled, "must reflect the damaged state")

	instance._party[0].hp_current = instance._party[0].hp_max
	instance._refresh_off_guard_conditions()
	assert_true(
		instance.exploration_hud.get_rest_button().disabled,
		"Rest Button must re-disable once the real party member is healed back to full HP and MainScene re-syncs"
	)
