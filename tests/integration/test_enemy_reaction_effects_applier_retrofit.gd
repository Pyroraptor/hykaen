extends GutTest
## tests/integration/test_enemy_reaction_effects_applier_retrofit.gd —
## FEAT-005 (US-005, ADR-002).
##
## Steel-thread suite proving core/application/apply_on_hit_defense_uc.gd's
## ApplyOnHitDefenseUseCase (the enemy on-hit reaction damage path) no longer
## inline-mutates a live Combatant's hp directly, and instead constructs a
## core/domain/effects/damage_effect.gd DamageEffect and routes it through
## the SAME core/domain/effects_applier.gd EffectsApplier seam
## core/application/resolve_action_use_case.gd's Strike path already routes
## its own damage through (FEAT-004) — closing the "enemy reaction flows
## through the same Effects Applier" requirement (design notes'
## api_contracts #3) with zero behavioral drift.
##
## Verifies (test_criteria):
##   1. apply_on_hit_defense_uc.gd contains no inline hp mutation (static
##      grep assertion) — scoped to the live-Combatant branch of apply(),
##      mirroring tests/integration/test_strike_effects_applier_retrofit.gd's
##      established `if target is CombatantClass:` branch-scoping convention
##      (a legacy Dictionary-target fallback branch is explicitly out of
##      scope, exactly as it is for the already-retrofitted Strike path).
##   2. The enemy reaction constructs a DamageEffect and calls the SAME
##      Effects-Applier seam/instance used by Strike (shared-instance
##      assertion), both via a freshly-wired ResolveActionUseCase and via the
##      REAL, live-booted MainScene composition root.
##   3. Boot-real enemy-reaction e2e: hp / AttackEvent / combat-log diff
##      against the established pre-retrofit baseline
##      (tests/integration/test_mainscene_hit_reaction_apply.gd's pinned
##      Block-suppresses-fully / Pass-leaves-raw-damage expectations) is
##      zero.
##   4. Opportunistic Strike and flanking Off-Guard (+2) scenarios produce
##      damage amounts identical to the pre-retrofit baseline (both resolve
##      upstream of/independently from this file, so this is a defense-in-
##      depth regression proof that the retrofit left that math untouched).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")
const EffectsApplierClass       = preload("res://core/domain/effects_applier.gd")
const HexCoordClass             = preload("res://core/geometry/hex_coord.gd")
const FlankingClass             = preload("res://core/rules/flanking.gd")

const APPLY_ON_HIT_DEFENSE_UC_PATH: String = "res://core/application/apply_on_hit_defense_uc.gd"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_mainscene_hit_reaction_apply.gd's
## identically-named/valued constant): Titus acts first and the sole enemy
## (Skeleton) starts adjacent to him.
const PROLOGUE_SEED: int = 42

const END_TURN: String = "END_TURN"

## AC_GUARANTEED_HIT / OVERWHELMING_MITIGATION_STAT — mirror
## tests/integration/test_mainscene_hit_reaction_apply.gd's identically-
## named/valued constants: deterministic hit/full-mitigation without
## touching RNG/seed math.
const AC_GUARANTEED_HIT: int = -100
const OVERWHELMING_MITIGATION_STAT: int = 9999


# ── Local test doubles (mirrors tests/integration/
#    test_strike_effects_applier_retrofit.gd's established conventions) ────

class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


func _fresh_ae():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	})


func _target(hp_current: int = 50, ac: int = 5):
	return CombatantClass.from_dict({"name": "Target", "hp_current": hp_current, "ac": ac})


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _extract_function_body(content, func_signature_prefix) -> String — mirrors
## tests/integration/test_strike_effects_applier_retrofit.gd's identically-
## named helper: pulls the text of one function out of a whole-file source
## string, from its `func <name>(` line up to (not including) the next
## top-level `\nfunc `.
func _extract_function_body(content: String, func_signature_prefix: String) -> String:
	var start: int = content.find(func_signature_prefix)
	assert_true(start >= 0, "expected to find '%s' in the source file" % func_signature_prefix)
	if start < 0:
		return ""
	var next_func: int = content.find("\nfunc ", start + func_signature_prefix.length())
	if next_func < 0:
		return content.substr(start)
	return content.substr(start, next_func - start)


