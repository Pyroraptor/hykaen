extends GutTest
## tests/unit/test_resolve_cast_combat_log.gd — FEAT-276 (US-011; FR-010)
##
## GUT suite for core/application/use_cases/resolve_cast_use_case.gd's
## FEAT-276 extension: once RESOLUTION/EFFECT have run (or been skipped for
## an empty `targets` Array), ResolveCastUseCase.execute() now:
##   1. Clears `caster.casting_state` unconditionally (via the existing
##      Combatant.cancel_cast() mutator) — regardless of hit/miss.
##   2. Builds one core/domain/combat_log_entry.gd CombatLogEntry
##      (EventType.CAST_RESOLVE) and emits it via the injected
##      core/application/ports/combat_log_port.gd CombatLogPort — skipped
##      entirely when no CombatLogPort is injected.
##
## Mirrors tests/unit/test_resolve_cast_effect_mapping.gd's established
## "fake, duck-typed port doubles / real domain objects" convention
## (SpyResolutionPort, _fire_bolt()/_caster_at()/_enemy() fixture helpers).
##
## test_criteria covered:
##   - "Unit test confirms casting_state is null on the caster immediately
##     after resolution regardless of hit/miss."
##   - CombatLogPort.emit() receives a CAST_RESOLVE entry with the correct
##     spell/target/hit-miss/damage fields.
##
## UPDATED by US-003 (multi-target processing, AoE Fireball steel thread):
## an empty `targets` Array now emits ZERO CombatLogEntries (superseding this
## file's original "one wasted-action entry" assertions — see
## test_no_valid_target_emits_no_cast_resolve_entries below); CLEANUP
## (casting_state clearing) is unchanged. See core/application/use_cases/
## resolve_cast_use_case.gd's own US-003 doc for the full rationale.

const ResolutionPortClass     = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPortClass      = preload("res://core/application/ports/combat_log_port.gd")
const CombatLogEntryClass     = preload("res://core/domain/combat_log_entry.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass          = preload("res://core/domain/combatant.gd")
const HexCoordClass           = preload("res://core/geometry/hex_coord.gd")
const SpellClass              = preload("res://core/domain/spell.gd")
const ErrorCodeClass          = preload("res://core/application/ports/errors.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyResolutionPort -- returns a scripted AttackResult regardless of the
## arguments handed in (mirrors test_resolve_cast_effect_mapping.gd's
## identically-named double).
class SpyResolutionPort:
	extends ResolutionPortClass
	var scripted_result: Dictionary = {}

	func resolve_spell_attack(_attacker, _target, _spell, _defense_type) -> Dictionary:
		return scripted_result


## SpyCombatLogPort -- records every emit() call's entry argument, so a
## test can assert exactly what ResolveCastUseCase built.
class SpyCombatLogPort:
	extends CombatLogPortClass
	var entries: Array = []

	func emit(entry) -> void:
		entries.append(entry)


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _caster_at(hex_coord: HexCoordClass) -> CombatantClass:
	var c := CombatantClass.new("marigold_1", "Marigold", "Player", hex_coord)
	c.known_spell_ids = ["fire_bolt"]
	c.spellcasting_attribute_score = 4
	c.casting_state = {
		"spell_id": "fire_bolt",
		"remaining_actions": 0,
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


func _hit_result(damage_final: int) -> Dictionary:
	return {
		"hit": true,
		"crit": false,
		"roll_total": 18,
		"damage_raw": damage_final,
		"active_defense_applied": "none",
		"damage_final": damage_final,
	}


func _miss_result() -> Dictionary:
	return {
		"hit": false,
		"crit": false,
		"roll_total": 4,
		"damage_raw": 0,
		"active_defense_applied": "none",
		"damage_final": 0,
	}


# ══════════════════════════════════════════════════════════════════════════
# CLEANUP -- casting_state cleared unconditionally
# ══════════════════════════════════════════════════════════════════════════

func test_casting_state_is_cleared_on_a_hit() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	assert_true(caster.is_casting(), "fixture assumption: caster must be mid-cast before resolution")

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(caster.is_casting(), "casting_state must be cleared immediately after resolution on a hit")
	assert_true(caster.casting_state.is_empty())


func test_casting_state_is_cleared_on_a_miss() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(caster.is_casting(), "casting_state must be cleared immediately after resolution on a miss")
	assert_true(caster.casting_state.is_empty())


func test_casting_state_is_cleared_even_with_no_targets() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], resolution_spy)

	assert_true(result.get("success"))
	assert_false(caster.is_casting(), "a wasted-action resolve (no valid target) must still clear casting_state")


func test_casting_state_is_untouched_on_the_defensive_invalid_state_path() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _fire_bolt()
	var use_case := ResolveCastUseCaseClass.new()

	# resolution_port == null -> ERR_INVALID_STATE, defensive/should-be-
	# unreachable path -- must never touch casting_state.
	var result: Dictionary = use_case.execute(caster, spell, [], null)

	assert_eq(result.get("error"), ErrorCodeClass.ERR_INVALID_STATE)
	assert_true(caster.is_casting(), "the defensive ERR_INVALID_STATE path must never clear casting_state")


# ══════════════════════════════════════════════════════════════════════════
# LOG -- CombatLogPort.emit() receives a CAST_RESOLVE entry
# ══════════════════════════════════════════════════════════════════════════

func test_hit_emits_a_cast_resolve_entry_with_hit_true_and_damage_amount() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [target], resolution_spy, log_spy)

	assert_eq(log_spy.entries.size(), 1, "exactly one CAST_RESOLVE entry must be emitted")
	var entry = log_spy.entries[0]
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "marigold_1")
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.target_ids, ["skeleton"])
	assert_true(entry.hit)
	assert_eq(entry.damage_amount, 9)


