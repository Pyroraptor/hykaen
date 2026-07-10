extends GutTest
## tests/gut/test_defense_segment_reaction_outcomes.gd — FEAT-008 (US-008 /
## FR-007, Iteration J-R2 Part D): "Populate Defense segment via
## ReactionResolvedEvent/record_reaction".
##
## Before this feature, NOTHING in production code ever called
## presentation/event_log_view.gd's record_reaction() — FEAT-005/006/007
## wired record_attack()/render_attack_entry()/overwrite_entry_as_rich() into
## both live Strike call sites, but the paired reaction half of the
## storage-level AttackEvent<->ReactionResolvedEvent relation was left
## entirely unwired, so every rich row's 'Defense:' segment silently
## defaulted to "none" regardless of what a defender actually chose. This
## suite boots the REAL res://MainScene.tscn composition root (G2 — never a
## hand-wired double) and drives a real enemy-strikes-player Strike (via the
## SAME "end Titus's turn -> Skeleton auto-drives its Strike" flow
## tests/gut/test_rich_log_enemy_attack.gd already established) with a
## scripted PreHitAvoidance/OnHitMitigation resolver answering a FIXED
## reaction choice, and combatant stats skewed just enough to make the
## underlying core/rules/resolution.gd math DETERMINISTIC (never re-deriving
## that math itself — only forcing which side of a probabilistic roll a real,
## seeded RNG lands on), so each of dodge/parry/block/none can be asserted
## exactly, without flaking on the seeded RNG's actual roll.
##
## Verifies (test_criteria):
##   1. For each of dodge/parry/block/none, get_row_text(0) contains the
##      EXACT matching 'Defense: <outcome>' segment.
##   2. An AttackEvent with NO paired ReactionResolvedEvent (record_reaction()
##      never called for it) renders 'Defense: none'.
##   3. Grep-based checks confirm record_reaction() is invoked from BOTH live
##      call sites' production source (core/application/round_session.gd's
##      advance_ai_turn(), and MainScene.gd's _verb_bar_strike_execute()) —
##      not merely from this test.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ROUND_SESSION_SOURCE_PATH: String = "res://core/application/round_session.gd"
const MAIN_SCENE_SOURCE_PATH: String = "res://MainScene.gd"


## _FixedChoiceResolver — a synchronous ReactionResolverPort double (mirrors
## tests/gut/test_rich_log_enemy_attack.gd's `_ScriptedPassResolver`
## convention) that always answers with the SAME, caller-supplied choice for
## whichever PreHitAvoidance/OnHitMitigation trigger it is handed. Bypassing
## the real player-facing pop-up (turn_controller.gd/reaction_prompt_ui) —
## this suite is about the rich-log RENDERING of an already-resolved
## reaction, not the reaction-choice UI itself.
class _FixedChoiceResolver:
	extends RefCounted
	var choice: String

	func _init(p_choice: String) -> void:
		choice = p_choice

	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": choice}


## _ScriptedHexChoiceResolver — a HexChoiceResolverPort double that always
## answers with a pre-scripted legal hex (the "player's pick"). Used by the
## live-path Dodge-Step regression test below to script the hex choice the
## production _UIHexChoiceResolver would otherwise await as a battlefield click.
class _ScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"
	var chosen_hex

	func _init(p_chosen_hex) -> void:
		chosen_hex = p_chosen_hex

	func resolve(legal_hexes: Array):
		if legal_hexes.is_empty():
			return null
		return chosen_hex


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	# This suite asserts the Defense-segment outcome, not the Dodge-Step follow-up.
	# A successful Dodge now fires the live Dodge-Step hex prompt inside
	# advance_ai_turn(); the REAL _UIHexChoiceResolver would block awaiting a
	# battlefield click no headless test can deliver. Null it so
	# MainScene.resolve_hex_choice() returns null → Dodge-Step no-ops here
	# (the Dodge resolution and its "Defense: dodge" segment are unaffected).
	instance.hex_choice_resolver = null
	return instance


## _resolve_one_real_enemy_strike(instance, prehit_choice, onhit_choice) ->
## void — the SAME real "end Titus's turn -> Skeleton auto-drives its Strike
## against Titus" flow tests/gut/test_rich_log_enemy_attack.gd already
## established, but with the PreHitAvoidance/OnHitMitigation resolvers each
## scripted to a FIXED choice (rather than always "none"/Pass) so this
## suite can force a genuine Dodge/Parry/Block resolution to happen.
func _resolve_one_real_enemy_strike(instance, prehit_choice: String, onhit_choice: String) -> void:
	var prehit_resolver := _FixedChoiceResolver.new(prehit_choice)
	var onhit_resolver := _FixedChoiceResolver.new(onhit_choice)
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(onhit_resolver, "resolve"))

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(
		press_result.get("ok", false),
		"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully"
	)


