extends GutTest
## tests/integration/test_mainscene_r1_e2e.gd — FEAT-010 (US-009; closes out
## FR-009/NFR-001/002/003/005) companion suite: the Dodge-Step steel thread's
## capstone, exercised across a FULL round-1 sequence rather than a single
## isolated Strike.
##
## Boots the REAL res://MainScene.tscn composition root (G2 — never a
## hand-wired double) and drives round 1 of the prologue encounter (Titus vs
## the Skeleton) through TWO consecutive, real Strikes in the SAME
## session/round:
##   1. Titus's own opening Strike against the Skeleton (the SAME real
##      verb_bar_view.press("STRIKE") -> hex_grid_view.hex_clicked.emit(...)
##      flow tests/gut/test_rich_log_player_attack.gd already established) —
##      producing its OWN, independent rich log row.
##   2. Immediately followed, in the SAME round, by the Skeleton's own
##      returning Strike against Titus (the SAME real "end Titus's turn ->
##      Skeleton auto-drives its Strike" flow
##      tests/gut/test_rich_log_enemy_attack.gd already established) with a
##      FORCED-successful Dodge and a scripted, legal Step-selection hex
##      choice — the SAME capstone Dodge-Step-relocation-plus-rich-log thread
##      tests/gut/test_e2e_dodge_step_capstone.gd exercises in isolation, but
##      here proven to compose correctly alongside an UNRELATED, preceding
##      real Strike in the SAME round/session (US-007's "exactly one row per
##      attack" invariant, and the Dodge-Step relocation, must BOTH still
##      hold when interleaved).
##
## seed_override=7 is pinned (mirrors tests/gut/test_log_single_row_per_attack.gd's
## own established fixture note verbatim): the smallest seed under which the
## player's opening Strike does NOT defeat the Skeleton outright (so it
## survives to take its own turn) — this suite additionally forces the
## Skeleton's returning Strike's Dodge outcome deterministically (Titus's
## Mobility skill set absurdly high, mirroring
## tests/gut/test_defense_segment_reaction_outcomes.gd's
## `_force_guaranteed_dodge_success()` convention) rather than depending on
## seed=7's own natural roll for THAT Strike.
##
## Every collaborator driven below (`verb_bar_view`, `hex_grid_view`,
## `round_session`, `end_turn_control`, `event_log_view`,
## `movement_input_controller`) is the exact, unmodified, REUSED production
## instance MainScene.gd's own composition root wires — no test-local
## resolver/use-case graph, no mocked Application-layer port anywhere in this
## file (ADR-002/CR-001).
##
## test_criteria satisfied:
##   1. Round 1's two Strikes (player then enemy) each produce their OWN,
##      independent rich log row — never a basic+rich duplicate pair, and
##      never disturbing each other's row.
##   2. The Skeleton's forced-successful Dodge against Titus relocates
##      BOTH Titus's Combatant.hex_coord AND the on-screen HexGridView token
##      to the scripted, legal chosen hex.
##   3. Grep evidence: MainScene.gd's PLAYER-attack call site
##      (`_verb_bar_strike_execute()`) invokes record_attack/
##      render_attack_entry/record_reaction from real production source —
##      completing (alongside tests/gut/test_e2e_dodge_step_capstone.gd's own
##      ENEMY-path grep evidence) G5's live-path evidence requirement for
##      BOTH call sites this steel thread touches.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MAIN_SCENE_SOURCE_PATH: String = "res://MainScene.gd"


## _FixedChoiceResolver — mirrors tests/gut/test_defense_segment_reaction_outcomes.gd's
## `_FixedChoiceResolver` exactly.
class _FixedChoiceResolver:
	extends RefCounted
	var choice: String

	func _init(p_choice: String) -> void:
		choice = p_choice

	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": choice}


## ScriptedHexChoiceResolver — mirrors tests/gut/test_dodge_step_token_reposition.gd's
## own double of the same name/role exactly.
class ScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var call_count: int = 0
	var chosen_hex

	func _init(p_chosen_hex) -> void:
		chosen_hex = p_chosen_hex

	func resolve(legal_hexes: Array):
		call_count += 1
		if legal_hexes.is_empty():
			return null
		return chosen_hex


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _resolve_one_real_player_strike(instance) -> Dictionary — the SAME real
## Strike-scripting flow tests/gut/test_rich_log_player_attack.gd already
## established: press the STRIKE verb, then click the first in-reach
## candidate target's hex.
func _resolve_one_real_player_strike(instance) -> Dictionary:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
	return {"target_id": target_id}


func _force_guaranteed_dodge_success(instance) -> void:
	instance._party[0]["skills"] = {"mobility": 500, "determination": 500}


## _resolve_one_real_enemy_strike_with_forced_dodge(instance) -> void — the
## SAME real "end Titus's turn -> Skeleton auto-drives its Strike against
## Titus" flow tests/gut/test_rich_log_enemy_attack.gd already established,
## but with the PreHitAvoidance resolver scripted to ALWAYS choose "dodge".
func _resolve_one_real_enemy_strike_with_forced_dodge(instance) -> void:
	var prehit_resolver := _FixedChoiceResolver.new("dodge")
	var onhit_resolver := _FixedChoiceResolver.new("none")
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(onhit_resolver, "resolve"))

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(
		press_result.get("ok", false),
		"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully"
	)


