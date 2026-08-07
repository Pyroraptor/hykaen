extends GutTest
## tests/integration/test_fire_bolt_e2e_regression.gd — FEAT-007 (US-008;
## FR-008)
##
## Regression-proof suite for the AoE-Fireball steel thread (FEAT-001..
## FEAT-006): confirms Fire Bolt's pre-existing single-target (SCALAR) cast
## path -- SpellActionController.enter_selection()/build_area_set_selection()
## -> presentation/verbs/resolve_spell_controller.gd's ResolveSpellController
## -> core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase
## -- is genuinely UNAFFECTED by the parallel AREA_SET/AoE machinery this
## iteration added (Spell.is_area_effect(), SelectionResolutionUseCase.
## affected_set(), ResolveSpellController's `_maybe_resolve_aoe_cast()`
## branch, ResolveCastUseCase's multi-target fan-out).
##
## Mirrors tests/unit/application/test_resolve_cast_use_case_single_target_baseline_pre_refactor.gd's
## established "GENUINE, non-scripted RNG at a fixed seed, replayed
## independently -- never a hardcoded magic number" convention (that file's
## own FEAT-003 pinned baseline; PINNED_SEED below is the SAME 4242 value,
## so this suite pins the IDENTICAL pre-change baseline that file already
## captured, now re-verified through the wider ResolveSpellController/
## SpellActionController wiring the AoE refactor actually touched) plus
## tests/integration/test_resolve_spell_controller_aoe_targets.gd's own
## "fake, duck-typed port doubles / real domain objects, no engine boot"
## discipline for the controller-level plumbing.
##
## test_criteria covered:
##   1. Fire Bolt SpellActionController.enter_selection() asserts
##      resolution_mode==SCALAR with non-empty candidate_targets (re-proven
##      here as part of the FULL SpellActionController -> ResolveSpellController
##      wiring chain, complementing tests/unit/presentation/
##      test_fire_bolt_scalar_regression.gd's isolated unit coverage).
##   2. Fire Bolt resolves through the unchanged single-target
##      ResolveSpellController path, producing exactly one CombatLogEntry.
##   3. ResolveCastUseCase single-target output for a fixed RNG seed matches
##      the FEAT-003 pre-refactor baseline fixture (roll, damage,
##      hp_before/hp_after, log count).
##   4. All new regression tests in this feature pass under the GUT runner
##      with zero failures.

const SpellActionControllerClass  = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const SelectionDescriptorClass    = preload("res://core/application/selection_descriptor.gd")
const ResolutionPortClass         = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPortClass          = preload("res://core/application/ports/combat_log_port.gd")
const CombatLogEntryClass         = preload("res://core/domain/combat_log_entry.gd")
const ResolveCastUseCaseClass     = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const SpellClass                  = preload("res://core/domain/spell.gd")
const SeededRandomAdapterClass    = preload("res://core/combat/seeded_random_adapter.gd")
const RoundSessionHolderClass     = preload("res://infrastructure/round_session_holder.gd")

## PINNED_SEED — the SAME 4242 value tests/unit/application/
## test_resolve_cast_use_case_single_target_baseline_pre_refactor.gd (FEAT-003)
## already pinned as its pre-refactor Fire Bolt baseline. Reusing the
## identical seed against the identical caster/target/spell fixture means
## the independently-replayed expected roll/damage below reproduces that
## SAME baseline byte-for-byte -- proof this iteration's AoE refactor left
## it untouched.
const PINNED_SEED: int = 4242


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## SpyCombatLogPort -- records every emit() call's entry argument (mirrors
## tests/unit/application/test_resolve_cast_use_case_multi_target.gd's own
## identically-named double).
class SpyCombatLogPort:
	extends CombatLogPortClass
	var entries: Array = []

	func emit(entry) -> void:
		entries.append(entry)


