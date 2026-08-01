extends GutTest
## tests/unit/presentation/test_resolve_spell_controller.gd — FEAT-009
## (US-008; FR-011, ADR-005)
##
## GUT suite for presentation/verbs/resolve_spell_controller.gd's
## ResolveSpellController post-resolve DISCHARGE hook
## (`_maybe_discharge_item()`): the exit-point half of the item-implement
## steel thread (BeginCastUseCase's FEAT-007 charge-state guard is the
## entry-point half). Mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's
## established "fake, duck-typed port doubles / real domain objects"
## convention exactly -- no adapter, no engine boot (except the final
## smoke-check suite, which reuses the SAME real BeginCastUseCase already
## exercised by tests/unit/test_begin_cast_use_case.gd, still with zero
## engine boot).
##
## test_criteria covered:
##   1. After a successful Frost Breath resolve, orb_gram.is_charged==false.
##   2. After a successful 0-cost spell resolve (e.g. fire_bolt/Channel), no
##      equipped item's is_charged is mutated.
##   3. The discharge hook is a no-op (never throws) when no equipped item
##      matches the resolved spell's spell_id.
##   4. Incremental smoke check: castable_spell_ids(actor) called
##      immediately after discharge excludes "frost_breath".

const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const BeginCastUseCaseClass       = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const EffectKindClass             = preload("res://core/domain/effects/effect_kind.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeSpellCatalogPort -- duck-typed SpellCatalogPort double (mirrors
## tests/unit/test_resolve_cast_use_case_resolution.gd's own identical
## double).
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## FakeRoundEnergyPoolPort -- mirrors tests/unit/test_begin_cast_use_case.gd's
## own identical double (needed only by the smoke-check suite's
## castable_spell_ids() call).
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int

	func _init(starting_balance: int) -> void:
		_balance = starting_balance

	func reserve(_caster_id: String, amount: int) -> bool:
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## ScriptedResolutionPort -- always resolves to the same scripted
## AttackResult (mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's
## SpyResolutionPort, minus the call-recording -- not needed by this suite).
class ScriptedResolutionPort:
	extends ResolutionPortClass
	var scripted_result: Dictionary = {"hit": true, "crit": false, "roll_total": 18, "damage_raw": 5, "active_defense_applied": "none", "damage_final": 5}

	func resolve_spell_attack(_attacker, _target, _spell, _defense_type) -> Dictionary:
		return scripted_result


## ScriptedTargetingPort -- always returns the same pre-picked target
## (mirrors tests/unit/test_resolve_cast_use_case_resolution.gd's own
## identical double).
class ScriptedTargetingPort:
	extends RefCounted
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


## FakeEquippedItem -- FEAT-006's duck-typed equipped-item double (mirrors
## tests/unit/test_begin_cast_use_case.gd's own identical double), extended
## here with a real, mutable `is_charged` field so a test can assert the
## discharge hook actually flips it.
class FakeEquippedItem:
	extends RefCounted
	var prepared_spell_id: String = ""
	var is_charged: bool = false

	func _init(p_prepared_spell_id: String = "", p_is_charged: bool = false) -> void:
		prepared_spell_id = p_prepared_spell_id
		is_charged = p_is_charged


## FakeItemUserActor -- mirrors tests/unit/test_begin_cast_use_case.gd's own
## identical double: a duck-typed actor exposing a REAL, declared
## `equipped_items` property (unlike core/domain/combatant.gd's Combatant,
## which carries no such field -- only infrastructure/combatant_factory.gd's
## output Dictionary does, FEAT-005), plus the casting_state/is_casting()/
## begin_cast()/display_id() surface ResolveSpellController.execute() reads.
class FakeItemUserActor:
	extends RefCounted
	var known_spell_ids: Array = []
	var equipped_items: Array = []
	var casting_state: Dictionary = {}
	var hex_coord: HexCoordClass
	var _combatant_id: String

	func _init(combatant_id: String, p_hex_coord: HexCoordClass, p_equipped_items: Array = []) -> void:
		_combatant_id = combatant_id
		hex_coord = p_hex_coord
		equipped_items = p_equipped_items

	func display_id() -> String:
		return _combatant_id

	func is_casting() -> bool:
		return not casting_state.is_empty()

	func cancel_cast() -> void:
		casting_state = {}


func _frost_breath(energy_cost: int = 1) -> SpellClass:
	return SpellClass.new("frost_breath", "Frost Breath", 2, energy_cost, SpellClass.Defense.FORTITUDE, 30, "2d6+ATTR", "cold", ["Concentrate"], EffectKindClass.DAMAGE, {}, "dazed")


func _fire_bolt(energy_cost: int = 0) -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, energy_cost, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _channel() -> SpellClass:
	return SpellClass.new("channel", "Channel", 1, 0, SpellClass.Defense.NONE, 0, "", "", [], EffectKindClass.ADD_ENERGY, {"amount": 1})


func _caster(hex_coord: HexCoordClass, equipped_items: Array, spell_id: String, remaining_actions: int = 0) -> FakeItemUserActor:
	var actor := FakeItemUserActor.new("gram_marx_1", hex_coord, equipped_items)
	actor.casting_state = {
		"spell_id": spell_id,
		"remaining_actions": remaining_actions,
		"committed_energy": 0,
		"caster_id": "gram_marx_1",
	}
	return actor


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 10
	e.hp_max = 10
	e.reflex = 12
	e.fortitude = 12
	return e


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- a successful Frost Breath resolve discharges the
# item that prepared it (orb_gram.is_charged: true -> false)
# ══════════════════════════════════════════════════════════════════════════

func test_successful_frost_breath_resolve_discharges_the_preparing_item() -> void:
	var orb_gram := FakeEquippedItem.new("frost_breath", true)
	var actor := _caster(HexCoordClass.new(0, 0), [orb_gram], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"))
	assert_true(result.get("resolve_cast_result", {}).get("success"), "fixture assumption: the resolve must genuinely succeed for the discharge hook to run at all")
	assert_false(orb_gram.is_charged, "orb_gram.is_charged must be false once Frost Breath (energy_cost>0) successfully resolves")


func test_successful_frost_breath_resolve_via_pre_chosen_target_discharges_the_preparing_item() -> void:
	# The synchronous pre_chosen_target_id path (no TargetingPort call) --
	# the discharge hook must fire here too, not only the awaited
	# TargetingPort branch above.
	var orb_gram := FakeEquippedItem.new("frost_breath", true)
	var actor := _caster(HexCoordClass.new(0, 0), [orb_gram], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var resolution := ScriptedResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor, 0, "skeleton")

	assert_true(result.get("success"))
	assert_false(orb_gram.is_charged, "the pre-chosen-target resolve path must ALSO discharge the preparing item")


func test_missed_frost_breath_resolve_still_discharges_the_preparing_item() -> void:
	# The item is consumed by successfully CASTING (energy_cost>0), not by
	# LANDING the hit -- a miss still burns the charge (design notes'
	# error_handling: discharge is gated on resolve success, not hit).
	var orb_gram := FakeEquippedItem.new("frost_breath", true)
	var actor := _caster(HexCoordClass.new(0, 0), [orb_gram], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()
	resolution.scripted_result = {"hit": false, "crit": false, "roll_total": 2, "damage_raw": 0, "active_defense_applied": "none", "damage_final": 0}

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	await controller.execute(actor)

	assert_false(orb_gram.is_charged, "a missed attack roll still discharges the item -- resolution succeeded, only the attack itself missed")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- a successful 0-cost spell resolve never mutates any
# equipped item's is_charged
# ══════════════════════════════════════════════════════════════════════════

func test_successful_zero_cost_fire_bolt_resolve_does_not_discharge_any_equipped_item() -> void:
	var item := FakeEquippedItem.new("fire_bolt", true)
	var actor := _caster(HexCoordClass.new(0, 0), [item], "fire_bolt")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt(0)
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("resolve_cast_result", {}).get("success"), "fixture assumption: the 0-cost Fire Bolt resolve must genuinely succeed")
	assert_true(item.is_charged, "a 0-cost spell's successful resolve must never discharge an equipped item, even one that prepares the SAME spell_id")


func test_successful_zero_cost_channel_self_cast_resolve_does_not_discharge_any_equipped_item() -> void:
	var item := FakeEquippedItem.new("channel", true)
	var actor := _caster(HexCoordClass.new(0, 0), [item], "channel")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"energy_pool_fn": func(_c): return null,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"))
	assert_true(item.is_charged, "Channel's self-cast (0-cost, ADD_ENERGY) resolve must never discharge an equipped item")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- the discharge hook is a no-op (never throws) when no
# equipped item matches the resolved spell's spell_id
# ══════════════════════════════════════════════════════════════════════════

func test_discharge_hook_is_a_safe_no_op_when_no_equipped_item_matches() -> void:
	var unrelated_item := FakeEquippedItem.new("some_other_spell", true)
	var actor := _caster(HexCoordClass.new(0, 0), [unrelated_item], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"), "an unmatched equipped item must never prevent (or throw during) a successful resolve")
	assert_true(unrelated_item.is_charged, "an item that does not prepare the resolved spell must never be discharged")


func test_discharge_hook_is_a_safe_no_op_with_no_equipped_items_at_all() -> void:
	var actor := _caster(HexCoordClass.new(0, 0), [], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"), "an actor with no equipped_items at all must resolve successfully -- the discharge hook must never throw on an empty Array")


func test_discharge_hook_is_a_safe_no_op_when_resolve_cast_result_is_null() -> void:
	# No ResolutionPort wired -- ResolveCastUseCase is never driven at all
	# (_maybe_resolve_attack() returns null), so the discharge hook must see
	# a null resolve_cast_result and still not throw.
	var item := FakeEquippedItem.new("frost_breath", true)
	var actor := _caster(HexCoordClass.new(0, 0), [item], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
	})

	await controller.execute(actor)

	assert_true(item.is_charged, "with no ResolutionPort wired, resolve_cast_result is null -- the discharge hook must not fire (and must not throw)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- incremental smoke check: castable_spell_ids(actor) called
# immediately after discharge excludes "frost_breath" (mitigates RISK-001)
# ══════════════════════════════════════════════════════════════════════════

func test_smoke_check_castable_spell_ids_excludes_frost_breath_immediately_after_discharge() -> void:
	var orb_gram := FakeEquippedItem.new("frost_breath", true)
	var actor := _caster(HexCoordClass.new(0, 0), [orb_gram], "frost_breath")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["frost_breath"] = _frost_breath()
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = target
	var resolution := ScriptedResolutionPort.new()
	var pool := FakeRoundEnergyPoolPort.new(99)

	# Before the cast resolves, Frost Breath is offered (the item is
	# charged) -- confirms the fixture is meaningful, mirroring FEAT-006's
	# own castable_spell_ids() contract.
	var begin_cast_use_case := BeginCastUseCaseClass.new()
	var before: Array = begin_cast_use_case.castable_spell_ids(actor, catalog, pool)
	assert_true(before.has("frost_breath"), "fixture assumption: a charged item-prepared spell must be offered BEFORE the cast resolves")

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [target],
		"resolution_port": resolution,
	})
	var result: Dictionary = await controller.execute(actor)
	assert_true(result.get("resolve_cast_result", {}).get("success"))
	assert_false(orb_gram.is_charged, "fixture assumption: the discharge hook must have already flipped is_charged before this smoke check runs")

	var after: Array = begin_cast_use_case.castable_spell_ids(actor, catalog, pool)
	assert_false(after.has("frost_breath"), "post-discharge castable_spell_ids() must no longer offer frost_breath (RISK-001)")
