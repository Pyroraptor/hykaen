extends GutTest
## tests/unit/application/test_ai_planner_port.gd
##
## FEAT-001 (US-001 / FR-001) — GUT suite for the new APPLICATION-layer
## core/application/ai_planner_port.gd port.
##
## Verifies (this feature's test_criteria):
##   1. Base AIPlannerPort.plan_turn() push_errors (documented contract) and
##      returns [] — never null, and calling it never raises/crashes.
##   2. core/application/ai_decision_port.gd (the frozen, pre-existing port,
##      per ADR-001) is untouched by this feature — a diff-free check
##      against git, confirming no working-tree modification to that file.
##   3. AIPlannerPort has no inheritance/coupling to AIDecisionPort: it does
##      not extend/duck-couple to it, and neither script's source
##      references the other's class/file.
##
## Satisfies: FEAT-001, US-001, FR-001.

const AIPlannerPortClass = preload("res://core/application/ai_planner_port.gd")
const AIDecisionPortClass = preload("res://core/application/ai_decision_port.gd")

const AI_PLANNER_PORT_PATH := "res://core/application/ai_planner_port.gd"
const AI_DECISION_PORT_PATH := "res://core/application/ai_decision_port.gd"


# ══════════════════════════════════════════════════════════════════════════
# 1. Base plan_turn() contract: push_error + returns [] (not null, no crash)
# ══════════════════════════════════════════════════════════════════════════

func test_base_plan_turn_returns_empty_array_not_null() -> void:
	var port := AIPlannerPortClass.new()

	# Calling the abstract base directly must not raise/crash — the return
	# value being reachable at all is proof of that.
	var result = port.plan_turn({"name": "dummy"}, {"party": [], "enemies": [], "action_economy": null})

	assert_not_null(result, "plan_turn() must never return null")
	assert_true(typeof(result) == TYPE_ARRAY, "plan_turn() must return an Array")
	assert_eq(result, [], "base AIPlannerPort.plan_turn() must return an empty Array, not an error/null sentinel")


func test_base_plan_turn_pushes_error() -> void:
	var port := AIPlannerPortClass.new()

	# GUT/Godot doesn't expose a first-class "assert push_error was called"
	# hook, so this test documents + exercises the abstract contract
	# directly: calling the unimplemented base method is expected to emit
	# an engine error (visible in the test-run log) while still degrading
	# gracefully to a well-formed empty plan rather than throwing.
	assert_true(
		port.has_method("plan_turn"),
		"AIPlannerPort must expose plan_turn() so a push_error-then-return-[] contract is even reachable"
	)
	var result: Array = port.plan_turn(null, {})
	assert_eq(result, [], "abstract plan_turn() call (which push_errors) must still resolve to a well-formed empty plan")


func test_base_plan_turn_handles_missing_world_context_keys_gracefully() -> void:
	var port := AIPlannerPortClass.new()

	# world_context SHOULD carry party/enemies/action_economy per the
	# contract, but the abstract base must not assume/require any of them.
	var result: Array = port.plan_turn({"name": "dummy"}, {})
	assert_eq(result, [], "plan_turn() with a bare/empty world_context must still return []")


# ══════════════════════════════════════════════════════════════════════════
# 2. ai_decision_port.gd is untouched by this feature (diff-free check)
# ══════════════════════════════════════════════════════════════════════════

func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://")


func _git_available() -> bool:
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", _repo_root(), "rev-parse", "--is-inside-work-tree"], out, true)
	return rc == 0


func test_ai_decision_port_is_unmodified_per_adr_001() -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping ai_decision_port.gd diff-free check")
		return

	# Mirrors tests/unit/data/test_combine_data_commit_hygiene.gd's
	# established `git status --porcelain -- <path>` convention: any
	# staged, unstaged, or untracked change to the frozen
	# ai_decision_port.gd fails this test, proving ADR-001's "parallel
	# port, not an extension of frozen ai_decision_port.gd" constraint
	# actually held for this feature's changes.
	var out: Array = []
	var rc: int = OS.execute(
		"git",
		["-C", _repo_root(), "status", "--porcelain", "--", "core/application/ai_decision_port.gd"],
		out,
		true
	)
	var combined: String = ""
	for line in out:
		combined += String(line)

	assert_eq(rc, 0, "git status --porcelain -- core/application/ai_decision_port.gd must exit 0")
	assert_eq(
		combined.strip_edges(), "",
		(
			"core/application/ai_decision_port.gd must remain byte-for-byte "
			+ "unmodified/untouched by FEAT-001 (ADR-001: AIPlannerPort is a "
			+ "NEW parallel port, not an extension of the frozen "
			+ "ai_decision_port.gd). Offending git status output:\n%s"
		) % combined
	)


