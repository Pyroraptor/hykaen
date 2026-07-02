## scenes/battlefield/StrikeInputController.gd — StrikeInputController
## (FEAT-007 / US-007)
##
## Presentation layer (Clean Architecture): the player-facing controller that
## lets the active combatant select Strike as their one action and choose an
## in-range target directly against the hex battlefield (scenes/battlefield/
## HexBattlefield.gd, FEAT-005 -- optional collaborator, see below) and the
## turn-order surface it sits alongside (scenes/battlefield/TurnOrderWidget.gd,
## FEAT-006).
##
## FEAT-010 / US-010: lock()/is_locked() add a persistent, sticky
## post-resolution guard -- once scenes/battlefield/ResultScreen.gd (FEAT-010)
## observes an EncounterResultEvent it calls lock() here, after which
## select_target() always rejects with ERR_ENCOUNTER_ALREADY_RESOLVED
## regardless of any later configure() call. This is deliberately independent
## of (and stickier than) the existing "clear via configure({}, ...)"
## technique the prior iteration's presentation/result_screen_view.gd used --
## it survives a stray reconfigure() (e.g. a leftover TurnController signal)
## after the encounter has already concluded (defense in depth, mirroring the
## error_handling design note's "ENCOUNTER_ALREADY_RESOLVED is a defensive
## domain-level guard behind [the UI guard], in case the UI guard is
## bypassed").
##
## Mirrors the target-selection affordance already established by the prior
## iteration's presentation/strike_action_control.gd, but:
##   1. When a HexBattlefield is supplied, reuses ITS already-loaded position
##      data (get_hex_coord()) as the single source of truth for the actor's
##      and every candidate's hex position, instead of requiring every
##      Dictionary to carry a duplicated "hex_coord" key. Falling back to a
##      Dictionary's own "hex_coord" key (or none) when no battlefield is
##      supplied lets this controller be configured and exercised in complete
##      isolation, exactly as the tests below do.
##   2. Marks in-range/out-of-range candidates visually on the HexBattlefield
##      itself (set_selectable_combatant_ids()) so the UI visibly disallows
##      choosing an out-of-range target, not merely omitting an unused
##      control.
##   3. Surfaces every resolve_action_use_case error response (the acting
##      combatant is not the currently active one / the action budget is
##      exhausted / the target is out of range) as a non-blocking inline
##      message (get_last_error_message()) instead of silently no-oping or
##      crashing. The combatant's turn/this controller's own state is left
##      exactly as it was -- the player may simply choose a different target
##      or retry; no use case advancing the round is ever called from here.
##
## StrikeInputController performs NO hit/damage computation of its own. Its
## ONLY combat-adjacent computation is calling the SAME domain function the
## Application layer already uses internally (core/geometry/hex_math.gd
## HexMath.hex_neighbors()) to decide what the UI *offers* -- a UX affordance
## only (ADR-001). The actual Strike is always resolved by forwarding to the
## injected, REUSED resolve_action_use_case (core/application/
## resolve_action_use_case.gd, ADR-002/ADR-003: no forked/duplicate action
## path exists here) -- the domain re-validates every precondition
## regardless of what this controller pre-filtered (defense in depth); this
## controller's own filtering is never the source of truth.

class_name StrikeInputController
extends RefCounted

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## The one melee action this controller ever spends (US-007's "Strike" steel
## thread action).
const ACTION_NAME: String = "Strike"

## Local rejection code returned by select_target() when target_id does not
## name one of the currently in-range (selectable) candidates -- rejected
## HERE, before resolve_action_use_case is ever invoked: no action-budget
## spend, no event emission, no use-case call at all.
const ERR_TARGET_NOT_SELECTABLE: String = "ERR_TARGET_NOT_SELECTABLE"

## FEAT-010 / US-010: local/defensive rejection code returned by
## select_target() once lock() has been called (see file-level doc) --
## mirrors scenes/battlefield/EndTurnController.gd's identically-named
## contract.
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

## Human-readable inline messages for every error code
## resolve_action_use_case.resolve() (core/application/resolve_action_use_case.gd)
## may return, plus this controller's own local rejection codes above.
const _ERROR_MESSAGES: Dictionary = {
	"ERR_NOT_ACTIVE_COMBATANT": "It isn't your turn -- that action was not taken.",
	"ERR_NO_ACTION_REMAINING":  "No actions remain this round -- that action was not taken.",
	"ERR_TARGET_NOT_ADJACENT":  "That target is out of range -- pick an adjacent target.",
	"ERR_TARGET_INVALID":       "That target is no longer valid.",
	ERR_TARGET_NOT_SELECTABLE: "That target is out of range -- pick an adjacent target.",
	ERR_ENCOUNTER_ALREADY_RESOLVED: "The encounter has already been resolved -- no further actions can be taken.",
}

const _DEFAULT_ERROR_MESSAGE: String = "That action could not be completed -- your turn is still active."

## strike_resolved(result) -- emitted after select_target() successfully
## invokes resolve_action_use_case.resolve(), carrying that call's full
## result Dictionary.
signal strike_resolved(result: Dictionary)

