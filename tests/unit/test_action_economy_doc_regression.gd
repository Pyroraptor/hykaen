extends GutTest
## tests/unit/test_action_economy_doc_regression.gd
##
## GUT regression test for FEAT-101 / CHECKLIST-6 / US-006.
##
## core/rules/action_economy.gd:25 historically read:
##   "## Maximum action budget per turn (ADR-006)."
## which contradicted FR-006/ADR-001 (the 7-action budget is a per-ROUND
## resource shared across all of a combatant's turns and reactions within
## the round — see CR-001 AC-1/AC-2/AC-3 and the corrected doc-comments
## surrounding _budget/_is_spent/start_of_round()/end_of_round()).
##
## This test loads the SOURCE TEXT of core/rules/action_economy.gd (not just
## its runtime behaviour) and asserts:
##   1. The budget-reset doc-comment region (the MAX_BUDGET constant comment)
##      now reads "per round" rather than the stale "per turn".
##   2. The stale phrase "per turn" no longer appears immediately adjacent to
##      any comment line mentioning "budget" or "Spent" (case-insensitive),
##      so the terminology error cannot silently reappear elsewhere in the
##      budget-reset documentation.
##
## This is a comment-only regression guard — it does not exercise any
## ActionEconomy behaviour (see test_action_economy.gd for behavioural
## coverage) and intentionally makes no assertions about runtime state.

const ACTION_ECONOMY_PATH: String = "res://core/rules/action_economy.gd"


func _read_source() -> String:
	var file := FileAccess.open(ACTION_ECONOMY_PATH, FileAccess.READ)
	assert_not_null(
		file,
		"core/rules/action_economy.gd must be readable to verify its doc-comments"
	)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ── Criterion 1: budget-reset doc-comment region contains "per round" ────────

func test_max_budget_doc_comment_says_per_round() -> void:
	var content: String = _read_source()
	if content.is_empty():
		return

	var lines: PackedStringArray = content.split("\n")
	var found_max_budget_comment: bool = false
	for line: String in lines:
		if line.contains("Maximum action budget"):
			found_max_budget_comment = true
			assert_true(
				line.contains("per round"),
				"The MAX_BUDGET doc-comment must read 'per round' (FR-006/ADR-001) — got: '%s'" % line
			)

	assert_true(
		found_max_budget_comment,
		"Expected to find the 'Maximum action budget' doc-comment above MAX_BUDGET in action_economy.gd"
	)


# ── Criterion 2: stale "per turn" phrase must not sit adjacent to ────────────
# budget/Spent-reset comments, so the terminology error cannot silently
# reappear next to the round-economy documentation.

func test_per_turn_phrase_not_adjacent_to_budget_or_spent_comments() -> void:
	var content: String = _read_source()
	if content.is_empty():
		return

	var lines: PackedStringArray = content.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.to_lower().contains("per turn"):
			var window_start: int = max(0, i - 1)
			var window_end: int = min(lines.size() - 1, i + 1)
			var window: String = ""
			for w in range(window_start, window_end + 1):
				window += lines[w] + "\n"
			var window_lower: String = window.to_lower()
			var adjacent_to_budget: bool = window_lower.contains("budget")
			var adjacent_to_spent: bool = window_lower.contains("spent")
			assert_false(
				adjacent_to_budget or adjacent_to_spent,
				(
					"Stale 'per turn' phrasing found adjacent to a budget/Spent-reset "
					+ "comment at line %d: '%s' — the 7-action budget is a per-ROUND "
					+ "resource (FR-006/ADR-001); update the comment to say 'per round'."
				) % [i + 1, line]
			)
