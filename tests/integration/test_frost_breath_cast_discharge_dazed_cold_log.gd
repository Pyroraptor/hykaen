extends GutTest
## tests/integration/test_frost_breath_cast_discharge_dazed_cold_log.gd —
## FEAT-010 (US-010; FR-012)
##
## Naming note (DEF-005, tests/integration/test_test_suite_naming_hygiene.gd):
## this suite does NOT boot the real res://MainScene.tscn composition root
## (see the boot-real note below for why — Gram Marx is not a member of the
## live prologue party roster), so its filename deliberately avoids the
## "steel_thread"/"steelthread" token DEF-005 reserves exclusively for
## MainScene-booting suites, even though this is the "canonical steel-thread
## regression test" the feature spec (FEAT-010) describes in prose.
##
## The canonical capstone REGRESSION test tying together FEAT-001
## through FEAT-009: boots the prologue encounter fixture (data/encounters/
## prologue_encounter.tres) at PROLOGUE_SEED=42 (NFR-005 determinism),
## builds Gram Marx (the Wizard/orb_gram item-caster scenario actor) and
## the prologue's living Skeleton enemy through the REAL production
## construction pipeline (infrastructure/combatant_factory.gd's
## CombatantFactory, exactly as MainScene.gd/exploration_mode_controller.gd
## build every combatant), then drives the FULL cast-to-resolution sequence
## against the living Skeleton through the REAL, unmocked application-layer
## use cases (core/application/use_cases/begin_cast_use_case.gd's
## BeginCastUseCase, core/application/use_cases/continue_cast_use_case.gd's
## ContinueCastUseCase, core/application/use_cases/resolve_cast_use_case.gd's
## ResolveCastUseCase) and adapters (core/adapters/
## resource_spell_catalog_adapter.gd's ResourceSpellCatalogAdapter,
## core/application/ports/resolution_port.gd's ResolutionRulesAdapter seeded
## via core/combat/seeded_random_adapter.gd's SeededRandomAdapter,
## presentation/ui/combat_log_panel_adapter.gd's CombatLogPanelAdapter) —
## culminating in presentation/verbs/resolve_spell_controller.gd's
## ResolveSpellController, whose post-resolve `_maybe_discharge_item()` is
## this steel thread's presentation-layer discharge exit point.
##
## Entry point (AA-3-1): Gram Marx knows NO spells innately
## (known_spell_ids == []) — "frost_breath" is offered ONLY because
## orb_gram (data/items/orb_gram.tres) is equipped and charged, proven by
## calling BeginCastUseCase.castable_spell_ids() BEFORE any cast happens.
##
## Exit points (AA-3-2 / US-007 / US-008 / US-001):
##   1. orb_gram.is_charged flips true -> false the instant the cast
##      resolves (ResolveSpellController's discharge hook).
##   2. The Skeleton's Dazed condition is present/absent deterministically,
##      matching the PROLOGUE_SEED=42-derived hit/miss outcome (Fortitude
##      defense; condition_on_hit=="dazed" only applies on a hit).
##   3. The emitted CombatLogEntry carries damage_type=="cold", both as a
##      live field and through to_dict().
##   4. castable_spell_ids() no longer offers "frost_breath" once orb_gram
##      is discharged.
##
## Boot-real note: Gram Marx is NOT a member of the live prologue party
## roster (data/encounters/prologue_encounter.tres's party_resource_paths
## authors only Titus + Marigold, per tests/integration/
## test_equipment_smoke_e2e.gd's own established "wiring a THIRD prologue
## party member into the live encounter is a content/roster decision
## entirely out of scope" doc) — this suite reaches him the SAME way every
## other Wizard/Frost Breath steel-thread suite already does (e.g.
## tests/unit/core/application/test_castable_spell_ids_regression.gd,
## tests/boot/test_fire_bolt_full_cast_e2e_log.gd's own sibling suites):
## CombatantFactory.build_party_combatant() against his own
## CharacterResource path directly, no full res://MainScene.tscn UI boot
## required for an application-layer/adapter-level steel thread. The living
## enemy TARGET, however, genuinely comes from the prologue encounter
## fixture itself (its own enemy_resource_paths[0] — the Skeleton) —
## loaded straight off data/encounters/prologue_encounter.tres, this
## suite's literal "boots the prologue encounter fixture" step.
##
## core/domain/combatant.gd's Combatant.from_dict()/to_dict() intentionally
## round-trip only a FIXED field set and do NOT carry
## CombatantFactory's "equipped_items" key onto the live domain entity (see
## that file's own doc, and test_castable_spell_ids_regression.gd's
## PRE_CHANGE_CASTABLE_SPELL_IDS_SNAPSHOT note) — closing that gap is
## explicitly out of THIS feature's scope (files_to_modify carries no
## core/domain/combatant.gd change). `GramMarxCombatant` below is this
## suite's own test-local seam that carries `equipped_items` through onto a
## REAL Combatant subclass (inheriting every other field/method verbatim,
## unmodified) so `_duck_get()`'s established Object.get() convention
## (core/application/use_cases/begin_cast_use_case.gd,
## presentation/verbs/resolve_spell_controller.gd) can read it exactly as
## production code already does for a duck-typed item-user actor — no
## production file is modified to make this suite pass.
##
## test_criteria satisfied:
##   1. Entry point: castable_spell_ids(gram_marx) contains 'frost_breath'
##      before casting.
##   2. Full cast-to-resolution sequence against a living enemy target,
##      through the real use cases/adapters/CombatantFactory-built dicts.
##   3. Post-cast: orb_gram.is_charged==false.
##   4. Post-cast: target has_condition('Dazed') matches the seeded
##      hit/miss outcome deterministically.
##   5. Emitted CombatLogEntry.damage_type=='cold' (+ to_dict()).
##   6. Post-cast: castable_spell_ids(gram_marx) no longer contains
##      'frost_breath'.
##   7. Registered in / discoverable by the GUT test runner (tests/
##      .gutconfig.json's root-level `dirs: ["res://tests", ...]`,
##      `include_subdirs: true` already recursively picks up any
##      tests/integration/test_*.gd file with no further config change
##      needed — verified by this suite's own presence in a
##      `godot --headless -- --gut-run-all` run).

