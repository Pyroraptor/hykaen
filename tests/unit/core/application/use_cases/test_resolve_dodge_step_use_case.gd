extends GutTest
## tests/unit/core/application/use_cases/test_resolve_dodge_step_use_case.gd
##
## GUT test suite for FEAT-226 (US-005, FR-004, resolves FIND-221/FIND-222):
## "Guard illegal hex choice and silent token-move no-op in dodge-step
## path". Application-layer unit coverage (no Godot/scene dependency) of
## core/application/resolve_dodge_step_use_case.gd's ResolveDodgeStepUseCase
## — complements (never duplicates) tests/gut/test_dodge_step_prompt.gd's and
## tests/gut/test_dodge_step_token_reposition.gd's own isolation coverage of
## this SAME class's pre-existing contract.
##
## Verifies (test_criteria):
##   1. test_illegal_hex_choice_raises_guard_and_does_not_mutate_hex_coord --
##      a hex_choice_resolver_fn that answers with a hex NOT present in
##      legal_hexes must never mutate Combatant.hex_coord (target dictionary)
##      nor invoke token_reposition_fn, and the returned Dictionary must
##      surface "error": "ILLEGAL_HEX_CHOICE".
##   2. test_legal_hex_choice_still_applies_normally (regression) -- a hex
##      choice that IS a member of legal_hexes must continue to reposition
##      the token and mutate Combatant.hex_coord exactly as before, with
##      "error": null.
##   3. test_resolve_dodge_step_use_case_surfaces_token_not_found_error -- a
##      token_reposition_fn that explicitly returns `false` (mirroring
##      presentation/hex_grid_view.gd's move_token() TOKEN_NOT_FOUND
##      contract) must stop the use case BEFORE it mutates
##      Combatant.hex_coord, and the returned Dictionary must surface
##      "error": "TOKEN_NOT_FOUND".

const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: ILLEGAL_HEX_CHOICE guard.
# ══════════════════════════════════════════════════════════════════════════

func test_illegal_hex_choice_raises_guard_and_does_not_mutate_hex_coord() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()

	var legal_hexes: Array = [HexCoordClass.new(1, 0), HexCoordClass.new(0, 1)]
	var illegal_hex := HexCoordClass.new(9, 9)  # deliberately NOT in legal_hexes
	var resolver_fn := func(_hexes: Array):
		return illegal_hex

	var reposition_calls: Array = []
	var reposition_fn := func(token_id: String, hex_coord):
		reposition_calls.append([token_id, hex_coord])
		return true

	var original_hex := HexCoordClass.new(0, 0)
	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": original_hex}

	var result: Dictionary = await use_case.resolve(
		"defender-1", true, legal_hexes, resolver_fn, reposition_fn, target
	)

	assert_eq(result.get("error"), "ILLEGAL_HEX_CHOICE", "an out-of-legal-set hex choice must surface the ILLEGAL_HEX_CHOICE guard")
	assert_null(result["chosen_hex"], "an illegal hex choice must never be reported as the effective chosen_hex")
	assert_eq(reposition_calls.size(), 0, "token_reposition_fn must never be invoked for an illegal hex choice")
	assert_true(target["hex_coord"].equals(original_hex), "Combatant.hex_coord must be left completely untouched for an illegal hex choice")


