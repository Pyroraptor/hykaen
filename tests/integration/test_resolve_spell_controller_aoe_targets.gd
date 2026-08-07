extends GutTest
## tests/integration/test_resolve_spell_controller_aoe_targets.gd — FEAT-006
## (US-005; FR-004, ADR-004)
##
## GUT suite for presentation/verbs/resolve_spell_controller.gd's
## ResolveSpellController — the AoE branch of execute(): once a
## resolved AREA_SET selection's origin hex is known, this controller
## extracts that origin, calls
## core/application/selection_resolution_use_case.gd's
## SelectionResolutionUseCase.affected_set() (the SAME BFS ring-expansion
## primitive FEAT-005's build_area_set_selection() already reuses for its
## own candidate_hexes preview), filters the live combatant roster by
## hex_coord membership in that affected set, and hands the resulting
## Combatant[] to core/application/use_cases/resolve_cast_use_case.gd's
## ResolveCastUseCase.execute() (FEAT-003's already-multi-target-capable
## use case) — the wiring step connecting FEAT-005's AREA_SET descriptor to
## FEAT-003's multi-target resolution logic.
##
## Mirrors tests/unit/test_resolve_spell_controller_targeting.gd's /
## tests/unit/presentation/test_resolve_spell_controller.gd's established
## "fake, duck-typed port doubles / real domain objects" convention -- no
## adapter, no engine boot.
##
## test_criteria covered:
##   1. Combatants whose hex_coord falls inside the affected_set are
##      collected into the targets array passed to
##      ResolveCastUseCase.execute() (observed indirectly via the SAME
##      injected ResolutionPort double every target's attack roll must
##      travel through -- ResolveCastUseCase.execute() calls
##      resolution_port.resolve_spell_attack(caster, target, spell, defense)
##      once per target, so the SpyResolutionPort's recorded `calls` list
##      IS the targets array).
##   2. Combatants outside the affected_set are excluded from targets.
##   3. A combatant occupying the origin hex (including the caster) is
##      included per ADR-004's no-friendly-fire-filter rule.
##   4. Zero-combatants-in-area passes an empty targets array and the cast
##      still resolves via ResolveCastUseCase's success/empty path.
##   5. Non-AoE (Fire Bolt) cast flow through ResolveSpellController remains
##      unchanged (single-target regression guard).

const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const EffectKindClass             = preload("res://core/domain/effects/effect_kind.gd")
const ErrorCodeClass              = preload("res://core/application/ports/errors.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## FakeSpellCatalogPort -- duck-typed SpellCatalogPort double (mirrors every
## sibling ResolveSpellController suite's identical double).
class FakeSpellCatalogPort:
	extends RefCounted
	var spells: Dictionary = {}

	func get_spell(spell_id: String):
		return spells.get(spell_id, null)


## SpyResolutionPort -- records the `target` argument of every
## resolve_spell_attack() call (in call order) so a test can assert exactly
## which Combatants ResolveCastUseCase.execute() drove an attack roll
## against -- i.e. the targets array ResolveSpellController assembled and
## handed in. Always resolves to the same scripted hit.
class SpyResolutionPort:
	extends ResolutionPortClass
	var calls: Array = []
	var scripted_result: Dictionary = {"hit": true, "crit": false, "roll_total": 15, "damage_raw": 4, "active_defense_applied": "none", "damage_final": 4}

	func resolve_spell_attack(_attacker, target, _spell, _defense_type) -> Dictionary:
		calls.append(target)
		return scripted_result


## ScriptedTargetingPort -- used only by the Fire Bolt (non-AoE) regression
## test, mirrors tests/unit/test_resolve_spell_controller_targeting.gd's
## SpyTargetingPort.
class SpyTargetingPort:
	extends RefCounted
	var calls: Array = []
	var scripted_target = null

	func request_single_target(legal_targets: Array):
		calls.append(legal_targets.duplicate())
		return scripted_target


func _fireball(area_effect_radius_ft: int = 5) -> SpellClass:
	# area_effect_radius_ft=5 -> area_hex_radius()==1 (a small, fast-to-reason-
	# about blast: origin + its 6 immediate neighbors), range_ft=50 so the
	# origin hex used by these fixtures is always well within range.
	return SpellClass.new(
		"fireball", "Fireball", 2, 2, SpellClass.Defense.REFLEX, 50,
		"3d6+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "3d6+ATTR", "type": "fire"}, "", area_effect_radius_ft
	)


func _fire_bolt() -> SpellClass:
	return SpellClass.new("fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", [])


func _combatant(id: String, team: String, hex_coord: HexCoordClass, remaining_actions: int = 0, spell_id: String = "fireball") -> CombatantClass:
	var c := CombatantClass.new(id, id, team, hex_coord)
	c.hp_current = 10
	c.hp_max = 10
	c.known_spell_ids = [spell_id]
	c.casting_state = {
		"spell_id": spell_id,
		"remaining_actions": remaining_actions,
		"committed_energy": 0,
		"caster_id": id,
	}
	return c


func _enemy(id: String, hex_coord: HexCoordClass) -> CombatantClass:
	var e := CombatantClass.new(id, id, "Enemy", hex_coord)
	e.hp_current = 10
	e.hp_max = 10
	return e


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 + 2 + 3 -- in-area (incl. origin/caster) collected, out-of-area
# excluded
# ══════════════════════════════════════════════════════════════════════════

func test_aoe_cast_collects_in_area_combatants_including_the_caster_and_excludes_out_of_area() -> void:
	var origin := HexCoordClass.new(0, 0)
	var caster := _combatant("gram_marx_1", "Player", origin)  # occupies the origin hex itself
	var neighbor_in_area := _enemy("skeleton_a", HexCoordClass.new(1, 0))   # hex_distance 1 from origin -- inside radius-1 blast
	var far_out_of_area := _enemy("skeleton_b", HexCoordClass.new(2, 0))    # hex_distance 2 from origin -- outside radius-1 blast

	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fireball"] = _fireball()
	var resolution := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"resolution_port": resolution,
		"combatant_roster_fn": func(): return [caster, neighbor_in_area, far_out_of_area],
	})

	var result: Dictionary = await controller.execute(caster, 0, "", origin)

	assert_true(result.get("success"), "an AoE cast with in-area targets must resolve successfully")
	assert_true(result.get("resolve_cast_result", {}).get("success"), "ResolveCastUseCase.execute() must itself report success")

	var targeted_ids: Array = resolution.calls.map(func(t): return t.display_id())
	assert_true(targeted_ids.has("gram_marx_1"), "a combatant occupying the origin hex -- including the caster -- must be included per ADR-004's no-friendly-fire-filter rule")
	assert_true(targeted_ids.has("skeleton_a"), "a combatant inside the affected_set must be collected into the targets array")
	assert_false(targeted_ids.has("skeleton_b"), "a combatant outside the affected_set must be excluded from the targets array")
	assert_eq(resolution.calls.size(), 2, "exactly the two in-area combatants (caster + skeleton_a) must have been driven through ResolutionPort, no more/no less")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 -- zero combatants in the affected area
