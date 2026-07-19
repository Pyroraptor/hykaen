extends GutTest
## tests/unit/test_resolve_cast_use_case_resolution.gd — FEAT-009 (US-009;
## FR-008)
##
## GUT suite for:
##   - core/application/ports/resolution_port.gd's ResolutionPort abstract
##     contract sanity + its nested ResolutionRulesAdapter (the concrete
##     bridge down to core/rules/resolution.gd's UNMODIFIED
##     resolve_spell_attack()).
##   - core/application/use_cases/resolve_cast_use_case.gd's
##     ResolveCastUseCase — calls ResolutionPort.resolve_spell_attack()
##     once per target, UNMODIFIED (caster/target/spell/spell.defense
##     verbatim).
##   - presentation/verbs/resolve_spell_controller.gd's ResolveSpellController
##     wiring: once TargetingPort resolves a non-null target for an
##     attack-defense spell (e.g. Fire Bolt), ResolveCastUseCase is driven
##     and its result attached under the additive "resolve_cast_result" key;
##     a self/no-attack spell (Channel, Spell.Defense.NONE) never reaches
##     ResolutionPort at all.
##
## Mirrors tests/unit/test_resolve_spell_controller_targeting.gd's / tests/
## unit/test_begin_cast_use_case.gd's established "fake, duck-typed port
## doubles / real domain objects" convention for the unit-level suites; the
## final suite below is this feature's own "boot-real" proof (no separate
## tests/boot/ file is in this feature's scope) — it boots the REAL
## res://MainScene.tscn composition root to source Marigold's/the
## Skeleton's genuinely-authored stats and Fire Bolt's genuinely-authored
## SpellResource data, then drives ResolveCastUseCase/ResolutionRulesAdapter
## directly against them at a pinned seed.
##
## test_criteria covered:
##   1. Unit test confirms resolve_spell_attack is called with (caster,
##      target, fire_bolt_spell, REFLEX).
##   2. Boot-real test at a pinned seed confirms d20 + spell-mod vs target
##      Reflex produces the expected deterministic AttackResult.

const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const ResolveCastUseCaseClass     = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyResolutionPort -- records every resolve_spell_attack() call's
## (attacker, target, spell, defense_type) argument tuple, so a test can
## assert exactly what ResolveCastUseCase/ResolveSpellController handed it,
## and returns a scripted AttackResult.
class SpyResolutionPort:
	extends ResolutionPortClass
	var calls: Array = []
	var scripted_result: Dictionary = {"hit": true, "crit": false, "roll_total": 18, "damage_raw": 5, "active_defense_applied": "none", "damage_final": 5}

	func resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary:
		calls.append([attacker, target, spell, defense_type])
		return scripted_result


## FakeSpellCatalogPort -- duck-typed SpellCatalogPort double (mirrors
## tests/unit/test_resolve_spell_controller_targeting.gd's own identical
## double).
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## ScriptedTargetingPort -- always returns the same pre-picked target
## (or null) regardless of the legal_targets Array handed in.
class ScriptedTargetingPort:
	extends RefCounted
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _channel() -> SpellClass:
	return SpellClass.new("channel", "Channel", 1, 0, SpellClass.Defense.NONE, 0, "", "", [], SpellClass.EffectKindClass.ADD_ENERGY, {"amount": 1})


func _caster_at(hex_coord: HexCoordClass, remaining_actions: int = 0, spell_id: String = "fire_bolt"):
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = [spell_id]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": spell_id,
		"remaining_actions": remaining_actions,
		"committed_energy": 0,
		"caster_id": "marigold_1",
	}
	return c


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 10
	e.hp_max = 10
	e.reflex = 12
	return e


# ══════════════════════════════════════════════════════════════════════════
# ResolutionPort -- abstract contract sanity
# ══════════════════════════════════════════════════════════════════════════

func test_resolution_port_base_resolve_spell_attack_is_abstract_and_fails_safe() -> void:
	var port := ResolutionPortClass.new()
	var result: Dictionary = port.resolve_spell_attack(null, null, null, SpellClass.Defense.REFLEX)
	assert_false(result.get("hit"), "the abstract base must never fabricate a hit")
	assert_true(result.has("error"), "the abstract base must signal it was never overridden")


# ══════════════════════════════════════════════════════════════════════════
# ResolutionRulesAdapter -- bridges Combatant/Spell down to
# core/rules/resolution.gd's UNMODIFIED resolve_spell_attack()
# ══════════════════════════════════════════════════════════════════════════

