extends GutTest
## tests/unit/data/test_combine_data_commit_hygiene.gd
##
## FEAT-302 (US-001, US-009; NFR-006; CHECKLIST-4) — automated
## data-directory commit-hygiene gate.
##
## The prior review noted the project's automated test gate (pytest/GUT via
## scripts/test_command.sh) can pass even when data/ files (VerbResource
## .tres resources for STRIDE/STRIKE/COMBINE, and the
## reaction_follow_up/combinable fields added by US-001) exist only as
## working-tree edits -- CLAUDE.md's commit-hygiene rule ("data files MUST
## be committed") was previously a MANUAL reviewer inspection
## (`git status`/`git log`), not a machine-checkable gate.
##
## This suite turns that manual rule into a real, executable GUT test: it
## shells out to `git status --porcelain -- data/` (mirroring
## scripts/verify_clean_tree.sh's `git status --porcelain` convention, but
## scoped specifically to res://data, the directory CLAUDE.md's
## commit-hygiene section calls out by name) and asserts the captured
## output is empty. Any staged, unstaged, OR untracked change under data/
## fails this test with the offending `git status --porcelain` lines
## surfaced in the assertion message.
##
## A second test proves this isn't a vacuous check: it builds an isolated,
## throwaway git fixture repo (never touching the real project tree),
## deliberately dirties a tracked data/*.tres file (and adds an untracked
## one), and asserts `git status --porcelain -- data/` genuinely reports
## non-empty output in that dirty state -- confirming the detection
## mechanism this suite's real-repo test relies on actually works, not just
## that it happens to pass today because data/ happens to be clean today.
##
## Satisfies: FEAT-302, NFR-006, CHECKLIST-4.

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


## Absolute filesystem path to this project's repository root (the same
## directory a bare `git status` run from the repo root would operate
## against).
func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://")


## Best-effort availability check -- mirrors the existing
## OS.execute-availability convention already established in
## tests/ci/test_static_checks.gd and tests/sim/test_balance_simulation_post_fix.gd:
## some sandboxes may not expose a real subprocess-capable `git` binary, in
## which case this suite degrades to `pending()` rather than a hard
## failure, without ever silently skipping the check in an environment
## where it CAN run for real.
func _git_available() -> bool:
	var out: Array = []
	var rc: int = OS.execute("git", ["-C", _repo_root(), "rev-parse", "--is-inside-work-tree"], out, true)
	return rc == 0


## Runs `git -C <repo_dir> <args>`, capturing combined stdout+stderr and
## the process exit code.
func _run_git(repo_dir: String, args: Array) -> Dictionary:
	var full_args: Array = ["-C", repo_dir]
	full_args.append_array(args)
	var out: Array = []
	var rc: int = OS.execute("git", full_args, out, true)
	var combined: String = ""
	for line in out:
		combined += String(line)
	return {"exit_code": rc, "output": combined}


func _make_temp_dir() -> String:
	var out: Array = []
	var rc: int = OS.execute("mktemp", ["-d"], out, true)
	if rc != 0 or out.is_empty():
		return ""
	var path: String = String(out[0]).strip_edges()
	_temp_dirs.append(path)
	return path


func _write_file(path: String, contents: String) -> bool:
	var parent_dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(contents)
	f.close()
	return true


# ══════════════════════════════════════════════════════════════════════════
# The real gate: res://data/ must be fully committed right now.
# ══════════════════════════════════════════════════════════════════════════

