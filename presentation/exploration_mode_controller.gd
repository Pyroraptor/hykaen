## presentation/exploration_mode_controller.gd — ExplorationModeController
## (FEAT-009 / US-008 / FR-005).
##
## Presentation layer (Clean Architecture): the extracted, independently-
## testable controller for exploration-mode BOOT, hex-click handling, and
## scenario-encounter loading -- moved out of MainScene.gd's own former
## `_boot_exploration_mode()` / `load_encounter_from_scenario()` bodies
## (FEAT-006/FEAT-010). Owns the two Application-layer collaborators those
## methods used to construct inline:
##
##   scenario_session       — a fresh core/application/scenario_session.gd
##                             ScenarioSession, seeded from the injected
##                             scenario_path + boot()'s hex_combatants.
##   exploration_controller — a fresh core/application/exploration_controller.gd
##                             ExplorationController wrapping scenario_session.
##
## MainScene.gd remains the composition root: it owns `_game_mode`/
## `_active_encounter_id` (pure composition-root state, never duplicated
## here) and its own PINNED `_on_combat_triggered()` / `_on_exploration_hex_
## clicked()` / `_on_combat_won()` handler bodies (unchanged by this
## feature -- see MainScene.gd's own doc for why rewriting the multi-step
## combat handoff/round-wiring those methods drive is explicitly out of this
## feature's scope, mirroring presentation/round_flow_controller.gd's own
## "wrap, don't replace the pinned method" precedent). What MOVES here is:
##
##   1. BOOT: constructing scenario_session/exploration_controller and wiring
##      hex_grid_view.hex_clicked / exploration_controller.combat_triggered
##      to caller-supplied Callables (setup(deps)'s "on_hex_clicked"/
##      "on_combat_triggered" targets -- typically
##      Callable(main_scene, "_on_exploration_hex_clicked") /
##      Callable(main_scene, "_on_combat_triggered"), so the REAL, booted
##      res://MainScene.tscn's own signal-connection assertions
##      (tests/boot/test_boot_exploration_mode.gd et al.) keep observing
##      those exact connections, just wired from here instead of inline).
##   2. SCENARIO-ENCOUNTER LOADING: load_encounter_from_scenario(scenario,
##      encounter_id, seed) -- the LoadScenarioEncounterUseCase-driven use
##      case call + CombatantClass.from_dict() lift + EncounterClass.new()/
##      initialize() call, moved here verbatim (ADR-006, no duplicated
##      algorithm). On success this method ALSO emits this controller's own
##      `combat_triggered(encounter_id)` signal (design notes' api_contracts
##      #2: "load_encounter_from_scenario returns true and later emits
##      combat_triggered(encounter_id)") -- a signal independent of (and not
##      wired to) `exploration_controller.combat_triggered` above, available
##      for a future composition step; MainScene.gd's OWN
##      load_encounter_from_scenario() wrapper only reads the boolean return
##      value + this controller's `party`/`enemies`/`encounter` fields today.
##
## `combat_won_return_to_exploration()` is likewise declared here (this
## feature's own signal-surface requirement) and emitted by
## `resume_after_combat_won(encounter_id)` -- the exploration-side half of
## the post-combat handoff (mark the encounter complete in scenario_session,
## reconnect hex_click) -- available for a later feature to wire
## MainScene.gd's `_on_combat_won()` through; this feature does not itself
## rewire that pinned method (see file-level doc above).
##
## Idempotency (this feature's own test_criterion): boot(hex_combatants) is
## safe to call a second time -- a `_booted` guard makes every call after
## the first a no-op, so scenario_session/exploration_controller are never
## reconstructed (which would reset party_hex_positions) and hex_clicked/
## combat_triggered are never double-connected.
##
## FEAT-007 (US-007 / FR-009): boot() ALSO wires hex_grid_view.hex_hovered ->
## this controller's own _on_hex_hovered() (idempotency-guarded exactly like
## hex_clicked above) and builds this controller's cached PassabilityQuery/
## MoveCostQuery Callables (_is_passable_fn/_move_cost_fn) EXACTLY ONCE, via
## core/geometry/encounter_tile_adapter.gd's EncounterTileAdapter -- never
## rebuilt per hover event (ADR-006 shared-callable pattern: the SAME
## Callables a future execution/movement path would use, so preview and
## execution can never disagree about what's passable). The tile source is
## the scenario's first active encounter entry's EncounterResource (the
## terrain the party is walking through BEFORE any proximity trigger fires
## -- see data/scenarios/prologue_scenario.tres's own encounter_entries[0].
## encounter, which authors exactly this terrain); when the scenario has no
## encounter entries at all (or no scenario loaded), the Callables fall back
## to the open-world default (always passable, cost 1.0), mirroring
## core/application/exploration_controller.gd's own "no encounter injected"
## NFR-001 precedent.
##
## On every hex_hovered(hex_coord) with hex_coord non-null, while exploration
## is active (see notify_game_mode_changed()) and `selected_party_member_id`
## names a party member with a known scenario_session.party_hex_positions
## entry, computes core/geometry/hex_pathfinder.gd's
## HexPathfinder.find_path() from that member's current hex to the hovered
## hex using the cached Callables, and displays the result via
## hex_grid_view.set_path_overlay() -- an unreachable/impassable hover target
## resolves to an empty path, which set_path_overlay([]) always renders as
## "nothing" (no crash, API contract #6), so an unreachable hover is a silent
## no-preview no-op rather than a stale/wrong overlay.
##
## The overlay is cleared (hex_grid_view.clear_overlays()) on a `null`
## hex_hovered emission (HexGridView's own "mouse left this view" case, see
## its own doc) and when notify_game_mode_changed(false) transitions
## exploration from active to inactive (US-007's own "clear on mode switch
## away from exploration" requirement) -- both funnel through the SAME
## _clear_hover_preview() so there is exactly one overlay-clearing code path
## for this feature (ADR-006, no duplicated seam).
##
## FEAT-008 (US-008 / FR-010, ADR-005): _on_exploration_hex_clicked(hex_coord)
## is this controller's own click-to-navigate entry point -- computes the
## FULL path from the same cached Callables the hover preview above uses,
## clears the overlay exactly once, then awaits _execute_exploration_path()
## to walk every step, pairing exploration_controller.move_party_member()
## (domain finalization) with hex_grid_view.animate_token_to() (awaited
## presentation-side tween) one step at a time. See both methods' own doc
## comments below for the full ordering/no-op contract. Not yet wired to
## hex_grid_view.hex_clicked by boot() above -- that composition-root wiring
## (replacing MainScene.gd's own single-step _on_exploration_hex_clicked
## handler) is left to a later feature, mirroring this file's established
## "declared here, wired by a future step" precedent (see
## combat_won_return_to_exploration's own doc above).

