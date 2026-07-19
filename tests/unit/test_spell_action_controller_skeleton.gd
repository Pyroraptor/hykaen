extends GutTest
## tests/unit/test_spell_action_controller_skeleton.gd — FEAT-004 (US-004;
## FR-003)
##
## GUT suite for presentation/verbs/spell_action_controller.gd's
## SpellActionController — the CAST_SPELL verb's skeleton three-step
## contract (availability()/enter_selection()/execute()) and its
## `_verb_deps()` declared-ports list, plus core/application/ports/errors.gd's
## shared ErrorCode enum.
##
## Mirrors tests/unit/test_action_controller_execute_shapes.gd's established
## "minimal fake subclass / small real fake session" convention: no
## real MainScene.tscn boot is needed to exercise a single verb controller
## in isolation (that's tests/boot/test_main_scene_cast_spell_verb_registered.gd's
## job).
##
## test_criteria covered:
##   1. SpellActionController._verb_deps() returns the expected port list.
##   2. Stub availability()/enter_selection()/execute() return
##      contract-consistent shapes without crashing.

const SpellActionControllerClass = preload("res://presentation/verbs/spell_action_controller.gd")
const RoundSessionHolderClass    = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass             = preload("res://core/domain/combatant.gd")
const HexCoordClass              = preload("res://core/geometry/hex_coord.gd")
const ErrorCodeClass             = preload("res://core/application/ports/errors.gd")


## FakeSession — a tiny, real (not all-mocked) double satisfying the same
## current_actor()/current_actor_entity()/current_action_economy() contract
## core/application/round_session.gd's RoundSession exposes -- the only
## surface ActionController's base class (presentation/action_controller.gd)
## reads through the injected session_holder.
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


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


func _make_caster(known_spell_ids: Array, casting: bool = false):
	var actor := CombatantClass.new("caster_0", "Marigold", "Player", HexCoordClass.new(0, 0))
	actor.known_spell_ids = known_spell_ids
	if casting:
		actor.casting_state = {"spell_id": "fire_bolt", "remaining_actions": 1, "committed_energy": 0}
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: _verb_deps() returns the expected port list
# ══════════════════════════════════════════════════════════════════════════

func test_verb_deps_returns_the_expected_port_list() -> void:
	var ports: Array = SpellActionControllerClass._verb_deps()

	assert_eq(
		ports,
		["SelectionPort", "RoundEnergyPoolPort", "SpellCatalogPort", "ReactionWindowPort"],
		"SpellActionController._verb_deps() must declare exactly the four ports design notes' architecture section names"
	)


func test_verb_deps_is_callable_without_constructing_an_instance() -> void:
	# _verb_deps() is a pure, static declaration of the contract -- a
	# composition-root wiring check must be able to call it without first
	# building a controller (which itself requires a deps dict).
	assert_true(SpellActionControllerClass._verb_deps().size() > 0, "_verb_deps() must return a non-empty list even when called statically")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: stub availability()/enter_selection()/execute() return
# contract-consistent shapes without crashing
# ══════════════════════════════════════════════════════════════════════════

func test_availability_is_false_with_no_live_session() -> void:
	var controller := SpellActionControllerClass.new(_deps())

	assert_false(controller.availability(), "availability() must fail safe to false when there is no live session/actor")


func test_availability_is_false_when_actor_knows_no_spells_and_is_not_casting() -> void:
	var actor = _make_caster([])
	var controller := SpellActionControllerClass.new(_deps(actor))

	assert_false(controller.availability(), "an actor with an empty known_spell_ids and no in-progress cast must be unavailable")


func test_availability_is_true_when_actor_knows_at_least_one_spell() -> void:
	var actor = _make_caster(["fire_bolt", "channel"])
	var controller := SpellActionControllerClass.new(_deps(actor))

	assert_true(controller.availability(), "an actor with >=1 known spell must be available (skeleton half of US-004 contract #1)")