func test_illegal_hex_choice_guard_fires_even_with_no_reposition_fn_or_target_wired() -> void:
	# Defense in depth: the guard must trip on the resolver's answer alone,
	# independent of whether the optional FEAT-004 params are even supplied.
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var legal_hexes: Array = [HexCoordClass.new(1, 0)]
	var illegal_hex := HexCoordClass.new(5, -5)
	var resolver_fn := func(_hexes: Array):
		return illegal_hex

	var result: Dictionary = await use_case.resolve("defender-1", true, legal_hexes, resolver_fn)

	assert_eq(result.get("error"), "ILLEGAL_HEX_CHOICE")
	assert_null(result["chosen_hex"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (regression): a LEGAL hex choice still applies normally.
# ══════════════════════════════════════════════════════════════════════════

func test_legal_hex_choice_still_applies_normally() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()

	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	var reposition_calls: Array = []
	var reposition_fn := func(token_id: String, hex_coord):
		reposition_calls.append([token_id, hex_coord])
		return true

	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": HexCoordClass.new(0, -1)}

	var result: Dictionary = await use_case.resolve(
		"defender-1", true, legal_hexes, resolver_fn, reposition_fn, target
	)

	assert_null(result.get("error"), "a legal hex choice must never surface an error")
	assert_true(result["prompted"])
	assert_true(result["chosen_hex"].equals(target_hex))
	assert_eq(reposition_calls.size(), 1, "token_reposition_fn must be invoked exactly once for a legal hex choice")
	assert_eq(reposition_calls[0][0], "defender-1")
	assert_true(reposition_calls[0][1].equals(target_hex))
	assert_true(target["hex_coord"].equals(target_hex), "Combatant.hex_coord must update to the legally-chosen hex")


func test_legal_hex_choice_with_no_reposition_fn_or_target_preserves_prior_behavior() -> void:
	# Backward-compat: every pre-existing 4-arg call site must still behave
	# byte-for-byte identically, now also carrying "error": null.
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	var result: Dictionary = await use_case.resolve("defender-1", true, legal_hexes, resolver_fn)

	assert_true(result["prompted"])
	assert_true(result["chosen_hex"].equals(target_hex))
	assert_null(result.get("error"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: TOKEN_NOT_FOUND guard.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_dodge_step_use_case_surfaces_token_not_found_error() -> void:
	var use_case := ResolveDodgeStepUseCaseClass.new()

	var target_hex := HexCoordClass.new(1, 0)
	var legal_hexes: Array = [target_hex]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	# Mirrors presentation/hex_grid_view.gd's move_token() TOKEN_NOT_FOUND
	# contract: an explicit `false` return for an unknown combatant_id.
	var reposition_fn := func(_token_id: String, _hex_coord):
		return false

	var original_hex := HexCoordClass.new(0, 0)
	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": original_hex}

	var result: Dictionary = await use_case.resolve(
		"defender-1", true, legal_hexes, resolver_fn, reposition_fn, target
	)

	assert_eq(result.get("error"), "TOKEN_NOT_FOUND", "a token_reposition_fn reporting TOKEN_NOT_FOUND must surface that error")
	assert_true(target["hex_coord"].equals(original_hex), "Combatant.hex_coord must NOT be mutated when the on-screen token was never actually found/moved")


func test_token_reposition_fn_returning_void_is_still_treated_as_success() -> void:
	# Backward compat: every pre-FEAT-226 token_reposition_fn test double
	# (e.g. tests/gut/test_dodge_step_token_reposition.gd's own coverage)
	# returns nothing (void/null) -- that must NOT be misread as
	# TOKEN_NOT_FOUND; only an explicit `false` trips the guard.
	var use_case := ResolveDodgeStepUseCaseClass.new()
	var target_hex := HexCoordClass.new(2, -1)
	var legal_hexes: Array = [target_hex, HexCoordClass.new(0, 0)]
	var resolver_fn := func(_hexes: Array):
		return target_hex

	var reposition_calls: Array = []
	var reposition_fn := func(token_id: String, hex_coord):
		reposition_calls.append([token_id, hex_coord])
		# deliberately no return statement -- implicit null/void

	var target: Dictionary = {"combatant_id": "defender-1", "hex_coord": HexCoordClass.new(0, -1)}

	var result: Dictionary = await use_case.resolve(
		"defender-1", true, legal_hexes, resolver_fn, reposition_fn, target
	)

	assert_null(result.get("error"), "a void-returning token_reposition_fn must be treated as success, not TOKEN_NOT_FOUND")
	assert_true(target["hex_coord"].equals(target_hex), "Combatant.hex_coord must still update when token_reposition_fn returns void (success)")
