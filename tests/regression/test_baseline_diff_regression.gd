extends GutTest
## tests/regression/test_baseline_diff_regression.gd — FEAT-255
## (US-004, US-005, US-006, US-012, US-013; resolves PR-004).
##
## Addresses the unresolved deployment-gate finding (RISK-006) that the
## Effects Applier retrofit's "byte-identical, no-behavior-change" regression
## guarantee for player Strike (US-004), enemy on-hit reaction (US-005), the
## generalized event-emission seam (US-006), END_TURN preservation (US-012)
## and Strike preservation (US-013) was described only as a MANUAL diff step
## — never recorded as a durable, automated artifact a future change could be
## checked against. This suite closes that gap: it pins three known-good,
## pinned-seed (seed=42, this project's established PROLOGUE_SEED) baseline
## snapshots as checked-in fixture files under tests/regression/fixtures/,
## re-drives the IDENTICAL boot-real interaction each snapshot was captured
## from, and asserts every recorded field diffs to ZERO — hp outcome,
## AttackEvent payload fields, and the rendered combat-log line.
##
## Each fixture was captured driving the REAL res://MainScene.tscn
## composition root — no scripted/stubbed RNG anywhere — mirroring the exact
## boot-real conventions already established by
## tests/integration/test_strike_effects_applier_retrofit.gd (Section D),
## tests/integration/test_enemy_reaction_effects_applier_retrofit.gd, and
## tests/regression/test_end_turn_direct_execute.gd. Determinism (same seed,
## same interaction sequence -> same dice draws, since core/rules/rng.gd's
## seeded adapter is the sole source of randomness for a fixed encounter) is
## what makes a byte-identical pinned-seed diff meaningful at all — verified
## empirically by generating each fixture from two independent, fresh
## MainScene boots and confirming identical output before pinning it here.
##
## Wired as a gating stage in scripts/test_command.sh: a failure in ANY test
## below aborts the whole pipeline (non-zero exit, `set -euo pipefail`) —
## exactly like every other stage — so a future change that silently
## reintroduces drift into the Strike/enemy-reaction/END_TURN paths is
## caught automatically, not discovered later by a human re-running a manual
## diff.
##
## test_criteria covered:
##   1. player Strike hp outcome, AttackEvent fields, and combat-log line
##      match baseline_strike_seed42.json byte-for-byte —
##      test_player_strike_matches_pinned_seed42_baseline_byte_for_byte
##   2. enemy on-hit reaction hp outcome, AttackEvent fields, and combat-log
##      line match baseline_enemy_reaction_seed42.json byte-for-byte —
##      test_enemy_reaction_matches_pinned_seed42_baseline_byte_for_byte
##   3. END_TURN sequence at pinned seed matches baseline_end_turn_seed42.json
##      with zero deltas —
##      test_end_turn_sequence_matches_pinned_seed42_baseline_with_zero_deltas
##   4. scripts/test_command.sh exits non-zero if any baseline diff test
##      fails, confirming the stage actually gates the pipeline — this is a
##      process-level property of the wired GUT `-gexit` stage (mirrors every
##      other stage's exit-code contract) and is proven directly by
##      tests/unit/test_ci_hardening_feat039.py-style shell-level assertions;
##      here it is additionally proven structurally by
##      test_scripts_test_command_wires_the_baseline_diff_regression_stage()
##      below, which asserts the new stage is genuinely present and precedes
##      the terminal "all stages passed" echo (i.e. its failure is not
##      swallowed).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_strike_effects_applier_retrofit.gd's/
## tests/integration/test_enemy_reaction_effects_applier_retrofit.gd's
## identically-named/valued constant): Titus acts first and the sole enemy
## (Skeleton) starts adjacent to him.
const PROLOGUE_SEED: int = 42

const FIXTURES_DIR: String = "res://tests/regression/fixtures"


# ══════════════════════════════════════════════════════════════════════════
# Shared helpers (mirror this project's established boot-real conventions —
# see tests/integration/test_strike_effects_applier_retrofit.gd/
# tests/integration/test_enemy_reaction_effects_applier_retrofit.gd).
# ══════════════════════════════════════════════════════════════════════════

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


