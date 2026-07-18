## core/rules/infrastructure/spell_resource_loader.gd — SpellResourceLoader
## (FEAT-001 / US-002, FR-008)
##
## Infrastructure/Adapter layer (Clean Architecture): the ONE place
## ResourceLoader / Resource-file concerns meet spell data — implements
## core/rules/ports/spell_repository_port.gd's SpellRepositoryPort by
## loading each authored resources/spells/{spell_id}.tres via
## ResourceLoader.load() and hydrating a core/rules/spell_definition.gd
## SpellDefinition instance from it (Resource subclasses are hydrated
## field-by-field by ResourceLoader itself — this adapter's own job is
## purely to resolve the spell_id -> path mapping, drive the load, and
## enforce the load-time validation gate before anything is cached or
## exposed).
##
## Validation gate (design notes' security policy #1 / this feature's own
## test_criteria: "Loader rejects malformed spell data (negative
## energy_cost, actions<=0, range_ft<0)"): register() checks
## SpellDefinition.is_valid() before caching — a malformed definition is
## discarded (never cached, never discoverable via get_spell()) so a bad
## .tres can never reach downstream use-case logic. Production loading
## (_ensure_loaded()) routes through this SAME register() method, so the
## real ResourceLoader.load() path and this feature's unit tests (which
## register() hand-built SpellDefinition fixtures directly, without
## touching disk) exercise identical validation logic.
##
## Lazily loads on first get_spell() call and caches thereafter — spell
## data is static/authored, so re-reading from disk on every lookup would
## be pure waste.
##
## Domain purity boundary (ADR-001): this adapter is infrastructure, not
## domain — it is the one file in this feature permitted to call
## ResourceLoader.load(). It depends only on the domain type it hydrates
## (SpellDefinition) and the port it implements.
##
## Usage:
##   var repo: SpellRepositoryPort = SpellResourceLoader.new()
##   var fire_bolt = repo.get_spell("fire_bolt")
##   fire_bolt.actions   # 2

class_name SpellResourceLoader
extends "res://core/rules/ports/spell_repository_port.gd"

const SpellDefinitionClass = preload("res://core/rules/spell_definition.gd")

## Production spell_id -> .tres path mapping. A test may inject its own
## Dictionary via _init() to exercise the loader against fixtures without
## touching this production mapping.
const DEFAULT_SPELL_PATHS: Dictionary = {
	"fire_bolt": "res://resources/spells/fire_bolt.tres",
	"channel": "res://resources/spells/channel.tres",
}

var _spell_paths: Dictionary = {}
var _cache: Dictionary = {}
var _loaded: bool = false


func _init(spell_paths: Dictionary = DEFAULT_SPELL_PATHS) -> void:
	_spell_paths = spell_paths


## get_spell(spell_id) -> SpellDefinition | null — SpellRepositoryPort
## contract. Triggers lazy-loading of every configured spell_id -> path
## mapping on first call, then serves subsequent calls from cache.
func get_spell(spell_id: String):
	_ensure_loaded()
	return _cache.get(spell_id, null)


## register(spell_id, spell_definition) -> bool
##
## Validates `spell_definition` via is_valid()/validation_error() before
## caching it under `spell_id`. Returns false — and never caches the
## definition, so it is never discoverable via get_spell() — when
## validation fails or `spell_definition` is null. Returns true and caches
## it otherwise. Both the production ResourceLoader.load() path
## (_ensure_loaded()) and tests exercising rejection of malformed data call
## this SAME method, so the enforcement logic never diverges.
func register(spell_id: String, spell_definition) -> bool:
	if spell_definition == null or not spell_definition.is_valid():
		var reason: String = spell_definition.validation_error() if spell_definition != null else "spell resource is null"
		push_error("SpellResourceLoader: rejecting malformed spell '%s': %s" % [spell_id, reason])
		return false
	_cache[spell_id] = spell_definition
	return true


## _ensure_loaded() -> void — loads every configured spell_id -> path
## mapping exactly once (guarded by _loaded), via ResourceLoader.load() +
## register(). A path that fails to load (ResourceLoader returns null) is
## logged and skipped — it simply never becomes discoverable, matching
## register()'s own "malformed data is silently unavailable, never a
## crash" contract.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for spell_id in _spell_paths.keys():
		var path: String = _spell_paths[spell_id]
		var resource = ResourceLoader.load(path)
		if resource == null:
			push_error("SpellResourceLoader: failed to load spell resource '%s' at %s" % [spell_id, path])
			continue
		register(spell_id, resource)
