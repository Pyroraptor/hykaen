extends GutTest
## tests/integration/test_multi_round_loop.gd
##
## GUT test suite for FEAT-006 (US-004/FR-004, ADR-012): multi-round
## automatic continuation -- the first demoable slice of the steel thread's
## exit point, "a combat round runs end-to-end without hanging, including
## across multiple undecided rounds."
##
## Three changes land together:
##   1. core/application/round_session.gd's finish() now resets every
##      combatant's ActionEconomy budget_remaining back to 7 ONLY when this
##      round's own outcome is still undecided (outcome() == "") -- a
##      decided ('won'/'lost') outcome leaves budgets untouched (the
##      encounter is over; there is nothing left to reset for).
##   2. MainScene.gd's ROUND_NUMBER is now a runtime `var` (previously a
##      `const` fixed at 1) -- MainScene._on_round_over() increments it by
##      exactly one every time a round concludes undecided.
##   3. MainScene.gd's rewire_session() is the SINGLE reusable
##      composition-root method that obtains a fresh RoundSession
##      (RunRoundUseCase.begin_round()), wires its AI-Stride token-
##      reposition hook, and hands it to TurnController.set_session() --
##      invoked both by _ready() (startup, ROUND_NUMBER == 1) and by
##      _on_round_over() (round continuation), with no second/duplicated
##      copy of that wiring anywhere in the file.
##
## Verifies (test_criteria):
##   1. round_session.finish() resets every combatant's ActionEconomy budget
##      to 7 on outcome=='' (undecided), and does NOT reset it on a decided
##      outcome.
##   2. ROUND_NUMBER is a runtime var on MainScene, incremented on round
##      continuation.
##   3. rewire_session() is the single reusable rewiring method -- invoked
##      both at startup and on continuation, with no duplicated wiring code
##      (static source inspection).
##   4. A decided outcome still routes to ResultScreenView and starts no
##      further round (ROUND_NUMBER stays put).
##   5. Multi-round headless E2E: round 1 (undecided) -> round 2 (decided),
##      driven entirely through the real MainScene/TurnController/
##      EndTurnControl composition root, without the 1000-turn last-resort
##      guard ever needing to trip (a tiny, bounded loop guard on the test's
##      own drive loop stands in for "never hangs").

const RoundSessionClass            = preload("res://core/application/round_session.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")


# ── Fake/double port implementations (mirrors tests/integration/test_ai_token_reposition.gd) ──

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


## FakeAIDecisionPort — always issues a Strike against the first living
## target in `targets` (never Stride/WAIT) -- deterministic actor selection,
## isolating this suite's determinism entirely in ConstantRandomNumberPort
## below rather than in any positional/reach reasoning.
class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(combatant, targets: Array) -> Dictionary:
		for target in targets:
			if target.hp_current > 0:
				return {"action_type": "Strike", "target": target}
		return {"action_type": "", "target": {}}


## ConstantRandomNumberPort — returns the SAME scripted int for every roll()
## call regardless of dice_spec, so hit/miss/damage-magnitude is fully
## controlled by the combatant's "ac" fixture value (a raw d20 of, say, 1
## against ac=100 always misses; the same roll of 1 against ac=-100 always
## hits, and (with any 0 attribute modifier) always crits) -- no dependency
## on call ordering/count, unlike a scripted-sequence double.
class ConstantRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _value: int

	func _init(value: int) -> void:
		_value = value

	func roll(_dice_spec: Dictionary) -> int:
		return _value


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _weapon() -> Dictionary:
	return {"damage_modifier_attribute": "strength", "proficiency_bonus": 0, "damage_die": 6}


## _hero()/_golem() — a minimal, adjacent-hex 1v1 fixture (no reliance on the
## prologue encounter's own Titus/Skeleton stats or seed-dependent
## initiative) used throughout this suite. Both start unhittable (ac=100)
## against a scripted roll of 1 -- guaranteeing every Strike in round 1
## misses regardless of RNG concerns -- until a test explicitly lowers one
## side's `ac` (and/or `hp_current`) to force a decisive hit.
func _hero():
	return CombatantClass.from_dict({
		"name": "Hero", "combatant_id": "hero", "hp_current": 50, "hp_max": 50,
		"ac": 100, "strength": 0, "hex_coord": HexCoordClass.new(0, 0),
		"_is_enemy": false, "weapon": _weapon(),
	})


func _golem():
	return CombatantClass.from_dict({
		"name": "Golem", "combatant_id": "golem", "hp_current": 1, "hp_max": 1,
		"ac": 100, "strength": 0, "hex_coord": HexCoordClass.new(1, 0),
		"_is_enemy": true, "weapon": _weapon(),
	})