## The core CHECKLIST-4 gate. Invokes `git status --porcelain -- data/`
## against the actual project repository (exactly as a reviewer's manual
## `git status` inspection would, per CLAUDE.md) and asserts zero pending
## changes. This FAILS (not silently passes) if any data/*.tres file --
## including the Combine feature's VerbResource STRIDE/STRIKE/COMBINE
## resources and their reaction_follow_up/combinable fields from US-001 --
## is modified or untracked at test time, and only passes once every such
## edit is staged and committed.
func test_data_directory_has_no_uncommitted_or_untracked_changes() -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping data/ commit-hygiene gate")
		return

	var result: Dictionary = _run_git(_repo_root(), ["status", "--porcelain", "--", "data/"])
	assert_eq(
		result["exit_code"], 0,
		"git status --porcelain -- data/ must exit 0; got %d, output: %s" % [result["exit_code"], result["output"]]
	)
	assert_eq(
		String(result["output"]).strip_edges(), "",
		(
			"res://data/ has uncommitted or untracked changes. Per CLAUDE.md's "
			+ "commit-hygiene rule (NFR-006), every data/*.tres edit (VerbResource "
			+ "STRIDE/STRIKE/COMBINE fields, reaction_follow_up/combinable from "
			+ "US-001 included) must be staged and committed before this gate can "
			+ "pass (CHECKLIST-4). Run `git add data/ && git commit` to resolve. "
			+ "Offending `git status --porcelain -- data/` output:\n%s"
		) % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# Proves the detection mechanism itself is real: an isolated fixture repo
# with a dirtied data/*.tres reports non-empty `git status --porcelain --
# data/` output. Never touches the real project tree.
# ══════════════════════════════════════════════════════════════════════════

func test_gate_mechanism_detects_dirty_data_file_in_isolated_fixture_repo() -> void:
	if not _git_available():
		pending("git unavailable in this sandbox -- skipping fixture-repo detection check")
		return

	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox -- skipping fixture-repo detection check")
		return

	var init_result: Dictionary = _run_git(tmp_dir, ["init", "-q"])
	assert_eq(init_result["exit_code"], 0, "git init must succeed in the fixture dir; output: %s" % init_result["output"])
	_run_git(tmp_dir, ["config", "user.email", "gate-fixture@example.com"])
	_run_git(tmp_dir, ["config", "user.name", "Gate Fixture"])

	var verb_resource_path: String = tmp_dir + "/data/combine/strike_verb.tres"
	_write_file(
		verb_resource_path,
		"[gd_resource type=\"Resource\" script_class=\"VerbResource\" load_steps=2 format=3]\nverb_id = \"STRIKE\"\ncombinable = true\nreaction_follow_up = false\n"
	)

	# Control case: a fresh commit of the fixture data file must report a
	# clean data/ status -- proves the fixture itself isn't just innately
	# dirty (which would make the "detects dirty" assertion below vacuous).
	_run_git(tmp_dir, ["add", "-A"])
	var commit_result: Dictionary = _run_git(tmp_dir, ["commit", "-q", "-m", "fixture: initial committed data/"])
	assert_eq(commit_result["exit_code"], 0, "fixture commit must succeed; output: %s" % commit_result["output"])

	var clean_result: Dictionary = _run_git(tmp_dir, ["status", "--porcelain", "--", "data/"])
	assert_eq(
		String(clean_result["output"]).strip_edges(), "",
		"control case: a freshly committed fixture repo must report clean data/ status; got: %s" % clean_result["output"]
	)

	# Dirty case 1: modify a TRACKED data/*.tres file without committing.
	_write_file(
		verb_resource_path,
		"[gd_resource type=\"Resource\" script_class=\"VerbResource\" load_steps=2 format=3]\nverb_id = \"STRIKE\"\ncombinable = true\nreaction_follow_up = true\n"
	)
	var dirty_modified_result: Dictionary = _run_git(tmp_dir, ["status", "--porcelain", "--", "data/"])
	assert_ne(
		String(dirty_modified_result["output"]).strip_edges(), "",
		"the gate mechanism must detect an uncommitted modification to a tracked data/*.tres file"
	)
	assert_true(
		String(dirty_modified_result["output"]).contains("strike_verb.tres"),
		"dirty output must name the offending fixture file; got: %s" % dirty_modified_result["output"]
	)

	# Dirty case 2: revert the modification, then add a new UNTRACKED
	# data/*.tres file -- the gate must catch untracked files too, not
	# only modifications to already-tracked ones.
	_run_git(tmp_dir, ["checkout", "--", "data/combine/strike_verb.tres"])
	var reverted_result: Dictionary = _run_git(tmp_dir, ["status", "--porcelain", "--", "data/"])
	assert_eq(
		String(reverted_result["output"]).strip_edges(), "",
		"after reverting the modification, the fixture repo must be clean again; got: %s" % reverted_result["output"]
	)

	_write_file(
		tmp_dir + "/data/combine/combine_verb.tres",
		"[gd_resource type=\"Resource\" script_class=\"VerbResource\" load_steps=2 format=3]\nverb_id = \"COMBINE\"\ncombinable = true\nreaction_follow_up = false\n"
	)
	var dirty_untracked_result: Dictionary = _run_git(tmp_dir, ["status", "--porcelain", "--", "data/"])
	assert_ne(
		String(dirty_untracked_result["output"]).strip_edges(), "",
		"the gate mechanism must detect an untracked data/*.tres file"
	)
	assert_true(
		String(dirty_untracked_result["output"]).contains("combine_verb.tres"),
		"dirty output must name the untracked fixture file; got: %s" % dirty_untracked_result["output"]
	)
