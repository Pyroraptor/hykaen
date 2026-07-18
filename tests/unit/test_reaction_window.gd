extends GutTest
## tests/unit/test_reaction_window.gd
##
## GUT test suite for FEAT-009 (US-009 / FR-005, ADR-014): the pausable
## reaction-window architecture — core/application/reaction_window.gd's
## ReactionWindow, its two ports (core/application/ports/
## reaction_window_port.gd / reaction_chooser_port.gd),
## infrastructure/auto_reaction_chooser.gd's AutoReactionChooser, and
## infrastructure/static_check.gd's domain-purity checker.
##
## Verifies (this feature's test_criteria):
##   1. open(trigger) computes legal_reactions correctly per trigger-type
##      eligibility predicate — one case per trigger_type, eligible and
##      ineligible.
##   2. resume(choice) applies the choice (spends the reactor's reaction,
##      never the action-budget spend_action() path) and returns a
##      continuation synchronously — no blocking loop of any kind, proven
##      by driving open()/resume() across two separate, independent calls
##      with arbitrary other work in between.
##   3. AutoReactionChooser (headless Pass/fixed policy) drives resolution
##      to completion with no UI present, via open_and_resolve().
##   4. 'reaction window opened' / 'reaction resolved' events are emitted
##      via EventSinkPort/RoundEvents.
##   5. StaticCheck confirms zero Node/Control type imports under core/.

const ReactionWindowClass       = preload("res://core/application/reaction_window.gd")
const ReactionChooserPortClass  = preload("res://core/application/ports/reaction_chooser_port.gd")
const ReactionWindowPortClass   = preload("res://core/application/ports/reaction_window_port.gd")
const AutoReactionChooserClass  = preload("res://infrastructure/auto_reaction_chooser.gd")
const StaticCheckClass          = preload("res://infrastructure/static_check.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")


# ── Fake/double EventSinkPort (mirrors this project's established
#    tests/unit/core/application/test_round_session.gd convention) ─────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## FixedReactionChooser — a minimal ReactionChooserPort test double that
## always returns a caller-supplied choice, regardless of legal_reactions.
class FixedReactionChooser:
	extends "res://core/application/ports/reaction_chooser_port.gd"

	var _fixed_choice: String

	func _init(fixed_choice: String) -> void:
		_fixed_choice = fixed_choice

	func choose(_legal_reactions: Array, _context: Dictionary) -> String:
		return _fixed_choice


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _reactor(overrides: Dictionary = {}):
	var base: Dictionary = {
		"name": "Titus",
		"conditions": [],
		"conscious": true,
		"skills": {"mobility": 1, "determination": 1},
	}
	for key in overrides:
		base[key] = overrides[key]
	return CombatantClass.from_dict(base)


func _weapon(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"damage_die": 8,
		"parry_bonus": 0,
		"block_value": 0,
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _window() -> Dictionary:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	return {"window": window, "sink": sink}


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1: open(trigger) computes legal_reactions correctly per
# trigger-type eligibility predicate
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_trigger_is_legal_when_eligible() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_true(result["opened"], "Dodge window must open when reactor is not Spent")
	assert_eq(result["legal_reactions"], ["dodge"], "Dodge must be legal: ac defense, not Immobilized, open space")


func test_dodge_trigger_is_illegal_when_immobilized() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor({"conditions": ["Immobilized"]}),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(result["legal_reactions"], [], "Dodge must be illegal while Immobilized")


func test_dodge_trigger_is_illegal_without_open_space() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": false},
	})

	assert_eq(result["legal_reactions"], [], "Dodge must be illegal when no open space is available")


func test_dodge_trigger_is_illegal_for_non_ac_reflex_defense() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "fortitude",
		"attack_context": {},
	})

	assert_eq(result["legal_reactions"], [], "Dodge only triggers for ac/reflex defense types")