func test_ai_decision_port_file_exists_and_is_readable() -> void:
	# Sanity check underpinning the diff-free assertion above: the frozen
	# file must actually still exist at its documented path (a deleted
	# file would also report empty `git status --porcelain` output for the
	# wrong reason if this were somehow a rename/removal).
	assert_true(FileAccess.file_exists(AI_DECISION_PORT_PATH), "ai_decision_port.gd must still exist at its frozen path")


# ══════════════════════════════════════════════════════════════════════════
# 3. AIPlannerPort has no inheritance/coupling to AIDecisionPort
# ══════════════════════════════════════════════════════════════════════════

func test_ai_planner_port_does_not_inherit_from_ai_decision_port() -> void:
	var planner_port := AIPlannerPortClass.new()
	var decision_port := AIDecisionPortClass.new()

	# is_instance_of() (not the `is` operator) is used deliberately here:
	# GDScript's static type checker flags `is` between two provably
	# unrelated statically-typed script classes as a compile error ("so it
	# can't be of type ..."), which would make this file fail to even
	# parse. is_instance_of() performs the same runtime check without
	# tripping that static analysis.
	assert_false(
		is_instance_of(planner_port, AIDecisionPortClass),
		"an AIPlannerPort instance must not be an AIDecisionPort (no inheritance relationship)"
	)
	assert_false(
		is_instance_of(decision_port, AIPlannerPortClass),
		"an AIDecisionPort instance must not be an AIPlannerPort (no inheritance relationship)"
	)

	# Both ports must independently extend RefCounted directly (ADR-001
	# domain-purity boundary), not chain through one another.
	var planner_base_script = planner_port.get_script().get_base_script()
	var decision_base_script = decision_port.get_script().get_base_script()
	assert_null(planner_base_script, "AIPlannerPort's base script must be null (extends the built-in RefCounted directly, not another GDScript)")
	assert_null(decision_base_script, "AIDecisionPort's base script must be null (extends the built-in RefCounted directly, not another GDScript)")


## Strips full-line `##`/`#` doc/line comments so the coupling check below
## looks only at executable code (extends/preload/class_name/type
## references), not prose that merely *discusses* the sibling port for
## documentation purposes (e.g. this feature's own ADR-001 explanation of
## why the two ports are deliberately kept separate).
func _non_comment_lines(source: String) -> String:
	var kept: PackedStringArray = []
	for raw_line in source.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(raw_line)
	return "\n".join(kept)


func test_ai_planner_port_source_has_no_textual_coupling_to_ai_decision_port() -> void:
	var planner_code: String = _non_comment_lines(FileAccess.get_file_as_string(AI_PLANNER_PORT_PATH))
	var decision_code: String = _non_comment_lines(FileAccess.get_file_as_string(AI_DECISION_PORT_PATH))

	assert_false(
		planner_code.contains("ai_decision_port"),
		"ai_planner_port.gd's CODE (excluding comments) must not reference ai_decision_port.gd's path (no coupling, per ADR-001)"
	)
	assert_false(
		planner_code.contains("AIDecisionPort"),
		"ai_planner_port.gd's CODE (excluding comments) must not reference the AIDecisionPort class_name (no coupling, per ADR-001)"
	)
	assert_false(
		decision_code.contains("ai_planner_port"),
		"the frozen ai_decision_port.gd's CODE (excluding comments) must not reference ai_planner_port.gd's path"
	)
	assert_false(
		decision_code.contains("AIPlannerPort"),
		"the frozen ai_decision_port.gd's CODE (excluding comments) must not reference the AIPlannerPort class_name"
	)
