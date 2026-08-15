extends GutTest
## tests/unit/regression/test_frozen_files_checksum.gd — FEAT-405 (US-010,
## US-012; resolves FINDING-004, mitigates RISK-002).
##
## The AI-tier-planner steel thread's NFR-003 frozen-contract constraint
## (core/application/ai_decision_port.gd, core/combat/ai.gd, and the
## PreHitAvoidance/OnHitMitigation reaction-window contract — documented in
## several places as "core/combat/reaction_window.gd", this project's
## established doc-comment alias for the file that actually lives at
## core/application/reaction_window.gd, per that file's own US-010
## _execute_ai_plan() doc — must never be touched by AI-planner work) was,
## before this feature, verified only by a human spot-checking `git log`/
## `git diff` at each story boundary (US-012's manual gate). FINDING-004
## flagged that as a one-time, easy-to-skip check; RISK-002 named the
## consequence directly: a future story could silently drift one of these
## files (or the Strike-dispatch/reaction-window/two-phase-commit region
## US-010 moved verbatim into _execute_ai_plan()) and nothing would catch
## it before it shipped.
##
## This suite turns that manual gate into an automated, CI-enforced one,
## mirroring the EXACT SHA-256-of-file-text convention
## tests/tools/test_protected_files_unchanged.gd already established for a
## structurally identical problem (protected reaction/resolution contract
## files surviving an unrelated refactor) — the only difference is the
## pinned baseline values live in a committed JSON fixture
## (frozen_file_baseline_checksums.json) alongside this test rather than as
## GDScript constants, so a future, deliberate, reviewed change to any
## frozen surface regenerates a plain data file, not source code.
##
## Test criteria covered:
##   1. SHA-256 of core/application/ai_decision_port.gd matches the
##      recorded baseline —
##      test_ai_decision_port_matches_recorded_baseline_checksum
##   2. SHA-256 of core/combat/ai.gd matches the recorded baseline —
##      test_ai_matches_recorded_baseline_checksum
##   3. SHA-256 of core/application/reaction_window.gd (this project's
##      "core/combat/reaction_window.gd" doc-alias) matches the recorded
##      baseline — test_reaction_window_matches_recorded_baseline_checksum
##   4. CombineActionController.execute()'s method signature string matches
##      the recorded baseline signature exactly —
##      test_combine_action_controller_execute_signature_matches_recorded_baseline
##   5. The Strike-dispatch/reaction-window/two-phase-commit region of
##      core/application/round_session.gd (delimited by the documented
##      start_marker/end_marker in the baseline JSON) matches its recorded
##      post-US-010 baseline verbatim, failing loudly with a descriptive
##      assertion message on any divergence —
##      test_round_session_strike_dispatch_region_matches_recorded_post_us010_baseline
##   6. A single summarizing assertion (mirrors
##      test_protected_files_unchanged.gd's own "redundant by design"
##      convention) so a future refactor of this suite that accidentally
##      drops one of the individual tests above still has one assertion
##      enforcing the full frozen-contract set —
##      test_all_frozen_contracts_pass_the_guard_together


const BASELINE_JSON_PATH: String = "res://tests/unit/regression/frozen_file_baseline_checksums.json"


func _load_baseline() -> Dictionary:
	var f := FileAccess.open(BASELINE_JSON_PATH, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % BASELINE_JSON_PATH)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "%s must parse as a JSON object" % BASELINE_JSON_PATH)
	if not (parsed is Dictionary):
		return {}
	return parsed


