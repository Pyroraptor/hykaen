extends GutTest
## tests/infrastructure/test_single_instance_invariant.gd — FEAT-003
## (US-003 / FR-007, ADR-006 "single-instance invariant"), depends on
## FEAT-001 (US-001, iteration-D UI consolidation) and FEAT-002.
##
## Headless regression guard: proves the REAL, shipped res://MainScene.tscn
## composition root, once booted, contains EXACTLY ONE instance of each core
## UI element -- HexGridView, InitiativeView, ResultScreenView, and (per
## living combatant) a StatusPanelView row -- in its live scene tree.
##
## This is the counting complement to
## tests/infrastructure/test_mainscene_no_battlefield_refs.gd (a static,
## grep-style guard banning specific removed identifiers) and
## tests/infrastructure/test_mainscene_headless_boot.gd (a runtime guard
## asserting the kept stack is wired non-null): neither of those actually
## COUNTS instances, so a future regression that re-introduces a SECOND
## HexGridView/StatusPanelView/InitiativeView/ResultScreenView node (the
## "two-stack bug" this iteration's ADR-006 exists to prevent recurrence
## of) would not be caught by either -- only an explicit count assertion
## catches that class of bug. This test is the CI-wired regression guard
## fulfilling that role (FEAT-003 / US-003 / FR-007): it fails loudly
## (a non-zero GUT/CI exit) the moment any of the counts below deviates
## from exactly 1 (or, for StatusPanelView rows, from exactly one row per
## living combatant).
##
## StatusPanelView itself is architecturally a SINGLE Control node
## (presentation/status_panel_view.gd) that renders one row/Label per
## combatant internally (see its `_rows`/`_labels` Dictionaries, keyed by
## combatant_id) rather than one StatusPanelView node per combatant --
## so "exactly 1 StatusPanelView instance per living combatant" is checked
## as: exactly one StatusPanelView NODE in the tree, AND that node's row
## count (get_row_count()) equals the number of living combatants loaded
## from the prologue encounter fixture -- catching BOTH a duplicated
## StatusPanelView node AND duplicated/missing per-combatant rows within
## the single kept node (either of which would silently re-introduce the
## same "two-stack" class of bug for the status readout specifically).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


func test_mainscene_tree_contains_exactly_one_hex_grid_view_instance() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var matches: Array = []
	_collect_nodes_of_class(instance, "HexGridView", matches)

	assert_eq(
		matches.size(), 1,
		"MainScene's booted tree must contain EXACTLY 1 HexGridView instance (FEAT-003 / US-003 / "
		+ "ADR-006 single-instance invariant); found %d: %s" % [matches.size(), matches]
	)


func test_mainscene_tree_contains_exactly_one_status_panel_view_instance() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var matches: Array = []
	_collect_nodes_of_class(instance, "StatusPanelView", matches)

	assert_eq(
		matches.size(), 1,
		"MainScene's booted tree must contain EXACTLY 1 StatusPanelView instance (FEAT-003 / US-003 / "
		+ "ADR-006 single-instance invariant); found %d: %s" % [matches.size(), matches]
	)


## StatusPanelView renders one row PER LIVING COMBATANT inside that single
## node -- never a duplicated node per combatant. Asserts the row count
## exactly equals the number of living (hp_current > 0) combatants
## MainScene loaded from the prologue encounter fixture (its `_party` +
## `_enemies` fields), so neither a duplicated nor a missing per-combatant
## row can slip through unnoticed.
func test_status_panel_view_has_exactly_one_row_per_living_combatant() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	assert_not_null(instance.status_panel_view, "MainScene.status_panel_view must be wired (FEAT-001)")
	if instance.status_panel_view == null:
		return

	var living_combatant_count: int = _count_living(instance._party) + _count_living(instance._enemies)

	assert_eq(
		instance.status_panel_view.get_row_count(), living_combatant_count,
		(
			"StatusPanelView must render EXACTLY 1 row per living combatant -- no per-instance duplication "
			+ "(FEAT-003 / US-003 / ADR-006 single-instance invariant); expected %d living combatants, "
			+ "found %d rows"
		) % [living_combatant_count, instance.status_panel_view.get_row_count()]
	)


func test_mainscene_tree_contains_exactly_one_initiative_view_instance() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var matches: Array = []
	_collect_nodes_of_class(instance, "InitiativeView", matches)

	assert_eq(
		matches.size(), 1,
		"MainScene's booted tree must contain EXACTLY 1 InitiativeView instance (FEAT-003 / US-003 / "
		+ "ADR-006 single-instance invariant); found %d: %s" % [matches.size(), matches]
	)


func test_mainscene_tree_contains_exactly_one_result_screen_view_instance() -> void:
	var instance = await _boot_main_scene()
	if instance == null:
		return

	var matches: Array = []
	_collect_nodes_of_class(instance, "ResultScreenView", matches)

	assert_eq(
		matches.size(), 1,
		"MainScene's booted tree must contain EXACTLY 1 ResultScreenView instance (FEAT-003 / US-003 / "
		+ "ADR-006 single-instance invariant); found %d: %s" % [matches.size(), matches]
	)


# ── Internal helpers ─────────────────────────────────────────────────────

## _boot_main_scene() -> Node — loads and instantiates the REAL
## res://MainScene.tscn, adds it to the tree (auto-freed after the test),
## and awaits one process frame so _ready() has fully run -- mirroring
## tests/infrastructure/test_mainscene_headless_boot.gd's established
## boot convention.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return null

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup")
	if instance == null:
		return null

	add_child_autofree(instance)
	await get_tree().process_frame
	return instance


## _collect_nodes_of_class(node, class_name_string, out_matches) -> void —
## recursively walks `node`'s subtree (including `node` itself) and appends
## the String path of every descendant whose script declares
## `class_name == class_name_string` (checked via each node's script
## resource's "class_name" global, so this matches the SAME class_name
## declarations presentation/*.gd's `class_name HexGridView` etc. lines
## establish, not merely a node-name string match, which would be trivially
## fooled by renaming a node in the .tscn without changing its script).
func _collect_nodes_of_class(node: Node, class_name_string: String, out_matches: Array) -> void:
	if _node_is_of_class(node, class_name_string):
		out_matches.append(str(node.get_path()))
	for child in node.get_children():
		_collect_nodes_of_class(child, class_name_string, out_matches)


func _node_is_of_class(node: Node, class_name_string: String) -> bool:
	var script = node.get_script()
	if script == null:
		return false
	if not (script is Script):
		return false
	return String(script.get_global_name()) == class_name_string


## _count_living(combatants) -> int — mirrors MainScene.gd's own
## `_living_combatants()` filter (hp_current > 0), applied here read-only
## for test verification.
func _count_living(combatants: Array) -> int:
	var count: int = 0
	for c in combatants:
		if c.hp_current > 0:
			count += 1
	return count
