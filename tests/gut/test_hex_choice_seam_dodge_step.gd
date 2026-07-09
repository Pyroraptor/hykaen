extends GutTest
## tests/gut/test_hex_choice_seam_dodge_step.gd
##
## GUT suite for FEAT-001 (US-001, Dodge-Step steel thread): audits the
## EXISTING sprint-12 hex-choice injection seam
## (core/application/ports/hex_choice_resolver_port.gd, wired at the
## MainScene.gd composition root via the `hex_choice_resolver` field +
## resolve_hex_choice()) and confirms/extends it to accept a scripted
## legal-hex pick for the new Dodge-Step flow, per ADR-001/ADR-002
## ("no duplicate seam" — ResolveDodgeStepUseCase, a later feature, will
## reuse this EXACT seam rather than a parallel one).
##
## Verifies (this feature's test_criteria):
##   1. seam.choose_step_hex() accepts a scripted HexCoord for a Dodge-Step
##      request and returns it unchanged when it is a member of the
##      supplied legal_hexes set.
##   2. The original FEAT-001 caller (MainScene.gd's own
##      resolve_hex_choice(), the existing sprint-12 flow) still resolves
##      correctly with no behavior change (regression).
##
## Also exercises the companion RoundSession-level seam
## (set_hex_choice_resolver_fn() / _resolve_step_hex_choice()) this feature
## establishes on core/application/round_session.gd, mirroring the
## hex_choice_resolver_port.gd contract exactly, plus the G3/G4
## "zero-legal-adjacent-hex never awaits/prompts" guard.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


## ScriptedHexChoiceResolver — a concrete, scripted HexChoiceResolverPort
## test double (mirrors tests/application/test_hex_choice_resolver_seam.gd's
## own double of the same name/role exactly): always returns the
## pre-configured `_scripted_hex` for a non-empty legal_hexes (recording
## what it was handed for assertion), and null for an empty legal_hexes.
class ScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var _scripted_hex
	var received_legal_hexes: Array = []
	var call_count: int = 0

	func _init(scripted_hex) -> void:
		_scripted_hex = scripted_hex

	func resolve(legal_hexes: Array):
		call_count += 1
		received_legal_hexes = legal_hexes
		if legal_hexes.is_empty():
			return null
		return _scripted_hex


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root (mirrors this codebase's established convention, e.g.
## tests/application/test_hex_choice_resolver_seam.gd), pinning
## seed_override=42 for a deterministic boot.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — seam.choose_step_hex() accepts a scripted HexCoord for a
# Dodge-Step request and returns it unchanged when it is a member of the
# supplied legal_hexes set.
# ══════════════════════════════════════════════════════════════════════════

func test_choose_step_hex_returns_the_scripted_hex_unchanged_when_legal() -> void:
	var target_hex := HexCoordClass.new(1, -1)
	var other_hex := HexCoordClass.new(0, 1)
	var legal_hexes: Array = [target_hex, other_hex]

	var resolver := ScriptedHexChoiceResolver.new(target_hex)
	var result = await resolver.choose_step_hex("defender-alpha", legal_hexes)

	assert_not_null(result, "a scripted resolver handed a non-empty legal_hexes must never resolve to null")
	assert_true(result.equals(target_hex), "choose_step_hex() must return exactly the scripted choice, unchanged")
	var is_member: bool = false
	for hex in legal_hexes:
		if hex.equals(result):
			is_member = true
	assert_true(is_member, "the returned hex must be a member of the supplied legal_hexes set")


func test_choose_step_hex_delegates_to_the_same_resolve_seam_no_duplicate_logic() -> void:
	var target_hex := HexCoordClass.new(-2, 2)
	var legal_hexes: Array = [target_hex]
	var resolver := ScriptedHexChoiceResolver.new(target_hex)

	await resolver.choose_step_hex("defender-bravo", legal_hexes)

	assert_eq(resolver.call_count, 1, "choose_step_hex() must invoke the SAME underlying resolve() implementation, not a second one")
	assert_eq(resolver.received_legal_hexes, legal_hexes, "choose_step_hex() must forward legal_hexes to resolve() unmodified")


func test_choose_step_hex_returns_null_only_for_empty_legal_hexes() -> void:
	var resolver := ScriptedHexChoiceResolver.new(HexCoordClass.new(3, 0))

	var empty_result = await resolver.choose_step_hex("defender-charlie", [])
	assert_null(empty_result, "choose_step_hex() must return null for an empty legal_hexes (nothing to choose from)")

	var nonempty_result = await resolver.choose_step_hex("defender-charlie", [HexCoordClass.new(3, 0)])
	assert_not_null(nonempty_result, "choose_step_hex() must never return null for a non-empty legal_hexes")


func test_base_port_choose_step_hex_mirrors_resolves_null_for_empty_contract() -> void:
	var port := HexChoiceResolverPortClass.new()
	var result = await port.choose_step_hex("defender-delta", [])
	assert_null(result, "the abstract base Port's choose_step_hex() must honor the same null-only-when-empty contract as resolve()")


func test_choose_step_hex_flows_through_the_real_mainscene_wired_resolver() -> void:
	# G2: proves the Dodge-Step entry point works against the REAL,
	# composition-root-wired hex_choice_resolver field (never a resolver
	# self-wired/constructed in isolation by this test), exactly mirroring
	# tests/application/test_hex_choice_resolver_seam.gd's own convention.
	var instance = _boot_main_scene()

	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]

	var scripted := ScriptedHexChoiceResolver.new(target_hex)
	instance.hex_choice_resolver = scripted

	var result = await instance.hex_choice_resolver.choose_step_hex("defender-echo", legal_hexes)

	assert_true(result.equals(target_hex), "choose_step_hex() called on the REAL composition-root-wired resolver must return the scripted Dodge-Step choice")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the original FEAT-001 caller (MainScene.gd's own
# resolve_hex_choice(), the existing sprint-12 flow) still resolves
# correctly with no behavior change (regression).
# ══════════════════════════════════════════════════════════════════════════

func test_original_feat001_resolve_hex_choice_flow_is_unaffected_by_this_extension() -> void:
	var instance = _boot_main_scene()

	var target_hex := HexCoordClass.new(1, 0)
	var other_hex := HexCoordClass.new(0, 1)
	var legal_hexes: Array = [target_hex, other_hex]

	var scripted := ScriptedHexChoiceResolver.new(target_hex)
	instance.hex_choice_resolver = scripted

	# The ORIGINAL sprint-12 call path (single-argument legal_hexes only,
	# never defender_id) — must still resolve exactly as before.
	var result = await instance.resolve_hex_choice(legal_hexes)

	assert_not_null(result, "the pre-existing resolve_hex_choice() call path must be completely unaffected by adding choose_step_hex()")
	assert_true(result.equals(target_hex), "resolve_hex_choice() must still return exactly the scripted choice, byte-for-byte unchanged")
	assert_eq(scripted.call_count, 1, "resolve_hex_choice() must still invoke resolve() exactly once, the same as before this feature")


func test_default_hex_choice_resolver_still_wired_at_boot_after_this_extension() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.hex_choice_resolver, "MainScene must still wire a default hex_choice_resolver during initialization (regression)")
	assert_true(
		is_instance_of(instance.hex_choice_resolver, HexChoiceResolverPortClass),
		"the wired default must still satisfy the HexChoiceResolverPort contract (regression)"
	)
	assert_true(
		instance.hex_choice_resolver.has_method("choose_step_hex"),
		"the production default resolver must now ALSO expose choose_step_hex() via inheritance from the extended base Port"
	)