func _read_file_text(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1-3 — whole-file SHA-256 checksums of the three frozen contract
# files, each checked against its own recorded baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_ai_decision_port_matches_recorded_baseline_checksum() -> void:
	var baseline: Dictionary = _load_baseline()
	var frozen: Dictionary = baseline.get("frozen_files_sha256", {})
	var path: String = "res://core/application/ai_decision_port.gd"
	var expected: String = frozen.get("core/application/ai_decision_port.gd", "")
	assert_true(expected != "", "baseline JSON must record a checksum for core/application/ai_decision_port.gd")

	var actual: String = _read_file_text(path).sha256_text()
	assert_eq(
		actual, expected,
		"REGRESSION (FEAT-405 / NFR-003 / RISK-002): core/application/ai_decision_port.gd is a FROZEN contract file for the AI-tier-planner steel thread — any checksum drift means it was modified and must be reverted or, if the change is genuinely deliberate and reviewed, have frozen_file_baseline_checksums.json regenerated as its own explicit change"
	)


func test_ai_matches_recorded_baseline_checksum() -> void:
	var baseline: Dictionary = _load_baseline()
	var frozen: Dictionary = baseline.get("frozen_files_sha256", {})
	var path: String = "res://core/combat/ai.gd"
	var expected: String = frozen.get("core/combat/ai.gd", "")
	assert_true(expected != "", "baseline JSON must record a checksum for core/combat/ai.gd")

	var actual: String = _read_file_text(path).sha256_text()
	assert_eq(
		actual, expected,
		"REGRESSION (FEAT-405 / NFR-003 / RISK-002): core/combat/ai.gd is a FROZEN contract file (the legacy AIDecisionPort implementation MindlessAI/GruntAI are documented to be clean-room reimplementations of, never wrappers around) — any checksum drift means it was modified and must be reverted or, if genuinely deliberate and reviewed, have frozen_file_baseline_checksums.json regenerated as its own explicit change"
	)


func test_reaction_window_matches_recorded_baseline_checksum() -> void:
	var baseline: Dictionary = _load_baseline()
	var frozen: Dictionary = baseline.get("frozen_files_sha256", {})
	# NOTE: several existing round_session.gd doc comments (e.g. the
	# _execute_ai_plan() US-010 doc) refer to this frozen contract as
	# "core/combat/reaction_window.gd" — this project's established
	# doc-comment alias for the file that actually lives at
	# core/application/reaction_window.gd, the SAME file
	# tests/tools/test_protected_files_unchanged.gd already pins
	# byte-for-byte via its own PINNED_REACTION_WINDOW_SHA256 constant.
	var path: String = "res://core/application/reaction_window.gd"
	var expected: String = frozen.get("core/application/reaction_window.gd", "")
	assert_true(expected != "", "baseline JSON must record a checksum for core/application/reaction_window.gd")

	var actual: String = _read_file_text(path).sha256_text()
	assert_eq(
		actual, expected,
		"REGRESSION (FEAT-405 / NFR-003 / RISK-002): core/application/reaction_window.gd (\"core/combat/reaction_window.gd\" in round_session.gd's own doc comments) is a FROZEN contract file — the PreHitAvoidance/OnHitMitigation reaction-window logic AI-planner work must never touch — any checksum drift means it was modified and must be reverted or, if genuinely deliberate and reviewed, have frozen_file_baseline_checksums.json regenerated as its own explicit change"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — CombineActionController.execute()'s method signature string
# matches the recorded baseline exactly (param names/types/order unchanged).
# ══════════════════════════════════════════════════════════════════════════

## _extract_execute_signature(content) -> String — plain text-line parsing
## (not a real AST, per this feature's own test_criteria wording): scans
## for the first line beginning with "func execute(" and returns it
## trimmed of leading/trailing whitespace, so indentation drift alone never
## trips this guard while any real param/type/order/return-type change
## does.
func _extract_execute_signature(content: String) -> String:
	for line in content.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("func execute("):
			return trimmed
	return ""


func test_combine_action_controller_execute_signature_matches_recorded_baseline() -> void:
	var baseline: Dictionary = _load_baseline()
	var sig_baseline: Dictionary = baseline.get("combine_action_controller_execute_signature", {})
	var path: String = "res://" + String(sig_baseline.get("file", "core/controllers/combine_action_controller.gd"))
	var expected: String = String(sig_baseline.get("signature", ""))
	assert_true(expected != "", "baseline JSON must record CombineActionController.execute()'s signature")

	var content: String = _read_file_text(path)
	var actual: String = _extract_execute_signature(content)
	assert_true(actual != "", "core/controllers/combine_action_controller.gd must still contain a 'func execute(' declaration for this guard to extract")

	assert_eq(
		actual, expected,
		"REGRESSION (FEAT-405 / NFR-003 / RISK-002): CombineActionController.execute()'s method signature must match the recorded baseline exactly (param names/types/order/return type unchanged) — got '%s', expected '%s'" % [actual, expected]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — the Strike-dispatch/reaction-window/two-phase-commit region
# of round_session.gd's _execute_ai_plan() (moved there verbatim by
# US-010/FEAT-399) matches its recorded post-US-010 baseline verbatim.
# ══════════════════════════════════════════════════════════════════════════

func _extract_strike_dispatch_region(content: String, start_marker: String, end_marker: String) -> String:
	var start_idx: int = content.find(start_marker)
	var end_idx: int = content.find(end_marker)
	if start_idx < 0 or end_idx <= start_idx:
		return ""
	return content.substr(start_idx, end_idx - start_idx)


func test_round_session_strike_dispatch_region_matches_recorded_post_us010_baseline() -> void:
	var baseline: Dictionary = _load_baseline()
	var region_baseline: Dictionary = baseline.get("round_session_strike_dispatch_region", {})
	var path: String = "res://" + String(region_baseline.get("file", "core/application/round_session.gd"))
	var start_marker: String = String(region_baseline.get("start_marker", ""))
	var end_marker: String = String(region_baseline.get("end_marker", ""))
	var expected_sha256: String = String(region_baseline.get("sha256", ""))
	assert_true(start_marker != "" and end_marker != "" and expected_sha256 != "", "baseline JSON must record start_marker/end_marker/sha256 for the round_session.gd Strike-dispatch region")

	var content: String = _read_file_text(path)

	assert_true(
		content.count(start_marker) == 1,
		"core/application/round_session.gd must contain exactly ONE occurrence of the documented start_marker %s -- an ambiguous or missing marker means this guard can no longer reliably delimit the Strike-dispatch region" % [JSON.stringify(start_marker)]
	)
	assert_true(
		content.count(end_marker) == 1,
		"core/application/round_session.gd must contain exactly ONE occurrence of the documented end_marker %s -- an ambiguous or missing marker means this guard can no longer reliably delimit the Strike-dispatch region" % [JSON.stringify(end_marker)]
	)

	var region: String = _extract_strike_dispatch_region(content, start_marker, end_marker)
	assert_true(region != "", "the Strike-dispatch region extracted between start_marker and end_marker must be non-empty")

	# Sanity: the extracted region genuinely contains the reaction-window/
	# two-phase-commit machinery US-010 moved verbatim into
	# _execute_ai_plan(), so a future edit that narrows/widens the markers
	# still trips this guard rather than silently hashing an empty or
	# unrelated slice.
	assert_true(region.contains("two_phase_commit_pending"), "extracted Strike-dispatch region must contain the two-phase-commit machinery (two_phase_commit_pending)")
	assert_true(region.contains("reaction_budget_before"), "extracted Strike-dispatch region must contain the reaction-window budget-delta gate (reaction_budget_before)")

	var actual_sha256: String = region.sha256_text()
	assert_eq(
		actual_sha256, expected_sha256,
		"REGRESSION (FEAT-405 / US-010 / NFR-003 / RISK-002): the Strike-dispatch/reaction-window/two-phase-commit region of core/application/round_session.gd's _execute_ai_plan() must have ZERO diff relative to its recorded post-US-010 baseline -- a checksum mismatch means this cut-pasted-verbatim region drifted from the frozen contract it was moved from (advance_ai_turn()'s pre-FEAT-399 body); regenerate frozen_file_baseline_checksums.json only if the change is genuinely deliberate and reviewed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — all frozen contracts together, a single summarizing
# assertion (mirrors test_protected_files_unchanged.gd's own convention).
# ══════════════════════════════════════════════════════════════════════════

func test_all_frozen_contracts_pass_the_guard_together() -> void:
	var baseline: Dictionary = _load_baseline()
	var mismatches: Array = []

	var frozen: Dictionary = baseline.get("frozen_files_sha256", {})
	var whole_file_checks: Array = [
		["res://core/application/ai_decision_port.gd", frozen.get("core/application/ai_decision_port.gd", "")],
		["res://core/combat/ai.gd", frozen.get("core/combat/ai.gd", "")],
		["res://core/application/reaction_window.gd", frozen.get("core/application/reaction_window.gd", "")],
	]
	for pair in whole_file_checks:
		var res_path: String = pair[0]
		var expected: String = pair[1]
		if expected == "" or _read_file_text(res_path).sha256_text() != expected:
			mismatches.append(res_path)

	var sig_baseline: Dictionary = baseline.get("combine_action_controller_execute_signature", {})
	var sig_path: String = "res://" + String(sig_baseline.get("file", "core/controllers/combine_action_controller.gd"))
	var sig_expected: String = String(sig_baseline.get("signature", ""))
	if sig_expected == "" or _extract_execute_signature(_read_file_text(sig_path)) != sig_expected:
		mismatches.append(sig_path)

	var region_baseline: Dictionary = baseline.get("round_session_strike_dispatch_region", {})
	var region_path: String = "res://" + String(region_baseline.get("file", "core/application/round_session.gd"))
	var start_marker: String = String(region_baseline.get("start_marker", ""))
	var end_marker: String = String(region_baseline.get("end_marker", ""))
	var region_expected: String = String(region_baseline.get("sha256", ""))
	var region_content: String = _read_file_text(region_path)
	var region: String = _extract_strike_dispatch_region(region_content, start_marker, end_marker)
	if region_expected == "" or region == "" or region.sha256_text() != region_expected:
		mismatches.append(region_path)

	assert_eq(mismatches, [], "drifted frozen-contract files/regions (FEAT-405 / NFR-003 / RISK-002): %s" % [mismatches])
