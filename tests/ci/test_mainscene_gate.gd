extends GutTest
## tests/ci/test_mainscene_gate.gd
##
## GUT suite for FEAT-010 (US-009; FR-009, FR-010, FR-011; ADR-001 fitness
## functions): the composition-root line-count / no-circular-preload CI
## gate.
##
## Exercises ci/check_mainscene_gate.sh exactly as CI (ci/pipeline.yml)
## would invoke it -- via a real subprocess (OS.execute) -- so this suite
## proves the script actually works end-to-end, not merely that its source
## text looks plausible. Fixture files used to prove the "catches a real
## violation" criteria are built fresh under a temp dir for each test
## (never by mutating the real MainScene.gd) and torn down afterward.

const GATE_SCRIPT: String = "res://ci/check_mainscene_gate.sh"
const MAIN_SCENE_PATH: String = "res://MainScene.gd"

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


## _make_temp_dir() -> String — creates a fresh, empty filesystem temp
## directory (via `mktemp -d`) and registers it for cleanup in after_each().
## Returns "" if the underlying `mktemp` call is unavailable in this
## sandbox (tests using it should skip/no-op rather than fail hard in that
## case, mirroring tests/ci/test_static_checks.gd's identical convention).
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


## _run_script(script_res_path, args) -> Dictionary{exit_code, output} —
## runs ci/check_mainscene_gate.sh via `bash` against the given arguments,
## capturing combined stdout+stderr, mirroring
## tests/ci/test_static_checks.gd's identical helper.
func _run_script(script_res_path: String, args: Array) -> Dictionary:
	var absolute_script_path: String = ProjectSettings.globalize_path(script_res_path)
	var out: Array = []
	var full_args: Array = [absolute_script_path]
	full_args.append_array(args)
	var rc: int = OS.execute("bash", full_args, out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)
	return {"exit_code": rc, "output": combined_output}


# ══════════════════════════════════════════════════════════════════════════
# File existence / shape
# ══════════════════════════════════════════════════════════════════════════

func test_check_mainscene_gate_script_exists() -> void:
	assert_true(
		FileAccess.file_exists(GATE_SCRIPT),
		"ci/check_mainscene_gate.sh must exist"
	)


func test_check_mainscene_gate_script_has_shebang() -> void:
	var f := FileAccess.open(GATE_SCRIPT, FileAccess.READ)
	assert_not_null(f, "ci/check_mainscene_gate.sh must be readable")
	if f == null:
		return
	assert_true(
		f.get_line().begins_with("#!"),
		"ci/check_mainscene_gate.sh must start with a shebang line"
	)


# ══════════════════════════════════════════════════════════════════════════
# Real MainScene.gd passes both fitness functions (test_criteria #1/#2)
# ══════════════════════════════════════════════════════════════════════════

func test_gate_exits_zero_against_real_mainscene() -> void:
	var result: Dictionary = _run_script(GATE_SCRIPT, [ProjectSettings.globalize_path(MAIN_SCENE_PATH)])
	assert_eq(
		result["exit_code"], 0,
		"check_mainscene_gate.sh must exit 0 against the current MainScene.gd; output: %s" % result["output"]
	)


func test_real_mainscene_is_at_most_1000_lines() -> void:
	var f := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	assert_not_null(f, "MainScene.gd must be readable")
	if f == null:
		return
	var line_count: int = 0
	while not f.eof_reached():
		f.get_line()
		line_count += 1
	f.close()
	# FileAccess.get_line() reports one extra "line" when the file ends
	# with a trailing newline (an empty final read) -- tolerate a
	# one-line fencepost difference against `wc -l`'s convention.
	assert_true(
		line_count <= 1001,
		"MainScene.gd must be <= 1000 lines (US-009/FR-009); got %d" % line_count
	)


# ══════════════════════════════════════════════════════════════════════════
# Line-count budget: oversized fixture fails (test_criteria #1)
# ══════════════════════════════════════════════════════════════════════════

func test_gate_exits_nonzero_on_oversized_fixture() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var oversized_contents: String = "extends Node\n"
	for i in range(1010):
		oversized_contents += "# line %d\n" % i
	var fixture_path: String = tmp_dir + "/MainScene.gd"
	_write_file(fixture_path, oversized_contents)

	var result: Dictionary = _run_script(GATE_SCRIPT, [fixture_path])
	assert_ne(
		result["exit_code"], 0,
		"check_mainscene_gate.sh must exit non-zero when the target file exceeds 1000 lines"
	)
	assert_true(
		result["output"].contains("1000"),
		"failure output must mention the line-count budget; got: %s" % result["output"]
	)


func test_gate_exits_zero_on_fixture_exactly_at_budget() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var contents: String = "extends Node\n"
	for i in range(999):
		contents += "# line %d\n" % i
	var fixture_path: String = tmp_dir + "/MainScene.gd"
	_write_file(fixture_path, contents)

	var result: Dictionary = _run_script(GATE_SCRIPT, [fixture_path])
	assert_eq(
		result["exit_code"], 0,
		"control case: a fixture at exactly the 1000-line budget must pass; output: %s" % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# Circular preload: injected self-reference fails (test_criteria #2)
# ══════════════════════════════════════════════════════════════════════════

func test_gate_exits_nonzero_on_injected_circular_preload() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var fixture_path: String = tmp_dir + "/MainScene.gd"
	_write_file(
		fixture_path,
		"extends Node\nconst RogueSelfRef = preload(\"res://MainScene.gd\")\nfunc _ready() -> void:\n\tpass\n"
	)

	var result: Dictionary = _run_script(GATE_SCRIPT, [fixture_path])
	assert_ne(
		result["exit_code"], 0,
		"check_mainscene_gate.sh must exit non-zero when MainScene.gd preloads itself"
	)
	assert_true(
		result["output"].contains("MainScene.gd"),
		"failure output must name the circular reference; got: %s" % result["output"]
	)


func test_gate_does_not_flag_doc_comment_mentioning_mainscene() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var fixture_path: String = tmp_dir + "/MainScene.gd"
	_write_file(
		fixture_path,
		"extends Node\n## see MainScene.gd's own doc for details\nfunc _ready() -> void:\n\tpass\n"
	)

	var result: Dictionary = _run_script(GATE_SCRIPT, [fixture_path])
	assert_eq(
		result["exit_code"], 0,
		"a doc-comment mentioning MainScene.gd by name must not be flagged as a circular preload; output: %s" % result["output"]
	)


func test_gate_does_not_flag_preload_of_a_different_file() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	var fixture_path: String = tmp_dir + "/MainScene.gd"
	_write_file(
		fixture_path,
		"extends Node\nconst SomeOtherClass = preload(\"res://presentation/round_flow_controller.gd\")\n"
	)

	var result: Dictionary = _run_script(GATE_SCRIPT, [fixture_path])
	assert_eq(
		result["exit_code"], 0,
		"preloading an unrelated file must not be flagged as circular; output: %s" % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# Missing file argument
# ══════════════════════════════════════════════════════════════════════════

func test_gate_exits_nonzero_when_target_file_missing() -> void:
	var result: Dictionary = _run_script(GATE_SCRIPT, ["/nonexistent/path/MainScene.gd"])
	assert_ne(
		result["exit_code"], 0,
		"check_mainscene_gate.sh must exit non-zero when the target file does not exist"
	)
