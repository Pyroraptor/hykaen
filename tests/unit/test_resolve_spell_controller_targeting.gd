extends GutTest
## tests/unit/test_resolve_spell_controller_targeting.gd — FEAT-008 (US-008;
## FR-007, ADR-007)
##
## GUT suite for:
##   - core/application/ports/targeting_port.gd's TargetingPort abstract
##     contract sanity.
##   - presentation/verbs/resolve_spell_controller.gd's ResolveSpellController
##     -- the strict remaining_actions==0 gate, range-filtered candidate
##     selection, and the self-target (range_ft<=0) short-circuit.
##   - presentation/verbs/spell_action_controller.gd's SpellActionController
##     wiring: `_maybe_resolve_cast()` invokes ResolveSpellController.execute()
##     ONLY once a Begin/ContinueCastUseCase call drives remaining_actions to
##     exactly 0.
##
## Mirrors tests/unit/test_begin_cast_use_case.gd's / tests/unit/
## test_continue_cast_use_case.gd's established "fake, duck-typed port
## doubles / real domain objects" convention -- no adapter, no engine boot.
##
## test_criteria covered:
##   1. TargetingPort is invoked only when casting_state.remaining_actions
##      reaches 0.
##   2. out-of-range targets are excluded from the selectable set for Fire
##      Bolt (50ft).
##   3. a cancelled/interrupted casting_state never triggers targeting.

const TargetingPortClass          = preload("res://core/application/ports/targeting_port.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const RoundSessionHolderClass     = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const EnergyPoolClass             = preload("res://core/domain/energy_pool.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeSpellCatalogPort -- duck-typed SpellCatalogPort double (mirrors
## tests/unit/test_begin_cast_use_case.gd's own identical double).
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## SpyTargetingPort -- records every request_single_target() call's
## `legal_targets` argument (so a test can assert exactly which candidates
## survived range filtering) and returns a scripted target (or null).
class SpyTargetingPort:
	extends TargetingPortClass
	var calls: Array = []
	var scripted_target = null

	func request_single_target(legal_targets: Array):
		calls.append(legal_targets.duplicate())
		if legal_targets.is_empty():
			return null
		return scripted_target


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _channel() -> SpellClass:
	return SpellClass.new("channel", "Channel", 1, 0, SpellClass.Defense.NONE, 0, "", "", [], SpellClass.EffectKindClass.ADD_ENERGY, {"amount": 1})


func _caster_at(hex_coord: HexCoordClass, remaining_actions: int = 0, spell_id: String = "fire_bolt", casting: bool = true):
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = [spell_id]
	if casting:
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
	return e


# ══════════════════════════════════════════════════════════════════════════
# TargetingPort -- abstract contract sanity
# ══════════════════════════════════════════════════════════════════════════

func test_targeting_port_empty_legal_targets_always_resolves_to_null() -> void:
	var port := TargetingPortClass.new()
	assert_null(port.request_single_target([]), "an empty legal_targets Array must always yield null, never an error")


func test_targeting_port_request_aoe_targets_defaults_to_returning_every_legal_target() -> void:
	var port := TargetingPortClass.new()
	var targets: Array = ["a", "b"]
	assert_eq(port.request_aoe_targets(targets), targets, "the base AoE extension point defaults to passing every legal target through unfiltered")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- TargetingPort invoked ONLY when remaining_actions == 0
# ══════════════════════════════════════════════════════════════════════════

func test_execute_does_not_invoke_targeting_port_when_actor_is_null() -> void:
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"targeting_port": targeting})

	var result: Dictionary = await controller.execute(null)

	assert_true(targeting.calls.is_empty(), "TargetingPort must never be invoked for a null actor")
	assert_false(result.get("success"))
	assert_null(result.get("target_id"))


func test_execute_does_not_invoke_targeting_port_when_actor_is_not_casting() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "fire_bolt", false)
	assert_false(actor.is_casting())
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"targeting_port": targeting})

	await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "TargetingPort must never be invoked for an actor who is not mid-cast at all")


func test_execute_does_not_invoke_targeting_port_when_remaining_actions_is_above_zero() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 1)  # Fire Bolt, 1 action still owed
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"spell_catalog_port": catalog, "targeting_port": targeting})

	var result: Dictionary = await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "TargetingPort must never be invoked while remaining_actions > 0")
	assert_false(result.get("success"))
	assert_null(result.get("target_id"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE, "a not-yet-time-to-resolve gate result must not fabricate a real failure error code")


func test_execute_invokes_targeting_port_exactly_once_when_remaining_actions_is_zero() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0)
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var enemy := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := SpyTargetingPort.new()
	targeting.scripted_target = enemy
	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [enemy],
	})

	var result: Dictionary = await controller.execute(actor)

	assert_eq(targeting.calls.size(), 1, "TargetingPort.request_single_target() must be invoked exactly once when remaining_actions reaches 0")
	assert_true(result.get("success"))
	assert_eq(result.get("target_id"), "skeleton")
	assert_eq(result.get("error"), ErrorCodeClass.NONE)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- out-of-range targets excluded from the selectable set
