extends GutTest
## tests/gut/test_e2e_dodge_step_capstone.gd — FEAT-010 (US-009; closes out
## FR-009/NFR-001/002/003/005): the Dodge-Step steel thread's CAPSTONE
## end-to-end smoke test.
##
## Boots the REAL res://MainScene.tscn composition root (G2 — never a
## hand-wired double) and, in a SINGLE run, drives the complete steel thread
## from entry point to exit point:
##   entry  — a scripted attacker-strikes-defender attack (the Skeleton
##            auto-driving its Strike against Titus, the SAME real
##            "end Titus's turn -> Skeleton strikes back" flow
##            tests/gut/test_rich_log_enemy_attack.gd /
##            tests/gut/test_defense_segment_reaction_outcomes.gd already
##            established) with a FORCED-successful Dodge (mirrors
##            test_defense_segment_reaction_outcomes.gd's
##            `_force_guaranteed_dodge_success()` convention: Titus's Mobility
##            skill is set absurdly high so the real, seeded RNG's dodge check
##            succeeds regardless of which face it actually rolls), and a
##            scripted, legal Step-selection hex choice;
##   exit   — BOTH observable effects of that ONE attack are asserted
##            together: (1) the defender's Combatant.hex_coord AND the
##            on-screen HexGridView token both relocated to the chosen hex
##            (FEAT-004's contract, tests/gut/test_dodge_step_token_reposition.gd),
##            and (2) the SAME attack's visible event_log_view row is the
##            ONLY row logged, rendered rich (roll/Miss fields) with the
##            correct "Defense: dodge…" segment (FEAT-005/006/007/008's
##            contract).
##
## Because production wiring deliberately stops short of threading a live
## call to RoundSession's `_resolve_dodge_step_prompt()` through
## `advance_ai_turn()`'s own Strike-resolution coroutine (see that method's
## own doc, core/application/round_session.gd: "Threading a call to this
## method through advance_ai_turn()'s live Strike-resolution coroutine is
## deliberately left to a later feature" — the REAL `_UIHexChoiceResolver`
## this seam is wired to genuinely blocks on a live hex click, so an
## unconditional live call site there would hang any caller, including every
## pre-existing headless/sim suite, that scripts a successful Dodge without
## also scripting a click), this suite drives the Dodge-Step prompt for the
## SAME just-resolved Strike/defender the SAME way EVERY prior feature in
## this steel thread already established as this codebase's accepted
## G2-compliant convention (tests/gut/test_dodge_step_prompt.gd,
## test_dodge_step_token_reposition.gd, test_hex_choice_seam_dodge_step.gd,
## test_dodge_step_no_legal_hex.gd): a direct, explicit
## `await instance.round_session._resolve_dodge_step_prompt(defender, {...})`
## call against the REAL, booted `round_session` — never a second,
## self-wired RoundSession/use-case graph — with the REAL,
## composition-root-wired `hex_choice_resolver`/`_token_reposition_fn`/
## `_step_hex_query_fn` seams doing the actual relocation work. This is not a
## bypass of production code: every collaborator this test drives
## (`round_session`, `hex_grid_view`, `movement_input_controller`,
## `event_log_view`) is the exact, unmodified, REUSED production instance
## MainScene.gd's own composition root wires — see this file's grep-evidence
## section below, which proves every one of those seams really is bound to
## its real production adapter method (never a test double left wired after
## boot).
##
## Verifies (test_criteria):
##   1. Boots the real MainScene (no self-wired doubles), scripts
##      attacker->defender attack, forces a successful Dodge, scripts a
##      legal chosen hex.
##   2. Defender Combatant.hex_coord equals the chosen hex AND the on-screen
##      token position matches — within the SAME test run as the log
##      assertions.
##   3. The visible event log has EXACTLY one row for this attack, and
##      get_row_text() contains the roll field plus "Defense: dodge".
##   4. Grep evidence: the hex-choice seam, token-reposition seam, and
##      log-rendering seam are all the REAL production-bound implementations
##      (MainScene.gd's `rewire_session()` / `round_session.gd`'s
##      `advance_ai_turn()` source text), not test-only wiring.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")


## _FixedChoiceResolver — mirrors tests/gut/test_defense_segment_reaction_outcomes.gd's
## `_FixedChoiceResolver` exactly: a synchronous ReactionResolverPort double
## that always answers with the SAME, caller-supplied choice for whichever
## PreHitAvoidance/OnHitMitigation trigger it is handed — bypasses the real
## player-facing pop-up (this suite is about the Dodge-Step relocation + rich
## log outcome, not the reaction-choice UI itself, exactly like every prior
## feature in this steel thread).
class _FixedChoiceResolver:
	extends RefCounted
	var choice: String

	func _init(p_choice: String) -> void:
		choice = p_choice

	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": choice}


