## presentation/adapters/combine_targeting_registry_proxy.gd —
## CombineTargetingRegistryProxy (FEAT-002, US-002; FR-001; ADR-002).
##
## Adapter layer (Clean Architecture): extracted VERBATIM (same method
## body/signature) from MainScene.gd's former private inner class
## `_CombineTargetingRegistryProxy` (former lines 3646-3656) as this
## feature's foundational dependency-inversion seam — MainScene.gd now
## `preload()`s this file instead of defining the class inline.
##
## FEAT-007 (US-007; NFR-001): the thin presentation-layer adapter
## `_combine_targeting_registry_proxy` is an instance of. Exposes the EXACT
## SAME duck-typed `execute(verb_id, value) -> Dictionary` contract
## presentation/selection_overlay.gd's own `_registry` doc requires
## (`_verb_registry`'s `_VerbBarRegistryAdapter` satisfies the identical
## shape) — selection_overlay.gd itself is COMPLETELY UNCHANGED by this
## feature. Delegates every call straight back to the owning MainScene's
## own _on_combine_targeting_value_chosen(), never resolving a real
## ActionController itself.

class_name CombineTargetingRegistryProxy
extends RefCounted

var _main_scene


func _init(main_scene) -> void:
	_main_scene = main_scene


func execute(verb_id: String, value) -> Dictionary:
	return _main_scene._on_combine_targeting_value_chosen(verb_id, value)
