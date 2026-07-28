extends GutTest
## tests/gut/test_smoke_full_steel_thread.gd — FEAT-220 (US-002..US-009;
## resolves PR-003/PR-004): the CI-runnable release-gate smoke test.
##
## The V&V/deployment gate flagged two gaps: (1) no concrete "installable
## artifact" / exported-build smoke test existed, and (2) scripts/
## test_command.sh's full run had never been confirmed end-to-end. This
## file is the first gap's concrete fix — a single, automated, headless
## entry point (paired with scripts/smoke_test.sh) that boots the REAL
## res://MainScene.tscn composition root (G2 — never a hand-wired double)
## and drives the actual, full Dodge-Step steel thread in one run:
##
##   attack -> successful Dodge -> chosen hex -> token relocation ->
##   rich log row with the correct Defense segment
##
## exiting non-zero (via scripts/smoke_test.sh's `godot ... -gexit`
## invocation) on ANY observable-state failure, so CI has a real
## user-journey check rather than a manual sign-off document.
##
## This suite deliberately mirrors the already-established, PROVEN
## conventions this steel thread's prior features pinned down —
## tests/gut/test_e2e_dodge_step_capstone.gd (FEAT-010's own capstone),
## tests/gut/test_dodge_step_token_reposition.gd,
## tests/gut/test_defense_segment_reaction_outcomes.gd,
## tests/gut/test_rich_log_enemy_attack.gd — rather than inventing a new,
## parallel resolution path (ADR-002 "no duplicate seam"): the SAME
## `_force_guaranteed_dodge_success()` Mobility-skill trick, the SAME
## "end Titus's turn -> Skeleton auto-drives its Strike against Titus" real
## flow, and the SAME documented, established convention of driving
## `round_session._resolve_dodge_step_prompt()` directly for the
## just-resolved Strike/defender (see test_e2e_dodge_step_capstone.gd's
## top-level doc for why: the real `_UIHexChoiceResolver` this seam is
## wired to genuinely blocks on a live hex click, so an unconditional live
## call site through advance_ai_turn() would hang any headless/CI caller
## that scripts a successful Dodge without also scripting a click).
##
## Every collaborator this suite drives (`round_session`, `hex_grid_view`,
## `movement_input_controller`, `event_log_view`) is the exact, unmodified,
## REUSED production instance MainScene.gd's own composition root wires —
## the ONLY intentional substitution is the leaf `hex_choice_resolver`
## field (this codebase's established convention for scripting a legal
## Step choice without a live human click); every other seam
## (`_token_reposition_fn`, `_event_log_record_attack_fn`,
## `_event_log_render_attack_entry_fn`, `_event_log_record_reaction_fn`) is
## asserted to remain the real, composition-root-bound Callable throughout.
##
## test_criteria satisfied (this file):
##   1. Scripts a real attack + forced-successful Dodge + scripted
##      legal-hex pick against the LIVE composition root (no doubles).
##   2. Asserts defender.hex_coord equals the chosen hex.
##   3. Asserts event_log_view.get_row_text(i) for that attack contains the
##      roll field and "Defense: dodge" — and that the structured
##      AttackEvent record_attack() stored also carries the raw/final
##      damage fields the design's rich-log contract specifies (a
##      successful Dodge negates the Strike into a Miss, so damage
##      fields are legitimately zero and are not themselves rendered into
##      Miss-shaped text — see resolution.gd/event_log_view.gd — but the
##      structured roll/raw/final fields this row was rendered FROM are
##      always present and asserted directly here).
##   4. Asserts exactly one visible log row was produced for the attack —
##      no duplicate basic/rich rows.
##
## scripts/smoke_test.sh is the paired CI entry point that boots
## `godot --headless` with this exact test file via GUT's real CLI
## (`addons/gut/gut_cmdln.gd -gexit`), exiting 0 on success / non-zero on
## any assertion failure below.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## _FixedChoiceResolver — mirrors tests/gut/test_defense_segment_reaction_outcomes.gd's
## `_FixedChoiceResolver` exactly: a synchronous ReactionResolverPort double
## that always answers with the SAME, caller-supplied choice for whichever
## PreHitAvoidance/OnHitMitigation trigger it is handed — bypasses the real
## player-facing pop-up (this suite is about the Dodge-Step relocation +
## rich log outcome, not the reaction-choice UI itself).
class _FixedChoiceResolver:
	extends RefCounted
	var choice: String

	func _init(p_choice: String) -> void:
		choice = p_choice

	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": choice}


