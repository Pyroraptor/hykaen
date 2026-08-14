extends GutTest
## tests/integration/test_skeleton_shielded_block_e2e.gd
##
## END-TO-END STEEL THREAD: proves the shielded skeleton pipeline from raw
## .tres data through to the rendered reaction-prompt block button.
##
##   DATA         -> data/enemies/skeleton_shielded.tres,
##                   data/weapons/{arming_sword,small_shield}.tres
##   INFRASTRUCTURE -> infrastructure/combatant_factory.gd
##                   (CombatantFactory.build_enemy_combatant())
##   APPLICATION  -> core/application/round_session.gd
##                   (_build_defense_context(), _build_reaction_trigger())
##                   and core/application/reaction_window.gd
##                   (_compute_legal_reactions())
##   PRESENTATION -> scenes/ui/reaction_prompt_ui.gd (open_prompt())
##
## Entry point: CombatantFactory.build_enemy_combatant() on
## skeleton_shielded.tres. Exit point: rendered "Block (Small Shield 1d10+4)"
## Button, keyed by bare reaction id "block".

const CombatantFactoryClass        = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const ReactionWindowClass          = preload("res://core/application/reaction_window.gd")
const ReactionPromptUIScene        = preload("res://scenes/ui/reaction_prompt_ui.tscn")

const SKELETON_SHIELDED_PATH: String = "res://data/enemies/skeleton_shielded.tres"


class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"
	var _entries: Array
	func _init(entries: Array) -> void: _entries = entries
	func get_turn_order() -> Array: return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"
	func emit(_event) -> void: pass


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"
	func append(_entry: Dictionary) -> void: pass
	func get_history() -> Array: return []


class FakeAIDecisionPort:
	extends "res://core/application/ai_decision_port.gd"
	func decide_action(_combatant, _targets: Array) -> Dictionary:
		return {"action_type": "", "target": null}


func _durable_attacker():
	return CombatantClass.from_dict({
		"name":         "Titus",
		"combatant_id": "titus_1",
		"hp_current":   20,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    false,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 8,
		},
	})


func _round_session_for_trigger_tests(alpha):
	var entries: Array = [{"combatant": alpha, "action_economy": ActionEconomyClass.new()}]
	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		SeededRandomAdapterClass.new(1), FakeEventSinkPort.new(), FakeRoundHistoryPort.new()
	)
	var run_round_use_case = RunRoundUseCaseClass.new(
		FakeTurnOrderPort.new(entries), FakeEventSinkPort.new(), FakeRoundHistoryPort.new(),
		FakeAIDecisionPort.new(), resolve_action_use_case, DetermineOutcomeUseCaseClass.new()
	)
	return run_round_use_case.begin_round(1, [alpha], [])


func test_skeleton_shielded_block_reaction_prompt_end_to_end() -> void:
	# DATA -> INFRASTRUCTURE: build from the real skeleton_shielded.tres.
	var factory := CombatantFactoryClass.new()
	var combatant_dict: Dictionary = factory.build_enemy_combatant(
		SKELETON_SHIELDED_PATH, null, "enemy_1"
	)

	assert_false(combatant_dict.has("error"),
		"skeleton_shielded.tres must build without error (got: %s)" % [combatant_dict])
	var weapons: Array = combatant_dict.get("weapons", [])
	assert_eq(weapons.size(), 2,
		"shielded skeleton must carry 2 weapons: arming sword (primary) + small shield (off-hand)")
	assert_eq((weapons[1] as Dictionary).get("block_die", -1), 10,
		"weapons[1] (Small Shield) block_die must be 10")

	var skeleton = CombatantClass.from_dict(combatant_dict)
	assert_eq(skeleton.weapons.size(), 2, "Combatant entity must carry the same 2-weapon loadout")

	# APPLICATION: _build_defense_context() selects the small shield as best blocker.
	var attacker = _durable_attacker()
	var session = _round_session_for_trigger_tests(attacker)
	var target_ae := ActionEconomyClass.new()

	var defense_context: Dictionary = session._build_defense_context(skeleton, target_ae)
	assert_eq(defense_context["blocking_weapon"].get("block_die", -1), 10,
		"blocking_weapon must be the small shield (block_die 10)")
	assert_eq(defense_context["block_weapon_name"], "Small Shield")

	# APPLICATION: _build_reaction_trigger() carries the full 2-weapon array.
	var trigger: Dictionary = session._build_reaction_trigger(attacker, skeleton)
	assert_eq(trigger["weapons"], skeleton.weapons,
		"trigger['weapons'] must reflect the skeleton's 2-weapon loadout")

	# APPLICATION: _compute_legal_reactions() — block (shield) and parry (sword) both legal.
	var window := ReactionWindowClass.new(FakeEventSinkPort.new())
	var legal_reactions: Array = window._compute_legal_reactions(trigger)

	assert_true(legal_reactions.has("block"),
		"Small Shield (block_die 10) must make 'block' a legal reaction")
	assert_true(legal_reactions.has("parry"),
		"Arming Sword (parry_bonus 4) must make 'parry' a legal reaction")

	# PRESENTATION: reaction prompt renders "Block (Small Shield 1d10+4)".
	var ui = ReactionPromptUIScene.instantiate()
	add_child_autofree(ui)
	ui.open_prompt(legal_reactions, defense_context)

	var block_button: Button = ui.get_button("block")
	assert_not_null(block_button, "a legal 'block' reaction must render a Button")
	assert_eq(block_button.text, "Block (Small Shield 1d10+4)")

	var parry_button: Button = ui.get_button("parry")
	assert_not_null(parry_button, "a legal 'parry' reaction must render a Button")
	assert_true(parry_button.text.contains("Arming Sword"),
		"parry button must name the arming sword: '%s'" % parry_button.text)

	# Buttons keyed by bare reaction id, never enriched label strings.
	assert_null(ui.get_button("Block (Small Shield 1d10+4)"),
		"_buttons must never be keyed by the enriched label string")
