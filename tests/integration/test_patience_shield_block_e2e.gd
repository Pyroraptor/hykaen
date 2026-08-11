extends GutTest
## tests/integration/test_patience_shield_block_e2e.gd — FEAT-397 (US-011 /
## FR-012).
##
## END-TO-END STEEL THREAD: exercises the COMPLETE "Patience equips a
## shield" pipeline from raw .tres data through to the rendered
## reaction-prompt buttons, proving every layer boundary this iteration's
## design notes describe is actually wired together, in ONE test:
##   DATA         -> data/characters/dwarf_channeler.tres,
##                   data/weapons/{mace,small_shield}.tres
##   INFRASTRUCTURE -> infrastructure/combatant_factory.gd
##                   (CombatantFactory.build_party_combatant())
##   APPLICATION  -> core/application/round_session.gd
##                   (_build_reaction_trigger(), _build_defense_context())
##                   and core/application/reaction_window.gd
##                   (_compute_legal_reactions())
##   PRESENTATION -> scenes/ui/reaction_prompt_ui.gd (ReactionPromptUI.open_prompt())
##
## Entry point: CombatantFactory.build_party_combatant() on
## dwarf_channeler.tres. Exit point: rendered 'Block (Small Shield 1d10+4)'
## and 'Parry (Mace +1)' Buttons, both legal, both keyed by their bare
## reaction id.
##
## Unlike the pre-existing per-layer suites this steel thread depends on
## (tests/unit/infrastructure/test_combatant_factory.gd,
## tests/unit/core/application/test_round_session.gd,
## tests/unit/application/test_reaction_window.gd,
## tests/unit/ui/test_reaction_prompt_ui.gd — each of which verifies ONE
## layer in isolation, several using a hand-authored context/trigger
## stand-in), THIS test never hand-authors a defense-context dict or a
## trigger dict: every value flows from the ACTUAL CombatantFactory build of
## the ACTUAL dwarf_channeler.tres resource, through the ACTUAL
## RoundSession/ReactionWindow instance methods, into the ACTUAL
## ReactionPromptUI scene.
##
## Verifies (this feature's test_criteria):
##   1. build_party_combatant() on dwarf_channeler.tres yields
##      weapons.size()==2 and weapons[1].block_die==10.
##   2. _build_defense_context() for the built Patience combatant yields
##      blocking_weapon.block_die==10 and block_weapon_name=='Small Shield'.
##   3. _compute_legal_reactions() on the trigger built from Patience's
##      combatant yields both 'block' and 'parry' in legal_reactions.
##   4. The reaction prompt opened with this legal_reactions/context pair
##      renders a block button whose label contains 'Small Shield' and a
##      parry button whose label contains 'Mace'.
##   5. Both buttons are legal (present in legal_reactions) and map to bare
##      reaction ids in _buttons, not enriched label strings.

const CombatantFactoryClass        = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")
const ReactionPromptUIScene        = preload("res://scenes/ui/reaction_prompt_ui.tscn")

const DWARF_CHANNELER_PATH: String = "res://data/characters/dwarf_channeler.tres"


# ── Minimal fake port doubles -- mirrors tests/unit/core/application/
#    test_round_session.gd's established rig convention. Their sole purpose
#    here is to allow constructing a REAL RoundSession instance so this
#    test can exercise its REAL _build_reaction_trigger()/
#    _build_defense_context() instance methods; the round's own
#    cursor/turn-order/event-emission behavior is irrelevant to this
#    steel thread. ─────────────────────────────────────────────────────────

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	func emit(_event) -> void:
		pass


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	func append(_entry: Dictionary) -> void:
		pass

	func get_history() -> Array:
		return []


class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


func _durable_attacker():
	return CombatantClass.from_dict({
		"name":         "Attacker",
		"combatant_id": "attacker_1",
		"hp_current":   20,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    true,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	})


## _round_session_for_trigger_tests(alpha) — builds a minimally-wired, REAL
## RoundSession (via a REAL RunRoundUseCase.begin_round(), exactly mirroring
## tests/unit/core/application/test_round_session.gd's own
## _session_for_trigger_tests() helper) whose sole purpose here is to expose
## the REAL _build_reaction_trigger()/_build_defense_context() instance
## methods under test.
func _round_session_for_trigger_tests(alpha):
	var entries: Array = [{"combatant": alpha, "action_economy": ActionEconomyClass.new()}]
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()
	var random_number_port = SeededRandomAdapterClass.new(1)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, FakeAIDecisionPort.new(),
		resolve_action_use_case, determine_outcome_use_case
	)
	return run_round_use_case.begin_round(1, [alpha], [])


