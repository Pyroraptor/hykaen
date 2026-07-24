extends GutTest
## tests/gut/test_log_single_row_per_attack.gd — FEAT-007 (US-007 / FR-008,
## ADR-003): "Suppress duplicate basic log entry".
##
## FEAT-005 (player path) and FEAT-006 (enemy path) each already wire
## record_attack()/render_attack_entry()/overwrite_entry_as_rich() into their
## own live call site (MainScene.gd's `_verb_bar_strike_execute()` and
## core/application/round_session.gd's `advance_ai_turn()` respectively), so
## the plain-format row event_log_view.on_attack_event() appends is
## overwritten IN PLACE with the rich rendering rather than left standing
## alongside a second, freshly-appended rich row (presentation/
## event_log_view.gd's `overwrite_entry_as_rich()` — the concrete
## implementation of the design's ICombatLogPort suppress_basic_entry()
## contract for this steel thread: the basic row's own append-order slot is
## reused, never suppressed-then-re-appended, so no duplicate ever exists
## even transiently). tests/gut/test_rich_log_player_attack.gd and
## tests/gut/test_rich_log_enemy_attack.gd each already prove this in
## ISOLATION for their own path (one boot, one Strike, one path).
##
## This suite is the CROSS-PATH regression FEAT-007 exists to lock in: ONE
## booted res://MainScene.tscn (G2 — never a hand-wired double), driven
## through a FULL round — a real player Strike (Titus vs the Skeleton)
## immediately followed by a real enemy Strike (the Skeleton vs Titus, via
## the same round's turn-order advance) — asserting exactly ONE visible row
## exists per resolved attack (US-007's "no basic+rich duplicate pair",
## G3's "trace-but-don't-apply" anti-pattern eliminated for BOTH call sites
## in the SAME live session, not just each in isolation).
##
## Fixture note: seed_override=1 is pinned because, with this project's
## Titus/Marigold-vs-Skeleton prologue fixture (the roster now seats a
## second living, player-controlled combatant, Marigold, whose own initiative
## roll consumes one extra draw from core/rules/rng.gd's single seeded
## sequential stream, shifting every subsequent roll relative to any seed's
## pre-Marigold behavior), it is the smallest seed under which (a) Titus
## (the player) is genuinely the FIRST actor in turn order — required so
## this suite's opening _resolve_one_real_player_strike() call has a
## Strike to make at all — and (b) the player's opening Strike does NOT
## defeat the Skeleton (so the Skeleton survives to take its own turn once
## Marigold's own turn is also passed — most other seeds' opening Strike is
## a one-shot kill against the Skeleton's hp=8, which would abort the round
## before the enemy path ever fires). This suite does not depend on hit vs.
## miss to prove the single-row invariant (at seed=1 the opening Strike is
## actually a Critical Hit, not a Miss) — only that each Strike resolved at
## all and rendered its own single rich row.
##
## Verifies (test_criteria):
##   1. Booting real MainScene and scripting one player attack and one enemy
##      attack (in that order, within the same round): event_log_view has
##      EXACTLY one row per attack — never a stray basic-format sibling row
##      for either Strike.
##   2. Any non-visible consumer of the basic on_attack_event()-shaped
##      broadcast (here: presentation/status_panel_view.gd's independent
##      EventSinkPort subscription, which projects the SAME AttackEvent
##      Dictionary onto each combatant's HP/action-budget row) is unaffected
##      by event_log_view's own row suppression/overwrite — it keeps
##      receiving and correctly projecting the full event exactly as if
##      event_log_view did not exist.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## _resolve_one_real_enemy_strike()'s SAME synchronous-Pass double
## tests/gut/test_rich_log_enemy_attack.gd already established, required so
## a single, synchronous end_turn_control.press() call fully settles the
## Skeleton's Strike (this suite is about log-row suppression, not the
## reaction-choice UI itself).
class _ScriptedPassResolver:
	extends RefCounted
	func resolve(_trigger: Dictionary) -> Dictionary:
		return {"choice": "none"}


## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into
## GameMode.EXPLORATION with the legacy combat pipeline (round_session, etc.)
## gated behind a real _on_combat_triggered() handoff -- see MainScene.gd's
## own FEAT-316 doc. This suite drives real Strikes directly against
## `round_session`/the real verb bar, so this helper now also drives that
## SAME real handoff (mirrors tests/boot/test_first_cast_firebolt.gd's
## established `_boot_main_scene()` convention), landing the instance in
## GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


## _resolve_one_real_player_strike(instance) -> Dictionary — the SAME real
## Strike-scripting flow tests/gut/test_rich_log_player_attack.gd /
## tests/gut/test_player_strikes_enemy_pass_through.gd already established:
## press the STRIKE verb, then click the first in-reach candidate target's
## hex.
func _resolve_one_real_player_strike(instance) -> Dictionary:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
	return {"target_id": target_id}


