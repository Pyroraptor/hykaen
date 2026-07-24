## core/application/exploration_controller.gd — ExplorationController
## use-case orchestrator (FEAT-005 / US-004, FR-002)
##
## Application layer (Clean Architecture / ADR-001): extends RefCounted only
## — no Node/Control/CanvasItem inheritance, no engine lifecycle callbacks
## (_ready/_process/_physics_process), no engine I/O, and NO imports from
## presentation/ or MainScene.gd. Depends only on the injected
## core/application/scenario_session.gd ScenarioSession and the DOMAIN-layer
## core/geometry/hex_coord.gd / core/geometry/hex_math.gd /
## core/domain/trigger_type.gd value objects — never on a concrete
## Node/Control type. This directly mitigates
## RISK-002 (accidental Node/Presentation coupling); see
## tests/unit/test_exploration_controller.gd's dedicated source-scan test.
##
## Two responsibilities, both use-case orchestration over the injected
## ScenarioSession (never owning state itself beyond the session reference):
##
##   move_party_member(combatant_id, target_hex) -> bool
##     Single-hex-adjacency movement, FAIL-CLOSED (mirrors
##     ScenarioSession.mark_encounter_complete's dangling-id guard
##     philosophy, design notes' error_handling #1 "fail-closed
##     no-mutation"): an unknown combatant_id or a non-adjacent target_hex
##     leaves session.party_hex_positions completely untouched and returns
##     false — no exception, no partial write. A successful move updates
##     session.party_hex_positions[combatant_id] to target_hex, THEN runs
##     trigger evaluation, THEN returns true.
##
##   combat_triggered(encounter_id: String) [signal]
##     Emitted by _evaluate_triggers() at most once per successful move
##     (first-match-wins over session.get_active_encounter_entries()'s
##     authored order — ADR-005), and only for entries whose trigger fires
##     (i.e. never for an entry already excluded by
##     get_active_encounter_entries() because it is in
##     session.completed_encounter_ids — that exclusion is enforced once,
##     at the ScenarioSession boundary, per design notes' error_handling #3
##     "the invariant is enforced once ... not re-checked ad hoc").
##
## TODO (deferred, RISK-007 / ADR-006 mitigation): move_party_member()'s
## adjacency check does NOT enforce hex passability/terrain blocking this
## iteration — any adjacent hex is a legal move target regardless of
## authored tile data (e.g. HexTileDataResource walkability). Passability
## enforcement is an explicitly deferred backlog item; when it lands it
## belongs here, as an additional precondition alongside the adjacency
## check below, not bolted on elsewhere.
##
## Usage:
##   var controller := ExplorationController.new(session)
##   controller.combat_triggered.connect(_on_combat_triggered)
##   var moved: bool = controller.move_party_member("hero", HexCoord.new(1, 0))

class_name ExplorationController
extends RefCounted

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const TriggerTypeClass = preload("res://core/domain/trigger_type.gd")

## Emitted at most once per successful move (first-match-wins, ADR-005),
## carrying the encounter_id of the ScenarioEncounterEntryResource whose
## trigger fired. Never emitted for a move that itself failed (unknown
## combatant_id / non-adjacent target_hex).
signal combat_triggered(encounter_id: String)

## The injected ScenarioSession this controller orchestrates movement and
## trigger evaluation against. A reference, not a copy — mutations this
## controller makes to session.party_hex_positions are visible to any other
## holder of the same session instance.
var _session

## The ScenarioSession is a REQUIRED collaborator (there is no meaningful
## "no session" mode for an exploration controller), injected via the
## constructor rather than defaulted, matching this codebase's established
## constructor-injection convention for mandatory dependencies.
func _init(session) -> void:
	_session = session


## move_party_member(combatant_id, target_hex) -> bool
##
## FAIL-CLOSED, no-exception movement (design notes' api_contracts #1):
##   - combatant_id not present in _session.party_hex_positions -> returns
##     false, no mutation.
##   - target_hex not exactly hex-distance 1 from the combatant's current
##     hex -> returns false, no mutation.
##   - otherwise: _session.party_hex_positions[combatant_id] is updated to
##     target_hex, _evaluate_triggers(target_hex) runs (which may emit
##     combat_triggered at most once), and true is returned.
func move_party_member(combatant_id: String, target_hex) -> bool:
	if not _session.party_hex_positions.has(combatant_id):
		return false

	var current_hex = _session.party_hex_positions[combatant_id]

	# TODO(RISK-007 / ADR-006): passability/terrain-blocking enforcement is
	# deferred — this only checks adjacency, never authored tile
	# walkability. See file-level doc for the full deferred-scope note.
	if HexMathClass.hex_distance(current_hex, target_hex) != 1:
		return false

	_session.party_hex_positions[combatant_id] = target_hex
	_evaluate_triggers(target_hex)
	return true


## _evaluate_triggers(target_hex) -> void
##
## First-match-wins (ADR-005) scan over _session.get_active_encounter_entries()
## (already excludes any entry whose encounter_id is in
## _session.completed_encounter_ids — see ScenarioSession's own contract),
## in authored order. For each entry carrying a non-null PROXIMITY trigger,
## checks whether `target_hex` is a member of trigger.trigger_hexes (each
## stored as a {"q": int, "r": int} Dictionary per
## ProximityTriggerResource's schema). The FIRST entry whose trigger_hexes
## contains `target_hex` emits combat_triggered(entry.encounter_id) and the
## scan stops immediately — at most one emission per call, guaranteeing
## single-fire-per-move even when two active entries' trigger_hexes overlap.
func _evaluate_triggers(target_hex) -> void:
	for entry in _session.get_active_encounter_entries():
		var trigger = entry.trigger
		if trigger == null:
			continue
		if trigger.trigger_type != TriggerTypeClass.PROXIMITY:
			continue
		if _hex_in_trigger_hexes(target_hex, trigger.trigger_hexes):
			combat_triggered.emit(entry.encounter_id)
			return


## _hex_in_trigger_hexes(target_hex, trigger_hexes) -> bool
##
## true iff `target_hex` (q, r) matches one of the {"q": int, "r": int}
## Dictionaries in `trigger_hexes` (ProximityTriggerResource's authored
## schema — see data/triggers/proximity_trigger_resource.gd) by exact
## coordinate equality.
func _hex_in_trigger_hexes(target_hex, trigger_hexes: Array) -> bool:
	for hex_dict in trigger_hexes:
		if int(hex_dict.get("q", 0)) == target_hex.q and int(hex_dict.get("r", 0)) == target_hex.r:
			return true
	return false