class_name ExplorationModeController
extends RefCounted

const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const RNGClass = preload("res://core/rules/rng.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")
const HexPathfinderClass = preload("res://core/geometry/hex_pathfinder.gd")
const EncounterTileAdapterClass = preload("res://core/geometry/encounter_tile_adapter.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")

## Emitted by load_encounter_from_scenario() on success, carrying the
## encounter_id that was just loaded.
signal combat_triggered(encounter_id: String)

## Emitted by resume_after_combat_won() once the exploration-side half of
## the post-combat handoff (mark-complete + hex_click reconnect) is done.
signal combat_won_return_to_exploration()

## scenario_session — the ScenarioSession this controller constructs at
## boot(). Null until boot() has run.
var scenario_session = null

## exploration_controller — the ExplorationController this controller
## constructs at boot(), wrapping scenario_session. Null until boot() has
## run. Settable (not just gettable) so a caller (MainScene.gd's own
## `exploration_controller` proxy, or a GUT test) may substitute a spy/fake
## after boot() -- mirrors this codebase's established "assign over a real
## collaborator with a hand-written spy" test convention.
var exploration_controller = null

## party / enemies / encounter — the live Combatant roster + initialized
## Encounter assembled by the most recent successful load_encounter_from_
## scenario() call. Empty/null until a successful call.
var party: Array = []
var enemies: Array = []
var encounter = null

var _hex_grid_view = null
var _scenario_path: String = ""
var _on_hex_clicked_target: Callable = Callable()
var _on_combat_triggered_target: Callable = Callable()
var _booted: bool = false

## FEAT-007 (US-007, ADR-004): the "internal API" contract boundary this
## feature introduces — a Callable the composition root (MainScene.gd) binds
## to its own status-panel mirror (typically
## Callable(status_panel_view, "set_selected_combatant")) so every
## selection-state change made via _select_party_member() below is echoed to
## the exploration-mode status panel, not just to hex_grid_view. Defaults to
## an invalid/unbound Callable (setup()'s own "every key optional, no crash
## on a partially-configured setup()" convention, see setup()'s own doc) —
## _select_party_member()'s own `.is_valid()` guard below degrades this to a
## silent no-op (no throw) whenever no caller has wired it, so exploration
## selection keeps working even when the status-panel mirror is absent
## (e.g. an isolated unit test with no StatusPanelView double at all).
var _on_selection_changed_target: Callable = Callable()

## FEAT-006 (US-004 / FR-006, ADR-002, mitigates RISK-007): the camera-follow
## Callable the composition root (MainScene.gd) binds to its own GameCamera
## adapter (typically Callable(_game_camera, "move_to")) so every selection
## made via _select_party_member() below also pans the camera to the newly-
## selected party member's token. Defaults to an invalid/unbound Callable
## (setup()'s own "every key optional, no crash on a partially-configured
## setup()" convention, see setup()'s own doc) — _select_party_member()'s own
## `.is_valid()` guard below degrades this to a silent no-op (no throw)
## whenever no caller has wired it, so exploration selection keeps working
## unchanged even when no camera adapter is present (e.g. an isolated unit
## test with no GameCamera double at all) — this is the explicit backward-
## compatibility contract this feature's own regression test proves.
var _on_camera_follow_target: Callable = Callable()

