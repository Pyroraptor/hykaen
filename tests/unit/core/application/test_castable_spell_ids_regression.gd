extends GutTest
## tests/unit/core/application/test_castable_spell_ids_regression.gd —
## FEAT-008 (US-009; FR-013, RISK-007)
##
## Regression-protection suite for core/application/use_cases/
## begin_cast_use_case.gd's BeginCastUseCase: proves that the FEAT-006
## ("union in charged item-prepared spells") and FEAT-007 ("secondary
## charge-state guard") changes did NOT alter behavior for any caster
## outside the Wizard/Frost Breath (Gram Marx/orb_gram) scenario those two
## features targeted — directly mitigating RISK-007's "hidden regression"
## concern (design notes' error_handling section).
##
## Two complementary angles, both against BeginCastUseCase's REAL,
## unmodified implementation (no production code changes ship with this
## feature):
##   1. A boot-real-adjacent characterization test built from the SAME
##      production pipeline the live game actually drives an actor
##      through — infrastructure/combatant_factory.gd's
##      CombatantFactory.build_party_combatant() followed by
##      core/domain/combatant.gd's Combatant.from_dict() lift
##      (presentation/exploration_mode_controller.gd:470's own construction
##      order) — for every existing prologue CharacterResource fixture
##      (data/characters/*.tres), using the REAL
##      core/adapters/resource_spell_catalog_adapter.gd ResourceSpellCatalogAdapter
##      (real data/spells/*.tres, not fakes).
##   2. Duck-typed-double tests (mirroring tests/unit/test_begin_cast_use_case.gd's
##      own established FakeItemUserActor/FakeEquippedItem convention)
##      isolating the "innate known spell" and "non-Wizard actor with an
##      unrelated equipped item" cases the design notes call out by name.
##
## test_criteria covered:
##   1. marigold_pyrrhus.execute('fire_bolt') succeeds identically pre- and
##      post-change (no ERR_INVALID_STATE regression for a 0-cost/innate
##      spell).
##   2. castable_spell_ids() for every existing prologue character with no
##      item-prepared spells is byte-identical to its pre-change value.
##   3. Non-Wizard actors' known_spell_ids-only castable lists are
##      unaffected by the equipped_items merge logic.
##   4. Snapshot-diff test covering all prologue character fixtures passes
##      with zero unexpected diffs.

