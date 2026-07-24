extends GutTest
## tests/boot/test_fire_bolt_full_cast_e2e_log.gd — FEAT-276 (US-011;
## FR-010)
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root (never a hand-wired double) genuinely drives a FULL Fire Bolt cast
## for the prologue's caster (Marigold) — select verb -> pay energy ->
## continue action -> resolve — through the SAME CAST_SPELL verb entry
## point production code drives (`_verb_bar_cast_spell_execute()`), and
## that resolution clears `casting_state` and emits a CAST_RESOLVE
## core/domain/combat_log_entry.gd CombatLogEntry via this feature's new
## presentation/ui/combat_log_panel_adapter.gd CombatLogPanelAdapter —
## design notes' exit-point requirement: "Combat log shows the resolved
## spell outcome."
##
## Mirrors tests/boot/test_first_cast_firebolt.gd's / tests/boot/
## test_continue_cast_firebolt.gd's established "_boot_main_scene()" /
## "_advance_to_marigolds_turn()" conventions exactly for the select-verb
## -> pay-energy -> continue-action half of this flow.
##
## The RESOLVE half needs a TargetingPort/ResolutionPort/CombatLogPort this
## feature's two in-scope files (core/application/use_cases/
## resolve_cast_use_case.gd, presentation/verbs/resolve_spell_controller.gd)
## default to null when unwired (mirroring FEAT-008's/FEAT-009's own
## "no live composition-root wiring yet, MainScene.gd is NOT modified by
## this feature" convention — see resolve_spell_controller.gd's own
## file-level doc); presentation/verbs/spell_action_controller.gd and
## MainScene.gd are NOT in this feature's files_to_modify list either. This
## suite therefore swaps a REAL SpellActionController — built from the
## booted composition root's OWN `_verb_deps()` dict (session_holder etc.,
## byte-for-byte unchanged) plus a resolve_spell_controller wired with a
## scripted TargetingPort (no live TargetingPort UI adapter exists yet
## anywhere in this codebase to boot-real against — the SAME gap every
## prior Cast-a-Spell feature's own boot-real/unit suite already works
## around identically, e.g. tests/unit/test_resolve_cast_use_case_resolution.gd's
## own "no separate tests/boot/ file is in this feature's scope" boot-real
## suite), a REAL ResolutionPort.ResolutionRulesAdapter (core/rules/
## resolution.gd, unmodified), and a REAL CombatLogPanelAdapter — into
## `instance._controllers["CAST_SPELL"]`, the SAME memoized slot
## MainScene.gd's own `_controller("CAST_SPELL")` reads. This is exactly
## the established "inject via deps, no extra production file needs to
## change" seam (SpellActionController's `deps["resolve_spell_controller"]`)
## driven through a REAL booted MainScene instead of a hand-built
## FakeSession double, so the production `_verb_bar_cast_spell_execute()`
## shim itself drives the full flow end-to-end — never a bespoke
## resolution path this test invents on its own.
##
## test_criteria satisfied:
##   "Boot-real test confirms a full Fire Bolt cast (select verb -> pay
##   energy -> continue action -> resolve) emits a CAST_RESOLVE combat-log
##   entry with correct spell, target, hit/miss, damage fields."
##   "Unit test confirms casting_state is null on the caster immediately
##   after resolution regardless of hit/miss" — reproduced boot-real here
##   (the dedicated unit-level proof, covering BOTH a scripted hit and a
##   scripted miss directly against ResolveCastUseCase, lives in
##   tests/unit/test_resolve_cast_combat_log.gd).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/boot/test_first_cast_firebolt.gd's identically-named/
## valued constant). Also used to seed this suite's OWN injected
## ResolutionPort, so Fire Bolt's attack roll is deterministic/replayable
## (NFR-002) even though production composition-root wiring for a shared
## round-level RNG source does not exist yet (out of this feature's scope).
const PROLOGUE_SEED: int = 42

const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")


