## core/application/ports/spell_catalog_port.gd — SpellCatalogPort (FEAT-005
## / US-005; FR-004, FR-011)
##
## Application layer (Clean Architecture): documents the contract
## BeginCastUseCase (core/application/use_cases/begin_cast_use_case.gd)
## depends on to resolve a spell_id -> core/domain/spell.gd Spell — mirrors
## this project's established Protocol-style port pattern
## (core/application/ports/reaction_window_port.gd). The ONE concrete
## implementation this feature wires is core/adapters/
## resource_spell_catalog_adapter.gd's ResourceSpellCatalogAdapter (FEAT-001,
## Iteration M), unmodified — it already implements get_spell(spell_id) with
## the exact matching signature/return shape (duck-typed; this port is never
## `extends`-ed by that adapter, mirroring core/application/ports/
## action_economy_port.gd's own "concrete adapters ... simply duck-type it"
## fallback for lightweight adapters).
##
## Contract (design notes' architecture section):
##   get_spell(spell_id) -> Spell | null
##     Resolves a spell_id to its core/domain/spell.gd Spell domain value
##     object, or null for an unknown/malformed spell_id (see
##     ResourceSpellCatalogAdapter's own doc for its null-on-malformed-data
##     convention).
##   list_known_castable(caster, pool_balance) -> Array[Spell]
##     Every Spell in `caster`'s known_spell_ids whose energy_cost is
##     affordable against `pool_balance` (US-013's "known spell IDs filtered
##     by pool balance"). Declared here as part of this port's contract;
##     BeginCastUseCase computes this filtering itself via get_spell() calls
##     rather than requiring every adapter to implement this convenience
##     method (ResourceSpellCatalogAdapter does not implement it yet) — a
##     future concrete adapter MAY implement it for a Presentation-layer
##     list-pick UI to call directly.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name SpellCatalogPort
extends RefCounted


## get_spell(spell_id) -> Spell | null — abstract; concrete adapters MUST
## override.
func get_spell(_spell_id: String):
	push_error("SpellCatalogPort.get_spell() is abstract — override in a concrete adapter")
	return null


## list_known_castable(caster, pool_balance) -> Array — abstract; concrete
## adapters MAY override (see file-level doc — BeginCastUseCase does not
## require this method on its injected collaborator).
func list_known_castable(_caster, _pool_balance: int) -> Array:
	push_error("SpellCatalogPort.list_known_castable() is abstract — override in a concrete adapter")
	return []
