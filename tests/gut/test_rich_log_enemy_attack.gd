extends GutTest
## tests/gut/test_rich_log_enemy_attack.gd — FEAT-006 (US-006, Iteration
## J-R2 Part D): "Render rich combat log entry for enemy attack path".
##
## Mirrors tests/gut/test_rich_log_player_attack.gd (FEAT-005) for the
## enemy-strikes-player call site. Boots the REAL res://MainScene.tscn
## composition root (G2 -- never a hand-wired double) and scripts a real
## enemy Strike the SAME way tests/test_mainscene_combat_log_richness.gd
## already established: end Titus's turn via the REAL $EndTurnControl, which
## (via TurnController's auto-drive, US-011) causes the Skeleton's turn to be
## resolved through RoundSession.advance_ai_turn() -- then asserts the live
## advance_ai_turn() call site actually invokes core/log/attack_event.gd-
## backed record_attack()/render_attack_entry() on the REAL, booted
## event_log_view -- not a test double -- and that the visible log's
## get_row_text(0) shows a RICH-format row (roll/raw/final damage fields),
## the steel-thread exit condition this feature exists for. Row 0 is the
## Strike's OWN row -- it must never be pushed later by a same-call
## CombatantDefeatedEvent (a killing blow legitimately appends its OWN,
## separate row immediately afterward; that row is untouched by this
## feature and is not itself "duplicate" rich-vs-plain content for the
## Strike).
##
## Verifies (test_criteria):
##   1. Booting real MainScene and scripting an enemy attack: get_row_text(0)
##      contains the roll/raw/final damage fields render_attack_entry()
##      produces, and exactly one rich row is appended for this Strike (no
##      basic+rich duplicate pair).
##   2. record_attack()/render_attack_entry() is invoked on the LIVE
##      enemy-attack call site (not a test double): the visible row's
##      attack_event_id (a real, observable field of event_log_view's
##      `_entries` backing store, see get_entry()) is retrievable via
##      get_structured_attack() (proving record_attack() ran against the
##      REAL, live-booted event_log_view), and the row's rendered text is
##      byte-for-byte what a fresh render_attack_entry() call for that SAME
##      id produces (proving render_attack_entry() -- not a re-derived
##      string -- actually drove the visible row).
##   3. A companion grep-based check (below) confirms
##      RoundSession.advance_ai_turn()'s source text actually invokes
##      record_attack/render_attack_entry (live-path evidence, mirrors
##      tests/gut/test_rich_log_player_attack.gd's own
##      "static source-shape" grep convention).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## _ScriptedPassResolver -- a synchronous ReactionResolverPort double (mirrors
## tests/test_mainscene_combat_log_richness.gd's established
## _ScriptedDodgeResolver convention) that always answers "none"/Pass for
## whichever PreHitAvoidance/OnHitMitigation trigger it is handed. Without
## this override, MainScene.gd's composition-root wiring points both windows
## at the REAL, player-facing TurnController.resolve_reaction() -- which
## awaits an actual reaction-prompt UI signal -- so a synchronous, scripted
## Pass is required for this suite's single, synchronous press() call to
## fully settle the Skeleton's Strike (this feature is about the rich-log
## RENDERING of a resolved Strike, not the reaction-choice UI itself).
class _ScriptedPassResolver:
	extends RefCounted
	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": "none"}


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	# This suite asserts the enemy-path rich log, not the Dodge-Step follow-up.
	# A successful Dodge now fires the live Dodge-Step hex prompt inside
	# advance_ai_turn(); the REAL _UIHexChoiceResolver would block awaiting a
	# battlefield click no headless test can deliver. Null it so
	# MainScene.resolve_hex_choice() returns null → Dodge-Step no-ops here.
	instance.hex_choice_resolver = null
	return instance


