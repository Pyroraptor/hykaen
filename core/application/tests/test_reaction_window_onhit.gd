extends GutTest
## core/application/tests/test_reaction_window_onhit.gd
##
## GUT suite for FEAT-004 (US-004 / FR-003): the new "OnHitMitigation"
## reaction window (Parry/Block only, opened AFTER the attack roll/hit
## result is known), built atop FEAT-001's resolve_to_hit()/
## apply_on_hit_defense() two-phase split (core/rules/resolution.gd) and
## FEAT-003's is_on_hit_mitigation_eligible() budget gate
## (core/application/reaction_window.gd).
##
## Sections:
##   A. core/application/reaction_window.gd's _compute_legal_reactions() —
##      the "OnHitMitigation" trigger_type offers exactly whichever of
##      Parry/Block is_parry_eligible()/is_block_eligible() report eligible,
##      reusing those SAME predicates, but ONLY once
##      is_on_hit_mitigation_eligible() reports true.
##   B. reaction_window.gd's new open_and_resolve_onhit_mitigation() —
##      Parry success negates damage, Block reduces damage by 1[W]+
##      block_value (clamped >= 0), apply_on_hit_defense() is NEVER invoked
##      on a miss or when a reaction was already spent this Strike, and
##      declining (Pass) leaves damage untouched.
##   C. core/application/round_session.gd's new OnHitMitigation resolver
##      seam (_onhit_mitigation_resolver_fn/set_onhit_mitigation_resolver_fn()/
##      _resolve_onhit_mitigation()) — stored/invokable once injected, and a
##      complete, byte-for-byte no-op (synchronous {"choice":"none"}
##      fallback) for every pre-existing caller/test double that never
##      injects one (NFR-004).

const ReactionWindowClass      = preload("res://core/application/reaction_window.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ResolutionClass          = preload("res://core/rules/resolution.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double EventSinkPort (mirrors core/application/tests/
#    test_reaction_window_prehit.gd's established convention) ─────────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## SpyActionEconomy — a real ActionEconomy that records every spend_action()
## call, so "spend_reaction(), never spend_action()" can be proven directly.
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


## SequenceRNG — mirrors test_reaction_window_prehit.gd's own SequenceRNG:
## returns successive values from pre-set d20/roll sequences.
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


## SpyResolution — a real Resolution subclass that records every
## apply_on_hit_defense() call, so "apply_on_hit_defense is NEVER invoked
## when partial.hit == false / when a reaction was already spent" (this
## feature's test_criteria #2/#5) can be proven directly rather than merely
## inferred from the returned Dictionary.
class SpyResolution:
	extends "res://core/rules/resolution.gd"

	var apply_on_hit_defense_call_count: int = 0

	func apply_on_hit_defense(partial: Dictionary, on_hit_defense: String = "none", ctx: Dictionary = {}) -> Dictionary:
		apply_on_hit_defense_call_count += 1
		return super.apply_on_hit_defense(partial, on_hit_defense, ctx)


# ── Shared fixture helpers ──────────────────────────────────────────────────

var _attacker: Dictionary = {
	"strength": 3, "dexterity": 1, "constitution": 2,
	"willpower": 1, "intellect": 1, "intuition": 1, "social": 1
}

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


func _resolution(d20_seq: Array, roll_seq: Array = []) -> SpyResolution:
	var res := SpyResolution.new(SequenceRNG.new(d20_seq, roll_seq))
	return res


# ══════════════════════════════════════════════════════════════════════════
# Section A: _compute_legal_reactions() — "OnHitMitigation" trigger_type
# ══════════════════════════════════════════════════════════════════════════

func test_onhit_mitigation_offers_parry_and_block_when_both_eligible() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 2},
		"attack_hit": true,
		"reaction_already_spent": false,
	})

	assert_eq(opened["legal_reactions"], ["parry", "block"],
		"OnHitMitigation must offer BOTH Parry and Block when the reactor's weapon is eligible for both (test_criteria #1)")


func test_onhit_mitigation_offers_only_parry_when_block_value_absent() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 0},
		"attack_hit": true,
		"reaction_already_spent": false,
	})

	assert_eq(opened["legal_reactions"], ["parry"])


func test_onhit_mitigation_offers_only_block_when_parry_bonus_absent() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 0, "block_value": 2},
		"attack_hit": true,
		"reaction_already_spent": false,
	})

	assert_eq(opened["legal_reactions"], ["block"])


