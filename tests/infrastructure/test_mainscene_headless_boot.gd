extends GutTest
## tests/infrastructure/test_mainscene_headless_boot.gd — FEAT-001
## (US-001 / FR-005, iteration D "UI Consolidation + Movement UX").
##
## Runtime complement to tests/infrastructure/test_mainscene_no_battlefield_refs.gd's
## static/grep-style guard: proves the REAL, shipped res://MainScene.tscn
## composition root
##   1. boots headlessly with zero compile/runtime errors after the
##      duplicate scenes/battlefield/* UI stack was removed (every
##      composition-root field this project's established convention
##      treats as the headless proxy for "zero unhandled errors on boot" --
##      see tests/gut/test_smoke_boot.gd / tests/smoke/
##      test_main_scene_headless_boot.gd -- resolves non-null), and
##   2. instantiates NO node anywhere in its tree whose script belongs to
##      the removed res://scenes/battlefield/ package, and
##   3. carries NO signal connection anywhere in its tree whose target
##      object's script belongs to the removed res://scenes/battlefield/
##      package (an "orphaned" connection pointing at a removed script) --
##      the runtime proof that removing the node instances also removed
##      every piece of signal wiring that referenced them (P0-2's "leave NO
##      dangling preload/instantiate of a removed scene").

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## The removed package every node/connection below must NOT resolve into.
const _REMOVED_SCRIPT_PREFIX: String = "res://scenes/battlefield/"


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — headless boot of MainScene completes with zero compile/
# runtime errors: mirrors this project's established proxy (tests/gut/
# test_smoke_boot.gd, tests/smoke/test_main_scene_headless_boot.gd) of
# asserting every composition-root field is non-null after a real frame has
# elapsed -- each field is only left null when an internal push_error()
# fail-fast path was hit.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_boots_headlessly_with_zero_errors_after_battlefield_removal() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene (FEAT-001)")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup (FEAT-001)")
	if instance == null:
		return

	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.encounter_repository, "MainScene.encounter_repository must be non-null after first frame post-removal (FEAT-001)")
	assert_not_null(instance.random_port, "MainScene.random_port must be non-null after first frame post-removal (FEAT-001)")
	assert_not_null(instance.event_sink, "MainScene.event_sink must be non-null after first frame post-removal (FEAT-001)")
	assert_not_null(instance.encounter, "MainScene.encounter must be non-null after first frame post-removal (FEAT-001)")
	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after first frame post-removal (FEAT-001)")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")

	# The kept, single presentation/* stack must still be fully wired.
	assert_not_null(instance.hex_grid_view, "MainScene.hex_grid_view must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.status_panel_view, "MainScene.status_panel_view must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.initiative_view, "MainScene.initiative_view must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.event_log_view, "MainScene.event_log_view must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance._verb_registry, "MainScene._verb_registry must remain wired -- FEAT-006 (US-006) drives Strike solely through it, no dedicated strike_action_control node remains")
	assert_not_null(instance.end_turn_control, "MainScene.end_turn_control must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.result_screen_view, "MainScene.result_screen_view must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.turn_controller, "MainScene.turn_controller must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.movement_input_controller, "MainScene.movement_input_controller must remain wired (the kept stack, FEAT-001)")
	assert_not_null(instance.verb_bar_view, "MainScene.verb_bar_view must be wired to a real $VerbBarView node in MainScene.tscn (FEAT-004 / US-004)")
	if instance.verb_bar_view != null:
		assert_gt(instance.verb_bar_view.get_button_count(), 0, "MainScene.verb_bar_view must render at least one verb button after boot (FEAT-004 / US-004)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — no node anywhere in the booted MainScene tree is an instance
# of a script from the removed res://scenes/battlefield/ package.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_tree_contains_no_node_from_the_removed_battlefield_package() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame

	var offenders: Array = []
	_collect_battlefield_script_nodes(instance, offenders)

	assert_eq(
		offenders.size(), 0,
		"MainScene's tree must contain no node whose script belongs to the removed "
		+ "res://scenes/battlefield/ package (FEAT-001 / US-001); found: %s" % [offenders]
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — no orphaned signal connections remain: enumerate every
# signal connection on every node in the booted MainScene tree and assert
# none targets an object whose script belongs to the removed
# res://scenes/battlefield/ package.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_tree_has_no_signal_connections_targeting_removed_battlefield_scripts() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame

	var offenders: Array = []
	_collect_connections_targeting_battlefield(instance, offenders)

	assert_eq(
		offenders.size(), 0,
		"MainScene's tree must carry no signal connection whose target object's script belongs to the "
		+ "removed res://scenes/battlefield/ package -- a dangling connection to a removed component "
		+ "(FEAT-001 / US-001); found: %s" % [offenders]
	)


# ── Internal helpers ─────────────────────────────────────────────────────

func _is_removed_battlefield_script(script) -> bool:
	if script == null:
		return false
	if not (script is Script):
		return false
	var path: String = script.resource_path
	return path != "" and path.begins_with(_REMOVED_SCRIPT_PREFIX)


func _collect_battlefield_script_nodes(node: Node, out_offenders: Array) -> void:
	if _is_removed_battlefield_script(node.get_script()):
		out_offenders.append(str(node.get_path()))
	for child in node.get_children():
		_collect_battlefield_script_nodes(child, out_offenders)


func _collect_connections_targeting_battlefield(node: Node, out_offenders: Array) -> void:
	for sig in node.get_signal_list():
		var signal_name: String = sig.get("name", "")
		if signal_name == "":
			continue
		for connection in node.get_signal_connection_list(signal_name):
			var callable: Callable = connection.get("callable")
			if callable == null:
				continue
			var target_object = callable.get_object()
			if target_object == null:
				continue
			if _is_removed_battlefield_script(target_object.get_script()):
				out_offenders.append(
					"%s.%s -> %s" % [str(node.get_path()), signal_name, target_object.get_script().resource_path]
				)
	for child in node.get_children():
		_collect_connections_targeting_battlefield(child, out_offenders)
