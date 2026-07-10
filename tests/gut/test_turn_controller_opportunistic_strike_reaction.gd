extends GutTest
## tests/gut/test_turn_controller_opportunistic_strike_reaction.gd
##
## GUT suite for iteration K FEAT-008 (US-008 / "Opportunistic Strike
## ordering, interrupt, and initiative semantics"): presentation/
## turn_controller.gd's NEW resolve_opportunistic_strike_reaction() —
## the dedicated, named integration point a Stride's OpportunisticStrike
## reaction window is driven through (see that method's own file-level
## doc for why it exists as a thin wrapper around the pre-existing
## resolve_reaction() coroutine rather than a second, parallel
## trigger-building/await path).
##
## Drives the REAL, unmodified presentation/turn_controller.gd
## TurnController and the REAL, unmodified core/application/
## reaction_window.gd ReactionWindow together (mirroring tests/gut/
## test_reaction_error_handling_and_observability.gd's established
## "real TurnController + real ReactionWindow + a scripted
## ReactionChooserPort double standing in for the human's pop-up answer"
## rig) — never calling reaction_window.open()/resume() directly as this
## suite's own proof (G2: drive the real coroutine entry point).
##
## Verifies (test_criteria):
##   1. A legal "opportunistic_strike" answer is genuinely `await`ed through
##      resolve_reaction() and resolves ok, spending the reactor's OWN
##      reaction budget via ActionEconomy.spend_reaction() (never a second,
##      parallel spend path).
##   2. The coroutine genuinely suspends on the injected chooser's choose()
##      — proven the same way test_reaction_error_handling_and_observability.gd
##      proves it: a chooser that mutates state before answering is observed
##      to have run BEFORE resolve_opportunistic_strike_reaction() returns.
##   3. configure_reactions() never having been called degrades safely
##      (ERR_NO_REACTION_WINDOW, no crash) — mirrors resolve_reaction()'s own
##      documented contract, proving the wrapper adds no new failure mode.
##   4. The built trigger's shape matches core/application/reaction_window.gd's
##      own "OpportunisticStrike" trigger_type legality gate (melee_reach
##      context) — a non-"opportunistic_strike"-only legal_reactions set
##      would signal a malformed trigger; this suite pins that only
##      "opportunistic_strike" is ever offered.

const TurnControllerClass = preload("res://presentation/turn_controller.gd")
const ReactionWindowClass = preload("res://core/application/reaction_window.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## FixedChoiceReactionChooser -- mirrors tests/gut/
## test_reaction_error_handling_and_observability.gd's identically-named
## double: always answers with a caller-supplied choice, recording the
## legal_reactions/context it was actually offered (so this suite can pin
## the trigger's real shape without reading reaction_window.gd internals
## directly).
class FixedChoiceReactionChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var _fixed_choice: String
	var calls: Array = []

	func _init(fixed_choice: String) -> void:
		_fixed_choice = fixed_choice

	func choose(legal_reactions: Array, context: Dictionary) -> String:
		calls.append({"legal_reactions": legal_reactions, "context": context})
		return _fixed_choice


func _fresh_ae():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _reactor() -> Dictionary:
	return {"name": "Titus", "combatant_id": "titus", "weapon": {"damage_die": 8}}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: a legal "opportunistic_strike" answer resolves ok and spends
# the reactor's OWN reaction via ActionEconomy.spend_reaction().
# ══════════════════════════════════════════════════════════════════════════

func test_legal_opportunistic_strike_choice_resolves_and_spends_reaction() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var chooser := FixedChoiceReactionChooser.new("opportunistic_strike")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	var ae := _fresh_ae()
	var result: Dictionary = await turn_controller.resolve_opportunistic_strike_reaction(
		_reactor(), {"melee_reach": true}, ae, 3
	)

	assert_true(result.get("ok", false), "a legal opportunistic_strike choice must resolve ok")
	assert_eq(result.get("choice", ""), "opportunistic_strike")
	assert_true(result.get("opened", false), "a genuinely eligible reactor must open a real window (never the 'opened: false' short-circuit)")
	assert_true(ae.is_spent(), "the reactor's OWN reaction budget must be spent for a taken Opportunistic Strike")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: the coroutine genuinely suspends on the injected chooser's
# choose() -- the chooser is observed to have actually run (recorded a
# call) once resolve_opportunistic_strike_reaction() returns, proving this
# is a real await, not a synchronous pass-through.
# ══════════════════════════════════════════════════════════════════════════

func test_coroutine_genuinely_awaits_the_injected_chooser() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var chooser := FixedChoiceReactionChooser.new("none")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	assert_eq(chooser.calls.size(), 0, "fixture assumption: the chooser has not been asked anything yet")

	var result: Dictionary = await turn_controller.resolve_opportunistic_strike_reaction(
		_reactor(), {"melee_reach": true}, _fresh_ae(), 1
	)

	assert_eq(chooser.calls.size(), 1, "the injected chooser must have been genuinely awaited exactly once")
	assert_eq(chooser.calls[0]["legal_reactions"], ["opportunistic_strike"], "the chooser must be offered exactly the OpportunisticStrike window's own legal_reactions set")
	assert_eq(result.get("choice", ""), "none", "a Pass answer must be reported back verbatim")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: configure_reactions() never called degrades safely.
# ══════════════════════════════════════════════════════════════════════════

func test_unconfigured_turn_controller_degrades_safely() -> void:
	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)

	var result: Dictionary = await turn_controller.resolve_opportunistic_strike_reaction(
		_reactor(), {"melee_reach": true}, null, 1
	)

	assert_false(result.get("ok", true), "an unconfigured TurnController must degrade safely rather than crash")
	assert_eq(result.get("error", ""), "ERR_NO_REACTION_WINDOW")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: the built trigger's legal_reactions is exactly
# ["opportunistic_strike"] -- pinning the OpportunisticStrike trigger shape
# this method builds internally.
# ══════════════════════════════════════════════════════════════════════════

func test_built_trigger_offers_exactly_opportunistic_strike() -> void:
	var sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(sink)
	var chooser := FixedChoiceReactionChooser.new("opportunistic_strike")

	var turn_controller := TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	await turn_controller.resolve_opportunistic_strike_reaction(_reactor(), {"melee_reach": true}, _fresh_ae(), 5)

	assert_eq(chooser.calls[0]["legal_reactions"], ["opportunistic_strike"])
	assert_eq(chooser.calls[0]["context"], {"melee_reach": true}, "the context Callable-supplied to the reactor_resolver_fn must be forwarded verbatim as attack_context")