func test_onhit_mitigation_offers_nothing_when_weapon_ineligible_for_either() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 0, "block_value": 0},
		"attack_hit": true,
		"reaction_already_spent": false,
	})

	assert_eq(opened["legal_reactions"], [])


func test_onhit_mitigation_offers_nothing_on_a_miss_even_with_an_eligible_weapon() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 2},
		"attack_hit": false,
		"reaction_already_spent": false,
	})

	assert_eq(opened["legal_reactions"], [],
		"OnHitMitigation must offer nothing at all on a miss -- there is no hit to mitigate (test_criteria #5)")


func test_onhit_mitigation_offers_nothing_when_a_reaction_was_already_spent_even_on_a_hit() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 2},
		"attack_hit": true,
		"reaction_already_spent": true,
	})

	assert_eq(opened["legal_reactions"], [],
		"OnHitMitigation must offer nothing once this Strike's one reaction was already spent, regardless of hit result (test_criteria #1/#5)")


func test_onhit_mitigation_gate_defaults_are_safe_when_keys_are_omitted() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	# Neither "attack_hit" nor "reaction_already_spent" supplied -- the safe
	# default (attack_hit defaults false) must offer nothing, never crash.
	var opened: Dictionary = window.open({
		"trigger_type": "OnHitMitigation",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 2},
	})

	assert_eq(opened["legal_reactions"], [])


# ══════════════════════════════════════════════════════════════════════════
# Section B: open_and_resolve_onhit_mitigation()
# ══════════════════════════════════════════════════════════════════════════

func test_successful_parry_negates_damage_to_zero() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=16 -> roll_total=16+3+2=21 >= ac(13) -> hit. damage die=4 ->
	# damage_raw=4+3=7. parry_d20=18 -> parry_roll=18+parry_bonus(4)=22 > 21
	# -> Parry SUCCEEDS: damage_final=0.
	var resolution: SpyResolution = _resolution([16, 18], [4])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})
	assert_true(partial["hit"])
	assert_eq(partial["damage_raw"], 7)

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 4, "block_value": 0},
			"reactor_action_economy": ae,
			"attack_context": {"parrying_weapon": {"parry_bonus": 4}},
			"round_number": 2,
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "parry")
	assert_eq(outcome["damage_final"], 0, "a successful Parry must negate damage to zero (test_criteria #3)")
	assert_eq(outcome["active_defense_applied"], "parry")
	assert_true(outcome["on_hit_suppressed"])
	assert_true(outcome["reaction_spent"])

	assert_eq(resolution.apply_on_hit_defense_call_count, 1)
	assert_eq(ae.get_remaining(), 6, "a triggered Parry must spend exactly one reaction")

	assert_eq(sink.events.size(), 2, "open() emits a ReactionWindowOpenedEvent, then the resolved choice emits a ReactionResolvedEvent")
	assert_true(sink.events[1] is RoundEventsClass.ReactionResolvedBroadcast)
	assert_eq(sink.events[1].choice, "parry")
	assert_eq(sink.events[1].round, 2)


func test_failed_parry_leaves_damage_unmitigated() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=16 -> roll_total=21. damage_raw=7. parry_d20=2 ->
	# parry_roll=2+4=6, NOT > 21 -> Parry FAILS to protect.
	var resolution: SpyResolution = _resolution([16, 2], [4])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 4, "block_value": 0},
			"reactor_action_economy": ae,
			"attack_context": {"parrying_weapon": {"parry_bonus": 4}},
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "parry")
	assert_eq(outcome["damage_final"], 7, "a failed Parry must not reduce damage at all")
	assert_false(outcome["on_hit_suppressed"])
	assert_true(outcome["reaction_spent"], "a reaction is spent whether or not the Parry actually protects")
	assert_eq(ae.get_remaining(), 6)


func test_block_reduces_damage_by_one_w_plus_block_value_clamped_at_zero() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=16 -> roll_total=21. damage_raw=7. block-reduction die=3 ->
	# block_reduction = 3 (1[W]) + block_value(2) = 5 -> damage_final = 2.
	var resolution: SpyResolution = _resolution([16], [4, 3])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 2},
			"reactor_action_economy": ae,
			"attack_context": {"blocking_weapon": {"damage_die": 6, "block_value": 2}},
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "block")
	assert_eq(outcome["damage_final"], 2, "Block must reduce damage_raw by 1[W]+block_value (test_criteria #4)")
	assert_eq(outcome["active_defense_applied"], "block")
	assert_true(outcome["on_hit_suppressed"])
	assert_true(outcome["reaction_spent"])
	assert_eq(ae.get_remaining(), 6)


