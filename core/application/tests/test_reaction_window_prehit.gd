extends GutTest
## core/application/tests/test_reaction_window_prehit.gd
##
## GUT suite for FEAT-002 (US-002 / FR-001, Iteration J Part B — "reaction-
## timing correction"): the new "PreHitAvoidance" reaction window
## (Dodge/Steel only, opened BEFORE the attack roll), built atop FEAT-001's
## resolve_to_hit()/apply_on_hit_defense() two-phase split
## (core/rules/resolution.gd, core/rules/tests/test_resolution_two_phase.gd).
##
## Sections:
##   A. core/application/reaction_window.gd's _compute_legal_reactions() —
##      the "PreHitAvoidance" trigger_type offers exactly whichever of
##      Dodge/Steel is_dodge_eligible()/is_steel_eligible() report eligible,
##      reusing those SAME predicates (never a re-derived rule).
##   B. reaction_window.gd's new open_and_resolve_prehit_avoidance() —
##      dodge/steel success short-circuits (resolve_to_hit is the ONLY phase
##      ever invoked; apply_on_hit_defense() is NEVER called; no damage),
##      dodge/steel failure sets on_hit_suppressed (a reaction was already
##      spent this Strike), and Pass proceeds to a plain roll.
##   C. core/application/round_session.gd's advance_ai_turn() — the new
##      PreHitAvoidance resolver seam is `await`ed BEFORE any RNG draw in
##      the eventual resolve_to_hit() call, short-circuits/suppresses the
##      existing WeaponAttack (on-hit) window correctly, and — when the new
##      seam is never injected (every pre-existing caller) — is a complete,
##      byte-for-byte no-op (NFR-004).

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


# ── Fake/double EventSinkPort (mirrors tests/unit/test_dodge_reaction.gd's
#    established convention — each suite in this project owns its own
#    doubles) ─────────────────────────────────────────────────────────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## SpyActionEconomy — a real ActionEconomy that records every spend_action()
## call, so "spend_reaction(), never spend_action()" can be proven directly
## (mirrors tests/unit/test_dodge_reaction.gd's identically-named double).
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


## SequenceRNG — mirrors core/rules/tests/test_resolution_two_phase.gd's own
## SequenceRNG: returns successive values from pre-set d20/roll sequences.
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
## apply_on_hit_defense() call, so "apply_on_hit_defense is NEVER invoked by
## the PreHitAvoidance-only flow" (test_criteria: successful Dodge
## short-circuits before any on-hit/damage-mitigation phase runs) can be
## proven directly rather than merely inferred from the returned Dictionary.
class SpyResolution:
	extends "res://core/rules/resolution.gd"

	var apply_on_hit_defense_call_count: int = 0
	var resolve_to_hit_call_count: int = 0

	func resolve_to_hit(attacker: Dictionary, target: Dictionary, weapon: Dictionary, defense_type: String, pre_hit_defense: String = "none", ctx: Dictionary = {}) -> Dictionary:
		resolve_to_hit_call_count += 1
		return super.resolve_to_hit(attacker, target, weapon, defense_type, pre_hit_defense, ctx)

	func apply_on_hit_defense(partial: Dictionary, on_hit_defense: String = "none", ctx: Dictionary = {}) -> Dictionary:
		apply_on_hit_defense_call_count += 1
		return super.apply_on_hit_defense(partial, on_hit_defense, ctx)


# ── Shared fixture helpers (Sections A/B) ───────────────────────────────────

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
# Section A: _compute_legal_reactions() — "PreHitAvoidance" trigger_type
# ══════════════════════════════════════════════════════════════════════════

func test_prehit_avoidance_offers_dodge_when_eligible_vs_ac() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor(),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], ["dodge"],
		"PreHitAvoidance must offer Dodge (never Steel) for an 'ac' defense_type when eligible")