func _attack_row_indices(instance) -> Array:
	var indices: Array = []
	for i in range(instance.event_log_view.get_entry_count()):
		if instance.event_log_view.get_row_text(i).contains(" attacks "):
			indices.append(i)
	return indices


# ══════════════════════════════════════════════════════════════════════════
# Round 1, end to end: a real player Strike immediately followed by the
# Skeleton's own real, forced-Dodge returning Strike (with Dodge-Step
# relocation), in the SAME round/session -- each producing exactly one rich
# log row, and the Dodge-Step relocation composing correctly alongside the
# earlier, unrelated player Strike.
# ══════════════════════════════════════════════════════════════════════════

## _assert_seams_are_the_real_composition_root_bindings(instance) -> void —
## FEAT-218 (closes PR-001/G2): identity/regression guard mirroring
## tests/gut/test_seam_composition_root_wiring.gd's own identity checks and
## tests/gut/test_e2e_dodge_step_capstone.gd's identically-named helper --
## proves the token-reposition, hex-choice, and combat-log seams this suite's
## assertions rest on remain the EXACT Callables/objects MainScene.gd's own
## composition root bound at boot, never re-wired to a test-local double
## inside this test body.
func _assert_seams_are_the_real_composition_root_bindings(instance) -> void:
	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "round_session._token_reposition_fn must remain bound")
	assert_same(reposition_fn.get_object(), instance.hex_grid_view, "the token-reposition seam must remain bound to the REAL, booted hex_grid_view -- never re-wired to a local double inside this test body")
	assert_eq(reposition_fn.get_method(), StringName("move_token"), "the token-reposition seam must remain bound to hex_grid_view's real move_token()")

	var hex_choice_fn: Callable = instance.round_session._hex_choice_resolver_fn
	assert_true(hex_choice_fn.is_valid(), "round_session._hex_choice_resolver_fn must remain bound")
	assert_same(hex_choice_fn.get_object(), instance, "the hex-choice seam must remain bound to the REAL MainScene instance's resolve_hex_choice() call path -- never re-wired to a local double's own resolve method")
	assert_eq(hex_choice_fn.get_method(), StringName("resolve_hex_choice"), "the hex-choice seam must remain bound to MainScene's real resolve_hex_choice()")

	for fn in [instance.round_session._event_log_record_attack_fn, instance.round_session._event_log_render_attack_entry_fn, instance.round_session._event_log_record_reaction_fn]:
		assert_true(fn.is_valid(), "every combat-log Callable must remain bound")
		assert_same(fn.get_object(), instance.event_log_view, "every combat-log seam must remain bound to the REAL, booted event_log_view -- never re-wired to a local double inside this test body")


