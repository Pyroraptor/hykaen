## presentation/adapters/gd_combine_action_economy_port.gd —
## GdCombineActionEconomyPort (FEAT-002, US-002; FR-001; ADR-002).
##
## Adapter layer (Clean Architecture): the driven/secondary adapter that
## implements core/application/ports/action_economy_port.gd's
## ActionEconomyPort contract. Extracted VERBATIM (same method bodies/
## signatures) from MainScene.gd's former private inner class
## `_GdCombineActionEconomyPort` (former lines 3601-3632) as this feature's
## foundational dependency-inversion seam — MainScene.gd now `preload()`s
## this file instead of defining the class inline.
##
## FEAT-298 (resolves DEF-NEW-003): minimal ActionEconomyPort adapter for
## `_core_combine_action_controller`'s `_charge_action_economy()`
## (core/controllers/combine_action_controller.gd). Never captures a single
## ActionEconomy instance at construction time — instead, every call
## resolves `_owner._verb_bar_current_action_economy()` (the SAME
## `round_session.current_action_economy()` read every other verb's own
## availability gate already uses) lazily, so the port stays correct
## across `rewire_session()`/round-boundary ActionEconomy instance swaps,
## mirroring `GdVerbRegistryPort`'s own "thin, lazily-resolving adapter"
## convention. When no live ActionEconomy is available (e.g. before the
## first round is wired), degrades safely: spend_action()/spend_reaction()
## report failure without mutating anything, is_spent() reports true
## (nothing left to spend), get_remaining() reports 0 — never a crash.

## Extends by path (not by bare global class_name) deliberately: this
## adapter must parse correctly even before Godot's global script class
## cache (.godot/global_script_class_cache.cfg, gitignored/environment-
## local) has been rebuilt to include ActionEconomyPort — mirroring
## presentation/adapters/core_cast_spell_adapter.gd's own
## `extends "res://...port.gd"` convention (FEAT-003 hardening).
class_name GdCombineActionEconomyPort
extends "res://core/application/ports/action_economy_port.gd"

var _owner  # MainScene — untyped to avoid a cyclic self-reference.


func _init(owner) -> void:
	_owner = owner


func spend_action(action_metadata: Dictionary) -> Dictionary:
	var economy = _owner._verb_bar_current_action_economy()
	if economy == null:
		return {"success": false, "ok": false}
	return economy.spend_action(action_metadata)


func spend_reaction() -> Dictionary:
	var economy = _owner._verb_bar_current_action_economy()
	if economy == null:
		return {"success": false, "ok": false}
	return economy.spend_reaction()


func is_spent() -> bool:
	var economy = _owner._verb_bar_current_action_economy()
	if economy == null:
		return true
	return economy.is_spent()


func get_remaining() -> int:
	var economy = _owner._verb_bar_current_action_economy()
	if economy == null:
		return 0
	return economy.get_remaining()
