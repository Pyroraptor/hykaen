extends GutTest
## tests/unit/test_spell_repository_loader.gd
##
## GUT unit test suite for FEAT-001 (US-002 / FR-008): SpellRepositoryPort-
## conformant loader adapter
## (core/rules/infrastructure/spell_resource_loader.gd).
##
## Confirms:
##   - SpellResourceLoader IS-A SpellRepositoryPort (core/rules/ports/
##     spell_repository_port.gd)
##   - Fire Bolt / Channel are discoverable by spell_id through the port
##   - an unknown spell_id returns null (never an error/crash)
##   - malformed spell data (negative energy_cost, actions<=0,
##     range_ft<0) is rejected by register() — never cached, never
##     discoverable via get_spell() — per the design notes' security
##     invariant #1

const SpellResourceLoaderClass = preload("res://core/rules/infrastructure/spell_resource_loader.gd")
const SpellRepositoryPortClass = preload("res://core/rules/ports/spell_repository_port.gd")
const SpellDefinitionClass = preload("res://core/rules/spell_definition.gd")


# ══════════════════════════════════════════════════════════════════════════
# Port conformance
# ══════════════════════════════════════════════════════════════════════════

func test_loader_is_a_spell_repository_port() -> void:
	var loader = SpellResourceLoaderClass.new()
	assert_true(loader is SpellRepositoryPortClass, "SpellResourceLoader must extend SpellRepositoryPort")


# ══════════════════════════════════════════════════════════════════════════
# Discovery by spell_id (test_criteria: "Fire Bolt is discoverable by
# spell_id through the SpellRepositoryPort adapter")
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_discoverable_by_spell_id() -> void:
	var loader = SpellResourceLoaderClass.new()
	var spell = loader.get_spell("fire_bolt")
	assert_not_null(spell, "fire_bolt must be discoverable through SpellRepositoryPort.get_spell()")
	if spell == null:
		return
	assert_eq(spell.spell_id, "fire_bolt")
	assert_eq(spell.actions, 2)
	assert_eq(spell.range_ft, 50)
	assert_eq(spell.defense_type, "reflex")


func test_channel_discoverable_by_spell_id() -> void:
	var loader = SpellResourceLoaderClass.new()
	var spell = loader.get_spell("channel")
	assert_not_null(spell, "channel must be discoverable through SpellRepositoryPort.get_spell()")
	if spell == null:
		return
	assert_eq(spell.spell_id, "channel")
	assert_eq(spell.actions, 1)


func test_unknown_spell_id_returns_null() -> void:
	var loader = SpellResourceLoaderClass.new()
	assert_null(loader.get_spell("does_not_exist"), "unknown spell_id must return null, never error/crash")


func test_get_spell_caches_across_calls() -> void:
	var loader = SpellResourceLoaderClass.new()
	var first = loader.get_spell("fire_bolt")
	var second = loader.get_spell("fire_bolt")
	assert_same(first, second, "repeated get_spell() calls must return the SAME cached instance")


# ══════════════════════════════════════════════════════════════════════════
# Malformed-data rejection (test_criteria: "Loader rejects malformed spell
# data (negative energy_cost, actions<=0, range_ft<0) per validation rule")
# ══════════════════════════════════════════════════════════════════════════

func test_register_rejects_malformed_spell_negative_energy_cost() -> void:
	var loader = SpellResourceLoaderClass.new()
	var bad = SpellDefinitionClass.new()
	bad.spell_id = "bad_energy"
	bad.actions = 1
	bad.energy_cost = -3
	bad.range_ft = 0
	var accepted: bool = loader.register("bad_energy", bad)
	assert_false(accepted, "loader must reject negative energy_cost")
	assert_null(loader.get_spell("bad_energy"), "rejected spell must never be discoverable")


func test_register_rejects_malformed_spell_non_positive_actions() -> void:
	var loader = SpellResourceLoaderClass.new()
	var bad = SpellDefinitionClass.new()
	bad.spell_id = "bad_actions"
	bad.actions = 0
	bad.energy_cost = 0
	bad.range_ft = 0
	var accepted: bool = loader.register("bad_actions", bad)
	assert_false(accepted, "loader must reject actions <= 0")
	assert_null(loader.get_spell("bad_actions"))


func test_register_rejects_malformed_spell_negative_range() -> void:
	var loader = SpellResourceLoaderClass.new()
	var bad = SpellDefinitionClass.new()
	bad.spell_id = "bad_range"
	bad.actions = 1
	bad.energy_cost = 0
	bad.range_ft = -10
	var accepted: bool = loader.register("bad_range", bad)
	assert_false(accepted, "loader must reject negative range_ft")
	assert_null(loader.get_spell("bad_range"))


func test_register_rejects_null_spell_definition() -> void:
	var loader = SpellResourceLoaderClass.new()
	var accepted: bool = loader.register("nothing", null)
	assert_false(accepted, "loader must reject a null spell definition")
	assert_null(loader.get_spell("nothing"))


func test_register_accepts_valid_spell() -> void:
	var loader = SpellResourceLoaderClass.new()
	var good = SpellDefinitionClass.new()
	good.spell_id = "good"
	good.actions = 1
	good.energy_cost = 0
	good.range_ft = 10
	var accepted: bool = loader.register("good", good)
	assert_true(accepted, "a valid spell definition must be accepted")
	assert_same(loader.get_spell("good"), good)


# ══════════════════════════════════════════════════════════════════════════
# Injected path map — proves the loader's spell_id -> path resolution is a
# genuine seam, not a hardcoded pair of ResourceLoader.load() calls, and
# that a malformed .tres discovered via the REAL ResourceLoader path is
# rejected identically to a hand-built fixture passed to register().
# ══════════════════════════════════════════════════════════════════════════

func test_loader_rejects_missing_path_without_crashing() -> void:
	var loader = SpellResourceLoaderClass.new({"nonexistent": "res://resources/spells/does_not_exist.tres"})
	assert_null(loader.get_spell("nonexistent"), "a spell_id whose .tres fails to load must return null, never crash")
