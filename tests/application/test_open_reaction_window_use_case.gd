extends GutTest
## tests/application/test_open_reaction_window_use_case.gd
##
## GUT suite for iteration K FEAT-004 (US-004, ADR-004):
## core/application/open_reaction_window_use_case.gd's OpenReactionWindowUseCase
## — the generalized, synchronous (no `await`) reaction-window opener that
## feeds a defender's legal reactions through an injected ReactionChooserPort.
##
## Validates (test_criteria):
##   1. An empty legal_reactions Array short-circuits to PASS WITHOUT ever
##      invoking chooser_port.choose().
##   2. The RESERVE gate (action_current - 1 < ActionEconomy.RESERVE) forces
##      PASS WITHOUT ever invoking chooser_port.choose(), even when the
##      chooser would otherwise pick a legal, worthwhile reaction.
##   3. A legal, chosen reaction is returned verbatim.
##   4. A chooser answering with an illegal choice (not in legal_reactions,
##      not PASS) is coerced to PASS (safety net).
##   5. A null chooser_port degrades to PASS without crashing.
##   6. Determinism: two calls with identical arguments return the identical
##      choice (no RNG of its own).

const OpenReactionWindowUseCaseClass = preload("res://core/application/open_reaction_window_use_case.gd")
const ReactionChooserPortClass       = preload("res://core/application/ports/reaction_chooser_port.gd")
const ActionEconomyClass             = preload("res://core/rules/action_economy.gd")


## SpyChooser — records every choose() call it receives and returns a
## pre-scripted answer; each suite in this project owns its own doubles.
class SpyChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var _answer: String
	var calls: Array = []

	func _init(answer: String) -> void:
		_answer = answer

	func choose(legal_reactions: Array, context: Dictionary) -> String:
		calls.append({"legal_reactions": legal_reactions, "context": context})
		return _answer


func _use_case():
	return OpenReactionWindowUseCaseClass.new()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — empty legal_reactions -> PASS, chooser never invoked.
# ══════════════════════════════════════════════════════════════════════════

func test_empty_legal_reactions_returns_pass_without_calling_chooser() -> void:
	var chooser := SpyChooser.new("dodge")
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, [], {"action_current": 7}, chooser
	)

	assert_eq(choice, ReactionChooserPortClass.PASS, "no legal reactions must resolve to Pass")
	assert_eq(chooser.calls.size(), 0, "chooser_port.choose() must never be invoked when there is nothing to offer")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — RESERVE gate forces Pass, chooser never invoked.
# ══════════════════════════════════════════════════════════════════════════

func test_reserve_gate_forces_pass_without_calling_chooser_even_with_one_action_remaining() -> void:
	# action_current=1 -> 1-1=0 < RESERVE(1) -> forced Pass.
	var chooser := SpyChooser.new("dodge")
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {"action_current": 1}, chooser
	)

	assert_eq(choice, ReactionChooserPortClass.PASS, "reacting down to 0 remaining actions must be forced to Pass")
	assert_eq(chooser.calls.size(), 0, "chooser_port.choose() must never be invoked once the RESERVE gate has already decided Pass")


func test_reserve_gate_is_a_noop_with_two_actions_remaining() -> void:
	# action_current=2 -> 2-1=1 >= RESERVE(1) -> gate passes; chooser is consulted.
	var chooser := SpyChooser.new("dodge")
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {"action_current": 2}, chooser
	)

	assert_eq(choice, "dodge")
	assert_eq(chooser.calls.size(), 1, "the RESERVE gate must be a no-op once action_current-1 >= RESERVE")


func test_action_current_defaults_to_max_budget_when_omitted() -> void:
	# A context with no "action_current" key must never spuriously trip the
	# RESERVE gate -- mirrors infrastructure/ai_reaction_policy.gd's own
	# documented default.
	var chooser := SpyChooser.new("dodge")
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {}, chooser
	)
	assert_eq(choice, "dodge", "omitting action_current must not trip the RESERVE gate")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — a legal, chosen reaction is returned verbatim, and the
# chooser receives legal_reactions/context verbatim.
# ══════════════════════════════════════════════════════════════════════════

func test_legal_choice_is_returned_verbatim_and_context_forwarded_unchanged() -> void:
	var chooser := SpyChooser.new("block")
	var context: Dictionary = {"action_current": 7, "hp_current": 20, "damage_raw": 10}
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_ON_HIT_MITIGATION, ["parry", "block"], context, chooser
	)

	assert_eq(choice, "block")
	assert_eq(chooser.calls.size(), 1)
	assert_eq(chooser.calls[0]["legal_reactions"], ["parry", "block"])
	assert_same(chooser.calls[0]["context"], context, "context must be forwarded to the chooser as the SAME Dictionary reference")


func test_pass_answer_is_returned_verbatim() -> void:
	var chooser := SpyChooser.new(ReactionChooserPortClass.PASS)
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {"action_current": 7}, chooser
	)
	assert_eq(choice, ReactionChooserPortClass.PASS)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — an illegal choice is coerced to Pass (safety net).
# ══════════════════════════════════════════════════════════════════════════

func test_illegal_choice_is_coerced_to_pass() -> void:
	var chooser := SpyChooser.new("steel")  # not offered
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {"action_current": 7}, chooser
	)
	assert_eq(choice, ReactionChooserPortClass.PASS, "a chosen reaction not present in legal_reactions must degrade to Pass")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — a null chooser_port degrades to Pass.
# ══════════════════════════════════════════════════════════════════════════

func test_null_chooser_port_degrades_to_pass() -> void:
	var choice: String = _use_case().open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], {"action_current": 7}, null
	)
	assert_eq(choice, ReactionChooserPortClass.PASS)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 — determinism: identical inputs -> identical outputs.
# ══════════════════════════════════════════════════════════════════════════

func test_open_is_deterministic_across_repeated_calls_with_identical_arguments() -> void:
	var context: Dictionary = {"action_current": 7, "mobility": 1, "targeted_defense_value": 10}
	var use_case := _use_case()

	var choice_a: String = use_case.open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], context, SpyChooser.new("dodge")
	)
	var choice_b: String = use_case.open(
		OpenReactionWindowUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE, ["dodge"], context, SpyChooser.new("dodge")
	)

	assert_eq(choice_a, choice_b, "identical (window_type, legal_reactions, context) must always resolve to the identical choice")
