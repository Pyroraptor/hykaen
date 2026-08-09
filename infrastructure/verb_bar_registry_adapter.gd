extends RefCounted

## VerbBarRegistryAdapter - the presentation/verb_bar_view.gd VerbBarView registry
## contract (FEAT-004 / US-004/FR-001), a small GENERIC, data-driven dispatch
## table mirroring verb_registry.py's pytest-only VerbRegistry (ADR-004):
## register() is the ONLY method that special-cases a verb_id;
## list_verbs()/is_available()/enter_selection()/execute() are plain dict lookups
## followed by a delegate Callable.call() - there is deliberately NO verb-name
## branching in any of those four methods, so a hypothetical fifth verb could be
## registered without touching this class.
##
## Composition-root de-bloat (2026-07-10): extracted from a MainScene.gd inner
## class; built ONLY by MainScene._build_verb_registry(), referenced via
## VerbBarRegistryAdapterClass.

var _availability_fns: Dictionary = {}
var _enter_selection_fns: Dictionary = {}
var _execute_fns: Dictionary = {}
var _order: Array = []


## register(verb_id, availability_fn, enter_selection_fn, execute_fn) - the ONLY
## method that special-cases a verb_id; every dispatch method below is a generic
## dict lookup over whatever has been register()ed.
func register(verb_id: String, availability_fn: Callable, enter_selection_fn: Callable, execute_fn: Callable) -> void:
	if not _availability_fns.has(verb_id):
		_order.append(verb_id)
	_availability_fns[verb_id] = availability_fn
	_enter_selection_fns[verb_id] = enter_selection_fn
	_execute_fns[verb_id] = execute_fn


func list_verbs() -> Array:
	var descriptors: Array = []
	for verb_id in _order:
		descriptors.append({"verb_id": verb_id})
	return descriptors


func is_available(verb_id: String) -> bool:
	return bool(_availability_fns[verb_id].call())


func enter_selection(verb_id: String):
	return _enter_selection_fns[verb_id].call()


func execute(verb_id: String, selection = null):
	return await _execute_fns[verb_id].call(selection)
