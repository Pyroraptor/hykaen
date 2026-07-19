extends GutTest
## tests/e2e/test_determinism_pinned_seed_cast_a_spell.gd — FEAT-282
## (US-018; NFR-002)
##
## Boots the REAL, shipped res://MainScene.tscn composition root TWICE,
## independently, both pinned to the SAME seed (via the in-process
## `seed_override` injection point, ADR-004's top-precedence contract, and
## a freshly-seeded ResolutionPort built from the SAME PROLOGUE_SEED --
## mirrors tests/boot/test_fire_bolt_full_cast_e2e_log.gd's own established
## "seeded ResolutionPort" convention), and drives the IDENTICAL Cast-a-
## Spell steel-thread sequence tests/e2e/test_steel_thread_cast_a_spell.gd
## exercises (Fire Bolt across a turn boundary, Channel after a round
## boundary, an Opportunistic Strike exposure window) through BOTH boots --
## then asserts every recorded roll, damage value, log entry, and reaction
## outcome is byte-identical between the two independent runs (NFR-002).
##
## Mirrors tests/regression/test_seed_determinism.gd's established
## "two independent boots, diff the recorded outcomes" convention, applied
## here to the Cast-a-Spell steel thread specifically (that suite's own
## double-boot diff only exercises the base Strike/movement pipeline, never
## a spell cast).
##
## test_criteria satisfied:
##   "Running the full scenario twice at a pinned seed produces identical
##   rolls, damage, and reaction outcomes."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass  = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const RoundEventsClass            = preload("res://core/rules/round_events.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/e2e/test_steel_thread_cast_a_spell.gd's identically-
## named/valued constant). Pinned identically across BOTH independent runs
## below -- the entire point of this suite.
const PROLOGUE_SEED: int = 42

## AC_GUARANTEED_HIT / SURVIVABLE_HP -- mirror tests/e2e/
## test_steel_thread_cast_a_spell.gd's identically-named/valued constants.
## SURVIVABLE_HP (rather than a LETHAL_HP cancellation) is used here so the
## reaction window's own resolved outcome (hit, roll, damage) is captured
## and diffed without the scenario terminating in a cast cancellation --
## the cancellation path itself is already proven deterministic-by-
## construction (it consumes zero RNG state, per design notes'
## error_handling section) and is covered by tests/e2e/
## test_steel_thread_cast_a_spell.gd's own dedicated suite.
const AC_GUARANTEED_HIT: int = -1000
const SURVIVABLE_HP: int = 500

## _ENEMY_HP_HANDICAP -- mirrors tests/e2e/
## test_steel_thread_post_remediation_smoke.gd's identically-motivated
## fixture: the real prologue Skeleton (8 hp) is one-shot-killable by a
## guaranteed-hit, guaranteed-crit Fire Bolt (defense_value pinned to
## AC_GUARANTEED_HIT auto-satisfies the +10 crit threshold too), which
## would end the encounter (outcome "won") before this suite's own later
## Channel/Opportunistic-Strike legs ever run. Bumping the Skeleton's real,
## live hp keeps it alive through the WHOLE scenario -- comfortably above
## any possible single Fire Bolt crit -- with no change to its other
## stats/behavior.
const _ENEMY_HP_HANDICAP: int = 200

## _MAX_TURN_EXCHANGES -- safety bound on any bounded loop below (CWE-835
## "never loop unbounded" guard, mirroring this codebase's established
## convention, e.g. tests/e2e/test_steel_thread_post_remediation_smoke.gd).
const _MAX_TURN_EXCHANGES: int = 30


## ScriptedTargetingPort -- always returns the same pre-picked target,
## mirroring every prior boot-real Cast-a-Spell suite's identically-shaped
## test double.
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


func _advance_to_marigolds_turn(instance) -> void:
	var exchanges: int = 0
	while not instance.round_session.is_round_over() and instance.round_session.current_actor_entity().name != "Marigold" and exchanges < _MAX_TURN_EXCHANGES:
		exchanges += 1
		var press_result: Dictionary = instance.end_turn_control.press()
		assert_true(press_result.get("ok", false), "EndTurnControl.press() must succeed while advancing to Marigold's turn")


## _force_all_spent(instance) -- mirrors tests/e2e/
## test_steel_thread_cast_a_spell.gd's / tests/boot/
## test_cast_persists_across_round_boundary.gd's identically-named,
## established helper exactly.
func _force_all_spent(instance) -> void:
	var order: Array = instance.encounter.get_turn_order()
	for i in range(order.size()):
		var action_economy = instance.encounter.get_action_economy(i)
		while not action_economy.is_spent():
			action_economy.spend_reaction()