## FEAT-007 (US-007 / FR-009): the party member whose hex the hover-preview
## path is computed FROM. Defaults empty ("no selection" -- hover is a
## no-op); boot() defaults this to the FIRST hex_combatants entry seeded
## into scenario_session.party_hex_positions (mirroring MainScene.gd's own
## `_party[0]` "the active party member" convention used by hex-click
## movement) whenever it is still empty, so a caller never has to select a
## party member explicitly just to see the default steel-thread behavior --
## but MAY reassign this field directly (this codebase's established
## "settable public field, not a dedicated setter method" convention, see
## `exploration_controller`/`scenario_session` above) to preview a path from
## a different party member.
var selected_party_member_id: String = ""

## FEAT-007 (US-007 / FR-009, ADR-006): the cached PassabilityQuery/
## MoveCostQuery Callables this controller's own _on_hex_hovered() hands to
## HexPathfinder.find_path(), built EXACTLY ONCE by boot() (see boot()'s own
## doc) via EncounterTileAdapterClass.make_is_passable()/make_move_cost(), or
## a trivial always-passable/unit-cost pair when no encounter data is
## available. Invalid (Callable()) until boot() has run.
var _is_passable_fn: Callable = Callable()
var _move_cost_fn: Callable = Callable()

## FEAT-007 (US-007 / FR-009): true while EXPLORATION mode is the active game
## mode (this controller's own local mirror of MainScene.gd's `_game_mode`,
## kept intentionally decoupled from MainScene's GameMode enum -- Clean
## Architecture: this presentation-layer controller only needs a boolean,
## never MainScene's own type). Defaults true (mirrors MainScene.gd's own
## `_game_mode` defaulting to GameMode.EXPLORATION at boot). See
## notify_game_mode_changed().
var _exploration_active: bool = true

## FEAT-007 (US-007 / FR-009): the preview path color the hover-preview
## overlay is drawn with -- distinct from a future click-to-navigate
## execution overlay's own color (not introduced by this feature), so a
## later feature can tell the two apart on hex_grid_view at a glance.
const HOVER_PREVIEW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.6)


## setup(deps) -> void — injects this controller's collaborators. Recognized
## keys (all optional, each defaulting to a harmless no-op value so a
## partially-configured setup() never crashes boot()):
##   "hex_grid_view"        — the HexGridView node whose hex_clicked signal
##                             boot() wires to "on_hex_clicked".
##   "scenario_path"        — String res:// path to the ScenarioResource
##                             boot() loads.
##   "on_hex_clicked"       — Callable invoked (via hex_grid_view.hex_clicked)
##                             on every exploration-mode hex click.
##   "on_combat_triggered"  — Callable invoked (via exploration_controller.
##                             combat_triggered) the instant a proximity
##                             trigger fires.
##   "on_selection_changed" — FEAT-007 (US-007, ADR-004): Callable invoked
##                             (via _select_party_member(), see its own doc)
##                             with the newly-selected combatant_id every
##                             time selection changes. The composition
##                             root's "internal API" contract boundary to the
##                             status-panel mirror — typically
##                             Callable(status_panel_view,
##                             "set_selected_combatant"). Left unbound
##                             (Callable()) when absent; _select_party_member()
##                             degrades gracefully (skips the call, never
##                             throws) whenever it is invalid.
##   "on_camera_follow"     — FEAT-006 (US-004, ADR-002): Callable invoked
##                             (via _select_party_member(), see its own doc)
##                             with the newly-selected party member's world
##                             position (Vector2, from hex_grid_view.
##                             axial_to_pixel_with_offset()) every time
##                             selection changes. The composition root's
##                             "internal API" contract boundary to the camera
##                             adapter — typically Callable(_game_camera,
##                             "move_to"). Left unbound (Callable()) when
##                             absent; _select_party_member() degrades
##                             gracefully (skips the call, never throws)
##                             whenever it is invalid — explicit backward-
##                             compatibility contract (RISK-007), proven by
##                             this feature's own regression test.
func setup(deps: Dictionary) -> void:
	_hex_grid_view = deps.get("hex_grid_view", null)
	_scenario_path = deps.get("scenario_path", "")
	_on_hex_clicked_target = deps.get("on_hex_clicked", Callable())
	_on_combat_triggered_target = deps.get("on_combat_triggered", Callable())
	_on_selection_changed_target = deps.get("on_selection_changed", Callable())
	_on_camera_follow_target = deps.get("on_camera_follow", Callable())