func test_patience_shield_block_reaction_prompt_end_to_end() -> void:
	# ── ENTRY POINT (DATA -> INFRASTRUCTURE): CombatantFactory
	# .build_party_combatant() on Patience's REAL character resource, walking
	# her REAL starting_equipment ([mace.tres, small_shield.tres,
	# chain_shirt.tres]) -- not a hand-authored stand-in.
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_party_combatant(DWARF_CHANNELER_PATH, null, "patience_1")

	assert_false(combatant_dict.has("error"), "dwarf_channeler.tres must build without error")
	var weapons: Array = combatant_dict.get("weapons", [])
	assert_eq(weapons.size(), 2, "Patience must have 2 weapons: mace (primary) + small shield (off-hand)")
	assert_eq(
		(weapons[1] as Dictionary).get("block_die", -1), 10,
		"weapons[1] (Small Shield) block_die must be 10"
	)

	var patience = CombatantClass.from_dict(combatant_dict)
	assert_eq(patience.weapons.size(), 2, "Patience entity must carry the same 2-weapon loadout")

	# ── APPLICATION: core/application/round_session.gd's REAL
	# _build_defense_context() -- best-weapon selection over Patience's REAL
	# weapons array (not a hand-authored context dict).
	var attacker = _durable_attacker()
	var session = _round_session_for_trigger_tests(attacker)
	var target_action_economy := ActionEconomyClass.new()

	var defense_context: Dictionary = session._build_defense_context(patience, target_action_economy)

	assert_eq(
		defense_context["blocking_weapon"].get("block_die", -1), 10,
		"blocking_weapon must be the small shield (block_die 10)"
	)
	assert_eq(defense_context["block_weapon_name"], "Small Shield")

	# ── APPLICATION: core/application/round_session.gd's REAL
	# _build_reaction_trigger() -- the trigger a live enemy Strike against
	# Patience actually opens, carrying her REAL 2-element weapons array.
	var trigger: Dictionary = session._build_reaction_trigger(attacker, patience)
	assert_eq(
		trigger["weapons"], patience.weapons,
		"trigger['weapons'] must reflect Patience's real 2-weapon loadout"
	)

	# ── APPLICATION: core/application/reaction_window.gd's REAL
	# _compute_legal_reactions() -- both Parry (mace) and Block (shield) must
	# be legal for this trigger, proving multi-weapon eligibility is wired
	# through from the real data.
	var window := ReactionWindowClass.new(FakeEventSinkPort.new())
	var legal_reactions: Array = window._compute_legal_reactions(trigger)

	assert_true(legal_reactions.has("block"), "Small Shield must make 'block' a legal reaction")
	assert_true(legal_reactions.has("parry"), "Mace must make 'parry' a legal reaction")

	# ── EXIT POINT (PRESENTATION): scenes/ui/reaction_prompt_ui.gd's REAL
	# open_prompt() renders weapon-specific 'Block (Small Shield 1d10+4)' /
	# 'Parry (Mace +1)' buttons, sourced from the REAL legal_reactions +
	# defense_context produced above -- never a hardcoded string.
	var ui = ReactionPromptUIScene.instantiate()
	add_child_autofree(ui)
	ui.open_prompt(legal_reactions, defense_context)

	var block_button: Button = ui.get_button("block")
	var parry_button: Button = ui.get_button("parry")

	assert_not_null(block_button, "a legal 'block' reaction must render a Button")
	assert_not_null(parry_button, "a legal 'parry' reaction must render a Button")
	assert_true(
		block_button.text.contains("Small Shield"),
		"block button label must name the actual blocking weapon: '%s'" % block_button.text
	)
	assert_true(
		parry_button.text.contains("Mace"),
		"parry button label must name the actual parrying weapon: '%s'" % parry_button.text
	)
	assert_eq(block_button.text, "Block (Small Shield 1d10+4)")
	assert_eq(parry_button.text, "Parry (Mace +1)")

	# ── Both buttons are legal AND map to bare reaction ids in _buttons,
	# never the enriched label strings -- the frozen legal_reactions
	# Array[String] contract survives end-to-end into the UI layer.
	assert_true(legal_reactions.has("block"))
	assert_true(legal_reactions.has("parry"))
	assert_null(
		ui.get_button("Block (Small Shield 1d10+4)"),
		"_buttons must never be keyed by the enriched block label string"
	)
	assert_null(
		ui.get_button("Parry (Mace +1)"),
		"_buttons must never be keyed by the enriched parry label string"
	)