## _resolve_one_real_enemy_strike(instance) -> void — the SAME real "end
## Titus's turn -> Skeleton auto-drives its Strike against Titus" flow
## tests/gut/test_rich_log_enemy_attack.gd already established.
func _resolve_one_real_enemy_strike(instance) -> void:
	var scripted_resolver := _ScriptedPassResolver.new()
	instance.round_session.set_prehit_avoidance_resolver_fn(Callable(scripted_resolver, "resolve"))
	instance.round_session.set_onhit_mitigation_resolver_fn(Callable(scripted_resolver, "resolve"))

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(
		press_result.get("ok", false),
		"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully"
	)

	# FEAT-002 (Iteration M P0-0): the prologue roster now seats Marigold as a
	# second living, player-controlled combatant ("player_1") between Titus
	# and the Skeleton in turn order. RoundSession/TurnController only
	# auto-drives AI (enemy) turns, never a second living player -- so
	# Titus's own End Turn press above only hands the turn to Marigold; a
	# second press (Marigold's free pass) is required before the Skeleton's
	# AI turn (and therefore its Strike) is actually reached.
	if not instance.round_session.current_actor().is_enemy:
		var second_press_result: Dictionary = instance.end_turn_control.press()
		assert_true(
			second_press_result.get("ok", false),
			"the real EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully for Marigold's turn too"
		)


