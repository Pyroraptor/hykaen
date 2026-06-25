## HeadlessRunner — autoload that intercepts --gut-run-all from the command line.
##
## When godot runs with the --gut-run-all user argument, this singleton
## loads .gutconfig.json, instantiates GutRunner, and delegates to GUT's
## built-in exit-on-done logic so the process exits 0 (all pass) or 1
## (any failure).  When the flag is absent the singleton does nothing,
## allowing the normal game scene to load.
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

	var runner = GutRunner.instantiate()
	runner.set_gut_config(config)
	get_tree().root.add_child(runner)
	# run_tests() is safe here: add_child() above has fully initialised the runner
	# (including @onready vars) because the tree is already running at this point.
	runner.run_tests()
