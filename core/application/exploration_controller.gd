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
## FEAT-004 (US-004 / FR-008): navigate_party_member(combatant_id, path) -> int
##     Walks a precomputed multi-hex path (path[0] == the combatant's
##     current hex) via repeated move_party_member() calls, one step at a
##     time. Returns -1 with zero mutation on a mismatched/empty path;
##     otherwise returns the index of the last step actually reached
##     (path.size() - 1 on full completion, or an earlier index if halted
##     by an impassable step or a synchronous combat_triggered emission).
##     See navigate_party_member()'s own doc comment below for the full
##     outcome table.
##
## FEAT-003 (US-003 / FR-007, ADR-003): move_party_member() now ALSO
## enforces tile passability, but ONLY when an EncounterResource is
## injected via the constructor's optional trailing `encounter` parameter.
## When no encounter is injected (the parameter stays null, its default),
## behavior is byte-for-byte identical to pre-iteration: adjacency is the
## only precondition (RISK-007 mitigation, see this feature's explicit
## regression test in
## tests/unit/core/application/test_exploration_controller_pathfinding.gd).
## When an encounter IS injected, the constructor builds a PassabilityQuery
## Callable via core/geometry/encounter_tile_adapter.gd's
## EncounterTileAdapter.make_is_passable(encounter) — the application layer
## never touches EncounterResource/HexTileDataResource's schema directly,
## only the Callable port shape (Clean Architecture: this file stays
## application-layer, EncounterTileAdapter is the infrastructure/adapter
## translation boundary). Ordering invariant (S0-4a): the passability check
## runs strictly AFTER the adjacency check and strictly BEFORE any
## party_hex_positions mutation — see move_party_member() below.
##
## Usage:
##   var controller := ExplorationController.new(session)
##   controller.combat_triggered.connect(_on_combat_triggered)
##   var moved: bool = controller.move_party_member("hero", HexCoord.new(1, 0))
##
##   # With passability enforcement (FEAT-003):
##   var controller := ExplorationController.new(session, encounter)
##   var moved: bool = controller.move_party_member("hero", HexCoord.new(1, 0))

class_name ExplorationController
extends RefCounted

const HexMathClass = preload("res://core/geometry/hex_math.gd")
const TriggerTypeClass = preload("res://core/domain/trigger_type.gd")
const EncounterTileAdapterClass = preload("res://core/geometry/encounter_tile_adapter.gd")

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

## PassabilityQuery port Callable (HexCoord) -> bool, built from the
## injected `encounter` at construction time via EncounterTileAdapter
## (FEAT-003). Stays null when no encounter is injected — move_party_member()
## treats a null _is_passable as "passability enforcement is inert",
## preserving pre-iteration no-encounter behavior exactly (RISK-007).
var _is_passable

## The ScenarioSession is a REQUIRED collaborator (there is no meaningful
## "no session" mode for an exploration controller), injected via the
## constructor rather than defaulted, matching this codebase's established
## constructor-injection convention for mandatory dependencies.
##
## `encounter` (FEAT-003 / US-003, ADR-003) is an OPTIONAL trailing
## parameter defaulting to null — existing single-argument call sites
## (`ExplorationController.new(session)`) are entirely unaffected. When a
## non-null EncounterResource is supplied, this constructor builds the
## PassabilityQuery Callable used by move_party_member() below via
## EncounterTileAdapter.make_is_passable(encounter); when null, passability
## enforcement stays inert (NFR-001).
func _init(session, encounter = null) -> void:
	_session = session
	if encounter != null:
		_is_passable = EncounterTileAdapterClass.make_is_passable(encounter)