func test_miss_emits_a_cast_resolve_entry_with_hit_false_and_zero_damage() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [target], resolution_spy, log_spy)

	assert_eq(log_spy.entries.size(), 1)
	var entry = log_spy.entries[0]
	assert_false(entry.hit)
	assert_eq(entry.damage_amount, 0)
	assert_eq(entry.target_ids, ["skeleton"])


## Updated by US-003 (multi-target processing, AoE Fireball steel thread):
## an empty `targets` Array now emits ZERO CombatLogEntries (design notes'
## architecture section: "Empty targets -> {success: true} short-circuit ...
## no log entries"), superseding FEAT-276's original "one wasted-action
## entry with target_ids: [] / hit: null" shape asserted here previously.
## casting_state is still cleared (CLEANUP is unchanged by US-003 — see
## test_casting_state_is_cleared_even_with_no_targets above).
func test_no_valid_target_emits_no_cast_resolve_entries() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [], resolution_spy, log_spy)

	assert_true(result.get("success"))
	assert_eq(result.get("results"), [])
	assert_true(log_spy.entries.is_empty(), "an empty targets Array must emit zero CombatLogEntries (US-003)")


func test_no_combat_log_port_wired_never_crashes_and_still_clears_casting_state() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)

	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], resolution_spy)

	assert_true(result.get("success"))
	assert_false(caster.is_casting())


func test_defensive_invalid_state_path_never_emits_a_log_entry() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var spell := _fire_bolt()
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [], null, log_spy)

	assert_true(log_spy.entries.is_empty(), "the defensive ERR_INVALID_STATE path must never emit a CombatLogEntry")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-001 (US-001; FR-001, FR-002): emitted entry carries spell.damage_type
# ══════════════════════════════════════════════════════════════════════════

func test_emitted_combat_log_entry_carries_the_spells_damage_type_on_a_hit() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()

	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _hit_result(9)
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [target], resolution_spy, log_spy)

	assert_eq(log_spy.entries.size(), 1)
	var entry = log_spy.entries[0]
	assert_eq(entry.damage_type, "fire", "the emitted CombatLogEntry must carry the resolved spell's damage_type")


## Updated by US-003 (multi-target processing): exercised against a real
## (non-null) target rather than an empty `targets` Array — an empty Array
## no longer emits any entry at all (see
## test_no_valid_target_emits_no_cast_resolve_entries above), so this
## damage_type-default regression check needs a genuine result to observe.
func test_emitted_combat_log_entry_defaults_damage_type_to_empty_string_for_a_non_damage_spell() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := SpellClass.new("channel", "Channel", 1, 0, SpellClass.Defense.NONE, 0, "", "", ["Concentrate"])
	var resolution_spy := SpyResolutionPort.new()
	resolution_spy.scripted_result = _miss_result()
	var log_spy := SpyCombatLogPort.new()

	var use_case := ResolveCastUseCaseClass.new()
	use_case.execute(caster, spell, [target], resolution_spy, log_spy)

	assert_eq(log_spy.entries.size(), 1)
	var entry = log_spy.entries[0]
	assert_eq(entry.damage_type, "", "a spell fixture predating this feature (empty damage_type) must not regress")
