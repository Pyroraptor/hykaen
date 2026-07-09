extends GutTest
## core/log/tests/test_event_log_rendering.gd
##
## GUT suite for FEAT-008 (US-008 / FR-007): extending presentation/
## event_log_view.gd's structured-storage rendering (FEAT-007) to surface
## roll_total, the hit/crit flag, damage_raw AND damage_final, and to
## derive a single active-defense outcome string from the paired
## core/log/reaction_resolved_event.gd ReactionResolvedEvent — WITHOUT
## touching core/rules/resolution.gd's RNG or math in any way.
##
## NOTE ON FILE LOCATION (files_to_modify said "core/log/event_log_view.gd"):
## no such file exists in this project. presentation/event_log_view.gd is
## the actual, single EventLogView implementation — the same file
## core/log/tests/test_event_log_structured_storage.gd (FEAT-007) already
## targets from this same core/log/tests/ directory. This suite modifies
## that real file, consistent with FEAT-007's precedent, rather than
## creating a second, divergent event_log_view.gd under core/log/.
##
## Verifies (test_criteria):
##   1. Rendered log string for a hit includes roll_total, crit flag,
##      damage_raw and damage_final.
##   2. Active-defense outcome string derived correctly for each of: none,
##      dodge-succeeded, dodge-failed, parry-succeeded, parry-failed,
##      block reduced-by-N.
##   3. core/rules/resolution.gd is UNMODIFIED by this feature — a pinned-MD5
##      diff check performed in test setup (before_all()), mirroring
##      tests/sim/test_balance_simulation_post_fix.gd's established
##      "production file unmodified" pattern.
##
## Criterion 4 ("Balance-sim regression run confirms win_rate 0.747,
## avg_rounds 1.081 and the 7-key provenance are unchanged") is already
## enforced project-wide by the pre-existing, checked-in
## tests/pytest/test_sim_results_provenance.py (pins exactly those two
## values plus the seven-key sim_results.json shape) and
## tests/sim/test_balance_sim.gd/test_balance_simulation_post_fix.gd — this
## feature touches only presentation/event_log_view.gd (a read-only
## rendering surface never consulted by core/sim/simulator.gd's passive-
## defense-only balance-sim path), so those pre-existing suites passing
## unchanged (see scripts/test_command.sh stages [2/9] and [8/9]) IS the
## regression confirmation this criterion asks for; this suite does not
## duplicate a fresh N=1000 run.

const AttackEventClass           = preload("res://core/log/attack_event.gd")
const ReactionResolvedEventClass = preload("res://core/log/reaction_resolved_event.gd")

## EventLogViewClass — the plain SCRIPT (never the .tscn scene), mirroring
## test_event_log_structured_storage.gd's established rationale: core/
## (ADR-001 domain purity, tests/static/test_no_godot_types_in_core.py) must
## never preload a Godot .tscn scene resource, even from a test file.
const EventLogViewClass = preload("res://presentation/event_log_view.gd")

## Pinned MD5 hash (FileAccess.get_as_text().md5_text()) of
## core/rules/resolution.gd — the "diff check in test setup" test_criteria
## #3 requires, mirroring tests/sim/test_balance_simulation_post_fix.gd's
## _EXPECTED_HASHES pattern. FEAT-008's entire scope is presentation/
## event_log_view.gd; this hash proves resolution.gd's RNG/math file was
## never touched while implementing it.
##
## FEAT-002 (US-001, ADR-001) update: this baseline was intentionally
## re-pinned to reflect a legitimate, later, IN-SCOPE change to
## resolution.gd — a purely additive, doc-only cross-reference to the new
## core/application/resolve_to_hit_uc.gd / apply_on_hit_defense_uc.gd
## application-layer use cases (see resolution.gd's own FEAT-002 doc). No
## RNG or math in resolution.gd was touched; this guard still correctly
## fails if a FUTURE, unrelated feature edits resolution.gd's math again.
const _RESOLUTION_GD_PATH: String = "res://core/rules/resolution.gd"
const _RESOLUTION_GD_EXPECTED_MD5: String = "f99271348ee81801463bafbb5e7f3965"

