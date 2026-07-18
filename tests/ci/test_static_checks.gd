extends GutTest
## tests/ci/test_static_checks.gd
##
## GUT suite for FEAT-009 (US-009; NFR-001, NFR-002, NFR-006, NFR-007;
## ADR-001, ADR-002, ADR-006): architecture compliance static-check
## tooling.
##
## Exercises the two standalone shell-script CI gates this feature
## introduces:
##   - ci/check_domain_purity.sh   (ADR-001: no Node/Control in core/)
##   - ci/check_no_duplicate_seams.sh (ADR-002/ADR-006: no duplicate
##     _movement_used gate / AI decision / token-reposition call path)
##
## Both scripts are invoked exactly as CI (ci/pipeline.yml) invokes them —
## via a real subprocess (OS.execute) — so this suite proves the scripts
## actually work end-to-end, not merely that their source text looks
## plausible. Fixture directories used to prove the "catches a real
## violation" criteria are built fresh under a temp dir for each test
## (never by mutating the real core/ tree) and torn down afterward.

const DOMAIN_PURITY_SCRIPT: String = "res://ci/check_domain_purity.sh"
const NO_DUP_SEAMS_SCRIPT: String = "res://ci/check_no_duplicate_seams.sh"
const PIPELINE_YML_PATH: String = "res://ci/pipeline.yml"

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


## _make_temp_dir() -> String — creates a fresh, empty filesystem temp
## directory (via `mktemp -d`) and registers it for cleanup in
## after_each(). Returns "" if the underlying `mktemp` call is unavailable
## in this sandbox (tests using it should skip/no-op rather than fail
## hard in that case, mirroring this project's existing best-effort
## OS.execute-availability convention — see
## tests/sim/test_balance_simulation_post_fix.gd).
func _make_temp_dir() -> String:
	var out: Array = []
	var rc: int = OS.execute("mktemp", ["-d"], out, true)
	if rc != 0 or out.is_empty():
		return ""
	var path: String = String(out[0]).strip_edges()
	_temp_dirs.append(path)
	return path


## _write_file(path, contents) -> bool — writes `contents` to an absolute
## filesystem `path`, creating any missing parent directories first.
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
## runs one of this feature's ci/*.sh scripts via `bash` (so the scripts'
## own shebang/permissions are irrelevant to whether the test harness can
## invoke them) against the given arguments, capturing combined
## stdout+stderr.
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

func test_check_domain_purity_script_exists() -> void:
	assert_true(
		FileAccess.file_exists(DOMAIN_PURITY_SCRIPT),
		"ci/check_domain_purity.sh must exist"
	)


func test_check_no_duplicate_seams_script_exists() -> void:
	assert_true(
		FileAccess.file_exists(NO_DUP_SEAMS_SCRIPT),
		"ci/check_no_duplicate_seams.sh must exist"
	)


func test_check_domain_purity_script_has_shebang() -> void:
	var f := FileAccess.open(DOMAIN_PURITY_SCRIPT, FileAccess.READ)
	assert_not_null(f, "ci/check_domain_purity.sh must be readable")
	if f == null:
		return
	assert_true(
		f.get_line().begins_with("#!"),
		"ci/check_domain_purity.sh must start with a shebang line"
	)


func test_check_no_duplicate_seams_script_has_shebang() -> void:
	var f := FileAccess.open(NO_DUP_SEAMS_SCRIPT, FileAccess.READ)
	assert_not_null(f, "ci/check_no_duplicate_seams.sh must be readable")
	if f == null:
		return
	assert_true(
		f.get_line().begins_with("#!"),
		"ci/check_no_duplicate_seams.sh must start with a shebang line"
	)


# ══════════════════════════════════════════════════════════════════════════
# ci/check_domain_purity.sh: real core/ tree passes (test_criteria #1)
# ══════════════════════════════════════════════════════════════════════════

