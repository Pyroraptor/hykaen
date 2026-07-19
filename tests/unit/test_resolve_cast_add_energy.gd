extends GutTest
## tests/unit/test_resolve_cast_add_energy.gd — FEAT-277 (US-012; FR-013)
##
## GUT suite for core/application/use_cases/resolve_cast_use_case.gd's
## FEAT-277 extension: a spell whose `spell.effect_type` is
## core/domain/effects/effect_kind.gd EffectKind.ADD_ENERGY (e.g. Channel)
## resolves through the IDENTICAL ResolveCastUseCase.execute() entry point
## every attack-defense spell (Fire Bolt) already drives (design notes:
## "Routes Channel through the identical SpellActionController/
## ResolveSpellController/ResolveCastUseCase path (no bespoke verb)") —
## dispatched to a dedicated ADD_ENERGY branch that:
##   1. NEVER invokes ResolutionPort (there is no attack roll for Channel).
##   2. Applies +1 energy (spell.effect_params["amount"]) to the CASTER's
##      own round-scoped core/domain/energy_pool.gd EnergyPool, obtained via
##      the injected `energy_pool_fn` Callable(caster) -> EnergyPool.
##   3. Still runs the SAME CLEANUP (casting_state cleared) + LOG
##      (CAST_RESOLVE CombatLogEntry, with `energy_delta` set and
##      `target_ids=[]`/`hit=null`/`damage_amount=null`) steps FEAT-276
##      established for every other branch of this use case.
##
## Mirrors tests/unit/test_resolve_cast_effect_mapping.gd's established
## "fake, duck-typed port doubles / real domain objects" convention
## (SpyResolutionPort, SpyCombatLogPort, _caster_at()/_channel() fixture
## helpers) — this suite additionally drives a REAL core/domain/
## energy_pool.gd EnergyPool to prove the caster's pool genuinely gains
## energy through this seam.
##
## test_criteria covered (FEAT-277):
##   - "Boot-real test confirms a Channel cast (1 action, no targeting)
##     resolves through SpellActionController/ResolveSpellController and
##     adds +1 to the caster's round energy pool" — the unit-level proof of
##     the ResolveCastUseCase half lives here; the full boot-real proof
##     lives in tests/boot/test_channel_cast_e2e.gd.
##   - "Boot-real test confirms a CAST_RESOLVE log entry is emitted for
##     Channel with energy_delta=1 and empty target_ids" — the unit-level
##     proof lives here.

const ResolutionPortClass     = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPortClass      = preload("res://core/application/ports/combat_log_port.gd")
const CombatLogEntryClass     = preload("res://core/domain/combat_log_entry.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const SpellClass              = preload("res://core/domain/spell.gd")
const EnergyPoolClass         = preload("res://core/domain/energy_pool.gd")
const ErrorCodeClass          = preload("res://core/application/ports/errors.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyResolutionPort -- records whether it was ever called at all (mirrors
## test_resolve_cast_effect_mapping.gd's identically-named double).
class SpyResolutionPort:
	extends ResolutionPortClass
	var calls: Array = []

	func resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary:
		calls.append([attacker, target, spell, defense_type])
		return {"hit": true, "damage_final": 999}


## SpyCombatLogPort -- records every emit() call's entry (mirrors
## tests/unit/test_resolve_cast_combat_log.gd's identically-named double).
class SpyCombatLogPort:
	extends CombatLogPortClass
	var entries: Array = []

	func emit(entry) -> void:
		entries.append(entry)


func _channel() -> SpellClass:
	return SpellClass.new("channel", "Channel", 1, 0, SpellClass.Defense.NONE, 0, "", "", ["Concentrate"], SpellClass.EffectKindClass.ADD_ENERGY, {"amount": 1})


func _caster_at(hex_coord: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = ["channel"]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": "channel",
		"remaining_actions": 0,
		"committed_energy": 0,
		"caster_id": "marigold_1",
	}
	return c


func _energy_pool_fn_for(pool: EnergyPoolClass) -> Callable:
	return func(_caster): return pool


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 -- ResolutionPort is never invoked for an ADD_ENERGY spell
# ══════════════════════════════════════════════════════════════════════════

func test_execute_never_invokes_resolution_port_for_channel() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var spy := SpyResolutionPort.new()
	var pool := EnergyPoolClass.new(4)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], spy, null, _energy_pool_fn_for(pool))

	assert_true(spy.calls.is_empty(), "ADD_ENERGY spells must never invoke ResolutionPort -- there is no attack roll")
	assert_true(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.NONE)