## FEAT-006 (US-005/FR-005, ADR-002): MainScene now wires RoundSession's
## enemy-strikes-player reaction window to the REAL, blocking
## TurnController.resolve_reaction() -> PlayerReactionChooser ->
## $ReactionPromptUI chain (MainScene.gd's rewire_session()), which has "no
## auto-timeout" by design (scenes/ui/reaction_prompt_ui.gd) and suspends
## until an actual player clicks an option. This suite drives Golem's AI
## Strikes against Hero headlessly with no player present, so it swaps the
## injected ReactionChooserPort for infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser("pass") immediately after boot -- the SAME headless
## double every other reaction-system suite already uses -- via
## TurnController.configure_reactions()'s own documented "safe to call any
## number of times" contract. This reproduces the exact pre-FEAT-006
## "none"/PASS default this suite's assertions were written against, never a
## new production behavior; the REAL PlayerReactionChooser is still what
## MainScene.gd wires for an actual player session. `_wire_synthetic_fixture()`
## below re-invokes rewire_session() for its own synthetic rig, but never
## touches turn_controller._reaction_chooser, so this swap stays in effect.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 1
	add_child_autofree(instance)
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _wire_synthetic_fixture(instance, hero, golem) -> void — replaces the real
## MainScene's prologue-encounter pipeline (`_party`/`_enemies`/
## `resolve_action_use_case`/`run_round_use_case`) with a fully-controlled
## synthetic 1v1 rig, THEN drives MainScene's own `rewire_session()` (the
## SAME single reusable method _ready() already called at boot) to obtain
## round 1's RoundSession over that rig -- exercising the real composition-
## root wiring (TurnController/EndTurnControl/VerbBarView/`_verb_registry`)
## against fully deterministic combatants, rather than the prologue
## encounter's own randomized/seed-sensitive Titus-vs-Skeleton fight.
func _wire_synthetic_fixture(instance, hero, golem) -> void:
	var entries: Array = [_entry(hero), _entry(golem)]
	var turn_order_port = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()
	var rng_port = ConstantRandomNumberPort.new(1)

	instance._party = [hero]
	instance._enemies = [golem]
	instance.round_history_port = round_history_port
	instance.resolve_action_use_case = ResolveActionUseCaseClass.new(rng_port, instance.event_sink, round_history_port)
	instance.determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	instance.run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, instance.event_sink, round_history_port, FakeAIDecisionPort.new(),
		instance.resolve_action_use_case, instance.determine_outcome_use_case
	)

	instance.rewire_session()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: round_session.finish() resets every combatant's ActionEconomy
# budget to 7 on outcome=='' (undecided), and does NOT reset it on a decided
# outcome.
# ══════════════════════════════════════════════════════════════════════════

func _make_use_case(entries: Array, rng_value: int) -> Dictionary:
	var turn_order_port = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()
	var event_sink_port = FakeEventSinkPort.new()
	var rng_port = ConstantRandomNumberPort.new(rng_value)
	var resolve_action_use_case = ResolveActionUseCaseClass.new(rng_port, event_sink_port, round_history_port)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)
	return {
		"use_case": run_round_use_case,
		"resolve_action_use_case": resolve_action_use_case,
		"event_sink": event_sink_port,
	}


func test_finish_resets_budgets_to_max_on_undecided_outcome() -> void:
	var alpha = CombatantClass.from_dict({"name": "Alpha", "hp_current": 20, "ac": 100, "strength": 0, "weapon": _weapon()})
	var bravo = CombatantClass.from_dict({"name": "Bravo", "hp_current": 20, "ac": 100, "strength": 0, "weapon": _weapon()})
	var entries: Array = [_entry(alpha), _entry(bravo)]

	var rig: Dictionary = _make_use_case(entries, 1)  # scripted miss (roll 1 vs ac 100)
	var session = rig["use_case"].begin_round(1, [alpha], [bravo])

	var resolve_result: Dictionary = rig["resolve_action_use_case"].resolve(
		alpha, entries[0]["action_economy"], bravo, "Strike", 1, 0
	)
	assert_true(resolve_result.get("resolved", false))
	assert_false(resolve_result.get("target_defeated", true), "fixture assumption: ac=100 vs a scripted roll of 1 must miss")
	assert_eq(entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET - 1)

	var result: Dictionary = session.finish()

	assert_eq(result.get("outcome", "MISSING"), "", "fixture assumption: nobody died -- this round's outcome must be undecided")
	assert_eq(
		entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"finish() must reset every combatant's ActionEconomy budget to MAX_BUDGET (7) when outcome=='' (undecided)"
	)
	assert_eq(entries[1]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET)
	assert_false(entries[0]["action_economy"].is_spent())