## action_error(message) -- emitted whenever select_target() is rejected,
## whether locally (an out-of-range/unknown target) or by
## resolve_action_use_case itself, carrying the same human-readable message
## get_last_error_message() returns. No subscriber is required.
signal action_error(message: String)

## The acting combatant Dictionary (as passed to configure()).
var _actor: Dictionary = {}

## The actor's ActionEconomy instance (core/rules/action_economy.gd),
## injected -- never constructed here.
var _action_economy = null

## The injected, REUSED resolve_action_use_case (core/application/
## resolve_action_use_case.gd) -- never constructed or forked here.
var _resolve_action_use_case = null

## The identifier of the combatant the caller asserts is CURRENTLY active
## (e.g. the current turn owner) -- forwarded verbatim as
## resolve_action_use_case.resolve()'s active_combatant_id argument so the
## domain can enforce turn order (defense in depth). "" (the default) means
## no such assertion is made.
var _active_combatant_id: String = ""

var _round_number: int = 1
var _cycle_index: int = 0

## The optional HexBattlefield collaborator (scenes/battlefield/
## HexBattlefield.gd) this controller reads position data from and reports
## selectable/not-selectable targets to.
var _battlefield = null

## The candidate targets currently in range -- exactly the subset of the
## last configure() call's candidate_targets whose position is one of the
## actor's 6 flat-top axial neighbors (HexMath.hex_neighbors()).
var _selectable_targets: Array = []

## The candidate targets currently NOT in range (the complement of
## _selectable_targets within the last configure() call's candidate_targets).
var _non_selectable_targets: Array = []

var _last_error_code: String = ""
var _last_error_message: String = ""

## FEAT-010 / US-010: true once lock() has been called -- sticky across any
## later configure() call (see file-level doc). select_target() always
## rejects with ERR_ENCOUNTER_ALREADY_RESOLVED while true.
var _locked: bool = false


## lock() -> void -- permanently locks this controller (FEAT-010 / US-010):
## every subsequent select_target() call is rejected with
## ERR_ENCOUNTER_ALREADY_RESOLVED, regardless of any later configure() call.
## Intended to be called exactly once, by scenes/battlefield/ResultScreen.gd,
## the moment an EncounterResultEvent is observed. There is no unlock() --
## this steel thread never continues a round past resolution.
func lock() -> void:
	_locked = true


## is_locked() -> bool -- true once lock() has been called.
func is_locked() -> bool:
	return _locked


## configure(actor, action_economy, resolve_action_use_case,
##           candidate_targets, active_combatant_id, round_number,
##           cycle_index, battlefield) -> void
##
## actor                -- the acting combatant Dictionary. Duck-typed to
##                          match resolve_action_use_case.resolve()'s
##                          `combatant` parameter shape; MAY carry a
##                          "hex_coord" key, used when `battlefield` is null
##                          or has no position on record for this actor.
## action_economy       -- the actor's ActionEconomy instance for this round.
## resolve_action_use_case -- the injected, REUSED use case instance this
##                          controller forwards a selected Strike to.
## candidate_targets    -- Array of target Dictionaries (enemies), each MAY
##                          carry "hex_coord". Re-filtered into
##                          _selectable_targets/_non_selectable_targets on
##                          every call (no leaked state from a prior
##                          configure()/turn).
## active_combatant_id  -- OPTIONAL; forwarded to resolve_action_use_case so
##                          it can reject an out-of-turn Strike
##                          (ERR_NOT_ACTIVE_COMBATANT). Defaults to "" (no
##                          assertion made).
## round_number/cycle_index -- stamped on the resolved AttackEvent/history
##                          entry exactly as resolve_action_use_case expects.
## battlefield           -- OPTIONAL HexBattlefield (scenes/battlefield/
##                          HexBattlefield.gd). When supplied, its
##                          get_hex_coord() is preferred over a Dictionary's
##                          own "hex_coord" key, and it is told which
##                          candidates are currently selectable/not via
##                          set_selectable_combatant_ids() so the UI visibly
##                          disallows an out-of-range target.
func configure(
	actor: Dictionary,
	action_economy,
	resolve_action_use_case,
	candidate_targets: Array,
	active_combatant_id: String = "",
	round_number: int = 1,
	cycle_index: int = 0,
	battlefield = null
) -> void:
	_actor = actor
	_action_economy = action_economy
	_resolve_action_use_case = resolve_action_use_case
	_active_combatant_id = active_combatant_id
	_round_number = round_number
	_cycle_index = cycle_index
	_battlefield = battlefield
	_last_error_code = ""
	_last_error_message = ""
	_rebuild_targets(candidate_targets)


## get_selectable_target_ids() -> Array[String] -- the target_id (see
## _target_id()) of every currently selectable (in-range) target, in the
## same order they were filtered.
func get_selectable_target_ids() -> Array:
	var ids: Array = []
	for target in _selectable_targets:
		ids.append(_target_id(target))
	return ids


## is_target_selectable(target_id) -> bool -- true iff target_id names one of
## the currently selectable (in-range) targets.
func is_target_selectable(target_id: String) -> bool:
	if _locked:
		return false
	return _find_target(_selectable_targets, target_id) != null


