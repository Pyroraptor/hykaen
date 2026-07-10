extends GutTest
## tests/gut/test_player_strikes_enemy_pass_through.gd — FEAT-005 (US-004 /
## FR-004, ADR-005 (CR-001 accepted debt)) Part A; SUPERSEDED for its
## Part-B-specific assertions by iteration K FEAT-004 (US-004, ADR-004).
##
## Iteration I's Part A wired a REAL, awaited reaction window onto the
## enemy-strikes-player path (core/application/round_session.gd's
## advance_ai_turn()) while deliberately keeping MainScene.gd's
## `_verb_bar_strike_execute()` (player-strikes-enemy) a pure pass-through:
## the enemy always "Passed", no reaction window ever opened, no pop-up was
## ever shown for the enemy. That file-level doc explicitly named "Part B, a
## real enemy reaction AI policy" as the future feature that would end this
## pass-through — iteration K FEAT-004 IS that Part B: `_verb_bar_strike_execute()`
## now calls core/application/resolve_action_use_case.gd's SEPARATE
## resolve_reactive() entry point (not resolve()), handing it
## infrastructure/ai_reaction_policy.gd's AIReactionPolicy as the enemy
## target's ReactionChooserPort, so the enemy genuinely reacts
## (Dodge/Parry/Block) on this path.
##
## What SURVIVES from Part A (still true, and now doubles as this feature's
## OWN "no pop-up UI opens during the enemy's reaction window" test
## criterion): AIReactionPolicy is a SYNCHRONOUS, no-`await`, no-coroutine
## ReactionChooserPort — resolve_reactive() never suspends, so the enemy's
## reaction decision can NEVER open `reaction_prompt_ui` (the player-facing
## blocking pop-up) or fire its `reaction_chosen` signal. Criterion 2 below
## (test_player_strike_never_opens_a_reaction_window_or_prompt_for_the_enemy)
## is kept, UNCHANGED, from Part A for exactly this reason — it remains a
## true and valuable regression guard.
##
## What is REPLACED: Criterion 1 (the old "MainScene calls resolve() with
## exactly 6 default-only args" source-shape pin) and Criterion 3 (the old
## "byte-for-byte unchanged from the pre-sprint unmitigated baseline"
## outcome pin) both directly contradicted Part B's whole purpose and are
## replaced below with Part-B-accurate equivalents. Boot-real coverage of
## the ACTUAL new behavior (HP/budget changes from a genuine AI-chosen
## reaction, determinism) lives in
## tests/integration/test_mainscene_player_strike_enemy_reaction.gd
## (iteration K FEAT-004's own dedicated suite) — this file stays scoped to
## the composition-root WIRING shape and the "no pop-up" guarantee.
##
## FEAT-230 (DEF-003) UPDATE: at the time this doc-comment was originally
## written, the file path above named a suite that did not exist yet — a
## forward reference that, left unresolved, silently masked a real coverage
## gap (only Dodge was ever boot-real tested on this path; Parry was only
## ever exercised via hand-built dictionaries, and Block had no coverage at
## all). tests/integration/test_mainscene_player_strike_enemy_reaction.gd
## now EXISTS and carries exactly that boot-real Parry/Block coverage
## (test_forced_parry_success_yields_higher_skeleton_hp_current_vs_unmitigated
## / test_forced_block_yields_higher_skeleton_hp_current_vs_unmitigated) —
## the reference above is no longer stale.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const AIReactionPolicyClass     = preload("res://infrastructure/ai_reaction_policy.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")

const MAIN_SCENE_SOURCE_PATH: String = "res://MainScene.gd"
## Composition-root de-bloat (2026-07-10): the player-strikes-enemy call site
## (formerly MainScene._verb_bar_strike_execute()'s body) moved into
## StrikeActionController.execute(); the source-grep guard below follows it there.
const STRIKE_CONTROLLER_SOURCE_PATH: String = "res://presentation/strike_action_controller.gd"


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _resolve_one_real_player_strike(instance) -> Dictionary:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
	return {"target_id": target_id}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (REPLACED for Part B, iteration K FEAT-004) — MainScene.gd's