# ══════════════════════════════════════════════════════════════════════════
# RoundSession-level seam establishment (core/application/round_session.gd):
# set_hex_choice_resolver_fn() / _resolve_step_hex_choice()
# ══════════════════════════════════════════════════════════════════════════

func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _durable_combatant(p_name: String, p_is_enemy: bool) -> Dictionary:
	return {
		"name":         p_name,
		"combatant_id": p_name.to_lower(),
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	}


class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


func _make_session():
	var alpha: Dictionary = _durable_combatant("Alpha", false)
	var bravo: Dictionary = _durable_combatant("Bravo", true)
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	return run_round_use_case.begin_round(1, [alpha], [bravo])


func test_set_hex_choice_resolver_fn_stores_and_is_invokable() -> void:
	var session = _make_session()
	var target_hex := HexCoordClass.new(1, 1)
	var resolver := ScriptedHexChoiceResolver.new(target_hex)

	session.set_hex_choice_resolver_fn(Callable(resolver, "resolve"))

	assert_true(session._hex_choice_resolver_fn.is_valid(), "the injected Callable must be stored and retrievable off RoundSession")

	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]
	var result = await session._resolve_step_hex_choice(legal_hexes)

	assert_true(result.equals(target_hex), "RoundSession's internal seam must invoke the injected Callable and return its result verbatim")
	assert_eq(resolver.call_count, 1, "the injected Callable must be invoked exactly once")


func test_resolve_step_hex_choice_defaults_to_null_when_unset() -> void:
	var session = _make_session()
	assert_false(session._hex_choice_resolver_fn.is_valid(), "fixture assumption: no resolver has been injected on a fresh session")

	var result = await session._resolve_step_hex_choice([HexCoordClass.new(1, 0)])

	assert_null(result, "an un-injected hex-choice seam must never fabricate/guess a hex for a non-empty legal_hexes")


func test_resolve_step_hex_choice_returns_null_immediately_for_empty_legal_hexes_without_invoking_resolver() -> void:
	# G3/G4 guard: the zero-legal-adjacent-hex case must short-circuit
	# BEFORE ever awaiting/invoking the injected resolver -- no prompt.
	var session = _make_session()
	var resolver := ScriptedHexChoiceResolver.new(HexCoordClass.new(5, 5))
	session.set_hex_choice_resolver_fn(Callable(resolver, "resolve"))

	var result = await session._resolve_step_hex_choice([])

	assert_null(result, "an empty legal_hexes must resolve to null")
	assert_eq(resolver.call_count, 0, "an empty legal_hexes must never invoke the injected resolver at all (no await/prompt)")


func test_round_session_hex_choice_seam_never_references_presentation_by_type() -> void:
	var f := FileAccess.open("res://core/application/round_session.gd", FileAccess.READ)
	assert_not_null(f, "core/application/round_session.gd must be readable")
	if f == null:
		return
	var source: String = f.get_as_text()
	f.close()

	assert_false(
		source.contains("res://presentation"),
		"RoundSession's new hex-choice seam must never preload/reference anything under presentation/ (ADR-001/ADR-002)"
	)
