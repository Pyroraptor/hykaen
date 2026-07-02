## presentation/strike_action_control.gd — StrikeActionControl (FEAT-109 / US-009)
##
## Presentation layer (Clean Architecture): the player-facing control that
## performs a melee Strike, satisfying the steel thread's "performs a melee
## Strike on an in-reach enemy" criterion.
##
## StrikeActionControl is intentionally thin:
##   1. Target filtering (UX/defense-in-depth mirror, NOT re-implementing the
##      domain rule): configure() is handed the acting combatant Dictionary
##      (MAY carry a "hex_coord" key -- a core/geometry/hex_coord.gd HexCoord
##      instance) and a list of candidate target Dictionaries. It restricts
##      the SELECTABLE targets to exactly those candidates whose hex_coord is
##      one of the actor's 6 flat-top axial neighbors, computed via the SAME
##      domain function the application layer already uses internally
##      (core/geometry/hex_math.gd HexMath.hex_neighbors() -- US-002/US-003).
##      A non-adjacent candidate is never rendered as a selectable button and
##      is rejected defensively even if select_target() is called with its id
##      directly (e.g. from a test or a stale UI reference) -- this control
##      never re-implements the reach RULE itself, it only mirrors it for UX.
##   2. Invocation: select_target(target_id) calls the INJECTED
##      resolve_action_use_case's resolve() method directly -- the existing,
##      REUSED Application-layer use case (core/application/
##      resolve_action_use_case.gd, ADR-002/CR-001: no duplicate action path)
##      -- which itself re-validates adjacency/action-budget defense-in-depth
##      and, on success, spends one action from the actor's ActionBudget
##      (core/rules/action_economy.gd) and emits a typed AttackEvent via the
##      injected EventSinkPort (core/rules/round_events.gd), observable by any
##      Presentation projection already subscribed to that sink (StatusPanelView,
##      EventLogView, InitiativeView, HexGridView) -- StrikeActionControl never
##      pushes events to those views itself.
##
## StrikeActionControl MUST NOT re-implement resolution/damage/adjacency
## rules -- it only (a) filters using the domain adjacency function for UX
## and (b) forwards the player's choice to the existing use case. No new
## port or use case is introduced (ADR-002 / CR-001 guardrail).
##
## FEAT-137 / DEF-004 (US-010): lock()/is_locked() add a persistent, sticky
## post-resolution guard -- once presentation/result_screen_view.gd observes
## an EncounterResultEvent it calls lock() here, after which select_target()
## and is_target_selectable() always report rejected/false and every
## selectable-target button is cleared, regardless of any later configure()
## call. This mirrors scenes/battlefield/StrikeInputController.gd's
## lock()/is_locked() contract exactly and is deliberately independent of (and
## stickier than) the one-time configure({}, null, null, [])-clear technique
## this file used to rely on -- that technique re-enabled input the moment
## anything called configure() again (e.g. a stray reconfigure() from a
## leftover TurnController signal) after the encounter had already concluded.
## There is no unlock() -- this steel thread never continues a round past
## resolution.

class_name StrikeActionControl
extends Control

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## Action name this control always spends -- the one melee action that
## exists in the current ruleset (US-009's "Strike" steel-thread action).
const ACTION_NAME: String = "Strike"

## FEAT-137 / DEF-004: local/defensive rejection code returned by
## select_target() once lock() has been called -- mirrors
## scenes/battlefield/StrikeInputController.gd's identically-named contract.
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

## strike_resolved(result) -- emitted after select_target() invokes
## resolve_action_use_case.resolve(), carrying that call's full result
## Dictionary. Presentation code composing this control MAY listen for
## richer UX feedback; no subscriber is required for this control to work.
signal strike_resolved(result: Dictionary)

## The acting combatant Dictionary (as passed to configure()), including its
## "hex_coord" key when reach-gating is desired.
var _actor: Dictionary = {}

## The actor's ActionEconomy instance (core/rules/action_economy.gd),
## injected -- StrikeActionControl never constructs one itself.
var _action_economy = null

