extends GutTest
## tests/unit/test_block_reaction.gd
##
## GUT test suite for FEAT-206 (US-012 / FR-012, ADR-016): wiring the Block
## reaction into LIVE play — the THIRD live, player-triggerable reaction on
## the steel thread's pop-up surface (FEAT-010 wired Dodge, FEAT-205 wired
## Parry).
##
## core/rules/resolution.gd (FEAT-059) already fully implements Block's
## post-hit math: a hit by a weapon attack vs AC, when the reactor wields a
## weapon with block_value > 0, reduces damage by
## roll(block_die|damage_die, tier) + block_value, floored at 0
## (on_hit_suppressed=true). core/application/reaction_window.gd (FEAT-009)
## already exposes Resolution.is_block_eligible() via its "Block"
## trigger_type branch and already delegates the ENTIRE attack — including
## whatever trigger["attack_context"] carries (e.g. "blocking_weapon",
## "blocking_weapon_tier") — to the injected Resolution instance via
## open_and_resolve_attack(). This feature closes the gap FEAT-205's own doc
## identified: proving that hand-off ACTUALLY reaches resolution.gd's Block
## branch end-to-end, headlessly, via AutoReactionChooser — exactly as
## FEAT-010/FEAT-205 proved for Dodge/Parry.
##
## Verifies (this feature's test_criteria):
##   1. The Block trigger fires only when the reactor wields a weapon with
##      block_value > 0 AND is hit by a weapon attack vs AC.
##   2. damage reduction = roll(block_die|damage_die, tier) + block_value,
##      floored at 0.
##   3. The Block reaction pays via ActionEconomy.spend_reaction();
##      spend_action() is never called.
##   4. A headless test verifies the Block damage-reduction outcome is
##      reachable via AutoReactionChooser (infrastructure/
##      auto_reaction_chooser.gd) with no UI present.

const ReactionWindowClass      = preload("res://core/application/reaction_window.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ResolutionClass          = preload("res://core/rules/resolution.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")
const CombatantClass           = preload("res://core/domain/combatant.gd")


# ── Fake/double EventSinkPort (mirrors tests/unit/test_parry_reaction.gd's
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


## SequenceRNG — multi-step RNG stub mirroring tests/unit/test_parry_reaction.gd's
## own SequenceRNG: returns successive values from pre-set d20/roll sequences.
## Block's RNG consumption order (per resolution.gd's doc) is:
##   1. _rng.d20()     — attacker's attack roll
##   2. _rng.roll(...) — damage roll (hit only)
##   3. _rng.roll(...) — block-reduction roll (post-hit, Block only)
## All draw from the SAME d20_seq/roll_seq pools in call order.
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


## The reactor's OWN blocking weapon — used both for eligibility
## (trigger["weapon"]) and, duplicated into trigger["attack_context"] as
## "blocking_weapon", for resolution.gd's actual post-hit block roll.
func _blocking_weapon(block_value: int = 3) -> Dictionary:
	return {"damage_die": 6, "parry_bonus": 0, "block_value": block_value}


func _window() -> Dictionary:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	return {"window": window, "sink": sink}


func _resolution(d20_seq: Array, roll_seq: Array = []) -> ResolutionClass:
	return ResolutionClass.new(SequenceRNG.new(d20_seq, roll_seq))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Block trigger fires only when the reactor wields a weapon
# with block_value > 0 and is hit by a weapon attack vs AC
# ══════════════════════════════════════════════════════════════════════════

func test_block_offered_when_weapon_has_block_value() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor": _reactor(),
		"weapon": _blocking_weapon(3),
		"defense_type": "ac",
	})

	assert_eq(opened["legal_reactions"], ["block"],
		"Block must be offered when the reactor's weapon has block_value > 0")


func test_block_withheld_when_weapon_has_no_block_value() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var opened: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor": _reactor(),
		"weapon": _blocking_weapon(0),
		"defense_type": "ac",
	})

	assert_eq(opened["legal_reactions"], [],
		"Block must never be offered when the reactor's weapon has block_value == 0")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 + 4: damage reduction = roll(block_die|damage_die, tier) +
# block_value, floored at 0, driven headlessly via AutoReactionChooser
# (no UI present)
# ══════════════════════════════════════════════════════════════════════════

func test_block_via_auto_chooser_reduces_damage_by_roll_plus_block_value() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var blocking_weapon: Dictionary = _blocking_weapon(3)

	# attack_d20=11 → roll_total = 11 + strength(3) + prof(2) = 16 → hits ac(13)
	# damage_die roll=4 → damage_raw = 4 + strength(3) = 7
	# block roll(6,1)=2 → block_reduction = 2 + block_value(3) = 5
	# damage_final = max(0, 7 - 5) = 2
	var resolution: ResolutionClass = _resolution([11], [4, 2])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], "block",
		"AutoReactionChooser's first_legal policy must pick the offered 'block' reaction")
	assert_eq(outcome["active_defense_applied"], "block")
	assert_true(outcome["hit"], "the underlying attack still hits AC")
	assert_true(outcome["on_hit_suppressed"], "a successful Block must set on_hit_suppressed=true")
	assert_eq(outcome["damage_raw"], 7, "damage_raw still reflects the unreduced roll for observability")
	assert_eq(outcome["damage_final"], 2, "damage_final = max(0, damage_raw - (block_roll + block_value))")


