extends GutTest
## tests/unit/test_cast_concentrate_trait_gate.gd — FEAT-284 (US-014; FR-016,
## PR-003)
##
## GUT suite proving presentation/verbs/spell_action_controller.gd's
## SpellActionController._provoke_reaction_on_cast() now gates on an
## explicit `spell.has_trait("Concentrate")` runtime check BEFORE ever
## touching the ReactionWindowPort collaborator (`_reaction`) — resolving
## PR-003's gating finding: FEAT-279 fired the window for ANY successful
## cast unconditionally, rather than checking the Concentrate trait first.
##
## Mirrors tests/unit/test_spell_action_controller_skeleton.gd's established
## "minimal fake subclass / small real fake session" convention. Exercises
## the CONTINUING-cast execute() branch (ContinueCastUseCase) rather than
## the first-cast branch, since it requires no RoundEnergyPoolPort/
## energy-reservation wiring at all (only the first-cast branch needs a
## session exposing get_energy_pool() — see that file's FakeSession doc),
## and `_provoke_reaction_on_cast()` runs identically on BOTH branches (see
## that method's own file-level doc: "runs on BOTH the first-cast ... and
## continuing-cast ... branches").
##
## test_criteria covered:
##   1. Casting a spell whose traits array includes "Concentrate" (Fire
##      Bolt, Channel — resolved through the REAL
##      ResourceSpellCatalogAdapter / data/spells/*.tres fixtures) still
##      fires the reaction window exactly as before (no regression to
##      US-014's existing behavior).
##   2. Casting a hypothetical spell fixture WITHOUT the "Concentrate"
##      trait does NOT invoke the reaction window at all.

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const RoundSessionHolderClass    = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const SpellClass                 = preload("res://core/domain/spell.gd")
const EffectKindClass            = preload("res://core/domain/effects/effect_kind.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")


## FakeSession — mirrors test_spell_action_controller_skeleton.gd's own
## identically-named double; deliberately does NOT implement
## get_energy_pool(), so this suite only ever exercises the
## CONTINUING-cast branch (see file-level doc).
class FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null


## FakeSpellCatalogPort — a minimal SpellCatalogPort double letting this
## suite inject a hypothetical non-Concentrate spell fixture the real
## ResourceSpellCatalogAdapter (data/spells/*.tres) has no authored file
## for.
class FakeSpellCatalogPort:
	extends RefCounted
	var _spells: Dictionary

	func _init(spells: Dictionary) -> void:
		_spells = spells

	func get_spell(spell_id: String):
		return _spells.get(spell_id, null)


## FakeReaction — a minimal ReactionWindowPort-shaped double (mirrors
## presentation/reaction_controller.gd's own method surface) recording
## whether the reaction window was ever actually consulted.
## order_candidate_reactors_by_initiative() is the FIRST call
## `_provoke_reaction_on_cast()` makes once past this feature's new gate,
## so a zero call count proves the window was never opened.
class FakeReaction:
	extends RefCounted
	var order_called_count: int = 0

	func order_candidate_reactors_by_initiative(candidates: Array) -> Array:
		order_called_count += 1
		return candidates

	func is_reactor_reaction_spent(_reactor) -> bool:
		return false

	func resolve_enemy_opportunistic_strike_reaction(_reactor, _context: Dictionary) -> Dictionary:
		return {"choice": "none"}


func _make_mid_cast_actor(spell_id: String):
	var actor := CombatantClass.new("caster_0", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = [spell_id]
	actor.casting_state = {
		"spell_id": spell_id,
		"remaining_actions": 2,
		"committed_energy": 0,
		"caster_id": "caster_0",
	}
	return actor


func _deps(actor, spell_catalog_port, reaction) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	holder.set_current(FakeSession.new(actor))
	return {
		"session_holder": holder,
		"spell_catalog_port": spell_catalog_port,
		"reaction": reaction,
		"living_enemy_reactors": Callable(),
		"current_turn_order": Callable(),
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a Concentrate-trait spell (Fire Bolt, Channel) still fires
# the reaction window exactly as before -- no regression to US-014.
# ══════════════════════════════════════════════════════════════════════════

func test_fire_bolt_continuing_cast_still_fires_reaction_window() -> void:
	var actor = _make_mid_cast_actor("fire_bolt")
	var reaction := FakeReaction.new()
	var controller := SpellActionControllerClass.new(_deps(actor, ResourceSpellCatalogAdapterClass.new(), reaction))

	var result: Dictionary = await controller.execute()

	assert_true(result.get("success", false), "the continuing-cast action itself must still succeed")
	assert_eq(reaction.order_called_count, 1, "a Fire Bolt (Concentrate-trait) continuing-cast action must still fire the reaction window exactly as before")


func test_channel_continuing_cast_still_fires_reaction_window() -> void:
	var actor = _make_mid_cast_actor("channel")
	var reaction := FakeReaction.new()
	var controller := SpellActionControllerClass.new(_deps(actor, ResourceSpellCatalogAdapterClass.new(), reaction))

	var result: Dictionary = await controller.execute()

	assert_true(result.get("success", false), "the continuing-cast action itself must still succeed")
	assert_eq(reaction.order_called_count, 1, "a Channel (Concentrate-trait) continuing-cast action must still fire the reaction window exactly as before")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: a hypothetical spell fixture WITHOUT the Concentrate trait
# does NOT invoke the reaction window.
# ══════════════════════════════════════════════════════════════════════════

func test_non_concentrate_spell_fixture_does_not_fire_reaction_window() -> void:
	var non_concentrate_spell := SpellClass.new(
		"test_shield", "Shield", 1, 0, SpellClass.Defense.NONE, 0,
		"", "", [], EffectKindClass.ADD_ENERGY, {}
	)
	var catalog := FakeSpellCatalogPort.new({"test_shield": non_concentrate_spell})
	var actor = _make_mid_cast_actor("test_shield")
	var reaction := FakeReaction.new()
	var controller := SpellActionControllerClass.new(_deps(actor, catalog, reaction))

	var result: Dictionary = await controller.execute()

	assert_true(result.get("success", false), "the continuing-cast action itself must still succeed even when the reaction window is gated off")
	assert_eq(reaction.order_called_count, 0, "a non-Concentrate-trait spell must NEVER invoke the reaction window")


func test_unresolvable_spell_id_does_not_fire_reaction_window() -> void:
	# Defensive: an unknown/malformed spell_id (empty catalog) must degrade
	# to "not Concentrate" rather than crash or fire the window.
	var catalog := FakeSpellCatalogPort.new({})
	var actor = _make_mid_cast_actor("nonexistent_spell")
	var reaction := FakeReaction.new()
	var controller := SpellActionControllerClass.new(_deps(actor, catalog, reaction))

	var result: Dictionary = await controller.execute()

	assert_true(result.get("success", false), "the continuing-cast action itself must still succeed")
	assert_eq(reaction.order_called_count, 0, "an unresolvable spell_id must never fire the reaction window")