func test_round1_player_strike_then_enemy_forced_dodge_strike_each_produce_one_row_and_dodge_step_relocates_defender() -> void:
	var instance = _boot_main_scene_with_seed(7)
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")

	# FEAT-218 (G2 gap closure): prove the seams this test is about to
	# exercise are the real composition-root bindings BEFORE this suite
	# scripts anything.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	# ── Round 1, Strike 1: Titus (the player) strikes the Skeleton. ─────────
	_resolve_one_real_player_strike(instance)

	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"exactly one row (total) may exist after the player's opening Strike -- no basic+rich duplicate pair"
	)
	var player_row_text: String = instance.event_log_view.get_row_text(0)
	assert_string_contains(player_row_text, "roll", "the player Strike's row must render the rich roll_total field")
	assert_string_contains(player_row_text, "Defense:", "the player Strike's row must render the rich active-defense field")
	var player_attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(player_attack_event_id) != "", "the visible player-Strike row must carry the attack_event_id it was rendered from")

	# ── Round 1, Strike 2: the Skeleton strikes back at Titus, with a FORCED
	# successful Dodge. ───────────────────────────────────────────────────────
	var defender: Dictionary = instance._party[0]
	assert_eq(defender.get("name", ""), "Titus", "fixture: Titus (the real player combatant) must be the prologue's defender")
	var defender_id: String = defender.get("combatant_id", defender.get("name", ""))
	var original_hex = defender.get("hex_coord", null)
	assert_not_null(original_hex, "fixture assumption: the defender must already carry a hex_coord")

	_force_guaranteed_dodge_success(instance)
	_resolve_one_real_enemy_strike_with_forced_dodge(instance)

	# FEAT-218 (G2 gap closure): the enemy's forced-Dodge Strike above must
	# still have been driven entirely through the real composition-root
	# seams -- no local double was substituted underneath it.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	assert_eq(
		instance.event_log_view.get_entry_count(), 2,
		"exactly two rows (total) may exist after BOTH the player Strike AND the Skeleton's forced-Dodge returning Strike -- one row per attack, never a duplicate pair for either"
	)
	var all_attack_rows: Array = _attack_row_indices(instance)
	assert_eq(all_attack_rows.size(), 2, "exactly one 'attacks' row per resolved Strike -- two Strikes, two rows")

	var enemy_row_index: int = all_attack_rows[1]
	var enemy_row_text: String = instance.event_log_view.get_row_text(enemy_row_index)
	assert_string_contains(enemy_row_text, "roll", "the Skeleton's forced-Dodge row must render the rich roll_total field")
	assert_string_contains(enemy_row_text, "Defense: dodge", "the Skeleton's forced-Dodge row must render the Dodge active-defense segment")
	assert_string_contains(enemy_row_text, "Miss", "a successful Dodge (a miss) must render the Miss label")

	var enemy_attack_event_id = instance.event_log_view.get_entry(enemy_row_index).get("attack_event_id", "")
	assert_ne(
		str(enemy_attack_event_id), str(player_attack_event_id),
		"the Skeleton's row must be tagged with its OWN attack_event_id, distinct from the player Strike's row"
	)

	# The player Strike's OWN row must stay untouched by the LATER enemy
	# Strike.
	assert_eq(
		instance.event_log_view.get_row_text(0), player_row_text,
		"the player Strike's row must remain exactly as rendered, unaffected by the LATER enemy Strike's own row"
	)

	# ── The SAME successful Dodge relocates the defender: Combatant.hex_coord
	# AND the on-screen token, in the SAME test run as the log assertions
	# above. ───────────────────────────────────────────────────────────────
	var legal_hexes: Array = instance._query_selectable_step_hexes(defender_id)
	assert_true(legal_hexes.size() > 0, "fixture assumption: the defender must have at least one legal Step destination after the forced Dodge")
	var chosen_hex = legal_hexes[0]
	assert_false(chosen_hex.equals(original_hex), "fixture assumption: the scripted chosen hex must differ from the defender's current hex")

	var scripted := ScriptedHexChoiceResolver.new(chosen_hex)
	instance.hex_choice_resolver = scripted

	# FEAT-218 (G2 gap closure): the line above deliberately substitutes ONLY
	# the leaf `hex_choice_resolver` field (this codebase's established,
	# documented convention for scripting a legal Step choice without a live
	# human click). Prove the round_session-LEVEL seam Callable itself, and
	# every other port this test depends on, is still the REAL
	# composition-root binding.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	# Re-assert once more after driving the Dodge-Step prompt.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	assert_eq(scripted.call_count, 1, "the Skeleton's forced-successful Dodge must invoke the Step-selection prompt exactly once")
	assert_true(
		defender.get("hex_coord", null).equals(chosen_hex),
		"the defender's Combatant.hex_coord must equal the scripted chosen hex after the successful Dodge-Step"
	)

	var token_after = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_after, "the defender's token must still be on record after the Dodge-Step reposition")
	assert_true(token_after.hex_coord.equals(chosen_hex), "the defender's on-screen token hex must update to the scripted chosen hex")
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel_with_offset(chosen_hex),
		"the defender's rendered screen position must resync to the chosen hex's axial-to-pixel projection"
	)

	# ── Both rows (player Strike + enemy forced-Dodge Strike) remain exactly
	# as rendered -- the Dodge-Step relocation logs no additional row. ───────
	assert_eq(instance.event_log_view.get_entry_count(), 2, "the Dodge-Step relocation itself must log no additional row -- still exactly two rows total for round 1's two Strikes")
	assert_eq(instance.event_log_view.get_row_text(0), player_row_text, "the player Strike's row must remain unaffected by the Dodge-Step relocation")
	assert_eq(instance.event_log_view.get_row_text(enemy_row_index), enemy_row_text, "the enemy Strike's row must remain unaffected by the Dodge-Step relocation")


# ══════════════════════════════════════════════════════════════════════════
# G5 observability gate: grep evidence that MainScene.gd's PLAYER-attack call
# site (`_verb_bar_strike_execute()`) invokes the SAME log-rendering seam
# this suite's player Strike drove above, from real production source.
# ══════════════════════════════════════════════════════════════════════════

func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func test_main_scene_player_strike_call_site_invokes_the_real_log_rendering_seam() -> void:
	var content: String = _read_file(MAIN_SCENE_SOURCE_PATH)

	var strike_execute_start: int = content.find("func _verb_bar_strike_execute(")
	assert_true(strike_execute_start != -1, "MainScene.gd must still declare _verb_bar_strike_execute() -- the player-strikes-enemy call site")

	var next_func_start: int = content.find("\nfunc ", strike_execute_start + 1)
	if next_func_start == -1:
		next_func_start = content.length()
	var function_body: String = content.substr(strike_execute_start, next_func_start - strike_execute_start)

	assert_string_contains(function_body, "record_attack", "MainScene.gd's player-attack call site must invoke record_attack -- live-path evidence, not merely a test-only call")
	assert_string_contains(function_body, "render_attack_entry", "MainScene.gd's player-attack call site must invoke render_attack_entry -- live-path evidence, not merely a test-only call")
	assert_string_contains(function_body, "record_reaction", "MainScene.gd's player-attack call site must invoke record_reaction -- live-path evidence, not merely a test-only call")