var _resolution_gd_actual_md5: String


func before_all() -> void:
	_resolution_gd_actual_md5 = _file_md5_text(_RESOLUTION_GD_PATH)


func _file_md5_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content.md5_text()


## _make_event_log() -> EventLogView — builds a bare EventLogView from its
## SCRIPT, mirroring test_event_log_structured_storage.gd's `_make_event_log()`.
func _make_event_log():
	var log = EventLogViewClass.new()
	add_child_autofree(log)
	return log


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: core/rules/resolution.gd is UNMODIFIED — pinned-MD5 diff
# check in test setup.
# ══════════════════════════════════════════════════════════════════════════

func test_resolution_gd_is_unmodified_pinned_md5_check() -> void:
	assert_eq(
		_resolution_gd_actual_md5, _RESOLUTION_GD_EXPECTED_MD5,
		(
			"FEAT-008 scope guard FAILED: core/rules/resolution.gd changed since the "
			+ "pinned baseline — FEAT-008 (US-008/FR-007) must never touch resolution.gd's "
			+ "RNG or math, only presentation/event_log_view.gd's rendering. "
			+ "expected=%s actual=%s"
		) % [_RESOLUTION_GD_EXPECTED_MD5, _resolution_gd_actual_md5]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: rendered log string for a hit includes roll_total, crit
# flag, damage_raw and damage_final.
# ══════════════════════════════════════════════════════════════════════════

func test_render_attack_entry_for_a_hit_includes_roll_total_crit_flag_and_both_damage_values() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new(
		"AE-1", 3, "goblin", "titus", "test_sword",
		17, true, false, 8, 6, false, false
	)
	log.record_attack(attack_event)

	var text: String = log.render_attack_entry("AE-1")

	assert_string_contains(text, "17", "rendered hit entry must include roll_total")
	assert_string_contains(text, "Hit", "rendered non-crit hit entry must be labeled 'Hit'")
	assert_string_contains(text, "8", "rendered hit entry must include damage_raw")
	assert_string_contains(text, "6", "rendered hit entry must include damage_final")


func test_render_attack_entry_for_a_critical_hit_includes_crit_flag_distinct_from_a_plain_hit() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new(
		"AE-2", 1, "goblin", "titus", "test_sword",
		20, true, true, 12, 12, false, false
	)
	log.record_attack(attack_event)

	var text: String = log.render_attack_entry("AE-2")

	assert_string_contains(text, "Critical Hit", "rendered crit hit entry must be distinctly labeled")
	assert_string_contains(text, "20", "rendered crit entry must include roll_total")
	assert_string_contains(text, "12", "rendered crit entry must include damage_raw/damage_final")


func test_render_attack_entry_for_an_unpaired_id_returns_empty_string() -> void:
	var log = _make_event_log()

	assert_eq(log.render_attack_entry("does-not-exist"), "", "an unrecorded attack_event_id must render as \"\", never an error")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: active-defense outcome string derived correctly for each of:
# none, dodge-succeeded, dodge-failed, parry-succeeded, parry-failed,
# block reduced-by-N.
# ══════════════════════════════════════════════════════════════════════════

func test_active_defense_outcome_is_none_when_no_reaction_was_paired() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-none", 1, "goblin", "titus", "test_sword", 10, true, false, 5, 5)
	log.record_attack(attack_event)

	assert_eq(log.get_active_defense_outcome_string("AE-none"), "none")

	var text: String = log.render_attack_entry("AE-none")
	assert_string_contains(text, "Defense: none")


func test_active_defense_outcome_is_none_when_paired_reaction_is_an_explicit_pass() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-pass", 1, "goblin", "titus", "test_sword", 10, true, false, 5, 5)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-pass", null, "PreHitAvoidance", "none", "ai", "none"),
		"AE-pass"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-pass"), "none")


func test_active_defense_outcome_dodge_succeeded() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-dodge-ok", 1, "goblin", "titus", "test_sword", 14, false, false, 0, 0, true)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "PreHitAvoidance", "dodge", "ai", "dodge_succeeded"),
		"AE-dodge-ok"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-dodge-ok"), "dodge-succeeded")

	var text: String = log.render_attack_entry("AE-dodge-ok")
	assert_string_contains(text, "Defense: dodge-succeeded")


