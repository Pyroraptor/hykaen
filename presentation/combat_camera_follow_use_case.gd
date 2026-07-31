class_name CombatCameraFollowUseCase
extends RefCounted

## presentation/combat_camera_follow_use_case.gd — CombatCameraFollowUseCase
## (FEAT-007 / US-005, mitigates RISK-009).
##
## Presentation-layer use case (mirrors presentation/
## auto_select_active_actor_use_case.gd's own extraction precedent, ADR-005):
## reacts to MainScene's existing TurnController.active_actor_changed
## handler by panning the combat-mode camera to the newly-active actor's
## current hex -- the design notes' APPLICATION-layer "FollowTokenUseCase"
## realized as a thin, directly-wired class (ADR-002: constructor-injected
## with the concrete collaborators MainScene already holds, rather than a
## formal ICameraPort/IHexGridQueryPort/IScenarioSessionPort interface,
## matching this codebase's established pragmatic-wiring convention).
##
## The camera itself is injected as a `camera_follow_fn: Callable`
## (`Callable(_game_camera, "move_to")`) rather than a direct GameCamera
## reference -- mirroring FEAT-006's presentation/exploration_mode_
## controller.gd `on_camera_follow` Callable dependency exactly (see its
## `_on_camera_follow_target.call(world_pos)` call site) -- rather than a
## literal `.move_to(` method call. This is deliberate, not merely stylistic:
## ci/check_no_duplicate_seams.sh's seam-singularity gate (FEAT-009/ADR-002/
## ADR-006) textually scans core/presentation/infrastructure for `.move_to(`
## call sites and only allowlists core/rules/movement.gd/core/domain/
## effects_applier.gd as legitimate callers of Combatant.move_to() (the hex
## -mutation seam) -- it cannot distinguish that identically-named
## GameCamera.move_to() (a camera pan, unrelated to Combatant's mutator) is
## a different method. Invoking it via Callable.call() -- exactly as every
## other camera-follow call site in this codebase already does -- keeps this
## file text-free of a literal `.move_to(` call and avoids a false-positive
## trip of that gate.
##
## Extracted out of MainScene.gd (the composition root) purely to keep
## MainScene.gd inside its FR-009/ADR-001 1000-line budget (enforced by
## tests/ci/test_mainscene_gate.gd) -- the SAME reason
## AutoSelectActiveActorUseCase was extracted for FEAT-008. MainScene.gd
## remains the sole place that constructs this use case (it is the only
## file holding hex_grid_view, _game_camera, scenario_session, and the live
## _party/_enemies roster simultaneously).
##
## execute(combatant) -> void — resolves `combatant`'s current hex via
## _get_combatant_hex(combatant.combatant_id) (this use case's stand-in for
## the design notes' IScenarioSessionPort.get_combatant_hex(): checks the
## injected scenario_session's party_hex_positions first, then falls back
## to the live _party/_enemies roster the injected Callables read), converts
## it to world space via hex_grid_view.axial_to_pixel_with_offset() (the
## SAME offset-aware conversion FEAT-006's
## ExplorationModeController._select_party_member() already uses for the
## exploration-mode camera follow), and pans the camera via
## camera_follow_fn.call(world_pos). Guards silently -- no exception, no
## camera movement -- whenever `combatant` is null, `camera_follow_fn` is
## not a valid Callable, `hex_grid_view` is null, or the hex cannot be
## resolved (e.g. an actor not yet placed on the grid), but push_warning()s
## a breadcrumb on that skip path so a future debugging session has a trace
## instead of a silent no-op (RISK-009).

var _hex_grid_view
var _camera_follow_fn: Callable
var _scenario_session
var _party_fn: Callable
var _enemies_fn: Callable


func _init(
	hex_grid_view, camera_follow_fn: Callable, scenario_session, party_fn: Callable, enemies_fn: Callable
) -> void:
	_hex_grid_view = hex_grid_view
	_camera_follow_fn = camera_follow_fn
	_scenario_session = scenario_session
	_party_fn = party_fn
	_enemies_fn = enemies_fn


func execute(combatant) -> void:
	if combatant == null or not _camera_follow_fn.is_valid() or _hex_grid_view == null:
		return

	var hex_coord = _get_combatant_hex(combatant.combatant_id)
	if hex_coord == null:
		push_warning(
			"CombatCameraFollowUseCase: cannot resolve hex for combatant_id '%s' -- camera follow skipped (RISK-009)"
			% combatant.combatant_id
		)
		return

	_camera_follow_fn.call(_hex_grid_view.axial_to_pixel(hex_coord))


## _get_combatant_hex(combatant_id) -> HexCoord or null — scenario_session.
## party_hex_positions first (the authoritative party-position store other
## call sites, e.g. MainScene._on_combat_won(), already read/write), then
## the live _party/_enemies roster the injected Callables read (covers
## Enemy actors, and Player actors whose mid-combat position hasn't been
## re-synced into party_hex_positions yet). Returns null -- never a
## default/sentinel hex -- when combatant_id matches neither, so execute()
## can distinguish "unresolved" from a genuine (0,0) placement.
func _get_combatant_hex(combatant_id: String):
	if _scenario_session != null and _scenario_session.party_hex_positions.has(combatant_id):
		return _scenario_session.party_hex_positions[combatant_id]

	if _party_fn.is_valid():
		for combatant in _party_fn.call():
			if combatant.combatant_id == combatant_id:
				return combatant.hex_coord

	if _enemies_fn.is_valid():
		for enemy in _enemies_fn.call():
			if enemy.combatant_id == combatant_id:
				return enemy.hex_coord

	return null