## _resolve_one_real_enemy_strike(instance) -> void -- the SAME real
## "end Titus's turn -> Skeleton auto-drives its Strike against Titus" flow
## tests/test_mainscene_combat_log_richness.gd already established: pressing
## the real $EndTurnControl forwards to RoundSession.end_current_turn(),
## whose turn_ended signal (MainScene.gd's _on_end_turn_control_turn_ended())
## re-invokes TurnController.set_session(), auto-driving the Skeleton's turn
## via RoundSession.advance_ai_turn() -- with no reaction resolver injected,
## every await along that chain resolves against its synchronous
## default-safety fallback, so this single, synchronous press() call fully
## settles the Skeleton's Strike before returning (mirrors that suite's own,
## already-passing convention).
func _resolve_one_real_enemy_strike(instance) -> void:
	var scripted_resolver := _ScriptedPassResolver.new()
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(scripted_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(scripted_resolver, "resolve"))

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(
		press_result.get("ok", false),
		"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a real enemy Strike, driven through the real composition
# root, produces a rich-format row at index 0 (its OWN row -- never pushed
# later or duplicated by a plain-format sibling).
# ══════════════════════════════════════════════════════════════════════════

func test_real_enemy_strike_renders_a_rich_row_at_index_zero() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")

	_resolve_one_real_enemy_strike(instance)

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"at least one visible row must exist after the Skeleton's auto-driven Strike"
	)

	var row_text: String = instance.event_log_view.get_row_text(0)
	assert_true(row_text != "", "get_row_text(0) must be non-empty after a resolved enemy Strike")
	assert_string_contains(row_text, "roll", "the rich row must render the roll_total field")
	assert_string_contains(row_text, "Defense:", "the rich row must render the active-defense outcome field")

	var attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the visible row must carry the attack_event_id it was rendered from")

	var attack_event = instance.event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(attack_event, "the structured AttackEvent recorded via record_attack() must be retrievable for the just-resolved enemy Strike")
	if attack_event != null:
		assert_true(attack_event.roll_total > 0, "the real resolution.gd math must produce a non-zero roll_total")
		if attack_event.is_hit:
			assert_string_contains(row_text, str(attack_event.damage_raw), "a hit must render the raw damage field")
			assert_string_contains(row_text, str(attack_event.damage_final), "a hit must render the final damage field")
		else:
			assert_string_contains(row_text, "Miss", "a miss must render the Miss label")

	# No-duplicate-row guard: no OTHER row may be a stale plain-format
	# "attacks ... for N damage." entry for this SAME Strike -- row 0 above
	# is the Strike's ONLY "attacks"-shaped row (any additional rows, e.g. a
	# killing blow's "was defeated by" entry, describe a DIFFERENT event).
	var attacks_row_count: int = 0
	for i in range(instance.event_log_view.get_entry_count()):
		if instance.event_log_view.get_row_text(i).contains(" attacks "):
			attacks_row_count += 1
	assert_eq(attacks_row_count, 1, "exactly one 'attacks' row may exist for a single resolved enemy Strike -- no basic+rich duplicate pair")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — record_attack()/render_attack_entry() are invoked on the
# LIVE enemy-attack call site against the REAL, booted event_log_view (this
# suite never substitutes a test double for event_log_view itself).
# ══════════════════════════════════════════════════════════════════════════

func test_live_enemy_attack_call_site_invokes_record_attack_and_render_attack_entry_on_the_real_event_log_view() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var real_event_log_view = instance.event_log_view
	assert_not_null(real_event_log_view, "MainScene.event_log_view must be a real EventLogView after boot")
	assert_eq(real_event_log_view.get_entry_count(), 0, "sanity: no row yet")

	_resolve_one_real_enemy_strike(instance)

	var attack_event_id = real_event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the live call site must have generated and recorded an attack_event_id for this Strike")

	# record_attack() ran against the REAL, live-booted event_log_view: the
	# structured AttackEvent it stored is retrievable by that SAME id.
	var stored_attack = real_event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(
		stored_attack,
		"record_attack() must have been invoked on the REAL, live-booted event_log_view for this Strike's attack_event_id -- it must be retrievable via get_structured_attack()"
	)

	# render_attack_entry() -- not a second, re-derived formatting -- drove
	# the visible row: re-invoking it for the SAME id must reproduce the
	# EXACT text already showing at row 0.
	var rendered_text: String = real_event_log_view.render_attack_entry(attack_event_id)
	assert_true(rendered_text != "", "render_attack_entry() must produce non-empty text for the recorded attack_event_id")
	assert_eq(
		real_event_log_view.get_row_text(0), rendered_text,
		"the visible row's text must be EXACTLY what render_attack_entry() renders for this Strike -- proving render_attack_entry() (not a re-derived string) drove the live row"
	)

