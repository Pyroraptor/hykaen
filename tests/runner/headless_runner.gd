## HeadlessRunner — autoload that intercepts --gut-run-all from the command line.
##
## When godot runs with the --gut-run-all user argument, this singleton
## loads .gutconfig.json, instantiates GutRunner, and delegates to GUT's
## built-in exit-on-done logic. When the flag is absent the singleton does
## nothing, allowing the normal game scene to load.
##
## FEAT-348 (DEF-003, US-006): the process exit code is no longer GUT's raw
## "any failure -> exit 1" rule. This runner also wires
## ci/gate_exit_policy.gd in as GUT's `post_run_script` hook, which
## overrides the exit code to 0 iff the actual failing-test set produced by
## this run exactly matches the ci/accepted_known_failures.json manifest
## (no new/regressed failures, and no manifest entry that unexpectedly
## started passing) — and non-zero otherwise. See
## ci/gate_exit_policy.gd's module doc comment for the full rationale.
##
## Implementation note: _ready() is called while the scene tree is still
## initialising autoloads, so add_child() would fail with "Parent node is
## busy setting up children".  Deferring the entire setup to the next
## idle frame (call_deferred) avoids this race and lets @onready variables
## inside GutRunner initialise properly before run_tests() is called.
extends Node

func _ready() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not ("--gut-run-all" in user_args):
		return
	# Defer so the scene tree finishes initialising before we add children.
	call_deferred("_launch_gut")


func _launch_gut() -> void:
	var GutConfig = load("res://addons/gut/gut_config.gd")
	var GutRunner = load("res://addons/gut/gui/GutRunner.tscn")

	var config = GutConfig.new()
	# Load settings from .gutconfig.json (dirs, include_subdirs, should_exit, etc.)
	config.load_options("res://.gutconfig.json")
	# Ensure the process exits when tests finish (required for CI exit-code forwarding)
	config.options.should_exit = true
	# FEAT-348 (DEF-003, US-006): wire GUT's own "post_run_script" extension
	# point (addons/gut/hook_script.gd / GutRunner._handle_quit) to
	# ci/gate_exit_policy.gd so the REAL process exit code is decided by the
	# accepted-known-failures manifest comparison -- exit 0 iff the actual
	# failing-test set returned by this run exactly matches
	# ci/accepted_known_failures.json -- rather than by GUT's default "any
	# failure -> exit 1" rule. Without this, "N accepted known failures" and
	# "exit code 0" could never both hold simultaneously, which is the exact
	# contradiction DEF-003 identified in FR-006's literal acceptance
	# criteria.
	config.options.post_run_script = "res://ci/gate_exit_policy.gd"

	var runner = GutRunner.instantiate()
	runner.set_gut_config(config)
	get_tree().root.add_child(runner)
	# run_tests() is safe here: add_child() above has fully initialised the runner
	# (including @onready vars) because the tree is already running at this point.
	runner.run_tests()
