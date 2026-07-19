extends GutTest
## tests/boot/test_cast_spell_verb_deps_composition_root_wiring.gd — FEAT-283
## (resolves PR-001; US-004/US-008/US-009/US-011)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's own `_verb_deps()` dict (never a hand-wired test double) now
## carries the four CAST_SPELL-only collaborators PR-001's blocker finding
## called out as never having been wired: "targeting_port"/"resolution_port"/
## "combat_log_port"/"energy_pool_fn". Prior to this feature,
## tests/boot/test_fire_bolt_full_cast_e2e_log.gd's/test_channel_cast_e2e.gd's
## own "_wire_real_cast_spell_controller()" helpers had to
## `instance._verb_deps().duplicate()` and manually inject a
## "resolve_spell_controller" carrying those four ports themselves — proving
## only that the CODE compiled against a hand-wired test double, never that
## the real composition root could drive spell resolution on its own (PR-001).
## This suite drives `instance._controller("CAST_SPELL")` /
## `instance._verb_bar_cast_spell_execute()` directly, with NO
## `_verb_deps().duplicate()` / `instance._controllers["CAST_SPELL"] = ...`
## override anywhere in this file, to prove that gap is closed.
##
## Verifies (test_criteria):
##   1. `_verb_deps_cache` for CAST_SPELL contains non-null targeting_port/
##      resolution_port/combat_log_port/energy_pool_fn keys.
##   2. `_controller("CAST_SPELL")` returns a fully-initialized
##      SpellActionController whose pipeline resolves a full cast with no
##      manual override/duplicate() of the dependency dict.
##   3. Boot-real: MainScene + the prologue encounter load headless with the
##      fully-wired CAST_SPELL verb dependencies present (no crash, no
##      null-dependency error).
##   4. Regression: STRIKE/STEP/STRIDE/END_TURN's own `_verb_deps()` entries
##      are unchanged by this additive wiring.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's/
## test_channel_cast_e2e.gd's identically-named/valued constant).
const PROLOGUE_SEED: int = 42

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolutionPortClass        = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPanelAdapterClass = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass        = preload("res://core/domain/combat_log_entry.gd")


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


## _advance_to_marigolds_turn(instance) -> void -- Titus acts first in the
## prologue's turn order (seed=42); pass turns (EndTurnControl is ALWAYS
## available) until it is Marigold's live turn (mirrors
## tests/boot/test_fire_bolt_full_cast_e2e_log.gd's/test_channel_cast_e2e.gd's
## identically-named helper).
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: _verb_deps_cache for CAST_SPELL contains non-null
# targeting_port/resolution_port/combat_log_port/energy_pool_fn keys
# (previously missing/absent).
# ══════════════════════════════════════════════════════════════════════════

func test_verb_deps_cache_contains_the_four_previously_missing_cast_spell_keys() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var deps: Dictionary = instance._verb_deps()
	assert_same(instance._verb_deps_cache, deps, "_verb_deps() must return the memoized _verb_deps_cache instance")

	assert_true(deps.has("targeting_port"), "_verb_deps_cache must carry a 'targeting_port' key")
	assert_not_null(deps.get("targeting_port"), "'targeting_port' must be non-null -- a real TargetingPort adapter")
	assert_true(
		deps.get("targeting_port").has_method("request_single_target"),
		"'targeting_port' must be a real TargetingPort-shaped adapter"
	)

	assert_true(deps.has("resolution_port"), "_verb_deps_cache must carry a 'resolution_port' key")
	assert_not_null(deps.get("resolution_port"), "'resolution_port' must be non-null -- a real ResolutionPort adapter")
	assert_true(
		deps.get("resolution_port") is ResolutionPortClass.ResolutionRulesAdapter,
		"'resolution_port' must be a real ResolutionRulesAdapter wrapping the composition root's shared RandomPort"
	)

	assert_true(deps.has("combat_log_port"), "_verb_deps_cache must carry a 'combat_log_port' key")
	assert_not_null(deps.get("combat_log_port"), "'combat_log_port' must be non-null -- a real CombatLogPort adapter")
	assert_true(
		deps.get("combat_log_port") is CombatLogPanelAdapterClass,
		"'combat_log_port' must be a real CombatLogPanelAdapter"
	)

	assert_true(deps.has("energy_pool_fn"), "_verb_deps_cache must carry an 'energy_pool_fn' key")
	var energy_pool_fn = deps.get("energy_pool_fn")
	assert_true(energy_pool_fn is Callable and energy_pool_fn.is_valid(), "'energy_pool_fn' must be a valid, real Callable")

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	var pool = energy_pool_fn.call(marigold)
	assert_not_null(pool, "'energy_pool_fn' must resolve to a real, non-null EnergyPool for a live caster")
	assert_same(
		pool, instance.round_session.get_energy_pool(marigold),
		"'energy_pool_fn' must read the SAME live EnergyPool round_session.get_energy_pool() itself returns -- never a second/parallel pool"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: _controller("CAST_SPELL") returns a fully-initialized
# SpellActionController whose pipeline resolves end-to-end from the REAL
# _verb_deps() dict alone -- no manual override/duplicate() anywhere in this
# file.
# ══════════════════════════════════════════════════════════════════════════

func test_controller_cast_spell_is_a_real_spell_action_controller_from_unmodified_verb_deps() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var controller = instance._controller("CAST_SPELL")
	assert_true(controller is SpellActionControllerClass, "_controller(\"CAST_SPELL\") must return a real SpellActionController")
	assert_same(
		controller, instance._controllers.get("CAST_SPELL"),
		"_controller() must memoize the SAME instance into _controllers"
	)


func test_full_channel_cast_resolves_end_to_end_through_the_real_composition_root_with_zero_test_overrides() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("channel"), "fixture assumption: Marigold must know Channel")

	# The real, production combat-log adapter -- read directly off the real
	# _verb_deps() dict, never constructed/injected by this test.
	var combat_log_panel = instance._verb_deps().get("combat_log_port")
	assert_not_null(combat_log_panel, "fixture assumption: _verb_deps() must already carry a real combat_log_port")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	var pool_before = instance.round_session.get_energy_pool(marigold)
	var energy_before: int = pool_before.current

	# ── select verb -> pay energy (0 for Channel) -> resolve, all in ONE
	# action (Channel costs 1 action), through the PRODUCTION
	# _verb_bar_cast_spell_execute() shim -- instance._controller("CAST_SPELL")
	# / instance._controllers["CAST_SPELL"] is NEVER overridden anywhere in
	# this test; every collaborator comes from the real composition root's
	# _verb_deps() dict alone. ─────────────────────────────────────────────
	var cast_result: Dictionary = instance._verb_bar_cast_spell_execute("channel")
	assert_true(cast_result.get("success", false), "the real, unmodified CAST_SPELL pipeline must resolve a full Channel cast")

	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after Channel resolves")
	assert_true(marigold.casting_state.is_empty())

	var pool_after = instance.round_session.get_energy_pool(marigold)
	assert_same(pool_after, pool_before, "get_energy_pool() must return the SAME live EnergyPool instance across calls")
	assert_eq(
		pool_after.current, energy_before + 1,
		"Channel's resolution must add exactly +1 to the caster's own round energy pool via the real energy_pool_fn"
	)

	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted via the real combat_log_port")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "channel")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.energy_delta, 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: boot-real -- MainScene + the prologue encounter load headless