func _titus(instance):
	return instance._party[0]


func _attack_events(instance) -> Array:
	return instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)


## _load_fixture(filename) -> Dictionary — reads and parses one checked-in
## JSON baseline fixture from tests/regression/fixtures/. JSON has no
## int/float distinction (every JSON number parses as Godot's TYPE_FLOAT),
## but every value this project's own AttackEvent/history/round-event fields
## carry is integer-valued -- GDScript's native Dictionary `==` operator
## (used by both assert_eq()'s deep comparator below AND this suite's own
## key-by-key loops) compares nested values by STRICT type, so an
## unconverted 20.0 (float, from JSON) would never equal a live 20 (int,
## from a real AttackEvent.to_dict()) even though `20 == 20.0` alone is
## true. _deep_int_cast() normalizes every whole-valued float recursively
## right after parsing, so every downstream comparison below is comparing
## like-for-like Variant types, not just like-for-like values.
func _load_fixture(filename: String) -> Dictionary:
	var path: String = "%s/%s" % [FIXTURES_DIR, filename]
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % path)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "%s must parse as a JSON object" % path)
	if not (parsed is Dictionary):
		return {}
	return _deep_int_cast(parsed)


## _deep_int_cast(value) -> Variant — recursively walks a Dictionary/Array,
## converting every whole-valued TYPE_FLOAT leaf to TYPE_INT (see
## _load_fixture()'s doc above for why this is required). Every other type
## (String, bool, already-int, null) passes through unchanged.
func _deep_int_cast(value):
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value.keys():
			out[key] = _deep_int_cast(value[key])
		return out
	if value is Array:
		var out_arr: Array = []
		for item in value:
			out_arr.append(_deep_int_cast(item))
		return out_arr
	if typeof(value) == TYPE_FLOAT and float(value) == float(int(value)):
		return int(value)
	return value


## _find_attack_row_text(instance) -> String — the rich-rendered combat-log
## row text for the (assumed single) resolved Strike in this scenario. Scans
## in append order and returns the LAST row whose text contains " attacks "
## (the rich/plain attack-row marker both render_attack_entry() and
## on_attack_event() always include) rather than assuming it is the final
## appended entry -- a lethal Strike also appends a trailing
## "was defeated by" consequence row immediately after it (see
## presentation/event_log_view.gd's overwrite_entry_as_rich() doc: the
## attack row keeps its ORIGINAL chronological slot; a defeat consequence,
## when any, is appended afterward).
func _find_attack_row_text(instance) -> String:
	var found: String = ""
	for i in range(instance.event_log_view.get_entry_count()):
		var text: String = instance.event_log_view.get_row_text(i)
		if text.find(" attacks ") != -1:
			found = text
	return found


func _press_end_turn_and_resolve_any_reaction_prompts(instance) -> void:
	instance.verb_bar_view.press("END_TURN")

	var guard: int = 0
	while instance.reaction_prompt_ui.is_open() and guard < 10:
		var options: Array = instance.reaction_prompt_ui.get_displayed_options()
		if "none" in options:
			instance.reaction_prompt_ui.press_option("none")
		else:
			instance.reaction_prompt_ui.press_option(options[0])
		guard += 1


func _classify_event(e) -> String:
	if e is RoundEventsClass.AttackBroadcast:
		return "AttackBroadcast"
	if e is RoundEventsClass.CombatantDefeatedEvent:
		return "CombatantDefeatedEvent"
	if e is RoundEventsClass.EncounterResultEvent:
		return "EncounterResultEvent"
	if e is RoundEventsClass.TurnAdvancedEvent:
		return "TurnAdvancedEvent"
	if e is RoundEventsClass.ReactionWindowOpenedEvent:
		return "ReactionWindowOpenedEvent"
	if e is RoundEventsClass.ReactionResolvedBroadcast:
		return "ReactionResolvedBroadcast"
	return "Unknown"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — player Strike hp outcome, AttackEvent fields, and combat-log
