extends GutTest
## tests/gut/test_enemy_strike_reaction_window.gd
##
## GUT suite for FEAT-004 (US-003 / FR-003, ADR-004): opening the
## defender's reaction window on the enemy-strikes-player path and
## resolving the chosen reaction.
##
## Prior features built every piece this feature wires together:
##   - FEAT-001 (tests/gut/test_resolve_action_use_case_active_defense.gd)
##     threaded active_defense/defense_context trailing parameters through
##     ResolveActionUseCase.resolve()/_resolve_strike() as a verbatim
##     pass-through into core/rules/resolution.gd's resolve_weapon_attack().
##   - FEAT-002/FEAT-003 (tests/gut/test_round_session_reaction_resolver_injection.gd,
##     tests/gut/test_async_reaction_propagation.gd) built and proved the
##     ReactionResolverPort Callable seam on RoundSession
##     (set_reaction_resolver_fn()/_resolve_reaction()) -- an injected
##     resolver is genuinely `await`ed before a Strike resolves, with no
##     deadlock/double-advance, and a byte-for-byte-unchanged synchronous
##     fallback when nothing is injected.
##
## This feature closes the gap those left open: RoundSession.advance_ai_turn()
## now ACTS on the resolver's answer -- it builds a ReactionTrigger (carrying
## the attacker/target combatants, defense_type "ac", attack_context, the
## defender's OWN live ActionEconomy, and the round number), awaits the
## injected resolver, builds a DefenseContext (the defender's ActionEconomy
## plus its own weapon as both parrying_weapon/blocking_weapon, and a
## default-safe open_space_available), and threads the resolved
## active_defense + DefenseContext into ResolveActionUseCase.resolve() --
## the SAME resolve()/resolution.gd pipeline every other reaction-enabled
## call site in this codebase already exercises. RoundSession itself never
## re-implements Dodge/Block/Parry/Steel math, never re-derives reaction
## eligibility, and never spends a reaction directly -- resolution.gd (via
## ActionEconomy.spend_reaction()) remains the sole place either happens.
##
## Verifies (test_criteria):
##   1. Dodge negates the Strike (hit=false / damage=0), per resolution.gd's
##      own Mobility-check math -- never re-derived by this suite.
##   2. Block reduces damage per resolution.gd's own math, using the
##      DEFENDER's OWN weapon as the resolved blocking_weapon.
##   3. A Parry roll that beats the attacker's roll_total zeroes damage,
##      using the DEFENDER's OWN weapon as the resolved parrying_weapon.
##   4. Steel remains illegal/dormant for a weapon Strike vs AC: reaction_
##      window.gd's OWN, unmodified legality gate (is_steel_eligible() via
##      ReactionWindow.open()) never offers it, and even if a
##      misbehaving/malicious resolver answers "steel" anyway, resolution.gd
##      treats it as a no-op (byte-identical to Pass) rather than crashing or
##      mutating budget.
##   5. Pass reproduces the EXACT pre-sprint unreacted outcome -- the
##      round_session-mediated path with choice "none" is byte-for-byte
##      identical to calling resolve() directly with its pre-FEAT-001
##      default arguments, given the identical RNG sequence (the
##      characterization baseline's own contract).
##   6. ActionEconomy.spend_reaction() fires on the DEFENDER for every
##      non-Pass chosen reaction (Dodge/Block/Parry), and is never invoked
##      for Pass/Steel-on-AC.
##   7. Legality is established via core/application/reaction_window.gd's
##      OWN, unmodified open() gate -- this suite never re-implements or
##      bypasses is_dodge_eligible()/is_block_eligible()/is_parry_eligible()/
##      is_steel_eligible().

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double port implementations (mirrors tests/gut/
#    test_round_session_reaction_resolver_injection.gd's identically-named
#    doubles) ──────────────────────────────────────────────────────────────

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


## ScriptedRandomNumberPort -- mirrors tests/gut/
## test_resolve_action_use_case_active_defense.gd's identically-named double:
## returns pre-scripted values from `roll(dice_spec)` in call order, so every
## RNG draw across the pre-attack/attack/damage/block/parry sequence
## (core/rules/resolution.gd's own documented "RNG consumption order") is
## fully deterministic and independently controllable per scenario.
class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## ScriptedReactionResolver -- a ReactionResolverPort double
## (`async func(trigger: Dictionary) -> Dictionary`) that always answers
## with a fixed, pre-scripted choice, recording every trigger it was
## invoked with (so this suite can assert on the ReactionTrigger's shape
## alongside the mechanical Strike outcome).
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


## _attacker() -- the enemy (Bravo). roll_total = raw_d20 + strength(3) +
## proficiency_bonus(2) = raw_d20 + 5.
func _attacker() -> Dictionary:
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


## _defender() -- the player (Alpha). Carries a single weapon eligible for
## BOTH Parry (parry_bonus 3) and Block (block_value 2), and a Mobility
## skill Dodge's substituted defense value is computed from -- exactly the
## shape RoundSession._build_defense_context() resolves parrying_weapon/
## blocking_weapon from (this project's combatant model has one weapon
## slot, not a separate loadout).
func _defender() -> Dictionary:
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


## _make_session(entries, party, enemies, random_number_port) -> Dictionary
## -- builds a fully-wired, REAL RunRoundUseCase (the SAME production
## resolve_action_use_case/AIClass pipeline every other RoundSession suite in
## this codebase exercises) atop the given scripted RNG, and begins round 1.
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


## _reaction_window_trigger(trigger_type, reactor, weapon) -> Dictionary --
## the shape core/application/reaction_window.gd's OWN open() expects (see
## that file's own doc). Built independently of RoundSession's
## ReactionTrigger so this suite can exercise reaction_window.gd's
## eligibility gate directly and unmodified (test_criteria #7), the way a
## real resolver (presentation/turn_controller.gd's resolve_reaction())
## would when translating a RoundSession-issued trigger into a live
## reaction-window prompt.
func _reaction_window_trigger(trigger_type: String, reactor: Dictionary, weapon: Dictionary) -> Dictionary:
	return {
		"trigger_type":   trigger_type,
		"reactor":        reactor,
		"weapon":         weapon,
		"defense_type":   "ac",
		"attack_context": {},
		"round_number":   1,
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 + 6 + 7: Dodge negates the Strike, spends the defender's
# reaction, and was offered as legal per reaction_window.gd's own gate.
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_reaction_negates_the_strike_and_spends_defenders_reaction() -> void:
	var bravo: Dictionary = _attacker()
	var alpha: Dictionary = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# test_criteria #7: legality established via reaction_window.gd's OWN,
	# unmodified gate -- never re-derived by this suite.
	var event_sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(event_sink)
	var opened: Dictionary = window.open(_reaction_window_trigger("Dodge", alpha, alpha["weapon"]))
	assert_eq(opened.get("legal_reactions", []), ["dodge"], "Dodge must be legal per reaction_window.gd's own is_dodge_eligible() gate for this fixture (not Immobilized, open space)")

	# RNG order (resolution.gd doc): [1] Mobility check d20, [2] attack d20.
	# Mobility check (15 + skill 1 = 16) STRICTLY beats the attack roll
	# (1 + 5 = 6) -> Dodge succeeds, attack misses, zero damage rolled.
	var rng := ScriptedRandomNumberPort.new([15, 1])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]
	assert_eq(session.current_actor().get("name", ""), "Bravo", "fixture assumption: the Enemy leads the turn order")

	var resolver := ScriptedReactionResolver.new("dodge")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(resolver.calls.size(), 1, "the injected resolver must be awaited exactly once for this Strike")
	assert_eq(rig["history"].entries.size(), 1, "exactly one Strike must be resolved")

	var attack_event = rig["event_sink"].events[0]
	assert_false(attack_event.hit, "PINNED (resolution.gd Dodge math): the successful Mobility check must cause a miss")
	assert_eq(alpha.get("hp_current", 0), hp_before, "a negated (missed) Strike must deal zero damage")

	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1,
		"ActionEconomy.spend_reaction() must fire on the DEFENDER for a chosen Dodge"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 6 + 7: Block reduces damage per resolution.gd's math using
# the defender's OWN resolved blocking_weapon, and spends its reaction.
# ══════════════════════════════════════════════════════════════════════════

func test_block_reaction_reduces_damage_using_the_resolved_blocking_weapon() -> void:
	var bravo: Dictionary = _attacker()
	var alpha: Dictionary = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var event_sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(event_sink)
	var opened: Dictionary = window.open(_reaction_window_trigger("Block", alpha, alpha["weapon"]))
	assert_eq(opened.get("legal_reactions", []), ["block"], "Block must be legal per reaction_window.gd's own is_block_eligible() gate for this fixture (weapon.block_value > 0)")

	# RNG order: [1] attack d20 (10 -> roll_total 15, hits ac 10, not a
	# crit), [2] damage die (4 -> damage_raw = 4 + strength(3) = 7),
	# [3] block-reduction die (3 -> block_reduction = 3 + block_value(2) = 5).
	# damage_final = max(0, 7 - 5) = 2.
	var rng := ScriptedRandomNumberPort.new([10, 4, 3])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := ScriptedReactionResolver.new("block")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(rig["history"].entries.size(), 1)
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "fixture assumption: the attack roll must hit for Block's post-hit branch to trigger")
	assert_eq(attack_event.damage_final, 2, "PINNED (resolution.gd Block math using Alpha's OWN weapon: block_die=6 fallback, tier 1, block_value 2): damage_raw(7) - block_reduction(5) = 2")
	assert_eq(hp_before - alpha.get("hp_current", 0), 2, "the defender's HP must drop by exactly the Block-reduced damage")

	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1,
		"ActionEconomy.spend_reaction() must fire on the DEFENDER for a chosen Block"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 + 6 + 7: a Parry roll that beats the attacker's roll_total
