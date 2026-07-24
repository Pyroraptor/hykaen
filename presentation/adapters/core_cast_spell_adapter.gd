## presentation/adapters/core_cast_spell_adapter.gd — CoreCastSpellAdapter
## (FEAT-002, US-002; FR-001; ADR-002).
##
## Adapter layer (Clean Architecture): the driven/secondary adapter that
## implements core/application/combine/verb_controller_port.gd's
## VerbControllerPort contract for the CAST_SPELL combine sub-action.
## Extracted VERBATIM (same method bodies/signatures) from MainScene.gd's
## former private inner class `_CoreCastSpellAdapter` (former lines
## 3537-3565) as this feature's foundational dependency-inversion seam —
## MainScene.gd now `preload()`s this file instead of defining the class
## inline, per the design notes' "adapters are concrete GDScript classes
## ... in presentation/adapters/" architecture section.
##
## Offer phase (no selected_hex in context): delegates to the presentation
## SpellActionController's 0-arg enter_selection() to get the actor's
## available spells as candidate_options. SelectionOverlay then handles the
## two-step spell-picker → target flow internally as a single activate() call.
##
## Resolution phase (selected_hex present in context): the value is the
## {"option": chosen_spell, "target": target_id} dict SelectionOverlay's
## _resolve() builds after both spell and target are chosen. Stored verbatim
## in meta["chosen_target"] so CombineActionController._targeting_payload_for()
## returns it unchanged to execute() — the exact OPTION_TARGET shape
## SpellActionController.execute() already expects.

class_name CoreCastSpellAdapter
extends "res://core/application/combine/verb_controller_port.gd"

const SelectionDescriptorClass = preload("res://core/domain/combine/selection_descriptor.gd")

var _get_ctrl_fn: Callable


func _init(deps: Dictionary = {}) -> void:
	_get_ctrl_fn = deps.get("get_ctrl_fn", Callable())


func enter_selection(context: Dictionary) -> Object:
	var order_index: int = context.get("order_index", 0)
	var selected = context.get("selected_hex")
	if selected != null:
		return SelectionDescriptorClass.new(true, [], [], [], order_index,
			{"chosen_target": selected})
	if not _get_ctrl_fn.is_valid():
		return _sd_failure(order_index)
	var pres_ctrl = _get_ctrl_fn.call()
	if pres_ctrl == null:
		return _sd_failure(order_index)
	var pres_result = pres_ctrl.enter_selection()
	var candidate_options: Array = pres_result.get("candidate_options", [])
	if candidate_options.is_empty():
		return _sd_failure(order_index)
	return SelectionDescriptorClass.new(true, candidate_options, [], [], order_index, {})


func _sd_failure(order_index: int) -> Object:
	return SelectionDescriptorClass.new(false, [], [], [], order_index,
		{"error_code": "NO_LEGAL_OPTIONS"})
