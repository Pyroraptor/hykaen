extends GutTest
## tests/integration/test_strike_effects_applier_retrofit.gd — FEAT-004
## (US-004, design notes' architecture/api_contracts §2).
##
## Steel-thread business-logic-to-live-state slice: proves
## core/application/resolve_action_use_case.gd's `_finalize_strike_result()`
## no longer inline-mutates a live Combatant's hp directly for a resolved
## Strike, and instead constructs exactly one core/domain/effects/
## damage_effect.gd DamageEffect and routes it through the single
## core/domain/effects_applier.gd EffectsApplier seam this use case shares
## with core/application/apply_on_hit_defense_uc.gd's ApplyOnHitDefenseUseCase
## (see resolve_action_use_case.gd's own `_effects_applier` doc) — while
## leaving the emitted AttackEvent (core/rules/round_events.gd's
## RoundEvents.AttackBroadcast) byte-identical in shape/fields to the
## pre-retrofit baseline this suite pins.
##
## Sections (test_criteria):
##   A. Static source check: _finalize_strike_result() contains no inline
##      `.take_damage(`/unconditional `hp_current -/=` mutation for the live
##      Combatant path, and DOES construct a DamageEffect + call the
##      EffectsApplier seam exactly once.
##   B. Behavioral check: resolving a damaging Strike against a real
##      Combatant target mutates hp_current by exactly damage_final, via the
##      SAME EffectsApplier instance exposed by
##      ResolveActionUseCase.get_effects_applier() — proving the constructed
##      DamageEffect was actually applied against the live combatant set,
##      not a copy.
##   C. AttackEvent shape/fields pin: the emitted RoundEvents.AttackBroadcast
##      for a scripted, deterministic Strike carries the exact same
##      round/attacker_name/target_name/roll/defense_type/defense_value/
##      hit/crit/damage_final/actor_updated_action_budget fields the
##      pre-retrofit baseline produced (mirrors
##      tests/characterization/test_strike_characterization.gd's pinning
##      convention).
##   D. Boot-real, same-seed player-Strike scenario (mirrors
##      tests/integration/test_reserve_gate_boot_real.gd's established
##      "_boot_main_scene()" convention): drives ONE real player Strike
##      through the REAL res://MainScene.tscn composition root and asserts
##      zero diff between (a) the live target Combatant's hp drop and the
##      recorded AttackEvent's damage_final, and (b) the RoundHistoryPort's
##      appended combat-log entry's damage_final and the AttackEvent's own
##      damage_final — proving no drift was introduced by routing Strike
##      damage through the EffectsApplier seam instead of an inline mutator.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")
const EffectsApplierClass       = preload("res://core/domain/effects_applier.gd")
const DamageEffectClass         = preload("res://core/domain/effects/damage_effect.gd")

const RESOLVE_ACTION_USE_CASE_PATH: String = "res://core/application/resolve_action_use_case.gd"


# ── Local test doubles (mirrors tests/characterization/
#    test_strike_characterization.gd's established conventions — each suite
#    in this project owns its own doubles) ──────────────────────────────────

class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var calls: Array = []

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		calls.append(dice_spec)
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


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port    = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


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


## _extract_function_body(content, func_signature_prefix) -> String — pulls
## the text of one function (from its `func <name>(` line up to, but not
## including, the next top-level `\nfunc `) out of a whole-file source
## string, so static assertions below can scope themselves to
## `_finalize_strike_result()` alone rather than the whole file (which still
## legitimately mentions "take_damage"/"hp_current" in doc-comments and in
## OTHER methods, e.g. `_is_target_invalid()`).
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
## scanning for a call pattern, mirroring
## ci/check_no_duplicate_seams.sh's `grep -vE ':[[:space:]]*##'` convention —
## a comment merely NAMING a pattern (e.g. this file's own doc above) must
## never be mistaken for a live call site.
func _strip_comment_lines(body: String) -> String:
	var kept: Array = []
	for line in body.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ══════════════════════════════════════════════════════════════════════════
# Section A — static source check (test_criteria #1/#2): _finalize_strike_
# result() contains no inline take_damage/hp_current mutation code for the
# live Combatant path, and constructs exactly one DamageEffect routed
# through the single EffectsApplier seam.
# ══════════════════════════════════════════════════════════════════════════

func test_finalize_strike_result_contains_no_inline_take_damage_call() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")
	var live_code: String = _strip_comment_lines(body)

	assert_false(
		live_code.contains(".take_damage("),
		"FEAT-004: _finalize_strike_result() must no longer call .take_damage() inline -- damage must be routed through a constructed DamageEffect + the EffectsApplier seam instead"
	)