func test_finish_does_not_reset_budgets_on_decided_outcome() -> void:
	var lethal = CombatantClass.from_dict({"name": "Lethal", "hp_current": 20, "ac": -100, "strength": 0, "weapon": _weapon()})
	var fragile = CombatantClass.from_dict({"name": "Fragile", "hp_current": 1, "ac": -100, "strength": 0, "weapon": _weapon()})
	var entries: Array = [_entry(lethal), _entry(fragile)]

	var rig: Dictionary = _make_use_case(entries, 20)  # scripted hit+crit (roll 20 vs ac -100)
	var session = rig["use_case"].begin_round(1, [lethal], [fragile])

	var resolve_result: Dictionary = rig["resolve_action_use_case"].resolve(
		lethal, entries[0]["action_economy"], fragile, "Strike", 1, 0
	)
	assert_true(resolve_result.get("resolved", false))
	assert_true(fragile.hp_current <= 0, "fixture assumption: Fragile must die to this scripted Strike")

	var end_result: Dictionary = session.end_current_turn()
	assert_eq(end_result.get("outcome", "MISSING"), "won")
	assert_true(session.is_round_over())

	var remaining_before_finish: int = entries[0]["action_economy"].get_remaining()
	assert_ne(remaining_before_finish, ActionEconomyClass.MAX_BUDGET, "fixture assumption: Lethal must have already spent its one Strike's action")

	var result: Dictionary = session.finish()

	assert_eq(result.get("outcome", "MISSING"), "won")
	assert_eq(
		entries[0]["action_economy"].get_remaining(), remaining_before_finish,
		"finish() must NOT reset ActionEconomy budgets on a DECIDED ('won') outcome"
	)
	assert_ne(
		entries[0]["action_economy"].get_remaining(), ActionEconomyClass.MAX_BUDGET,
		"a decided round's finish() must never leave a combatant's budget back at MAX_BUDGET"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: ROUND_NUMBER is a runtime var on MainScene (a `const` would
# make this assignment a compile-time error).
# ══════════════════════════════════════════════════════════════════════════

func test_round_number_is_a_mutable_runtime_var() -> void:
	var instance = _boot_main_scene()

	assert_eq(instance.ROUND_NUMBER, 1, "ROUND_NUMBER must start at 1, exactly as the pre-FEAT-006 constant did")

	instance.ROUND_NUMBER = 41
	assert_eq(instance.ROUND_NUMBER, 41, "ROUND_NUMBER must be reassignable -- a runtime var, not a const")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: rewire_session() is the single reusable rewiring method --
# invoked both at startup and on continuation, with no duplicated wiring
# code (static source inspection, mirroring test_ai_token_reposition.gd's
# single-move_token()-definition check).
# ══════════════════════════════════════════════════════════════════════════

func test_rewire_session_is_the_single_reusable_composition_root_rewiring_method() -> void:
	var source: String = _read_file("res://MainScene.gd")

	assert_eq(
		source.count("func rewire_session("), 1,
		"exactly one rewire_session() method must be defined -- the single reusable composition-root rewiring seam"
	)
	assert_eq(
		source.count("run_round_use_case.begin_round("), 1,
		"RunRoundUseCase.begin_round() must be called from exactly one call site (inside rewire_session()) -- never duplicated in _ready()/_on_round_over()"
	)

	var ready_start: int = source.find("func _ready(")
	var ready_end: int = source.find("\nfunc ", ready_start + 1)
	var ready_body: String = source.substr(ready_start, ready_end - ready_start)
	assert_true(ready_body.contains("rewire_session()"), "_ready() must invoke rewire_session() to obtain the startup round session")

	var on_round_over_start: int = source.find("func _on_round_over(")
	assert_true(on_round_over_start >= 0, "MainScene must define _on_round_over()")
	var on_round_over_end: int = source.find("\nfunc ", on_round_over_start + 1)
	var on_round_over_body: String = source.substr(on_round_over_start, on_round_over_end - on_round_over_start)

	assert_true(
		on_round_over_body.contains("rewire_session()"),
		"_on_round_over() must call rewire_session() to continue into the next round"
	)
	assert_false(
		on_round_over_body.contains("run_round_use_case.begin_round("),
		"_on_round_over() must not directly call begin_round() -- that wiring belongs solely inside rewire_session()"
	)
	assert_false(
		on_round_over_body.contains("set_token_reposition_fn"),
		"_on_round_over() must not directly re-wire the token-reposition hook -- that wiring belongs solely inside rewire_session()"
	)


func test_rewire_session_wires_token_reposition_and_turn_controller_for_a_fresh_round() -> void:
	var instance = _boot_main_scene()
	var hero = _hero()
	var golem = _golem()
	_wire_synthetic_fixture(instance, hero, golem)

	assert_not_null(instance.round_session, "rewire_session() must assign a real RoundSession")
	assert_is(instance.round_session, RoundSessionClass)

	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "rewire_session() must wire the AI-Stride token-reposition hook")
	assert_eq(reposition_fn.get_object(), instance.hex_grid_view)
	assert_eq(reposition_fn.get_method(), &"move_token")

	assert_false(instance.round_session.current_actor().is_enemy, "Hero (party) must act first in this synthetic fixture")
	assert_true(instance.end_turn_control.is_enabled(), "rewire_session() must hand the new session to TurnController.set_session(), which configures EndTurnControl")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: a decided outcome still routes to ResultScreenView and starts
# no further round.
# ══════════════════════════════════════════════════════════════════════════

func test_decided_outcome_routes_to_result_screen_view_and_starts_no_new_round() -> void:
	var instance = _boot_main_scene()
	var hero = _hero()
	hero.ac = -100
	hero.hp_current = 1
	var golem = _golem()
	_wire_synthetic_fixture(instance, hero, golem)

	assert_false(instance.result_screen_view.is_shown(), "fixture assumption: no result yet before any turn is taken")

	instance._verb_registry.execute("STRIKE", "golem")
	instance.end_turn_control.press()

	assert_true(instance.round_session.is_round_over())
	assert_eq(
		instance.round_session.outcome(), "lost",
		"fixture: Golem's guaranteed-hit, guaranteed-crit AI counter-Strike must decide the encounter against Hero"
	)
	assert_eq(instance.ROUND_NUMBER, 1, "a decided outcome must NOT increment ROUND_NUMBER / start a new round")
	assert_true(instance.result_screen_view.is_shown(), "a decided outcome must still route to ResultScreenView")

	var result_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1)
	assert_eq(result_events[0].outcome, "lost")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: multi-round headless E2E -- round 1 (undecided, natural
# full-budget exhaustion) -> round 2 (decided), driven entirely through the
# real MainScene/TurnController/EndTurnControl composition root, without
# ever needing anywhere near TurnController's 1000-turn last-resort guard.
# ══════════════════════════════════════════════════════════════════════════

func test_multi_round_loop_round_one_undecided_continues_into_round_two_decided() -> void:
	var instance = _boot_main_scene()
	var hero = _hero()
	var golem = _golem()
	_wire_synthetic_fixture(instance, hero, golem)

	assert_eq(instance.ROUND_NUMBER, 1, "fixture setup: the synthetic rig must start on round 1")

	var made_lethal: bool = false
	var guard: int = 0
	# A tiny, bounded drive loop (guard < 20) stands in for "this must never
	# hang" -- with 7 actions per combatant per round, round 1 concludes
	# within 7 iterations and round 2's first Strike concludes it, so this
	# loop is expected to exit within ~8 iterations, nowhere near the bound,
	# and nowhere near TurnController's own separate 1000-Enemy-turn guard.
	while not instance.round_session.is_round_over() and guard < 20:
		guard += 1

		if instance.ROUND_NUMBER == 2 and not made_lethal:
			# Round 1 concluded undecided (both sides exhausted their 7-action
			# budget against each other's unhittable ac=100, per the fixture's
			# doc) -- now make Hero's counter-Strike lethal against Golem's
			# next AI turn so round 2 concludes decisively.
			hero.ac = -100
			hero.hp_current = 1
			made_lethal = true

		if not instance.round_session.current_actor().is_enemy:
			instance._verb_registry.execute("STRIKE", "golem")
		instance.end_turn_control.press()

	assert_true(guard < 20, "the round(s) must conclude within the bounded drive loop -- never hang")
	assert_true(instance.round_session.is_round_over())

	assert_eq(
		instance.ROUND_NUMBER, 2,
		"round 1 must have concluded undecided and continued automatically into round 2 exactly once"
	)
	assert_eq(
		instance.round_session.outcome(), "lost",
		"round 2 must conclude with a decided outcome once Golem's guaranteed-hit Strike lands against the now-vulnerable Hero"
	)
	assert_true(instance.result_screen_view.is_shown(), "the final decided outcome must still route to ResultScreenView")

	var result_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.EncounterResultEvent)
	assert_eq(result_events.size(), 1, "exactly one decided encounter outcome must ever be reached across both rounds")
	assert_eq(result_events[0].round, 2, "the decided outcome must be stamped with round 2's number, not round 1's")

	var turn_advanced_round_numbers: Array = []
	for e in instance.event_sink.log:
		if e is RoundEventsClass.TurnAdvancedEvent:
			turn_advanced_round_numbers.append(e.round)
	assert_true(turn_advanced_round_numbers.has(1), "round 1's own TurnAdvancedEvents must have been observed")
	assert_true(turn_advanced_round_numbers.has(2), "round 2's own TurnAdvancedEvents must have been observed -- proving a genuine second round ran")
