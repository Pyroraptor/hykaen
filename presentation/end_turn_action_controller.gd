extends "res://presentation/action_controller.gd"

## EndTurnActionController — the END_TURN verb (FEAT-004 / US-004). Always
## available; has no Layer 2 selection (design notes: "no Layer 2, per spec" —
## enter_selection() exists only so the generic dispatch contract stays uniform
## across every verb; VerbBarView.press() calls execute() directly for END_TURN).
## execute() presses the injected EndTurnControl.
##
## Concrete ActionController subclass (presentation/action_controller.gd),
## extracted from MainScene's _verb_bar_end_turn_* methods (composition-root
## de-bloat, 2026-07-10). MainScene keeps thin delegating shims.

var _end_turn_control


func _init(session_holder, end_turn_control) -> void:
	super(session_holder)
	_end_turn_control = end_turn_control


func availability() -> bool:
	return true


func enter_selection() -> Dictionary:
	return {"verb_id": "END_TURN", "candidate_hexes": [], "candidate_targets": []}


func execute(_selection = null) -> Dictionary:
	if _end_turn_control == null:
		return {"ok": false}
	return _end_turn_control.press()
