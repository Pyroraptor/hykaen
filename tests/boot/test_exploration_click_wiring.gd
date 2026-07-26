extends GutTest
## tests/boot/test_exploration_click_wiring.gd — FEAT-324 (US-008, resolves
## DEF-001).
##
## Boot-real proof that the REAL, shipped res://MainScene.tscn composition
## root's `_boot_exploration_mode()`-equivalent boot step (MainScene._ready())
## now routes `hex_grid_view.hex_clicked` to the FEAT-007/008/009
## pathfinding-driven, animated `ExplorationModeController.
## _on_exploration_hex_clicked` handler -- NEVER to a pre-iteration,
## adjacency-only, non-animated MainScene-owned handler (the DEF-001 defect
## this feature resolves: MainScene._on_exploration_hex_clicked used to be
## wired in parallel with -- and shadow -- the real, pathfinding-aware
## handler that already lived on `instance._exploration`).
##
## Unlike every earlier boot suite's "call the handler directly" convention
## (tests/boot/test_exploration_pathfinding.gd et al., which bypass
## hex_grid_view.hex_clicked entirely because it used to be wired to the
## dead MainScene handler), this suite's whole purpose is to inspect the
## LIVE signal connection list itself -- proving the real click event path
## reaches the real handler, not just that the handler works when invoked
## directly.
##
## test_criteria covered here:
##   - hex_grid_view.hex_clicked.get_connections() contains EXACTLY ONE
##     connection, whose target is instance._exploration (the
##     ExplorationModeController instance) and whose method is
##     "_on_exploration_hex_clicked".
##   - MainScene.gd no longer declares `_on_exploration_hex_clicked` as a
##     symbol at all (source-scan assertion) -- so it cannot be silently
##     reintroduced or accidentally left wired in parallel with the real
##     handler ever again.
##   - the FEAT-007 hover wiring (hex_grid_view.hex_hovered ->
##     ExplorationModeController._on_hex_hovered) remains connected and is
##     completely unaffected by this feature's click-wiring change.

const MAIN_SCENE_PATH: String = "res://MainScene.gd"
const MAIN_SCENE_SCENE_PATH: String = "res://MainScene.tscn"
const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/boot/test_boot_exploration_mode.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# hex_grid_view.hex_clicked carries EXACTLY ONE live connection, targeting
# ExplorationModeController._on_exploration_hex_clicked.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_clicked_has_exactly_one_connection_targeting_exploration_mode_controller() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.hex_grid_view, "MainScene must wire a real $HexGridView")
	assert_not_null(instance._exploration, "MainScene must construct a real ExplorationModeController instance")
	assert_true(
		instance._exploration is ExplorationModeControllerClass,
		"instance._exploration must be a real ExplorationModeController instance"
	)

	var connections: Array = instance.hex_grid_view.hex_clicked.get_connections()
	assert_eq(
		connections.size(), 1,
		"hex_grid_view.hex_clicked must carry EXACTLY ONE live connection after boot -- no parallel/dead-handler wiring"
	)

	var callable: Callable = connections[0]["callable"]
	assert_eq(
		callable.get_object(), instance._exploration,
		"hex_clicked's sole connection must target the ExplorationModeController instance (instance._exploration), not MainScene itself"
	)
	assert_eq(
		callable.get_method(), "_on_exploration_hex_clicked",
		"hex_clicked's sole connection must invoke ExplorationModeController._on_exploration_hex_clicked"
	)
	assert_true(
		instance.hex_grid_view.hex_clicked.is_connected(Callable(instance._exploration, "_on_exploration_hex_clicked")),
		"hex_clicked must be genuinely connected to instance._exploration._on_exploration_hex_clicked"
	)


# ══════════════════════════════════════════════════════════════════════════
# MainScene.gd no longer declares _on_exploration_hex_clicked as a symbol at
# all -- it cannot be silently reintroduced or left wired in parallel.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_source_no_longer_declares_on_exploration_hex_clicked() -> void:
	var file := FileAccess.open(MAIN_SCENE_PATH, FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	# A source-scan for the DECLARATION only (never for the method-name
	## string literal MainScene.gd legitimately still uses to build a
	## Callable targeting ExplorationModeController's own method, e.g.
	## `Callable(_exploration, "_on_exploration_hex_clicked")` --
	## that reference is exactly this feature's intended wiring, not the
	## dead handler this criterion guards against).
	assert_true(
		content.find("func _on_exploration_hex_clicked") == -1,
		"MainScene.gd must not declare its OWN _on_exploration_hex_clicked function -- the dead, pre-iteration " +
		"adjacency-only handler must be fully deleted, not merely left unwired, so it cannot be silently reintroduced " +
		"or accidentally left wired in parallel with ExplorationModeController's own real handler"
	)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-007's hex_hovered wiring remains connected and unaffected.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_hovered_wiring_to_exploration_mode_controller_remains_connected() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(
		instance.hex_grid_view.hex_hovered.is_connected(Callable(instance._exploration, "_on_hex_hovered")),
		"hex_grid_view.hex_hovered must remain connected to ExplorationModeController._on_hex_hovered (FEAT-007), unaffected by this feature"
	)

	var hover_connections: Array = instance.hex_grid_view.hex_hovered.get_connections()
	assert_eq(
		hover_connections.size(), 1,
		"hex_hovered must carry exactly one connection -- this feature only changes hex_clicked wiring"
	)