## boot(hex_combatants) -> void — constructs scenario_session/
## exploration_controller from `_scenario_path` (setup()), seeds
## scenario_session.party_hex_positions from `hex_combatants` (already
## loaded/rendered by the caller, mirrors the pre-extraction
## `_boot_exploration_mode()` contract verbatim), and wires the two
## injected Callables. IDEMPOTENT-SAFE: every call after the first is a
## silent no-op (this feature's own test_criterion) -- so re-entrant/
## repeated boot() calls can never reset an in-progress exploration session
## or double-connect a signal.
##
## A missing/malformed scenario resource push_error()s and leaves
## scenario_session.scenario null rather than aborting -- EXPLORATION mode
## still exists in a degenerate (no scenario) state instead of crashing
## (unchanged from the pre-extraction contract).
func boot(hex_combatants: Array) -> void:
	if _booted:
		return
	_booted = true

	scenario_session = ScenarioSessionClass.new()

	if _scenario_path == "":
		push_error("ExplorationModeController.boot(): no scenario_path configured (setup() not called?)")
	else:
		var scenario_resource = ResourceLoader.load(_scenario_path)
		if scenario_resource == null:
			push_error("ExplorationModeController.boot(): failed to load " + _scenario_path)
		else:
			scenario_session.scenario = scenario_resource
			var party_count: int = 0
			if scenario_resource.party != null:
				party_count = scenario_resource.party.character_resource_paths.size()
			for i in range(min(party_count, hex_combatants.size())):
				var party_hex_combatant = hex_combatants[i]
				scenario_session.party_hex_positions[party_hex_combatant.combatant_id] = party_hex_combatant.hex_coord
				# FEAT-007 (US-007 / FR-009): default `selected_party_member_id`
				# to the FIRST seeded party member (mirrors MainScene.gd's own
				# `_party[0]` convention for hex-click movement) so hover
				# preview works out of the box without a caller having to
				# select a party member explicitly. Never overwrites an
				# already-set selection (e.g. one assigned before boot()).
				# FEAT-002 (US-003 / FR-005, ADR-002): routed through
				# _select_party_member() rather than assigning
				# `selected_party_member_id` directly -- this boot-time
				# auto-select is the single call site that previously wrote
				# to `selected_party_member_id` outside the helper, and is
				# now the same single authorized write path every other
				# selection call site (_on_exploration_hex_clicked, a future
				# active-actor-changed handler) uses -- see
				# _select_party_member()'s own doc below.
				if selected_party_member_id == "":
					_select_party_member(party_hex_combatant.combatant_id)

	exploration_controller = ExplorationControllerClass.new(scenario_session)

	# FEAT-007 (US-007 / FR-009, ADR-006): build the cached PassabilityQuery/
	# MoveCostQuery Callables EXACTLY ONCE for this controller's lifetime --
	# never rebuilt inside _on_hex_hovered(), no matter how many hover events
	# arrive. Sourced from the scenario's first active encounter entry's
	# EncounterResource (the terrain the party is walking through before any
	# proximity trigger fires); falls back to the open-world default
	# (always passable, cost 1.0) when no such entry/encounter exists,
	# mirroring ExplorationController's own "no encounter injected" NFR-001
	# precedent.
	var pathfinding_encounter = null
	if scenario_session.scenario != null and not scenario_session.scenario.encounter_entries.is_empty():
		pathfinding_encounter = scenario_session.scenario.encounter_entries[0].encounter
	if pathfinding_encounter != null:
		_is_passable_fn = EncounterTileAdapterClass.make_is_passable(pathfinding_encounter)
		_move_cost_fn = EncounterTileAdapterClass.make_move_cost(pathfinding_encounter)
		# FEAT-009 (FR-007 test-migration criterion): paint the encounter's
		# authored terrain onto hex_grid_view via the SAME per-tile data
		# (data/tiles/hex_tile_data_resource.gd's q/r/terrain_type) the
		# EncounterTileAdapter above already reads for pathfinding -- so the
		# terrain a scenario's boot encounter authors is actually rendered,
		# not merely used for passability math. A no-op for any encounter
		# with an empty `tiles` array (e.g. the authored prologue encounter).
		if _hex_grid_view != null:
			for tile in pathfinding_encounter.tiles:
				_hex_grid_view.set_tile_terrain(HexCoordClass.new(tile.q, tile.r), tile.terrain_type)
	else:
		_is_passable_fn = func(_hex_coord): return true
		_move_cost_fn = func(_hex_coord): return 1.0

	if _on_combat_triggered_target.is_valid():
		if not exploration_controller.combat_triggered.is_connected(_on_combat_triggered_target):
			exploration_controller.combat_triggered.connect(_on_combat_triggered_target)

	# FEAT-009 (US-008 / FR-010, ADR-004): connect this controller's OWN
	# cooperative-polling flag directly to the domain-level
	# exploration_controller.combat_triggered signal -- independent of
	# whatever the caller-supplied `on_combat_triggered` target above does
	# (e.g. MainScene._on_combat_triggered flips ITS OWN `_game_mode`, but
	# never calls back into this controller's notify_game_mode_changed()).
	# Without this connection, `_exploration_active` would never flip when a
	# mid-path move triggers combat in the real, booted composition root,
	# leaving _execute_exploration_path()'s "if not _exploration_active:
	# return" abort check permanently dead code -- see _on_domain_combat_
	# triggered()'s own doc below for the full mechanism.
	if not exploration_controller.combat_triggered.is_connected(_on_domain_combat_triggered):
		exploration_controller.combat_triggered.connect(_on_domain_combat_triggered)

	if _hex_grid_view != null and _on_hex_clicked_target.is_valid():
		if not _hex_grid_view.hex_clicked.is_connected(_on_hex_clicked_target):
			_hex_grid_view.hex_clicked.connect(_on_hex_clicked_target)

	# FEAT-007 (US-007 / FR-009): wire HexGridView's hex_hovered straight into
	# this controller's own _on_hex_hovered() -- unlike hex_clicked/
	# combat_triggered above, this target is never caller-injected (no
	# "on_hex_hovered" setup() key), because the hover-preview behavior
	# itself belongs entirely to this controller (US-007's own scope), not to
	# a caller-supplied handler.
	if _hex_grid_view != null:
		if not _hex_grid_view.hex_hovered.is_connected(_on_hex_hovered):
			_hex_grid_view.hex_hovered.connect(_on_hex_hovered)


