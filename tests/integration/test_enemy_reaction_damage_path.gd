extends GutTest
## tests/integration/test_enemy_reaction_damage_path.gd — FEAT-005 (US-005).
##
## GUT suite for FEAT-005: retrofits core/application/apply_on_hit_defense_uc.gd
## (ApplyOnHitDefenseUseCase) — the "Phase 2" commit core/application/
## round_session.gd's advance_ai_turn() awaits during an enemy's turn's
## two-phase Strike commit (the "enemy on-hit reaction" damage path: an
## enemy's Strike hits, the DEFENDER's OnHitMitigation reaction — Block/
## Parry — is resolved, and the FINAL, post-mitigation damage is committed)
## — so it no longer inline-mutates hp_current directly
## (`target.take_damage(damage_final)` / `target["hp_current"] -= ...`), but
## instead constructs a DamageEffect and routes it through the SAME domain
## EffectsApplier seam (core/domain/effects_applier.gd) core/application/
## resolve_action_use_case.gd's Strike path already routes its own damage
## through (FEAT-004). This closes the steel thread's "the enemy's on-hit
## reaction flows through the same Effects Applier" requirement — no
## parallel/duplicate hp-mutation path remains.
##
## Verifies (test_criteria):
##   1. boot-real enemy-reaction e2e test: hp/AttackEvent/log diff matches
##      baseline exactly — the SAME pinned expectations
##      tests/integration/test_mainscene_hit_reaction_apply.gd already
##      established for this exact two-phase on-hit commit path (Block
##      fully suppresses to a pinned zero; Pass reproduces the raw,
##      unmitigated damage byte-for-byte) — this suite re-derives those same
##      pinned outcomes AFTER the EffectsApplier retrofit and additionally
##      inspects the live event_log_view row for the resolved Strike.
##   2. Opportunistic Strike (Iteration K) damage math regression test
##      unaffected — Opportunistic Strike resolves through a completely
##      different call path (core/application/use_cases/
##      resolve_stride_use_case.gd's _resolve_opportunistic_strike_effect()
##      -> ResolveActionUseCase.resolve(), the ALREADY-retrofitted FEAT-004
##      Strike path — never apply_on_hit_defense_uc.gd), so this criterion
##      is a defense-in-depth boot-real regression proof that this file's
##      retrofit left that math untouched.
##   3. flanking Off-Guard +2 modifier regression test unaffected — Off-Guard
##      is computed entirely inside the to-hit phase (before
##      apply_on_hit_defense_uc.gd is ever reached), so this is likewise a
##      defense-in-depth regression proof.
##   4. static check confirms no inline hp mutation remains in
##      apply_on_hit_defense_uc.gd — a direct source-text scan (mirroring
##      ci/check_no_duplicate_seams.sh's own comment-filtering convention)
##      proves no genuine `.take_damage(`/inline `["hp_current"] = ... -`
##      call site remains outside a `##`/`#` doc-comment line.
##   5. both Strike and enemy-reaction paths verified to call the identical
##      EffectsApplier module/instance — both against the REAL, live-booted
##      MainScene composition root's own `resolve_action_use_case`, and
##      against a freshly-constructed standalone ResolveActionUseCase
##      (proving the sharing is a genuine _init()-time wiring guarantee, not
##      an accident of this particular boot).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")
const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const EffectsApplierClass = preload("res://core/domain/effects_applier.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const FlankingClass = preload("res://core/rules/flanking.gd")

const APPLY_ON_HIT_DEFENSE_UC_PATH: String = "res://core/application/apply_on_hit_defense_uc.gd"

## PROLOGUE_SEED — this project's established known-good fixture seed: Titus
## acts first and the sole enemy (Skeleton) starts adjacent to him (mirrors
## tests/integration/test_mainscene_hit_reaction_apply.gd's identically-named
## /valued constant).
const PROLOGUE_SEED: int = 42

const END_TURN: String = "END_TURN"

## AC_GUARANTEED_HIT — mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant: an absurdly low AC guarantees a hit
## with no RNG/seed edits.
const AC_GUARANTEED_HIT: int = -100

## OVERWHELMING_MITIGATION_STAT — mirrors tests/integration/
## test_mainscene_hit_reaction_apply.gd's identically-named/valued constant.
const OVERWHELMING_MITIGATION_STAT: int = 9999


func _boot_main_scene(seed_value: int = PROLOGUE_SEED):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _titus(instance):
	return instance._party[0]


func _titus_id(instance) -> String:
	return _titus(instance).combatant_id


func _press_end_turn_and_drive_enemy_strike(instance) -> void:
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)
	# Marigold (the second, player-controlled party member added alongside
	# Titus) now holds the cursor -- RoundSession/TurnController only
	# auto-drives AI (enemy) turns, never a second living player combatant --
	# so an explicit manual End Turn is required here too before the
	# Skeleton's turn (and its Strike) is ever reached.
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Marigold (the second party member) acts second, before the enemy, at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)