## ScriptedHexChoiceResolver — mirrors tests/gut/test_dodge_step_token_reposition.gd's
## own double of the same name/role: always answers with the pre-configured
## `chosen_hex`, recording every call for this suite's "invoked exactly
## once" assertion.
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


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=42 for a deterministic boot
## (Titus vs the Skeleton, prologue encounter) — this codebase's
## established convention.
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with round_session/verb_bar_view/
## selection_overlay/turn_controller signal wiring gated behind a real
## _on_combat_triggered() handoff (see MainScene.gd's own FEAT-316 doc). This
## suite drives round_session/hex_grid_view/event_log_view directly, so this
## helper now also drives the SAME real handoff tests/boot/
## test_exploration_to_combat_handoff_trigger.gd exercises directly, landing
## the instance in GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


## _force_guaranteed_dodge_success(instance) -> void — mirrors
## tests/gut/test_defense_segment_reaction_outcomes.gd's identically-named
## helper: Dodge substitutes a Mobility check (d20 + skills.mobility) for
## the passive defense value when triggered (core/rules/resolution.gd's
## resolve_to_hit()). Setting Titus's Mobility absurdly high guarantees
## that check exceeds the attacker's roll_total regardless of which d20
## faces the real, seeded RNG rolls for either side — a deterministic
## Dodge SUCCESS, never a re-derived hit/miss computation of this suite's
## own.
func _force_guaranteed_dodge_success(instance) -> void:
	instance._party[0]["skills"] = {"mobility": 500, "determination": 500}


## _resolve_one_real_enemy_strike_with_forced_dodge(instance) -> void — the
## SAME real "end Titus's turn -> Skeleton auto-drives its Strike against
## Titus" flow tests/gut/test_rich_log_enemy_attack.gd already established,
## with the PreHitAvoidance resolver scripted to ALWAYS choose "dodge" —
## forcing a genuine PreHitAvoidance Dodge resolution for the Skeleton's
## Strike.
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

	# The roster now includes Marigold (a second, player-controlled combatant,
	# "player_1"), who acts second at seed=42 -- BEFORE the Skeleton's turn.
	# TurnController only auto-drives Enemy turns (US-011), so ending Titus's
	# turn alone now stops the cursor on Marigold, not the enemy; an extra
	# manual End Turn is required to advance past her turn too.
	if not instance.round_session.current_actor().is_enemy:
		press_result = instance.end_turn_control.press()
		assert_true(
			press_result.get("ok", false),
			"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully for Marigold's turn"
		)


## _assert_seams_are_the_real_composition_root_bindings(instance) -> void —
## G2 identity/regression guard proving the ports this suite's assertions
## rest on are still the EXACT Callables/objects MainScene.gd's own
## composition root bound at boot — never a local double this test body
## silently re-wired underneath the assertions above/below.
func _assert_seams_are_the_real_composition_root_bindings(instance) -> void:
	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "round_session._token_reposition_fn must remain bound")
	assert_same(
		reposition_fn.get_object(), instance.hex_grid_view,
		"the token-reposition seam must remain bound to the REAL, booted hex_grid_view — never re-wired to a local double"
	)
	assert_eq(reposition_fn.get_method(), StringName("move_token"), "the token-reposition seam must remain bound to hex_grid_view's real move_token()")

	for fn in [instance.round_session._event_log_record_attack_fn, instance.round_session._event_log_render_attack_entry_fn, instance.round_session._event_log_record_reaction_fn]:
		assert_true(fn.is_valid(), "every combat-log Callable must remain bound")
		assert_same(
			fn.get_object(), instance.event_log_view,
			"every combat-log seam must remain bound to the REAL, booted event_log_view — never re-wired to a local double"
		)


# ══════════════════════════════════════════════════════════════════════════
# THE smoke test: entry point (real scripted attack, forced Dodge, scripted
# legal hex) to exit point (relocation + correct single rich log row) in
# ONE run against the live, booted MainScene composition root.
# ══════════════════════════════════════════════════════════════════════════

