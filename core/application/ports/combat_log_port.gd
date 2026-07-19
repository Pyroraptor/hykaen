## core/application/ports/combat_log_port.gd — CombatLogPort (FEAT-276 /
## US-011; FR-010)
##
## Application layer (Clean Architecture, ADR-001): documents the contract
## core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase
## depends on to publish a resolved cast's outcome — mirrors this project's
## established Protocol-style port pattern (core/application/ports/
## resolution_port.gd's ResolutionPort, core/application/ports/
## targeting_port.gd's TargetingPort): a base class documenting the
## abstract contract; a concrete adapter either `extends` it or simply
## duck-types it. The one concrete adapter this feature ships is
## presentation/ui/combat_log_panel_adapter.gd's CombatLogPanelAdapter.
##
## Contract (design notes' api_contracts #4):
##   emit(entry: CombatLogEntry) -> void
##     Fire-and-forget — the presentation layer subscribes/records; there
##     is no error path (a best-effort UI update never rolls back domain
##     state). `entry` is a core/domain/combat_log_entry.gd CombatLogEntry
##     value object, handed in UNMODIFIED by the caller (ResolveCastUseCase
##     performs no further transformation once it has built the entry).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var port: CombatLogPort = CombatLogPanelAdapter.new()
##   port.emit(CombatLogEntry.new(CombatLogEntry.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt", ["skeleton"], true, 9, null))

class_name CombatLogPort
extends RefCounted


## emit(entry) -> void — abstract; concrete adapters MUST override. The
## base implementation exists only to document the contract and to fail
## LOUD (push_error), mirroring ResolutionPort's / TargetingPort's
## identical "abstract base, push_error default" convention — never to
## silently swallow an entry.
func emit(_entry) -> void:
	push_error("CombatLogPort.emit() is abstract — override in a concrete adapter")
