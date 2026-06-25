extends GutTest
## tests/unit/test_spec_gate.gd
##
## GUT test suite for FEAT-021 — CI Spec Approval Gate.
## Enforces that docs/hollow-world-v0-spec.org exists and carries the
## author-approval marker '#+APPROVAL:' before the combat test suite runs.
##
## These tests are GATE TESTS: they fail intentionally until the spec document
## is hand-authored and committed with the approval marker (per ADR-004 / US-001).
## Once the spec is present and signed, both tests pass and merge is unblocked.


# ── Gate Test 1: spec file must exist in the repository ───────────────────────

func test_spec_file_exists() -> void:
	assert_true(
		FileAccess.file_exists("res://docs/hollow-world-v0-spec.org"),
		"docs/hollow-world-v0-spec.org must be authored and committed before combat code can be validated"
	)


# ── Gate Test 2: spec file must carry the author-approval marker ──────────────

func test_spec_has_approval_marker() -> void:
	var file := FileAccess.open("res://docs/hollow-world-v0-spec.org", FileAccess.READ)
	assert_not_null(
		file,
		"docs/hollow-world-v0-spec.org must be readable — author it and commit before merging"
	)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_true(
		content.contains("#+APPROVAL:"),
		"docs/hollow-world-v0-spec.org must contain '#+APPROVAL:' marker — "
		+ "add the approval line after reviewing the spec (per ADR-004)"
	)
