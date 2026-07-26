extends GutTest
## tests/boot/test_title_screen_boot_performance.gd — FEAT-008 (US-006;
## NFR-005).
##
## Proves scenes/TitleScreen.tscn + presentation/title_screen.gd loads fast
## and never eagerly loads/preloads the (much heavier) MainScene.tscn
## composition root at parse/boot time:
##
##   1. Boot-to-interactive timing: instantiates TitleScreen.tscn and adds
##      it to the tree, sampled across multiple runs and averaged (mirrors
##      this project's core/sim/simulator.gd "many samples, tolerance
##      window" convention rather than a single, flake-prone sample) --
##      asserted against a deliberately GENEROUS threshold, well above
##      NFR-005's nominal "loads in under one second" target, so ordinary
##      CI-machine variance never trips this gate. This test exists to
##      catch a gross regression (e.g. an accidentally-added synchronous
##      MainScene.tscn load inside _ready()), not to enforce a tight SLA.
##   2. Source-scan (mirrors tests/integration/test_auto_save_on_combat_won.gd's
##      "extract one function's body, inspect its content" convention):
##      TitleScreen.gd's _ready() function body contains no
##      load()/preload() call, and in particular never references
##      MainScene.tscn/MainScene at all -- the composition root is only
##      ever resolved lazily, inside the transition seam
##      (_transition_to_main_scene()), at the moment a button is actually
##      pressed.

const TITLE_SCREEN_PATH: String = "res://scenes/TitleScreen.tscn"
const TITLE_SCREEN_SCRIPT_PATH: String = "res://presentation/title_screen.gd"

## SAMPLE_COUNT / AVERAGE_THRESHOLD_MSEC — see file doc: multiple samples
## averaged against a deliberately generous threshold so ordinary CI
## variance can never flake this gate; it exists only to catch a gross
## regression.
const SAMPLE_COUNT: int = 5
const AVERAGE_THRESHOLD_MSEC: float = 3000.0


func _instantiate_title_screen():
	var packed: PackedScene = ResourceLoader.load(TITLE_SCREEN_PATH)
	assert_not_null(packed, "TitleScreen.tscn must load as a PackedScene")
	return packed.instantiate()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — average boot-to-interactive time across multiple samples.
# ══════════════════════════════════════════════════════════════════════════

func test_average_boot_to_interactive_time_across_samples_is_within_generous_threshold() -> void:
	var total_msec: int = 0

	for i in range(SAMPLE_COUNT):
		var start_msec: int = Time.get_ticks_msec()

		var instance = _instantiate_title_screen()
		add_child_autofree(instance)
		await get_tree().process_frame

		var elapsed_msec: int = Time.get_ticks_msec() - start_msec
		total_msec += elapsed_msec

	var average_msec: float = float(total_msec) / float(SAMPLE_COUNT)

	assert_true(
		average_msec < AVERAGE_THRESHOLD_MSEC,
		(
			"TitleScreen must load to interactive well under a generous %.0fms average across %d samples (measured average: %.1fms) -- a large regression here likely means MainScene.tscn (or similarly heavy work) is being loaded eagerly"
			% [AVERAGE_THRESHOLD_MSEC, SAMPLE_COUNT, average_msec]
		)
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — _ready() never load()/preload()s MainScene.tscn (NFR-005).
# ══════════════════════════════════════════════════════════════════════════

func _read_title_screen_source() -> String:
	var file := FileAccess.open(TITLE_SCREEN_SCRIPT_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/title_screen.gd must be readable")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _extract_function_body(content: String, function_signature_prefix: String) -> String:
	var body_start: int = content.find(function_signature_prefix)
	assert_true(body_start >= 0, "TitleScreen.gd must define a function starting with '%s'" % function_signature_prefix)
	if body_start < 0:
		return ""

	var next_func: int = content.find("\nfunc ", body_start + 1)
	if next_func < 0:
		next_func = content.length()
	return content.substr(body_start, next_func - body_start)


func test_ready_never_loads_or_preloads_main_scene() -> void:
	var content: String = _read_title_screen_source()
	var ready_body: String = _extract_function_body(content, "func _ready(")

	assert_false(
		ready_body.contains("preload("),
		"_ready() must never preload() anything -- MainScene.tscn in particular must only be resolved lazily, at transition time (NFR-005)"
	)
	assert_false(
		ready_body.contains("load("),
		"_ready() must never load() anything eagerly (NFR-005) -- in particular, MainScene.tscn must only be resolved lazily inside the transition seam, once a button is actually pressed"
	)
	assert_false(
		ready_body.contains("MainScene"),
		"_ready() must never reference MainScene.tscn/MainScene at all -- the composition root is resolved lazily, only inside _transition_to_main_scene()"
	)
