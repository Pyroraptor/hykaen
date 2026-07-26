extends GutTest
## tests/integration/test_headless_boot.gd — FEAT-010 (US-010; NFR-003/
## NFR-004/NFR-005), Iteration F steel-thread capstone: headless-boot
## zero-error/zero-warning gate.
##
## GDScript/GUT-native complement to tests/integration/
## test_headless_boot_smoke.py's pytest suite (which already proves the
## identical guarantee): spawns a SECOND, independent, real
## `godot --headless` process booting this project's actual
## run/main_scene target (project.godot's run/main_scene=
## res://scenes/TitleScreen.tscn as of FEAT-337/DEF-001 -- see that fix's
## own doc below -- no GUT harness/HeadlessRunner involvement beyond the
## autoload every launch of this project always carries) and reads that
## process's own real stdout+stderr directly -- the one vantage point from
## which "zero ERROR/WARNING console output" can actually be observed
## (mirrors tests/ci/test_static_checks.gd's established OS.execute-based
## real-subprocess convention, and tests/integration/
## test_headless_boot_smoke.py's own `bare_headless_boot` fixture
## rationale).
##
## FEAT-337 (DEF-001): project.godot's run/main_scene was repointed from
## res://MainScene.tscn to res://scenes/TitleScreen.tscn -- a real launched
## build must reach the Title Screen (New Game / Continue / Dev: Pick
## Scenario) first, per the steel thread's declared entry_point and FR-006
## AC1, rather than bypassing it straight into MainScene via ADR-005's
## uninitialized-CurrentGameState fallback. This suite's "reaches an
## interactive boot state" marker below is updated accordingly to
## TitleScreen's own boot-confirmation print (presentation/title_screen.gd's
## _ready()), not MainScene's.
##
## Design note -- why a SEPARATE bare boot, never `godot --headless --
## --gut-run-all`/`-s addons/gut/gut_cmdln.gd`: in this project's pinned
## engine build, loading GUT's own bundled editor-GUI scripts (e.g.
## addons/gut/gui/RunExternally.gd) independently emits real, pre-existing
## SCRIPT ERROR/ERROR-level console lines that have nothing to do with this
## project's own res://MainScene.tscn composition root -- a GUT-tooling
## compatibility quirk, not a regression in any of this feature's own files.
## Asserting "zero ERROR output" against a process that also loads GUT's own
## editor tooling would therefore make this gate permanently red for a
## reason entirely orthogonal to what this feature exists to verify. A bare
## `godot --headless --quit-after N` boot of the shipped project (no GUT
## involvement at all beyond the tests/runner/headless_runner.gd autoload
## every real launch of this project already carries) sidesteps that
## entirely and observes exactly what a real, non-test player launch would
## produce on their own console.
##
## Design note -- the pre-existing "invalid UID" resource-format warning
## class: booting this project today already emits a handful of
## WARNING-level lines of the shape:
##
##     WARNING: res://data/encounters/prologue_encounter.tres:3 - ext_resource,
##     invalid UID: uid://encrsc1a2b3cd - using text path instead: ...
##          at: load (scene/resources/resource_format_text.cpp:453)
##
## These come from Godot's resource loader falling back from a stale/
## placeholder UID recorded inside this project's committed `.tres` fixture
## files (data/*) to the resource's text path -- a pre-existing, unrelated
## data/tooling quirk (no corresponding `.gd.uid` files are committed) that
## predates this feature, is not one of this feature's files_to_create/
## files_to_modify, and carries no resolves_findings entry. It fires during
## ResourceLoader.load(), before MainScene.gd's own composition-root logic
## (the thing this feature's steel thread actually verifies) ever runs a
## single line. Treating it as a hard failure here would make this gate
## permanently red for a reason entirely orthogonal to what this feature
## exists to verify -- so this suite narrowly allowlists ONLY that
## documented warning shape (reusing tests/integration/
## test_headless_boot_smoke.py's identical, already-reviewed rationale
## verbatim rather than re-deriving a second one) and requires TRUE ZERO
## tolerance for every other WARNING and for every ERROR line.
##
## Every subprocess-invoking test is skipped (via GUT's pending(), mirroring
## tests/ci/test_static_checks.gd's `mktemp`-unavailable convention) when no
## `godot` binary is discoverable on PATH, so this suite still collects and
## reports meaningfully in any environment.
##
## test_criteria satisfied: "MainScene boots headless with zero error/
## warning lines to stdout/stderr" and "Zero flakiness observed across
## multiple consecutive CI runs at the pinned seed."

const SeedPolicyClass = preload("res://infrastructure/seed_policy.gd")