func test_resolution_rules_adapter_resolves_fire_bolt_against_reflex_deterministically() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(42))
	var result: Dictionary = port.resolve_spell_attack(caster, target, spell, spell.defense)

	assert_false(result.has("error"), "a valid Reflex-defense spell attack must not hit resolution.gd's invalid-defense-type guard")
	assert_true(result.has("hit"))
	assert_true(result.has("roll_total"))

	# Determinism (NFR-002): a second, independently constructed adapter at
	# the SAME seed must reproduce the IDENTICAL AttackResult.
	var port2 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(42))
	var result2: Dictionary = port2.resolve_spell_attack(caster, target, spell, spell.defense)
	assert_eq(result2, result, "the same pinned seed must reproduce an identical AttackResult")


func test_resolution_rules_adapter_rejects_defense_none_via_resolutions_own_guard() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0), 0, "channel")
	var target = caster
	var spell := _channel()

	var port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(42))
	var result: Dictionary = port.resolve_spell_attack(caster, target, spell, spell.defense)

	assert_true(result.has("error"), "Spell.Defense.NONE must never resolve to a fabricated defense; resolution.gd's own guard must reject it")
	assert_false(result.get("hit"))


# ══════════════════════════════════════════════════════════════════════════
# ResolveCastUseCase -- test_criteria #1: resolve_spell_attack is called
# with (caster, target, fire_bolt_spell, REFLEX), UNMODIFIED, per target
# ══════════════════════════════════════════════════════════════════════════

func test_execute_calls_resolution_port_with_caster_target_spell_and_spells_defense_unmodified() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	var spy := SpyResolutionPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], spy)

	assert_eq(spy.calls.size(), 1, "resolve_spell_attack must be invoked exactly once for a single target")
	var call: Array = spy.calls[0]
	assert_same(call[0], caster, "the attacker argument must be the SAME caster instance, unmodified")
	assert_same(call[1], target, "the target argument must be the SAME target instance, unmodified")
	assert_same(call[2], spell, "the spell argument must be the SAME spell instance, unmodified")
	assert_eq(call[3], SpellClass.Defense.REFLEX, "the defense_type argument must be spell.defense verbatim -- Fire Bolt's REFLEX")

	assert_true(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE)
	assert_eq(result.get("results").size(), 1)
	assert_eq(result.get("results")[0].get("target_id"), "skeleton")
	assert_eq(result.get("results")[0].get("attack_result"), spy.scripted_result)


func test_execute_calls_resolution_port_once_per_target() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0))
	var target_a := _enemy("skeleton_a", HexCoordClass.new(1, 0))
	var target_b := _enemy("skeleton_b", HexCoordClass.new(2, 0))
	var spell := _fire_bolt()
	var spy := SpyResolutionPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target_a, target_b], spy)

	assert_eq(spy.calls.size(), 2, "resolve_spell_attack must be invoked exactly once PER target")
	assert_same(spy.calls[0][1], target_a)
	assert_same(spy.calls[1][1], target_b)
	assert_eq(result.get("results").size(), 2)


func test_execute_skips_null_targets_without_invoking_resolution_port() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0))
	var spell := _fire_bolt()
	var spy := SpyResolutionPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [null], spy)

	assert_true(spy.calls.is_empty(), "a null target must never reach ResolutionPort")
	assert_true(result.get("success"))
	assert_true(result.get("results").is_empty())


func test_execute_fails_safe_with_no_resolution_port_wired() -> void:
	var caster = _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], null)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)
	assert_true(result.get("results").is_empty())


func test_execute_fails_safe_with_null_caster() -> void:
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	var spy := SpyResolutionPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(null, spell, [target], spy)

	assert_true(spy.calls.is_empty(), "a null caster must never reach ResolutionPort")
	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)


# ══════════════════════════════════════════════════════════════════════════
# ResolveSpellController wiring -- ResolveCastUseCase is driven once a
# TargetingPort target has been resolved for an attack-defense spell
# ══════════════════════════════════════════════════════════════════════════

func test_controller_attaches_resolve_cast_result_once_fire_bolt_target_is_chosen() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0))
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var enemy := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = enemy
	var spy := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [enemy],
		"resolution_port": spy,
	})

	var result: Dictionary = controller.execute(actor)

	assert_true(result.get("success"))
	assert_eq(result.get("target_id"), "skeleton")
	assert_eq(spy.calls.size(), 1, "ResolutionPort must be invoked exactly once once a target has been chosen for an attack-defense spell")
	assert_same(spy.calls[0][0], actor)
	assert_same(spy.calls[0][1], enemy)
	assert_eq(spy.calls[0][3], SpellClass.Defense.REFLEX)

	assert_true(result.has("resolve_cast_result"), "the ExecuteResult must carry the additive resolve_cast_result key")
	var resolve_cast_result: Dictionary = result["resolve_cast_result"]
	assert_true(resolve_cast_result.get("success"))
	assert_eq(resolve_cast_result.get("results")[0].get("attack_result"), spy.scripted_result)