func _reposition_marigold_adjacent_to_skeleton(marigold, skeleton) -> void:
	marigold.hex_coord = HexCoordClass.new(skeleton.hex_coord.q + 1, skeleton.hex_coord.r)


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


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
		"energy_pool_fn": func(caster): return instance.round_session.get_energy_pool(caster),
	})
	instance._controllers["CAST_SPELL"] = SpellActionControllerClass.new(deps)
	return combat_log_panel


## _run_full_scenario() -> Dictionary -- boots a FRESH, independent
## MainScene instance pinned to PROLOGUE_SEED and drives the full Cast-a-
## Spell steel thread (Fire Bolt across a turn boundary -> Channel after a
## round boundary -> an Opportunistic Strike exposure window), recording
## every RNG-derived outcome along the way into a plain-value snapshot
## Dictionary (no Node/Combatant references -- only ints/bools/Strings/
## Arrays/Dictionaries of same, so two independent snapshots can be
## directly diffed via `==`/assert_eq). Called exactly twice by this
## suite's own test function below, each call producing a fully
## independent boot (mirrors tests/regression/test_seed_determinism.gd's
## own established "two independent boots" convention).
func _run_full_scenario() -> Dictionary:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]

	# Guarantee Fire Bolt hits the Skeleton (Reflex) -- a forced, but
	# equally-forced-in-both-runs, hit removes hit/miss branching from this
	# suite's own control flow while leaving every dice ROLL genuinely
	# RNG-derived and therefore meaningful to diff. Handicap its hp first
	# (file-level doc) so the guaranteed-crit hit cannot end the encounter
	# before the rest of the scenario runs.
	skeleton.hp_current = _ENEMY_HP_HANDICAP
	skeleton.hp_max = _ENEMY_HP_HANDICAP
	skeleton.reflex = AC_GUARANTEED_HIT

	var combat_log_panel = _wire_real_cast_spell_controller(instance, skeleton)

	# ── Fire Bolt: begin -> cross a TURN boundary -> continue -> resolve. ──
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn")

	var begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(begin_result.get("success", false), "the first Fire Bolt CAST_SPELL action must succeed")

	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's own turn")

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn")

	var continue_result: Dictionary = instance._verb_bar_cast_spell_execute()
	assert_true(continue_result.get("success", false), "the continuing Fire Bolt CAST_SPELL action must succeed")
	assert_false(marigold.is_casting(), "Fire Bolt must have resolved and cleared casting_state")

	# ── cross a ROUND boundary, then cast Channel. ──────────────────────────
	_force_all_spent(instance)
	var round_end_result: Dictionary = instance.end_turn_control.press()
	assert_true(round_end_result.get("ok", false), "EndTurnControl.press() must succeed to end Marigold's turn and drive the round over")
	await get_tree().process_frame

	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "fixture assumption: it must now be Marigold's live turn in round 2")

	var channel_result: Dictionary = instance._verb_bar_cast_spell_execute("channel")
	assert_true(channel_result.get("success", false), "the Channel CAST_SPELL action must succeed")
	assert_false(marigold.is_casting(), "Channel must have resolved and cleared casting_state")

	# ── an Opportunistic Strike exposure window: reposition adjacent to the
	# Skeleton, guarantee a hit against Marigold, but keep her SURVIVABLE so
	# the reaction's own resolved outcome (hit/roll/damage) is captured
	# rather than the scenario terminating in a cancellation. ──────────────
	var post_channel_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(post_channel_turn_result.get("ok", false), "EndTurnControl.press() must succeed for Marigold's Channel turn")
	_advance_to_marigolds_turn(instance)
	assert_eq(instance.round_session.current_actor_entity(), marigold, "it must now be Marigold's NEXT live turn for the reaction-window leg")

	_reposition_marigold_adjacent_to_skeleton(marigold, skeleton)
	marigold.ac = AC_GUARANTEED_HIT
	marigold.hp_current = SURVIVABLE_HP
	marigold.hp_max = SURVIVABLE_HP

	var reaction_begin_result: Dictionary = instance._verb_bar_cast_spell_execute("fire_bolt")
	assert_true(reaction_begin_result.get("success", false), "the reaction-provoking Fire Bolt CAST_SPELL action must succeed")

	var reaction_result: Dictionary = reaction_begin_result.get("reaction_result", {})
	var reactions: Array = reaction_result.get("reactions", [])
	var reaction_choice: String = reactions[0].get("choice", "") if reactions.size() > 0 else ""
	var strike_result: Dictionary = reactions[0].get("strike_result", {}) if reactions.size() > 0 else {}

	# ── snapshot every RNG-derived outcome, as plain values only. ───────────
	var log_entries: Array = []
	for i in range(combat_log_panel.get_entry_count()):
		log_entries.append(combat_log_panel.get_entry(i).to_dict())

	var attack_event_dicts: Array = []
	for attack_event in _attack_events(instance):
		attack_event_dicts.append(attack_event.to_dict())

	return {
		"resolved_seed": instance.resolved_seed,
		"log_entries": log_entries,
		"attack_events": attack_event_dicts,
		"skeleton_hp_final": skeleton.hp_current,
		"marigold_hp_final": marigold.hp_current,
		"marigold_energy_pool_final": instance.round_session.get_energy_pool(marigold).current,
		"reaction_choice": reaction_choice,
		"reaction_hit": strike_result.get("hit", null),
		"reaction_crit": strike_result.get("crit", null),
		"reaction_roll_total": strike_result.get("roll_total", null),
		"reaction_damage_final": strike_result.get("damage_final", null),
		"reaction_target_defeated": strike_result.get("target_defeated", null),
	}