# ══════════════════════════════════════════════════════════════════════════

func test_aoe_cast_with_zero_combatants_in_area_resolves_with_empty_targets() -> void:
	var origin := HexCoordClass.new(0, 0)
	var caster := _combatant("gram_marx_1", "Player", HexCoordClass.new(10, 10))  # caster stands far from the chosen origin
	var far_out_of_area := _enemy("skeleton_b", HexCoordClass.new(2, 0))  # outside the radius-1 blast centered on origin

	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fireball"] = _fireball()
	var resolution := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"resolution_port": resolution,
		"combatant_roster_fn": func(): return [far_out_of_area],
	})

	var result: Dictionary = await controller.execute(caster, 0, "", origin)

	assert_true(result.get("success"), "a wasted/empty-area AoE cast is still a successful resolution, per FEAT-003's empty-targets short-circuit contract")
	var resolve_cast_result: Dictionary = result.get("resolve_cast_result", {})
	assert_true(resolve_cast_result.get("success"), "ResolveCastUseCase.execute() with an empty targets array must still report success")
	assert_eq(resolve_cast_result.get("results"), [], "zero combatants in the affected area must yield an empty results array")
	assert_true(resolution.calls.is_empty(), "ResolutionPort must never be invoked when the targets array is empty")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 -- Fire Bolt (non-AoE) regression guard
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_non_aoe_flow_is_unchanged_even_when_an_origin_hex_is_supplied() -> void:
	# A non-area-effect spell must stay on the existing single-target
	# TargetingPort flow byte-for-byte, even if a caller mistakenly supplies
	# an origin hex (e.g. stale UI state) -- is_area_effect() gates the new
	# AoE branch, so Fire Bolt must never reach it.
	var actor := _combatant("marigold_1", "Player", HexCoordClass.new(0, 0), 0, "fire_bolt")
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

	var result: Dictionary = await controller.execute(actor, 0, "", HexCoordClass.new(5, 5))

	assert_eq(targeting.calls.size(), 1, "Fire Bolt must still drive TargetingPort exactly once, unaffected by a supplied origin hex")
	assert_true(result.get("success"))
	assert_eq(result.get("target_id"), "skeleton")


func test_aoe_branch_never_triggers_when_no_origin_hex_is_supplied() -> void:
	# Fireball (is_area_effect()==true) with no origin hex supplied (the
	# pre-FEAT-006 call shape) must NOT crash or silently no-op into the AoE
	# branch -- it falls through to the pre-existing single-target flow
	# unchanged (no live TargetingPort wired here, so it fails safe exactly
	# like tests/unit/test_resolve_spell_controller_targeting.gd's own
	# "fails safe with no targeting port wired" case).
	var actor := _combatant("gram_marx_1", "Player", HexCoordClass.new(0, 0))
	var catalog := FakeSpellCatalogPort.new()
	catalog.spells["fireball"] = _fireball()
	var resolution := SpyResolutionPort.new()

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"resolution_port": resolution,
	})

	var result: Dictionary = await controller.execute(actor)

	assert_false(result.get("success"))
	assert_eq(result.get("error"), ErrorCodeClass.ERR_NO_VALID_TARGET)
	assert_true(resolution.calls.is_empty(), "with no origin hex supplied, the AoE branch must never run")
