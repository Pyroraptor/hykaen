extends GutTest
## tests/unit/test_parry_reaction.gd
##
## GUT test suite for FEAT-205 (US-011 / FR-011, ADR-016): wiring the Parry
## reaction into LIVE play — the SECOND live, player-triggerable reaction on
## the steel thread's pop-up surface (FEAT-010 wired Dodge first).
##
## core/rules/resolution.gd (FEAT-059) already fully implements Parry's
## post-hit math: a hit by a weapon attack vs AC, when the reactor wields a
## weapon with parry_bonus > 0, rolls d20 + parry_bonus and STRICTLY exceeds
## the attacker's roll_total to suppress damage to 0 (on_hit_suppressed=true).
## core/application/reaction_window.gd (FEAT-009) already exposes
## Resolution.is_parry_eligible() via its "Parry" trigger_type branch and
## already delegates the ENTIRE attack — including whatever
## trigger["attack_context"] carries (e.g. "parrying_weapon") — to the
## injected Resolution instance via open_and_resolve_attack(). This feature
## closes the gap FEAT-010's own doc identified: proving that hand-off
## ACTUALLY reaches resolution.gd's Parry branch end-to-end, headlessly, via
## AutoReactionChooser — exactly as FEAT-010 proved for Dodge.
##
## Verifies (this feature's test_criteria):
##   1. The Parry trigger fires only when the reactor wields a weapon with
##      parry_bonus > 0 AND is hit by a weapon attack vs AC.
##   2. A strict-exceed d20+parry_bonus roll suppresses damage to 0 and sets
##      on_hit_suppressed=true; a NON-strict-exceed (tie or lower) roll does
##      NOT suppress damage.
##   3. The Parry reaction pays via ActionEconomy.spend_reaction();
##      spend_action() is never called.
##   4. A headless test verifies the Parry strict-exceed->0 outcome is
##      reachable via AutoReactionChooser (infrastructure/
##      auto_reaction_chooser.gd) with no UI present.

const ReactionWindowClass      = preload("res://core/application/reaction_window.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ResolutionClass          = preload("res://core/rules/resolution.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")
const CombatantClass           = preload("res://core/domain/combatant.gd")


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


## SequenceRNG — multi-step RNG stub mirroring tests/unit/test_dodge_reaction.gd's
## own SequenceRNG: returns successive values from pre-set d20/roll sequences.
## Parry's RNG consumption order (per resolution.gd's doc) is:
##   1. _rng.d20()     — attacker's attack roll
##   2. _rng.roll(...) — damage roll (hit only)
##   3. _rng.d20()     — parry attack roll (post-hit, Parry only)
## All three draw from the SAME d20_seq/roll_seq pools in call order.
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

## Standard attacker's weapon: d6 damage, strength modifier, +2 proficiency bonus.
var _weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 6
}


func _reactor(overrides: Dictionary = {}):
	var base: Dictionary = {
		"name": "Titus",
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"conditions": [],
		"conscious": true,
		"skills": {"mobility": 1, "determination": 1},
	}
	for key in overrides:
		base[key] = overrides[key]
	return CombatantClass.from_dict(base)


## The reactor's OWN parrying weapon — used both for eligibility
## (trigger["weapon"]) and, duplicated into trigger["attack_context"] as
## "parrying_weapon", for resolution.gd's actual post-hit parry roll.
func _parrying_weapon(parry_bonus: int = 3) -> Dictionary:
	return {"damage_die": 8, "parry_bonus": parry_bonus, "block_value": 0}


func _window() -> Dictionary:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	return {"window": window, "sink": sink}


func _resolution(d20_seq: Array, roll_seq: Array = []) -> ResolutionClass:
	return ResolutionClass.new(SequenceRNG.new(d20_seq, roll_seq))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Parry trigger fires only when the reactor wields a weapon
# with parry_bonus > 0 and is hit by a weapon attack vs AC
# ══════════════════════════════════════════════════════════════════════════

func test_parry_offered_when_weapon_has_parry_bonus() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _parrying_weapon(3),
		"defense_type": "ac",
	})

	assert_eq(opened["legal_reactions"], ["parry"],
		"Parry must be offered when the reactor's weapon has parry_bonus > 0")