## _force_guaranteed_hit(instance) -> void — Parry/Block are ON-HIT-only
## reactions (core/rules/resolution.gd's apply_on_hit_defense() precondition)
## — they are never even offered on a miss. Rather than re-deriving/gaming
## the seeded RNG's actual roll, this drives Titus's passive AC absurdly low
## so the Skeleton's attack roll ALWAYS meets/exceeds it regardless of which
## d20 face the real RNG lands on — a deterministic HIT, never a re-derived
## hit/miss computation of this suite's own.
func _force_guaranteed_hit(instance) -> void:
	instance._party[0]["ac"] = -1000


## _force_guaranteed_dodge_success(instance) -> void — Dodge substitutes a
## Mobility check (d20 + skills.mobility) for the passive defense value when
## triggered (core/rules/resolution.gd's resolve_to_hit()). Setting Titus's
## Mobility absurdly high guarantees that check exceeds the attacker's
## roll_total regardless of which d20 faces the real RNG rolls for either
## side — a deterministic Dodge SUCCESS, never a re-derived hit/miss
## computation of this suite's own.
func _force_guaranteed_dodge_success(instance) -> void:
	instance._party[0]["skills"] = {"mobility": 500, "determination": 500}


## _force_guaranteed_parry_success(instance) -> void — Parry succeeds only
## when its opposed roll (d20 + parry_bonus) STRICTLY exceeds the attacker's
## roll_total (core/rules/resolution.gd's apply_on_hit_defense()). Setting
## Titus's weapon parry_bonus absurdly high guarantees that regardless of
## either side's real d20 roll.
func _force_guaranteed_parry_success(instance) -> void:
	instance._party[0]["weapon"]["parry_bonus"] = 500


func _row0_text(instance) -> String:
	return instance.event_log_view.get_row_text(0)


func _row0_attack_event_id(instance):
	return instance.event_log_view.get_entry(0).get("attack_event_id", "")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — dodge/parry/block/none each render the EXACT matching
# 'Defense: <outcome>' segment.
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_reaction_renders_the_dodge_succeeded_defense_segment() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	_force_guaranteed_dodge_success(instance)
	_resolve_one_real_enemy_strike(instance, "dodge", "none")

	var row_text: String = _row0_text(instance)
	assert_string_contains(row_text, "Defense: dodge-succeeded", "a forced-successful Dodge must render the exact 'Defense: dodge-succeeded' segment")

	var attack_event_id = _row0_attack_event_id(instance)
	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event_id, "PreHitAvoidance")
	assert_not_null(paired_reaction, "record_reaction() must have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window")
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "dodge")
		assert_eq(paired_reaction.outcome, "dodge_succeeded")


# ══════════════════════════════════════════════════════════════════════════
# REGRESSION (dodge-step dead-in-live-play): a successful Dodge must actually
# relocate the defender when resolved through advance_ai_turn()'s LIVE
# coroutine — NOT only when round_session._resolve_dodge_step_prompt() is
# called directly (which is all every other Dodge-Step test did, so none
# caught that advance_ai_turn() never invoked it in real play). This drives a
# REAL enemy Strike that Titus Dodges and asserts the live path moved him.
# ══════════════════════════════════════════════════════════════════════════
func test_successful_dodge_through_advance_ai_turn_relocates_defender_via_live_wiring() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var titus = instance._party[0]
	var titus_id: String = titus.get("combatant_id", titus.get("name", ""))
	var original_hex = titus.get("hex_coord", null)
	assert_not_null(original_hex, "fixture: Titus must carry a hex_coord at boot")

	# Pick a REAL legal Step destination and script the player's hex pick to it,
	# replacing the boot helper's null resolver — THIS test exercises the Step.
	var legal_hexes: Array = instance._query_selectable_step_hexes(titus_id)
	assert_true(legal_hexes.size() > 0, "fixture: Titus must have at least one legal Step destination at boot")
	var chosen_hex = legal_hexes[0]
	assert_false(chosen_hex.equals(original_hex), "fixture: the chosen hex must differ from Titus's current hex")
	instance.hex_choice_resolver = _ScriptedHexChoiceResolver.new(chosen_hex)

	_force_guaranteed_dodge_success(instance)
	_resolve_one_real_enemy_strike(instance, "dodge", "none")

	assert_true(
		titus.get("hex_coord", null).equals(chosen_hex),
		"a successful Dodge resolved through advance_ai_turn()'s LIVE coroutine must relocate Titus to the player-picked hex — the wiring that was dead in play until round_session.advance_ai_turn() invoked _resolve_dodge_step_prompt()"
	)