# (Fire Bolt, 50ft == 10 hexes at 1 hex == 5 ft)
# ══════════════════════════════════════════════════════════════════════════

func test_out_of_range_targets_are_excluded_from_the_set_handed_to_targeting_port() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0)
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()  # range_ft = 50 -> 10 hexes

	var in_range := _enemy("in_range", HexCoordClass.new(10, 0))       # hex_distance 10 -- exactly at range
	var out_of_range := _enemy("out_of_range", HexCoordClass.new(11, 0))  # hex_distance 11 -- beyond range
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [in_range, out_of_range],
	})

	await controller.execute(actor)

	assert_eq(targeting.calls.size(), 1)
	var legal_targets: Array = targeting.calls[0]
	assert_true(legal_targets.has(in_range), "a target at exactly range_ft (converted to hexes) must be selectable")
	assert_false(legal_targets.has(out_of_range), "a target beyond range_ft (converted to hexes) must be excluded from the selectable set")
	assert_eq(legal_targets.size(), 1, "only the in-range candidate may reach TargetingPort")


func test_execute_returns_no_valid_target_when_every_candidate_is_out_of_range() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0)
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()

	var out_of_range := _enemy("far_away", HexCoordClass.new(99, 0))
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [out_of_range],
	})

	var result: Dictionary = await controller.execute(actor)

	assert_eq(targeting.calls, [[]], "TargetingPort must still be asked, but with an EMPTY legal_targets Array, when every candidate is out of range")
	assert_true(result.get("success"), "a wasted-action resolve (no valid target) is still a successful resolution step, per api_contracts #2")
	assert_null(result.get("target_id"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_NO_VALID_TARGET)


func test_channel_self_target_spell_never_invokes_targeting_port() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "channel")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"spell_catalog_port": catalog, "targeting_port": targeting})

	var result: Dictionary = await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "a self/no-target spell (range_ft <= 0, e.g. Channel) must never open targeting at all")
	assert_true(result.get("success"))
	assert_eq(result.get("target_id"), "marigold_1", "a self-targeted spell resolves its target_id to the caster's own id")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-277 (US-012; FR-013) -- Channel routes through the SAME
# ResolveCastUseCase every attack-defense spell drives (no bespoke verb),
# applying +1 energy to the caster's own round energy pool via the
# injected "energy_pool_fn" dep.
# ══════════════════════════════════════════════════════════════════════════

func test_channel_self_cast_attaches_resolve_cast_result_and_adds_energy_to_the_pool() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "channel")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()
	var pool := EnergyPoolClass.new(4)
	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"energy_pool_fn": func(_c): return pool,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"))
	assert_true(result.has("resolve_cast_result"), "Channel must route through ResolveCastUseCase, attaching resolve_cast_result")
	assert_true(result["resolve_cast_result"].get("success"))
	assert_eq(pool.current, 1, "the caster's own round energy pool must gain +1 energy on a resolved Channel cast")
	assert_false(actor.is_casting(), "casting_state must be cleared once Channel resolves")


func test_channel_self_cast_degrades_safely_with_no_energy_pool_fn_wired() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "channel")
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()
	var controller := ResolveSpellControllerClass.new({"spell_catalog_port": catalog})

	var result: Dictionary = await controller.execute(actor)

	assert_true(result.get("success"), "an unwired energy_pool_fn must degrade safely, never crash")
	assert_true(result.has("resolve_cast_result"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- a cancelled/interrupted casting_state never triggers
# targeting
# ══════════════════════════════════════════════════════════════════════════

func test_execute_does_not_invoke_targeting_port_after_cast_is_cancelled() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0)
	assert_true(actor.is_casting())
	assert_eq(actor.casting_state.get("remaining_actions"), 0, "fixture assumption: the cast was at the resolve-eligible boundary before cancellation")

	# Simulate a lethal Opportunistic Strike / interruption clearing the
	# cast (core/domain/combatant.gd's Combatant.cancel_cast()) -- the SAME
	# domain mutator a future CancelCastUseCase invokes.
	actor.cancel_cast()
	assert_false(actor.is_casting(), "fixture assumption: cancel_cast() must clear casting_state back to empty")

	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var enemy := _enemy("skeleton", HexCoordClass.new(1, 0))
	var targeting := SpyTargetingPort.new()
	targeting.scripted_target = enemy
	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [enemy],
	})

	var result: Dictionary = await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "a cancelled/interrupted cast must NEVER trigger targeting, even though remaining_actions had reached 0 immediately before cancellation")
	assert_false(result.get("success"))
	assert_null(result.get("target_id"))


func test_execute_does_not_invoke_targeting_port_for_an_actor_that_never_began_a_cast() -> void:
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	assert_false(actor.is_casting())
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"targeting_port": targeting})

	await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "an actor who never began a cast at all must never trigger targeting")


# ══════════════════════════════════════════════════════════════════════════
# Defensive: unwired collaborators degrade safely
# ══════════════════════════════════════════════════════════════════════════