func test_parry_trigger_is_legal_when_weapon_has_parry_bonus() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _weapon({"parry_bonus": 2}),
	})

	assert_eq(result["legal_reactions"], ["parry"], "Parry must be legal when weapon.parry_bonus > 0")


func test_parry_trigger_is_illegal_without_parry_bonus() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _weapon({"parry_bonus": 0}),
	})

	assert_eq(result["legal_reactions"], [], "Parry must be illegal when weapon.parry_bonus == 0")


func test_block_trigger_is_legal_when_weapon_has_block_value() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor": _reactor(),
		"weapon": _weapon({"block_value": 2}),
	})

	assert_eq(result["legal_reactions"], ["block"], "Block must be legal when weapon.block_value > 0")


func test_block_trigger_is_illegal_without_block_value() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor": _reactor(),
		"weapon": _weapon({"block_value": 0}),
	})

	assert_eq(result["legal_reactions"], [], "Block must be illegal when weapon.block_value == 0")


func test_steel_trigger_is_legal_when_conscious_against_fortitude() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Steel",
		"reactor": _reactor({"conscious": true}),
		"defense_type": "fortitude",
	})

	assert_eq(result["legal_reactions"], ["steel"], "Steel must be legal: fortitude defense, conscious")


func test_steel_trigger_is_illegal_when_unconscious() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "Steel",
		"reactor": _reactor({"conscious": false}),
		"defense_type": "will",
	})

	assert_eq(result["legal_reactions"], [], "Steel must be illegal while unconscious")


func test_opportunistic_strike_trigger_is_legal_with_melee_reach() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "OpportunisticStrike",
		"reactor": _reactor(),
		"attack_context": {"melee_reach": true},
	})

	assert_eq(result["legal_reactions"], ["opportunistic_strike"])


func test_opportunistic_strike_trigger_is_illegal_without_melee_reach() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({
		"trigger_type": "OpportunisticStrike",
		"reactor": _reactor(),
		"attack_context": {"melee_reach": false},
	})

	assert_eq(result["legal_reactions"], [])


func test_unrecognized_trigger_type_yields_no_legal_reactions() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var result: Dictionary = window.open({"trigger_type": "Bogus", "reactor": _reactor()})

	assert_eq(result["legal_reactions"], [], "an unrecognized trigger_type must never raise/crash")
	assert_true(result["opened"])


## ALREADY_SPENT: the window never opens when the reactor's ActionEconomy
## is already Spent (this feature's api_contracts).
func test_open_reports_not_opened_when_reactor_already_spent() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	for i in range(7):
		ae.spend_reaction()
	assert_true(ae.is_spent())

	var result: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"weapon": _weapon({"parry_bonus": 2}),
	})

	assert_false(result["opened"], "a window must not open for an already-Spent reactor")
	assert_eq(result["window_id"], "")
	assert_eq(result["legal_reactions"], [])
	assert_eq(sink.events.size(), 0, "no event should be emitted when the window never opens")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2: resume(choice) applies the choice and continues
# resolution without blocking the engine thread
# ══════════════════════════════════════════════════════════════════════════

func test_resume_applies_legal_choice_and_spends_reaction() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	# Arbitrary "other engine work" happens here, between open() and
	# resume() — proving this class never blocks waiting inside open()
	# for a decision (test_criteria #2's "non-blocking on the engine
	# thread" requirement). A real caller would be servicing other
	# frames/turns/UI input in between these two calls.
	assert_eq(ae.get_remaining(), 7, "opening a window must never itself spend a reaction")

	var result: Dictionary = window.resume(opened["window_id"], "dodge", "player")

	assert_true(result["ok"])
	assert_eq(result["choice"], "dodge")
	assert_eq(ae.get_remaining(), 6, "resume() with a non-Pass choice must spend exactly one reaction")


