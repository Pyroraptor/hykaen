class_name AutoSelectActiveActorUseCase
extends RefCounted

## presentation/auto_select_active_actor_use_case.gd — AutoSelectActiveActorUseCase
## (FEAT-008 / US-008, FR-008, ADR-005).
##
## Reacts to TurnController's existing `active_actor_changed(actor)` signal
## (consumed, not produced, by this feature -- see design notes'
## api_contracts #8): whenever the newly-active actor is a PARTY member,
## mirrors that actor's combatant_id onto BOTH hex_grid_view.
## set_selected_combatant() and status_panel_view.set_selected_combatant(),
## keeping the ring (hex_grid_view) and the gold status-panel highlight in
## lockstep (invariant: hex_grid_view.get_selected_combatant() ==
## status_panel_view.get_selected_combatant_id() after every call). An
## ENEMY actor becoming active is a deliberate no-op -- both selections are
## left exactly as they were -- per RISK-002 (avoiding flicker/race
## conditions from mutating selection mid-signal on turns the player does
## not control).
##
## Extracted out of MainScene.gd (the composition root) purely to keep
## MainScene.gd inside its FR-009/ADR-001 1000-line budget (enforced by
## tests/ci/test_mainscene_gate.gd) -- mirroring the precedent already set
## by presentation/turn_presentation_controller.gd's own extraction. ADR-005
## explains why this use case's LOGIC is a thin, directly-wired call rather
## than a multi-port abstraction (ISelectionRenderer/ISelectionHighlighter
## are satisfied structurally by HexGridView/StatusPanelView, not via a
## formal interface), not that it must be textually inlined into
## MainScene.gd's own body. MainScene.gd remains the sole place that
## constructs this use case (it is the only file holding both hex_grid_view
## and status_panel_view references simultaneously), so it is still, in
## spirit, "the composition root's use case."

var _hex_grid_view
var _status_panel_view
var _party_fn: Callable


func _init(hex_grid_view, status_panel_view, party_fn: Callable) -> void:
	_hex_grid_view = hex_grid_view
	_status_panel_view = status_panel_view
	_party_fn = party_fn


## execute(combatant) -> void — no-op when combatant is null or is not a
## party member (covers the enemy-turn case: enemies are never present in
## the roster `_party_fn` returns). Otherwise pushes combatant.combatant_id
## to both collaborators, in this fixed order (hex_grid_view first, then
## status_panel_view), matching the precedent set by
## presentation/exploration_mode_controller.gd's _select_party_member().
func execute(combatant) -> void:
	if combatant == null:
		return
	if not _is_party_member(combatant.combatant_id):
		return

	var active_combatant_id: String = combatant.combatant_id
	if _hex_grid_view != null:
		_hex_grid_view.set_selected_combatant(active_combatant_id)
	if _status_panel_view != null:
		_status_panel_view.set_selected_combatant(active_combatant_id)


## _is_party_member(combatant_id) -> bool — true iff combatant_id belongs to
## a combatant currently seated in the live roster `_party_fn` returns (the
## IPartyMembership check the design notes call for, realized directly
## against the live roster rather than a separate scenario_session-backed
## adapter, since combat-mode party membership is exactly "is this
## combatant_id one of `_party`'s entries").
func _is_party_member(combatant_id: String) -> bool:
	for member in _party_fn.call():
		if member.combatant_id == combatant_id:
			return true
	return false
