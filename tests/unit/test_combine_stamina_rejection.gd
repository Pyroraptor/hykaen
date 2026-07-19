extends GutTest
## tests/unit/test_combine_stamina_rejection.gd — FEAT-003 (US-003; FR-002;
## ADR-004)
##
## Iteration N (Combinations): rejects a Combine execute() call when the
## acting Combatant has insufficient Stamina, routing the rejection through
## the EXISTING core/rules/action_economy.gd ActionEconomy.combine_actions()
## Stamina>=1 check (ADR-004) -- no parallel/duplicate Stamina comparison is
## authored in presentation/combine_action_controller.gd itself.
##
## Builds on FEAT-002 (tests/unit/test_combine_stamina_decrement.gd), which
## proved a VALID Combine execute() call drains exactly one Stamina via
## Combatant.spend_stamina(). This feature adds the missing precondition
## gate in front of that spend: when action_economy.combine_actions()
## reports failure (stamina_pool < 1), execute() must short-circuit BEFORE
## any spend_stamina() call, returning a structured ExecutionResult
## {ok: false, reason: "VALIDATION_FAILED"} (design notes' api_contracts
## #3 failure-mode list) rather than crashing or silently decrementing
## below zero.
##
## test_criteria covered:
##   1. A combatant with stamina=0 calling execute() returns
##      ExecutionResult.ok == false with reason VALIDATION_FAILED, and
##      stamina remains 0 (no decrement).
##   2. Regression test confirms only one Stamina-check code path exists:
##      action_economy.combine_actions() is the SOLE caller site of the
##      Stamina check within combine_action_controller.gd (grep/reflection
##      -based static scan -- no second/ad-hoc stamina comparison).

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const RoundSessionHolderClass      = preload("res://infrastructure/round_session_holder.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")


## FakeSession — mirrors tests/unit/test_combine_stamina_decrement.gd's
## established minimal double satisfying the current_actor()/
## current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's base class reads through the
## injected session_holder.
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


## SpyCombatant — mirrors test_combine_stamina_decrement.gd's Spy convention:
## a real Combatant that additionally counts spend_stamina() calls, so a
## rejected (insufficient-Stamina) execute() call can be proven to never
## reach the mutator at all.
class SpyCombatant:
	extends "res://core/domain/combatant.gd"

	var spend_stamina_call_count: int = 0

	func spend_stamina(amount: int = 1) -> void:
		spend_stamina_call_count += 1
		super.spend_stamina(amount)


func _deps(actor = null) -> Dictionary:
	var holder := RoundSessionHolderClass.new()
	if actor != null:
		holder.set_current(FakeSession.new(actor))
	return {"session_holder": holder}


func _make_actor(starting_stamina: int) -> SpyCombatant:
	var actor := SpyCombatant.new("player_0", "Titus", "Player", HexCoordClass.new(0, 0))
	actor.stamina = starting_stamina
	return actor


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a Combatant with stamina=0 calling execute() is rejected:
# ok == false, reason == VALIDATION_FAILED, stamina remains 0 (no decrement).
# ══════════════════════════════════════════════════════════════════════════

func test_execute_with_zero_stamina_returns_ok_false_reason_validation_failed() -> void:
	var actor := _make_actor(0)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.execute(null)

	assert_false(result.get("ok", true), "execute() with stamina=0 must report ok=false")
	assert_eq(
		result.get("reason"), "VALIDATION_FAILED",
		"execute() with stamina=0 must report reason=VALIDATION_FAILED"
	)


func test_execute_with_zero_stamina_does_not_decrement_stamina() -> void:
	var actor := _make_actor(0)
	var controller := CombineActionControllerClass.new(_deps(actor))

	controller.execute(null)

	assert_eq(actor.stamina, 0, "a rejected Combine execute() call must leave stamina at 0 -- no decrement")


func test_execute_with_zero_stamina_never_calls_spend_stamina() -> void:
	var actor := _make_actor(0)
	var controller := CombineActionControllerClass.new(_deps(actor))

	controller.execute(null)

	assert_eq(
		actor.spend_stamina_call_count, 0,
		"a rejected (insufficient-Stamina) Combine execute() call must never reach Combatant.spend_stamina()"
	)


func test_execute_with_negative_stamina_is_also_rejected() -> void:
	# Defensive: a combatant that somehow already sits below zero (e.g. from
	# an unrelated prior mutator) must still be rejected, not further
	# decremented.
	var actor := _make_actor(-1)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.execute(null)

	assert_false(result.get("ok", true), "execute() with negative stamina must report ok=false")
	assert_eq(actor.stamina, -1, "a rejected Combine execute() call must not further decrement an already-negative stamina")


# ══════════════════════════════════════════════════════════════════════════
# Sanity check — a combatant with sufficient Stamina (>=1) is unaffected by
# this feature's new gate: execute() still succeeds and still spends exactly
# one Stamina, exactly as FEAT-002 established.
# ══════════════════════════════════════════════════════════════════════════

func test_execute_with_sufficient_stamina_still_succeeds_and_spends_one() -> void:
	var actor := _make_actor(1)
	var controller := CombineActionControllerClass.new(_deps(actor))

	var result: Dictionary = controller.execute(null)

	assert_true(result.get("ok", false), "execute() with stamina>=1 must still report ok=true")
	assert_eq(actor.stamina, 0, "execute() with stamina=1 must still spend exactly one Stamina, landing at 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — regression/reflection: action_economy.combine_actions() is
# the SOLE Stamina-check code path within combine_action_controller.gd --
# no parallel/duplicate ad-hoc stamina comparison exists in the file.
# ══════════════════════════════════════════════════════════════════════════

func _read_combine_controller_text() -> String:
	var f := FileAccess.open("res://presentation/combine_action_controller.gd", FileAccess.READ)
	assert_not_null(f, "presentation/combine_action_controller.gd must exist and be readable")
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _non_comment_code_text(contents) -> String -- strips every full-line
## comment (mirrors tests/unit/test_combine_action_controller_registration.gd's
## established helper) so explanatory doc-comment prose mentioning
## "combine_actions" or "stamina" in passing never trips this scan -- only
## actual CODE tokens count.
func _non_comment_code_text(contents: String) -> String:
	var code_lines: PackedStringArray = []
	for line in contents.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	return "\n".join(code_lines)


func test_combine_actions_is_the_sole_stamina_check_call_site() -> void:
	var code: String = _non_comment_code_text(_read_combine_controller_text())

	var call_count: int = code.count("combine_actions(")
	assert_eq(
		call_count, 1,
		"combine_action_controller.gd must call action_economy.combine_actions() exactly once -- the sole Stamina-check code path"
	)


func test_no_parallel_ad_hoc_stamina_comparison_exists() -> void:
	var code: String = _non_comment_code_text(_read_combine_controller_text())

	# No second/duplicate hand-rolled comparison against `.stamina` (e.g.
	# `actor.stamina < 1` / `actor.stamina >= 1`) may exist alongside the
	# single combine_actions() call -- the Stamina>=1 gate must be checked
	# in exactly ONE place (core/rules/action_economy.gd), never re-derived
	# here.
	var forbidden_patterns: Array = [
		"stamina <", "stamina<", "stamina >=", "stamina>=",
		"stamina <=", "stamina<=", "stamina >", "stamina>", "stamina ==", "stamina==",
	]
	for pattern in forbidden_patterns:
		assert_false(
			code.contains(pattern),
			"combine_action_controller.gd must not contain an ad-hoc stamina comparison ('%s') -- route the Stamina check exclusively through action_economy.combine_actions()" % pattern
		)
