extends GutTest
## tests/unit/presentation/test_fire_bolt_scalar_regression.gd — FEAT-007
## (US-008; FR-008)
##
## Regression-proof suite for presentation/verbs/spell_action_controller.gd's
## SpellActionController: this iteration's AoE-Fireball steel thread
## (FEAT-001..FEAT-006) added a whole new AREA_SET branch to
## `enter_selection()`/`build_area_set_selection()`, gated on
## Spell.is_area_effect() (core/domain/spell.gd, FEAT-001). Fire Bolt
## (data/spells/fire_bolt.tres) carries no `area_effect_radius_ft`, so
## `is_area_effect()` is false for it and it MUST stay on the pre-existing
## SCALAR branch byte-for-byte, both through the directly-callable
## `build_area_set_selection()` helper AND through the REAL, wired
## `enter_selection()` no-arg verb-table entry point (mirrors
## tests/unit/presentation/test_spell_action_controller_aoe.gd's own
## criterion-4/`test_enter_selection_real_entry_point_...` conventions,
## reproduced here as this feature's OWN dedicated, explicit regression
## file rather than relying solely on FEAT-005's incidental coverage).
##
## test_criteria covered (this file's share):
##   1. Fire Bolt SpellActionController.enter_selection() asserts
##      resolution_mode==SCALAR with non-empty candidate_targets.

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const SelectionDescriptorClass   = preload("res://core/application/selection_descriptor.gd")
const SpellClass                 = preload("res://core/domain/spell.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const RoundSessionHolderClass    = preload("res://infrastructure/round_session_holder.gd")


func _fire_bolt() -> Object:
	# Mirrors data/spells/fire_bolt.tres exactly (range_ft=50, no
	# area_effect_radius_ft -> is_area_effect()==false, the SCALAR-path
	# regression fixture this whole suite pins down).
	return SpellClass.new(
		"fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50,
		"2d8+ATTR", "fire", ["Concentrate"]
	)


func _marigold() -> Object:
	var caster := CombatantClass.new("marigold_1", "Marigold", "Player", HexCoordClass.new(0, 0))
	caster.known_spell_ids = ["fire_bolt"]
	return caster


func _living_enemy() -> Object:
	return CombatantClass.new("skeleton_0", "Skeleton", "Enemy", HexCoordClass.new(1, 0))


func _controller(deps: Dictionary = {}) -> Object:
	return SpellActionControllerClass.new(deps)


## _FakeSession — the same minimal current_actor()/current_actor_entity()/
## current_action_economy() double tests/unit/presentation/
## test_spell_action_controller_aoe.gd's own `_FakeSession` uses to drive
## the REAL, wired `enter_selection()` entry point without a full RoundSession.
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
# Criterion 1 — build_area_set_selection() (the shared branching
# implementation) still returns SCALAR + populated candidate_targets for
# Fire Bolt, unaffected by the AoE refactor.
# ══════════════════════════════════════════════════════════════════════════

func test_build_area_set_selection_for_fire_bolt_returns_scalar_mode_with_populated_candidate_targets() -> void:
	var living_enemy := _living_enemy()
	var controller := _controller({"targeting_candidates_fn": func(): return [living_enemy]})
	var marigold := _marigold()

	var descriptor: Dictionary = controller.build_area_set_selection(_fire_bolt(), marigold)

	assert_true(descriptor.get("is_valid"), "a valid Fire Bolt/caster pair must produce is_valid==true")
	assert_eq(
		descriptor.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.SCALAR,
		"Fire Bolt (is_area_effect()==false) must stay on the unchanged SCALAR path"
	)
	var candidate_targets: Array = descriptor.get("candidate_targets", [])
	assert_false(candidate_targets.is_empty(), "SCALAR mode must populate candidate_targets from the injected targeting_candidates_fn")
	assert_eq(candidate_targets, ["skeleton_0"])
	assert_eq(descriptor.get("candidate_hexes"), [], "SCALAR mode must leave candidate_hexes empty -- an AoE origin-hex pick never applies to Fire Bolt")
	assert_null(descriptor.get("geometry_rule"), "a SCALAR descriptor must never carry an AREA_SET geometry_rule")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (continued) — the REAL, wired enter_selection() no-arg
# verb-table entry point (not just the directly-callable helper above)
# reaches the SAME SCALAR branch, with a genuinely non-empty
# candidate_targets, for a mid-cast Fire Bolt with exactly one action
# remaining (the "last action before resolution" gate).
# ══════════════════════════════════════════════════════════════════════════

func test_enter_selection_real_entry_point_returns_scalar_for_in_progress_fire_bolt_cast() -> void:
	var marigold := _marigold()
	marigold.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0}

	var living_enemy := _living_enemy()
	var holder := RoundSessionHolderClass.new()
	var session := _FakeSession.new(marigold)
	holder.set_current(session)

	var controller := _controller({
		"session_holder": holder,
		"targeting_candidates_fn": func(): return [living_enemy],
	})

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL")
	assert_eq(
		selection.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.SCALAR,
		"a mid-cast, one-action-remaining Fire Bolt must reach the unchanged SCALAR branch through the real enter_selection() entry point, never AREA_SET"
	)
	var candidate_targets: Array = selection.get("candidate_targets", [])
	assert_false(candidate_targets.is_empty(), "candidate_targets must be genuinely non-empty -- the SCALAR path's own regression contract")
	assert_eq(candidate_targets, ["skeleton_0"])
	assert_eq(selection.get("candidate_hexes", []), [], "no AREA_SET candidate_hexes must ever leak into a Fire Bolt selection")


func test_enter_selection_real_entry_point_returns_empty_when_no_living_targets_are_available() -> void:
	# Documents the boundary: an unwired/empty targeting_candidates_fn is
	# still handled the SAME pre-AoE-refactor way (falls through to the
	# base class's inert {} default, US-008's SCALAR contract untouched).
	var marigold := _marigold()
	marigold.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0}

	var holder := RoundSessionHolderClass.new()
	var session := _FakeSession.new(marigold)
	holder.set_current(session)

	var controller := _controller({"session_holder": holder})

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection, {}, "with no candidates available, Fire Bolt's SCALAR branch must degrade to the base class's pre-existing inert {} shape, unaffected by the AoE refactor")
