## core/application/ports/combat_resource_loader_port.gd — CombatResourceLoaderPort
## (FEAT-003 / US-001 / FR-008, ADR-004).
##
## Application layer (Clean Architecture, ADR-001): documents the resource-
## loading contract core/application/combat_session_factory.gd's
## CombatSessionFactory depends on to materialize the EncounterResource a
## combat session is assembled from. Mirrors this project's established
## Protocol-style port pattern (core/application/combine/verb_registry_port.gd,
## core/application/ports/spell_catalog_port.gd) — GDScript has no
## `Protocol`/`interface` keyword, so this is realized as an abstract
## RefCounted base class: the unimplemented method below push_error()s and
## fails safe (returns null) rather than crash.
##
## The ONLY concrete implementation in production is
## presentation/adapters/gd_resource_loader_adapter.gd's GdResourceLoaderAdapter
## — the sole caller of load()/ResourceLoader for this seam (ADR-005). GUT
## tests inject a lightweight fake implementing this same contract instead
## (tests/gut/test_combat_session_factory.gd), so CombatSessionFactory.build()
## is exercised without touching the real filesystem/resource cache.
##
## Contract:
##   load_resource(path: String) -> Resource
##     Loads and returns the Resource at `path`. Returns null (never throws —
##     GDScript has no exceptions, ADR-005) if `path` is missing/invalid/
##     unresolvable; every caller MUST check for a null return.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name CombatResourceLoaderPort
extends RefCounted


## load_resource(path) -> Resource — abstract; concrete adapters MUST
## override. Returns null by default so an un-overridden port fails safe
## (no resource) rather than crashing.
func load_resource(_path: String):
	push_error("CombatResourceLoaderPort.load_resource() is abstract — override in a concrete adapter")
	return null