func test_resume_with_pass_does_not_spend_a_reaction() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	var result: Dictionary = window.resume(opened["window_id"], ReactionChooserPortClass.PASS, "player")

	assert_true(result["ok"])
	assert_eq(result["choice"], ReactionChooserPortClass.PASS)
	assert_eq(ae.get_remaining(), 7, "Pass must never spend a reaction")


func test_resume_rejects_illegal_choice() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _weapon({"parry_bonus": 0}),  # Parry NOT legal
	})

	var result: Dictionary = window.resume(opened["window_id"], "parry", "player")

	assert_false(result["ok"])
	assert_eq(result["error"], ReactionWindowPortClass.ERR_ILLEGAL_CHOICE)


func test_resume_rejects_stale_window_id() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	window.open({"trigger_type": "Parry", "reactor": _reactor(), "weapon": _weapon({"parry_bonus": 2})})

	var result: Dictionary = window.resume("some-other-window-id", "parry", "player")

	assert_false(result["ok"])
	assert_eq(result["error"], ReactionWindowPortClass.ERR_STALE_WINDOW)


## Resuming the SAME window_id twice must fail the second time — resume()
## closes the window (a one-shot operation per window_id).
func test_resume_is_one_shot_per_window() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _weapon({"parry_bonus": 2}),
	})

	var first: Dictionary = window.resume(opened["window_id"], "parry", "player")
	assert_true(first["ok"])

	var second: Dictionary = window.resume(opened["window_id"], "parry", "player")
	assert_false(second["ok"], "resuming an already-resolved window must fail")
	assert_eq(second["error"], ReactionWindowPortClass.ERR_STALE_WINDOW)


## Race guard: if the reactor's budget was exhausted by something ELSE
## between open() and resume() (e.g. another reaction spent it), resume()
## must fall back to Pass rather than erroring/crashing.
func test_resume_falls_back_to_pass_when_reactor_spent_between_open_and_resume() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	# Something else exhausts the reactor's budget before resume() runs.
	for i in range(7):
		ae.spend_reaction()
	assert_true(ae.is_spent())

	var result: Dictionary = window.resume(opened["window_id"], "dodge", "player")

	assert_true(result["ok"], "resume() must never fail/hang on a race-exhausted budget")
	assert_eq(result["choice"], ReactionChooserPortClass.PASS, "must fall back to Pass, not the requested choice")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3: AutoReactionChooser (headless Pass/fixed policy) drives
# resolution to completion with no UI present
# ══════════════════════════════════════════════════════════════════════════

func test_auto_reaction_chooser_pass_policy_always_declines() -> void:
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")
	assert_eq(chooser.choose(["dodge"], {}), ReactionChooserPortClass.PASS)
	assert_eq(chooser.choose([], {}), ReactionChooserPortClass.PASS)


func test_auto_reaction_chooser_first_legal_policy_takes_first_option() -> void:
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	assert_eq(chooser.choose(["dodge"], {}), "dodge")
	assert_eq(chooser.choose([], {}), ReactionChooserPortClass.PASS, "no legal option -> Pass, never a crash")


func test_open_and_resolve_drives_resolution_with_default_pass_policy_headless() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")

	var result: Dictionary = window.open_and_resolve({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	}, chooser)

	assert_true(result["ok"], "open_and_resolve must complete synchronously with no UI present")
	assert_eq(result["choice"], ReactionChooserPortClass.PASS)
	assert_eq(ae.get_remaining(), 7)


func test_open_and_resolve_drives_resolution_with_first_legal_policy_headless() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	var result: Dictionary = window.open_and_resolve({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"weapon": _weapon({"parry_bonus": 2}),
	}, chooser)

	assert_true(result["ok"])
	assert_eq(result["choice"], "parry")
	assert_eq(ae.get_remaining(), 6, "the chosen reaction must actually spend a reaction end-to-end")