# with the fully-wired CAST_SPELL verb dependencies present (no crash, no
# null-dependency error).
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_loads_cleanly_with_fully_wired_cast_spell_dependencies_present() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance, "MainScene.tscn must instantiate headlessly with no crash")
	assert_not_null(instance.round_session, "a real RoundSession must be live after first frame (the prologue encounter loaded cleanly)")

	var deps: Dictionary = instance._verb_deps()
	for key in ["targeting_port", "resolution_port", "combat_log_port", "energy_pool_fn"]:
		assert_not_null(deps.get(key), "CAST_SPELL dependency '%s' must be non-null after a real headless boot" % key)

	# Driving CAST_SPELL's three-step verb contract must not crash/error.
	var available: bool = instance._verb_bar_cast_spell_availability()
	assert_typeof(available, TYPE_BOOL, "CAST_SPELL availability() must resolve to a real bool with no crash")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (regression): STRIKE/STEP/STRIDE/END_TURN's own _verb_deps()
# entries are unchanged by this feature's additive CAST_SPELL-only keys.
# ══════════════════════════════════════════════════════════════════════════

func test_pre_existing_verb_deps_keys_are_unchanged_by_the_cast_spell_additions() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var deps: Dictionary = instance._verb_deps()

	assert_same(deps.get("session_holder"), instance._round_session_holder)
	assert_same(deps.get("end_turn_control"), instance.end_turn_control)
	assert_same(deps.get("movement_input_controller"), instance.movement_input_controller)
	assert_same(deps.get("status_panel_view"), instance.status_panel_view)
	assert_same(deps.get("event_log_view"), instance.event_log_view)
	assert_same(deps.get("resolve_action_use_case"), instance.resolve_action_use_case)
	assert_same(deps.get("enemy_reaction_chooser"), instance.enemy_reaction_chooser)
	assert_same(deps.get("reaction"), instance._reaction())

	var action_economy_for: Callable = deps.get("action_economy_for")
	assert_eq(action_economy_for.get_object(), instance)
	assert_eq(action_economy_for.get_method(), "_action_economy_for")

	var current_round_number: Callable = deps.get("current_round_number")
	assert_eq(current_round_number.get_method(), "_current_round_number")

	var after_successful_move: Callable = deps.get("after_successful_move")
	assert_eq(after_successful_move.get_method(), "_after_successful_move")

	var living_enemy_reactors: Callable = deps.get("living_enemy_reactors")
	assert_eq(living_enemy_reactors.get_method(), "_living_enemy_reactors")

	var current_turn_order: Callable = deps.get("current_turn_order")
	assert_eq(current_turn_order.get_method(), "_current_turn_order")

	var query_selectable_step_hexes: Callable = deps.get("query_selectable_step_hexes")
	assert_eq(query_selectable_step_hexes.get_method(), "_query_selectable_step_hexes")


func test_strike_step_stride_end_turn_controllers_still_construct_and_operate_normally() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	for verb_id in ["STRIKE", "STEP", "STRIDE", "END_TURN"]:
		var controller = instance._controller(verb_id)
		assert_not_null(controller, "verb '%s' must still construct a real controller from _verb_deps()" % verb_id)
		var available = controller.availability()
		assert_typeof(available, TYPE_BOOL, "verb '%s' availability() must still resolve to a real bool with no crash" % verb_id)