# ══════════════════════════════════════════════════════════════════════════
# Running the full Cast-a-Spell steel thread twice at PROLOGUE_SEED
# produces identical rolls, damage, and reaction outcomes (NFR-002).
# ══════════════════════════════════════════════════════════════════════════

func test_running_full_scenario_twice_at_pinned_seed_produces_identical_outcomes() -> void:
	var run_1: Dictionary = await _run_full_scenario()
	var run_2: Dictionary = await _run_full_scenario()

	assert_eq(run_1.get("resolved_seed"), PROLOGUE_SEED, "run 1 must have honored seed_override=PROLOGUE_SEED")
	assert_eq(run_2.get("resolved_seed"), PROLOGUE_SEED, "run 2 must have honored seed_override=PROLOGUE_SEED")

	# Non-vacuous sanity: real work actually happened in both runs (a bug
	# that silently no-ops the whole scenario would otherwise make this
	# suite trivially/vacuously pass).
	assert_eq(run_1.get("log_entries").size(), 2, "fixture assumption: exactly the Fire Bolt + Channel CAST_RESOLVE entries must have been recorded")
	assert_eq(run_1.get("attack_events").size(), 1, "fixture assumption: exactly the Opportunistic Strike's AttackBroadcast must have been recorded")
	assert_eq(run_1.get("reaction_choice"), "opportunistic_strike", "fixture assumption: the reaction window must have genuinely resolved to opportunistic_strike")

	# ── rolls, damage, and reaction outcomes -- byte-identical across the
	# two independent boots. ─────────────────────────────────────────────────
	assert_eq(run_2.get("log_entries"), run_1.get("log_entries"), "the recorded CAST_RESOLVE combat-log entries (spell/target/hit/damage/energy) must be identical across two independent boots of the same pinned seed")
	assert_eq(run_2.get("attack_events"), run_1.get("attack_events"), "the recorded AttackBroadcast (Opportunistic Strike roll/damage) must be identical across two independent boots of the same pinned seed")
	assert_eq(run_2.get("skeleton_hp_final"), run_1.get("skeleton_hp_final"), "the Skeleton's final hp (Fire Bolt's applied damage) must be identical")
	assert_eq(run_2.get("marigold_hp_final"), run_1.get("marigold_hp_final"), "Marigold's final hp (the Opportunistic Strike's applied damage) must be identical")
	assert_eq(run_2.get("marigold_energy_pool_final"), run_1.get("marigold_energy_pool_final"), "Marigold's final round energy pool balance (Channel's +1) must be identical")
	assert_eq(run_2.get("reaction_choice"), run_1.get("reaction_choice"), "the reactor's chosen reaction must be identical")
	assert_eq(run_2.get("reaction_hit"), run_1.get("reaction_hit"), "the reaction's resolved hit/miss must be identical")
	assert_eq(run_2.get("reaction_crit"), run_1.get("reaction_crit"), "the reaction's resolved crit must be identical")
	assert_eq(run_2.get("reaction_roll_total"), run_1.get("reaction_roll_total"), "the reaction's attack roll total must be identical")
	assert_eq(run_2.get("reaction_damage_final"), run_1.get("reaction_damage_final"), "the reaction's final damage must be identical")
	assert_eq(run_2.get("reaction_target_defeated"), run_1.get("reaction_target_defeated"), "the reaction's target_defeated outcome must be identical")

	# Whole-snapshot deep-equality sanity check (belt-and-suspenders): the
	# ENTIRE recorded snapshot of two independent boots at the same pinned
	# seed must be byte-identical.
	assert_eq(run_2, run_1, "the entire recorded snapshot of two independent boots at the same pinned seed must be byte-identical")