func test_controller_never_invokes_resolution_port_for_channel_self_target() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "channel")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()
	var spy := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"resolution_port": spy,
	})

	var result: Dictionary = controller.execute(actor)

	assert_true(spy.calls.is_empty(), "a self/no-attack spell (Spell.Defense.NONE, e.g. Channel) must never invoke ResolutionPort")
	assert_true(result.get("success"))
	# FEAT-277 (US-012; FR-013): Channel now resolves through the SAME
	# ResolveCastUseCase every attack-defense spell drives (no bespoke
	# verb) -- the additive resolve_cast_result key IS now attached, even
	# though ResolutionPort itself is (correctly, per the assertion above)
	# never invoked for this ADD_ENERGY effect-type branch.
	assert_true(result.has("resolve_cast_result"), "Channel must resolve through ResolveCastUseCase (FEAT-277), attaching resolve_cast_result")
	var resolve_cast_result: Dictionary = result["resolve_cast_result"]
	assert_true(resolve_cast_result.get("success"))


func test_controller_never_invokes_resolution_port_when_no_valid_target() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0))
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var out_of_range := _enemy("far_away", HexCoordClass.new(99, 0))
	var targeting := ScriptedTargetingPort.new()  # scripted_target stays null
	var spy := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [out_of_range],
		"resolution_port": spy,
	})

	var result: Dictionary = controller.execute(actor)

	assert_true(spy.calls.is_empty(), "no chosen target means nothing to resolve -- ResolutionPort must never be invoked")
	assert_eq(result.get("error"), ErrorCodeClass.ERR_NO_VALID_TARGET)
	assert_false(result.has("resolve_cast_result"))


func test_controller_degrades_safely_with_no_resolution_port_wired() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0))
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var enemy := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = enemy

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [enemy],
	})

	var result: Dictionary = controller.execute(actor)

	assert_true(result.get("success"), "targeting alone must still succeed with no ResolutionPort wired")
	assert_eq(result.get("target_id"), "skeleton")
	assert_false(result.has("resolve_cast_result"), "no resolve_cast_result key must be attached when ResolutionPort is unwired")


# ══════════════════════════════════════════════════════════════════════════
# Boot-real -- pinned-seed determinism against genuinely authored data
# (no separate tests/boot/ file is in this feature's file scope; this
# suite's own boot-real coverage lives here instead)
# ══════════════════════════════════════════════════════════════════════════

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const PROLOGUE_SEED: int = 42


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _find_marigold(instance):
	for combatant in instance._party:
		if combatant.name == "Marigold":
			return combatant
	return null


func test_boot_real_fire_bolt_resolves_deterministically_against_reflex_at_pinned_seed() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var marigold = _find_marigold(instance)
	assert_not_null(marigold, "fixture assumption: Marigold must be present in the live party")
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter's real enemy roster carries exactly the Skeleton")
	var skeleton = instance._enemies[0]

	# Real, production-adapter-loaded spell data -- NOT a hand-authored test
	# fixture -- confirming Fire Bolt genuinely targets Reflex per US-009.
	var catalog := ResourceSpellCatalogAdapterClass.new()
	var fire_bolt = catalog.get_spell("fire_bolt")
	assert_not_null(fire_bolt)
	assert_eq(fire_bolt.defense, SpellClass.Defense.REFLEX, "Fire Bolt's authored SpellResource data must target Reflex")

	var use_case := ResolveCastUseCaseClass.new()
	var port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))
	var result: Dictionary = use_case.execute(marigold, fire_bolt, [skeleton], port)

	assert_true(result.get("success"))
	var attack_result: Dictionary = result.get("results")[0].get("attack_result")
	assert_false(attack_result.has("error"))

	# Independently replay the SAME pinned seed to compute the expected
	# d20 + spell-mod roll -- the SOLE source of randomness for this call
	# (design notes' security section: "Deterministic RNG ... is reused
	# unmodified for resolve_spell_attack").
	var expected_rng := SeededRandomAdapterClass.new(PROLOGUE_SEED)
	var expected_raw: int = expected_rng.d20()
	var expected_roll_total: int = expected_raw + marigold.spellcasting_attribute_score
	assert_eq(attack_result.get("roll_total"), expected_roll_total, "roll_total must equal d20 + spell-mod, deterministically reproduced at the pinned seed")
	assert_eq(attack_result.get("hit"), expected_roll_total >= skeleton.reflex, "hit must be determined against the target's REAL, authored Reflex defense")

	# NFR-002 determinism: a second, independently seeded run reproduces the
	# IDENTICAL AttackResult.
	var port2 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))
	var result2: Dictionary = use_case.execute(marigold, fire_bolt, [skeleton], port2)
	assert_eq(result2.get("results")[0].get("attack_result"), attack_result, "the same pinned seed must reproduce an identical AttackResult")