## move_party_member(combatant_id, target_hex) -> bool
##
## FAIL-CLOSED, no-exception movement (design notes' api_contracts #1 and
## #3, FEAT-003 extension):
##   - combatant_id not present in _session.party_hex_positions -> returns
##     false, no mutation.
##   - target_hex not exactly hex-distance 1 from the combatant's current
##     hex -> returns false, no mutation.
##   - an encounter was injected (constructor's optional `encounter` param)
##     AND _is_passable.call(target_hex) is false -> returns false, no
##     mutation. This check runs strictly AFTER the adjacency check above
##     and strictly BEFORE the mutation below (S0-4a ordering invariant).
##     When no encounter was injected, _is_passable is null and this check
##     is entirely skipped — adjacency remains the only precondition,
##     byte-for-byte matching pre-iteration behavior (RISK-007).
##   - otherwise: _session.party_hex_positions[combatant_id] is updated to
##     target_hex, _evaluate_triggers(target_hex) runs (which may emit
##     combat_triggered at most once), and true is returned.
func move_party_member(combatant_id: String, target_hex) -> bool:
	if not _session.party_hex_positions.has(combatant_id):
		return false

	var current_hex = _session.party_hex_positions[combatant_id]

	if HexMathClass.hex_distance(current_hex, target_hex) != 1:
		return false

	# FEAT-003 / US-003 / FR-007 (ADR-003, S0-4a ordering invariant): the
	# passability check runs strictly AFTER the adjacency check above and
	# strictly BEFORE any party_hex_positions mutation below. Inert
	# (_is_passable == null) when no encounter was injected, preserving
	# pre-iteration no-encounter behavior exactly (RISK-007).
	if _is_passable != null and not _is_passable.call(target_hex):
		return false

	_session.party_hex_positions[combatant_id] = target_hex
	_evaluate_triggers(target_hex)
	return true


## navigate_party_member(combatant_id, path) -> int
##
## FEAT-004 (US-004 / FR-008): walks a precomputed multi-hex `path` (an
## Array of HexCoord, INCLUSIVE of the combatant's starting hex at
## path[0], as produced by core/geometry/hex_pathfinder.gd's
## HexPathfinder.find_path()) one step at a time via repeated
## move_party_member() calls. This establishes the domain-side
## finalization ordering contract later consumed by animation code
## (mitigates RISK-002): each step is fully finalized in
## _session.party_hex_positions (and any trigger evaluated) strictly
## BEFORE the next step is attempted, so a caller inspecting
## party_hex_positions between steps never observes a torn/partial hex.
##
## Outcomes (design notes' api_contracts #4):
##   - path.is_empty(), OR combatant_id is unknown, OR path[0] does not
##     equal the combatant's CURRENT hex -> returns -1, with ZERO mutation
##     (not even the first step is attempted).
##   - every step succeeds -> returns path.size() - 1 (the goal's index),
##     with _session.party_hex_positions[combatant_id] left at the goal
##     hex.
##   - a move_party_member() call mid-path returns false (e.g. an
##     impassable step, FEAT-003) -> navigation halts immediately; returns
##     the index of the LAST successfully completed step;
##     _session.party_hex_positions reflects exactly that partial progress
##     (no torn writes -- each completed step was already fully finalized
##     by move_party_member() itself before the next step began).
##   - combat_triggered fires SYNCHRONOUSLY inside a move_party_member()
##     call mid-path -> navigation halts immediately after that step;
##     returns the triggering step's index (that step's move already
##     completed fully -- party_hex_positions IS updated to that step's
##     hex; the caller/controller layer observes the mode flip via
##     game-mode state, not via this return value).
func navigate_party_member(combatant_id: String, path: Array) -> int:
	if path.is_empty():
		return -1
	if not _session.party_hex_positions.has(combatant_id):
		return -1

	var current_hex = _session.party_hex_positions[combatant_id]
	if not path[0].equals(current_hex):
		return -1

	# Watches combat_triggered for the duration of this call only, so a
	# synchronous emission from _evaluate_triggers() (invoked inside
	# move_party_member() below) can be observed immediately after each
	# step, without navigate_party_member() itself needing any knowledge of
	# trigger/encounter internals (Clean Architecture: this stays a pure
	# orchestration loop over the existing move_party_member() contract).
	# `trigger_fired` is a single-element-appended Array (not a plain bool)
	# because GDScript lambdas capture outer scalars by value, not by
	# reference -- appending to a captured Array/container is the
	# established mutable-closure pattern this codebase already uses (see
	# e.g. core/application/combine_queue_build_session.gd's
	# `aborted.connect(func(): abort_signals.append(true))`).
	var trigger_fired: Array = []
	var on_trigger := func(_encounter_id): trigger_fired.append(true)
	combat_triggered.connect(on_trigger)

	var last_completed_index := 0
	for i in range(1, path.size()):
		var moved: bool = move_party_member(combatant_id, path[i])
		if not moved:
			break
		last_completed_index = i
		if not trigger_fired.is_empty():
			break

	combat_triggered.disconnect(on_trigger)
	return last_completed_index


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