# player-strikes-enemy call site now calls resolve_action_use_case's
# resolve_reactive() entry point (NEVER resolve()), wired to a REAL
# AIReactionPolicy instance (`enemy_reaction_chooser`) and the target's own
# live ActionEconomy — the composition-root wiring this feature's whole
# steel-thread slice depends on.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_strike_call_site_calls_resolve_reactive_not_resolve() -> void:
	var content: String = _read_file(STRIKE_CONTROLLER_SOURCE_PATH)

	var strike_execute_start: int = content.find("func execute(")
	assert_true(strike_execute_start != -1, "StrikeActionController must still declare execute()")
	var next_func_start: int = content.find("\nfunc ", strike_execute_start + 1)
	if next_func_start == -1:
		next_func_start = content.length()
	var function_body: String = content.substr(strike_execute_start, next_func_start - strike_execute_start)

	assert_string_contains(
		function_body, "resolve_action_use_case.resolve_reactive(",
		"StrikeActionController.execute() (the player-strikes-enemy call site) must call resolve_reactive() (iteration K FEAT-004 Part B) -- never the atomic resolve()"
	)
	assert_string_contains(
		function_body, "enemy_reaction_chooser",
		"StrikeActionController.execute() must hand resolve_reactive() the REAL enemy_reaction_chooser (AIReactionPolicy)"
	)


func test_main_scene_wires_a_real_ai_reaction_policy_instance_for_the_enemy() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_not_null(instance.enemy_reaction_chooser, "MainScene.gd must construct a real enemy_reaction_chooser in _ready()")
	assert_true(
		is_instance_of(instance.enemy_reaction_chooser, AIReactionPolicyClass),
		"enemy_reaction_chooser must be a REAL infrastructure/ai_reaction_policy.gd AIReactionPolicy instance"
	)
	assert_ne(
		instance.enemy_reaction_chooser, instance.player_reaction_chooser,
		"the enemy's chooser must be a DISTINCT adapter from the player's own pop-up-backed player_reaction_chooser"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (UNCHANGED from Part A) — a real player Strike against a real
# enemy NEVER opens the player-facing reaction pop-up for the enemy, and
# NEVER emits a ReactionWindowOpenedEvent/ReactionResolvedEvent (this
# project's core/application/reaction_window.gd machinery is not used on
# this path at all — the enemy's reaction is decided synchronously via
# core/application/open_reaction_window_use_case.gd instead). This IS
# iteration K FEAT-004's own "no pop-up UI opens during the enemy's reaction
# window" test criterion.
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_never_opens_a_reaction_window_or_prompt_for_the_enemy() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(instance.reaction_prompt_ui.is_open(), "sanity: the reaction pop-up must be closed before any Strike happens")
	watch_signals(instance.reaction_prompt_ui)

	_resolve_one_real_player_strike(instance)

	assert_false(instance.reaction_prompt_ui.is_open(), "a player-strikes-enemy Strike must never open the reaction pop-up for the enemy")
	assert_signal_not_emitted(
		instance.reaction_prompt_ui, "reaction_chosen",
		"the enemy's reaction is decided synchronously (AIReactionPolicy) -- reaction_chosen (the pop-up's own signal) must never fire"
	)

	for event in instance.event_sink.log:
		assert_false(
			is_instance_of(event, RoundEventsClass.ReactionWindowOpenedEvent),
			"no ReactionWindowOpenedEvent may be emitted for a player-strikes-enemy Strike -- this path never drives core/application/reaction_window.gd"
		)
		assert_false(
			is_instance_of(event, RoundEventsClass.ReactionResolvedEvent),
			"no ReactionResolvedEvent may be emitted for a player-strikes-enemy Strike -- this path never drives core/application/reaction_window.gd"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (REPLACED for Part B) — a resolved player Strike against the
# enemy still emits exactly one AttackEvent and still costs the actor
# exactly one action, regardless of whether the enemy reacted (the
# resolve_reactive()/resolve() shared _finalize_strike_result() tail
# guarantees this — see core/application/resolve_action_use_case.gd).
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_still_emits_exactly_one_attack_event_and_costs_one_action() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)

	_resolve_one_real_player_strike(instance)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackEvent)
	assert_eq(attack_events.size(), 1, "a real player Strike must emit exactly one AttackEvent")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(after_remaining, before_remaining - 1, "a resolved Strike must still cost exactly 1 action for the ACTOR, identical to every other Strike path")
