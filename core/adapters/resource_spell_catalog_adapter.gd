## core/adapters/resource_spell_catalog_adapter.gd —
## ResourceSpellCatalogAdapter (FEAT-001, Iteration M, US-002; FR-011,
## FR-013 data half)
##
## Adapter/Infrastructure layer (Clean Architecture, ADR-001): the ONE place
## ResourceLoader / core/resources/spell_resource.gd SpellResource-file
## concerns meet the domain core/domain/spell.gd Spell value object.
## Loads data/spells/*.tres (SpellResource, authored by this feature) via
## ResourceLoader and maps each into a domain Spell VO. Application-layer
## use cases (a future BeginCastUseCase/ContinueCastUseCase/
## ResolveCastUseCase, per this iteration's design notes' SpellCatalogPort)
## never see a Godot Resource object through this seam — only Spell —
## matching core/infrastructure/resource_encounter_repository.gd's
## established "adapter loads Resources, hands back domain types"
## convention.
##
## ID -> path convention (spell_id == filename-stem, mirroring
## core/resources/spell_resource.gd's own authoring convention):
##   spell_id "fire_bolt" -> res://data/spells/fire_bolt.tres
##   spell_id "channel"   -> res://data/spells/channel.tres
##
## A malformed/invalid SpellResource (see SpellResource.is_valid()) is
## never exposed through get_spell() — it is logged and treated as
## unknown (returns null), matching the project's established
## "malformed authored data must fail fast/never silently corrupt runtime
## state" convention (see core/rules/infrastructure/spell_resource_loader.gd).
##
## Usage:
##   var adapter := ResourceSpellCatalogAdapter.new()
##   var fire_bolt := adapter.get_spell("fire_bolt")
##   fire_bolt.actions_cost   # 2

class_name ResourceSpellCatalogAdapter
extends RefCounted

const SpellClass = preload("res://core/domain/spell.gd")

## Directory holding authored SpellResource .tres files, keyed by spell_id.
const SPELL_RESOURCE_DIR: String = "res://data/spells/"

## Per-instance spell_id -> SpellResource.tres path mapping, so tests may
## inject a fixture directory without touching production data.
var _resource_dir: String = SPELL_RESOURCE_DIR


func _init(resource_dir: String = SPELL_RESOURCE_DIR) -> void:
	_resource_dir = resource_dir


## get_spell(spell_id) -> Spell | null
##
## Loads res://data/spells/{spell_id}.tres and maps its fields onto a
## domain Spell VO. Returns null (and push_error()s) when the resource
## fails to load, is not a valid SpellResource instance, or fails
## SpellResource.is_valid()'s load-time invariants.
func get_spell(spell_id: String):
	var path: String = _resource_dir + spell_id + ".tres"
	var spell_resource = ResourceLoader.load(path)
	if spell_resource == null:
		push_error("ResourceSpellCatalogAdapter: failed to load spell resource at %s" % path)
		return null
	if not spell_resource.has_method("is_valid") or not spell_resource.is_valid():
		var reason: String = spell_resource.validation_error() if spell_resource.has_method("validation_error") else "not a valid SpellResource"
		push_error("ResourceSpellCatalogAdapter: rejecting malformed spell '%s': %s" % [spell_id, reason])
		return null

	return SpellClass.new(
		spell_resource.spell_id,
		spell_resource.name,
		spell_resource.actions_cost,
		spell_resource.energy_cost,
		spell_resource.defense,
		spell_resource.range_ft,
		spell_resource.damage_formula,
		spell_resource.damage_type,
		spell_resource.traits,
		spell_resource.effect_type,
		spell_resource.effect_params,
		spell_resource.condition_on_hit
	)