## ScriptedTargetingPort -- always returns the same pre-picked target,
## mirroring tests/unit/test_resolve_cast_use_case_resolution.gd's /
## tests/unit/test_resolve_spell_controller_targeting.gd's identically-
## shaped test double.
class ScriptedTargetingPort:
	extends TargetingPortClass
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


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
## Marigold's live turn again.
func _advance_to_marigolds_turn(instance) -> void:
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold":
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _wire_real_cast_spell_controller(instance, skeleton) -> CombatLogPanelAdapter
## -- see file-level doc for why this injection is necessary and how it
## stays within this feature's two-file scope.
func _wire_real_cast_spell_controller(instance, skeleton):
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = skeleton

	var combat_log_panel := CombatLogPanelAdapterClass.new()
	var resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))

	var deps: Dictionary = instance._verb_deps().duplicate()
	deps["resolve_spell_controller"] = ResolveSpellControllerClass.new({
		"targeting_port": targeting,
		"candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": combat_log_panel,
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


func test_full_fire_bolt_cast_emits_cast_resolve_log_entry_and_clears_casting_state() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]
	var skeleton_hp_before: int = skeleton.hp_current

	var combat_log_panel = _wire_real_cast_spell_controller(instance, skeleton)

	# ── select verb -> pay energy (first cast; Fire Bolt's 2-action cost
	# leaves remaining_actions == 1) ─────────────────────────────────────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")
	assert_false(marigold.is_casting(), "fixture assumption: Marigold must not already be mid-cast")

	var begin_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first CAST_SPELL action (select verb + pay energy) must succeed")
	assert_true(marigold.is_casting())
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)
	assert_eq(combat_log_panel.get_entry_count(), 0, "no CAST_RESOLVE entry yet -- the cast has not reached resolution")

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	# ── cycle the Skeleton's + Titus's turns back around to Marigold's
	# NEXT turn (mirrors tests/boot/test_continue_cast_firebolt.gd) ──────
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")
	assert_true(marigold.is_casting(), "the in-progress cast must survive every intervening turn")
	assert_eq(marigold.casting_state.get("remaining_actions"), 1)

	# ── continue action -> resolve (drives remaining_actions to 0, which
	# triggers ResolveCastUseCase through the SAME production
	# _verb_bar_cast_spell_execute() shim, with NO selection argument --
	# US-006: no re-selection) ───────────────────────────────────────────
	var continue_result: Dictionary = instance.verb_dispatch_controller._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "the continuing CAST_SPELL action must succeed")

	# ── casting_state must be null (cleared) immediately after
	# resolution, regardless of hit/miss ─────────────────────────────────
	assert_false(marigold.is_casting(), "casting_state must be cleared immediately after resolution")
	assert_true(marigold.casting_state.is_empty(), "the live Combatant's own casting_state Dictionary must be empty")

	# ── the combat log shows the resolved spell outcome (US-011's
	# exit-point requirement) ────────────────────────────────────────────
	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.actor_id, marigold.display_id())
	assert_eq(entry.target_ids, [skeleton.display_id()])
	assert_typeof(entry.hit, TYPE_BOOL, "hit must resolve to a real bool, never left null, once a genuine target was resolved against")

	if entry.hit:
		assert_gt(entry.damage_amount, 0, "a hit must carry a positive damage_amount")
		assert_lt(skeleton.hp_current, skeleton_hp_before, "a hit must have genuinely reduced the Skeleton's hp through the live EffectsApplier seam")
	else:
		assert_eq(entry.damage_amount, 0, "a miss must carry zero damage_amount")
		assert_eq(skeleton.hp_current, skeleton_hp_before, "a miss must leave the Skeleton's hp untouched")

	# The rendered CombatLogPanelAdapter line is a genuinely human-readable
	# sentence describing the resolved outcome (this feature's "rendered by
	# a CombatLogPanel adapter" requirement).
	var rendered_text: String = combat_log_panel.get_entry_text(0)
	assert_true(rendered_text.contains("fire_bolt"), "the rendered line must name the spell")
	assert_true(rendered_text.contains(marigold.display_id()), "the rendered line must name the caster")
	assert_true(rendered_text.contains(skeleton.display_id()), "the rendered line must name the target")
