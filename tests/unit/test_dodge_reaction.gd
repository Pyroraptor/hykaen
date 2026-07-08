extends GutTest
## tests/unit/test_dodge_reaction.gd
##
## GUT test suite for FEAT-010 (US-010 / FR-010, ADR-016): wiring the Dodge
## reaction into LIVE play — the first live, player-triggerable reaction on
## the steel thread.
##
## Prior features built the pieces in isolation:
##   - FEAT-007 rewired resolution.gd's Dodge/Steel checks onto the real
##     skills['mobility']/skills['determination'] values.
##   - FEAT-009 built ReactionWindow (core/application/reaction_window.gd),
##     which could compute Dodge's legal_reactions and spend a reaction via
##     resume(), but NEVER actually invoked resolution.gd's
##     resolve_weapon_attack() — a chosen "dodge" never touched a live
##     attack's hit/miss outcome.
##
## FEAT-010 closes that gap: ReactionWindow.open_and_resolve_attack() asks
## an injected ReactionChooserPort (here, the headless AutoReactionChooser)
## for a decision, then delegates the ENTIRE attack roll — including the
## pre-hit Mobility check substituting for passive AC/Reflex — to the
## injected core/rules/resolution.gd Resolution instance, which is the SOLE
## place that spends the reactor's reaction (ActionEconomy.spend_reaction(),
## NEVER spend_action()).
##
## Verifies (this feature's test_criteria):
##   1. Dodge trigger fires only when reactor is not Immobilized AND an open
##      adjacent hex exists (open_space_available).
##   2. A successful pre-hit Mobility check sets defender_stepped=true and
##      the attack misses.
##   3. The Dodge reaction pays via ActionEconomy.spend_reaction();
##      spend_action() is never called.
##   4. A headless test verifies the Dodge miss+step outcome is reachable via
##      AutoReactionChooser (infrastructure/auto_reaction_chooser.gd) with no
##      UI present.

const ReactionWindowClass      = preload("res://core/application/reaction_window.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ResolutionClass          = preload("res://core/rules/resolution.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")


# ── Fake/double EventSinkPort (mirrors tests/unit/test_reaction_window.gd's
#    established convention) ─────────────────────────────────────────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## SpyActionEconomy — a real ActionEconomy that records every spend_action()
## call, so test_criteria #3 ("spend_action() is never called") can be
## proven directly rather than merely inferred from budget_remaining.
## spend_reaction() is left completely untouched (inherited as-is).
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


## SequenceRNG — multi-step RNG stub mirroring tests/unit/test_dodge_steel_checks.gd's
## own SequenceRNG: returns successive values from pre-set d20/roll sequences.
class SequenceRNG:
	var _d20_seq: Array
	var _roll_seq: Array
	var _d20_idx: int = 0
	var _roll_idx: int = 0

	func _init(d20_seq: Array, roll_seq: Array = []) -> void:
		_d20_seq = d20_seq
		_roll_seq = roll_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(_die_size: int, _count: int) -> int:
		var val: int = _roll_seq[_roll_idx % _roll_seq.size()]
		_roll_idx += 1
		return val


# ── Shared fixture helpers ─────────────────────────────────────────────────

## Standard attacker: strength(3) + proficiency(2) → attack modifier +5.
var _attacker: Dictionary = {
	"strength": 3, "dexterity": 1, "constitution": 2,
	"willpower": 1, "intellect": 1, "intuition": 1, "social": 1
}

## Standard weapon: d6 damage, strength modifier, +2 proficiency bonus.
var _weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 6
}


func _reactor(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"name": "Titus",
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"conditions": [],
		"conscious": true,
		"skills": {"mobility": 1, "determination": 1},
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _window() -> Dictionary:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	return {"window": window, "sink": sink}


func _resolution(d20_seq: Array, roll_seq: Array = []) -> ResolutionClass:
	return ResolutionClass.new(SequenceRNG.new(d20_seq, roll_seq))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Dodge trigger fires only when reactor not Immobilized AND an
# open adjacent hex exists
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_offered_when_not_immobilized_and_open_hex_exists() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], ["dodge"],
		"Dodge must be offered when the reactor is not Immobilized and an open adjacent hex exists")