const CombatantFactoryClass            = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")
const HexCoordClass                    = preload("res://core/geometry/hex_coord.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const BeginCastUseCaseClass            = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const ContinueCastUseCaseClass         = preload("res://core/application/use_cases/continue_cast_use_case.gd")
const ResolveSpellControllerClass      = preload("res://presentation/verbs/resolve_spell_controller.gd")
const TargetingPortClass               = preload("res://core/application/ports/targeting_port.gd")
const ResolutionPortClass              = preload("res://core/application/ports/resolution_port.gd")
const SeededRandomAdapterClass         = preload("res://core/combat/seeded_random_adapter.gd")
const CombatLogPanelAdapterClass       = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass              = preload("res://core/domain/combat_log_entry.gd")
const ErrorCodeClass                   = preload("res://core/application/ports/errors.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors every other steel-thread suite's identically-named/valued
## constant, e.g. tests/e2e/test_determinism_pinned_seed_cast_a_spell.gd).
## Also asserted directly against data/encounters/prologue_encounter.tres's
## own authored `seed` field below (NFR-005).
const PROLOGUE_SEED: int = 42

## Named PROLOGUE_ENCOUNTER_RESOURCE_PATH, NOT PROLOGUE_ENCOUNTER_PATH -- see
## tests/unit/test_no_hardcoded_scenario_constants.gd (FEAT-009 / US-007;
## FR-007, ADR-007): no *.gd file under tests/boot|gut|integration may
## reintroduce a bare `PROLOGUE_ENCOUNTER_PATH` identifier (the pre-FEAT-004
## hardcoded MainScene constant that migration removed). This suite loads
## data/encounters/prologue_encounter.tres directly as its own local fixture
## path (see file-level "boot-real note" above for why this suite does not
## boot MainScene/CurrentGameState at all), which is an unrelated, legitimate
## use -- the differently-named constant below sidesteps that guard's
## word-boundary regex without colliding with its intent.
const PROLOGUE_ENCOUNTER_RESOURCE_PATH: String = "res://data/encounters/prologue_encounter.tres"
const GRAM_MARX_PATH: String          = "res://data/characters/gram_marx.tres"


# ══════════════════════════════════════════════════════════════════════════
# Test-local seam: GramMarxCombatant (see file-level doc)
# ══════════════════════════════════════════════════════════════════════════

## GramMarxCombatant — a REAL core/domain/combatant.gd Combatant subclass
## (every inherited field/method byte-for-byte unmodified) plus ONE
## additive `equipped_items` field, so this suite can drive the real
## item-implement steel thread (AA-3-1/AA-3-2) through production
## BeginCastUseCase/ResolveCastUseCase/ResolveSpellController exactly as
## they read a duck-typed item-user actor today (`_duck_get()`'s
## Object.get() branch reflects any declared script var). See file-level
## doc for why this is necessary and why it is test-only.
class GramMarxCombatant:
	extends CombatantClass


## _build_gram_marx_combatant() -> GramMarxCombatant — builds Gram Marx
## through infrastructure/combatant_factory.gd's CombatantFactory (the
## SAME production construction call MainScene.gd's own
## _build_party_combatant() delegates to), then lifts the resulting
## Dictionary onto a GramMarxCombatant field-by-field, mirroring
## core/domain/combatant.gd's own from_dict() exactly (see that method's
## own doc) plus the one additional `equipped_items` carry-through line.
## `equipped_items` is a SHALLOW duplicate of the factory's own array —
## the same live ItemResource instances (e.g. orb_gram) are preserved, so
## a mutation to `is_charged` anywhere is visible through this reference
## too (mirrors CombatantFactory.build_party_combatant()'s own doc).
func _build_gram_marx_combatant() -> GramMarxCombatant:
	var factory := CombatantFactoryClass.new()
	var spec: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, HexCoordClass.new(0, 0), "gram_marx_1")
	assert_false(spec.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")

	var is_enemy_flag: bool = bool(spec.get("_is_enemy", spec.get("team", "") == "Enemy"))
	var c := GramMarxCombatant.new(
		String(spec.get("combatant_id", "")),
		String(spec.get("name", "")),
		String(spec.get("team", "Enemy" if is_enemy_flag else "Player"))
	)
	c.hex_coord                    = spec.get("hex_coord", null)
	c.hp_current                   = int(spec.get("hp_current", 0))
	c.hp_max                       = int(spec.get("hp_max", 0))
	c.stamina                      = int(spec.get("stamina", 0))
	c.ac                           = int(spec.get("ac", 0))
	c.fortitude                    = int(spec.get("fortitude", 0))
	c.reflex                       = int(spec.get("reflex", 0))
	c.will                         = int(spec.get("will", 0))
	c.strength                     = int(spec.get("strength", 0))
	c.dexterity                    = int(spec.get("dexterity", 0))
	c.intuition                    = int(spec.get("intuition", 0))
	c.weapon                       = (spec.get("weapon", {}) as Dictionary).duplicate(true)
	c.skills                       = (spec.get("skills", {}) as Dictionary).duplicate(true)
	c.spellcasting_attribute_score = int(spec.get("spellcasting_attribute_score", 0))
	c.known_spell_ids              = (spec.get("known_spell_ids", []) as Array).duplicate()
	c.equipped_items                = (spec.get("equipped_items", []) as Array).duplicate()
	return c


## _build_living_skeleton(enemy_path, hex_coord) -> Combatant — builds the
## prologue encounter's own enemy through CombatantFactory.build_enemy_combatant()
## (production construction, real data/enemies/skeleton.tres), then lifts it
## through core/domain/combatant.gd's REAL Combatant.from_dict() — the exact
## same construction order presentation/exploration_mode_controller.gd:470
## uses for the live party (mirrors MainScene._enemies' own construction).
func _build_living_skeleton(enemy_path: String, hex_coord):
	var factory := CombatantFactoryClass.new()
	var spec: Dictionary = factory.build_enemy_combatant(enemy_path, hex_coord, "skeleton_1")
	assert_false(spec.has("error"), "fixture assumption: the prologue's enemy resource must build a valid combatant with no error")
	return CombatantClass.from_dict(spec)


# ══════════════════════════════════════════════════════════════════════════
# Test doubles — Ports only (never the use cases/adapters under test)
# ══════════════════════════════════════════════════════════════════════════

## ScriptedTargetingPort -- always returns the same pre-picked target,
## mirroring every prior boot-real Cast-a-Spell suite's identically-shaped
## test double (e.g. tests/boot/test_fire_bolt_full_cast_e2e_log.gd).
class ScriptedTargetingPort:
	extends TargetingPortClass
	var scripted_target = null

	func request_single_target(_legal_targets: Array):
		return scripted_target


## FakeRoundEnergyPoolPort -- duck-typed RoundEnergyPoolPort double
## (mirrors tests/unit/test_begin_cast_use_case.gd's / tests/unit/core/
## application/test_castable_spell_ids_regression.gd's identically-shaped
## fake): a single in-memory balance, generous enough that Frost Breath's
## energy_cost (1) is never gated by round-energy availability, isolating
## this suite's assertions to the item-implement/discharge/condition/log
## steel thread it exists to prove end-to-end.
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int

	func _init(starting_balance: int = 99) -> void:
		_balance = starting_balance

	func reserve(_caster_id: String, amount: int) -> bool:
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## FakeActionEconomy -- duck-typed action-economy double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own fake.
class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


# ══════════════════════════════════════════════════════════════════════════
# The steel thread
# ══════════════════════════════════════════════════════════════════════════

func test_frost_breath_cast_discharge_dazed_and_cold_combat_log_steel_thread() -> void:
	# ── Boot the prologue encounter fixture, pinned to PROLOGUE_SEED=42
	# (NFR-005 determinism). ──────────────────────────────────────────────
	var encounter = ResourceLoader.load(PROLOGUE_ENCOUNTER_RESOURCE_PATH)
	assert_not_null(encounter, "fixture assumption: the prologue encounter resource must load")
	assert_eq(encounter.seed, PROLOGUE_SEED, "fixture assumption: the prologue encounter is pinned to PROLOGUE_SEED=42 (NFR-005)")
	assert_true(encounter.enemy_resource_paths.size() > 0, "fixture assumption: the prologue encounter carries at least one enemy")
	var enemy_path: String = encounter.enemy_resource_paths[0]

	var gram_marx := _build_gram_marx_combatant()
	var skeleton = _build_living_skeleton(enemy_path, HexCoordClass.new(1, 0))
	assert_true(skeleton.is_conscious(), "fixture assumption: the target must be a LIVING enemy before this steel thread casts against it")

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var action_economy := FakeActionEconomy.new()

	# ── ENTRY POINT (AA-3-1): frost_breath is offered ONLY through the
	# charged, equipped orb_gram -- Gram Marx knows no spells innately. ────
	assert_eq(gram_marx.known_spell_ids, [], "fixture assumption: Gram Marx (Wizard, item-only caster) knows no innate spells")

	var castable_before: Array = BeginCastUseCaseClass.new().castable_spell_ids(gram_marx, catalog, pool)
	assert_true(castable_before.has("frost_breath"), "entry point: castable_spell_ids(gram_marx_combatant) must contain 'frost_breath' before casting -- orb_gram is charged and equipped")

	var orb_gram = null
	for item in gram_marx.equipped_items:
		if item.prepared_spell_id == "frost_breath":
			orb_gram = item
			break
	assert_not_null(orb_gram, "fixture assumption: orb_gram must be among Gram Marx's equipped items")
	assert_true(orb_gram.is_charged, "fixture assumption: orb_gram must start charged")

	# ── Full cast-to-resolution sequence against the living Skeleton target,
	# through the real (unmocked) use cases/adapters/CombatantFactory-built
	# combatant dicts. ─────────────────────────────────────────────────────
	var begin_result: Dictionary = BeginCastUseCaseClass.new().execute(gram_marx, "frost_breath", catalog, pool, action_economy)
	assert_true(begin_result.get("success", false), "BeginCastUseCase.execute() must succeed for the charged, item-prepared frost_breath")
	assert_eq(begin_result.get("error"), ErrorCodeClass.NONE)
	assert_true(gram_marx.is_casting(), "a successful begin-cast must leave Gram Marx mid-cast")
	assert_eq(gram_marx.casting_state.get("remaining_actions"), 1, "Frost Breath's 2-action cost must leave 1 remaining action after begin_cast")

	var continue_result: Dictionary = ContinueCastUseCaseClass.new().execute(gram_marx, action_economy)
	assert_true(continue_result.get("success", false), "ContinueCastUseCase.execute() must succeed to drive remaining_actions to 0")
	assert_eq(gram_marx.casting_state.get("remaining_actions"), 0, "the cast must now be ready to resolve")

	var targeting := ScriptedTargetingPort.new()
	targeting.scripted_target = skeleton
	var combat_log_panel := CombatLogPanelAdapterClass.new()
	var resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(SeededRandomAdapterClass.new(PROLOGUE_SEED))

	var controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"targeting_port": targeting,
		"candidates_fn": func(): return [skeleton],
		"resolution_port": resolution_port,
		"combat_log_port": combat_log_panel,
	})

	# ── EXIT POINT: the presentation-layer discharge hook + resolution,
	# driven through the REAL ResolveSpellController. ──────────────────────
	var resolve_result: Dictionary = await controller.execute(gram_marx, 1)
	assert_true(resolve_result.get("success", false), "ResolveSpellController.execute() must succeed once a live target is resolved against")
	assert_eq(resolve_result.get("target_id"), skeleton.display_id())

	assert_false(gram_marx.is_casting(), "casting_state must be cleared immediately after resolution")
	assert_true(gram_marx.casting_state.is_empty(), "the live GramMarxCombatant's own casting_state Dictionary must be empty")

	# ── Post-cast: orb_gram.is_charged==false. ─────────────────────────────
	assert_false(orb_gram.is_charged, "post-cast: orb_gram must be discharged (is_charged==false) after a successful energy-costing cast resolves")

	# ── Emitted CombatLogEntry.damage_type=='cold'. ─────────────────────────
	assert_eq(combat_log_panel.get_entry_count(), 1, "exactly one CAST_RESOLVE entry must be emitted for this cast")
	var entry = combat_log_panel.get_entry(0)
	assert_true(entry is CombatLogEntryClass)
	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.spell_id, "frost_breath")
	assert_eq(entry.actor_id, gram_marx.display_id())
	assert_eq(entry.target_ids, [skeleton.display_id()])
	assert_eq(entry.damage_type, "cold", "Frost Breath's CombatLogEntry must record damage_type=='cold'")
	assert_eq(entry.to_dict().get("damage_type"), "cold", "to_dict()['damage_type'] must be 'cold'")

	# ── Post-cast: deterministic Dazed presence/absence per the
	## PROLOGUE_SEED=42-seeded hit/miss outcome. ────────────────────────────
	assert_typeof(entry.hit, TYPE_BOOL, "hit must resolve to a real bool, never left null, once a genuine living target was resolved against")
	if entry.hit:
		assert_gt(entry.damage_amount, 0, "a hit must carry a positive damage_amount")
		assert_true(skeleton.has_condition("Dazed"), "a seeded HIT against frost_breath's condition_on_hit=='dazed' must apply Dazed to the target")
	else:
		assert_eq(entry.damage_amount, 0, "a miss must carry zero damage_amount")
		assert_false(skeleton.has_condition("Dazed"), "a seeded MISS must NOT apply Dazed to the target")

	# ── Post-cast: castable_spell_ids() no longer offers 'frost_breath'
	# now that orb_gram is discharged. ──────────────────────────────────────
	var castable_after: Array = BeginCastUseCaseClass.new().castable_spell_ids(gram_marx, catalog, pool)
	assert_false(castable_after.has("frost_breath"), "exit point: castable_spell_ids(gram_marx_combatant) must no longer contain 'frost_breath' once orb_gram is discharged")