# line match baseline_strike_seed42.json byte-for-byte.
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_matches_pinned_seed42_baseline_byte_for_byte() -> void:
	var baseline: Dictionary = _load_fixture("baseline_strike_seed42.json")

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = skeleton.combatant_id
	var hp_before: int = skeleton.hp_current
	assert_eq(hp_before, int(baseline["hp_before"]), "PINNED: Skeleton hp_before must match the seed=42 baseline")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(skeleton_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")
	var target_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	var attack_event = attack_events[0]
	var hp_after: int = skeleton.hp_current

	# ── hp outcome — zero diff ────────────────────────────────────────────
	assert_eq(hp_after, int(baseline["hp_after"]), "PINNED: Skeleton hp_after must match the seed=42 baseline byte-for-byte -- any diff signals drift in the Effects Applier retrofit's Strike path")

	# ── AttackEvent fields — zero diff ─────────────────────────────────────
	var expected_event: Dictionary = baseline["attack_event"]
	var actual_event: Dictionary = attack_event.to_dict()
	for key in expected_event.keys():
		assert_eq(
			actual_event.get(key), expected_event[key],
			"PINNED: AttackEvent field '%s' must match the seed=42 baseline byte-for-byte" % key
		)

	# ── round-history entry — zero diff ────────────────────────────────────
	var history: Array = instance.round_history_port.get_history()
	assert_eq(history.size(), 1, "PINNED: exactly one history entry appended")
	var entry: Dictionary = history[0]
	assert_eq(
		entry.get("damage_final", -1), int(baseline["history_entry_damage_final"]),
		"PINNED: history entry damage_final must match the seed=42 baseline"
	)
	assert_eq(
		entry.get("target", {}).get("hp_current", -1), int(baseline["history_entry_target_hp_current"]),
		"PINNED: history entry target hp_current must match the seed=42 baseline"
	)

	# ── combat-log line — zero diff ────────────────────────────────────────
	assert_eq(
		_find_attack_row_text(instance), String(baseline["combat_log_line"]),
		"PINNED: the rendered combat-log row for this Strike must match the seed=42 baseline byte-for-byte"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — enemy on-hit reaction hp outcome, AttackEvent fields, and
# combat-log line match baseline_enemy_reaction_seed42.json byte-for-byte.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_reaction_matches_pinned_seed42_baseline_byte_for_byte() -> void:
	var baseline: Dictionary = _load_fixture("baseline_enemy_reaction_seed42.json")

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var titus_id: String = titus.combatant_id
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(hp_before, int(baseline["hp_before"]), "PINNED: Titus hp_before must match the seed=42 baseline")

	var log_count_before: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_before, int(baseline["log_count_before"]), "PINNED: log_count_before must match the seed=42 baseline")

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	_press_end_turn_and_resolve_any_reaction_prompts(instance)

	var attack_events: Array = _attack_events(instance)
	assert_eq(attack_events.size(), int(baseline["attack_event_count"]), "PINNED: attack_event_count must match the seed=42 baseline")
	var attack_event = attack_events[0]
	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)

	# ── hp outcome — zero diff ────────────────────────────────────────────
	assert_eq(hp_after, int(baseline["hp_after"]), "PINNED: Titus hp_after must match the seed=42 baseline byte-for-byte -- any diff signals drift in the Effects Applier retrofit's enemy-reaction path")

	# ── AttackEvent fields — zero diff ─────────────────────────────────────
	var expected_event: Dictionary = baseline["attack_event"]
	var actual_event: Dictionary = attack_event.to_dict()
	for key in expected_event.keys():
		assert_eq(
			actual_event.get(key), expected_event[key],
			"PINNED: AttackEvent field '%s' must match the seed=42 baseline byte-for-byte" % key
		)

	# ── combat-log line — zero diff ────────────────────────────────────────
	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, int(baseline["log_count_after"]), "PINNED: log_count_after must match the seed=42 baseline")
	assert_eq(
		_find_attack_row_text(instance), String(baseline["combat_log_line"]),
		"PINNED: the rendered combat-log row for this enemy reaction must match the seed=42 baseline byte-for-byte"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — END_TURN sequence at pinned seed matches
# baseline_end_turn_seed42.json with zero deltas.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_sequence_matches_pinned_seed42_baseline_with_zero_deltas() -> void:
	var baseline: Dictionary = _load_fixture("baseline_end_turn_seed42.json")

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor_before = instance.round_session.current_actor()
	assert_eq(actor_before.name, String(baseline["actor_before_name"]), "PINNED: actor_before_name must match the seed=42 baseline")

	var log_count_before: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_before, int(baseline["log_count_before"]), "PINNED: log_count_before must match the seed=42 baseline")

	var end_turn_result: Dictionary = instance.verb_bar_view.press("END_TURN")

	var guard: int = 0
	while instance.reaction_prompt_ui.is_open() and guard < 10:
		var options: Array = instance.reaction_prompt_ui.get_displayed_options()
		if "none" in options:
			instance.reaction_prompt_ui.press_option("none")
		else:
			instance.reaction_prompt_ui.press_option(options[0])
		guard += 1

	# ── END_TURN's own execute() result — zero diff (US-012 preservation) ──
	var expected_result: Dictionary = baseline["end_turn_result"]
	for key in expected_result.keys():
		assert_eq(
			end_turn_result.get(key), expected_result[key],
			"PINNED: END_TURN's execute() result field '%s' must match the seed=42 baseline" % key
		)

	# ── the full ordered sequence of round events — zero deltas ────────────
	var actual_sequence: Array = []
	for e in instance.event_sink.log:
		actual_sequence.append(_classify_event(e))
	var expected_sequence: Array = baseline["event_class_sequence"]
	assert_eq(actual_sequence.size(), expected_sequence.size(), "PINNED: the number of round events emitted by this END_TURN press must match the seed=42 baseline")
	for i in range(min(actual_sequence.size(), expected_sequence.size())):
		assert_eq(
			actual_sequence[i], expected_sequence[i],
			"PINNED: round event #%d's class must match the seed=42 baseline sequence (position-for-position, zero deltas)" % i
		)
	assert_eq(instance.event_sink.log.size(), int(baseline["event_count"]), "PINNED: event_count must match the seed=42 baseline")

	# ── active-actor identity settles back correctly, and the combat log
	# grows by exactly the baseline's delta — zero diff ────────────────────
	var actor_after = instance.round_session.current_actor()
	assert_eq(actor_after.name, String(baseline["actor_after_name"]), "PINNED: actor_after_name must match the seed=42 baseline")

	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, int(baseline["log_count_after"]), "PINNED: log_count_after must match the seed=42 baseline")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — scripts/test_command.sh exits non-zero if any baseline diff