func test_finalize_strike_result_does_not_unconditionally_mutate_hp_current_for_combatant_targets() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")
	var live_code: String = _strip_comment_lines(body)

	# The live Combatant-instance branch (guarded by `if target is
	# CombatantClass:`) must dispatch through DamageEffect + EffectsApplier
	# only -- it must never itself write `target.hp_current =`/`target["hp_current"] =`
	# (an inline mutation the pre-retrofit code performed directly).
	var combatant_branch_start: int = live_code.find("if target is CombatantClass:")
	assert_true(combatant_branch_start >= 0, "expected a live-Combatant-instance branch guarded by 'if target is CombatantClass:'")
	var else_start: int = live_code.find("else:", combatant_branch_start)
	var combatant_branch: String = live_code.substr(combatant_branch_start, else_start - combatant_branch_start) if else_start >= 0 else live_code.substr(combatant_branch_start)

	assert_false(
		combatant_branch.contains("hp_current ="),
		"FEAT-004: the live-Combatant branch of _finalize_strike_result() must not directly assign hp_current -- it must route damage through EffectsApplier.apply() instead"
	)


func test_finalize_strike_result_constructs_exactly_one_damage_effect() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")
	var live_code: String = _strip_comment_lines(body)

	var construction_count: int = live_code.count("DamageEffectClass.new(")
	assert_eq(
		construction_count, 1,
		"FEAT-004: _finalize_strike_result() must construct exactly one DamageEffect per resolved Strike, found %d" % construction_count
	)


func test_finalize_strike_result_routes_damage_through_the_effects_applier_seam() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")
	var live_code: String = _strip_comment_lines(body)

	assert_true(
		live_code.contains("_effects_applier.apply("),
		"FEAT-004: _finalize_strike_result() must call the shared EffectsApplier instance's apply() with the constructed DamageEffect"
	)