func test_block_clamps_damage_final_at_zero_when_reduction_exceeds_raw_damage() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=16 -> roll_total=21. damage_raw=7. block-reduction die=6 ->
	# block_reduction = 6 + block_value(10) = 16 -- far more than damage_raw
	# (7) -- damage_final must clamp at 0, never go negative.
	var resolution: SpyResolution = _resolution([16], [4, 6])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 10},
			"reactor_action_economy": ae,
			"attack_context": {"blocking_weapon": {"damage_die": 6, "block_value": 10}},
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(outcome["damage_final"], 0, "damage_final must clamp at 0, never negative (test_criteria #4)")


func test_apply_on_hit_defense_never_invoked_on_a_miss() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=1 -> roll_total=1+3+2=6 < ac(13) -> miss. No damage roll.
	var resolution: SpyResolution = _resolution([1])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})
	assert_false(partial["hit"])

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 4, "block_value": 2},
			"reactor_action_economy": ae,
			"attack_context": {},
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(resolution.apply_on_hit_defense_call_count, 0,
		"apply_on_hit_defense must never be invoked when partial.hit == false (test_criteria #2)")
	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["window_id"], "", "the window must never open at all on a miss (test_criteria #5)")
	assert_eq(outcome["damage_final"], 0)
	assert_false(outcome["reaction_spent"])
	assert_eq(ae.get_remaining(), 7, "no reaction may be spent when the window never opens")
	assert_eq(sink.events.size(), 0, "no event of any kind is emitted when the window is skipped entirely on a miss")


func test_window_skipped_entirely_when_a_reaction_was_already_spent_this_strike() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=16 -> roll_total=21 -> hit. damage_raw=7. A pre-hit Dodge (or
	# any prior reaction) already spent this Strike's ONE reaction --
	# reaction_already_spent=true must gate this window closed regardless of
	# the hit result (test_criteria #5).
	var resolution: SpyResolution = _resolution([16], [4])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})
	assert_true(partial["hit"])

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 4, "block_value": 2},
			"reactor_action_economy": ae,
			"attack_context": {},
			"reaction_already_spent": true,
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(resolution.apply_on_hit_defense_call_count, 0,
		"apply_on_hit_defense must never be invoked once a reaction was already spent this Strike")
	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["window_id"], "", "the window must never open at all once a reaction was already spent")
	assert_eq(outcome["damage_final"], 7, "an un-mitigated hit still deals its full raw damage")
	assert_false(outcome["reaction_spent"])
	assert_eq(ae.get_remaining(), 7, "no SECOND reaction may be spent for this Strike")
	assert_eq(sink.events.size(), 0)


func test_declining_the_offer_leaves_damage_unmitigated() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")

	var resolution: SpyResolution = _resolution([16], [4])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})

	var outcome: Dictionary = window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 4, "block_value": 2},
			"reactor_action_economy": ae,
			"attack_context": {},
			"round_number": 5,
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["damage_final"], 7, "declining every offered reaction must leave damage fully unmitigated")
	assert_false(outcome["reaction_spent"])
	assert_eq(resolution.apply_on_hit_defense_call_count, 0)
	assert_eq(ae.get_remaining(), 7, "declining every offered reaction must never spend a reaction")

	# Unlike the miss/already-spent gate-skip paths above, the window DID
	# open here (the gate passed -- a hit, no prior spend) -- Pass is a real
	# answer to a real offer, so a ReactionResolvedEvent is still emitted.
	assert_eq(sink.events.size(), 2, "open() emits a ReactionWindowOpenedEvent, then the resolved choice emits a ReactionResolvedEvent")
	assert_eq(sink.events[1].choice, ReactionChooserPortClass.PASS)


func test_block_pays_via_spend_reaction_never_spend_action() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: SpyActionEconomy = SpyActionEconomy.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	var resolution: SpyResolution = _resolution([16], [4, 3])
	var partial: Dictionary = resolution.resolve_to_hit(_attacker, _reactor(), _weapon, "ac", "none", {})

	window.open_and_resolve_onhit_mitigation(
		{
			"trigger_type": "OnHitMitigation",
			"reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 2},
			"reactor_action_economy": ae,
			"attack_context": {"blocking_weapon": {"damage_die": 6, "block_value": 2}},
		},
		resolution,
		partial,
		chooser
	)

	assert_eq(ae.spend_action_call_count, 0, "OnHitMitigation must NEVER call ActionEconomy.spend_action()")
	assert_eq(ae.get_remaining(), 6)