## The real boot-confirmation log line presentation/title_screen.gd's own
## _ready() prints (see TitleScreen.gd's
## `print("INFO: Hykaen TitleScreen booted...")` call) -- used below to
## guard against a degenerate "silently empty/no-op boot" trivially
## satisfying "zero ERROR/WARNING output".
##
## FEAT-337 (DEF-001): project.godot's run/main_scene now boots into
## res://scenes/TitleScreen.tscn, not res://MainScene.tscn -- a real,
## non-test launch (this file's bare `godot --headless` subprocess never
## presses New Game/Continue) reaches TitleScreen's own interactive,
## input-awaiting boot state and stops there, so this suite's marker is
## TitleScreen's boot-confirmation line, not MainScene's. (MainScene's own
## "...booted into EXPLORATION mode..." print, previously asserted here
## pre-FEAT-337, only ever fires now once TitleScreen's New Game/Continue/
## Dev:Pick Scenario transitions into MainScene.tscn -- see tests/boot/
## test_title_screen_boot_performance.gd and tests/unit/
## test_title_screen_buttons.gd for that later-stage coverage.)
const MAIN_SCENE_BOOT_MARKER: String = "Hykaen TitleScreen booted -- interactive, input-awaiting boot state"

## The ONE pre-existing, documented, out-of-scope warning shape this suite
## allowlists (see file-level design note above) -- the specific
## "ext_resource, invalid UID ... using text path instead" phrasing Godot's
## resource_format_text.cpp loader emits.
const _ALLOWLISTED_WARNING_MARKER_A: String = "ext_resource, invalid UID"
const _ALLOWLISTED_WARNING_MARKER_B: String = "using text path instead"

## FEAT-004 (US-004; FR-004, ADR-005, mitigates RISK-006): a SECOND,
## deliberately narrow, documented warning shape allowlisted alongside the
## resource-UID one above -- mirrors tests/integration/
## test_headless_boot_smoke.py's identical
## _ALLOWLISTED_CURRENT_GAME_STATE_FALLBACK_WARNING_PATTERN addition. A bare
## headless boot never goes through a title screen / "New Game" flow (that
## composition-root wiring is TitleScreen.gd, a LATER, not-yet-implemented
## feature), so CurrentGameState.data is genuinely, correctly uninitialized
## here every time, and MainScene._ready()'s single push_warning() fallback
## call site (see MainScene.gd) is expected, intentional steel-thread
## behavior -- an explicit FEAT-004 test_criterion, not a regression.
const _ALLOWLISTED_WARNING_MARKER_CURRENT_GAME_STATE_FALLBACK: String = (
	"MainScene: CurrentGameState was uninitialized; falling back to prologue"
)

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) -- this
## codebase's established integration/E2E convention. Threaded through to
## the spawned subprocess via the HYKAEN_SEED environment variable
## (infrastructure/seed_policy.gd) so every repeated boot below is pinned to
## the identical, reproducible playthrough.
const PINNED_SEED: int = 42

## Number of frames the bare headless boot is allowed to run before Godot's
## own `--quit-after` flag terminates it (CWE-835 "never loop unbounded"
## guard, mirroring tests/integration/test_headless_boot_smoke.py's
## `_QUIT_AFTER_FRAMES`).
const _QUIT_AFTER_FRAMES: int = 10

## Safety bound (seconds) on the spawned subprocess, enforced via the
## `timeout` shell utility so a hung child process can never stall this
## suite indefinitely (CWE-835 guard).
const _SUBPROCESS_TIMEOUT_SECONDS: int = 90

## Number of independent, repeated bare boots exercised by the
## multi-consecutive-run flakiness check below (mirrors tests/integration/
## test_steel_thread_e2e.gd's `_DETERMINISM_RUN_COUNT`).
const _REPEATED_RUN_COUNT: int = 3


# ══════════════════════════════════════════════════════════════════════════
# Real-environment isolation for HYKAEN_SEED -- mirrors tests/regression/
# test_seed_determinism.gd's before_each()/after_each() convention so no
# test state leaks to any other GUT script sharing this headless run.
# ══════════════════════════════════════════════════════════════════════════

var _had_env_var_before: bool = false
var _original_env_value: String = ""


func before_each() -> void:
	_had_env_var_before = OS.has_environment(SeedPolicyClass.ENV_VAR_NAME)
	if _had_env_var_before:
		_original_env_value = OS.get_environment(SeedPolicyClass.ENV_VAR_NAME)
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(PINNED_SEED))


func after_each() -> void:
	if _had_env_var_before:
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, _original_env_value)
	else:
		OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)


## _find_godot_binary() -> String -- mirrors tests/integration/
## test_headless_boot_smoke.py's identically-named helper's candidate list,
## so both suites agree on how the `godot` binary is discovered.
func _find_godot_binary() -> String:
	for candidate in ["godot", "godot4", "godot4.3", "godot-headless"]:
		var out: Array = []
		var rc: int = OS.execute("which", [candidate], out, true)
		if rc == 0 and not out.is_empty():
			return candidate
	return ""