func test_parry_reaction_renders_the_parry_succeeded_defense_segment() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	_force_guaranteed_hit(instance)
	_force_guaranteed_parry_success(instance)
	_resolve_one_real_enemy_strike(instance, "none", "parry")

	var row_text: String = _row0_text(instance)
	assert_string_contains(row_text, "Defense: parry-succeeded", "a forced-successful Parry must render the exact 'Defense: parry-succeeded' segment")

	var attack_event_id = _row0_attack_event_id(instance)
	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event_id, "OnHitMitigation")
	assert_not_null(paired_reaction, "record_reaction() must have paired a ReactionResolvedEvent to this Strike's OnHitMitigation window")
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "parry")
		assert_eq(paired_reaction.outcome, "parry_succeeded")


func test_block_reaction_renders_the_block_reduced_by_n_defense_segment() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	_force_guaranteed_hit(instance)
	_resolve_one_real_enemy_strike(instance, "none", "block")

	var row_text: String = _row0_text(instance)
	assert_string_contains(row_text, "Defense: block reduced-by-", "a resolved Block must render the 'Defense: block reduced-by-N' segment")

	var attack_event_id = _row0_attack_event_id(instance)
	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event_id, "OnHitMitigation")
	assert_not_null(paired_reaction, "record_reaction() must have paired a ReactionResolvedEvent to this Strike's OnHitMitigation window")
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "block")
		assert_eq(paired_reaction.outcome, "block_reduced_by_n")
		assert_true(int(paired_reaction.reduced_by) >= 0, "reduced_by must be a non-negative int")


func test_none_reaction_renders_the_none_defense_segment() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	_resolve_one_real_enemy_strike(instance, "none", "none")

	var row_text: String = _row0_text(instance)
	assert_string_contains(row_text, "Defense: none", "a Passed reaction must render the exact 'Defense: none' segment")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — an AttackEvent with NO paired ReactionResolvedEvent renders
# 'Defense: none' (record_reaction() was never invoked for it at all).
# ══════════════════════════════════════════════════════════════════════════

func test_attack_event_with_no_paired_reaction_renders_defense_none() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	const AttackEventClass = preload("res://core/log/attack_event.gd")
	var attack_event = AttackEventClass.new(
		"unit-test-attack-1", 1, "attacker-1", "target-1", "weapon-1",
		12, true, false, 5, 5, false, false
	)
	instance.event_log_view.record_attack(attack_event)
	# Deliberately never call record_reaction() for this attack_event_id.

	var rendered_text: String = instance.event_log_view.render_attack_entry("unit-test-attack-1")
	assert_string_contains(rendered_text, "Defense: none", "an AttackEvent with no paired reaction must render 'Defense: none'")

	var outcome_string: String = instance.event_log_view.get_active_defense_outcome_string("unit-test-attack-1")
	assert_eq(outcome_string, "none", "get_active_defense_outcome_string() must default to 'none' when no reaction was ever recorded")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — grep-based checks confirm record_reaction() is invoked from
# BOTH live call sites' production source, not merely from this test
# (mirrors tests/gut/test_rich_log_enemy_attack.gd's/
# tests/gut/test_rich_log_player_attack.gd's own established
# static-source-shape convention).
# ══════════════════════════════════════════════════════════════════════════

func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _function_body(content: String, func_signature_prefix: String) -> String:
	var start: int = content.find(func_signature_prefix)
	assert_true(start != -1, "%s must be present in the source" % func_signature_prefix)
	if start == -1:
		return ""
	var next_func_start: int = content.find("\nfunc ", start + 1)
	if next_func_start == -1:
		next_func_start = content.length()
	return content.substr(start, next_func_start - start)


func test_round_session_source_invokes_record_reaction_from_advance_ai_turn() -> void:
	var content: String = _read_file(ROUND_SESSION_SOURCE_PATH)
	var function_body: String = _function_body(content, "func advance_ai_turn(")

	assert_string_contains(
		function_body, "record_reaction",
		"RoundSession.advance_ai_turn() must invoke record_reaction (via RenderCombatLogUseCase) -- live-path evidence, not merely a test-only call"
	)


func test_main_scene_source_invokes_record_reaction_from_player_strike_execute() -> void:
	var content: String = _read_file(MAIN_SCENE_SOURCE_PATH)
	var function_body: String = _function_body(content, "func _verb_bar_strike_execute(")

	assert_string_contains(
		function_body, "record_reaction",
		"MainScene._verb_bar_strike_execute() must invoke record_reaction (via RenderCombatLogUseCase) -- live-path evidence for the player-strikes-enemy call site"
	)