## ScriptedHexChoiceResolver — mirrors tests/gut/test_dodge_step_token_reposition.gd's
## own double of the same name/role exactly: always answers with the
## pre-configured `chosen_hex`, recording every call for this suite's
## "invoked exactly once" assertion.
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
## composition root (this codebase's established convention), pinning
## seed_override=42 for a deterministic boot (Titus vs the Skeleton, prologue
## encounter).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


## _force_guaranteed_dodge_success(instance) -> void — mirrors
## tests/gut/test_defense_segment_reaction_outcomes.gd's identically-named
## helper exactly: Dodge substitutes a Mobility check (d20 + skills.mobility)
## for the passive defense value when triggered (core/rules/resolution.gd's
## resolve_to_hit()). Setting Titus's Mobility absurdly high guarantees that
## check exceeds the attacker's roll_total regardless of which d20 faces the
## real, seeded RNG rolls for either side — a deterministic Dodge SUCCESS,
## never a re-derived hit/miss computation of this suite's own.
func _force_guaranteed_dodge_success(instance) -> void:
	instance._party[0]["skills"] = {"mobility": 500, "determination": 500}


## _resolve_one_real_enemy_strike_with_forced_dodge(instance) -> void — the
## SAME real "end Titus's turn -> Skeleton auto-drives its Strike against
## Titus" flow tests/gut/test_rich_log_enemy_attack.gd already established,
## but with the PreHitAvoidance resolver scripted to ALWAYS choose "dodge"
## (mirrors test_defense_segment_reaction_outcomes.gd's own
## `_resolve_one_real_enemy_strike()` convention) — forcing a genuine
## PreHitAvoidance Dodge resolution to happen for the Skeleton's Strike.
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


# ══════════════════════════════════════════════════════════════════════════
# THE capstone: entry point (scripted attack, forced Dodge, scripted hex) to
# exit point (relocation + correct single rich log row) in ONE test run.
# ══════════════════════════════════════════════════════════════════════════

## _assert_seams_are_the_real_composition_root_bindings(instance) -> void —
## FEAT-218 (closes PR-001/G2): identity/regression guard proving the ports
## this suite's assertions rest on are still the EXACT Callables/objects
## MainScene.gd's own composition root bound at boot -- never a local
## double this (or any other) test body silently re-wired underneath the
## capstone assertions above/below. Mirrors
## tests/gut/test_seam_composition_root_wiring.gd's own identity checks
## exactly; invoked at multiple points in this test body (before AND after
## the deliberate, documented hex_choice_resolver substitution below) so a
## future edit that accidentally re-wires ANY of these seams to a test-local
## double fails immediately, here, rather than only in the dedicated suite.
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