## _classify_console_lines(text) -> Dictionary{errors: Array, warnings: Array}
## -- splits raw Godot console output into (errors, warnings), where
## `warnings` EXCLUDES any line matching the one documented, pre-existing
## allowlisted warning shape above -- mirrors tests/integration/
## test_headless_boot_smoke.py's `_classify_console_lines()` classification
## logic exactly (never a re-derived/divergent rule).
func _classify_console_lines(text: String) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("ERROR:"):
			errors.append(line)
		elif line.begins_with("WARNING:"):
			var is_allowlisted: bool = (
				(line.contains(_ALLOWLISTED_WARNING_MARKER_A) and line.contains(_ALLOWLISTED_WARNING_MARKER_B))
				or line.contains(_ALLOWLISTED_WARNING_MARKER_CURRENT_GAME_STATE_FALLBACK)
			)
			if not is_allowlisted:
				warnings.append(line)
	return {"errors": errors, "warnings": warnings}


## _run_bare_headless_boot() -> Dictionary{exit_code: int, output: String} --
## spawns a SECOND, independent, real `godot --headless` process booting
## this project's actual run/main_scene target (no GUT/HeadlessRunner
## involvement beyond the autoload every launch of this project always
## carries) via the `timeout` utility (CWE-835 bound), capturing combined
## stdout+stderr, mirroring tests/ci/test_static_checks.gd's OS.execute
## convention.
func _run_bare_headless_boot(godot_bin: String) -> Dictionary:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var rc: int = OS.execute(
		"timeout",
		[
			str(_SUBPROCESS_TIMEOUT_SECONDS),
			godot_bin, "--headless", "--path", repo_root,
			"--quit-after", str(_QUIT_AFTER_FRAMES),
		],
		out, true
	)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)
	return {"exit_code": rc, "output": combined_output}


# ══════════════════════════════════════════════════════════════════════════
# Classification-logic unit tests -- run with no `godot` binary required, so
# this suite's allowlist discriminates correctly regardless of environment.
# Mirrors tests/integration/test_headless_boot_smoke.py's
# TestConsoleLineClassification suite exactly.
# ══════════════════════════════════════════════════════════════════════════

func test_allowlisted_uid_warning_is_excluded() -> void:
	var sample: String = (
		"WARNING: res://data/encounters/prologue_encounter.tres:3 - "
		+ "ext_resource, invalid UID: uid://encrsc1a2b3cd - using text "
		+ "path instead: res://data/encounters/encounter_resource.gd\n"
		+ "     at: load (scene/resources/resource_format_text.cpp:453)"
	)
	var classified: Dictionary = _classify_console_lines(sample)
	assert_eq(classified["errors"], [])
	assert_eq(classified["warnings"], [], "the documented pre-existing resource-UID warning shape must be allowlisted, not flagged")


func test_allowlisted_current_game_state_fallback_warning_is_excluded() -> void:
	## FEAT-004 (US-004; FR-004, ADR-005): the SECOND allowlisted warning
	## shape -- MainScene's own uninitialized-CurrentGameState fallback --
	## is expected, intentional steel-thread behavior on a bare headless
	## boot, so it must be excluded exactly like the pre-existing
	## resource-UID warning above.
	var sample: String = (
		"WARNING: MainScene: CurrentGameState was uninitialized; falling back to prologue\n"
		+ "     at: push_warning (core/variant/variant_utility.cpp:1112)"
	)
	var classified: Dictionary = _classify_console_lines(sample)
	assert_eq(classified["errors"], [])
	assert_eq(classified["warnings"], [], "the documented CurrentGameState-uninitialized fallback warning must be allowlisted, not flagged")


func test_an_unrelated_warning_is_still_flagged() -> void:
	var sample: String = "WARNING: some unrelated future regression happened here"
	var classified: Dictionary = _classify_console_lines(sample)
	assert_eq(classified["errors"], [])
	assert_eq(classified["warnings"], [sample], "an unrelated WARNING line must NOT be caught by the narrow UID allowlist")


func test_an_error_line_is_always_flagged_even_alongside_allowlisted_warnings() -> void:
	var sample: String = (
		"WARNING: res://data/encounters/prologue_encounter.tres:3 - "
		+ "ext_resource, invalid UID: uid://encrsc1a2b3cd - using text "
		+ "path instead: res://data/encounters/encounter_resource.gd\n"
		+ "ERROR: something actually went wrong during boot"
	)
	var classified: Dictionary = _classify_console_lines(sample)
	assert_eq(classified["errors"], ["ERROR: something actually went wrong during boot"])
	assert_eq(classified["warnings"], [])


