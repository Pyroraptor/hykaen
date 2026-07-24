## presentation/adapters/gd_resource_loader_adapter.gd — GdResourceLoaderAdapter
## (FEAT-003, US-001; FR-008; ADR-004/ADR-005).
##
## Adapter layer (Clean Architecture): the driven/secondary adapter that
## implements core/application/ports/combat_resource_loader_port.gd's
## CombatResourceLoaderPort contract for
## core/application/combat_session_factory.gd's CombatSessionFactory. This is
## the SOLE caller of load()/ResourceLoader for CombatSessionFactory's
## resource-loading seam (ADR-005) — enabling GUT to inject a fake
## CombatResourceLoaderPort in tests/gut/test_combat_session_factory.gd
## instead of exercising the real filesystem/resource cache.
##
## Security note (design notes' security section): validates `path` resolves
## under res://data/ before calling load(), so a future player-/mod-supplied
## resource path can never traverse outside the authored data directory.

## Extends by path (not by bare global class_name) deliberately: this
## adapter must parse correctly even before Godot's global script class
## cache (.godot/global_script_class_cache.cfg, gitignored/environment-
## local) has been rebuilt to include this feature's newly added port —
## mirroring the SAME `extends "res://...port.gd"` convention this
## codebase's own GUT test fakes already use for fresh port
## implementations (e.g. tests/gut/test_combat_session_factory.gd's
## FakeCombatResourceLoaderPort).
class_name GdResourceLoaderAdapter
extends "res://core/application/ports/combat_resource_loader_port.gd"

## Every path this adapter will load MUST live under this prefix (security
## section: prevents accidental/malicious path traversal if resource paths
## ever become player- or mod-supplied in a later iteration).
const REQUIRED_PATH_PREFIX: String = "res://data/"


## load_resource(path) -> Resource — the sole load()/ResourceLoader call
## site for CombatSessionFactory's resource-loading seam. Returns null
## (never throws — GDScript has no exceptions, ADR-005) both when `path`
## falls outside res://data/ and when ResourceLoader.load() itself fails to
## resolve the path; either case push_error()s so the failure is visible in
## Godot's Output/debugger panel during manual playtesting, not just under
## GUT.
func load_resource(path: String):
	if not path.begins_with(REQUIRED_PATH_PREFIX):
		push_error("GdResourceLoaderAdapter: refusing to load path outside %s: %s" % [REQUIRED_PATH_PREFIX, path])
		return null

	var resource = ResourceLoader.load(path)
	if resource == null:
		push_error("GdResourceLoaderAdapter: failed to load resource at %s" % path)
	return resource
