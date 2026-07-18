## core/rules/ports/spell_repository_port.gd — SpellRepositoryPort
## (FEAT-001 / US-002, FR-008, ADR-007)
##
## Application-layer port (Clean Architecture): defines the spell-lookup
## contract a future BeginCastUseCase/ContinueCastUseCase/ResolveSpellUseCase
## depends on to resolve a spell_id into its hydrated
## core/rules/spell_definition.gd SpellDefinition, so orchestration code
## never touches ResourceLoader/Resource-file concerns directly (those live
## solely in core/rules/infrastructure/spell_resource_loader.gd).
##
## GDScript has no formal interface/Protocol keyword, so — matching the
## existing port pattern established by core/rules/random_port.gd and
## core/application/round_history_port.gd — this base class documents the
## contract and provides an abstract get_spell() that concrete adapters
## MUST override. Concrete adapters extend this script directly
## (`extends "res://core/rules/ports/spell_repository_port.gd"`).
##
## Contract:
##   get_spell(spell_id: String) -> SpellDefinition | null
##     Returns the hydrated SpellDefinition registered under `spell_id`, or
##     null when no such spell is known OR the underlying data failed
##     validation (see SpellDefinition.is_valid()) — a caller must never
##     receive a malformed/invalid SpellDefinition through this contract.
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance.
##
## Usage example:
##   var repo: SpellRepositoryPort = SpellResourceLoader.new()  # production
##   var fire_bolt = repo.get_spell("fire_bolt")
##   fire_bolt.actions  # 2

class_name SpellRepositoryPort
extends RefCounted


## get_spell(spell_id) -> SpellDefinition | null — abstract; concrete
## adapters MUST override. The base implementation exists only to document
## the contract and fail loudly if a caller is ever handed a bare
## SpellRepositoryPort instead of a concrete adapter.
func get_spell(_spell_id: String):
	push_error("SpellRepositoryPort.get_spell() is abstract — override in a concrete adapter (SpellResourceLoader)")
	return null