## The injected, REUSED resolve_action_use_case (core/application/
## resolve_action_use_case.gd) -- StrikeActionControl never constructs one
## itself and never forks/duplicates its logic (ADR-002).
var _resolve_action_use_case = null

var _round_number: int = 1
var _cycle_index: int = 0

## The candidate targets currently in reach -- exactly the subset of the
## last configure() call's candidate_targets whose hex_coord is one of the
## actor's 6 flat-top axial neighbors (HexMath.hex_neighbors()).
var _selectable_targets: Array = []

## target_id (String) -> Button, one per currently selectable target.
var _buttons: Dictionary = {}

## FEAT-137 / DEF-004: true once lock() has been called -- sticky across any
## later configure() call (see file-level doc). select_target()/
## is_target_selectable() always report rejected/false while true.
var _locked: bool = false

@onready var _targets_container: VBoxContainer = $TargetsContainer


## lock() -> void -- permanently locks this control (FEAT-137 / DEF-004):
## every subsequent select_target() call is rejected with
## ERR_ENCOUNTER_ALREADY_RESOLVED, is_target_selectable() always reports
## false, and every rendered selectable-target button is cleared -- all
## regardless of any later configure() call. Intended to be called exactly
## once, by presentation/result_screen_view.gd, the moment an
## EncounterResultEvent is observed. There is no unlock().
func lock() -> void:
	_locked = true
	_rebuild_targets([])


## is_locked() -> bool -- true once lock() has been called.
func is_locked() -> bool:
	return _locked


## configure(actor, action_economy, resolve_action_use_case,
##           candidate_targets, round_number, cycle_index) -> void
##
## actor              -- the acting combatant Dictionary (MAY carry
##                        "hex_coord"). Duck-typed to match
##                        resolve_action_use_case.resolve()'s `combatant`
##                        parameter shape.
## action_economy     -- the actor's ActionEconomy instance for this round.
## resolve_action_use_case -- the injected, REUSED use case instance this
##                        control forwards a selected Strike to.
## candidate_targets  -- Array of target Dictionaries (enemies), each MAY
##                        carry "hex_coord". Re-filtered into
##                        _selectable_targets on every call (no leaked state
##                        from a prior configure()/turn).
## round_number/cycle_index -- stamped on the resolved AttackEvent/history
##                        entry exactly as resolve_action_use_case expects.
func configure(
	actor: Dictionary,
	action_economy,
	resolve_action_use_case,
	candidate_targets: Array,
	round_number: int = 1,
	cycle_index: int = 0
) -> void:
	_actor = actor
	_action_economy = action_economy
	_resolve_action_use_case = resolve_action_use_case
	_round_number = round_number
	_cycle_index = cycle_index
	# FEAT-137 / DEF-004: once lock() has been called, no later configure()
	# call may repopulate selectable targets/buttons -- the lock is sticky
	# across a stray reconfigure() (see file-level doc).
	_rebuild_targets([] if _locked else candidate_targets)


## get_selectable_target_ids() -> Array[String] -- the target_id (see
## _target_id()) of every currently selectable (in-reach) target, in the
## same order they were filtered. Exactly matches HexMath.hex_neighbors()
## membership against the last configure() call's candidate_targets.
func get_selectable_target_ids() -> Array:
	var ids: Array = []
	for target in _selectable_targets:
		ids.append(_target_id(target))
	return ids


## is_target_selectable(target_id) -> bool -- true iff target_id names one
## of the currently in-reach targets.
func is_target_selectable(target_id: String) -> bool:
	if _locked:
		return false
	return _find_selectable_target(target_id) != null


## get_button_count() -> int -- number of selectable-target buttons
## currently rendered (display-level assertion, mirrors the other
## presentation views' get_row_count()/get_token_count()).
func get_button_count() -> int:
	return _buttons.size()