func test_info_and_debug_lines_are_never_flagged() -> void:
	var sample: String = (
		"INFO: Hykaen MainScene booted into the prologue encounter "
		+ "(interactive) -- current_actor=Titus round_over=false\n"
		+ "DEBUG: viewport_centering centering_offset=(576, 324)"
	)
	var classified: Dictionary = _classify_console_lines(sample)
	assert_eq(classified["errors"], [])
	assert_eq(classified["warnings"], [])


func test_no_console_output_at_all_classifies_as_zero_errors_and_warnings() -> void:
	var classified: Dictionary = _classify_console_lines("")
	assert_eq(classified["errors"], [])
	assert_eq(classified["warnings"], [])


# ══════════════════════════════════════════════════════════════════════════
# test_criteria: "MainScene boots headless with zero error/warning lines to
# stdout/stderr."
# ══════════════════════════════════════════════════════════════════════════

func test_bare_headless_boot_exits_successfully() -> void:
	var godot_bin: String = _find_godot_binary()
	if godot_bin == "":
		pending("godot binary not found on PATH -- skipping real-subprocess headless boot check")
		return

	var result: Dictionary = _run_bare_headless_boot(godot_bin)
	assert_eq(
		result["exit_code"], 0,
		"a real `godot --headless` boot of the shipped project must exit 0 (no crash/unhandled fatal error); output:\n%s" % result["output"]
	)


func test_bare_headless_boot_produces_zero_error_level_console_output() -> void:
	var godot_bin: String = _find_godot_binary()
	if godot_bin == "":
		pending("godot binary not found on PATH -- skipping real-subprocess headless boot check")
		return

	var result: Dictionary = _run_bare_headless_boot(godot_bin)
	var classified: Dictionary = _classify_console_lines(result["output"])
	assert_eq(
		classified["errors"], [],
		"booting the real res://scenes/TitleScreen.tscn composition root headlessly (FEAT-337 / DEF-001) must produce ZERO ERROR-level console lines; full output:\n%s" % result["output"]
	)


func test_bare_headless_boot_produces_zero_unallowlisted_warning_level_console_output() -> void:
	var godot_bin: String = _find_godot_binary()
	if godot_bin == "":
		pending("godot binary not found on PATH -- skipping real-subprocess headless boot check")
		return

	var result: Dictionary = _run_bare_headless_boot(godot_bin)
	var classified: Dictionary = _classify_console_lines(result["output"])
	assert_eq(
		classified["warnings"], [],
		"booting the real res://scenes/TitleScreen.tscn composition root headlessly (FEAT-337 / DEF-001) must produce ZERO WARNING-level console lines beyond the one documented, "
		+ "pre-existing, out-of-scope resource-UID warning shape; full output:\n%s" % result["output"]
	)


func test_bare_headless_boot_actually_reaches_the_interactive_prologue_encounter() -> void:
	var godot_bin: String = _find_godot_binary()
	if godot_bin == "":
		pending("godot binary not found on PATH -- skipping real-subprocess headless boot check")
		return

	var result: Dictionary = _run_bare_headless_boot(godot_bin)
	assert_true(
		result["output"].contains(MAIN_SCENE_BOOT_MARKER),
		"the real TitleScreen.tscn composition root (FEAT-337 / DEF-001: project.godot's run/main_scene) must actually reach its interactive, input-awaiting boot state within "
		+ "%d frames -- its own boot-confirmation log line was not observed; full output:\n%s" % [_QUIT_AFTER_FRAMES, result["output"]]
	)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria: "Zero flakiness observed across multiple consecutive CI
# runs at the pinned seed."
# ══════════════════════════════════════════════════════════════════════════

func test_multiple_consecutive_pinned_seed_headless_boots_all_produce_zero_error_and_warning_output() -> void:
	var godot_bin: String = _find_godot_binary()
	if godot_bin == "":
		pending("godot binary not found on PATH -- skipping real-subprocess headless boot check")
		return

	for i in range(_REPEATED_RUN_COUNT):
		var result: Dictionary = _run_bare_headless_boot(godot_bin)
		assert_eq(result["exit_code"], 0, "run %d: a real headless boot at the pinned seed must exit 0; output:\n%s" % [i, result["output"]])

		var classified: Dictionary = _classify_console_lines(result["output"])
		assert_eq(classified["errors"], [], "run %d: zero ERROR-level console lines must be produced; output:\n%s" % [i, result["output"]])
		assert_eq(
			classified["warnings"], [],
			"run %d: zero unallowlisted WARNING-level console lines must be produced; output:\n%s" % [i, result["output"]]
		)
		assert_true(
			result["output"].contains(MAIN_SCENE_BOOT_MARKER),
			"run %d: the real TitleScreen.tscn composition root (FEAT-337 / DEF-001) must reach its interactive boot state every single consecutive run" % i
		)