# test fails, confirming the stage actually gates the pipeline: a structural
# proof the new stage is genuinely wired into the gate (not merely present
# as an unreferenced file) and precedes the terminal success echo, so a
# failure in it is never swallowed.
# ══════════════════════════════════════════════════════════════════════════

func test_scripts_test_command_wires_the_baseline_diff_regression_stage() -> void:
	var f := FileAccess.open("res://scripts/test_command.sh", FileAccess.READ)
	assert_not_null(f, "res://scripts/test_command.sh must be readable")
	if f == null:
		return
	var content: String = f.get_as_text()
	f.close()

	assert_true(
		content.contains("test_baseline_diff_regression.gd"),
		"FEAT-255: scripts/test_command.sh must invoke tests/regression/test_baseline_diff_regression.gd as its own gating stage"
	)

	var stage_idx: int = content.find("test_baseline_diff_regression.gd")
	var success_idx: int = content.find("all stages passed")
	assert_true(stage_idx >= 0 and success_idx >= 0 and stage_idx < success_idx, "FEAT-255: the baseline-diff regression stage must run BEFORE the terminal success echo -- set -euo pipefail then guarantees its failure aborts the whole gate with a non-zero exit code")

	assert_true(content.contains("set -euo pipefail") or content.contains("set -eu"), "scripts/test_command.sh must still fail fast (non-zero exit) on any stage failure, including the new baseline-diff regression stage")