## has_error() -> bool -- true iff the most recent select_target() call was
## rejected (locally or by the domain) and its inline message has not yet
## been cleared by a subsequent successful selection.
func has_error() -> bool:
	return _last_error_code != ""


## get_last_error_code() -> String -- the error code from the most recent
## rejected select_target() call, or "" if none/cleared.
func get_last_error_code() -> String:
	return _last_error_code


## get_last_error_message() -> String -- the non-blocking, human-readable
## inline message for the most recent rejected select_target() call, or ""
## if none/cleared.
func get_last_error_message() -> String:
	return _last_error_message


## select_target(target_id) -> Dictionary -- the player's chosen target.
##
## When target_id names a currently selectable (in-range) target, forwards
## directly to the injected resolve_action_use_case.resolve() (ADR-002: no
## duplicate action path) and returns its result Dictionary verbatim.
##   - On success (result.ok == true): clears any prior inline error, emits
##     strike_resolved with that result, and returns it.
##   - On rejection by the domain (result.ok == false -- e.g.
##     ERR_NOT_ACTIVE_COMBATANT / ERR_NO_ACTION_REMAINING /
##     ERR_TARGET_NOT_ADJACENT / ERR_TARGET_INVALID): records a non-blocking
##     inline message (get_last_error_message()), emits action_error, and
##     returns the result verbatim. No use case that advances the round is
##     ever called from here, so the combatant's turn is left exactly as it
##     was -- the caller may simply try again.
##
## When target_id does NOT name a currently selectable target (out of range,
## or unknown) -- including a stale/spoofed id never offered as selectable --
## this is rejected HERE, before ever reaching the use case: no
## action-budget spend, no event emission, no use-case call at all. Returns
## {"ok": false, "resolved": false, "error": ERR_TARGET_NOT_SELECTABLE} and
## records the same kind of non-blocking inline message.
func select_target(target_id: String) -> Dictionary:
	if _locked:
		return _fail(ERR_ENCOUNTER_ALREADY_RESOLVED)

	var target = _find_target(_selectable_targets, target_id)
	if target == null:
		return _fail(ERR_TARGET_NOT_SELECTABLE)

	var result: Dictionary = _resolve_action_use_case.resolve(
		_actor, _action_economy, target, ACTION_NAME, _round_number, _cycle_index, _active_combatant_id
	)

	if not result.get("ok", false):
		return _fail(result.get("error", ""))

	_last_error_code = ""
	_last_error_message = ""
	strike_resolved.emit(result)
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

func _fail(error_code: String) -> Dictionary:
	_last_error_code = error_code
	_last_error_message = _ERROR_MESSAGES.get(error_code, _DEFAULT_ERROR_MESSAGE)
	action_error.emit(_last_error_message)
	return {"ok": false, "resolved": false, "error": error_code}


## _rebuild_targets(candidate_targets) -> void -- recomputes
## _selectable_targets/_non_selectable_targets (the in-range filter,
## mirroring the domain's own hex_neighbors() precondition for UX purposes
## only) and, when a battlefield collaborator is configured, reports the
## result to it for visual display.
func _rebuild_targets(candidate_targets: Array) -> void:
	_selectable_targets = []
	_non_selectable_targets = []

	var actor_hex = _hex_coord_for(_actor)
	if actor_hex != null:
		var neighbors: Array = HexMathClass.hex_neighbors(actor_hex)
		for target in candidate_targets:
			var target_hex = _hex_coord_for(target)
			if target_hex != null and _is_one_of(target_hex, neighbors):
				_selectable_targets.append(target)
			else:
				_non_selectable_targets.append(target)
	else:
		_non_selectable_targets = candidate_targets.duplicate()

	if _battlefield != null:
		_battlefield.set_selectable_combatant_ids(get_selectable_target_ids(), _target_ids(_non_selectable_targets))


func _is_one_of(hex_coord, candidates: Array) -> bool:
	for candidate in candidates:
		if candidate.equals(hex_coord):
			return true
	return false


## _hex_coord_for(combatant) -> HexCoord or null -- prefers the injected
## HexBattlefield's already-loaded position (get_hex_coord()) when one is
## configured and knows about `combatant`; otherwise falls back to
## `combatant`'s own "hex_coord" key (or null if neither has one).
func _hex_coord_for(combatant: Dictionary):
	if _battlefield != null:
		var id: String = _target_id(combatant)
		if id != "":
			var from_battlefield = _battlefield.get_hex_coord(id)
			if from_battlefield != null:
				return from_battlefield
	return combatant.get("hex_coord", null)


func _find_target(targets: Array, target_id: String):
	for target in targets:
		if _target_id(target) == target_id:
			return target
	return null


## _target_id(target) -> String -- target Dictionaries are duck-typed the
## same way resolve_action_use_case expects them; "combatant_id" is
## preferred when present, falling back to "name".
func _target_id(target: Dictionary) -> String:
	return target.get("combatant_id", target.get("name", ""))


func _target_ids(targets: Array) -> Array:
	var ids: Array = []
	for target in targets:
		ids.append(_target_id(target))
	return ids
