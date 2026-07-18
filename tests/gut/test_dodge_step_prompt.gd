extends GutTest
## tests/gut/test_dodge_step_prompt.gd
##
## GUT suite for FEAT-002 (US-002, Dodge-Step steel thread): "Prompt player
## to choose Dodge-Step destination hex". Boots the REAL res://MainScene.tscn
## composition root (G2 -- never a hand-wired double) and proves
## ResolveDodgeStepUseCase, wired through core/application/round_session.gd's
## new `_step_hex_query_fn`/`_hex_choice_resolver_fn`-driven
## `_resolve_dodge_step_prompt()` and MainScene.gd's rewire_session()
## wiring, actually triggers the SAME Step-selection prompt UX the FEAT-001
## seam (core/application/ports/hex_choice_resolver_port.gd,
## MainScene.gd's `hex_choice_resolver` field + resolve_hex_choice())
## already established -- reused, unmodified.
##
## Verifies (test_criteria):
##   1. Forcing a successful Dodge invokes the Step-selection prompt exactly
##      once.
##   2. The prompt's offered hex set exactly matches
##      movement_input_controller.get_selectable_step_hexes() for the
##      defender (no new adjacency rule introduced).
##   3. No prompt appears when the Dodge is not successful.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


## CountingScriptedHexChoiceResolver -- a concrete HexChoiceResolverPort test
## double (mirrors tests/gut/test_hex_choice_seam_dodge_step.gd's
## ScriptedHexChoiceResolver exactly) that records every resolve() call --
## the "was the Step-selection prompt invoked, and with which legal_hexes"
## observation point for this suite's assertions -- and always answers with
## the first hex it is offered (a deterministic, always-legal choice).
class CountingScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var call_count: int = 0
	var received_legal_hexes: Array = []

	func resolve(legal_hexes: Array):
		call_count += 1
		received_legal_hexes = legal_hexes
		if legal_hexes.is_empty():
			return null
		return legal_hexes[0]


## _hex_arrays_equal(a, b) -> bool -- element-wise HexCoord.equals() array
## comparison (HexCoord instances are compared by value throughout this
## codebase via .equals(), never GDScript's reference-based `==` -- see e.g.
## presentation/movement_input_controller.gd's own _find_selectable()). Two
## independently-computed hex arrays (e.g. one from
## movement_input_controller.get_selectable_step_hexes() and one from
## get_selectable_step_hexes_for()) are always DIFFERENT HexCoord object
## instances even when they name the same coordinates, so GUT's default
## assert_eq() (reference/`==`-based) is unsuitable here.
func _hex_arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not a[i].equals(b[i]):
			return false
	return true


## _boot_main_scene() -> Node -- instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention, e.g.
## tests/gut/test_hex_choice_seam_dodge_step.gd), pinning seed_override=42
## for a deterministic boot (Titus vs the Skeleton, prologue encounter).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 + 2: a successful Dodge invokes the Step-selection prompt
# exactly once, offering exactly get_selectable_step_hexes()'s set.
# ══════════════════════════════════════════════════════════════════════════