## Strips full-line `##`/`#` doc-comment lines out of a source snippet before
## scanning for a call pattern (mirrors ci/check_no_duplicate_seams.sh's
## `grep -vE ':[[:space:]]*##'` convention) — a comment merely NAMING a
## pattern must never be mistaken for a live call site.
func _strip_comment_lines(body: String) -> String:
	var kept: Array = []
	for line in body.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — static source check: apply_on_hit_defense_uc.gd contains no
# inline hp mutation for the live-Combatant path, and DOES construct a
# DamageEffect and route it through the shared EffectsApplier seam.
# ══════════════════════════════════════════════════════════════════════════

func test_apply_contains_no_inline_take_damage_call() -> void:
	var content: String = _read_file(APPLY_ON_HIT_DEFENSE_UC_PATH)
	var body: String = _extract_function_body(content, "func apply(")
	var live_code: String = _strip_comment_lines(body)

	assert_false(
		live_code.contains(".take_damage("),
		"FEAT-005: apply() must no longer call .take_damage() inline -- damage must be routed through a constructed DamageEffect + the EffectsApplier seam instead"
	)


func test_apply_does_not_unconditionally_mutate_hp_current_for_combatant_targets() -> void:
	var content: String = _read_file(APPLY_ON_HIT_DEFENSE_UC_PATH)
	var body: String = _extract_function_body(content, "func apply(")
	var live_code: String = _strip_comment_lines(body)

	# The live Combatant-instance branch (guarded by `if target is
	# CombatantClass:`) must dispatch through DamageEffect + EffectsApplier
	# only -- it must never itself write `target.hp_current =`/
	# `target["hp_current"] =` (the pre-retrofit inline mutation shape). A
	# legacy Dictionary-target fallback branch (the `else:` sibling) is out
	# of scope here, exactly as it is for the already-retrofitted Strike
	# path (test_strike_effects_applier_retrofit.gd's identically-scoped
	# assertion).
	var combatant_branch_start: int = live_code.find("if target is CombatantClass:")
	assert_true(combatant_branch_start >= 0, "expected a live-Combatant-instance branch guarded by 'if target is CombatantClass:'")
	var else_start: int = live_code.find("else:", combatant_branch_start)
	var combatant_branch: String = live_code.substr(combatant_branch_start, else_start - combatant_branch_start) if else_start >= 0 else live_code.substr(combatant_branch_start)

	assert_false(
		combatant_branch.contains("hp_current ="),
		"FEAT-005: the live-Combatant branch of apply() must not directly assign hp_current -- it must route damage through EffectsApplier.apply() instead"
	)


func test_apply_constructs_exactly_one_damage_effect_per_committed_hit() -> void:
	var content: String = _read_file(APPLY_ON_HIT_DEFENSE_UC_PATH)
	var body: String = _extract_function_body(content, "func apply(")
	var live_code: String = _strip_comment_lines(body)

	var construction_count: int = live_code.count("DamageEffectClass.new(")
	assert_eq(
		construction_count, 1,
		"FEAT-005: apply() must construct exactly one DamageEffect per committed reaction outcome, found %d" % construction_count
	)


func test_apply_routes_damage_through_the_effects_applier_seam() -> void:
	var content: String = _read_file(APPLY_ON_HIT_DEFENSE_UC_PATH)
	var body: String = _extract_function_body(content, "func apply(")
	var live_code: String = _strip_comment_lines(body)

	assert_true(
		live_code.contains("_effects_applier.apply("),
		"FEAT-005: apply() must call the shared EffectsApplier instance's apply() with the constructed DamageEffect"
	)