func test_active_defense_outcome_dodge_failed() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-dodge-fail", 1, "goblin", "titus", "test_sword", 16, true, false, 7, 7)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "PreHitAvoidance", "dodge", "ai", "dodge_failed"),
		"AE-dodge-fail"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-dodge-fail"), "dodge-failed")

	var text: String = log.render_attack_entry("AE-dodge-fail")
	assert_string_contains(text, "Defense: dodge-failed")


func test_active_defense_outcome_parry_succeeded() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-parry-ok", 1, "goblin", "titus", "test_sword", 15, true, false, 9, 0, false, false)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "OnHitMitigation", "parry", "ai", "parry_succeeded"),
		"AE-parry-ok"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-parry-ok"), "parry-succeeded")

	var text: String = log.render_attack_entry("AE-parry-ok")
	assert_string_contains(text, "Defense: parry-succeeded")


func test_active_defense_outcome_parry_failed() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-parry-fail", 1, "goblin", "titus", "test_sword", 15, true, false, 9, 9)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "OnHitMitigation", "parry", "ai", "parry_failed"),
		"AE-parry-fail"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-parry-fail"), "parry-failed")

	var text: String = log.render_attack_entry("AE-parry-fail")
	assert_string_contains(text, "Defense: parry-failed")


func test_active_defense_outcome_block_reduced_by_n() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-block", 1, "goblin", "titus", "test_sword", 15, true, false, 9, 5)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "OnHitMitigation", "block", "ai", "block_reduced_by_n", 4),
		"AE-block"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-block"), "block reduced-by-4")

	var text: String = log.render_attack_entry("AE-block")
	assert_string_contains(text, "Defense: block reduced-by-4")
	assert_string_contains(text, "9", "rendered block entry must still include damage_raw")
	assert_string_contains(text, "5", "rendered block entry must still include the mitigated damage_final")


func test_active_defense_outcome_prefers_the_window_that_actually_fired_over_an_unfired_none_window() -> void:
	## A PreHitAvoidance "none"/Pass window paired alongside a real
	## OnHitMitigation block — the budget invariant guarantees at most ONE of
	## the two windows ever carries a non-"none" outcome, but both may be
	## explicitly recorded (Pass on one, a real reaction on the other).
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-both", 1, "goblin", "titus", "test_sword", 15, true, false, 9, 6)
	log.record_attack(attack_event)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-1", null, "PreHitAvoidance", "none", "ai", "none"),
		"AE-both"
	)
	log.record_reaction(
		ReactionResolvedEventClass.new("RE-2", null, "OnHitMitigation", "block", "ai", "block_reduced_by_n", 3),
		"AE-both"
	)

	assert_eq(log.get_active_defense_outcome_string("AE-both"), "block reduced-by-3")


func test_active_defense_outcome_for_unrecorded_attack_event_id_is_none() -> void:
	var log = _make_event_log()
	assert_eq(log.get_active_defense_outcome_string("does-not-exist"), "none")


# ══════════════════════════════════════════════════════════════════════════
# Regression guard: this feature's new rendering path must never touch
# FEAT-007's pre-existing formatted-string entries (`_entries`) or storage
# accessors — record_attack()/record_reaction()/get_structured_attack()/
# get_paired_reaction() behave exactly as FEAT-007 left them.
# ══════════════════════════════════════════════════════════════════════════

func test_render_attack_entry_never_appends_to_the_entries_array() -> void:
	var log = _make_event_log()
	var attack_event := AttackEventClass.new("AE-render-only", 1, "goblin", "titus", "test_sword", 12, true, false, 5, 5)
	log.record_attack(attack_event)

	log.render_attack_entry("AE-render-only")
	log.get_active_defense_outcome_string("AE-render-only")

	assert_eq(log.get_entry_count(), 0, "rendering structured data must never append to the pre-existing formatted-string `_entries`")