func test_successful_dodge_invokes_the_step_selection_prompt_exactly_once_with_the_matching_hex_set() -> void:
	var instance = _boot_main_scene()

	var defender = instance.round_session.current_actor()
	assert_eq(defender.name, "Titus", "fixture: Titus (the real player combatant) must be the current actor at boot")
	var defender_id: String = defender.display_id()

	# The REAL wiring this feature adds (MainScene.gd's rewire_session()):
	# round_session.set_hex_choice_resolver_fn(Callable(self, "resolve_hex_choice"))
	# round_session.set_step_hex_query_fn(Callable(self, "_query_selectable_step_hexes")).
	assert_true(instance.round_session._hex_choice_resolver_fn.is_valid(), "MainScene must wire round_session.set_hex_choice_resolver_fn() in its composition root")
	assert_true(instance.round_session._step_hex_query_fn.is_valid(), "MainScene must wire round_session.set_step_hex_query_fn() in its composition root")

	# The set of legal Step hexes for the defender, computed via the SAME
	# unchanged movement_input_controller.get_selectable_step_hexes() this
	# controller already reports for Titus (still the configured actor --
	# nothing has moved since boot).
	var expected_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(expected_hexes.size() > 0, "fixture assumption: Titus must have at least one legal Step destination at boot")

	# ── Override the REAL, composition-root-wired hex_choice_resolver field
	# (never a resolver self-wired/constructed in isolation, G2) with a
	# counting double so this test can observe "was the prompt invoked, and
	# with which legal_hexes" -- mirrors
	# tests/gut/test_hex_choice_seam_dodge_step.gd's own established
	# convention for extending/observing this EXACT seam. ────────────────
	var scripted := CountingScriptedHexChoiceResolver.new()
	instance.hex_choice_resolver = scripted

	# Drive the REAL production seam this feature wires: RoundSession's
	# _resolve_dodge_step_prompt(), invoked exactly as advance_ai_turn()'s
	# two-phase Strike branch invokes it once resolve_to_hit() reports
	# defender_stepped=true for a just-resolved Strike against `defender`.
	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	assert_eq(scripted.call_count, 1, "a successful Dodge must invoke the Step-selection prompt exactly once")
	assert_true(
		_hex_arrays_equal(scripted.received_legal_hexes, expected_hexes),
		"the prompt's offered hex set must exactly match get_selectable_step_hexes() -- no new adjacency rule introduced"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: no prompt appears when the Dodge is not successful.
# ══════════════════════════════════════════════════════════════════════════

func test_no_prompt_when_dodge_is_not_successful() -> void:
	var instance = _boot_main_scene()

	var defender = instance.round_session.current_actor()
	var scripted := CountingScriptedHexChoiceResolver.new()
	instance.hex_choice_resolver = scripted

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": false})

	assert_eq(scripted.call_count, 0, "no Step-selection prompt may appear when the Dodge did not succeed")


func test_no_prompt_when_defender_stepped_key_is_absent() -> void:
	# Defense in depth: a partial Dictionary that never even carries
	# "defender_stepped" (e.g. a miss with no active defense at all) must
	# also never prompt -- get()'s documented false default.
	var instance = _boot_main_scene()

	var defender = instance.round_session.current_actor()
	var scripted := CountingScriptedHexChoiceResolver.new()
	instance.hex_choice_resolver = scripted

	await instance.round_session._resolve_dodge_step_prompt(defender, {})

	assert_eq(scripted.call_count, 0, "an absent defender_stepped key must default to false and never prompt")


# ══════════════════════════════════════════════════════════════════════════
# G3/G4 guard: a successful Dodge with zero legal adjacent hexes must never
# prompt (no query result to offer).
# ══════════════════════════════════════════════════════════════════════════

func test_no_prompt_when_defender_has_zero_legal_step_hexes() -> void:
	var instance = _boot_main_scene()

	var defender = instance.round_session.current_actor()
	var scripted := CountingScriptedHexChoiceResolver.new()
	instance.hex_choice_resolver = scripted

	# Force the query seam to report no legal Step hexes for this defender,
	# without touching movement_input_controller's own (unmodified)
	# adjacency rule -- mirrors ResolveDodgeStepUseCase's own documented
	# "empty legal_hexes -> never prompt" guard clause.
	instance.round_session.set_step_hex_query_fn(func(_combatant_id): return [])

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	assert_eq(scripted.call_count, 0, "a successful Dodge with zero legal Step hexes must never invoke the prompt")


# ══════════════════════════════════════════════════════════════════════════
# ResolveDodgeStepUseCase in isolation (Application layer unit coverage) --
# no Godot/scene dependency at all.
# ══════════════════════════════════════════════════════════════════════════

const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")


func test_use_case_does_not_prompt_when_defender_stepped_is_false() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var calls: Array = []
	var resolver_fn := func(legal_hexes: Array):
		calls.append(legal_hexes)
		return legal_hexes[0]

	var result: Dictionary = await use_case.resolve("defender-1", false, [HexCoordClass.new(1, 0)], resolver_fn)

	assert_false(result["prompted"])
	assert_null(result["chosen_hex"])
	assert_eq(calls.size(), 0, "the resolver Callable must never be invoked when defender_stepped is false")


func test_use_case_does_not_prompt_when_legal_hexes_is_empty() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var calls: Array = []
	var resolver_fn := func(legal_hexes: Array):
		calls.append(legal_hexes)
		return null

	var result: Dictionary = await use_case.resolve("defender-1", true, [], resolver_fn)

	assert_false(result["prompted"])
	assert_null(result["chosen_hex"])
	assert_eq(calls.size(), 0, "the resolver Callable must never be invoked for an empty legal_hexes set")


func test_use_case_prompts_and_returns_the_chosen_hex_when_defender_stepped_and_legal_hexes_nonempty() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]
	var calls: Array = []
	var resolver_fn := func(hexes: Array):
		calls.append(hexes)
		return target_hex

	var result: Dictionary = await use_case.resolve("defender-1", true, legal_hexes, resolver_fn)

	assert_true(result["prompted"])
	assert_eq(result["defender_id"], "defender-1")
	assert_true(result["chosen_hex"].equals(target_hex))
	assert_eq(calls.size(), 1, "the resolver Callable must be invoked exactly once")
	assert_eq(calls[0], legal_hexes, "the resolver must be handed legal_hexes unmodified")


func test_use_case_does_not_prompt_when_resolver_callable_is_unset() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()

	var result: Dictionary = await use_case.resolve("defender-1", true, [HexCoordClass.new(1, 0)], Callable())

	assert_false(result["prompted"])
	assert_null(result["chosen_hex"])