func test_domain_purity_check_exits_zero_against_real_core_tree() -> void:
	var result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, ["core"])
	assert_eq(
		result["exit_code"], 0,
		"check_domain_purity.sh must exit 0 against the current core/ tree; output: %s" % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# ci/check_domain_purity.sh: injected 'extends Node' fails (test_criteria #1)
# ══════════════════════════════════════════════════════════════════════════

func test_domain_purity_check_exits_nonzero_on_injected_extends_node() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	# A clean, legitimate domain file first — proves the fixture dir itself
	# isn't just empty (which would make the check vacuously pass).
	_write_file(
		tmp_dir + "/core/rules/clean_fixture.gd",
		"class_name CleanFixture\nextends RefCounted\nvar q: int\n"
	)
	var clean_result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, [tmp_dir + "/core"])
	assert_eq(
		clean_result["exit_code"], 0,
		"control case: a clean fixture dir must pass; output: %s" % clean_result["output"]
	)

	# Deliberately inject a Node-extending file (ADR-001 violation).
	_write_file(
		tmp_dir + "/core/rules/injected_violation.gd",
		"class_name RogueWidget\nextends Node\n\nfunc _ready() -> void:\n\tpass\n"
	)
	var dirty_result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, [tmp_dir + "/core"])
	assert_ne(
		dirty_result["exit_code"], 0,
		"check_domain_purity.sh must exit non-zero once an 'extends Node' line is injected into a core/ fixture file"
	)
	assert_true(
		dirty_result["output"].contains("injected_violation.gd"),
		"failure output must name the offending fixture file; got: %s" % dirty_result["output"]
	)


func test_domain_purity_check_exits_nonzero_on_injected_extends_control() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_write_file(
		tmp_dir + "/core/rules/injected_control_violation.gd",
		"class_name RogueLabel\nextends Control\n"
	)
	var result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, [tmp_dir + "/core"])
	assert_ne(
		result["exit_code"], 0,
		"check_domain_purity.sh must exit non-zero once an 'extends Control' line is injected into a core/ fixture file"
	)


func test_domain_purity_check_does_not_flag_string_extends_chain() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	# A quoted extends chain (this project's real script-inheritance
	# pattern, e.g. core/application/ai_decision_port.gd's adapters) must
	# never be a false positive.
	_write_file(
		tmp_dir + "/core/rules/adapter_fixture.gd",
		"class_name Adapter\nextends \"res://core/rules/random_port.gd\"\n"
	)
	var result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, [tmp_dir + "/core"])
	assert_eq(
		result["exit_code"], 0,
		"a quoted extends \"res://...\" chain must not be flagged as a scene-tree violation; output: %s" % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# ci/check_no_duplicate_seams.sh: real repo passes (test_criteria #2)
# ══════════════════════════════════════════════════════════════════════════

func test_no_duplicate_seams_check_exits_zero_against_real_repo() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [repo_root])
	assert_eq(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit 0 against the current repository; output: %s" % result["output"]
	)
	assert_true(
		result["output"].contains("_movement_used"),
		"output must confirm the _movement_used gate check ran; got: %s" % result["output"]
	)


## FEAT-002 (US-002): the seam-4 EffectsApplier check must also run (and
## pass) against the real repository, confirming EffectsApplier is
## reported as the sole (non-legacy) call site of every Combatant mutator.
func test_no_duplicate_seams_check_reports_effects_applier_seam_against_real_repo() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [repo_root])
	assert_eq(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit 0 against the current repository; output: %s" % result["output"]
	)
	for method_name in ["take_damage", "heal", "add_condition", "move_to"]:
		assert_true(
			result["output"].contains(method_name),
			"output must confirm the '%s' EffectsApplier-seam check ran; got: %s" % [method_name, result["output"]]
		)


# ══════════════════════════════════════════════════════════════════════════
# ci/check_no_duplicate_seams.sh: injected duplicate _movement_used gate
# is detected (test_criteria #2)
# ══════════════════════════════════════════════════════════════════════════

func _copy_real_file_into_fixture(res_source_path: String, dest_path: String) -> void:
	var f := FileAccess.open(res_source_path, FileAccess.READ)
	if f == null:
		return
	var contents: String = f.get_as_text()
	f.close()
	_write_file(dest_path, contents)