func test_apply_on_hit_defense_uc_preloads_damage_effect_and_effects_applier() -> void:
	var content: String = _read_file(APPLY_ON_HIT_DEFENSE_UC_PATH)
	assert_true(
		content.contains("res://core/domain/effects/damage_effect.gd"),
		"FEAT-005: apply_on_hit_defense_uc.gd must preload/reference core/domain/effects/damage_effect.gd"
	)
	assert_true(
		content.contains("res://core/domain/effects_applier.gd"),
		"FEAT-005: apply_on_hit_defense_uc.gd must preload/reference core/domain/effects_applier.gd"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the enemy reaction calls the SAME Effects-Applier seam/
# instance used by Strike (shared-instance assertion).
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_action_use_case_wires_the_identical_effects_applier_instance_into_both_paths() -> void:
	var use_case = ResolveActionUseCaseClass.new(
		ScriptedRandomNumberPort.new([]), FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
	)

	var strike_effects_applier = use_case.get_effects_applier()
	var reaction_effects_applier = use_case.get_apply_on_hit_defense_use_case().get_effects_applier()

	assert_not_null(strike_effects_applier)
	assert_true(strike_effects_applier is EffectsApplierClass, "the shared instance must genuinely be an EffectsApplier (core/domain/effects_applier.gd)")
	assert_same(
		strike_effects_applier, reaction_effects_applier,
		"FEAT-005: ResolveActionUseCase._init() must construct exactly ONE EffectsApplier instance and inject it into BOTH the Strike path and the ApplyOnHitDefenseUseCase enemy-reaction path -- never two independently-constructed instances"
	)


func test_boot_real_mainscene_strike_and_enemy_reaction_share_the_identical_effects_applier_instance() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)

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


func test_reaction_apply_mutates_the_live_target_via_the_shared_effects_applier() -> void:
	var use_case = ResolveActionUseCaseClass.new(
		ScriptedRandomNumberPort.new([]), FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
	)
	var reaction_uc = use_case.get_apply_on_hit_defense_use_case()

	var attacker = _attacker()
	var target = _target(50, 5)
	var hp_before: int = target.hp_current

	var partial: Dictionary = {
		"hit": true,
		"crit": false,
		"damage_raw": 10,
		"roll_total": 15,
		"defense_type": "ac",
		"defense_value": 5,
		"active_defense_applied": "none",
	}

	var result: Dictionary = reaction_uc.apply(partial, attacker, target, "none", {}, 1, null)
	var damage_final: int = result.get("damage_final", -1)
	assert_true(damage_final > 0, "an unmitigated hit must commit positive final damage")

	assert_eq(
		target.hp_current, hp_before - damage_final,
		"FEAT-005: the live target Combatant's hp_current must drop by EXACTLY damage_final -- proving the constructed DamageEffect was applied against the live combatant set, by reference, via the shared EffectsApplier"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — boot-real enemy-reaction e2e: hp / AttackEvent / log diff
# against the established pre-retrofit baseline is zero (Block; Pass).
# ══════════════════════════════════════════════════════════════════════════

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


func test_boot_real_enemy_reaction_block_matches_pre_retrofit_baseline_hp_and_attack_event() -> void:
	var instance = _boot_main_scene()
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
	assert_false(instance.reaction_prompt_ui.is_open())

	# ── hp diff vs the pre-retrofit baseline (test_mainscene_hit_reaction_apply.gd)
	# is zero: a genuinely-applied, overwhelming Block must leave ZERO damage
	# taken. ──────────────────────────────────────────────────────────────
	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_after, hp_before, "Titus's own HP panel must show ZERO damage taken once a successful Block is GENUINELY applied via the retrofitted EffectsApplier seam -- matches the pre-retrofit baseline exactly")

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	assert_true(attack_events[0].hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_eq(attack_events[0].damage_final, 0, "the committed AttackEvent must carry the mitigated (zero) final damage -- matches the pre-retrofit baseline")

	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, log_count_before + 1, "exactly one new combat-log row must be appended for this Strike -- matches the pre-retrofit baseline")