func test_execute_succeeds_for_channel_with_a_null_resolution_port() -> void:
	# Unlike the DAMAGE branch, a null resolution_port must NOT be an
	# ERR_INVALID_STATE failure for an ADD_ENERGY spell -- no attack roll is
	# ever needed for it.
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], null, null, _energy_pool_fn_for(pool))

	assert_true(result.get("success"), "a null ResolutionPort must not fail an ADD_ENERGY resolve")
	assert_eq(result.get("error"), ErrorCodeClass.NONE)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- +1 energy (spell.effect_params.amount) applied to the
# caster's own round energy pool
# ══════════════════════════════════════════════════════════════════════════

func test_execute_adds_one_energy_to_the_casters_own_pool() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)
	assert_eq(pool.current, 0, "fixture assumption: a freshly-created pool starts empty")

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], null, null, _energy_pool_fn_for(pool))

	assert_eq(pool.current, 1, "Channel's authored effect_params.amount=1 must add exactly +1 to the caster's own round energy pool")


func test_execute_passes_the_live_caster_to_energy_pool_fn() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)
	var received_callers: Array = []
	var fn := func(c):
		received_callers.append(c)
		return pool

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], null, null, fn)

	assert_eq(received_callers.size(), 1, "energy_pool_fn must be called exactly once")
	assert_same(received_callers[0], caster, "energy_pool_fn must be handed the SAME live caster instance")


func test_execute_degrades_safely_with_no_energy_pool_fn_wired() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], null)

	assert_true(result.get("success"), "an unwired energy_pool_fn must degrade safely, never crash")
	assert_false(caster.is_casting(), "casting_state must still be cleared even when energy_pool_fn is unwired")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 -- CLEANUP + LOG (CAST_RESOLVE, energy_delta=1, empty
# target_ids)
# ══════════════════════════════════════════════════════════════════════════

func test_execute_clears_casting_state_for_channel() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)
	assert_true(caster.is_casting(), "fixture assumption: caster must be mid-cast before resolution")

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], null, null, _energy_pool_fn_for(pool))

	assert_false(caster.is_casting(), "casting_state must be cleared immediately after a Channel resolve")
	assert_true(caster.casting_state.is_empty())


func test_execute_emits_a_cast_resolve_entry_with_energy_delta_one_and_empty_target_ids() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], null, log_spy, _energy_pool_fn_for(pool))

	assert_eq(log_spy.entries.size(), 1, "exactly one CAST_RESOLVE entry must be emitted for a Channel cast")
	var entry = log_spy.entries[0]
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "marigold_1")
	assert_eq(entry.spell_id, "channel")
	assert_eq(entry.target_ids, [], "Channel's ADD_ENERGY effect has no target -- target_ids must be empty")
	assert_null(entry.hit, "Channel is not an attack -- hit must be null")
	assert_null(entry.damage_amount, "Channel deals no damage -- damage_amount must be null")
	assert_eq(entry.energy_delta, 1, "energy_delta must equal the +1 actually applied to the caster's round energy pool")


func test_no_combat_log_port_wired_never_crashes_for_channel() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], null, null, _energy_pool_fn_for(pool))

	assert_true(result.get("success"))
	assert_false(caster.is_casting())


func test_execute_fails_safe_with_null_caster_for_channel() -> void:
	var spell := _channel()
	var pool := EnergyPoolClass.new(4)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(null, spell, [], null, null, _energy_pool_fn_for(pool))

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)
	assert_eq(pool.current, 0, "a null caster must never reach the energy pool mutation")