func test_smoke_full_steel_thread_dodge_step_relocation_and_rich_log() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")
	_assert_seams_are_the_real_composition_root_bindings(instance)

	var defender = instance._party[0]
	assert_eq(defender.name, "Titus", "fixture: Titus (the real player combatant) must be the prologue's defender")
	var defender_id: String = defender.combatant_id

	var original_hex = defender.hex_coord
	assert_not_null(original_hex, "fixture assumption: the defender must already carry a hex_coord at boot")

	var token_before = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_before, "fixture assumption: hex_grid_view must already carry a token for the defender")
	assert_true(token_before.hex_coord.equals(original_hex), "the on-screen token must start at the defender's pre-Strike hex")

	# ── Entry point: a REAL attacker (the Skeleton) strikes the REAL
	# defender (Titus), through the real "end turn -> AI strikes back" flow,
	# with a FORCED-successful Dodge. ─────────────────────────────────────
	_force_guaranteed_dodge_success(instance)
	_resolve_one_real_enemy_strike_with_forced_dodge(instance)

	# ── Exit point (half 1): exactly one visible row for this ONE attack,
	# rendered rich, carrying the correct "Defense: dodge…" segment
	# (test_criteria: "exactly one visible log row ... no duplicate
	# basic/rich rows"). ───────────────────────────────────────────────────
	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"exactly one row (total) may exist after the ONE resolved, forced-Dodge Strike — no basic+rich duplicate pair"
	)
	var row_text: String = instance.event_log_view.get_row_text(0)
	assert_true(row_text != "", "get_row_text(0) must be non-empty after the resolved, forced-Dodge Strike")
	assert_string_contains(row_text, "roll", "the rich row must render the roll_total field")
	assert_string_contains(row_text, "Defense: dodge", "the rich row must render the Dodge active-defense segment for this Strike (test_criteria)")

	var attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the visible row must carry the attack_event_id it was rendered from")

	# test_criteria: the rich row's roll/raw/final fields — pulled directly
	# off the SAME structured AttackEvent record_attack() stored and
	# render_attack_entry() rendered `row_text` from (a successful Dodge
	# negates the Strike into a Miss, so damage fields are legitimately 0
	# and are not themselves substrings of the Miss-shaped text, but the
	# fields themselves are always present and asserted here directly).
	var attack_event = instance.event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(attack_event, "the structured AttackEvent recorded via record_attack() must be retrievable for this Strike")
	if attack_event != null:
		assert_true(attack_event.roll_total > 0, "the real resolution.gd math must produce a non-zero roll_total (the 'roll' field)")
		assert_true(attack_event.damage_raw >= 0, "the structured AttackEvent must carry a raw-damage field")
		assert_true(attack_event.damage_final >= 0, "the structured AttackEvent must carry a final-damage field")
		assert_false(attack_event.is_hit, "a successful Dodge must resolve this Strike as a Miss")
		assert_string_contains(row_text, "Miss", "a successful Dodge (a miss) must render the Miss label")

	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event_id, "PreHitAvoidance")
	assert_not_null(paired_reaction, "record_reaction() must have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window")
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "dodge", "the paired reaction's own choice must be the forced 'dodge' this suite scripted")
		assert_eq(paired_reaction.outcome, "dodge_succeeded", "the paired reaction's outcome must confirm the forced Dodge actually succeeded")

	# ── Exit point (half 2): the SAME attack's Dodge-Step now relocates the
	# defender, via the REAL, composition-root-wired seams
	# (hex_choice_resolver / _token_reposition_fn / _step_hex_query_fn) —
	# driven the SAME way this codebase's steel thread already established
	# as its accepted convention. ───────────────────────────────────────────
	var legal_hexes: Array = instance._query_selectable_step_hexes(defender_id)
	assert_true(legal_hexes.size() > 0, "fixture assumption: the defender must have at least one legal Step destination after the forced Dodge")
	var chosen_hex = legal_hexes[0]
	assert_false(chosen_hex.equals(original_hex), "fixture assumption: the scripted chosen hex must actually differ from the defender's current hex")

	assert_true(defender.hex_coord.equals(original_hex), "sanity: the defender must not yet have moved before the Dodge-Step prompt is driven")

	var scripted := ScriptedHexChoiceResolver.new(chosen_hex)
	instance.hex_choice_resolver = scripted

	_assert_seams_are_the_real_composition_root_bindings(instance)

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	_assert_seams_are_the_real_composition_root_bindings(instance)

	assert_eq(scripted.call_count, 1, "the SAME successful Dodge this attack just resolved must invoke the Step-selection prompt exactly once")

	# test_criteria: defender.hex_coord equals the chosen hex.
	assert_true(
		defender.hex_coord.equals(chosen_hex),
		"the defender's Combatant.hex_coord must equal the scripted chosen hex after the successful Dodge-Step"
	)

	var token_after = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_after, "the defender's token must still be on record after the Dodge-Step reposition")
	assert_true(
		token_after.hex_coord.equals(chosen_hex),
		"the defender's on-screen token hex must update to the scripted chosen hex"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(chosen_hex),
		"the defender's rendered screen position must resync to the chosen hex's axial-to-pixel projection"
	)

	# Re-assert the SAME attack's log row is still the ONLY one, unchanged
	# by the subsequent relocation — no duplicate row was produced by the
	# Step itself (test_criteria).
	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"the Dodge-Step relocation itself must log no additional row — still exactly one row for this ONE attack"
	)
	assert_eq(
		instance.event_log_view.get_row_text(0), row_text,
		"the attack's own rich log row must remain byte-for-byte unchanged by the later Dodge-Step relocation"
	)