func test_resolve_action_use_case_preloads_damage_effect_and_effects_applier() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	assert_true(
		content.contains("res://core/domain/effects/damage_effect.gd"),
		"FEAT-004: resolve_action_use_case.gd must preload/reference core/domain/effects/damage_effect.gd"
	)
	assert_true(
		content.contains("res://core/domain/effects_applier.gd"),
		"FEAT-004: resolve_action_use_case.gd must preload/reference core/domain/effects_applier.gd"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section B — behavioral check (test_criteria #2): a resolved, damaging
# Strike against a real live Combatant target mutates hp_current by exactly
# damage_final, dispatched through the SAME EffectsApplier instance
# get_effects_applier() exposes.
# ══════════════════════════════════════════════════════════════════════════

func test_resolved_strike_applies_damage_via_the_effects_applier_seam() -> void:
	var rig: Dictionary = _make_use_case([10, 4])  # attack roll=10, damage roll=4
	var use_case = rig["use_case"]

	assert_true(
		use_case.get_effects_applier() is EffectsApplierClass,
		"ResolveActionUseCase must expose the shared EffectsApplier instance _finalize_strike_result() dispatches through"
	)

	var target = _target(50, 5)
	var hp_before: int = target.hp_current

	var result: Dictionary = use_case.resolve(_attacker(), _fresh_ae(), target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "the scripted Strike must resolve (roll_total(10) >= ac(5) -> hit)")
	var damage_final: int = result.get("damage_final", -1)
	assert_true(damage_final > 0, "the scripted Strike must deal positive damage")

	assert_eq(
		target.hp_current, hp_before - damage_final,
		"FEAT-004: the live target Combatant's hp_current must drop by EXACTLY damage_final -- proving the constructed DamageEffect was applied against the live combatant set, by reference, via EffectsApplier"
	)


func test_missed_strike_applies_no_damage_effect_and_leaves_hp_unchanged() -> void:
	var rig: Dictionary = _make_use_case([1])  # attack roll=1 -> guaranteed miss
	var use_case = rig["use_case"]

	var target = _target(50, 20)
	var hp_before: int = target.hp_current

	var result: Dictionary = use_case.resolve(_attacker(), _fresh_ae(), target, "Strike", 1, 0)

	assert_true(result.get("ok", false), "a missed Strike still resolves (ok=true)")
	assert_false(result["event"].hit, "PINNED: roll_total(1) < ac(20) -> miss")
	assert_eq(result.get("damage_final", -1), 0, "a miss must deal zero damage")
	assert_eq(target.hp_current, hp_before, "a missed Strike must never construct/apply a DamageEffect -- hp_current must be untouched")


# ══════════════════════════════════════════════════════════════════════════
# Section C — AttackEvent shape/fields pin (test_criteria #3): the emitted
# RoundEvents.AttackBroadcast for a deterministic Strike carries the exact
# same fields the pre-retrofit inline-mutation code produced.
# ══════════════════════════════════════════════════════════════════════════

func test_attack_event_shape_and_fields_are_unchanged_by_the_retrofit() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var use_case = rig["use_case"]
	var target = _target(50, 5)

	var result: Dictionary = use_case.resolve(_attacker(), _fresh_ae(), target, "Strike", 3, 1)
	assert_true(result.get("ok", false), "the scripted Strike must resolve")

	var event = result["event"]
	assert_true(event is RoundEventsClass.AttackBroadcast, "PINNED: the emitted event must be a RoundEvents.AttackBroadcast")
	assert_eq(event.round, 3, "PINNED: round field unchanged")
	assert_eq(event.attacker_name, "Attacker", "PINNED: attacker_name field unchanged")
	assert_eq(event.target_name, "Target", "PINNED: target_name field unchanged")
	assert_eq(event.roll, 10, "PINNED: roll field unchanged")
	assert_eq(event.defense_type, "ac", "PINNED: defense_type field unchanged")
	assert_eq(event.defense_value, 5, "PINNED: defense_value field unchanged")
	assert_true(event.hit, "PINNED: hit field unchanged (roll_total(10) >= ac(5))")
	assert_false(event.crit, "PINNED: crit field unchanged (excess < 10)")
	assert_eq(event.damage_final, 4, "PINNED: damage_final field unchanged (damage roll(4) + strength_mod(0))")
	assert_not_null(event.actor_updated_action_budget, "PINNED: actor_updated_action_budget must still be populated")
	assert_true(event.actor_updated_action_budget.has("remaining"), "PINNED: actor_updated_action_budget must still carry 'remaining'")
	assert_true(event.actor_updated_action_budget.has("spent"), "PINNED: actor_updated_action_budget must still carry 'spent'")

	# Exactly one event emitted for a non-lethal Strike (attack only, no
	# combatant_defeated) -- the retrofit must not change emission count.
	assert_eq(rig["event_sink"].events.size(), 1, "PINNED: exactly one event (attack) emitted for a non-lethal Strike")

	# The round-history entry's shape (test_criteria: "unchanged in shape") --
	# same keys as the pre-retrofit contract, damage_final matching the event.
	var history: Array = rig["history"].get_history()
	assert_eq(history.size(), 1, "PINNED: exactly one history entry appended")
	var entry: Dictionary = history[0]
	for expected_key in ["attacker", "action", "target", "roll", "damage_final", "budget_remaining", "round", "cycle_index", "entry"]:
		assert_true(entry.has(expected_key), "PINNED: history entry must still carry key '%s'" % expected_key)
	assert_eq(entry["damage_final"], event.damage_final, "PINNED: history entry damage_final must match the emitted AttackEvent's damage_final")


# ══════════════════════════════════════════════════════════════════════════
# Section D — boot-real, same-seed player-Strike scenario (test_criteria
# #4): drives ONE real player Strike through the REAL res://MainScene.tscn
# composition root and asserts zero diff between the live hp outcome and the
# recorded combat log.
# ══════════════════════════════════════════════════════════════════════════

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/integration/test_reserve_gate_boot_real.gd's identically-
## named/valued constant): Titus acts first and the sole enemy (Skeleton)
## starts adjacent to him.
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func _sole_attack_event(instance):
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	return attack_events[0]


func test_boot_real_same_seed_player_strike_hp_outcome_matches_attack_event_zero_diff() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = skeleton.combatant_id
	var hp_before: int = skeleton.hp_current

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(skeleton_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	var target_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	var attack_event = _sole_attack_event(instance)
	var hp_after: int = skeleton.hp_current

	# Criterion: zero diff between the live hp outcome and the recorded
	# AttackEvent's damage_final -- proving EffectsApplier mutated the SAME
	# live Combatant instance the container holds, exactly as the
	# pre-retrofit inline take_damage()/hp_current mutator did.
	assert_eq(
		hp_before - hp_after, attack_event.damage_final,
		"boot-real: the Skeleton's live hp_current must drop by EXACTLY the AttackEvent's damage_final -- zero diff"
	)

	# Criterion: zero diff between the appended combat-log entry and the
	# AttackEvent it was derived from.
	var history: Array = instance.round_history_port.get_history()
	assert_true(history.size() > 0, "at least one combat-log entry must be appended for the resolved Strike")
	var last_entry: Dictionary = history[history.size() - 1]
	assert_eq(
		last_entry.get("damage_final", -1), attack_event.damage_final,
		"boot-real: the combat log's damage_final must match the AttackEvent's damage_final -- zero diff"
	)
	assert_eq(
		last_entry.get("target", {}).get("hp_current", -1), hp_after,
		"boot-real: the combat log's snapshotted target hp_current must match the live Skeleton's post-Strike hp_current -- zero diff"
	)