func test_availability_is_true_when_actor_is_already_mid_cast() -> void:
	var actor = _make_caster(["fire_bolt"], true)
	var controller := SpellActionControllerClass.new(_deps(actor))

	assert_true(controller.availability(), "an actor already mid-cast (is_casting() == true) must be available -- the 'continue casting' path")


func test_enter_selection_returns_verb_id_tagged_candidate_shape_when_not_casting() -> void:
	var actor = _make_caster(["fire_bolt", "channel"])
	var controller := SpellActionControllerClass.new(_deps(actor))

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL", "enter_selection() must tag its result with verb_id CAST_SPELL, mirroring every other verb")
	assert_true(selection.has("candidate_hexes"), "enter_selection() must return the shared candidate_hexes key")
	assert_true(selection.has("candidate_targets"), "enter_selection() must return the shared candidate_targets key")


func test_enter_selection_returns_empty_dict_when_actor_is_already_mid_cast() -> void:
	var actor = _make_caster(["fire_bolt"], true)
	var controller := SpellActionControllerClass.new(_deps(actor))

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection, {}, "enter_selection() must skip Layer 2 selection (empty Dictionary) when the actor is already mid-cast (US-006)")


func test_enter_selection_does_not_crash_with_no_live_session() -> void:
	var controller := SpellActionControllerClass.new(_deps())

	var selection: Dictionary = controller.enter_selection()

	assert_eq(selection.get("verb_id"), "CAST_SPELL", "enter_selection() with no live actor must still fail safe to the tagged empty-candidate shape, never crash")


func test_execute_returns_contract_consistent_shape_without_crashing() -> void:
	var actor = _make_caster(["fire_bolt"])
	var controller := SpellActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.execute("fire_bolt")

	assert_true(result.has("success"), "execute()'s result must carry a 'success' key (ExecuteResult contract)")
	assert_true(result.has("casting_state"), "execute()'s result must carry a 'casting_state' key (ExecuteResult contract)")
	assert_true(result.has("error"), "execute()'s result must carry an 'error' key (ExecuteResult contract)")
	assert_false(result.get("success"), "the skeleton stub must never report success -- no use case is wired in yet")
	assert_null(result.get("casting_state"), "the skeleton stub must never mutate/set casting_state")
	assert_eq(result.get("error"), ErrorCodeClass.NONE, "the skeleton stub's error must be the closed enum's NONE member, not a fabricated real failure code")


func test_execute_does_not_crash_with_no_selection_argument() -> void:
	var controller := SpellActionControllerClass.new(_deps())

	var result: Dictionary = controller.execute()

	assert_false(result.get("success", true), "execute() called with no selection argument at all must still fail safe, never crash")


# ══════════════════════════════════════════════════════════════════════════
# ErrorCode (core/application/ports/errors.gd) — shared closed enum sanity
# ══════════════════════════════════════════════════════════════════════════

func test_error_code_none_is_the_zero_default_member() -> void:
	assert_eq(ErrorCodeClass.NONE, 0, "ErrorCode.NONE must be the enum's zero/default member")


func test_error_code_declares_every_api_contract_member_as_a_distinct_value() -> void:
	# Direct static references (not generic Object.get()/has() reflection --
	# GDScript enum members are compile-time constants of the script class,
	# not instance properties) confirming every api_contracts error code
	# exists and every member below is a distinct integer (a closed enum
	# with no accidental aliasing).
	var values: Array = [
		ErrorCodeClass.NONE,
		ErrorCodeClass.ERR_NO_CASTABLE_SPELL,
		ErrorCodeClass.ERR_INSUFFICIENT_ENERGY,
		ErrorCodeClass.ERR_NOT_CASTABLE,
		ErrorCodeClass.ERR_CAST_CANCELLED,
		ErrorCodeClass.ERR_NO_VALID_TARGET,
		ErrorCodeClass.ERR_INVALID_STATE,
	]

	var seen_values: Dictionary = {}
	for value in values:
		assert_false(seen_values.has(value), "ErrorCode member value %s must not alias another member's value" % value)
		seen_values[value] = true

	assert_eq(values.size(), 7, "ErrorCode must declare exactly the 7 members (NONE + the 6 api_contracts error codes)")
