## presentation/MoveActionControl.gd — MoveActionControl (FEAT-007 / US-007 / FR-002)
##
## Presentation layer (Clean Architecture): a visible Move affordance,
## sibling to presentation/strike_action_control.gd, satisfying US-007's
## "sees a visible affordance indicating a Move is currently available"
## criterion. MoveActionControl is intentionally thin and holds NO movement
## rule logic of its own (ADR-001) — it never calls into
## core/rules/movement.gd or presentation/movement_input_controller.gd
## directly. It is simply handed the already-computed selectable-hex Array
## (the SAME union(Step, Stride) set MainScene.gd's _highlight_legal_moves()
## already pushes to HexGridView.set_selectable_hexes(), API contract #3) via
## configure(), and reflects that set's emptiness in `visible`. The actual
## move is executed by clicking a highlighted hex on HexGridView (API
## contract #4) — this control is an indicator, not a separate input path,
## so no new use case or port is introduced (ADR-002 / CR-001 guardrail).
##
## FEAT-137 / DEF-004 style sticky lock (mirroring
## presentation/strike_action_control.gd's and
## presentation/end_turn_control.gd's identically-named lock()/is_locked()
## contract exactly, see tests/gut/test_presentation_controls_sticky_lock.gd):
## once lock() has been called, this control is disabled AND hidden,
## regardless of any later configure() call — mirroring the API contract's
## "MoveActionControl hidden" postcondition of the uniform post-resolution
## lock (design notes' API contract #6). There is no unlock().

class_name MoveActionControl
extends Control

## FEAT-137 / DEF-004: local/defensive rejection code mirroring
## StrikeActionControl's/EndTurnControl's identically-named contract, kept
## here purely for consistency even though MoveActionControl exposes no
## select()/press()-style method of its own to reject.
const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"

## The most recently configured selectable-hex Array (Array of
## core/geometry/hex_coord.gd HexCoord instances) — never re-derived, only
## read for its emptiness.
var _selectable_hexes: Array = []

## FEAT-137 / DEF-004: true once lock() has been called — sticky across any
## later configure() call (see file-level doc). is_enabled() always reports
## false and `visible` always reports false while true.
var _locked: bool = false


func _ready() -> void:
	_refresh_visible_state()


## lock() -> void — permanently locks this control (FEAT-137 / DEF-004):
## is_enabled() reports false and the control is hidden, regardless of any
## later configure() call. Intended to be called exactly once, alongside
## StrikeActionControl.lock()/EndTurnControl.lock(), the moment an
## EncounterResultEvent is observed. There is no unlock().
func lock() -> void:
	_locked = true
	_refresh_visible_state()


## is_locked() -> bool — true once lock() has been called.
func is_locked() -> bool:
	return _locked


## configure(selectable_hexes) -> void — hands this control the CURRENT
## selectable-hex set (normally the same union(Step, Stride) Array
## MainScene.gd's _highlight_legal_moves() computes and pushes to
## HexGridView.set_selectable_hexes()), and refreshes `visible` accordingly.
## Does NOT reset a prior lock() — see file-level doc.
func configure(selectable_hexes: Array) -> void:
	_selectable_hexes = selectable_hexes
	_refresh_visible_state()


## is_enabled() -> bool — true iff a Move is currently available (a non-empty
## selectable-hex set was last configured) and this control has not been
## locked. Mirrors StrikeActionControl's is_target_selectable()/
## EndTurnControl's is_enabled() enabled/disabled contract for consistency.
## Always false once lock() has been called (FEAT-137 / DEF-004).
func is_enabled() -> bool:
	if _locked:
		return false
	return not _selectable_hexes.is_empty()


# ── Internal helpers ─────────────────────────────────────────────────────

func _refresh_visible_state() -> void:
	visible = is_enabled()