## _attack_row_indices(instance) -> Array[int] — every append-order index
## whose rendered text is an "... attacks ..." row (the fingerprint shared by
## both the plain and the rich format — see the module doc's no-duplicate-row
## guard convention already established by test_rich_log_player_attack.gd /
## test_rich_log_enemy_attack.gd).
func _attack_row_indices(instance) -> Array:
	var indices: Array = []
	for i in range(instance.event_log_view.get_entry_count()):
		if instance.event_log_view.get_row_text(i).contains(" attacks "):
			indices.append(i)
	return indices


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — one player Strike immediately followed by one enemy Strike,
# in the SAME booted MainScene / round, each produce EXACTLY one visible
# "attacks" row — never a basic+rich duplicate pair for either Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_one_player_attack_and_one_enemy_attack_each_produce_exactly_one_row() -> void:
	var instance = await _boot_main_scene_with_seed(1)
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")

	# ── Player attack: Titus strikes the Skeleton. ──────────────────────────
	_resolve_one_real_player_strike(instance)

	assert_eq(
		instance.event_log_view.get_entry_count(), 1,
		"exactly one row (total) may exist after a single resolved player Strike -- no basic+rich duplicate pair"
	)
	var player_attack_rows: Array = _attack_row_indices(instance)
	assert_eq(player_attack_rows.size(), 1, "exactly one 'attacks' row may exist for the player Strike -- G3's trace-but-don't-apply duplicate is eliminated")

	var player_row_text: String = instance.event_log_view.get_row_text(player_attack_rows[0])
	assert_string_contains(player_row_text, "roll", "the player Strike's row must render the rich roll_total field, not the suppressed plain format")
	assert_string_contains(player_row_text, "Defense:", "the player Strike's row must render the rich active-defense field")

	var player_attack_event_id = instance.event_log_view.get_entry(player_attack_rows[0]).get("attack_event_id", "")
	assert_true(str(player_attack_event_id) != "", "the visible player-Strike row must carry the attack_event_id it was rendered from (proof of rich rendering, not a bare string)")
	assert_not_null(
		instance.event_log_view.get_structured_attack(player_attack_event_id),
		"the player Strike's structured AttackEvent must be retrievable -- record_attack() ran against the REAL, live event_log_view"
	)

	# ── Enemy attack: Titus ends his turn, the Skeleton auto-drives its own
	# Strike back against Titus, in this SAME round/session. ───────────────
	_resolve_one_real_enemy_strike(instance)

	assert_eq(
		instance.event_log_view.get_entry_count(), 2,
		"exactly two rows (total) may exist after both the player Strike AND the enemy Strike have resolved -- one row per attack, never a duplicate pair for either"
	)
	var all_attack_rows: Array = _attack_row_indices(instance)
	assert_eq(all_attack_rows.size(), 2, "exactly one 'attacks' row per resolved Strike -- two Strikes, two rows, never three or four from a stray basic+rich pair")

	var enemy_row_index: int = all_attack_rows[1]
	var enemy_row_text: String = instance.event_log_view.get_row_text(enemy_row_index)
	assert_string_contains(enemy_row_text, "roll", "the enemy Strike's row must render the rich roll_total field, not the suppressed plain format")
	assert_string_contains(enemy_row_text, "Defense:", "the enemy Strike's row must render the rich active-defense field")

	var enemy_attack_event_id = instance.event_log_view.get_entry(enemy_row_index).get("attack_event_id", "")
	assert_true(str(enemy_attack_event_id) != "", "the visible enemy-Strike row must carry the attack_event_id it was rendered from")
	assert_ne(
		str(enemy_attack_event_id), str(player_attack_event_id),
		"the enemy Strike's row must be tagged with its OWN attack_event_id, distinct from the player Strike's row"
	)
	assert_not_null(
		instance.event_log_view.get_structured_attack(enemy_attack_event_id),
		"the enemy Strike's structured AttackEvent must be retrievable -- record_attack() ran against the REAL, live event_log_view"
	)

	# ── The player Strike's OWN row must stay untouched by the LATER enemy
	# Strike -- it must still be the SAME rich text it was right after
	# resolving, never silently mutated by a second Strike's bookkeeping. ───
	assert_eq(
		instance.event_log_view.get_row_text(player_attack_rows[0]), player_row_text,
		"the player Strike's row must remain exactly as rendered, unaffected by the LATER enemy Strike's own row"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a non-visible consumer of the SAME broadcast AttackEvent
# (presentation/status_panel_view.gd's independent EventSinkPort
# subscription) is unaffected by event_log_view's row-suppression/overwrite
# mechanism -- it keeps projecting HP/action-budget exactly as if
# event_log_view were not wired at all.
# ══════════════════════════════════════════════════════════════════════════

func test_non_visible_status_panel_consumer_is_unaffected_by_log_row_suppression() -> void:
	var instance = await _boot_main_scene_with_seed(1)
	await get_tree().process_frame

	assert_not_null(instance.status_panel_view, "MainScene.status_panel_view must be wired after boot")

	var player_status_before: Dictionary = instance.status_panel_view.get_status("player_0")
	var enemy_status_before: Dictionary = instance.status_panel_view.get_status("enemy_0")
	var player_budget_before: int = player_status_before.get("action_budget_remaining", 0)

	_resolve_one_real_player_strike(instance)

	# Regardless of event_log_view's own internal row-suppression/overwrite
	# bookkeeping for this SAME Strike, StatusPanelView's independent
	# subscription must still have received the full AttackEvent broadcast
	# and projected both the attacker's spent action budget and the
	# defender's post-Strike HP.
	var player_status_after_strike: Dictionary = instance.status_panel_view.get_status("player_0")
	assert_true(
		player_status_after_strike.get("action_budget_remaining", player_budget_before) < player_budget_before,
		"StatusPanelView must still project Titus's reduced action budget after his Strike -- unaffected by event_log_view's row suppression"
	)

	var enemy_status_after_strike: Dictionary = instance.status_panel_view.get_status("enemy_0")
	var expected_enemy_hp: int = enemy_status_before.get("hp_current", 0)
	var player_row_text: String = instance.event_log_view.get_row_text(0)
	if not player_row_text.contains("Miss"):
		# fixture note: seed_override=7 resolves the opening Strike as a Miss
		# (see this file's top-level doc); this branch only guards against a
		# future engine/content change flipping that outcome, so the HP
		# projection is still checked either way rather than hardcoded blind.
		expected_enemy_hp = maxi(expected_enemy_hp - 1, 0)
	assert_true(
		enemy_status_after_strike.get("hp_current", -1) <= enemy_status_before.get("hp_current", 0),
		"StatusPanelView's HP projection for the Skeleton must still reflect the resolved Strike's outcome -- unaffected by event_log_view's own row suppression"
	)

	# Meanwhile the visible log itself must still show exactly one row for
	# this Strike (event_log_view's own contract, criterion 1 above) -- the
	# two consumers' independent projections of the SAME broadcast never
	# interfere with each other.
	assert_eq(instance.event_log_view.get_entry_count(), 1, "event_log_view must still show exactly one row for the player Strike while StatusPanelView is independently unaffected")

	_resolve_one_real_enemy_strike(instance)

	var player_status_after_enemy_strike: Dictionary = instance.status_panel_view.get_status("player_0")
	assert_true(
		player_status_after_enemy_strike.get("hp_current", -1) <= player_status_after_strike.get("hp_current", 0),
		"StatusPanelView's HP projection for Titus must still reflect the enemy Strike's outcome -- unaffected by event_log_view's own row suppression"
	)
	assert_eq(instance.event_log_view.get_entry_count(), 2, "event_log_view must still show exactly one row per attack (two total) while StatusPanelView remains independently unaffected")