func test_dodge_withheld_when_reactor_immobilized() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor({"conditions": ["Immobilized"]}),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], [],
		"Dodge must never be offered while the reactor is Immobilized")


func test_dodge_withheld_when_no_open_adjacent_hex() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": false},
	})

	assert_eq(opened["legal_reactions"], [],
		"Dodge must never be offered when no open adjacent hex exists")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 4: a successful pre-hit Mobility check sets
# defender_stepped=true and the attack misses, driven headlessly via
# AutoReactionChooser (no UI present)
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_success_via_auto_chooser_sets_defender_stepped_and_misses() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# mob_d20=16 → mobility_check = 16 + skills.mobility(1) = 17
	# attack_d20=10 → roll_total = 10 + strength(3) + prof(2) = 15
	# 15 < 17 → Dodge SUCCEEDS: attack misses, defender steps. No damage
	# roll is ever consumed (roll_seq intentionally left empty).
	var resolution: ResolutionClass = _resolution([16, 10])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Dodge",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "dodge",
		"AutoReactionChooser's first_legal policy must pick the offered 'dodge' reaction")
	assert_eq(outcome["active_defense_applied"], "dodge")
	assert_false(outcome["hit"], "successful Dodge (mobility check beats roll_total) must miss")
	assert_true(outcome["defender_stepped"], "successful Dodge must set defender_stepped=true")
	assert_eq(outcome["damage_final"], 0, "a miss deals zero damage")


func test_dodge_failure_via_auto_chooser_still_resolves_the_hit() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# mob_d20=2 → mobility_check = 2 + skills.mobility(1) = 3
	# attack_d20=10 → roll_total = 15
	# 15 >= 3 → Dodge FAILS to protect: attack hits, defender does NOT step.
	var resolution: ResolutionClass = _resolution([2, 10], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Dodge",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["active_defense_applied"], "dodge",
		"the reaction was still triggered/spent even though it failed to protect")
	assert_true(outcome["hit"], "a failed Dodge check must not prevent the hit")
	assert_false(outcome["defender_stepped"], "a failed Dodge must not set defender_stepped")


func test_dodge_pass_policy_never_triggers_the_reaction() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")

	# No Dodge check is ever rolled — the passive "ac" defense (13) is used
	# directly. attack_d20=16 → roll_total = 16 + 5 = 21 >= 13 → hit.
	var resolution: ResolutionClass = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Dodge",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["active_defense_applied"], "none",
		"declining the Dodge offer must resolve the attack against passive AC only")
	assert_eq(ae.get_remaining(), 7, "declining the reaction must never spend a reaction")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the Dodge reaction pays via spend_reaction(); spend_action()
# is NEVER called
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_pays_via_spend_reaction_never_spend_action() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: SpyActionEconomy = SpyActionEconomy.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var resolution: ResolutionClass = _resolution([16, 10])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Dodge",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(ae.spend_action_call_count, 0,
		"the Dodge reaction must NEVER call ActionEconomy.spend_action()")
	assert_eq(ae.get_remaining(), 6,
		"the Dodge reaction must spend exactly one reaction via spend_reaction()")
	assert_true(ae.can_take_action(),
		"spend_reaction() must not trip the per-turn spend_action() gate")


func test_dodge_reaction_resolved_event_emitted_with_dodge_choice() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var resolution: ResolutionClass = _resolution([16, 10])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Dodge",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
			"round_number": 2,
		},
		resolution,
		_attacker,
		_weapon,
		chooser,
		"ai_policy"
	)

	assert_eq(sink.events.size(), 2, "open() and the attack resolution must each emit exactly one event")
	assert_true(sink.events[0] is RoundEventsClass.ReactionWindowOpenedEvent)
	var resolved_event = sink.events[1]
	assert_true(resolved_event is RoundEventsClass.ReactionResolvedEvent)
	assert_eq(resolved_event.round, 2)
	assert_eq(resolved_event.choice, "dodge")
	assert_eq(resolved_event.resolved_by, "ai_policy")