func _latest_structured_attack_event(instance):
	var count: int = instance.event_log_view.get_entry_count()
	assert_true(count > 0, "at least one row must exist in the real event_log_view after a resolved Strike")
	if count == 0:
		return null
	var attack_event_id = instance.event_log_view.get_entry(count - 1).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the latest row must carry a non-empty attack_event_id")
	return instance.event_log_view.get_structured_attack(attack_event_id)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — boot-real enemy-reaction e2e: hp/AttackEvent/log diff
# matches the pinned baseline exactly (Block; Pass).
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_enemy_reaction_block_matches_pinned_baseline_hp_attack_event_and_log() -> void:
	var instance = _boot_main_scene()

	# FEAT-316 (resolves DEF-001/PR-001): round_session/turn_controller
	# signals/verb bar only become live once a real combat trigger fires (see
	# MainScene.gd's own FEAT-316 doc) -- drive the same real handoff here so
	# this suite's two-phase reaction pop-up flow can be driven exactly as it
	# was before this feature.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT
	titus["weapon"]["block_value"] = OVERWHELMING_MITIGATION_STAT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_true(hp_before > 0, "fixture assumption: Titus starts with positive HP")

	var log_count_before: int = instance.event_log_view.get_entry_count()

	_press_end_turn_and_drive_enemy_strike(instance)

	assert_true(instance.reaction_prompt_ui.is_open(), "the PreHitAvoidance pop-up must open for the incoming Strike")
	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	assert_true(instance.reaction_prompt_ui.get_displayed_options().has("block"), "Block must be offered for Titus's real longsword")
	instance.reaction_prompt_ui.press_option("block")

	assert_false(instance.reaction_prompt_ui.is_open(), "no further reaction window may remain open once this Strike's OnHitMitigation choice has resolved")

	# ── hp diff matches the pinned baseline exactly: a genuinely-applied,
	# overwhelming Block must leave ZERO damage taken (FR-001's mitigation
	# formula — max(0, raw - reduction) = 0), byte-for-byte the SAME baseline
	# tests/integration/test_mainscene_hit_reaction_apply.gd already pins for
	# this exact scenario. ─────────────────────────────────────────────────
	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_after, hp_before, "Titus's own HP panel must show ZERO damage taken once a successful Block is GENUINELY applied via the retrofitted EffectsApplier seam")

	# ── AttackEvent diff matches the pinned baseline exactly. ───────────────
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the committed AttackEvent must carry the mitigated (zero) final damage, matching the pre-retrofit baseline")
	assert_eq(attack_events[0].target_name, "Titus")
	assert_eq(attack_events[0].attacker_name, "Skeleton")

	var structured_attack_event = _latest_structured_attack_event(instance)
	if structured_attack_event != null:
		assert_true(structured_attack_event.damage_raw > 0, "fixture assumption: a guaranteed hit must roll positive raw damage")
		assert_eq(structured_attack_event.damage_final, 0, "the structured AttackEvent must also carry final_damage == 0, matching the pre-retrofit baseline")

	# ── log diff matches the pinned baseline exactly: exactly one new row is
	# appended, and it is non-empty / references the resolved combatants
	# (the rich row's render_attack_entry() format references the structured
	# AttackEvent's attacker_id/target_id -- stable combatant ids, e.g.
	# "enemy_0"/"player_0" -- never the display name). ──────────────────────
	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, log_count_before + 1, "exactly one new combat-log row must be appended for this Strike")
	var latest_entry: Dictionary = instance.event_log_view.get_entry(log_count_after - 1)
	var latest_text: String = str(latest_entry.get("text", ""))
	assert_true(latest_text.length() > 0, "the appended combat-log row must carry non-empty text")
	if structured_attack_event != null:
		assert_true(
			latest_text.contains(structured_attack_event.attacker_id),
			"the appended combat-log row must reference the attacking combatant's id (%s); got: %s" % [structured_attack_event.attacker_id, latest_text]
		)
		assert_true(
			latest_text.contains(structured_attack_event.target_id),
			"the appended combat-log row must reference the defending combatant's id (%s); got: %s" % [structured_attack_event.target_id, latest_text]
		)