## When the reactor is already Spent, open_and_resolve() must still
## complete (no resume() call against a never-opened window) — proving the
## headless drive-to-completion path never stalls even on this edge case.
func test_open_and_resolve_completes_when_reactor_already_spent() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	for i in range(7):
		ae.spend_reaction()

	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	var result: Dictionary = window.open_and_resolve({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"weapon": _weapon({"parry_bonus": 2}),
	}, chooser)

	assert_true(result["ok"])
	assert_false(result["opened"])
	assert_eq(result["choice"], ReactionChooserPortClass.PASS)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4: 'reaction window opened' and 'reaction resolved' events
# are emitted via EventSinkPort/RoundEvents
# ══════════════════════════════════════════════════════════════════════════

func test_open_emits_reaction_window_opened_event() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
		"round_number": 3,
	})

	assert_eq(sink.events.size(), 1)
	var event = sink.events[0]
	assert_true(event is RoundEventsClass.ReactionWindowOpenedEvent)
	assert_eq(event.round, 3)
	assert_eq(event.trigger_type, "Dodge")
	assert_eq(event.reactor_name, "Titus")
	assert_eq(event.legal_reactions, ["dodge"])
	assert_eq(event.to_dict()["window_id"], event.window_id)


func test_resume_emits_reaction_resolved_event() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var opened: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor": _reactor(),
		"weapon": _weapon({"block_value": 3}),
		"round_number": 5,
	})
	window.resume(opened["window_id"], "block", "ai_policy")

	assert_eq(sink.events.size(), 2, "open() and resume() must each emit exactly one event")
	var event = sink.events[1]
	assert_true(event is RoundEventsClass.ReactionResolvedBroadcast)
	assert_eq(event.round, 5)
	assert_eq(event.window_id, opened["window_id"])
	assert_eq(event.choice, "block")
	assert_eq(event.resolved_by, "ai_policy")
	assert_eq(event.to_dict()["choice"], "block")


func test_no_event_emitted_on_illegal_choice_or_stale_window() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var opened: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _weapon({"parry_bonus": 0}),
	})
	assert_eq(sink.events.size(), 1)

	window.resume(opened["window_id"], "parry", "player")   # illegal (not offered)
	window.resume("stale-id", ReactionChooserPortClass.PASS, "player")  # stale

	assert_eq(sink.events.size(), 1, "a rejected resume() must never emit a reaction_resolved event")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #5: static check confirms zero Node/Control type imports
# in core/
# ══════════════════════════════════════════════════════════════════════════

func test_static_check_confirms_core_is_free_of_engine_imports() -> void:
	var checker: StaticCheckClass = StaticCheckClass.new()
	var violations: Array = checker.scan_for_engine_imports("res://core")
	assert_eq(violations, [], "core/ must contain zero 'extends Node'/'extends Control' clauses")


func test_static_check_does_not_flag_quoted_extends_chain() -> void:
	# reaction_window.gd itself uses `extends "res://core/application/
	# ports/reaction_window_port.gd"` — proves the checker's own pattern
	# doesn't false-positive on this feature's own new files.
	var checker: StaticCheckClass = StaticCheckClass.new()
	var violations: Array = checker.scan_for_engine_imports("res://core/application")
	assert_eq(violations, [])


func test_static_check_detects_injected_violation() -> void:
	var checker: StaticCheckClass = StaticCheckClass.new()

	var out: Array = []
	var rc: int = OS.execute("mktemp", ["-d"], out, true)
	if rc != 0 or out.is_empty():
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return
	var tmp_dir: String = String(out[0]).strip_edges()

	var violation_path: String = tmp_dir + "/rogue_widget.gd"
	var f := FileAccess.open(violation_path, FileAccess.WRITE)
	f.store_string("class_name RogueWidget\nextends Node\n")
	f.close()

	var violations: Array = checker.scan_for_engine_imports(tmp_dir)
	OS.execute("rm", ["-rf", tmp_dir], [], true)

	assert_eq(violations.size(), 1)
	assert_true(String(violations[0]["file"]).ends_with("rogue_widget.gd"))
