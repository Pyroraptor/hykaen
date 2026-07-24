extends GutTest
## tests/boot/test_combat_pipeline_gated_by_game_mode.gd — FEAT-316 (US-005 /
## US-007, resolves DEF-001 / PR-001).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root no longer wires the legacy hardcoded combat pipeline (rewire_session(),
## $VerbBarView.configure(), $SelectionOverlay.configure(), and
## $TurnController.round_over/active_actor_changed) unconditionally in
## _ready() -- it now stays dormant for the entire EXPLORATION-mode lifetime
## of a fresh boot, and is wired ONLY inside _on_combat_triggered(), the real
## trigger-driven handoff into GameMode.COMBAT (already proven end-to-end by
## tests/boot/test_exploration_to_combat_handoff.gd / test_exploration_to_
## combat_handoff_trigger.gd).
##
## Directly realizes FR-004's acceptance criteria: "verb bar / combat UI is
## inactive during EXPLORATION" and "_on_round_over is NOT connected at boot".
##
## Mirrors this project's established `_boot_main_scene()` convention (real
## MainScene.tscn via ResourceLoader.load() + instantiate(), pinned
## seed_override=42) used by every other boot-real suite in this directory.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors every other boot-real suite's identically-named/valued
## constant).
const PROLOGUE_SEED: int = 42

const PROLOGUE_ENCOUNTER_ID: String = "prologue"


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Boot-real: default _game_mode == EXPLORATION, round_session is null
# (rewire_session() was not called).
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_is_null_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.EXPLORATION, "fixture assumption: boot must default to EXPLORATION mode")
	assert_null(
		instance.round_session,
		"round_session must be null at boot (rewire_session() must not run outside a real combat handoff, FEAT-316)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Boot-real: verb_bar_view.configure() is not invoked and the verb bar is not
# active/visible at boot.
# ══════════════════════════════════════════════════════════════════════════

func test_verb_bar_view_is_not_configured_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.verb_bar_view, "fixture assumption: $VerbBarView must be wired")
	assert_eq(
		instance.verb_bar_view.get_button_count(), 0,
		"verb_bar_view.configure() must not have been invoked at boot -- zero verb buttons must be rendered (FEAT-316)"
	)
	assert_eq(
		instance.verb_bar_view.get_verb_ids(), [],
		"verb_bar_view must have no rendered verb_ids at boot (never configure()d, FEAT-316)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Boot-real: selection_overlay.configure() is not invoked at boot.
# ══════════════════════════════════════════════════════════════════════════

func test_selection_overlay_is_not_configured_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.selection_overlay, "fixture assumption: selection_overlay must be constructed")
	assert_null(
		instance.selection_overlay._registry,
		"selection_overlay.configure() must not have been invoked at boot -- its injected registry must stay null (FEAT-316)"
	)
	assert_false(
		instance.selection_overlay.is_active(),
		"selection_overlay must not be active at boot (never configure()d/activate()d, FEAT-316)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Boot-real: turn_controller.round_over and active_actor_changed have zero
# connections at boot.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_signals_have_zero_connections_at_boot() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.turn_controller, "fixture assumption: $TurnController must be wired")
	assert_eq(
		instance.turn_controller.active_actor_changed.get_connections().size(), 0,
		"turn_controller.active_actor_changed must have zero connections at boot (FEAT-316 / FR-004)"
	)
	assert_eq(
		instance.turn_controller.round_over.get_connections().size(), 0,
		"turn_controller.round_over must have zero connections at boot (FEAT-316 / FR-004, the DEF-001 acceptance criterion)"
	)
	assert_false(
		instance.turn_controller.active_actor_changed.is_connected(Callable(instance, "_on_active_actor_changed")),
		"turn_controller.active_actor_changed must not be connected to MainScene._on_active_actor_changed at boot"
	)
	assert_false(
		instance.turn_controller.round_over.is_connected(Callable(instance, "_on_round_over")),
		"turn_controller.round_over must not be connected to MainScene._on_round_over at boot (the DEF-001 acceptance criterion)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Boot-real regression: on a valid combat trigger, _on_combat_triggered()
# still performs ALL of the above wiring and combat proceeds normally -- no
# functional regression to the existing handoff path.
# ══════════════════════════════════════════════════════════════════════════

func test_combat_triggered_still_performs_all_deferred_wiring_and_combat_proceeds() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "a valid trigger must switch _game_mode to COMBAT")

	assert_not_null(instance.round_session, "_on_combat_triggered() must call rewire_session() -- round_session must be live")

	assert_not_null(instance.verb_bar_view, "fixture assumption: $VerbBarView must be wired")
	assert_true(
		instance.verb_bar_view.get_button_count() > 0,
		"_on_combat_triggered() must call verb_bar_view.configure() -- at least one verb button must be rendered"
	)

	assert_eq(
		instance.selection_overlay._registry, instance._verb_registry,
		"_on_combat_triggered() must call selection_overlay.configure() with the live _verb_registry"
	)

	assert_true(
		instance.turn_controller.active_actor_changed.is_connected(Callable(instance, "_on_active_actor_changed")),
		"_on_combat_triggered() must connect turn_controller.active_actor_changed -> _on_active_actor_changed"
	)
	assert_true(
		instance.turn_controller.round_over.is_connected(Callable(instance, "_on_round_over")),
		"_on_combat_triggered() must connect turn_controller.round_over -> _on_round_over"
	)

	var actor = instance.round_session.current_actor()
	assert_not_null(actor, "round_session.current_actor() must return a live Combatant -- TurnController/initiative is active")
	assert_is(actor, CombatantClass, "current_actor() must be a real Combatant instance")