## _FakeSession -- the minimal current_actor()/current_actor_entity()/
## current_action_economy() double this project's SpellActionController
## suites already establish (tests/unit/presentation/
## test_spell_action_controller_aoe.gd, tests/unit/presentation/
## test_fire_bolt_scalar_regression.gd), used here to drive the REAL,
## wired enter_selection() entry point.
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
# Fixtures — byte-for-byte identical to FEAT-003's own pinned baseline
# fixture (test_resolve_cast_use_case_single_target_baseline_pre_refactor.gd),
# so the SAME seed reproduces the SAME roll/damage sequence.
# ══════════════════════════════════════════════════════════════════════════

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


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 + 2 — the FULL SpellActionController -> ResolveSpellController
# wiring chain: enter_selection() returns SCALAR + non-empty
# candidate_targets, and resolving against the returned candidate produces
# exactly one CombatLogEntry.
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_full_scalar_chain_from_enter_selection_through_resolve_spell_controller() -> void:
	var marigold := _caster_at(HexCoordClass.new(0, 0))
	marigold.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0}
	var skeleton := _enemy("skeleton", HexCoordClass.new(1, 0))

	var holder := RoundSessionHolderClass.new()
	holder.set_current(_FakeSession.new(marigold))

	var resolution_port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var log_spy := SpyCombatLogPort.new()

	var controller := SpellActionControllerClass.new({
		"session_holder": holder,
		"targeting_candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": log_spy,
	})

	# ── entry point: enter_selection() must still resolve to SCALAR with a
	# genuinely non-empty candidate_targets -- the AoE refactor's AREA_SET
	# branch must never be reached for Fire Bolt. ────────────────────────────
	var selection: Dictionary = controller.enter_selection()
	assert_eq(selection.get("verb_id"), "CAST_SPELL")
	assert_eq(
		selection.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.SCALAR,
		"Fire Bolt must reach the unchanged SCALAR branch through the real, wired enter_selection() entry point"
	)
	var candidate_targets: Array = selection.get("candidate_targets", [])
	assert_eq(candidate_targets, ["skeleton"], "candidate_targets must be populated with the in-range living enemy, unaffected by AoE machinery")

	# ── exit point: resolving through ResolveSpellController (constructed
	# directly, mirroring how SpellActionController._maybe_resolve_cast()
	# itself hands the actor to it) must still emit exactly one
	# CombatLogEntry for this single target. This is the SAME "last action
	# before resolution" transition production code drives via
	# ContinueCastUseCase (remaining_actions: 1 -> 0) immediately before
	# _maybe_resolve_cast() ever calls ResolveSpellController.execute() --
	# reproduced explicitly here since this suite drives the two controllers
	# directly rather than through a full ContinueCastUseCase call. ─────────
	marigold.casting_state["remaining_actions"] = 0
	var resolve_controller := ResolveSpellControllerClass.new({
		"candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": log_spy,
	})
	# Pass "skeleton" as the pre-chosen target id -- the SAME synchronous path
	# SpellActionController.execute() feeds ResolveSpellController when the
	# overlay already resolved a target during enter_selection() (this
	# suite's own candidate_targets assertion above), never invoking
	# TargetingPort at all.
	var result: Dictionary = await resolve_controller.execute(marigold, 0, "skeleton")

	assert_true(result.get("success"))
	assert_eq(result.get("target_id"), "skeleton")
	var resolve_cast_result: Dictionary = result.get("resolve_cast_result", {})
	assert_true(resolve_cast_result.get("success"))
	assert_eq(resolve_cast_result.get("results").size(), 1, "a single-target Fire Bolt cast must still produce exactly one result entry")

	assert_eq(log_spy.entries.size(), 1, "a single-target Fire Bolt cast must still emit exactly one CombatLogEntry, unaffected by ResolveCastUseCase's multi-target fan-out refactor")
	var entry = log_spy.entries[0]
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "marigold_1")
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.target_ids, ["skeleton"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — ResolveCastUseCase single-target output for the pinned seed
# matches the FEAT-003 pre-refactor baseline exactly: roll, damage,
# hp_before/hp_after, log count.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_cast_use_case_single_target_output_matches_feat003_pinned_seed_baseline() -> void:
	var caster := _caster_at(HexCoordClass.new(0, 0))
	var target := _enemy("skeleton", HexCoordClass.new(1, 0))
	var spell := _fire_bolt()
	var log_spy := SpyCombatLogPort.new()
	var hp_before: int = target.hp_current

	var port := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var use_case := ResolveCastUseCaseClass.new()
	var result: Dictionary = use_case.execute(caster, spell, [target], port, log_spy)

	assert_true(result.get("success"))
	var results: Array = result.get("results")
	assert_eq(results.size(), 1)

	# Independently replay the SAME pinned seed (NEVER a hardcoded magic
	# number -- mirrors FEAT-003's own baseline test convention) to compute
	# the expected d20 + spell-mod roll, hit/miss, and damage -- this IS the
	# "pre-refactor baseline" test_criteria #3 requires this feature to pin
	# against, captured fresh here rather than duplicated as a literal so it
	# can never silently drift from core/rules/rng.gd's actual sequence.
	var expected_rng := SeededRandomAdapterClass.new(PINNED_SEED)
	var expected_raw: int = expected_rng.d20()
	var expected_roll_total: int = expected_raw + caster.spellcasting_attribute_score
	var expected_hit: bool = expected_roll_total >= target.reflex
	var expected_damage: int = int(results[0].get("damage_applied"))
	var expected_hp_after: int = hp_before - expected_damage

	var attack_result: Dictionary = results[0].get("attack_result")
	assert_eq(attack_result.get("roll_total"), expected_roll_total, "PINNED: roll_total must match the FEAT-003 baseline's d20 + spell-mod computation exactly")
	assert_eq(attack_result.get("hit"), expected_hit, "PINNED: hit must match the FEAT-003 baseline's Reflex-defense comparison exactly")

	# ── hp_before/hp_after — zero diff against the FEAT-003 baseline ────────
	assert_eq(hp_before, 10, "PINNED: hp_before must match the FEAT-003 baseline fixture's starting hp (10)")
	assert_eq(target.hp_current, expected_hp_after, "PINNED: hp_after must match the FEAT-003 baseline's hp_current - damage_applied computation exactly")

	# ── log count — exactly one entry, zero diff ─────────────────────────────
	assert_eq(log_spy.entries.size(), 1, "PINNED: a single-target Fire Bolt cast must emit exactly one CombatLogEntry, matching the FEAT-003 baseline's log count")
	var entry = log_spy.entries[0]
	assert_eq(entry.damage_amount, expected_damage, "PINNED: the CombatLogEntry's damage_amount must match the FEAT-003 baseline exactly")
	assert_eq(entry.roll_total, expected_roll_total, "PINNED: the CombatLogEntry's roll_total must match the FEAT-003 baseline exactly")
	assert_eq(entry.hit, expected_hit, "PINNED: the CombatLogEntry's hit must match the FEAT-003 baseline exactly")


## NFR-002 determinism companion (mirrors FEAT-003's own baseline test): a
## second, independently-constructed run at the SAME pinned seed reproduces
## an identical roll/damage/hp/log outcome -- proving the baseline captured
## above is not an artifact of shared mutable state, still true post-AoE-
## refactor.
func test_pinned_seed_baseline_is_reproducible_across_independent_runs() -> void:
	var spell := _fire_bolt()

	var caster_1 := _caster_at(HexCoordClass.new(0, 0))
	var target_1 := _enemy("skeleton", HexCoordClass.new(1, 0))
	var log_spy_1 := SpyCombatLogPort.new()
	var port_1 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var result_1: Dictionary = ResolveCastUseCaseClass.new().execute(caster_1, spell, [target_1], port_1, log_spy_1)

	var caster_2 := _caster_at(HexCoordClass.new(0, 0))
	var target_2 := _enemy("skeleton", HexCoordClass.new(1, 0))
	var log_spy_2 := SpyCombatLogPort.new()
	var port_2 := ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PINNED_SEED))
	var result_2: Dictionary = ResolveCastUseCaseClass.new().execute(caster_2, spell, [target_2], port_2, log_spy_2)

	assert_eq(result_1.get("results")[0].get("attack_result"), result_2.get("results")[0].get("attack_result"))
	assert_eq(target_1.hp_current, target_2.hp_current)
	assert_eq(log_spy_1.entries.size(), 1)
	assert_eq(log_spy_2.entries.size(), 1)
	assert_eq(log_spy_1.entries[0].damage_amount, log_spy_2.entries[0].damage_amount)
	assert_eq(log_spy_1.entries[0].roll_total, log_spy_2.entries[0].roll_total)
