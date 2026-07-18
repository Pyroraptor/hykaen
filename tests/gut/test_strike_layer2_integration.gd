extends GutTest
## tests/gut/test_strike_layer2_integration.gd — FEAT-008 (US-008 / FR-003;
## ADR-002).
##
## Integration-test complement to tests/pytest/test_verb_registry.py's
## TestStrikeEnterSelectionEnemyOnlyTargeting (the Python-level pin of the
## same "only in-reach enemy target ids" contract). This suite boots the
## REAL, shipped res://MainScene.tscn composition root headless (mirroring
## tests/integration/test_movement_affordance_integration.gd's/tests/
## infrastructure/test_presentation_stack_wiring.gd's
## `_boot_main_scene_with_seed()` fixture) with NO stub/mock standing in for
## HexGridView, `_verb_registry`, resolve_action_use_case, or the new
## presentation/selection_overlay.gd SelectionOverlay -- proving Strike's
## Layer 2 (target highlight -> click -> resolve) works end-to-end through
## the exact objects a real player drives.
##
## test_criteria satisfied:
##   1. test_strike_enter_selection_highlights_only_in_reach_enemy_targets()
##      -- the GDScript-runtime complement to the Python unit test criterion.
##   2. test_clicking_a_highlighted_target_resolves_through_select_target_and_updates_board_and_status_bar()
##   3. test_clicking_a_non_highlighted_out_of_reach_location_produces_no_resolution()
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not
##      this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass       = preload("res://presentation/hex_grid_view.gd")
const SelectionOverlayClass  = preload("res://presentation/selection_overlay.gd")
const HexCoordClass          = preload("res://core/geometry/hex_coord.gd")


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/integration/test_movement_affordance_integration.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _far_unoccupied_hex(instance) -> HexCoord -- a hex clearly outside every
## living combatant's occupied hex and outside every currently highlighted
## candidate, used to simulate an out-of-reach click.
func _far_unoccupied_hex(instance):
	var occupied: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var hex_coord = combatant.hex_coord
		if hex_coord != null:
			occupied["%d,%d" % [hex_coord.q, hex_coord.r]] = true

	for q in range(4, 6):
		for r in range(4, 6):
			var key: String = "%d,%d" % [q, r]
			if not occupied.has(key):
				return HexCoordClass.new(q, r)
	return HexCoordClass.new(99, 99)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — pressing STRIKE surfaces (and SelectionOverlay highlights)
# EXACTLY the in-reach enemy target ids -- no ally, no out-of-reach enemy.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_enter_selection_highlights_only_in_reach_enemy_targets() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		is_instance_of(instance.selection_overlay, SelectionOverlayClass),
		"MainScene must wire the REAL presentation/selection_overlay.gd SelectionOverlay -- no stub/mock"
	)
	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"fixture assumption: the prologue's first actor has at least one in-reach target at seed=42"
	)

	var expected_target_ids: Array = instance._strike_reachable_target_ids()
	assert_true(expected_target_ids.size() > 0, "sanity check: at least one enemy is in reach at boot")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var candidate_targets: Array = selection.get("candidate_targets", [])

	assert_eq(
		candidate_targets, expected_target_ids,
		"Strike's Layer 2 selection must surface EXACTLY the in-reach enemy target ids -- no more, no less"
	)

	# SelectionOverlay itself (not merely the raw descriptor) must reflect
	# the SAME exactly-in-reach-enemies set.
	assert_true(instance.selection_overlay.is_active(), "SelectionOverlay must be active (Layer 2) after pressing STRIKE")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "STRIKE")

	var highlighted_ids: Array = instance.selection_overlay.get_highlighted_target_ids()
	assert_eq(highlighted_ids.size(), expected_target_ids.size(), "SelectionOverlay must highlight exactly one hex per in-reach enemy target")
	for target_id in expected_target_ids:
		assert_true(highlighted_ids.has(target_id), "expected in-reach enemy target %s to be highlighted" % target_id)

	# The exact hex(es) pushed to the real HexGridView must be precisely the
	# highlighted target(s)' own occupied hex(es) -- the SAME positional data
	# CombatantTokenView already renders from, never an independently
	# recomputed position.
	var highlighted_hexes: Array = instance.selection_overlay.get_highlighted_hexes()
	assert_eq(highlighted_hexes.size(), expected_target_ids.size())
	for target_id in expected_target_ids:
		var token = instance.hex_grid_view.get_token(target_id)
		assert_not_null(token, "fixture assumption: every in-reach target has a rendered HexGridView token")
		var found: bool = false
		for hex_coord in highlighted_hexes:
			if hex_coord.equals(token.hex_coord):
				found = true
				break
		assert_true(found, "the in-reach target %s's own hex must be among SelectionOverlay's highlighted hexes" % target_id)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — clicking a highlighted target's hex resolves through the
# REAL ActionResolverPort.select_target()/ResolveActionUseCase path (no
# forked logic), and the board (HexGridView token count/state) and status
# bar (StatusPanelView / EventLogView) reflect the outcome.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_highlighted_target_resolves_through_select_target_and_updates_board_and_status_bar() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	var events_before: int = instance.event_log_view.get_entry_count()

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists")
	var target_id: String = target_ids[0]

	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")
	var target_hex_before_hp = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(target_hex_before_hp > 0, "sanity check: the target starts alive")

	# Simulate the real player interaction: a left-click resolving to the
	# highlighted target's own hex, via the REAL HexGridView.hex_clicked
	# signal SelectionOverlay is subscribed to (presentation/
	# selection_overlay.gd, wired by MainScene.gd) -- never calling
	# `_verb_registry.execute()` directly.
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the click resolves a real Strike")

	# The board (status bar / event log) reflects the outcome -- resolved
	# through the SAME resolve_action_use_case.resolve() every other Strike
	# path in this codebase already uses (ADR-002: no forked resolution
	# logic).
	assert_true(
		instance.event_log_view.get_entry_count() > events_before,
		"resolving STRIKE via a real highlighted-target click must flow through resolve_action_use_case and log a real AttackEvent"
	)

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"the acting combatant's action_budget_remaining must decrease by EXACTLY 1 after the real Strike resolves"
	)

	var target_hp_after: int = instance.status_panel_view.get_status(target_id).get("hp_current", -1)
	assert_true(
		target_hp_after < target_hex_before_hp,
		"the target's displayed hp_current must decrease -- the real Strike must have actually damaged it"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — clicking a non-highlighted (out-of-reach) location produces
# NO resolution at all: no action-budget spend, no event logged, no HP
# change on any combatant.
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_a_non_highlighted_out_of_reach_location_produces_no_resolution() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	var events_before: int = instance.event_log_view.get_entry_count()

	var out_of_reach_hex = _far_unoccupied_hex(instance)
	watch_signals(instance.selection_overlay)

	instance.hex_grid_view.hex_clicked.emit(out_of_reach_hex)

	assert_signal_emitted(instance.selection_overlay, "selection_rejected", "an out-of-reach click must emit selection_rejected, never selection_resolved")
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "an out-of-reach click must NEVER resolve through the verb registry")

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1), before_remaining,
		"an out-of-reach click must spend no action -- no resolution may occur"
	)
	assert_eq(
		instance.event_log_view.get_entry_count(), events_before,
		"an out-of-reach click must log no event -- no resolution may occur"
	)
	assert_true(
		instance.selection_overlay.is_active(),
		"Strike's Layer 2 selection must remain active after a rejected, non-highlighted click (no accidental cancel)"
	)
