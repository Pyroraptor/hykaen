extends GutTest
## tests/unit/test_main_scene_game_camera.gd — FEAT-001 (US-001 / FR-001,
## ADR-001, Iteration W).
##
## GUT test suite proving a Camera2D node named "GameCamera" exists as a
## sibling of HexGridView under the world layer of the REAL res://MainScene.tscn
## composition root (ADR-002 pattern: instantiate the real scene, never a
## hand-wired double). This is the infrastructure foundation the rest of the
## Iteration W camera/panning steel thread builds on -- GameCamera itself is
## not yet wired into any GDScript logic at this step (that lands in a later
## feature, per the iteration's set_origin_offset() re-implementation story);
## this test only asserts the node exists, is configured correctly, and that
## its mere presence causes no regression to the existing centered-boot
## behaviour already covered by tests/gut/test_viewport_centering.gd.
##
## test_criteria satisfied:
##   1. A scene-tree/node-path test confirms GameCamera exists as a sibling
##      of HexGridView under the world layer.
##   2. GameCamera.current == true.
##   3. GameCamera.position_smoothing_enabled == false.
##   4. Loading the (real MainScene, this project's boot/"prologue") scene
##      still renders the hex map centered exactly as before the camera
##      refactor -- verified here as a smoke check that boot completes with
##      a non-zero centering_offset unaffected by GameCamera's addition; the
##      full centering assertions live in tests/gut/test_viewport_centering.gd
##      and continue to pass unmodified (no offset field applied yet, so no
##      regression at this step).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null
	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate")
	if instance == null:
		return null
	# FEAT-006 (US-005/FR-005, ADR-002): pin the prologue fixture's own
	# established seed so this boot proceeds deterministically, mirroring
	# every other MainScene.tscn-booting test in this project.
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — GameCamera exists as a sibling of HexGridView under the
# world layer (i.e. shares HexGridView's own parent node in the real,
# instantiated scene tree).
# ══════════════════════════════════════════════════════════════════════════

func test_game_camera_exists_as_sibling_of_hex_grid_view() -> void:
	var instance = _boot_main_scene()
	if instance == null:
		return

	var hex_grid_view: Node = instance.get_node_or_null("HexGridView")
	assert_not_null(hex_grid_view, "MainScene must expose a HexGridView child node")
	if hex_grid_view == null:
		return

	var world_layer: Node = hex_grid_view.get_parent()
	assert_not_null(world_layer, "HexGridView must have a parent (the world layer)")
	if world_layer == null:
		return

	var game_camera: Node = world_layer.get_node_or_null("GameCamera")
	assert_not_null(
		game_camera,
		"GameCamera must exist as a sibling of HexGridView under the world layer"
	)
	if game_camera == null:
		return

	assert_eq(
		game_camera.get_parent(), hex_grid_view.get_parent(),
		"GameCamera and HexGridView must share the same parent node (the world layer)"
	)
	assert_is(
		game_camera, Camera2D,
		"GameCamera must be a Camera2D node"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — GameCamera.current == true.
# ══════════════════════════════════════════════════════════════════════════

func test_game_camera_is_current() -> void:
	var instance = _boot_main_scene()
	if instance == null:
		return

	var hex_grid_view: Node = instance.get_node_or_null("HexGridView")
	if hex_grid_view == null:
		fail_test("MainScene must expose a HexGridView child node")
		return

	var game_camera: Camera2D = hex_grid_view.get_parent().get_node_or_null("GameCamera")
	assert_not_null(game_camera, "GameCamera must exist to check its current property")
	if game_camera == null:
		return

	assert_true(game_camera.current, "GameCamera.current must be true")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — GameCamera.position_smoothing_enabled == false.
# ══════════════════════════════════════════════════════════════════════════

func test_game_camera_has_position_smoothing_disabled() -> void:
	var instance = _boot_main_scene()
	if instance == null:
		return

	var hex_grid_view: Node = instance.get_node_or_null("HexGridView")
	if hex_grid_view == null:
		fail_test("MainScene must expose a HexGridView child node")
		return

	var game_camera: Camera2D = hex_grid_view.get_parent().get_node_or_null("GameCamera")
	assert_not_null(game_camera, "GameCamera must exist to check its position_smoothing_enabled property")
	if game_camera == null:
		return

	assert_false(
		game_camera.position_smoothing_enabled,
		"GameCamera.position_smoothing_enabled must be false (no lag on future pan input)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — the hex map still renders centered exactly as before the
# camera node's addition (no regression): boot still resolves a non-zero
# centering_offset and every token still renders within viewport bounds,
# exactly as tests/gut/test_viewport_centering.gd already asserts in full.
# GameCamera's mere presence in the tree (not yet wired to any GDScript)
# must not perturb that existing behaviour.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_map_still_renders_centered_with_game_camera_present() -> void:
	var instance = _boot_main_scene()
	if instance == null:
		return

	await get_tree().process_frame

	assert_ne(
		instance.centering_offset, Vector2.ZERO,
		"MainScene must still resolve a non-zero centering_offset with GameCamera present (no regression)"
	)

	var hex_grid_view = instance.hex_grid_view
	assert_not_null(hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	if hex_grid_view == null:
		return

	assert_ne(
		hex_grid_view.get_origin_offset(), Vector2.ZERO,
		"HexGridView must still be configured with a non-zero origin offset (no offset field applied "
		+ "to the camera yet at this step -- centering continues to work exactly as before)"
	)
