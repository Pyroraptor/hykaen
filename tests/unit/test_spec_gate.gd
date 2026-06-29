extends GutTest
## tests/unit/test_spec_gate.gd
##
## GUT test suite for FEAT-021 / FEAT-074 — CI Spec Approval Gate.
## Enforces that docs/hollow-world-v0-spec.org exists, carries the
## author-approval marker '#+APPROVAL:', is not a stub placeholder, and
## contains all required ruleset content keywords.
##
## These are GATE TESTS (per ADR-004 / US-001) that mirror the CI lint steps
## lint-spec-approval-marker, lint-spec-no-placeholder, and
## lint-spec-content-keywords exactly, eliminating the false-confidence gap
## described in DEF-003 where local GUT passed but CI failed (FEAT-074).
##
## Tests fail intentionally until the human author completes the spec.
## Once the spec is present, signed, and contains all required content,
## all four tests pass and merge is unblocked.


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


# ── Gate Test 3: approval must not be a STUB placeholder ─────────────────────
## Mirrors the CI lint-spec-no-placeholder step (FEAT-039 / DEF-001).
## Reads docs/hollow-world-v0-spec.org and asserts the file body does NOT
## contain the string 'STUB placeholder'.  This test FAILS (GUT red) while the
## spec is a stub and PASSES once the human author supplies genuine content.
## Running `godot --headless -- --gut-run-all` exits non-zero locally when the
## spec is a stub, matching CI behaviour and eliminating the false-confidence
## gap described in DEF-003.

func test_spec_approval_not_placeholder() -> void:
	var file := FileAccess.open("res://docs/hollow-world-v0-spec.org", FileAccess.READ)
	assert_not_null(
		file,
		"docs/hollow-world-v0-spec.org must be readable — author it and commit before merging"
	)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(
		content.contains("STUB placeholder"),
		"docs/hollow-world-v0-spec.org must NOT contain 'STUB placeholder' — "
		+ "replace the stub with genuine approved ruleset content (per ADR-004 / DEF-001)"
	)


# ── Gate Test 4: spec must contain all required content keywords ──────────────
## Mirrors the CI lint-spec-content-keywords step (FEAT-057 / DEF-NEW-001)
## exactly.  FAILS when the spec is a stub that lacks the seven attribute
## names, HP formula, four defense keywords, action keywords, armor table
## marker, and talent tree marker.  PASSES once the human author completes
## the spec with all required section prose.
##
## No external network resources are accessed; no Godot Node class is used.

func test_spec_has_content_keywords() -> void:
	var file := FileAccess.open("res://docs/hollow-world-v0-spec.org", FileAccess.READ)
	assert_not_null(
		file,
		"docs/hollow-world-v0-spec.org must be readable — author it and commit before merging"
	)
	if file == null:
		return
	var content: String = file.get_as_text()
	var lower_content: String = content.to_lower()
	file.close()

	# ── Seven attribute names (case-insensitive, mirrors `grep -qi`) ─────────
	for attr: String in ["strength", "constitution", "dexterity", "willpower",
			"intellect", "intuition", "social"]:
		assert_true(
			lower_content.contains(attr),
			"docs/hollow-world-v0-spec.org missing attribute keyword: %s" % attr
		)

	# ── HP formula marker (case-sensitive, mirrors `grep -q 'HP ='`) ─────────
	assert_true(
		content.contains("HP ="),
		"docs/hollow-world-v0-spec.org missing HP formula marker 'HP ='"
	)

	# ── Four defense type keywords (case-sensitive, mirrors `grep -q`) ───────
	for kw: String in ["AC", "Reflex", "Fortitude", "Will"]:
		assert_true(
			content.contains(kw),
			"docs/hollow-world-v0-spec.org missing defense keyword: %s" % kw
		)

	# ── Action economy keywords (case-sensitive, mirrors `grep -q`) ──────────
	for kw: String in ["Strike", "Stride"]:
		assert_true(
			content.contains(kw),
			"docs/hollow-world-v0-spec.org missing action keyword: %s" % kw
		)

	# ── Armor table section marker (mirrors `grep -qE 'ac_base|\| Armor'`) ───
	assert_true(
		content.contains("ac_base") or content.contains("| Armor"),
		"docs/hollow-world-v0-spec.org missing armor table marker ('ac_base' or '| Armor')"
	)

	# ── Talent tree section marker (case-sensitive, mirrors `grep -q 'talent'`) ─
	assert_true(
		content.contains("talent"),
		"docs/hollow-world-v0-spec.org missing talent tree marker 'talent'"
	)