func test_execute_fails_safe_with_no_targeting_port_wired() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0)
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var controller := ResolveSpellControllerClass.new({"spell_catalog_port": catalog})

	var result: Dictionary = await controller.execute(actor)

	assert_false(result.get("success"))
	assert_null(result.get("target_id"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_NO_VALID_TARGET)


func test_execute_fails_safe_with_unknown_spell_id() -> void:
	var actor = _caster_at(HexCoordClass.new(0, 0), 0, "unknown_spell")
	var catalog := FakeSpellCatalogPort.new()
	var targeting := SpyTargetingPort.new()
	var controller := ResolveSpellControllerClass.new({"spell_catalog_port": catalog, "targeting_port": targeting})

	var result: Dictionary = await controller.execute(actor)

	assert_true(targeting.calls.is_empty(), "an unresolvable spell_id must never reach TargetingPort")
	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)


# ══════════════════════════════════════════════════════════════════════════
# SpellActionController wiring — _maybe_resolve_cast() gate
# ══════════════════════════════════════════════════════════════════════════

## FakeSession -- mirrors tests/unit/test_spell_action_controller_skeleton.gd's
## own FakeSession, EXTENDED with get_energy_pool() (FEAT-005's own
## documented "fail-safe degrade when absent" seam) so BeginCastUseCase's
## real execute() path is reachable from this suite's wiring tests.
class FakeSession:
	var _actor
	var _pools: Dictionary = {}

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null

	func get_energy_pool(caster):
		var key: String = caster.display_id()
		if not _pools.has(key):
			_pools[key] = EnergyPoolClass.new(99, 99)
		return _pools[key]


## SpyResolveSpellController -- records every execute() call's `actor`
## argument, so the wiring tests can assert WHETHER SpellActionController
## invoked it, without needing a full real TargetingPort/candidate chain.
class SpyResolveSpellController:
	extends RefCounted
	var calls: Array = []

	func execute(actor, _round_num: int = 0, _pre_chosen_target_id: String = ""):
		calls.append(actor)
		return {"success": true, "target_id": null, "error": ErrorCodeClass.NONE}


func _deps_with_spy(actor, spy) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder, "resolve_spell_controller": spy}


func test_spell_action_controller_invokes_resolve_spell_controller_when_continue_drains_to_zero() -> void:
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = ["fire_bolt"]
	actor.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0, "caster_id": "marigold_1"}
	var spy := SpyResolveSpellController.new()
	var controller := SpellActionControllerClass.new(_deps_with_spy(actor, spy))

	var result: Dictionary = await controller.execute()

	assert_eq(spy.calls.size(), 1, "a continue-cast call that drives remaining_actions to 0 must invoke ResolveSpellController exactly once")
	assert_same(spy.calls[0], actor, "ResolveSpellController must be handed the SAME live actor instance")
	assert_true(result.has("resolve_spell_result"), "the ExecuteResult must carry the additive resolve_spell_result key")


func test_spell_action_controller_does_not_invoke_resolve_spell_controller_while_actions_remain() -> void:
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = ["fire_bolt"]
	actor.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 2, "committed_energy": 0, "caster_id": "marigold_1"}
	var spy := SpyResolveSpellController.new()
	var controller := SpellActionControllerClass.new(_deps_with_spy(actor, spy))

	var result: Dictionary = await controller.execute()

	assert_true(spy.calls.is_empty(), "ResolveSpellController must not be invoked while remaining_actions is still above 0 after continuing")
	assert_false(result.has("resolve_spell_result"), "the ExecuteResult must not carry resolve_spell_result when the gate is not yet satisfied")


func test_spell_action_controller_invokes_resolve_spell_controller_on_first_cast_of_a_one_action_spell() -> void:
	# Channel is a 1-action spell -- begin_cast() immediately drives
	# remaining_actions to 0 on the FIRST cast, not only a later
	# continuation (file-level doc on SpellActionController's
	# `_maybe_resolve_cast()`).
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = ["channel"]
	var spy := SpyResolveSpellController.new()
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["channel"] = _channel()
	var deps := _deps_with_spy(actor, spy)
	deps["spell_catalog_port"] = catalog
	var controller := SpellActionControllerClass.new(deps)

	var result: Dictionary = await controller.execute("channel")

	assert_true(result.get("success", false), "fixture assumption: the first cast of a known, affordable spell must succeed")
	assert_eq(spy.calls.size(), 1, "a 1-action spell begun this turn must ALSO trigger ResolveSpellController on the FIRST cast")


func test_spell_action_controller_does_not_invoke_resolve_spell_controller_on_first_cast_of_a_two_action_spell() -> void:
	var actor := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = ["fire_bolt"]
	var spy := SpyResolveSpellController.new()
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fire_bolt"] = _fire_bolt()
	var deps := _deps_with_spy(actor, spy)
	deps["spell_catalog_port"] = catalog
	var controller := SpellActionControllerClass.new(deps)

	var result: Dictionary = await controller.execute("fire_bolt")

	assert_true(result.get("success", false), "fixture assumption: the first cast of a known, affordable spell must succeed")
	assert_true(spy.calls.is_empty(), "Fire Bolt's 2-action cost leaves remaining_actions == 1 after the first cast -- ResolveSpellController must not be invoked yet")
	assert_false(result.has("resolve_spell_result"))