func _build_clean_fixture_repo(tmp_dir: String) -> void:
	_copy_real_file_into_fixture(
		"res://core/rules/action_economy.gd", tmp_dir + "/core/rules/action_economy.gd"
	)
	_copy_real_file_into_fixture(
		"res://core/combat/ai.gd", tmp_dir + "/core/combat/ai.gd"
	)
	_copy_real_file_into_fixture(
		"res://core/application/ai_decision_port.gd", tmp_dir + "/core/application/ai_decision_port.gd"
	)
	_copy_real_file_into_fixture(
		"res://presentation/hex_grid_view.gd", tmp_dir + "/presentation/hex_grid_view.gd"
	)
	# FEAT-002 (US-002): EffectsApplier is the fixture's sole legitimate
	# call site of take_damage()/heal()/add_condition()/move_to() -- see
	# the seam-4 tests below.
	_copy_real_file_into_fixture(
		"res://core/domain/effects_applier.gd", tmp_dir + "/core/domain/effects_applier.gd"
	)


func test_no_duplicate_seams_check_passes_on_clean_fixture_repo() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_eq(
		result["exit_code"], 0,
		"control case: a clean single-seam fixture repo must pass; output: %s" % result["output"]
	)


func test_no_duplicate_seams_check_detects_injected_duplicate_movement_gate() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/core/rules/rogue_action_economy.gd",
		"class_name RogueActionEconomy\nextends RefCounted\nvar _movement_used: bool = false\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a second '_movement_used' gate is injected"
	)
	assert_true(
		result["output"].contains("_movement_used"),
		"failure output must name the _movement_used seam; got: %s" % result["output"]
	)


func test_no_duplicate_seams_check_detects_injected_duplicate_ai_decision_path() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/core/combat/rogue_ai.gd",
		"class_name RogueAI\nextends RefCounted\nfunc decide_action(_combatant: Dictionary, _targets: Array) -> Dictionary:\n\treturn {}\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a second concrete 'decide_action' implementation is injected"
	)


func test_no_duplicate_seams_check_detects_injected_duplicate_token_reposition_path() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/presentation/rogue_token_view.gd",
		"class_name RogueTokenView\nextends RefCounted\nfunc move_token(_combatant_id: String, _new_hex_coord) -> void:\n\tpass\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a second 'move_token' implementation is injected"
	)


# ══════════════════════════════════════════════════════════════════════════
# ci/check_no_duplicate_seams.sh: seam-4 -- EffectsApplier must be the sole
# (non-legacy) call site of take_damage/heal/add_condition/move_to
# (FEAT-002 / US-002)
# ══════════════════════════════════════════════════════════════════════════

func test_no_duplicate_seams_check_detects_injected_duplicate_heal_caller() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/presentation/rogue_healer.gd",
		"class_name RogueHealer\nextends RefCounted\nfunc do_heal(c) -> void:\n\tc.heal(5)\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a file outside EffectsApplier calls .heal( directly"
	)
	assert_true(
		result["output"].contains("rogue_healer.gd"),
		"failure output must name the offending fixture file; got: %s" % result["output"]
	)


func test_no_duplicate_seams_check_detects_injected_duplicate_add_condition_caller() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	_write_file(
		tmp_dir + "/presentation/rogue_condition_setter.gd",
		"class_name RogueConditionSetter\nextends RefCounted\nfunc do_it(c) -> void:\n\tc.add_condition(\"Off-Guard\")\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a file outside EffectsApplier calls .add_condition( directly"
	)
	assert_true(
		result["output"].contains("rogue_condition_setter.gd"),
		"failure output must name the offending fixture file; got: %s" % result["output"]
	)


func test_no_duplicate_seams_check_detects_injected_take_damage_caller_outside_legacy_allowlist() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	# resolve_action_use_case.gd / apply_on_hit_defense_uc.gd are the ONLY
	# documented pre-existing take_damage() callers (pending US-004/US-005
	# retrofit) -- a call site at any OTHER path must still be flagged.
	_write_file(
		tmp_dir + "/core/application/rogue_damage_source.gd",
		"class_name RogueDamageSource\nextends RefCounted\nfunc do_it(c) -> void:\n\tc.take_damage(3)\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a take_damage() call site exists outside EffectsApplier and the documented legacy allowlist"
	)
	assert_true(
		result["output"].contains("rogue_damage_source.gd"),
		"failure output must name the offending fixture file; got: %s" % result["output"]
	)