## _select_party_member(id) -> void — FEAT-002 (US-003 / FR-005, ADR-002):
## the SINGLE authorized write path for selection state (mitigates RISK-003
## at its source, per this feature's own design notes). Every call site that
## needs to change which party member is selected -- boot()'s own initial
## auto-select above, _on_exploration_hex_clicked()'s select-vs-move branch
## (a future feature per the X1-0 iteration plan), and a future active-actor-
## changed handler (X3-0) -- MUST route through this helper rather than
## assigning `selected_party_member_id` directly, so the two backing caches
## (this controller's own `selected_party_member_id` field and
## HexGridView's own `_selected_combatant_id`, set via
## set_selected_combatant()) can never desync.
##
## Sets `selected_party_member_id = id` (the "" sentinel clears selection,
## ADR-003, mirrors HexGridView.set_selected_combatant()'s own contract) and,
## if `_hex_grid_view != null` (defensive null-check, mirrors this file's
## established guard-clause convention -- a controller with no hex_grid_view
## wired, e.g. an isolated unit test, degrades to a state-only update rather
## than crashing), calls `_hex_grid_view.set_selected_combatant(id)` so the
## ring-render cache is updated in the SAME call, never a separate step a
## caller could forget.
##
## FEAT-007 (US-007, ADR-004): AFTER both of the above, invokes
## `_on_selection_changed_target.call(id)` -- the "internal API" contract
## boundary this feature adds (see setup()'s own "on_selection_changed" doc)
## -- so a caller-supplied mirror (typically the composition root's
## StatusPanelView.set_selected_combatant) is kept in lock-step with every
## selection change this helper makes, not just hex_grid_view's own ring
## cache. Degrades gracefully (skips the call, never throws) whenever
## `_on_selection_changed_target` is unbound/invalid -- exploration
## selection still fully functions; only the status-panel mirror is absent.
##
## FEAT-006 (US-004, ADR-002, mitigates RISK-007): AFTER the above, if
## `_on_camera_follow_target` is valid AND this controller can resolve `id`'s
## current hex (`_hex_grid_view != null`, `scenario_session != null`, and
## `scenario_session.party_hex_positions` has an entry for `id`), invokes
## `_on_camera_follow_target.call(world_pos)` with `world_pos` computed via
## `_hex_grid_view.axial_to_pixel_with_offset(hex_coord)` -- the SAME
## offset-aware conversion HexGridView itself uses to render that token, so
## the camera pans to exactly where the token is drawn. Degrades gracefully
## (skips the call, never throws) whenever the Callable is unbound/invalid
## or `id`'s hex cannot be resolved (e.g. an isolated unit test with no
## hex_grid_view/scenario_session wired at all) -- explicit backward-
## compatibility contract proven by this feature's own regression test.
func _select_party_member(id: String) -> void:
	selected_party_member_id = id
	if _hex_grid_view != null:
		_hex_grid_view.set_selected_combatant(id)
	if _on_selection_changed_target.is_valid():
		_on_selection_changed_target.call(id)
	if (
		_on_camera_follow_target.is_valid()
		and _hex_grid_view != null
		and scenario_session != null
		and scenario_session.party_hex_positions.has(id)
	):
		var hex_coord = scenario_session.party_hex_positions[id]
		var world_pos: Vector2 = _hex_grid_view.axial_to_pixel_with_offset(hex_coord)
		_on_camera_follow_target.call(world_pos)


## load_encounter_from_scenario(scenario, encounter_id, seed) -> bool —
## moved verbatim (ADR-006, no duplicated algorithm) from the pre-extraction
## MainScene.load_encounter_from_scenario(). Drives
## LoadScenarioEncounterUseCase.execute(scenario, encounter_id); on failure
## (ok=false) push_error()s and returns false WITHOUT mutating `party`/
## `enemies`/`encounter` at all. On success, lifts the use case's
## party_combatants/enemy_combatants Dictionaries onto live Combatant
## instances, assigns them to `party`/`enemies`, constructs + initialize()s
## a fresh EncounterClass around them seeded with `seed` (RNGClass.new(seed)),
## emits combat_triggered(encounter_id), and returns true.
func load_encounter_from_scenario(scenario, encounter_id: String, seed: int = -1) -> bool:
	var use_case := LoadScenarioEncounterUseCaseClass.new()
	var result: Dictionary = use_case.execute(scenario, encounter_id)

	if not result.get("ok", false):
		push_error(
			"ExplorationModeController.load_encounter_from_scenario: failed to load encounter_id '%s' (%s)"
			% [encounter_id, result.get("error_code", "UNKNOWN_ERROR")]
		)
		return false

	var new_party: Array = []
	for party_combatant_dict in result.get("party_combatants", []):
		new_party.append(CombatantClass.from_dict(party_combatant_dict))

	var new_enemies: Array = []
	for enemy_combatant_dict in result.get("enemy_combatants", []):
		new_enemies.append(CombatantClass.from_dict(enemy_combatant_dict))

	party = new_party
	enemies = new_enemies

	var rng := RNGClass.new(seed)
	encounter = EncounterClass.new(party, enemies, rng)
	encounter.initialize()

	combat_triggered.emit(encounter_id)
	return true