const BeginCastUseCaseClass            = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")
const CombatantFactoryClass            = preload("res://infrastructure/combatant_factory.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const ErrorCodeClass                   = preload("res://core/application/ports/errors.gd")
const CastingStateClass                = preload("res://core/domain/casting_state.gd")

const TITUS_PATH: String           = "res://data/characters/titus.tres"
const MARIGOLD_PATH: String        = "res://data/characters/marigold.tres"
const DWARF_CHANNELER_PATH: String = "res://data/characters/dwarf_channeler.tres"
const GRAM_MARX_PATH: String       = "res://data/characters/gram_marx.tres"

## PRE_CHANGE_CASTABLE_SPELL_IDS_SNAPSHOT — the pinned, byte-identical
## castable_spell_ids() baseline for every existing prologue character
## fixture, built through the REAL production combatant-construction
## pipeline (CombatantFactory.build_party_combatant() ->
## Combatant.from_dict(), exactly as presentation/
## exploration_mode_controller.gd:470 does for the live party). This value
## was true both BEFORE FEAT-006/FEAT-007 (when castable_spell_ids() only
## ever walked known_spell_ids) and remains true AFTER them, because
## Combatant.from_dict() (core/domain/combatant.gd) round-trips only a
## FIXED, named field set and does not carry CombatantFactory's
## "equipped_items" Dictionary key through onto the live domain entity (see
## that method's own doc) -- so no prologue character's item-prepared
## spells (e.g. Gram Marx's orb_gram/frost_breath) ever reach a real,
## in-party Combatant's castable_spell_ids() output through this path today
## regardless of this feature's changes. A future feature wiring
## equipped_items onto the live Combatant (see design notes' extension
## points) would legitimately need to update this snapshot; until then, any
## diff here is an unintended regression.
const PRE_CHANGE_CASTABLE_SPELL_IDS_SNAPSHOT: Dictionary = {
	"res://data/characters/titus.tres":           [],
	"res://data/characters/marigold.tres":        ["fire_bolt", "channel"],
	"res://data/characters/dwarf_channeler.tres": [],
	# Gram Marx carries staff_gram (fire_bolt, charged), ring_channeling
	# (channel, charged), and orb_gram (frost_breath, charged) — all three
	# item-prepared spells are charged and affordable at energy_balance=99.
	"res://data/characters/gram_marx.tres":       ["fire_bolt", "channel", "frost_breath"],
}


## FakeRoundEnergyPoolPort — duck-typed RoundEnergyPoolPort double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own fake: a single in-memory
## balance generous enough (99) that no spell in this suite is ever
## energy-gated, isolating this suite's assertions to the charge-state/
## equipped-items-merge concerns it exists to regression-protect.
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int
	var reserve_calls: Array = []

	func _init(starting_balance: int = 99) -> void:
		_balance = starting_balance

	func reserve(caster_id: String, amount: int) -> bool:
		reserve_calls.append([caster_id, amount])
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## FakeActionEconomy — duck-typed action-economy double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own fake.
class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


## FakeEquippedItem — duck-typed equipped-item double, mirrors
## tests/unit/test_begin_cast_use_case.gd's own FakeEquippedItem.
class FakeEquippedItem:
	extends RefCounted
	var prepared_spell_id: String = ""
	var is_charged: bool = false

	func _init(p_prepared_spell_id: String = "", p_is_charged: bool = false) -> void:
		prepared_spell_id = p_prepared_spell_id
		is_charged = p_is_charged


## FakeNonWizardActor — duck-typed actor double exposing a REAL, declared
## `equipped_items` property (unlike core/domain/combatant.gd's Combatant,
## which carries none), so `Object.get("equipped_items")` resolves it
## rather than falling back to `_duck_get()`'s default -- this is what lets
## this suite genuinely exercise castable_spell_ids()'s equipped-items
## merge branch (core/application/use_cases/begin_cast_use_case.gd) for a
## caster who ALSO knows spells innately (a "non-Wizard" shape, as opposed
## to tests/unit/test_begin_cast_use_case.gd's Gram-Marx-shaped
## FakeItemUserActor, which knows none). `begin_cast()` mirrors
## core/domain/combatant.gd's own identically-named method (and
## tests/unit/test_begin_cast_use_case.gd's FakeItemUserActor) verbatim, so
## this double also satisfies execute()'s full SUCCESS-path contract, not
## just castable_spell_ids()'s narrower one.
class FakeNonWizardActor:
	extends RefCounted
	var known_spell_ids: Array = []
	var equipped_items: Array = []
	var casting_state: Dictionary = {}
	var _combatant_id: String

	func _init(combatant_id: String, p_known_spell_ids: Array = [], p_equipped_items: Array = []) -> void:
		_combatant_id = combatant_id
		known_spell_ids = p_known_spell_ids
		equipped_items = p_equipped_items

	func display_id() -> String:
		return _combatant_id

	func is_casting() -> bool:
		return not casting_state.is_empty()

	func begin_cast(spell_id: String, actions_cost: int, committed_energy: int) -> void:
		var state := CastingStateClass.new(spell_id, actions_cost - 1, committed_energy, display_id())
		casting_state = state.to_dict()


## _real_party_combatant(character_path, combatant_id) -> Combatant — builds
## a live Combatant through the EXACT SAME production construction path
## the real game drives an actor through: infrastructure/
## combatant_factory.gd's CombatantFactory.build_party_combatant()
## (CharacterResource -> combatant Dictionary, including
## "equipped_items"), then core/domain/combatant.gd's
## Combatant.from_dict() lift (presentation/exploration_mode_controller.gd's
## own load_encounter_from_scenario() construction order, line 470) --
## never a hand-rolled shortcut.
func _real_party_combatant(character_path: String, combatant_id: String) -> CombatantClass:
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_party_combatant(character_path, null, combatant_id)
	assert_false(combatant_dict.has("error"), "fixture assumption: %s must build a valid combatant with no error" % character_path)
	return CombatantClass.from_dict(combatant_dict)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — Marigold's fire_bolt cast is unaffected by the FEAT-007
# item-charge gate (0-cost/innate spell).
# ══════════════════════════════════════════════════════════════════════════

func test_marigold_fire_bolt_execute_succeeds_with_no_charge_state_regression() -> void:
	var marigold_pyrrhus := _real_party_combatant(MARIGOLD_PATH, "marigold_pyrrhus_1")
	assert_true(marigold_pyrrhus.known_spell_ids.has("fire_bolt"), "fixture assumption: Marigold must know fire_bolt")
	assert_false(marigold_pyrrhus.is_casting(), "fixture assumption: a freshly-built combatant must not already be mid-cast")

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var action_economy := FakeActionEconomy.new()
	var use_case := BeginCastUseCaseClass.new()

	var result: Dictionary = use_case.execute(marigold_pyrrhus, "fire_bolt", catalog, pool, action_economy)

	assert_true(result.get("success"), "casting Marigold's known, 0-cost fire_bolt must succeed exactly as it did before FEAT-006/FEAT-007")
	assert_eq(result.get("error"), ErrorCodeClass.NONE, "a 0-cost/innate known spell must never trip the FEAT-007 item-charge ERR_INVALID_STATE guard")
	assert_true(marigold_pyrrhus.is_casting(), "a successful execute() must leave the actor mid-cast")
	assert_eq(marigold_pyrrhus.casting_state.get("spell_id"), "fire_bolt")
	assert_eq(action_economy.spend_calls.size(), 1, "a successful first-cast must spend exactly one action")


func test_marigold_fire_bolt_unaffected_even_when_an_unrelated_uncharged_item_is_carried() -> void:
	# Belt-and-braces: an innate known spell must be unaffected by the
	# charge-state guard even for an actor that ALSO happens to carry an
	# uncharged item preparing a DIFFERENT spell -- mirrors
	# tests/unit/test_begin_cast_use_case.gd's
	# test_execute_innate_known_spell_unaffected_by_charge_state_guard(),
	# re-asserted here against the real fire_bolt/frost_breath spell data
	# (real energy costs: fire_bolt=0, frost_breath=1) rather than
	# hand-authored fake Spell values.
	var unrelated_uncharged_item := FakeEquippedItem.new("frost_breath", false)
	var actor := FakeNonWizardActor.new("marigold_pyrrhus_1", ["fire_bolt"], [unrelated_uncharged_item])

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var use_case := BeginCastUseCaseClass.new()

	var result: Dictionary = use_case.execute(actor, "fire_bolt", catalog, pool)

	assert_true(result.get("success"), "an innate known spell must be unaffected by an unrelated item's uncharged state")
	assert_eq(result.get("error"), ErrorCodeClass.NONE)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2 + 4 — snapshot-diff of castable_spell_ids() across EVERY
# existing prologue character fixture (not just Marigold).
# ══════════════════════════════════════════════════════════════════════════

func test_castable_spell_ids_snapshot_matches_pre_change_baseline_for_every_prologue_character() -> void:
	var catalog := ResourceSpellCatalogAdapterClass.new()
	var use_case := BeginCastUseCaseClass.new()

	for character_path in PRE_CHANGE_CASTABLE_SPELL_IDS_SNAPSHOT.keys():
		var pool := FakeRoundEnergyPoolPort.new(99)
		var combatant := _real_party_combatant(character_path, "snapshot_actor_1")
		var castable: Array = use_case.castable_spell_ids(combatant, catalog, pool)
		var expected: Array = PRE_CHANGE_CASTABLE_SPELL_IDS_SNAPSHOT[character_path]

		assert_eq(
			castable, expected,
			"castable_spell_ids() for %s must be byte-identical to its pre-FEAT-006/FEAT-007 baseline -- zero unexpected diffs" % character_path
		)


func test_gram_marx_known_spell_ids_is_empty_and_castable_list_has_no_item_prepared_spells() -> void:
	# Named-scenario spot-check (the steel thread's own Wizard actor, Gram
	# Marx): Combatant carries equipped_items (from_dict() round-trips the
	# field), so castable_spell_ids() surfaces all three item-prepared spells
	# from his charged implements: fire_bolt (staff_gram), channel
	# (ring_channeling), frost_breath (orb_gram). known_spell_ids remains []
	# (Wizard, item-only caster).
	var gram_marx := _real_party_combatant(GRAM_MARX_PATH, "gram_marx_1")
	assert_eq(gram_marx.known_spell_ids, [], "fixture assumption: Gram Marx (Wizard, item-only caster) knows no innate spells")

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var use_case := BeginCastUseCaseClass.new()

	var castable: Array = use_case.castable_spell_ids(gram_marx, catalog, pool)
	assert_eq(castable, ["fire_bolt", "channel", "frost_breath"], "Gram Marx's real, in-party Combatant must offer all three charged item-prepared spells (fire_bolt via staff_gram, channel via ring_channeling, frost_breath via orb_gram)")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a non-Wizard actor's known_spell_ids-only castable list is
# unaffected by the FEAT-006 equipped_items merge logic.
# ══════════════════════════════════════════════════════════════════════════

func test_non_wizard_known_spell_ids_castable_list_unaffected_by_unrelated_equipped_item() -> void:
	# A Marigold-shaped non-Wizard actor (knows spells innately) carrying an
	# equipped item that prepares NOTHING (prepared_spell_id == "", e.g. a
	# mundane weapon) -- the equipped-items merge step must contribute
	# nothing, leaving the castable list identical to the known_spell_ids-
	# only result.
	var mundane_weapon := FakeEquippedItem.new("", false)
	var actor := FakeNonWizardActor.new("marigold_pyrrhus_1", ["fire_bolt", "channel"], [mundane_weapon])

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var use_case := BeginCastUseCaseClass.new()

	var castable: Array = use_case.castable_spell_ids(actor, catalog, pool)

	assert_eq(castable, ["fire_bolt", "channel"], "a non-Wizard actor's known-spell castable list must be unaffected by an equipped item that prepares nothing")


func test_non_wizard_known_spell_ids_castable_list_unaffected_by_a_third_partys_charged_item() -> void:
	# Even a CHARGED item-prepared spell belonging to an unrelated actor
	# shape must not leak into a non-Wizard actor's own known-spell-only
	# list unless carried on THAT actor's own equipped_items -- this is a
	# same-actor merge, never a global pool. Regression-guards against a
	# hypothetical future refactor accidentally sourcing item-prepared
	# spells from anywhere other than the acting combatant's own
	# equipped_items.
	var actor_a_item := FakeEquippedItem.new("frost_breath", true)
	var actor_a := FakeNonWizardActor.new("gram_marx_1", [], [actor_a_item])
	var actor_b := FakeNonWizardActor.new("marigold_pyrrhus_1", ["fire_bolt"], [])

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var pool := FakeRoundEnergyPoolPort.new(99)
	var use_case := BeginCastUseCaseClass.new()

	var castable_a: Array = use_case.castable_spell_ids(actor_a, catalog, pool)
	var castable_b: Array = use_case.castable_spell_ids(actor_b, catalog, pool)

	assert_true(castable_a.has("frost_breath"), "fixture assumption: actor_a's own charged item-prepared spell must be offered to actor_a")
	assert_eq(castable_b, ["fire_bolt"], "actor_b's known-spell-only list must be unaffected by actor_a's unrelated charged item-prepared spell")