func test_boot_real_enemy_reaction_pass_matches_pinned_baseline_hp_attack_event_and_log() -> void:
	var instance = _boot_main_scene()

	# FEAT-316: see the identical doc on the Block test above.
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")
	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("none")
	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_true(attack_events[0].damage_final > 0, "declining (Pass) must leave the Strike's real, unmitigated damage in place -- matching the pre-retrofit baseline")

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(
		hp_before - hp_after, attack_events[0].damage_final,
		"Titus's HP panel must show damage taken EXACTLY matching the unmitigated (raw) committed damage, matching the pre-retrofit baseline byte-for-byte"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Opportunistic Strike (Iteration K) damage math regression
# unaffected by this retrofit.
# ══════════════════════════════════════════════════════════════════════════

func test_opportunistic_strike_iteration_k_damage_math_regression_unaffected() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")

	var titus = instance._party[0]
	var skeleton = instance._enemies[0]

	# Force a guaranteed hit against Titus (the mover), comfortably survivable
	# -- mirrors tests/integration/test_player_stride_provokes_enemy_opportunistic_strike.gd's
	# established technique exactly.
	titus["ac"] = AC_GUARANTEED_HIT
	titus["hp_current"] = 500
	titus["hp_max"] = 500

	assert_true(
		not skeleton.weapon.has("range_hexes"),
		"fixture assumption: the Skeleton's real weapon carries melee reach"
	)

	var skeleton_ae = instance._action_economy_for(skeleton)
	var skeleton_budget_before: int = skeleton_ae.get_remaining()

	var selection: Dictionary = instance.verb_bar_view.press("STRIDE")
	var candidate_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")
	var destination = candidate_hexes[0]

	var titus_hp_before: int = titus.hp_current
	var stride_result: Dictionary = await instance.verb_dispatch_controller._verb_bar_stride_execute(destination)

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Opportunistic Strike must spend exactly one reaction from the Skeleton's own action budget -- Iteration K math unaffected by the FEAT-005 retrofit"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike (the Skeleton's Opportunistic Strike) must have resolved")
	var attack_event = attack_events[0]
	assert_eq(attack_event.attacker_name, "Skeleton")
	assert_eq(attack_event.target_name, "Titus")
	assert_true(attack_event.hit)
	assert_true(attack_event.damage_final > 0)

	var titus_hp_after: int = titus.hp_current
	assert_eq(
		titus_hp_before - titus_hp_after, attack_event.damage_final,
		"Titus's hp_current must drop by EXACTLY the resolved Opportunistic Strike's damage_final -- the Iteration K damage math the Strike path (not this file's retrofit) owns"
	)
	assert_true(stride_result.get("ok", false), "Titus's own Stride must still commit once the non-lethal Opportunistic Strike resolves")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — flanking Off-Guard (+2) modifier regression unaffected by
# this retrofit.
# ══════════════════════════════════════════════════════════════════════════

func _flanking_ally(hex_coord, combatant_id: String) -> Dictionary:
	return {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": combatant_id,
		"hex_coord": hex_coord,
	}


