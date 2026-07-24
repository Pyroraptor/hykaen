## presentation/adapters/combine_build_registry_proxy.gd —
## CombineBuildRegistryProxy (FEAT-002, US-002; FR-001; ADR-002).
##
## Adapter layer (Clean Architecture): extracted VERBATIM (same method
## body/signature) from MainScene.gd's former private inner class
## `_CombineBuildRegistryProxy` (former lines 3669-3678) as this feature's
## foundational dependency-inversion seam — MainScene.gd now `preload()`s
## this file instead of defining the class inline.
##
## FEAT-296 (DEF-NEW-001): the thin presentation-layer adapter
## `_combine_build_registry_proxy` is an instance of. Exposes the EXACT
## SAME duck-typed `execute(verb_id, value) -> Dictionary` contract
## presentation/selection_overlay.gd's own `_registry` doc requires --
## mirrors `CombineTargetingRegistryProxy`'s identical role, one phase
## earlier in the flow. selection_overlay.gd itself remains COMPLETELY
## UNCHANGED. Delegates every call straight back to the owning MainScene's
## own _on_combine_build_option_chosen(), never resolving a real
## ActionController itself.

class_name CombineBuildRegistryProxy
extends RefCounted

var _main_scene


func _init(main_scene) -> void:
	_main_scene = main_scene


func execute(verb_id: String, value) -> Dictionary:
	return _main_scene._on_combine_build_option_chosen(verb_id, value)