# ══════════════════════════════════════════════════════════════════════════
# Section C: core/application/round_session.gd's new OnHitMitigation seam
# ══════════════════════════════════════════════════════════════════════════

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPortRS:
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


## RecordingOnHitMitigationResolver — a ReactionResolverPort double (`async
## func(trigger) -> Dictionary`) for the new OnHitMitigation seam, mirroring
## tests/gut/test_round_session_reaction_resolver_injection.gd's
## RecordingReactionResolver convention.
class RecordingOnHitMitigationResolver:
	extends RefCounted

	var choice_to_return: String = "none"
	var calls: Array = []

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": choice_to_return}


func _rs_entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _rs_bravo() -> Dictionary:
	return {
		"name":         "Bravo",
		"combatant_id": "bravo",
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"_is_enemy":    true,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	}


func _rs_alpha() -> Dictionary:
	return {
		"name":         "Alpha",
		"combatant_id": "alpha",
		"hp_current":   2000,
		"ac":           10,
		"conscious":    true,
		"conditions":   [],
		"skills":       {"mobility": 1, "determination": 1},
		"_is_enemy":    false,
		"weapon": {
			"damage_modifier_attribute": "dexterity",
			"proficiency_bonus": 0,
			"damage_die": 6,
			"parry_bonus": 3,
			"block_value": 2,
		},
	}


func _rs_session(entries: Array, party: Array, enemies: Array, random_number_port):
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPortRS.new()
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	return run_round_use_case.begin_round(1, party, enemies)


func test_set_onhit_mitigation_resolver_fn_stores_the_callable_and_is_retrievable() -> void:
	var entries: Array = [_rs_entry(_rs_bravo()), _rs_entry(_rs_alpha())]
	var session = _rs_session(entries, [entries[1]["combatant"]], [entries[0]["combatant"]], null)

	var resolver := RecordingOnHitMitigationResolver.new()
	var fn := Callable(resolver, "resolve")

	session.set_onhit_mitigation_resolver_fn(fn)

	assert_true(session._onhit_mitigation_resolver_fn.is_valid(), "the injected Callable must be stored and retrievable off RoundSession")
	assert_eq(session._onhit_mitigation_resolver_fn.get_object(), resolver, "the stored Callable must target the exact injected object")
	assert_eq(session._onhit_mitigation_resolver_fn.get_method(), &"resolve", "the stored Callable must target the exact injected method")


func test_resolve_onhit_mitigation_invokes_the_injected_resolver_exactly_once() -> void:
	var entries: Array = [_rs_entry(_rs_bravo()), _rs_entry(_rs_alpha())]
	var session = _rs_session(entries, [entries[1]["combatant"]], [entries[0]["combatant"]], null)

	var resolver := RecordingOnHitMitigationResolver.new()
	resolver.choice_to_return = "block"
	session.set_onhit_mitigation_resolver_fn(Callable(resolver, "resolve"))

	var trigger: Dictionary = {"trigger_type": "OnHitMitigation", "reactor_id": "alpha"}
	var result: Dictionary = await session._resolve_onhit_mitigation(trigger)

	assert_eq(resolver.calls.size(), 1, "RoundSession's internal OnHitMitigation seam must invoke the injected Callable exactly once")
	assert_eq(resolver.calls[0], trigger, "the injected Callable must be invoked with the exact trigger Dictionary passed in")
	assert_eq(result, {"choice": "block"}, "RoundSession must return the injected resolver's result verbatim")


func test_resolve_onhit_mitigation_defaults_to_synchronous_none_pass_when_unset() -> void:
	var entries: Array = [_rs_entry(_rs_bravo()), _rs_entry(_rs_alpha())]
	var session = _rs_session(entries, [entries[1]["combatant"]], [entries[0]["combatant"]], null)

	assert_false(session._onhit_mitigation_resolver_fn.is_valid(), "fixture assumption: no resolver has been injected on a fresh session")

	var result: Dictionary = await session._resolve_onhit_mitigation({"trigger_type": "OnHitMitigation"})

	assert_eq(result, {"choice": "none"}, "an un-injected resolver must fall back to a synchronous 'none' (PASS) result -- the pre-change baseline (NFR-004)")