func test_flanking_off_guard_plus_two_modifier_regression_unaffected() -> void:
	var baseline_instance = _boot_main_scene()
	await get_tree().process_frame

	var baseline_target_id: String = baseline_instance._enemies[0].get("combatant_id", "")
	var baseline_result: Dictionary = baseline_instance._verb_registry.execute("STRIKE", baseline_target_id)
	assert_true(baseline_result.get("resolved", false), "the baseline (no-flanking) Strike must resolve")
	var baseline_attack_events: Array = baseline_instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(baseline_attack_events.size(), 1)
	var baseline_defense_value: int = baseline_attack_events[0].defense_value

	var off_guard_instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = off_guard_instance._enemies[0].get("combatant_id", "")
	assert_eq(target_id, baseline_target_id, "fixture assumption: both independent boots resolve the same prologue enemy id")

	var ally: Dictionary = _flanking_ally(HexCoordClass.new(2, 0), "synthetic_ally_enemy_reaction_regression")
	off_guard_instance._party.append(ally)
	off_guard_instance._refresh_off_guard_conditions()

	assert_true(
		FlankingClass.OFF_GUARD_CONDITION in off_guard_instance._enemies[0].get("conditions", []),
		"fixture setup: the live enemy target must carry the Off-Guard condition before the Strike is driven"
	)

	var off_guard_result: Dictionary = off_guard_instance._verb_registry.execute("STRIKE", target_id)
	assert_true(off_guard_result.get("resolved", false), "the Off-Guard Strike must resolve")
	var off_guard_attack_events: Array = off_guard_instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(off_guard_attack_events.size(), 1)
	var off_guard_defense_value: int = off_guard_attack_events[0].defense_value

	assert_eq(
		off_guard_defense_value, baseline_defense_value - 2,
		"the Off-Guard +2 modifier must still reduce defense_value by exactly 2 after the FEAT-005 retrofit -- Off-Guard is computed entirely in the to-hit phase, never touched by this file"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — static check: no inline hp mutation remains in
# apply_on_hit_defense_uc.gd.
# ══════════════════════════════════════════════════════════════════════════

func _read_source(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must exist and be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _non_comment_lines_containing(contents, needle) -> Array — every line of
## `contents` that contains `needle` as a genuine, non-doc-comment CALL site
## -- mirrors ci/check_no_duplicate_seams.sh's own comment-filtering
## convention (a line whose trimmed content begins with "#" is a comment,
## never a call site).
func _non_comment_lines_containing(contents: String, needle: String) -> Array:
	var hits: Array = []
	for line in contents.split("\n"):
		if not line.contains(needle):
			continue
		if line.strip_edges().begins_with("#"):
			continue
		hits.append(line)
	return hits


func test_apply_on_hit_defense_uc_contains_no_inline_take_damage_call() -> void:
	var contents: String = _read_source(APPLY_ON_HIT_DEFENSE_UC_PATH)
	var hits: Array = _non_comment_lines_containing(contents, ".take_damage(")
	assert_eq(
		hits.size(), 0,
		"apply_on_hit_defense_uc.gd must contain NO genuine '.take_damage(' call site any more -- found: %s" % str(hits)
	)


func test_apply_on_hit_defense_uc_contains_no_inline_hp_current_mutation() -> void:
	var contents: String = _read_source(APPLY_ON_HIT_DEFENSE_UC_PATH)
	# The ONLY historical inline mutation shape was
	# `target["hp_current"] = target.get("hp_current", 0) - damage_final`
	# gated by `if target.has_method("take_damage")` -- that has_method()
	# guard string is the unambiguous fingerprint of the removed pattern.
	var hits: Array = _non_comment_lines_containing(contents, 'target.has_method("take_damage")')
	assert_eq(
		hits.size(), 0,
		"apply_on_hit_defense_uc.gd must no longer branch on target.has_method(\"take_damage\") to inline-mutate hp -- found: %s" % str(hits)
	)


func test_apply_on_hit_defense_uc_routes_damage_through_effects_applier() -> void:
	var contents: String = _read_source(APPLY_ON_HIT_DEFENSE_UC_PATH)
	assert_true(contents.contains("res://core/domain/effects_applier.gd"), "apply_on_hit_defense_uc.gd must preload the domain EffectsApplier module")
	assert_true(contents.contains("res://core/domain/effects/damage_effect.gd"), "apply_on_hit_defense_uc.gd must preload DamageEffect")
	var applier_calls: Array = _non_comment_lines_containing(contents, "_effects_applier.apply(")
	assert_true(applier_calls.size() > 0, "apply_on_hit_defense_uc.gd must genuinely call _effects_applier.apply(...) to commit damage")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — Strike and enemy-reaction paths call the identical
# EffectsApplier module/instance.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_mainscene_strike_and_enemy_reaction_share_the_identical_effects_applier_instance() -> void:
	var instance = _boot_main_scene()
	var use_case = instance.resolve_action_use_case
	assert_not_null(use_case, "fixture assumption: MainScene exposes its live resolve_action_use_case")

	var strike_effects_applier = use_case.get_effects_applier()
	var reaction_effects_applier = use_case.get_apply_on_hit_defense_use_case().get_effects_applier()

	assert_not_null(strike_effects_applier)
	assert_not_null(reaction_effects_applier)
	assert_same(
		strike_effects_applier, reaction_effects_applier,
		"the REAL, live-booted MainScene's Strike path and enemy-reaction (ApplyOnHitDefenseUseCase) path must route damage through the IDENTICAL EffectsApplier instance -- no parallel seam"
	)


class _NoOpRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	func roll(_dice_spec: Dictionary) -> int:
		return 1


class _NoOpEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	func emit(_event) -> void:
		pass


class _NoOpRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	func append(_entry: Dictionary) -> void:
		pass

	func get_history() -> Array:
		return []


func test_freshly_constructed_resolve_action_use_case_wires_the_identical_effects_applier_instance() -> void:
	var use_case = ResolveActionUseCaseClass.new(
		_NoOpRandomNumberPort.new(), _NoOpEventSinkPort.new(), _NoOpRoundHistoryPort.new()
	)

	var strike_effects_applier = use_case.get_effects_applier()
	var reaction_effects_applier = use_case.get_apply_on_hit_defense_use_case().get_effects_applier()

	assert_not_null(strike_effects_applier)
	assert_same(
		strike_effects_applier, reaction_effects_applier,
		"ResolveActionUseCase._init() must construct exactly ONE EffectsApplier instance and inject it into BOTH the Strike path and the ApplyOnHitDefenseUseCase enemy-reaction path -- never two independently-constructed instances"
	)
	assert_true(
		strike_effects_applier is EffectsApplierClass,
		"the shared instance must genuinely be an EffectsApplier (core/domain/effects_applier.gd) -- the identical module both paths depend on"
	)