## select_target(target_id) -> Dictionary -- the player's chosen target.
## When target_id names a currently selectable (in-reach) target, forwards
## directly to the injected resolve_action_use_case.resolve() (ADR-002: no
## duplicate action path) and returns its result Dictionary verbatim,
## emitting strike_resolved with that same result.
##
## When target_id does NOT name a currently selectable target (not in
## reach, or unknown) -- including a stale/spoofed id never rendered as a
## button -- this is rejected HERE, before ever reaching the use case: no
## action-budget spend, no event emission, no use-case call at all.
## Returns {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}.
##
## FEAT-137 / DEF-004: once lock() has been called, select_target() is
## rejected HERE FIRST, before any other check, returning {"ok": false,
## "resolved": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED} -- sticky
## regardless of any later configure() call.
func select_target(target_id: String) -> Dictionary:
	if _locked:
		return {"ok": false, "resolved": false, "error": ERR_ENCOUNTER_ALREADY_RESOLVED}

	var target = _find_selectable_target(target_id)
	if target == null:
		return {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}

	var result: Dictionary = _resolve_action_use_case.resolve(
		_actor, _action_economy, target, ACTION_NAME, _round_number, _cycle_index
	)
	strike_resolved.emit(result)
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

## _rebuild_targets(candidate_targets) -> void -- recomputes
## _selectable_targets (the reach filter, US-002/US-003) and rebuilds one
## Button per selectable target. Clears any previously-rendered buttons
## first, so a repeated configure() call (e.g. a subsequent turn) never
## leaks duplicate buttons.
func _rebuild_targets(candidate_targets: Array) -> void:
	for button in _buttons.values():
		button.queue_free()
	_buttons.clear()

	_selectable_targets = _filter_in_reach(candidate_targets)

	for target in _selectable_targets:
		var target_id: String = _target_id(target)
		var button := Button.new()
		button.name = "Target_%s" % target_id
		button.text = target.get("name", target_id)
		if _targets_container != null:
			_targets_container.add_child(button)
		button.pressed.connect(_on_target_button_pressed.bind(target_id))
		_buttons[target_id] = button


## _filter_in_reach(candidate_targets) -> Array -- exactly the subset of
## candidate_targets whose "hex_coord" is one of the actor's 6 flat-top
## axial neighbors (core/geometry/hex_math.gd HexMath.hex_neighbors(),
## US-002/US-003). A candidate lacking "hex_coord", or an actor lacking
## "hex_coord", is never selectable -- StrikeActionControl requires
## positional data to gate reach at all (no reach data means no melee
## target can be offered).
func _filter_in_reach(candidate_targets: Array) -> Array:
	var actor_hex = _actor.get("hex_coord", null)
	if actor_hex == null:
		return []

	var neighbors: Array = HexMathClass.hex_neighbors(actor_hex)
	var in_reach: Array = []
	for target in candidate_targets:
		var target_hex = target.get("hex_coord", null)
		if target_hex == null:
			continue
		for neighbor in neighbors:
			if neighbor.equals(target_hex):
				in_reach.append(target)
				break
	return in_reach


## _find_selectable_target(target_id) -> Dictionary or null -- looks up
## target_id ONLY among the currently selectable (in-reach) targets, never
## the original (unfiltered) candidate_targets -- the enforcement point for
## test criterion 4 (a non-adjacent hex can never be selected, even by id).
func _find_selectable_target(target_id: String):
	for target in _selectable_targets:
		if _target_id(target) == target_id:
			return target
	return null


## _target_id(target) -> String -- target Dictionaries are duck-typed the
## same way resolve_action_use_case expects them (combatant_id is not part
## of that shape); "combatant_id" is preferred when present (matches
## core/domain/combatant.gd-derived view models), falling back to "name"
## (unique within one encounter's target list, matching the convention
## already relied on by presentation/status_panel_view.gd's _id_by_name).
func _target_id(target: Dictionary) -> String:
	return target.get("combatant_id", target.get("name", ""))


func _on_target_button_pressed(target_id: String) -> void:
	select_target(target_id)