func test_prehit_avoidance_offers_steel_when_eligible_vs_fortitude() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor(),
		"defense_type": "fortitude",
		"attack_context": {},
	})

	assert_eq(opened["legal_reactions"], ["steel"],
		"PreHitAvoidance must offer Steel (never Dodge) for a 'fortitude' defense_type when eligible")


func test_prehit_avoidance_withholds_dodge_when_reactor_immobilized() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor({"conditions": ["Immobilized"]}),
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], [],
		"PreHitAvoidance must never offer Dodge while the reactor is Immobilized (reuses is_dodge_eligible() verbatim)")


func test_prehit_avoidance_withholds_dodge_when_no_open_space() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor(),
		"defense_type": "reflex",
		"attack_context": {"open_space_available": false},
	})

	assert_eq(opened["legal_reactions"], [],
		"PreHitAvoidance must never offer Dodge when no open adjacent hex exists")


func test_prehit_avoidance_withholds_steel_when_reactor_unconscious() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor({"conscious": false}),
		"defense_type": "will",
		"attack_context": {},
	})

	assert_eq(opened["legal_reactions"], [],
		"PreHitAvoidance must never offer Steel while the reactor is unconscious")


func test_prehit_avoidance_never_offers_parry_or_block() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	# A reactor whose weapon is eligible for BOTH Parry and Block -- proving
	# PreHitAvoidance (unlike the pre-existing "WeaponAttack" trigger_type)
	# never includes them; they are strictly ON-HIT reactions, out of this
	# window's scope entirely.
	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor(),
		"weapon": {"parry_bonus": 4, "block_value": 3},
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], ["dodge"],
		"PreHitAvoidance must offer ONLY Dodge/Steel -- Parry/Block must never appear even when the reactor's weapon is eligible for them")


func test_prehit_avoidance_offers_nothing_when_defense_type_matches_neither() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	# No realistic defense_type ever makes BOTH is_dodge_eligible() and
	# is_steel_eligible() true at once (their defense_type domains are
	# mutually exclusive -- ["ac","reflex"] vs ["fortitude","will"]) -- an
	# unrecognized defense_type must offer neither.
	var opened: Dictionary = window.open({
		"trigger_type": "PreHitAvoidance",
		"reactor": _reactor(),
		"defense_type": "bogus",
		"attack_context": {"open_space_available": true},
	})

	assert_eq(opened["legal_reactions"], [],
		"an unrecognized defense_type must trigger neither Dodge nor Steel")


# ══════════════════════════════════════════════════════════════════════════
# Section B: open_and_resolve_prehit_avoidance()
# ══════════════════════════════════════════════════════════════════════════

func test_successful_dodge_short_circuits_before_any_on_hit_processing() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# mob_d20=16 -> mobility_check=16+mobility(1)=17. attack_d20=10 -> roll_total=15.
	# 15 < 17 -> Dodge SUCCEEDS: miss, defender steps, zero damage rolled.
	var resolution: SpyResolution = _resolution([16, 10])

	var outcome: Dictionary = window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "ac",
			"attack_context": {"open_space_available": true},
			"round_number": 3,
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "dodge")
	assert_false(outcome["hit"], "a successful Mobility check must miss")
	assert_true(outcome["defender_stepped"])
	assert_eq(outcome["damage_raw"], 0, "no damage roll is ever consumed on a Dodge-avoided attack")
	assert_true(outcome["short_circuited"], "a successful Dodge must short-circuit")
	assert_false(outcome["on_hit_suppressed"], "no on-hit reaction was even relevant -- the attack missed entirely")
	assert_true(outcome["reaction_spent"])

	assert_eq(resolution.resolve_to_hit_call_count, 1, "resolve_to_hit() must be invoked exactly once")
	assert_eq(resolution.apply_on_hit_defense_call_count, 0,
		"a successful Dodge must short-circuit BEFORE any on-hit/damage-mitigation phase (apply_on_hit_defense) ever runs")

	assert_eq(ae.get_remaining(), 6, "a triggered Dodge must spend exactly one reaction")

	assert_eq(sink.events.size(), 2)
	assert_true(sink.events[1] is RoundEventsClass.ReactionResolvedEvent)
	assert_eq(sink.events[1].choice, "dodge")
	assert_eq(sink.events[1].round, 3)