# zeroes damage using the defender's OWN resolved parrying_weapon, and
# spends its reaction.
# ══════════════════════════════════════════════════════════════════════════

func test_parry_beats_roll_zeroes_damage_using_the_resolved_parrying_weapon() -> void:
	var bravo: Dictionary = _attacker()
	var alpha: Dictionary = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var event_sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(event_sink)
	var opened: Dictionary = window.open(_reaction_window_trigger("Parry", alpha, alpha["weapon"]))
	assert_eq(opened.get("legal_reactions", []), ["parry"], "Parry must be legal per reaction_window.gd's own is_parry_eligible() gate for this fixture (weapon.parry_bonus > 0)")

	# RNG order: [1] attack d20 (10 -> roll_total 15, hits), [2] damage die
	# (4 -> damage_raw = 7), [3] parry d20 (15 -> parry_roll = 15 +
	# parry_bonus(3) = 18, STRICTLY exceeds roll_total 15 -> Parry succeeds).
	var rng := ScriptedRandomNumberPort.new([10, 4, 15])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := ScriptedReactionResolver.new("parry")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(rig["history"].entries.size(), 1)
	var attack_event = rig["event_sink"].events[0]
	assert_true(attack_event.hit, "fixture assumption: the attack roll must hit for Parry's post-hit branch to trigger")
	assert_eq(attack_event.damage_final, 0, "PINNED (resolution.gd Parry math): a strict-exceed parry roll must zero damage_final")
	assert_eq(alpha.get("hp_current", 0), hp_before, "a successfully-parried Strike must deal zero damage")

	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before - 1,
		"ActionEconomy.spend_reaction() must fire on the DEFENDER for a chosen Parry"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: Steel remains illegal/dormant for a weapon Strike vs AC.
