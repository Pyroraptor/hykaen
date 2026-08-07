extends GutTest
## tests/unit/presentation/test_spell_action_controller_aoe.gd — FEAT-005
## (US-004; FR-003, ADR-002/ADR-006)
##
## GUT suite for presentation/verbs/spell_action_controller.gd's
## SpellActionController — the entry point of the AoE-targeting steel
## thread: "player selects Fireball, targeting begins". Exercises
## `build_area_set_selection(spell, caster)` directly (the public,
## explicit-spell/caster-pair entry point `enter_selection()`'s own mid-cast
## branch delegates to — see that method's FEAT-005 doc) plus the real,
## wired `enter_selection()` no-arg verb-table entry point for integration
## coverage of the same branching rule.
##
## test_criteria covered:
##   1. build_area_set_selection(fireball, gram_marx) returns
##      resolution_mode==AREA_SET, geometry_rule=={radius:4},
##      candidate_targets==[].
##   2. candidate_hexes explicitly includes the caster's own hex (RISK-002).
##   3. candidate_hexes contains only hexes within spell.range_ft of the
##      caster's hex, no LOS/movement exclusions unexpectedly applied.
##   4. Fire Bolt (non-AoE) still returns resolution_mode==SCALAR with
##      populated candidate_targets (regression guard, US-008).
##   5. Invalid input (null spell or insufficient energy) returns
##      is_valid=false with empty candidate arrays, never a crash.

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const SelectionDescriptorClass   = preload("res://core/application/selection_descriptor.gd")
const SpellClass                 = preload("res://core/domain/spell.gd")
const EffectKindClass            = preload("res://core/domain/effects/effect_kind.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const HexMathClass               = preload("res://core/geometry/hex_math.gd")

const FEET_PER_HEX: int = 5


## FakeRoundEnergyPoolPort — duck-typed RoundEnergyPoolPort double, mirrors
## tests/unit/test_energy_gated_spell_list.gd's own fake: a single in-memory
## balance, used only for this suite's "insufficient energy" invalid-input
## case.
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


func _fireball() -> Object:
	# Mirrors data/spells/fireball.tres exactly (range_ft=100,
	# area_effect_radius_ft=20 -> area_hex_radius()==4, energy_cost=2).
	return SpellClass.new(
		"fireball", "Fireball", 2, 2, SpellClass.Defense.REFLEX, 100,
		"3d6+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "3d6+ATTR", "type": "fire"}, "", 20
	)


func _fire_bolt() -> Object:
	# Mirrors data/spells/fire_bolt.tres exactly (range_ft=50, no
	# area_effect_radius_ft -> is_area_effect()==false).
	return SpellClass.new(
		"fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50,
		"2d8+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "2d8+ATTR", "type": "fire"}
	)


func _gram_marx(known_spell_ids: Array = ["fireball"]) -> Object:
	var caster := CombatantClass.new("gram_marx", "Gram Marx", "Player", HexCoordClass.new(0, 0))
	caster.known_spell_ids = known_spell_ids
	return caster


func _controller(deps: Dictionary = {}) -> Object:
	return SpellActionControllerClass.new(deps)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: AREA_SET shape for Fireball
# ══════════════════════════════════════════════════════════════════════════

func test_build_area_set_selection_for_fireball_returns_area_set_mode() -> void:
	var controller := _controller()
	var gram_marx := _gram_marx()

	var descriptor: Dictionary = controller.build_area_set_selection(_fireball(), gram_marx)

	assert_true(descriptor.get("is_valid"), "a valid spell/caster pair must produce is_valid==true")
	assert_eq(
		descriptor.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET,
		"Fireball (is_area_effect()==true) must select ResolutionMode.AREA_SET"
	)
	assert_eq(
		descriptor.get("geometry_rule"), {"radius": 4},
		"geometry_rule must carry Fireball's area_hex_radius() (20ft / 5ft-per-hex == 4)"
	)
	assert_eq(
		descriptor.get("candidate_targets"), [],
		"an AoE origin is chosen by hex, never by clicking a target token -- candidate_targets must stay empty"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: caster's own hex is explicitly included (RISK-002)
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_hexes_includes_casters_own_hex() -> void:
	var controller := _controller()
	var gram_marx := _gram_marx()

	var descriptor: Dictionary = controller.build_area_set_selection(_fireball(), gram_marx)
	var candidate_hexes: Array = descriptor.get("candidate_hexes", [])

	var found_own_hex: bool = false
	for hex_coord in candidate_hexes:
		if hex_coord.equals(gram_marx.hex_coord):
			found_own_hex = true
			break
	assert_true(found_own_hex, "candidate_hexes must explicitly include the caster's own hex (RISK-002)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: candidate_hexes is bounded exactly by spell.range_ft, no
# LOS/movement exclusions
# ══════════════════════════════════════════════════════════════════════════

func test_candidate_hexes_bounded_exactly_by_spell_range_ft() -> void:
	var controller := _controller()
	var gram_marx := _gram_marx()
	var fireball := _fireball()

	var descriptor: Dictionary = controller.build_area_set_selection(fireball, gram_marx)
	var candidate_hexes: Array = descriptor.get("candidate_hexes", [])
	var range_hexes: int = int(fireball.range_ft / FEET_PER_HEX)

	assert_true(candidate_hexes.size() > 0, "candidate_hexes must be non-empty for a spell with range_ft > 0")

	for hex_coord in candidate_hexes:
		assert_true(
			HexMathClass.hex_distance(gram_marx.hex_coord, hex_coord) <= range_hexes,
			"every candidate hex must be within spell.range_ft (converted to hexes) of the caster's hex -- no unexpected LOS/movement exclusions, but also no hex further than range"
		)

	# Exact count of a filled hex-radius disk: 1 + 3*N*(N+1) for radius N --
	# confirms candidate_hexes is neither truncated nor over-expanded, not
	# merely "small enough".
	var expected_count: int = 1 + 3 * range_hexes * (range_hexes + 1)
	assert_eq(candidate_hexes.size(), expected_count, "candidate_hexes must contain the FULL filled hex disk of radius %d, no more/no less" % range_hexes)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Fire Bolt (non-AoE) regression -- unchanged SCALAR shape
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_non_aoe_still_returns_scalar_mode_with_populated_candidate_targets() -> void:
	var living_enemy := CombatantClass.new("skeleton_0", "Skeleton", "Enemy", HexCoordClass.new(1, 0))
	var controller := _controller({"targeting_candidates_fn": func(): return [living_enemy]})
	var gram_marx := _gram_marx(["fire_bolt"])

	var descriptor: Dictionary = controller.build_area_set_selection(_fire_bolt(), gram_marx)

	assert_true(descriptor.get("is_valid"), "a valid non-AoE spell/caster pair must produce is_valid==true")
	assert_eq(
		descriptor.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.SCALAR,
		"Fire Bolt (is_area_effect()==false) must stay on the unchanged SCALAR path"
	)
	assert_eq(
		descriptor.get("candidate_targets"), ["skeleton_0"],
		"SCALAR mode must still populate candidate_targets from the injected targeting_candidates_fn"
	)
	assert_eq(descriptor.get("candidate_hexes"), [], "SCALAR mode must leave candidate_hexes empty")


func test_enter_selection_real_entry_point_returns_area_set_for_in_progress_fireball_cast() -> void:
	# Integration coverage: the REAL, wired enter_selection() no-arg verb-
	# table entry point (not just the directly-callable helper above) must
	# reach the same AREA_SET branch once the actor is genuinely mid-cast on
	# an area-effect spell with exactly one action remaining (the existing
	# "last action before resolution" gate).
	var gram_marx := _gram_marx(["fireball"])
	gram_marx.casting_state = {"spell_id": "fireball", "remaining_actions": 1, "committed_energy": 2}

	var RoundSessionHolderClass = preload("res://infrastructure/round_session_holder.gd")
	var holder := RoundSessionHolderClass.new()

	var session := _FakeSession.new(gram_marx)
	holder.set_current(session)

	var controller := _controller({"session_holder": holder})

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL")
	assert_eq(selection.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET, "a mid-cast, one-action-remaining Fireball must reach the AREA_SET branch through the real enter_selection() entry point")
	assert_eq(selection.get("geometry_rule"), {"radius": 4})
	assert_eq(selection.get("candidate_targets"), [])
	assert_true(selection.get("candidate_hexes", []).size() > 0)


## _FakeSession — a tiny, real (not all-mocked) double satisfying the same
## current_actor()/current_actor_entity()/current_action_economy() contract
## core/application/round_session.gd's RoundSession exposes, mirroring
## tests/unit/test_spell_action_controller_skeleton.gd's own FakeSession.
class _FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: invalid input -- never a crash
# ══════════════════════════════════════════════════════════════════════════

func test_null_spell_returns_invalid_descriptor_with_empty_candidate_arrays() -> void:
	var controller := _controller()
	var gram_marx := _gram_marx()

	var descriptor: Dictionary = controller.build_area_set_selection(null, gram_marx)

	assert_false(descriptor.get("is_valid", true), "a null spell must produce is_valid==false")
	assert_eq(descriptor.get("candidate_hexes"), [], "a null spell must never produce candidate_hexes")
	assert_eq(descriptor.get("candidate_targets"), [], "a null spell must never produce candidate_targets")


func test_null_caster_returns_invalid_descriptor_with_empty_candidate_arrays() -> void:
	var controller := _controller()

	var descriptor: Dictionary = controller.build_area_set_selection(_fireball(), null)

	assert_false(descriptor.get("is_valid", true), "a null caster must produce is_valid==false")
	assert_eq(descriptor.get("candidate_hexes"), [])
	assert_eq(descriptor.get("candidate_targets"), [])


func test_insufficient_energy_returns_invalid_descriptor_with_empty_candidate_arrays() -> void:
	var controller := _controller()
	var gram_marx := _gram_marx()
	var fireball := _fireball()  # energy_cost == 2
	var pool_port := FakeRoundEnergyPoolPort.new(1)  # only 1 banked, needs 2

	var descriptor: Dictionary = controller.build_area_set_selection(fireball, gram_marx, pool_port)

	assert_false(descriptor.get("is_valid", true), "a caster who cannot afford spell.energy_cost must produce is_valid==false")
	assert_eq(descriptor.get("candidate_hexes"), [])
	assert_eq(descriptor.get("candidate_targets"), [])


func test_sufficient_energy_still_returns_valid_area_set_descriptor() -> void:
	# Sanity check on the OTHER side of the gate: the pool_port check is
	# genuinely energy-driven, not an unconditional rejection.
	var controller := _controller()
	var gram_marx := _gram_marx()
	var fireball := _fireball()  # energy_cost == 2
	var pool_port := FakeRoundEnergyPoolPort.new(2)

	var descriptor: Dictionary = controller.build_area_set_selection(fireball, gram_marx, pool_port)

	assert_true(descriptor.get("is_valid"), "a caster who CAN afford spell.energy_cost must still produce is_valid==true")
	assert_eq(descriptor.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET)