func test_failed_dodge_sets_on_hit_suppressed_and_still_resolves_the_hit() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# mob_d20=2 -> mobility_check=2+1=3. attack_d20=2 -> roll_total=2+3+2=7.
	# 7 >= 3 -> Dodge FAILS to protect: hit, no step, damage rolled. (7-3)=4
	# < 10 -- not a crit, so damage is a single-die roll, not the double-dice
	# crit formula.
	var resolution: SpyResolution = _resolution([2, 2], [4])

	var outcome: Dictionary = window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
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

	assert_eq(outcome["reaction_choice"], "dodge")
	assert_true(outcome["hit"], "a failed Dodge check must not prevent the hit")
	assert_false(outcome["defender_stepped"])
	assert_eq(outcome["damage_raw"], 7, "damage must still be computed normally on a Dodge-fail hit")
	assert_false(outcome["short_circuited"], "a failed Dodge must not short-circuit -- the Strike still hit")
	assert_true(outcome["on_hit_suppressed"],
		"a failed Dodge already spent the reactor's ONE reaction this Strike -- any subsequent on-hit window must be suppressed")
	assert_true(outcome["reaction_spent"])

	assert_eq(resolution.resolve_to_hit_call_count, 1)
	assert_eq(resolution.apply_on_hit_defense_call_count, 0,
		"open_and_resolve_prehit_avoidance() never itself calls apply_on_hit_defense() -- that is a later feature's (OnHitMitigation) responsibility")

	assert_eq(ae.get_remaining(), 6, "a failed-but-triggered Dodge still spends exactly one reaction")


func test_successful_steel_short_circuits() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# det_d20=16 -> determination_check=16+determination(1)=17. attack_d20=10 -> roll_total=15.
	# 15 < 17 -> Steel RESISTS: miss, next_check_bonus=2.
	var resolution: SpyResolution = _resolution([16, 10])

	var outcome: Dictionary = window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"defense_type": "fortitude",
			"attack_context": {},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "steel")
	assert_false(outcome["hit"])
	assert_eq(outcome["next_check_bonus"], 2)
	assert_true(outcome["short_circuited"])
	assert_false(outcome["on_hit_suppressed"])
	assert_eq(resolution.apply_on_hit_defense_call_count, 0)
	assert_eq(ae.get_remaining(), 6)


func test_pass_path_invokes_resolve_to_hit_and_leaves_on_hit_suppressed_false() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")

	# No Dodge check is ever rolled -- the passive "ac" defense (13) is used
	# directly. attack_d20=16 -> roll_total=16+3+2=21 >= 13 -> hit.
	var resolution: SpyResolution = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
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
		"declining every offered reaction must resolve the attack against passive AC only")
	assert_true(outcome["hit"])
	assert_eq(outcome["damage_raw"], 7)
	assert_false(outcome["short_circuited"])
	assert_false(outcome["on_hit_suppressed"])
	assert_false(outcome["reaction_spent"])

	assert_eq(resolution.resolve_to_hit_call_count, 1, "the Pass path must still invoke resolve_to_hit() exactly once, proceeding to a plain roll")
	assert_eq(resolution.apply_on_hit_defense_call_count, 0)
	assert_eq(ae.get_remaining(), 7, "declining every offered reaction must never spend a reaction")


func test_dodge_pays_via_spend_reaction_never_spend_action() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: SpyActionEconomy = SpyActionEconomy.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var resolution: SpyResolution = _resolution([16, 10])

	window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
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

	assert_eq(ae.spend_action_call_count, 0, "PreHitAvoidance must NEVER call ActionEconomy.spend_action()")
	assert_eq(ae.get_remaining(), 6)