## resume_after_combat_won(encounter_id) -> void — the exploration-side half
## of the post-combat return-to-exploration handoff: marks `encounter_id`
## complete in scenario_session (idempotent/defensive against a dangling id,
## mirrors ScenarioSession.mark_encounter_complete()'s own contract) and
## reconnects hex_grid_view.hex_clicked -> the injected on_hex_clicked
## Callable (guarded against a double-connect), then emits
## combat_won_return_to_exploration(). Safe to call with an unset/empty
## encounter_id (a no-op mark-complete step) or before boot() has run (a
## no-op reconnect step, since `_hex_grid_view`/`_on_hex_clicked_target`
## default to null/invalid).
func resume_after_combat_won(encounter_id: String) -> void:
	if scenario_session != null and encounter_id != "":
		scenario_session.mark_encounter_complete(encounter_id)

	if _hex_grid_view != null and _on_hex_clicked_target.is_valid():
		if not _hex_grid_view.hex_clicked.is_connected(_on_hex_clicked_target):
			_hex_grid_view.hex_clicked.connect(_on_hex_clicked_target)

	combat_won_return_to_exploration.emit()


## _on_hex_hovered(hex_coord) -> void — FEAT-007 (US-007 / FR-009): connected
## to hex_grid_view.hex_hovered by boot() above. `hex_coord == null`
## (HexGridView's own "mouse left this view" case) always clears the
## preview overlay via _clear_hover_preview() and returns.
##
## Otherwise a NO-OP no-preview case (never a crash, mirrors this
## codebase's established fail-closed conventions) when:
##   - exploration is not the active mode (see notify_game_mode_changed()),
##   - no party member is selected (`selected_party_member_id == ""`), or
##   - `selected_party_member_id` has no entry in
##     scenario_session.party_hex_positions (e.g. boot() never ran, or the
##     id was reassigned to something unknown).
##
## Otherwise: computes HexPathfinder.find_path() from the selected party
## member's CURRENT scenario_session.party_hex_positions hex to `hex_coord`,
## using this controller's cached `_is_passable_fn`/`_move_cost_fn` (built
## exactly once by boot(), never rebuilt here — ADR-006), and hands the
## result straight to hex_grid_view.set_path_overlay(). An unreachable/
## impassable `hex_coord` resolves to find_path()'s empty-Array contract,
## which set_path_overlay([]) always renders as "nothing" — so hovering an
## unreachable hex is a silent no-preview outcome, never a stale/wrong
## overlay left over from a previous, reachable hover target.
func _on_hex_hovered(hex_coord) -> void:
	if hex_coord == null:
		_clear_hover_preview()
		return

	if not _exploration_active:
		return
	if selected_party_member_id == "" or scenario_session == null:
		return
	if not scenario_session.party_hex_positions.has(selected_party_member_id):
		return

	var start_hex = scenario_session.party_hex_positions[selected_party_member_id]
	var path: Array = HexPathfinderClass.find_path(start_hex, hex_coord, _is_passable_fn, _move_cost_fn)

	if _hex_grid_view != null:
		_hex_grid_view.set_path_overlay(path, HOVER_PREVIEW_COLOR)


## notify_game_mode_changed(is_exploration_mode) -> void — FEAT-007 (US-007 /
## FR-009): the caller-driven counterpart to this controller's own local
## `_exploration_active` mirror of MainScene.gd's `_game_mode` (see that
## field's own doc for why this stays a plain bool rather than importing
## MainScene's GameMode enum). Intended to be called by a composition root
## whenever its own game mode flips (e.g. MainScene.gd's `_on_combat_
## triggered()`/post-combat handoff, though wiring that call site is left to
## a future feature per this feature's own file-scope — see this file's own
## header doc). Transitioning from active (true) to inactive (false) clears
## the hover-preview overlay via _clear_hover_preview() (US-007's own "clear
## on mode switch away from exploration" requirement); every other
## transition (inactive -> active, or no change at all) is a safe no-op —
## re-activating exploration does NOT eagerly redraw a preview, since no
## current hover-target is known until the next hex_hovered emission.
func notify_game_mode_changed(is_exploration_mode: bool) -> void:
	var was_active: bool = _exploration_active
	_exploration_active = is_exploration_mode
	if was_active and not is_exploration_mode:
		_clear_hover_preview()