func test_no_duplicate_seams_check_detects_injected_move_to_caller_outside_legacy_allowlist() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	_build_clean_fixture_repo(tmp_dir)
	# core/rules/movement.gd is the ONLY documented pre-existing move_to()
	# caller (a distinct, permanent Movement rule-layer seam) -- a call
	# site at any OTHER path must still be flagged.
	_write_file(
		tmp_dir + "/presentation/rogue_mover.gd",
		"class_name RogueMover\nextends RefCounted\nfunc do_it(c, hex) -> void:\n\tc.move_to(hex)\n"
	)
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [tmp_dir])
	assert_ne(
		result["exit_code"], 0,
		"check_no_duplicate_seams.sh must exit non-zero when a move_to() call site exists outside EffectsApplier and the documented legacy allowlist"
	)
	assert_true(
		result["output"].contains("rogue_mover.gd"),
		"failure output must name the offending fixture file; got: %s" % result["output"]
	)


# ══════════════════════════════════════════════════════════════════════════
# ci/pipeline.yml wires both scripts in as blocking gates (test_criteria #3)
# ══════════════════════════════════════════════════════════════════════════

func _read_pipeline_yml_text() -> String:
	var f := FileAccess.open(PIPELINE_YML_PATH, FileAccess.READ)
	assert_not_null(f, "ci/pipeline.yml must exist and be readable")
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func test_pipeline_yml_invokes_domain_purity_check() -> void:
	var contents: String = _read_pipeline_yml_text()
	assert_true(
		contents.contains("check_domain_purity.sh"),
		"ci/pipeline.yml must declare a stage invoking ci/check_domain_purity.sh"
	)


func test_pipeline_yml_invokes_no_duplicate_seams_check() -> void:
	var contents: String = _read_pipeline_yml_text()
	assert_true(
		contents.contains("check_no_duplicate_seams.sh"),
		"ci/pipeline.yml must declare a stage invoking ci/check_no_duplicate_seams.sh"
	)


## Both new stages must be required/blocking — `required: true`,
## `optional: false` — not merely advisory, mirroring every existing
## stage's convention in ci/pipeline.yml.
func test_pipeline_yml_new_stages_are_required_blocking_gates() -> void:
	var contents: String = _read_pipeline_yml_text()
	# Search for the STAGE's own `command:` line specifically (rather than
	# the first mention anywhere in the file) -- this feature's own
	# header-comment prose above the `stages:` list also names both
	# scripts, and a bare .find("check_domain_purity.sh") would match that
	# comment block instead of the actual stage entry, whose required/
	# optional flags follow further down.
	var domain_purity_idx: int = contents.find("command: ci/check_domain_purity.sh")
	var no_dup_seams_idx: int = contents.find("command: ci/check_no_duplicate_seams.sh")

	assert_true(domain_purity_idx != -1 and no_dup_seams_idx != -1)
	if domain_purity_idx == -1 or no_dup_seams_idx == -1:
		return

	# Look at a window of text around/after each stage's command line for
	# its required/optional flags (stage blocks are short, so a generous
	# forward window safely captures the same stage's own fields without
	# spilling into the next stage for this file's stage block size).
	var domain_purity_block: String = contents.substr(domain_purity_idx, 400)
	var no_dup_seams_block: String = contents.substr(no_dup_seams_idx, 400)

	assert_true(
		domain_purity_block.contains("required: true"),
		"the check_domain_purity.sh stage must be declared required: true"
	)
	assert_true(
		domain_purity_block.contains("optional: false"),
		"the check_domain_purity.sh stage must be declared optional: false"
	)
	assert_true(
		no_dup_seams_block.contains("required: true"),
		"the check_no_duplicate_seams.sh stage must be declared required: true"
	)
	assert_true(
		no_dup_seams_block.contains("optional: false"),
		"the check_no_duplicate_seams.sh stage must be declared optional: false"
	)


## End-to-end: running the exact commands ci/pipeline.yml declares for
## these two stages, from the repo root, must actually pass (proves the
## wiring isn't just textually present but functionally correct).
func test_pipeline_declared_domain_purity_stage_command_passes() -> void:
	var result: Dictionary = _run_script(DOMAIN_PURITY_SCRIPT, ["core"])
	assert_eq(result["exit_code"], 0, result["output"])


func test_pipeline_declared_no_duplicate_seams_stage_command_passes() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var result: Dictionary = _run_script(NO_DUP_SEAMS_SCRIPT, [repo_root])
	assert_eq(result["exit_code"], 0, result["output"])
