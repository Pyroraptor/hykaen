extends GutTest
## tests/integration/test_steel_thread_selection_e2e.gd — FEAT-009 (US-009):
## "End-to-end steel thread integration test: click selection and
## active-actor selection consistency."
##
## The capstone integration proof for this steel thread (FEAT-001..FEAT-008):
## exercises the REAL, booted res://MainScene.tscn composition root — the
## real HexGridView, the real StatusPanelView, the real
## ExplorationModeController, the real TurnController — end to end,
## entry_point (a simulated hex click during exploration / a simulated
## active_actor_changed handoff during combat) -> exit_point (the selection
## ring guard state + the status panel's gold row + id consistency across all
## three collaborators), with NOTHING mocked. This mirrors this codebase's
## established `_boot_main_scene()` convention (see
## tests/integration/test_exploration_click_disambiguation.gd,
## tests/integration/test_active_actor_selection.gd,
## tests/integration/test_exploration_status_panel_wiring.gd) rather than
## introducing a new one.
##
## Cross-cutting invariant under test throughout (ADR-002/ADR-003, design
## notes' "Invariant" section): after every use case completes,
## hex_grid_view.get_selected_combatant() ==
## status_panel_view.get_selected_combatant_id() ==
## ExplorationModeController.selected_party_member_id (exploration) or the
## active combat actor's combatant_id (combat) — never a divergence.
##
## Fixture facts (mirrors tests/integration/test_exploration_click_disambiguation.gd's
## and tests/integration/test_active_actor_selection.gd's own established
## fixture assumptions for data/scenarios/prologue_scenario.tres +
## data/parties/default_party.tres, seed=42):
##   - player_0 (Titus) starts at (0, 0) and is the default exploration
##     selection at boot.
##   - player_1 (Marigold) starts at (-1, 0) — hex-distance 1 (adjacent) from
##     Titus.
##   - enemy_0 (Skeleton) is the prologue encounter's seated enemy.
##   - At seed=42, the first actor whose turn opens combat is player_0
##     (Titus); a second, distinct party member (player_1 / Marigold) is
##     used to prove a genuine active-actor selection SHIFT.
##
## test_criteria covered (per feature spec):
##   1. Click a hex containing a party-member token in exploration mode ->
##      hex_grid_view.get_selected_combatant(),
##      status_panel_view.get_selected_combatant_id(), and
##      ExplorationModeController.selected_party_member_id are all equal and
##      non-empty.
##   2. The ring-draw guard state (should_draw_selection_ring()) is true for
##      the selected token (with the correct radius/width/color constants)
##      and — because the guard is a single, global "is there a current
##      selection with a live token" boolean keyed to EXACTLY ONE id (never a
##      per-token flag array) — is provably false for every OTHER token, since
##      _draw_selection_ring() only ever renders a ring for
##      _tokens[_selected_combatant_id] and no other id can equal the
##      selected one at the same time.
##   3. The corresponding StatusPanelView row is gold-modulated and every
##      other loaded row (including a combatant never present on
##      hex_grid_view during exploration, e.g. the not-yet-spawned enemy) is
##      white.
##   4. Transitioning into combat and driving active_actor_changed for a
##      player actor keeps hex_grid_view/status_panel_view updated to that
##      actor and mutually consistent.
##   5. Driving active_actor_changed for an enemy actor leaves both
##      selections unchanged from the prior player selection (RISK-002).
##   6. Contract preservation: get_combatant_id_at_hex, set_selected_combatant,
##      get_selected_combatant, get_selected_combatant_id, and
##      _select_party_member are all still present and callable with their
##      documented signatures — plus an E2E re-verification of RISK-003 (no
##      direct-assignment desync path): mutating hex_grid_view's selection
##      DIRECTLY (bypassing _select_party_member) must never retroactively
##      update ExplorationModeController.selected_party_member_id, proving
##      _select_party_member remains the single authorized write path.
##
## Because TurnController's own auto-drive loop never settles/emits
## active_actor_changed while an Enemy is the current actor (it auto-resolves
## every consecutive Enemy turn internally), this suite drives
## MainScene._on_active_actor_changed() directly with REAL, live Combatant
## instances drawn from the booted instance's own `_party`/`_enemies` arrays
## for the enemy-turn scenario — the SAME deterministic technique
## tests/integration/test_active_actor_selection.gd already establishes and
## documents (RISK-002: "avoiding flicker/race conditions from mid-signal
## mutation"). This exercises the exact handler TurnController's real
## active_actor_changed signal is wired to, against real domain Combatant
## entities, without depending on the AI's own multi-turn drive to happen to
## produce an observable mid-drive enemy actor.

