extends GutTest
## tests/boot/test_channel_cast_e2e.gd — FEAT-277 (US-012; FR-013)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely drives a FULL Channel cast for
## the prologue's caster (Marigold) — select verb -> pay energy (0 for
## Channel) -> resolve, all in a SINGLE action since Channel costs only 1
## action — through the SAME CAST_SPELL verb entry point production code
## drives (`_verb_bar_cast_spell_execute()`), the IDENTICAL
## SpellActionController/ResolveSpellController/ResolveCastUseCase path
## Fire Bolt already exercises (design notes: "Routes Channel through the
## identical ... path (no bespoke verb)"), and that resolution:
##   - adds +1 to the caster's OWN round energy pool
##     (round_session.get_energy_pool(marigold)).
##   - emits a CAST_RESOLVE core/domain/combat_log_entry.gd CombatLogEntry
##     with energy_delta=1 and empty target_ids.
##
## Mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's established
## "_boot_main_scene()" / "_advance_to_marigolds_turn()" / hand-wiring a REAL
## SpellActionController via `instance._controllers["CAST_SPELL"]`
## conventions exactly -- presentation/verbs/spell_action_controller.gd and
## MainScene.gd are NOT in this feature's files_to_modify list either (only
## core/application/use_cases/resolve_cast_use_case.gd and
## presentation/verbs/resolve_spell_controller.gd are), so this suite
## injects a "resolve_spell_controller" wired with this feature's new
## "energy_pool_fn" dep, mirroring "combat_log_port"'s/"resolution_port"'s
## identical "no live composition-root wiring yet" convention.
##
## test_criteria satisfied:
##   "Boot-real test confirms a Channel cast (1 action, no targeting)
##   resolves through SpellActionController/ResolveSpellController and adds
##   +1 to the caster's round energy pool."
##   "Boot-real test confirms a CAST_RESOLVE log entry is emitted for
##   Channel with energy_delta=1 and empty target_ids."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's identically-
## named/valued constant).
const PROLOGUE_SEED: int = 42

const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")


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
## available, regardless of whether an action was spent) until it is
## Marigold's live turn.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _wire_real_cast_spell_controller(instance) -> CombatLogPanelAdapter --
## see file-level doc for why this injection is necessary and how it stays
## within this feature's two-file scope (core/application/use_cases/
## resolve_cast_use_case.gd, presentation/verbs/resolve_spell_controller.gd).
## No TargetingPort/ResolutionPort is wired at all -- Channel never reaches
## either (self-target, ADD_ENERGY effect_type, no attack roll).
func _wire_real_cast_spell_controller(instance):
	var combat_log_panel := CombatLogPanelAdapterClass.new()

	var deps: Dictionary = instance._verb_deps().duplicate()
	deps["resolve_spell_controller"] = ResolveSpellControllerClass.new({
		"combat_log_port": combat_log_panel,
		"energy_pool_fn": func(caster): return instance.round_session.get_energy_pool(caster),
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


func test_full_channel_cast_adds_energy_and_emits_cast_resolve_log_entry() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_true(marigold.known_spell_ids.has("channel"), "fixture assumption: Marigold must know Channel")

	var combat_log_panel = _wire_real_cast_spell_controller(instance)

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	var pool_before = instance.round_session.get_energy_pool(marigold)
	var energy_before: int = pool_before.current

	# ── select verb -> pay energy (0 for Channel) -> resolve, all in ONE
	# action, since Channel's 1-action cost drives remaining_actions to 0
	# on the FIRST cast, through the SAME production
	# _verb_bar_cast_spell_execute() shim ──────────────────────────────────
	var cast_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("channel")
	assert_true(cast_result.get("success", false), "the single Channel CAST_SPELL action (select verb + pay energy + resolve) must succeed")

	# ── casting_state must be cleared immediately after resolution ────────
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after Channel resolves")
	assert_true(marigold.casting_state.is_empty())

	# ── the caster's OWN round energy pool gains +1 ────────────────────────
	var pool_after = instance.round_session.get_energy_pool(marigold)
	assert_same(pool_after, pool_before, "get_energy_pool() must return the SAME live EnergyPool instance across calls")
	assert_eq(pool_after.current, energy_before + 1, "Channel's resolution must add exactly +1 to the caster's own round energy pool")

	# ── a CAST_RESOLVE log entry is emitted with energy_delta=1 and empty
	# target_ids ────────────────────────────────────────────────────────────
	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "channel")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.target_ids, [], "Channel's ADD_ENERGY effect has no target -- target_ids must be empty")
	assert_null(entry.hit, "Channel is not an attack -- hit must be null")
	assert_null(entry.damage_amount, "Channel deals no damage -- damage_amount must be null")
	assert_eq(entry.energy_delta, 1, "energy_delta must equal the +1 actually applied to the caster's own round energy pool")

	var rendered_text: String = combat_log_panel.get_entry_text(0)
	assert_true(rendered_text.contains("channel"), "the rendered line must name the spell")
	assert_true(rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")