## Damage reduction is floored at 0 — it must never go negative even when
## the block roll comfortably exceeds the raw damage.
func test_block_damage_reduction_is_floored_at_zero() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var blocking_weapon: Dictionary = _blocking_weapon(10)

	# attack_d20=11 → roll_total = 16 → hits ac(13)
	# damage_die roll=4 → damage_raw = 7
	# block roll(6,1)=6 → block_reduction = 6 + block_value(10) = 16 >> damage_raw
	var resolution: ResolutionClass = _resolution([11], [4, 6])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["damage_final"], 0, "damage reduction must be floored at 0, never negative")
	assert_true(outcome["on_hit_suppressed"])


## Tier scaling: a tier-2 blocking weapon rolls the block die TWICE (2[W]).
func test_block_tier_scales_the_block_die_roll_count() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var blocking_weapon: Dictionary = _blocking_weapon(3)

	# attack_d20=11 → roll_total = 16 → hits ac(13)
	# damage_die roll=4 → damage_raw = 7
	# tier-2 block roll(6,2)=5 (SequenceRNG ignores die_size/count — it only
	# proves resolution.gd forwarded blocking_weapon_tier through to
	# _rng.roll()) → block_reduction = 5 + block_value(3) = 8
	var resolution: ResolutionClass = _resolution([11], [4, 5])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {
				"blocking_weapon": blocking_weapon,
				"blocking_weapon_tier": 2,
			},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["damage_final"], 0, "max(0, 7 - 8) = 0")


func test_block_pass_policy_never_triggers_the_reaction() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("pass")
	var blocking_weapon: Dictionary = _blocking_weapon(3)

	# No block roll is ever consumed — attack resolves against passive ac
	# only. attack_d20=11 → roll_total=16 >= 13 → hit; damage_raw=7.
	var resolution: ResolutionClass = _resolution([11], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(outcome["reaction_choice"], ReactionChooserPortClass.PASS)
	assert_eq(outcome["active_defense_applied"], "none",
		"declining the Block offer must resolve the attack against passive AC only, with no reduction")
	assert_false(outcome["on_hit_suppressed"])
	assert_eq(outcome["damage_final"], 7)
	assert_eq(ae.get_remaining(), 7, "declining the reaction must never spend a reaction")


## A Block offer against a non-AC defense_type (e.g. Fortitude) must never
## reduce damage — Block is strictly a weapon-attack-vs-AC reaction
## (test_criteria #1).
func test_block_does_not_apply_for_non_ac_defense_type() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var blocking_weapon: Dictionary = _blocking_weapon(3)
	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var resolution: ResolutionClass = _resolution([16], [4])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "fortitude",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	# _compute_legal_reactions("Block") only inspects weapon.block_value, so
	# eligibility here is unaffected by defense_type — but resolution.gd's
	# own Block branch only ever triggers when defense_type == "ac", so even
	# though the window is willing to offer/spend the reaction, the roll
	# never applies against a non-AC defense.
	assert_eq(outcome["active_defense_applied"], "none",
		"resolution.gd's Block branch never fires against a non-AC defense_type")
	assert_false(outcome["on_hit_suppressed"])
	assert_eq(outcome["damage_final"], 7)


func test_block_does_not_apply_on_miss() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var blocking_weapon: Dictionary = _blocking_weapon(3)
	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")

	# attack_d20=1 → roll_total = 1 + 3 + 2 = 6 < ac(13) → miss.
	var resolution: ResolutionClass = _resolution([1])

	var outcome: Dictionary = window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_false(outcome["hit"], "the attack must miss for this fixture")
	assert_eq(outcome["active_defense_applied"], "none",
		"Block never applies on a miss — the trigger requires being HIT")
	assert_eq(outcome["damage_final"], 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the Block reaction pays via spend_reaction(); spend_action()
# is NEVER called
# ══════════════════════════════════════════════════════════════════════════

func test_block_pays_via_spend_reaction_never_spend_action() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]

	var ae: SpyActionEconomy = SpyActionEconomy.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var blocking_weapon: Dictionary = _blocking_weapon(3)
	var resolution: ResolutionClass = _resolution([11], [4, 2])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
		},
		resolution,
		_attacker,
		_weapon,
		chooser
	)

	assert_eq(ae.spend_action_call_count, 0,
		"the Block reaction must NEVER call ActionEconomy.spend_action()")
	assert_eq(ae.get_remaining(), 6,
		"the Block reaction must spend exactly one reaction via spend_reaction()")
	assert_true(ae.can_take_action(),
		"spend_reaction() must not trip the per-turn spend_action() gate")


func test_block_reaction_resolved_event_emitted_with_block_choice() -> void:
	var built: Dictionary = _window()
	var window: ReactionWindowClass = built["window"]
	var sink: FakeEventSinkPort = built["sink"]

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var chooser: AutoReactionChooserClass = AutoReactionChooserClass.new("first_legal")
	var blocking_weapon: Dictionary = _blocking_weapon(3)
	var resolution: ResolutionClass = _resolution([11], [4, 2])

	window.open_and_resolve_attack(
		{
			"trigger_type": "Block",
			"reactor": _reactor(),
			"reactor_action_economy": ae,
			"weapon": blocking_weapon,
			"defense_type": "ac",
			"attack_context": {"blocking_weapon": blocking_weapon},
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
	assert_eq(resolved_event.choice, "block")
	assert_eq(resolved_event.resolved_by, "ai_policy")
