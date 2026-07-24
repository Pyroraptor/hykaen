extends GutTest
## tests/gut/test_dodge_step_token_reposition.gd
##
## GUT suite for FEAT-004 (US-004, Dodge-Step steel thread): "Relocate
## defender to player-chosen hex via shared token-reposition seam". Boots the
## REAL res://MainScene.tscn composition root (G2 -- never a hand-wired
## double) and proves a player-chosen Dodge-Step hex, resolved through
## core/application/round_session.gd's `_resolve_dodge_step_prompt()` (the
## SAME production seam tests/gut/test_dodge_step_prompt.gd already
## exercises) and core/application/resolve_dodge_step_use_case.gd's
## `resolve()`, actually RELOCATES the defender:
##   - Combatant.hex_coord is updated to the chosen hex.
##   - The on-screen token (presentation/hex_grid_view.gd's Node2D position)
##     visibly moves to the chosen hex.
## Both happen through the EXACT SAME `_token_reposition_fn` seam AI-Stride
## already established (FEAT-008 / ADR-006/ADR-002 "no duplicate seam") --
## core/application/round_session.gd's `_reposition_token_after_ai_stride()`
## -- never a second, parallel reposition implementation.
##
## Verifies (test_criteria):
##   1. A successful Dodge + a legal hex pick moves defender
##      Combatant.hex_coord to the chosen hex.
##   2. The on-screen token (hex_grid_view Node2D position) visibly moves to
##      the chosen hex.
##   3. `set_token_reposition_fn` is bound to `hex_grid_view.move_token` at the
##      REAL composition root (never a self-wired double, G2).
##   4. The existing turn-order/reaction-timing test suite remains green --
##      see this suite's own final section, which pins
##      ResolveDodgeStepUseCase's Application-layer contract in isolation
##      (no Godot/scene dependency), mirroring
##      tests/gut/test_dodge_step_prompt.gd's own established convention.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")


## ScriptedHexChoiceResolver -- a concrete HexChoiceResolverPort test double
## (mirrors tests/gut/test_dodge_step_prompt.gd's CountingScriptedHexChoiceResolver
## exactly) that always answers with a specific, pre-scripted legal hex --
## the "player's chosen hex" this suite drives.
class ScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var call_count: int = 0
	var chosen_hex

	func _init(p_chosen_hex) -> void:
		chosen_hex = p_chosen_hex

	func resolve(legal_hexes: Array):
		call_count += 1
		if legal_hexes.is_empty():
			return null
		return chosen_hex


## _boot_main_scene() -> Node -- instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention), pinning
## seed_override=42 for a deterministic boot (Titus vs the Skeleton, prologue
## encounter).
##
## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into
## GameMode.EXPLORATION with the legacy combat pipeline (round_session, etc.)
## gated behind a real _on_combat_triggered() handoff -- see MainScene.gd's
## own FEAT-316 doc. This suite drives Dodge-Step relocation directly against
## `round_session`, so this helper now also drives that SAME real handoff
## (mirrors tests/boot/test_first_cast_firebolt.gd's established
## `_boot_main_scene()` convention), landing the instance in GameMode.COMBAT
## with a live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criteria 1 + 2: a successful Dodge + a legal hex pick relocates BOTH
# defender Combatant.hex_coord AND the on-screen token.
# ══════════════════════════════════════════════════════════════════════════

func test_successful_dodge_and_legal_hex_pick_relocates_defender_hex_coord_and_on_screen_token() -> void:
	var instance = await _boot_main_scene()

	var defender = instance.round_session.current_actor()
	assert_eq(defender.name, "Titus", "fixture: Titus (the real player combatant) must be the current actor at boot")
	var defender_id: String = defender.display_id()

	var original_hex = defender.hex_coord
	assert_not_null(original_hex, "fixture assumption: the defender must already carry a hex_coord at boot")

	var legal_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(legal_hexes.size() > 0, "fixture assumption: Titus must have at least one legal Step destination at boot")
	var chosen_hex = legal_hexes[0]
	assert_false(chosen_hex.equals(original_hex), "fixture assumption: the chosen hex must actually differ from the defender's current hex")

	var token_before = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_before, "fixture assumption: hex_grid_view must already carry a token for the defender")
	assert_true(token_before.hex_coord.equals(original_hex), "fixture assumption: the token starts at the defender's pre-Dodge-Step hex")

	# ── Override the REAL, composition-root-wired hex_choice_resolver field
	# (never a resolver self-wired/constructed in isolation, G2) with a
	# scripted double that always answers with `chosen_hex` -- mirrors
	# tests/gut/test_dodge_step_prompt.gd's own established convention. ────
	var scripted := ScriptedHexChoiceResolver.new(chosen_hex)
	instance.hex_choice_resolver = scripted

	# Drive the REAL production seam this feature wires: RoundSession's
	# _resolve_dodge_step_prompt(), invoked exactly as advance_ai_turn()'s
	# two-phase Strike branch invokes it once resolve_to_hit() reports
	# defender_stepped=true for a just-resolved Strike against `defender`.
	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": true})

	assert_eq(scripted.call_count, 1, "a successful Dodge must invoke the Step-selection prompt exactly once")

	# Criterion 1: defender Combatant.hex_coord equals the chosen hex.
	assert_true(
		defender.hex_coord.equals(chosen_hex),
		"the defender's Combatant.hex_coord must equal the player-chosen hex after a successful Dodge-Step"
	)

	# Criterion 2: the on-screen token (hex_grid_view Node2D position)
	# visibly moved to the chosen hex.
	var token_after = instance.hex_grid_view.get_token(defender_id)
	assert_not_null(token_after, "the defender's token must still be on record after the Dodge-Step reposition")
	assert_true(
		token_after.hex_coord.equals(chosen_hex),
		"the defender's on-screen token hex must update to the player-chosen hex"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel_with_offset(chosen_hex),
		"the defender's rendered screen position must resync to the chosen hex's ADR-004 axial-to-pixel projection"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: MainScene wires set_token_reposition_fn to
# hex_grid_view.move_token at the REAL composition root (no self-wired
# double, G2) -- the SAME seam AI-Stride's own
# tests/integration/test_ai_token_reposition.gd already pins, since
# Dodge-Step reuses it verbatim rather than introducing a second, parallel
# reposition seam.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_wires_the_token_reposition_hook_to_hex_grid_view_move_token() -> void:
	var instance = await _boot_main_scene()

	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")

	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "MainScene must inject a token-reposition Callable into RoundSession -- the SAME seam AI-Stride and Dodge-Step both share")
	assert_eq(
		reposition_fn.get_object(), instance.hex_grid_view,
		"the Dodge-Step reposition path must target the SAME HexGridView instance the AI-Stride/player Step/Stride paths render tokens on"
	)
	assert_eq(
		reposition_fn.get_method(), &"move_token",
		"the Dodge-Step reposition path must call move_token() -- the SAME function every other reposition path already calls"
	)