## _on_domain_combat_triggered(encounter_id) -> void — FEAT-009 (US-008 /
## FR-010, ADR-004 cooperative-polling contract, mitigates RISK-002).
## Connected directly to exploration_controller.combat_triggered by boot()
## above, ALONGSIDE (never instead of) the caller-supplied `on_combat_
## triggered` target -- this is this controller's OWN, self-contained half
## of the mode-switch handoff, so the mid-path abort mechanism in
## _execute_exploration_path() below works correctly even if the composition
## root (MainScene.gd) never calls notify_game_mode_changed() itself.
##
## Because exploration_controller.combat_triggered is emitted SYNCHRONOUSLY
## from inside move_party_member() (via _evaluate_triggers()), this handler
## runs -- and `_exploration_active` is already false -- before that
## move_party_member() call returns to _execute_exploration_path(). The
## triggering step's own animate_token_to() (issued immediately after, for
## that SAME step) still plays to completion, but every subsequent step's
## move_party_member()/animate_token_to() pair is skipped: the loop's
## post-animation `if not _exploration_active: return` check (see
## _execute_exploration_path()'s own doc) observes the flipped flag and
## halts immediately. `encounter_id` is unused -- this handler only cares
## that a trigger fired, not which encounter.
func _on_domain_combat_triggered(_encounter_id: String) -> void:
	notify_game_mode_changed(false)


## _clear_hover_preview() -> void — the single shared overlay-clearing code
## path both _on_hex_hovered()'s null case and notify_game_mode_changed()'s
## active->inactive transition funnel through (ADR-006, no duplicated
## seam). Safe to call before boot() has run (`_hex_grid_view` still null).
func _clear_hover_preview() -> void:
	if _hex_grid_view != null:
		_hex_grid_view.clear_overlays()


## _on_exploration_hex_clicked(hex_coord) -> void — FEAT-008 (US-008 / FR-010,
## ADR-005). The click-to-navigate counterpart to _on_hex_hovered() above:
## computes the FULL path (via HexPathfinderClass.find_path(), using the SAME
## cached `_is_passable_fn`/`_move_cost_fn` Callables the hover preview
## already uses, ADR-006 -- preview and execution can never disagree about
## what is passable) from the selected party member's CURRENT hex to
## `hex_coord`, then walks it via _execute_exploration_path() below.
##
## Guard clauses mirror _on_hex_hovered()'s own no-op cases exactly (never a
## crash, ADR-006 shared-guard shape): not the active mode, no party member
## selected, or an unknown selection all return immediately without touching
## `_hex_grid_view` at all.
##
## Empty path (`hex_coord` unreachable/impassable under the cached
## Callables, per HexPathfinderClass.find_path()'s own "goal impassable or
## unreachable -> []" contract) is ALSO a silent no-op -- this feature's own
## explicit requirement (US-008's "clicking an unreachable/impassable hex
## results in no movement"): `_hex_grid_view.clear_overlays()` is never
## called and _execute_exploration_path() is never entered, so a stale hover
## preview overlay (if any) is left exactly as it was rather than being wiped
## for a click that produces no movement.
##
## Otherwise: clears the overlay EXACTLY ONCE (before the walk starts, never
## per-step) and awaits _execute_exploration_path(path) to walk every step in
## order.
##
## FEAT-006 (US-006 / FR-004, mitigates RISK-001/RISK-007/RISK-010): BEFORE
## any pathfinding is attempted, this method now runs the
## DisambiguateHexClickUseCase guard clause below -- click-to-select takes
## priority over click-to-move whenever the clicked hex is occupied by a
## DIFFERENT party member than the one currently selected. See that guard's
## own inline doc for the exact three-part condition and its fall-through
## contract.
func _on_exploration_hex_clicked(hex_coord) -> void:
	if not _exploration_active:
		return
	if selected_party_member_id == "" or scenario_session == null:
		return
	if not scenario_session.party_hex_positions.has(selected_party_member_id):
		return

	# FEAT-006 (US-006 / FR-004, ADR-005/ADR-006 shared-guard shape,
	# mitigates RISK-001/RISK-007/RISK-010): DisambiguateHexClickUseCase.
	# Queries ITokenLookup (hex_grid_view.get_combatant_id_at_hex()) BEFORE
	# any pathfinding is attempted (design notes' api_contracts). Click-to-
	# select wins over click-to-move ONLY when all three hold:
	#   1. the clicked hex is occupied at all (get_combatant_id_at_hex()
	#      returns a non-empty id -- an empty click, e.g. bare terrain,
	#      never matches, RISK-010's "empty hex" edge case);
	#   2. that id is a PARTY member (IPartyMembership: present in
	#      scenario_session.party_hex_positions) -- an enemy combatant's id,
	#      or any id foreign to the party, falls straight through to move
	#      instead of ever reaching _select_party_member() (RISK-001: a
	#      click on an enemy must never silently reassign the party
	#      selection);
	#   3. that id DIFFERS from `selected_party_member_id` -- clicking the
	#      currently-selected member's OWN hex (RISK-010's "own-hex click"
	#      edge case) is deliberately EXCLUDED here so it falls through to
	#      the unchanged move/pathfinding logic below (HexPathfinder.
	#      find_path() then trivially resolves start==goal to the
	#      single-element `[start]` path, a real no-movement walk -- never a
	#      redundant re-selection call).
	#
	# `_hex_grid_view == null`, OR a wired hex_grid_view double that does
	# not implement get_combatant_id_at_hex() at all (this codebase's
	# established convention: many pre-existing GUT suites hand-write a
	# minimal, duck-typed hex_grid_view fake/spy exposing only the methods
	# a given feature's own tests need -- FEAT-001 predates this feature,
	# but not every one of those pre-existing doubles was updated to add
	# it), short-circuits this whole block via the `has_method()` guard --
	# no lookup is even attempted, so every click falls straight through to
	# move, exactly as it did before this feature (error_handling: "any
	# lookup failure ... is treated as 'fall through to move'").
	if _hex_grid_view != null and _hex_grid_view.has_method("get_combatant_id_at_hex"):
		var clicked_combatant_id: String = _hex_grid_view.get_combatant_id_at_hex(hex_coord)
		if (
			clicked_combatant_id != ""
			and scenario_session.party_hex_positions.has(clicked_combatant_id)
			and clicked_combatant_id != selected_party_member_id
		):
			_select_party_member(clicked_combatant_id)
			return

	var start_hex = scenario_session.party_hex_positions[selected_party_member_id]
	var path: Array = HexPathfinderClass.find_path(start_hex, hex_coord, _is_passable_fn, _move_cost_fn)

	if path.is_empty():
		return

	if _hex_grid_view != null:
		_hex_grid_view.clear_overlays()

	await _execute_exploration_path(path)