const MainSceneClass = preload("res://MainScene.gd")
const HexGridViewClass = preload("res://presentation/hex_grid_view.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const GameStateDataClass = preload("res://data/game_state/game_state_data.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_exploration_click_disambiguation.gd's /
## tests/integration/test_active_actor_selection.gd's identically-named/
## valued constant).
const PROLOGUE_SEED: int = 42
const PROLOGUE_ENCOUNTER_ID: String = "prologue"

const GOLD: Color = Color(1.0, 0.9, 0.4)
const WHITE: Color = Color(1, 1, 1, 1)


# ══════════════════════════════════════════════════════════════════════════
# Fixture isolation — mirrors tests/integration/test_exploration_status_panel_wiring.gd's
# established convention: reseed CurrentGameState.data with a fresh
# GameStateData so every test in this file always takes the same
# prologue-fallback boot path, regardless of suite ordering.
# ══════════════════════════════════════════════════════════════════════════

func before_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func after_each() -> void:
	CurrentGameState.data = GameStateDataClass.new()


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "res://MainScene.tscn (the project's real composition root) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _find_combatant_by_id(instance, combatant_id) -> Combatant or null.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _assert_selection_consistency(instance, expected_id, context) -> void —
## the shared cross-system invariant assertion (ADR-002/ADR-003) this whole
## file exists to pin: hex_grid_view, status_panel_view, and (whenever
## exploration mode owns the selection) ExplorationModeController must all
## report the SAME, non-empty combatant_id.
func _assert_selection_consistency(instance, expected_id: String, context: String) -> void:
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), expected_id,
		"%s: hex_grid_view.get_selected_combatant() must equal '%s'" % [context, expected_id]
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), expected_id,
		"%s: status_panel_view.get_selected_combatant_id() must equal '%s'" % [context, expected_id]
	)
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), instance.status_panel_view.get_selected_combatant_id(),
		"%s: selection consistency invariant (hex_grid_view == status_panel_view) must hold" % context
	)
	assert_false(expected_id.is_empty(), "%s: the expected selected id must be non-empty" % context)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1-3 — exploration-mode hex click on a party-member token: ring
# guard + status highlight + id consistency across HexGridView/
# StatusPanelView/ExplorationModeController.
# ══════════════════════════════════════════════════════════════════════════