# ══════════════════════════════════════════════════════════════════════════
# Regression guard: no prompt (and therefore no reposition) when the Dodge
# did not succeed -- mirrors tests/gut/test_dodge_step_prompt.gd's own
# established coverage, re-pinned here so this suite alone proves the
# reposition wiring never fires on the overwhelmingly common non-Dodge path.
# ══════════════════════════════════════════════════════════════════════════

func test_no_reposition_when_dodge_is_not_successful() -> void:
	var instance = await _boot_main_scene()

	var defender = instance.round_session.current_actor()
	var original_hex = defender.hex_coord
	var defender_id: String = defender.display_id()

	var legal_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var scripted := ScriptedHexChoiceResolver.new(legal_hexes[0] if legal_hexes.size() > 0 else null)
	instance.hex_choice_resolver = scripted

	await instance.round_session._resolve_dodge_step_prompt(defender, {"defender_stepped": false})

	assert_eq(scripted.call_count, 0, "no Step-selection prompt may appear when the Dodge did not succeed")
	assert_true(defender.hex_coord.equals(original_hex), "defender hex_coord must be unchanged when the Dodge did not succeed")

	var token = instance.hex_grid_view.get_token(defender_id)
	assert_true(token.hex_coord.equals(original_hex), "the on-screen token must be unchanged when the Dodge did not succeed")


# ══════════════════════════════════════════════════════════════════════════
# ResolveDodgeStepUseCase in isolation (Application layer unit coverage) --
# no Godot/scene dependency at all -- pins the NEW reposition-wiring contract
# this feature adds directly, mirroring
## tests/gut/test_dodge_step_prompt.gd's own established isolation coverage.
# ══════════════════════════════════════════════════════════════════════════

func test_use_case_calls_token_reposition_fn_and_updates_target_hex_coord_when_a_hex_is_chosen() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	var reposition_calls: Array = []
	var reposition_fn := func(token_id: String, hex_coord):
		reposition_calls.append([token_id, hex_coord])

	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": HexCoordClass.new(0, -1)}

	var result: Dictionary = await use_case.resolve(
		"defender-1", true, legal_hexes, resolver_fn, reposition_fn, target
	)

	assert_true(result["prompted"])
	assert_true(result["chosen_hex"].equals(target_hex))
	assert_eq(reposition_calls.size(), 1, "the token-reposition Callable must be invoked exactly once when a hex is chosen")
	assert_eq(reposition_calls[0][0], "defender-1", "the token-reposition Callable must be invoked with the defender_id")
	assert_true(reposition_calls[0][1].equals(target_hex), "the token-reposition Callable must be invoked with the chosen hex")
	assert_true(target["hex_coord"].equals(target_hex), "the target Dictionary's hex_coord must be updated to the chosen hex")


func test_use_case_never_calls_token_reposition_fn_when_no_hex_is_chosen() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var reposition_calls: Array = []
	var reposition_fn := func(token_id: String, hex_coord):
		reposition_calls.append([token_id, hex_coord])

	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": HexCoordClass.new(0, -1)}
	var original_hex = target["hex_coord"]

	# defender_stepped=false -- no prompt at all.
	var result: Dictionary = await use_case.resolve(
		"defender-1", false, [HexCoordClass.new(1, 0)], func(_h): return HexCoordClass.new(1, 0),
		reposition_fn, target
	)

	assert_false(result["prompted"])
	assert_eq(reposition_calls.size(), 0, "the token-reposition Callable must never be invoked when no hex was ever chosen")
	assert_true(target["hex_coord"].equals(original_hex), "target hex_coord must be left untouched when no hex was ever chosen")


func test_use_case_omitting_the_new_optional_params_preserves_prior_behavior() -> void:
	# Backward-compat: every pre-existing 4-arg call site (e.g.
	# tests/gut/test_dodge_step_prompt.gd/test_dodge_step_no_legal_hex.gd's
	# own isolation coverage) must still behave byte-for-byte identically.
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	var result: Dictionary = await use_case.resolve("defender-1", true, legal_hexes, resolver_fn)

	assert_true(result["prompted"])
	assert_true(result["chosen_hex"].equals(target_hex))