func test_already_spent_reactor_never_opens_and_still_resolves_the_plain_roll() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.spend_reaction()
	assert_true(ae.is_spent(), "fixture: budget exhausted before this Strike")

	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	# No pre-hit check consumed -- window never opens -- straight to a plain
	# roll: attack_d20=16 -> roll_total=21 >= ac(13) -> hit.
	var resolution: SpyResolution = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_prehit_avoidance(
		{
			"trigger_type": "PreHitAvoidance",
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

	assert_eq(outcome["window_id"], "", "ALREADY_SPENT must never open a window")
	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_true(outcome["hit"])
	assert_eq(sink.events.size(), 0, "no event of any kind is emitted when the reactor was already Spent")


# ══════════════════════════════════════════════════════════════════════════
# Section C: core/application/round_session.gd integration
# ══════════════════════════════════════════════════════════════════════════

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


## ScriptedRandomNumberPort -- mirrors tests/gut/test_enemy_strike_reaction_window.gd's
## identically-named double, plus a `roll_call_count` so this suite can prove
## the PreHitAvoidance seam is awaited BEFORE any RNG draw happens (i.e.
## before any call in the chain ever reaches resolve_to_hit()'s own d20()/
## roll() consumption -- test_criteria #5).
class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var roll_call_count: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		roll_call_count += 1
		var v = _values[_index]
		_index += 1
		return v


## ScriptedPrehitAvoidanceResolver -- a ReactionResolverPort double
## (`async func(trigger) -> Dictionary`) for the NEW PreHitAvoidance seam.
## Records every trigger it was invoked with, AND the injected
## ScriptedRandomNumberPort's roll_call_count AT THE MOMENT it fires -- proof
## the window is awaited before any attack-roll RNG has been drawn.
class ScriptedPrehitAvoidanceResolver:
	extends RefCounted

	var result_to_return: Dictionary
	var calls: Array = []
	var _rng_spy

	func _init(result: Dictionary, rng_spy = null) -> void:
		result_to_return = result
		_rng_spy = rng_spy

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append({
			"trigger": trigger,
			"roll_call_count_at_invocation": _rng_spy.roll_call_count if _rng_spy != null else -1,
		})
		return result_to_return


## ScriptedReactionResolver -- the EXISTING WeaponAttack-window resolver
## double (mirrors tests/gut/test_enemy_strike_reaction_window.gd's
## identically-named class) -- used here purely to PROVE it is never invoked
## once the new PreHitAvoidance seam has already decided/suppressed a
## reaction for this Strike.
class ScriptedReactionResolver:
	extends RefCounted

	var choice_to_return: String
	var calls: Array = []

	func _init(choice: String) -> void:
		choice_to_return = choice

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		return {"choice": choice_to_return}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _rs_attacker() -> Dictionary:
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


func _rs_defender() -> Dictionary:
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


func _make_session(entries: Array, party: Array, enemies: Array, random_number_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var session = run_round_use_case.begin_round(1, party, enemies)
	return {"session": session, "history": round_history_port, "event_sink": event_sink_port}


func test_advance_ai_turn_awaits_prehit_avoidance_before_any_rng_draw() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# mob_d20=15 -> mobility_check=15+1=16. attack_d20=1 -> roll_total=6. Dodge succeeds.
	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]
	assert_eq(session.current_actor().get("name", ""), "Bravo")

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge"}, rng)
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(prehit_resolver.calls.size(), 1, "the PreHitAvoidance resolver must be awaited exactly once for this Strike")
	assert_eq(prehit_resolver.calls[0]["roll_call_count_at_invocation"], 0,
		"the PreHitAvoidance window must be awaited BEFORE any RNG roll() is drawn -- i.e. before resolve_to_hit() ever runs")


func test_successful_dodge_via_prehit_seam_negates_the_strike() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge"})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(rig["history"].entries.size(), 1, "exactly one Strike must be resolved")
	var attack_event = rig["event_sink"].events[0]
	assert_false(attack_event.hit, "a Dodge decided via the PreHitAvoidance seam must still negate the Strike")
	assert_eq(alpha.get("hp_current", 0), hp_before, "a negated Strike must deal zero damage")
	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1,
		"the DEFENDER's reaction must be spent exactly once"
	)


func test_dodge_decided_via_prehit_seam_skips_the_existing_weapon_attack_window() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# mob_d20=2 -> mobility_check=3. attack_d20=10 -> roll_total=13 -> hit
	# (Dodge fails to protect). damage die=4 -> damage_raw=4+3=7.
	var rng := ScriptedRandomNumberPort.new([2, 10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "dodge", "on_hit_suppressed": true})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	# If this legacy WeaponAttack resolver were ever invoked, it would offer
	# Block/Parry a SECOND reaction for the same Strike -- the ≤1 budget
	# invariant this feature protects.
	var weapon_attack_resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 0,
		"the existing WeaponAttack (on-hit) window must NEVER be asked once PreHitAvoidance already decided Dodge for this Strike")
	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1,
		"exactly ONE reaction (the Dodge) must be spent for this Strike -- never two"
	)
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "a failed Dodge must still resolve as a hit")


