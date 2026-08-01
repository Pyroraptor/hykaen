## presentation/equipment_panel_toggle_controller.gd —
## EquipmentPanelToggleController (FEAT-010 / US-011 / FR-010, mitigates
## RISK-007).
##
## Presentation layer (Clean Architecture): the 'E' key open/close affordance
## for the FEAT-009 EquipmentPanelUI (presentation/equipment_panel_ui.gd),
## extracted out of MainScene.gd entirely -- the composition root sits
## exactly at its <=1000-line budget (ADR-001, ci/check_mainscene_gate.sh),
## so this feature's whole open/closed state machine AND its "which
## CharacterResource does the currently selected party member map to" lookup
## live here instead, mirroring presentation/cancel_controller.gd's identical
## "no companion .tscn, instantiated directly by the composition root, plain
## RefCounted, never added to the scene tree" precedent -- MainScene.gd only
## owns a single instance of this class plus the `equipment_panel_ui` node
## reference and forwards every input event to handle_input() below.
##
## No collaborators are injected up front via a configure() step (unlike
## CancelController) -- handle_input()/toggle() instead take `panel`,
## `exploration`, `scenario_session`, and `party` as plain parameters on
## every call, so MainScene.gd's own composition-root wiring stays a single
## expression inside its existing _unhandled_input() rather than growing a
## new _ready()-time wiring block (further budget economy).
##
## Character resolution (_resolve_character()): `party` (the live Combatant
## roster) carries no CharacterResource reference of its own -- CombatantFactory
## flattens a CharacterResource into a plain combat-stat Dictionary/Combatant
## (infrastructure/combatant_factory.gd) -- so resolution is by POSITION
## instead: `party[i]`'s combatant_id is matched against `exploration.
## selected_party_member_id`, and that SAME index `i` looks up
## `scenario_session.scenario.party.character_resource_paths[i]` (ADR-002's
## scenario-authoritative party roster, data/characters/party_resource.gd) --
## valid because both `party` and `character_resource_paths` are built from
## that identical, ordered roster (data/parties/default_party.tres for the
## prologue fixture; data/encounters/prologue_encounter.tres's own
## party_resource_paths authors the SAME two character paths in the SAME
## order).
##
## Returns null (never crashes) for every "can't resolve" case -- no
## selection, no booted scenario/party, no matching `party` entry, or an
## index with no corresponding character_resource_paths entry -- the
## null-dereference-prevention guard toggle() relies on (US-011's security
## note, RISK-007's dedicated negative-case test).
class_name EquipmentPanelToggleController
extends RefCounted

## true while the panel is currently open (shown + populated via setup()).
## EquipmentPanelUI itself has no "is this open" query of its own (a dumb
## render target, see its own doc) -- this is the sole open/closed mirror.
var _open: bool = false


## is_open() -> bool — test/inspection helper.
func is_open() -> bool:
	return _open


## handle_input(event, panel, exploration, scenario_session, party) -> bool
## -- translates a fresh (non-echo) 'E' keydown into toggle(); returns
## whether `event` even named an 'E' keydown at all (mirrors
## CancelController.handle_input()'s own "was this event even ours"
## contract), regardless of whether toggle() itself ended up doing
## anything (a no-op toggle -- e.g. no party member selected -- still
## consumes the keypress).
func handle_input(event: InputEvent, panel, exploration, scenario_session, party: Array) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E):
		return false
	toggle(panel, exploration, scenario_session, party)
	return true


## toggle(panel, exploration, scenario_session, party) -> void
##
## While open: hides `panel` and calls clear() (discarding any rendered item
## data), then flips `_open` false. No character lookup is attempted on this
## branch -- closing never depends on who is currently selected.
##
## While closed: resolves the currently selected party member's
## CharacterResource via _resolve_character() below. A null resolution --
## most commonly "no party member selected" (US-011's own explicit no-op
## requirement) -- is a silent no-op: `panel` is neither shown nor toggled,
## and `_open` stays false. Only a successful resolution calls setup() and
## reveals the panel.
func toggle(panel, exploration, scenario_session, party: Array) -> void:
	if panel == null:
		return

	if _open:
		panel.clear()
		panel.visible = false
		_open = false
		return

	var character = _resolve_character(exploration, scenario_session, party)
	if character == null:
		return

	panel.setup(character)
	panel.visible = true
	_open = true


## refresh_for_active_actor(combatant, panel, scenario_session, party) -> void
## -- FEAT-365 (US-011 / FR-011, resolves PR-001): TurnController's
## active_actor_changed reaction. Closes the FR-011 gap called out in peer
## review -- MainScene._on_active_actor_changed() previously never touched
## the FEAT-009/FEAT-010 equipment panel at all.
##
## Null/no-actor changes and a currently-CLOSED panel are both safe no-ops
## (mirrors toggle()'s own null-guard convention above) -- this method never
## auto-OPENS the panel; it only refreshes or auto-closes an ALREADY-open
## one, per this feature's test_criteria.
##
## While open and `combatant` is a non-player-team actor (combatant.is_enemy,
## e.g. an enemy's turn starts): hides `panel` and calls clear() exactly like
## toggle()'s closing branch, so no stale gear data from the previously
## displayed party member is left visible during an enemy turn.
##
## While open and `combatant` is a player-team actor: resolves `combatant`'s
## own CharacterResource by POSITION (mirrors _resolve_character()'s
## `party`/`character_resource_paths` convention below, keyed off
## `combatant.display_id()` instead of `exploration.selected_party_member_id`
## -- the active actor need not be the exploration-mode selection). A null
## resolution (no matching party entry) leaves the panel's current contents
## untouched rather than clearing them -- this is not a "no selection"
## no-op case, just an unresolvable lookup, so it fails safe by doing
## nothing further.
func refresh_for_active_actor(combatant, panel, scenario_session, party: Array) -> void:
	if panel == null or combatant == null or not _open:
		return

	if combatant.is_enemy:
		panel.clear()
		panel.visible = false
		_open = false
		return

	var character = _resolve_character_by_id(combatant.display_id(), scenario_session, party)
	if character == null:
		return

	panel.setup(character)


## _resolve_character(exploration, scenario_session, party) ->
## CharacterResource|null — see file-level doc for the full by-position
## resolution contract.
func _resolve_character(exploration, scenario_session, party: Array):
	var selected_id: String = exploration.selected_party_member_id if exploration != null else ""
	return _resolve_character_by_id(selected_id, scenario_session, party)


## _resolve_character_by_id(selected_id, scenario_session, party) ->
## CharacterResource|null -- the shared by-position resolution body behind
## both _resolve_character() (keyed off exploration.selected_party_member_id)
## and refresh_for_active_actor() (keyed off combatant.display_id()). See
## file-level doc for the full "why POSITION, not a direct reference"
## rationale.
func _resolve_character_by_id(selected_id: String, scenario_session, party: Array):
	if selected_id == "":
		return null

	var scenario = scenario_session.scenario if scenario_session != null else null
	if scenario == null or scenario.party == null:
		return null

	var character_paths: Array = scenario.party.character_resource_paths
	for i in range(party.size()):
		var member = party[i]
		if member != null and member.display_id() == selected_id:
			return ResourceLoader.load(character_paths[i]) if i < character_paths.size() else null

	return null