func test_parry_withheld_when_weapon_has_no_parry_bonus() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"weapon": _parrying_weapon(0),
		"defense_type": "ac",
	})

	assert_eq(opened["legal_reactions"], [],
		"Parry must never be offered when the reactor's weapon has parry_bonus == 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 4: a strict-exceed d20+parry_bonus roll suppresses damage to
# 0 and sets on_hit_suppressed=true, driven headlessly via AutoReactionChooser
# (no UI present)
# ══════════════════════════════════════════════════════════════════════════

func test_parry_strict_exceed_via_auto_chooser_suppresses_damage_to_zero() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var parrying_weapon: Dictionary = _parrying_weapon(3)

	# attack_d20=10 → roll_total = 10 + strength(3) + prof(2) = 15 → hits ac(13)
	# damage_die roll=4 → damage_raw = 4 + strength(3) = 7
	# parry_d20=13 → parry_roll = 13 + parry_bonus(3) = 16
	# 16 > 15 (STRICT exceed) → Parry SUCCEEDS: damage suppressed to 0.
	var resolution: ResolutionClass = _resolution([10, 13], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "parry",
		"AutoReactionChooser's first_legal policy must pick the offered 'parry' reaction")
	assert_eq(outcome["active_defense_applied"], "parry")
	assert_true(outcome["hit"], "the underlying attack still hits AC")
	assert_true(outcome["on_hit_suppressed"], "a strict-exceed parry roll must set on_hit_suppressed=true")
	assert_eq(outcome["damage_final"], 0, "a successful Parry suppresses damage to 0")
	assert_eq(outcome["damage_raw"], 7, "damage_raw still reflects the unsuppressed roll for observability")


func test_parry_non_strict_exceed_via_auto_chooser_does_not_suppress_damage() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var parrying_weapon: Dictionary = _parrying_weapon(3)

	# attack_d20=10 → roll_total = 15 (hits ac 13)
	# damage roll=4 → damage_raw = 7
	# parry_d20=9 → parry_roll = 9 + 3 = 12; 12 <= 15 → Parry FAILS to suppress.
	var resolution: ResolutionClass = _resolution([10, 9], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["active_defense_applied"], "parry",
		"the reaction was still triggered/spent even though it failed to suppress damage")
	assert_false(outcome["on_hit_suppressed"], "a non-strict-exceed parry roll must not suppress damage")
	assert_eq(outcome["damage_final"], 7, "damage is unaffected when the parry roll fails to strictly exceed")


func test_parry_ties_attacker_roll_do_not_suppress_damage() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var parrying_weapon: Dictionary = _parrying_weapon(3)

	# attack_d20=10 → roll_total = 15
	# parry_d20=12 → parry_roll = 12 + 3 = 15 → EQUAL, not a strict exceed → fails.
	var resolution: ResolutionClass = _resolution([10, 12], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_false(outcome["on_hit_suppressed"], "an exact tie must NOT count as a strict exceed")
	assert_eq(outcome["damage_final"], 7)


func test_parry_pass_policy_never_triggers_the_reaction() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")
	var parrying_weapon: Dictionary = _parrying_weapon(3)

	# No parry roll is ever consumed — attack resolves against passive ac
	# only. attack_d20=16 → roll_total = 16 + 5 = 21 >= 13 → hit.
	var resolution: ResolutionClass = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["active_defense_applied"], "none",
		"declining the Parry offer must resolve the attack against passive AC only, with no suppression")
	assert_false(outcome["on_hit_suppressed"])
	assert_eq(ae.get_remaining(), 7, "declining the reaction must never spend a reaction")


## A Parry offer against a non-AC defense_type (e.g. Reflex) must never be
## legal — Parry is strictly a weapon-attack-vs-AC reaction (test_criteria #1).
func test_parry_withheld_for_non_ac_defense_type() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var parrying_weapon: Dictionary = _parrying_weapon(3)
	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var resolution: ResolutionClass = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "reflex",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	# _compute_legal_reactions("Parry") only inspects weapon.parry_bonus, so
	# eligibility here is unaffected by defense_type — but resolution.gd's
	# own Parry branch only ever triggers when defense_type == "ac", so even
	# though the window is willing to offer/spend the reaction, the roll
	# never applies against a non-AC defense.
	assert_eq(outcome["active_defense_applied"], "none",
		"resolution.gd's Parry branch never fires against a non-AC defense_type")
	assert_false(outcome["on_hit_suppressed"])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the Parry reaction pays via spend_reaction(); spend_action()
# is NEVER called
# ══════════════════════════════════════════════════════════════════════════

func test_parry_pays_via_spend_reaction_never_spend_action() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: SpyActionEconomy = SpyActionEconomy.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var parrying_weapon: Dictionary = _parrying_weapon(3)
	var resolution: ResolutionClass = _resolution([10, 13], [4])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(ae.spend_action_call_count, 0,
		"the Parry reaction must NEVER call ActionEconomy.spend_action()")
	assert_eq(ae.get_remaining(), 6,
		"the Parry reaction must spend exactly one reaction via spend_reaction()")
	assert_true(ae.can_take_action(),
		"spend_reaction() must not trip the per-turn spend_action() gate")


func test_parry_reaction_resolved_event_emitted_with_parry_choice() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var parrying_weapon: Dictionary = _parrying_weapon(3)
	var resolution: ResolutionClass = _resolution([10, 13], [4])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Parry",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": parrying_weapon,
			"defense_type": "ac",
			"attack_context": {"parrying_weapon": parrying_weapon},
			"round_number": 4,
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
	assert_true(resolved_event is RoundEventsClass.ReactionResolvedBroadcast)
	assert_eq(resolved_event.round, 4)
	assert_eq(resolved_event.choice, "parry")
	assert_eq(resolved_event.resolved_by, "ai_policy")