func test_prehit_on_hit_suppressed_alone_also_skips_the_existing_weapon_attack_window() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# No pre-hit check consumed (choice "none") -- straight to a plain roll:
	# attack_d20=10 -> roll_total=13 -> hit. damage die=4 -> damage_raw=7.
	var rng := ScriptedRandomNumberPort.new([10, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "none", "on_hit_suppressed": true})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	var weapon_attack_resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 0,
		"on_hit_suppressed reported by the PreHitAvoidance resolver must suppress the on-hit window even without an explicit dodge/steel choice")


func test_pass_via_prehit_seam_still_offers_the_existing_weapon_attack_window() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# attack_d20=10 -> roll_total=13 -> hit. damage die=4 -> damage_raw=7.
	# block-reduction die=3 -> block_reduction=3+block_value(2)=5 -> damage_final=2.
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var prehit_resolver := ScriptedPrehitAvoidanceResolver.new({"choice": "none"})
	session.set_prehit_avoidance_resolver_fn(Callable(prehit_resolver, "resolve"))

	var weapon_attack_resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 1,
		"declining the PreHitAvoidance offer (Pass) must still let the existing on-hit WeaponAttack window run")
	assert_eq(alpha.get("hp_current", 0), hp_before - 2, "Block chosen via the existing WeaponAttack window must still reduce damage as before")


func test_unset_prehit_seam_leaves_advance_ai_turn_byte_for_byte_unchanged() -> void:
	var bravo: Dictionary = _rs_attacker()
	var alpha: Dictionary = _rs_defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# mob_d20=15 -> mobility_check=16. attack_d20=1 -> roll_total=6. Dodge succeeds
	# via the PRE-EXISTING WeaponAttack window -- proving that never calling
	# set_prehit_avoidance_resolver_fn() (every pre-existing caller/test) is a
	# complete no-op (NFR-004): behavior is identical to
	# tests/gut/test_enemy_strike_reaction_window.gd's own Dodge scenario.
	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var weapon_attack_resolver := ScriptedReactionResolver.new("dodge")
	session.set_reaction_resolver_fn(Callable(weapon_attack_resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(weapon_attack_resolver.calls.size(), 1,
		"with no PreHitAvoidance resolver injected, the existing WeaponAttack window must still be asked exactly as before")
	var attack_event = rig["event_sink"].events[0]
	assert_false(attack_event.hit)
	assert_eq(alpha.get("hp_current", 0), hp_before)
	assert_eq(entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1)