func test_exploration_click_on_party_member_token_selects_with_consistent_ring_and_status_highlight() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# ── fixture sanity: default boot selection is Titus (player_0) at (0,0),
	# Marigold (player_1) is seated adjacent at (-1,0). ──────────────────────
	assert_eq(
		instance._exploration.selected_party_member_id, "player_0",
		"fixture assumption: Titus (player_0) is the default exploration selection at boot"
	)
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].q, -1, "fixture assumption: Marigold (player_1) starts at (-1, 0)")
	assert_eq(instance.scenario_session.party_hex_positions["player_1"].r, 0, "fixture assumption: Marigold (player_1) starts at (-1, 0)")

	var marigold_hex := HexCoordClass.new(-1, 0)
	assert_eq(
		instance.hex_grid_view.get_combatant_id_at_hex(marigold_hex), "player_1",
		"fixture assumption: Marigold's own token must be found at her own current hex (entry_point precondition)"
	)

	# ── entry_point: simulate a click on the hex containing Marigold's
	# party-member token. ─────────────────────────────────────────────────────
	await instance._exploration._on_exploration_hex_clicked(marigold_hex)

	# ── Criterion 1: id consistency across all three collaborators. ─────────
	_assert_selection_consistency(instance, "player_1", "after clicking Marigold's hex-token")
	assert_eq(
		instance._exploration.selected_party_member_id, "player_1",
		"ExplorationModeController.selected_party_member_id must also equal the clicked party member's id"
	)

	# ── Criterion 2: the ring-draw guard is true for the selected token, with
	# the documented radius/width/color, and — because should_draw_selection_
	# ring()/_draw_selection_ring() key off a SINGLE _selected_combatant_id,
	# never a per-token flag — is provably false for every other token
	# (Titus' own token still exists on the grid, but is not the selected id,
	# so no ring can ever be drawn for it). ──────────────────────────────────
	assert_true(
		instance.hex_grid_view.should_draw_selection_ring(),
		"the ring-draw guard must be true once a live-tokened combatant is selected"
	)
	assert_eq(
		HexGridViewClass.SELECTION_RING_RADIUS, HexGridViewClass.HEX_SIZE * 0.65,
		"the ring radius constant this guard's paired _draw_selection_ring() call reads must match the design-pinned value"
	)
	assert_eq(HexGridViewClass.SELECTION_RING_WIDTH, 3.0, "the ring width constant must match the design-pinned value")
	assert_eq(
		HexGridViewClass.SELECTION_RING_COLOR, Color(1.0, 1.0, 1.0, 0.9),
		"the ring color constant must match the design-pinned value"
	)
	assert_not_null(instance.hex_grid_view.get_token("player_0"), "fixture assumption: Titus' own token must still be on-screen (a non-selected token)")
	assert_ne(
		instance.hex_grid_view.get_selected_combatant(), "player_0",
		"the ring-draw pass renders ONLY _tokens[_selected_combatant_id] -- Titus' still-present token must NOT be the selected id, "
		+ "so the guard's single true state can never also cover a non-selected token"
	)

	# ── Criterion 3: StatusPanelView's corresponding row is gold; every other
	# loaded row (including the not-yet-spawned-on-hex_grid_view enemy row,
	# already loaded into StatusPanelView at boot per this steel thread's own
	# encounter-construction contract) is white. ─────────────────────────────
	assert_eq(
		instance.status_panel_view.get_row_modulate("player_1"), GOLD,
		"the selected party member's status-panel row must be gold-modulated"
	)
	assert_eq(instance.status_panel_view.get_row_modulate("player_0"), WHITE, "every other loaded row must remain white")
	assert_eq(
		instance.status_panel_view.get_row_modulate("enemy_0"), WHITE,
		"the not-yet-spawned enemy's status-panel row (loaded at boot alongside the party rows) must remain white too"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 4-5 — combat transition: active_actor_changed for a player actor
# and for an enemy actor, keeping (or deliberately not disturbing) the same
# cross-system consistency invariant.
# ══════════════════════════════════════════════════════════════════════════

func test_combat_active_actor_changed_keeps_selection_consistent_for_player_and_enemy_actors() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# ── entry_point: exploration -> combat handoff (the real proximity-
	# trigger/combat-session assembly path, not a mock). ─────────────────────
	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(instance._game_mode, MainSceneClass.GameMode.COMBAT, "fixture assumption: the real exploration->combat handoff must succeed")
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter must seed at least one live enemy")

	# ── Criterion 4 (initial state): combat entry already auto-selects the
	# active player actor (AutoSelectActiveActorUseCase, FEAT-008) -- assert
	# that state is genuinely consistent before any further transition. ─────
	var player_actor = instance.round_session.current_actor_entity()
	assert_not_null(player_actor, "fixture assumption: a live current actor must be seated at combat entry")
	assert_false(player_actor.is_enemy, "fixture assumption: the first actor at seed=42 is a living player combatant (Titus)")
	assert_eq(player_actor.combatant_id, "player_0", "fixture assumption: Titus is party index 0 -> combatant_id 'player_0'")
	_assert_selection_consistency(instance, "player_0", "at combat entry (active player actor)")

	# ── Criterion 5: an enemy actor becoming active must NOT change either
	# selection from the prior (player) selection. ──────────────────────────
	var enemy_actor = _find_combatant_by_id(instance, "enemy_0")
	assert_not_null(enemy_actor, "fixture assumption: prologue_encounter.tres seats a live 'enemy_0' (Skeleton)")
	assert_true(enemy_actor.is_enemy, "fixture assumption: 'enemy_0' is on the Enemy team")

	instance._on_active_actor_changed(enemy_actor)
	await get_tree().process_frame

	_assert_selection_consistency(instance, "player_0", "after an enemy actor's turn (RISK-002: must remain unchanged)")

	# ── Criterion 4 (transition): a SUBSEQUENT, DIFFERENT player actor
	# becoming active shifts both selections to it and remains consistent. ──
	var next_player_actor = _find_combatant_by_id(instance, "player_1")
	assert_not_null(next_player_actor, "fixture assumption: prologue_encounter.tres seats a live 'player_1' (Marigold)")
	assert_false(next_player_actor.is_enemy, "fixture assumption: 'player_1' is on the Player team")

	instance._on_active_actor_changed(next_player_actor)
	await get_tree().process_frame

	_assert_selection_consistency(instance, "player_1", "after the subsequent player actor's turn (a genuine selection shift)")

	# Ring-guard / status-highlight re-verification, now with the enemy token
	# actually present on hex_grid_view (added by the exploration->combat
	# handoff) — the same single-selected-id guard still correctly excludes
	# it, exactly as it excluded Titus' still-present token in the
	# exploration-mode test above.
	assert_true(instance.hex_grid_view.should_draw_selection_ring(), "the ring-draw guard must still be true for the newly active player actor")
	assert_not_null(instance.hex_grid_view.get_token("enemy_0"), "fixture assumption: the enemy token must now be on-screen after the combat handoff")
	assert_ne(instance.hex_grid_view.get_selected_combatant(), "enemy_0", "the live enemy token must never be the selected id after a player actor's turn")
	assert_eq(instance.status_panel_view.get_row_modulate("player_1"), GOLD, "the newly active player actor's status-panel row must be gold-modulated")
	assert_eq(instance.status_panel_view.get_row_modulate("enemy_0"), WHITE, "the enemy's status-panel row must remain white")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — contract preservation: none of HexGridView.
# get_combatant_id_at_hex/set_selected_combatant/get_selected_combatant,
# StatusPanelView.get_selected_combatant_id, or ExplorationModeController.
# _select_party_member were removed/renamed (RISK-009); each is exercised
# against its documented signature/behavior. Also re-verifies RISK-003 (no
# direct-assignment desync path) end to end.
# ══════════════════════════════════════════════════════════════════════════

func test_contract_preservation_documented_public_methods_remain_callable() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	# get_combatant_id_at_hex(hex_coord: HexCoord) -> String
	assert_true(instance.hex_grid_view.has_method("get_combatant_id_at_hex"), "HexGridView.get_combatant_id_at_hex must still exist")
	var titus_hex := HexCoordClass.new(0, 0)
	var resolved_id: String = instance.hex_grid_view.get_combatant_id_at_hex(titus_hex)
	assert_eq(resolved_id, "player_0", "get_combatant_id_at_hex(hex_coord) -> String must still resolve an occupied hex to its combatant_id")
	assert_eq(
		instance.hex_grid_view.get_combatant_id_at_hex(HexCoordClass.new(99, 99)), "",
		"get_combatant_id_at_hex must still return \"\" (never null) for an unoccupied hex"
	)

	# set_selected_combatant(id: String) -> void / get_selected_combatant() -> String (HexGridView)
	assert_true(instance.hex_grid_view.has_method("set_selected_combatant"), "HexGridView.set_selected_combatant must still exist")
	assert_true(instance.hex_grid_view.has_method("get_selected_combatant"), "HexGridView.get_selected_combatant must still exist")
	instance.hex_grid_view.set_selected_combatant("player_1")
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), "player_1",
		"set_selected_combatant(id)/get_selected_combatant() must still round-trip"
	)

	# get_selected_combatant_id() -> String (StatusPanelView)
	assert_true(instance.status_panel_view.has_method("get_selected_combatant_id"), "StatusPanelView.get_selected_combatant_id must still exist")
	assert_eq(
		typeof(instance.status_panel_view.get_selected_combatant_id()), TYPE_STRING,
		"StatusPanelView.get_selected_combatant_id() must still return a String"
	)

	# _select_party_member(id: String) -> void (ExplorationModeController) —
	# the SINGLE authorized write path (ADR-002/RISK-003).
	assert_true(instance._exploration.has_method("_select_party_member"), "ExplorationModeController._select_party_member must still exist")
	instance._exploration._select_party_member("player_1")
	assert_eq(instance._exploration.selected_party_member_id, "player_1", "_select_party_member(id) must still update selected_party_member_id")
	assert_eq(
		instance.hex_grid_view.get_selected_combatant(), "player_1",
		"_select_party_member(id) must still write through to hex_grid_view.set_selected_combatant()"
	)
	assert_eq(
		instance.status_panel_view.get_selected_combatant_id(), "player_1",
		"_select_party_member(id) must still write through to the status-panel mirror via on_selection_changed"
	)

	# RISK-003 re-verification (E2E): a call that mutates hex_grid_view's
	# selection DIRECTLY, bypassing _select_party_member entirely, must NOT
	# retroactively update ExplorationModeController.selected_party_member_id
	# — proving _select_party_member remains the single authorized writer,
	# never a shared mutable global two collaborators could independently
	# desync.
	instance.hex_grid_view.set_selected_combatant("player_0")
	assert_eq(instance.hex_grid_view.get_selected_combatant(), "player_0", "sanity check: the direct, bypassing call must still take effect on hex_grid_view itself")
	assert_eq(
		instance._exploration.selected_party_member_id, "player_1",
		"RISK-003: bypassing _select_party_member must NOT implicitly update ExplorationModeController.selected_party_member_id"
	)