## _execute_exploration_path(path) -> void — FEAT-008 (US-008 / FR-010,
## ADR-005, mitigates RISK-005): walks `path` (INCLUSIVE of the starting hex
## at path[0], as produced by HexPathfinderClass.find_path()) one step at a
## time, i in range(1, path.size()):
##
##   1. exploration_controller.move_party_member(selected_party_member_id,
##      path[i]) -- the DOMAIN-side finalization (scenario_session.
##      party_hex_positions update + trigger evaluation) for this step, run
##      to completion synchronously.
##   2. ONLY once step 1 has fully returned: await
##      _hex_grid_view.animate_token_to(selected_party_member_id, path[i]) --
##      the PRESENTATION-side tween for this SAME step, awaited to genuine
##      completion (never a fixed delay, RISK-008) before the loop proceeds
##      to step i+1.
##
## This ordering (domain finalization strictly before that step's animation
## begins, and that step's animation strictly complete before the next
## step's domain finalization begins) is the ADR-005 invariant this feature
## exists to establish: a caller inspecting party_hex_positions or the
## rendered token pixel position at any point during the walk never observes
## a torn/partial step, and steps are never batched (all moves upfront, all
## animations after) -- each step's move+animate pair completes in full
## before the next pair begins.
##
## Mid-path mode-switch abort (error_handling #6, api_contracts #8, FEAT-009
## completes ADR-004's cooperative-polling contract): if `_exploration_active`
## has gone false by the time a step's animation completes (e.g. that step's
## move_party_member() synchronously fired combat_triggered, which this
## controller's own _on_domain_combat_triggered() -- connected in boot() --
## flips via notify_game_mode_changed(false) BEFORE that move_party_member()
## call even returns; a caller's separately-injected combat_triggered handler
## may ALSO independently flip mode via
## notify_game_mode_changed(false)), the loop stops immediately -- no further
## move_party_member()/animate_token_to() calls are issued, leaving the token
## at that step's hex rather than the eventual path destination.
##
## Mid-path move_party_member() rejection abort (FEAT-325, DEF-002 closure):
## if exploration_controller.move_party_member() returns false for a step
## (currently unreachable via real terrain, which is static during a walk,
## but a live risk for any future dynamic-hazard feature -- e.g. a hazard
## that becomes impassable between the click-time HexPathfinder.find_path()
## call and this step's execution), the loop halts IMMEDIATELY, BEFORE
## animate_token_to() is ever called for that same step -- mirroring
## core/application/exploration_controller.gd's own navigate_party_member()
## halt-on-failure guard. The token is left at the pixel position of the
## last successfully completed hex, and party_hex_positions reflects exactly
## that same completed progress (no torn write, no token visually animating
## to a hex the domain layer never recorded).
func _execute_exploration_path(path: Array) -> void:
	for i in range(1, path.size()):
		var step = path[i]
		var moved: bool = true
		if exploration_controller != null:
			moved = exploration_controller.move_party_member(selected_party_member_id, step)
		if not moved:
			return
		if _hex_grid_view != null:
			await _hex_grid_view.animate_token_to(selected_party_member_id, step)
		if not _exploration_active:
			return


## get_is_passable_fn() / get_move_cost_fn() -> Callable — test/inspection
## helpers (mirrors HexGridView's own get_path_overlay()/get_path_overlay_
## color() convention): the cached PassabilityQuery/MoveCostQuery Callables
## boot() built exactly once. Invalid (Callable()) until boot() has run.
func get_is_passable_fn() -> Callable:
	return _is_passable_fn


func get_move_cost_fn() -> Callable:
	return _move_cost_fn


## is_exploration_active() -> bool — test/inspection helper: this
## controller's current local mirror of "is EXPLORATION the active game
## mode" (see notify_game_mode_changed()).
func is_exploration_active() -> bool:
	return _exploration_active