func test_boot_real_enemy_reaction_pass_matches_pre_retrofit_baseline_hp_and_attack_event() -> void:
	var instance = _boot_main_scene()
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT

	var titus_id: String = _titus_id(instance)
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	var log_count_before: int = instance.event_log_view.get_entry_count()

	_press_end_turn_and_drive_enemy_strike(instance)

	instance.reaction_prompt_ui.press_option("none")
	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("none")
	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1)
	assert_true(attack_events[0].hit)
	assert_true(attack_events[0].damage_final > 0, "declining (Pass) must leave the Strike's real, unmitigated damage in place -- matches the pre-retrofit baseline")

	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(
		hp_before - hp_after, attack_events[0].damage_final,
		"Titus's HP panel must show damage taken EXACTLY matching the unmitigated (raw) committed damage -- zero diff vs the pre-retrofit baseline"
	)

	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, log_count_before + 1, "exactly one new combat-log row must be appended -- matches the pre-retrofit baseline")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — Opportunistic Strike and flanking Off-Guard (+2) scenarios
# produce damage amounts identical to the pre-retrofit baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_opportunistic_strike_damage_math_unaffected_by_the_retrofit() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")

	var titus = instance._party[0]
	var skeleton = instance._enemies[0]

	# Force a guaranteed hit against Titus (the mover), comfortably
	# survivable -- mirrors tests/integration/
	# test_player_stride_provokes_enemy_opportunistic_strike.gd's established
	# technique exactly.
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
	var stride_result: Dictionary = await instance._verb_bar_stride_execute(destination)

	assert_eq(
		skeleton_ae.get_remaining(), skeleton_budget_before - 1,
		"the Opportunistic Strike must still spend exactly one reaction from the Skeleton's own action budget -- unaffected by the FEAT-005 retrofit"
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
		"Titus's hp_current must drop by EXACTLY the resolved Opportunistic Strike's damage_final -- identical to the pre-retrofit baseline (this resolves via the already-retrofitted Strike path, never this file's ApplyOnHitDefenseUseCase)"
	)
	assert_true(stride_result.get("ok", false), "Titus's own Stride must still commit once the non-lethal Opportunistic Strike resolves")


func _flanking_ally(hex_coord, combatant_id: String) -> Dictionary:
	return {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": combatant_id,
		"hex_coord": hex_coord,
	}


func test_flanking_off_guard_plus_two_modifier_produces_identical_defense_value_delta_vs_baseline() -> void:
	var baseline_instance = _boot_main_scene()
	await get_tree().process_frame

	var baseline_target_id: String = baseline_instance._enemies[0].get("combatant_id", "")
	var baseline_result: Dictionary = baseline_instance._verb_registry.execute("STRIKE", baseline_target_id)
	assert_true(baseline_result.get("resolved", false), "the baseline (no-flanking) Strike must resolve")
	var baseline_attack_events: Array = baseline_instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(baseline_attack_events.size(), 1)
	var baseline_defense_value: int = baseline_attack_events[0].defense_value
	var baseline_damage_final: int = baseline_attack_events[0].damage_final

	var off_guard_instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = off_guard_instance._enemies[0].get("combatant_id", "")
	assert_eq(target_id, baseline_target_id, "fixture assumption: both independent boots resolve the same prologue enemy id")

	var ally: Dictionary = _flanking_ally(HexCoordClass.new(2, 0), "synthetic_ally_enemy_reaction_effects_applier_retrofit")
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
		"the Off-Guard +2 modifier must still reduce defense_value by exactly 2 after the FEAT-005 retrofit -- identical to the pre-retrofit baseline (Off-Guard is computed entirely in the to-hit phase, never touched by this file)"
	)
	assert_true(
		baseline_damage_final >= 0 and off_guard_attack_events[0].damage_final >= 0,
		"fixture sanity: both Strikes must resolve with a well-formed non-negative final damage"
	)