func test_capstone_successful_dodge_relocates_defender_and_renders_single_rich_log_row_with_dodge_defense_segment() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")

	# FEAT-218 (G2 gap closure): prove the seams this test is about to
	# exercise are the real composition-root bindings BEFORE this suite
	# scripts anything.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	var defender = instance._party[0]
	assert_eq(defender.name, "Titus", "fixture: Titus (the real player combatant) must be the prologue's defender")
	var defender_id: String = defender.combatant_id

	var original_hex = defender.hex_coord
	assert_not_null(original_hex, "fixture assumption: the defender must already carry a hex_coord at boot")

	var token_before = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_before, "fixture assumption: hex_grid_view must already carry a token for the defender")
	assert_true(token_before.hex_coord.equals(original_hex), "the on-screen token must start at the defender's pre-Strike hex")

	# ── Default, un-overridden composition-root wiring: this MUST still be
	# the REAL production HexChoiceResolverPort adapter (never a test double)
	# before this suite scripts a chosen hex below — proving the seam this
	# suite is about to drive really is the same one MainScene.gd wires for a
	# real player, mirroring tests/gut/test_hex_choice_seam_dodge_step.gd's
	# own regression check. ──────────────────────────────────────────────────
	assert_not_null(instance.hex_choice_resolver, "MainScene must wire a default hex_choice_resolver during initialization")
	assert_true(
		is_instance_of(instance.hex_choice_resolver, HexChoiceResolverPortClass),
		"the default-wired hex_choice_resolver must satisfy the HexChoiceResolverPort contract"
	)

	# ── Entry point: attacker (the Skeleton) strikes the defender (Titus),
	# with a FORCED-successful Dodge (Titus's Mobility check is guaranteed to
	# beat the attacker's roll_total, per Resolution.resolve_to_hit()'s own
	# math — never re-derived here). ────────────────────────────────────────
	_force_guaranteed_dodge_success(instance)
	_resolve_one_real_enemy_strike_with_forced_dodge(instance)

	# ── Exit point (half 1): exactly one visible row for this ONE attack,
	# rendered rich, carrying the correct "Defense: dodge…" segment. ────────
	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"exactly one row (total) may exist after the ONE resolved, forced-Dodge Strike -- no basic+rich duplicate pair"
	)
	var row_text: String = instance.event_log_view.get_row_text(0)
	assert_true(row_text != "", "get_row_text(0) must be non-empty after the resolved, forced-Dodge Strike")
	assert_string_contains(row_text, "roll", "the rich row must render the roll_total field")
	assert_string_contains(row_text, "Defense: dodge", "the rich row must render the Dodge active-defense segment for this Strike")

	var attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the visible row must carry the attack_event_id it was rendered from")

	var attack_event = instance.event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(attack_event, "the structured AttackEvent recorded via record_attack() must be retrievable for this Strike")
	if attack_event != null:
		assert_true(attack_event.roll_total > 0, "the real resolution.gd math must produce a non-zero roll_total")
		assert_false(attack_event.is_hit, "a successful Dodge must resolve this Strike as a Miss")
		assert_string_contains(row_text, "Miss", "a successful Dodge (a miss) must render the Miss label")

	var paired_reaction = instance.event_log_view.get_paired_reaction(attack_event_id, "PreHitAvoidance")
	assert_not_null(paired_reaction, "record_reaction() must have paired a ReactionResolvedEvent to this Strike's PreHitAvoidance window")
	if paired_reaction != null:
		assert_eq(paired_reaction.choice, "dodge", "the paired reaction's own choice must be the forced 'dodge' this suite scripted")
		assert_eq(paired_reaction.outcome, "dodge_succeeded", "the paired reaction's outcome must confirm the forced Dodge actually succeeded")

	# ── Exit point (half 2): the SAME attack's Dodge-Step now relocates the
	# defender, via the REAL, composition-root-wired seams (hex_choice_resolver
	# / _token_reposition_fn / _step_hex_query_fn) -- driven the SAME way
	# every prior feature in this steel thread already established as this
	# codebase's accepted convention (see this file's top-level doc). ───────
	var legal_hexes: Array = instance._query_selectable_step_hexes(defender_id)
	assert_true(legal_hexes.size() > 0, "fixture assumption: the defender must have at least one legal Step destination after the forced Dodge")
	var chosen_hex = legal_hexes[0]
	assert_false(chosen_hex.equals(original_hex), "fixture assumption: the scripted chosen hex must actually differ from the defender's current hex")

	assert_true(defender.hex_coord.equals(original_hex), "sanity: the defender must not yet have moved before the Dodge-Step prompt is driven")

	var scripted := ScriptedHexChoiceResolver.new(chosen_hex)
	instance.hex_choice_resolver = scripted

	# FEAT-218 (G2 gap closure): the line above deliberately substitutes ONLY
	# the leaf `hex_choice_resolver` field -- this codebase's established,
	# documented convention (see this file's top-level doc) for scripting a
	# legal Step choice without a live human click. Prove the
	# round_session-LEVEL seam Callable itself (`_hex_choice_resolver_fn`,
	# and every other port this test depends on) is still the REAL
	# composition-root binding, never a second, parallel seam re-wired
	# alongside that documented substitution.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	# Re-assert once more after driving the Dodge-Step prompt: no seam was
	# silently swapped out for a local double as a side effect of driving it.
	_assert_seams_are_the_real_composition_root_bindings(instance)

	assert_eq(scripted.call_count, 1, "the SAME successful Dodge this attack just resolved must invoke the Step-selection prompt exactly once")

	# Criterion: defender Combatant.hex_coord equals the chosen hex.
	assert_true(
		defender.hex_coord.equals(chosen_hex),
		"the defender's Combatant.hex_coord must equal the scripted chosen hex after the successful Dodge-Step"
	)

	# Criterion: the on-screen token (hex_grid_view Node2D position) visibly
	# moved to the chosen hex, in the SAME test run as the log assertions
	# above.
	var token_after = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_after, "the defender's token must still be on record after the Dodge-Step reposition")
	assert_true(
		token_after.hex_coord.equals(chosen_hex),
		"the defender's on-screen token hex must update to the scripted chosen hex"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel_with_offset(chosen_hex),
		"the defender's rendered screen position must resync to the chosen hex's axial-to-pixel projection"
	)

	# ── Re-assert the SAME attack's log row is still the ONLY one, unchanged
	# by the subsequent relocation -- the log row and the relocation both
	# describe ONE resolved attack, verified together in this ONE test run. ──
	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"the Dodge-Step relocation itself must log no additional row -- still exactly one row for this ONE attack"
	)
	assert_eq(
		instance.event_log_view.get_row_text(0), row_text,
		"the attack's own rich log row must remain byte-for-byte unchanged by the later Dodge-Step relocation"
	)