# ══════════════════════════════════════════════════════════════════════════

func test_steel_is_never_offered_as_legal_by_reaction_window_and_stays_dormant_if_chosen_anyway() -> void:
	var alpha: Dictionary = _defender()

	# reaction_window.gd's OWN, unmodified legality gate: Steel requires
	# defense_type in [fortitude, will] -- a weapon Strike vs AC can NEVER
	# legalize it, regardless of the reactor's own state.
	var event_sink := FakeEventSinkPort.new()
	var window := ReactionWindowClass.new(event_sink)
	var opened: Dictionary = window.open(_reaction_window_trigger("Steel", alpha, alpha["weapon"]))
	assert_eq(opened.get("legal_reactions", []), [], "Steel must NEVER be legal for an 'ac' defense_type, per reaction_window.gd's own is_steel_eligible() gate")

	# Defense in depth: even if a misbehaving/malicious resolver answers
	# "steel" anyway, RoundSession forwards it verbatim (it never re-filters
	# a resolver's answer against legal_reactions itself -- that legality
	# check belongs solely to reaction_window.gd/resolution.gd), but
	# resolution.gd's own math must treat it as a complete no-op: byte-
	# identical to Pass, given the identical RNG sequence, with no reaction
	# spent.
	var bravo_a: Dictionary = _attacker()
	var alpha_a: Dictionary = _defender()
	var entries_a: Array = [_entry(bravo_a), _entry(alpha_a)]
	var rng_a := ScriptedRandomNumberPort.new([10, 4])
	var rig_a: Dictionary = _make_session(entries_a, [alpha_a], [bravo_a], rng_a)
	var resolver_a := ScriptedReactionResolver.new("steel")
	rig_a["session"].set_reaction_resolver_fn(Callable(resolver_a, "resolve"))
	var alpha_a_budget_before: int = entries_a[1]["action_economy"].get_remaining()
	await rig_a["session"].advance_ai_turn()
	var steel_event = rig_a["event_sink"].events[0]

	var bravo_b: Dictionary = _attacker()
	var alpha_b: Dictionary = _defender()
	var entries_b: Array = [_entry(bravo_b), _entry(alpha_b)]
	var rng_b := ScriptedRandomNumberPort.new([10, 4])
	var rig_b: Dictionary = _make_session(entries_b, [alpha_b], [bravo_b], rng_b)
	var resolver_b := ScriptedReactionResolver.new("none")
	rig_b["session"].set_reaction_resolver_fn(Callable(resolver_b, "resolve"))
	await rig_b["session"].advance_ai_turn()
	var pass_event = rig_b["event_sink"].events[0]

	assert_eq(steel_event.hit, pass_event.hit, "an (illegally) chosen Steel against an 'ac' Strike must resolve identically to Pass")
	assert_eq(steel_event.damage_final, pass_event.damage_final, "an (illegally) chosen Steel against an 'ac' Strike must deal identical damage to Pass")
	assert_eq(
		entries_a[1]["action_economy"].get_remaining(), alpha_a_budget_before,
		"Steel must never spend the defender's reaction when it is dormant (defense_type 'ac')"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: Pass reproduces the exact pre-sprint unreacted outcome --
# matches the characterization baseline (resolve()'s pre-FEAT-001 default
# arguments), given the identical RNG sequence.
# ══════════════════════════════════════════════════════════════════════════

func test_pass_reproduces_the_exact_pre_sprint_unreacted_outcome() -> void:
	var bravo: Dictionary = _attacker()
	var alpha: Dictionary = _defender()
	var entries: Array = [_entry(bravo), _entry(alpha)]

	# RNG order for an unreacted Strike: [1] attack d20, [2] damage die.
	var rng := ScriptedRandomNumberPort.new([15, 4])
	var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
	var session = rig["session"]

	var resolver := ScriptedReactionResolver.new("none")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var alpha_budget_before: int = entries[1]["action_economy"].get_remaining()
	var hp_before: int = alpha.get("hp_current", 0)

	await session.advance_ai_turn()

	assert_eq(rig["history"].entries.size(), 1)
	var reacted_event = rig["event_sink"].events[0]

	# Independently resolve the IDENTICAL Strike via resolve_action_use_case
	# directly, with resolve()'s pre-FEAT-001 default-only arguments (no
	# active_defense/defense_context) -- the characterization baseline this
	# criterion pins against -- fed the SAME scripted RNG sequence.
	var baseline_attacker: Dictionary = _attacker()
	var baseline_target: Dictionary = _defender()
	var baseline_rng := ScriptedRandomNumberPort.new([15, 4])
	var baseline_event_sink := FakeEventSinkPort.new()
	var baseline_history := FakeRoundHistoryPort.new()
	var baseline_use_case := ResolveActionUseCaseClass.new(baseline_rng, baseline_event_sink, baseline_history)
	var baseline_action_economy := ActionEconomyClass.new()
	baseline_action_economy.start_of_round()

	var baseline_result: Dictionary = baseline_use_case.resolve(
		baseline_attacker, baseline_action_economy, baseline_target, "Strike", 1, 0
	)

	assert_true(baseline_result.get("ok", false))
	var baseline_event = baseline_result["event"]

	assert_eq(reacted_event.hit, baseline_event.hit, "Pass through the round_session reaction window must match the pre-sprint (default-args) hit outcome exactly")
	assert_eq(reacted_event.damage_final, baseline_event.damage_final, "Pass through the round_session reaction window must match the pre-sprint (default-args) damage exactly")
	assert_eq(alpha.get("hp_current", 0), hp_before - baseline_event.damage_final, "the defender's HP must drop by exactly the baseline's damage")

	assert_eq(
		entries[1]["action_economy"].get_remaining(), alpha_budget_before,
		"Pass must never spend the defender's reaction"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 6 (consolidated): every non-Pass chosen reaction spends the
# defender's reaction; Pass never does -- proven per-scenario above; this
# test additionally confirms spend_action() (the ATTACKER's own budget) is
# always exactly one, unaffected by whichever reaction the defender chose.
# ══════════════════════════════════════════════════════════════════════════

func test_attackers_own_action_budget_is_unaffected_by_the_defenders_chosen_reaction() -> void:
	for choice in ["none", "dodge", "block", "parry"]:
		var bravo: Dictionary = _attacker()
		var alpha: Dictionary = _defender()
		var entries: Array = [_entry(bravo), _entry(alpha)]
		var rng := ScriptedRandomNumberPort.new([1, 1, 1, 1, 1, 1])
		var rig: Dictionary = _make_session(entries, [alpha], [bravo], rng)
		var resolver := ScriptedReactionResolver.new(choice)
		rig["session"].set_reaction_resolver_fn(Callable(resolver, "resolve"))

		var bravo_budget_before: int = entries[0]["action_economy"].get_remaining()
		await rig["session"].advance_ai_turn()

		assert_eq(
			entries[0]["action_economy"].get_remaining(), bravo_budget_before - 1,
			"the ATTACKER must always spend exactly one action for its own Strike, regardless of the defender's reaction choice ('%s')" % choice
		)
