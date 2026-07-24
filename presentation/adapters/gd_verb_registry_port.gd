## presentation/adapters/gd_verb_registry_port.gd — GdVerbRegistryPort
## (FEAT-002, US-002; FR-001; ADR-002).
##
## Adapter layer (Clean Architecture): the driven/secondary adapter that
## implements core/application/combine/verb_registry_port.gd's
## VerbRegistryPort contract. Extracted VERBATIM (same method body/
## signature) from MainScene.gd's former private inner class
## `_GdVerbRegistryPort` (former lines 3569-3583) as this feature's
## foundational dependency-inversion seam — MainScene.gd now `preload()`s
## this file instead of defining the class inline.
##
## Minimal VerbRegistryPort adapter (FEAT-007): returns the loaded STRIDE,
## STRIKE, and CAST_SPELL VerbResource .tres files as the available verb
## pool for any actor/context. Sufficient for the v0 Charge steel thread; a
## full actor/context-aware implementation is a later sprint's scope.

class_name GdVerbRegistryPort
extends VerbRegistryPort


func get_available_verbs(_actor, _context) -> Array:
	var verbs: Array = []
	var stride = load("res://data/verbs/stride.tres")
	if stride != null:
		verbs.append(stride)
	var strike = load("res://data/verbs/strike.tres")
	if strike != null:
		verbs.append(strike)
	var cast_spell = load("res://data/verbs/cast_spell.tres")
	if cast_spell != null:
		verbs.append(cast_spell)
	return verbs
