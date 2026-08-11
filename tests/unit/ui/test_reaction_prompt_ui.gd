extends GutTest
## tests/unit/ui/test_reaction_prompt_ui.gd
##
## GUT suite for FEAT-010 (US-010 / FR-010): scenes/ui/reaction_prompt_ui.gd's
## new `_label_for_reaction(reaction_id, context)` — the presentation-layer
## exit point of the "Patience equips a shield" steel thread. Enriches the
## 'parry'/'block' button labels with the weapon name + stats sourced from
## the defense context core/application/round_session.gd's
## `_build_defense_context()` produces (FEAT-008, already regression-tested
## byte-for-byte by tests/unit/core/application/test_round_session.gd's
## "Patience (mace + small shield)" suite) — this file does NOT re-verify
## _build_defense_context()'s own best-weapon-selection math, only that
## reaction_prompt_ui.gd correctly RENDERS the context dict it is handed.
##
## Verifies (this feature's test_criteria):
##   1. _label_for_reaction('block', <Patience defense context>) contains
##      'Small Shield' and the block die/bonus values.
##   2. _label_for_reaction('parry', <Patience defense context>) contains
##      'Mace' and the parry bonus.
##   3. _label_for_reaction falls back to String(reaction_id).capitalize()
##      when context lacks the relevant weapon-derived keys.
##   4. _buttons[reaction_id] stores the bare reaction id ('parry'/'block'),
##      never the enriched label string — the frozen legal_reactions
##      Array[String] contract survives end-to-end into the UI layer.
##   5. The Pass button and other non-weapon reaction labels/behavior
##      (e.g. 'dodge') are unaffected.

const ReactionPromptUIScene = preload("res://scenes/ui/reaction_prompt_ui.tscn")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")

## PATIENCE_DEFENSE_CONTEXT — mirrors, key-for-key and value-for-value, the
## Dictionary tests/unit/core/application/test_round_session.gd's
## test_build_defense_context_for_patience_selects_best_weapons_by_key()
## asserts core/application/round_session.gd's _build_defense_context()
## produces for Patience's real 2-weapon (mace + small shield) loadout:
## parrying_weapon = Mace (parry_bonus 1, ties block-value loser small
## shield on parry_bonus, first-wins), blocking_weapon = Small Shield
## (block_value 4 beats mace's 2, block_die 10).
const PATIENCE_DEFENSE_CONTEXT: Dictionary = {
	"parry_weapon_name": "Mace",
	"parry_bonus": 1,
	"block_weapon_name": "Small Shield",
	"block_weapon_value": 4,
	"block_weapon_die": 10,
	"block_weapon_damage_die": 4,
}


func _instantiate_ui() -> Node:
	var ui = ReactionPromptUIScene.instantiate()
	add_child_autofree(ui)
	return ui


# ══════════════════════════════════════════════════════════════════════════
# _label_for_reaction() — weapon-specific enrichment
# ══════════════════════════════════════════════════════════════════════════

func test_label_for_block_reaction_includes_weapon_name_and_die_and_bonus() -> void:
	var ui = _instantiate_ui()

	var label: String = ui._label_for_reaction("block", PATIENCE_DEFENSE_CONTEXT)

	assert_true(label.contains("Small Shield"), "block label must name the actual blocking weapon: '%s'" % label)
	assert_true(label.contains("10"), "block label must surface the block die (10): '%s'" % label)
	assert_true(label.contains("4"), "block label must surface the block value/bonus (4): '%s'" % label)
	assert_eq(label, "Block (Small Shield 1d10+4)")


func test_label_for_parry_reaction_includes_weapon_name_and_bonus() -> void:
	var ui = _instantiate_ui()

	var label: String = ui._label_for_reaction("parry", PATIENCE_DEFENSE_CONTEXT)

	assert_true(label.contains("Mace"), "parry label must name the actual parrying weapon: '%s'" % label)
	assert_true(label.contains("1"), "parry label must surface the parry bonus (1): '%s'" % label)
	assert_eq(label, "Parry (Mace +1)")


func test_label_for_block_falls_back_to_the_die_field_when_block_die_is_zero() -> void:
	var ui = _instantiate_ui()
	var context: Dictionary = {
		"block_weapon_name": "Buckler",
		"block_weapon_value": 3,
		"block_weapon_die": 0,
		"block_weapon_damage_die": 8,
	}

	var label: String = ui._label_for_reaction("block", context)

	assert_true(label.contains("Buckler"))
	assert_true(label.contains("8"), "must fall back to block_weapon_damage_die when block_weapon_die is 0: '%s'" % label)


# ══════════════════════════════════════════════════════════════════════════
# _label_for_reaction() — fallback to plain capitalized label
# ══════════════════════════════════════════════════════════════════════════

func test_label_for_block_falls_back_to_plain_capitalized_label_when_context_lacks_weapon_keys() -> void:
	var ui = _instantiate_ui()

	assert_eq(ui._label_for_reaction("block", {}), "Block")


func test_label_for_parry_falls_back_to_plain_capitalized_label_when_context_lacks_weapon_keys() -> void:
	var ui = _instantiate_ui()

	assert_eq(ui._label_for_reaction("parry", {}), "Parry")


func test_label_for_parry_falls_back_when_context_carries_only_unrelated_keys() -> void:
	var ui = _instantiate_ui()
	var context: Dictionary = {"attacker_name": "Goblin", "reactor_name": "Titus", "roll_total": 15}

	assert_eq(ui._label_for_reaction("parry", context), "Parry")
	assert_eq(ui._label_for_reaction("block", context), "Block")


func test_label_for_non_weapon_reaction_ids_is_always_the_plain_capitalized_label() -> void:
	var ui = _instantiate_ui()

	assert_eq(ui._label_for_reaction("dodge", PATIENCE_DEFENSE_CONTEXT), "Dodge")
	assert_eq(ui._label_for_reaction("steel", PATIENCE_DEFENSE_CONTEXT), "Steel")
	assert_eq(ui._label_for_reaction(ReactionChooserPortClass.PASS, {}), String(ReactionChooserPortClass.PASS).capitalize())


# ══════════════════════════════════════════════════════════════════════════
# _rebuild_buttons() wiring — enriched text, bare-id keys, Pass unaffected
# ══════════════════════════════════════════════════════════════════════════

func test_open_prompt_renders_enriched_block_and_parry_labels_for_patience_context() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt(["block", "parry"], PATIENCE_DEFENSE_CONTEXT)

	assert_eq(ui.get_button("block").text, "Block (Small Shield 1d10+4)")
	assert_eq(ui.get_button("parry").text, "Parry (Mace +1)")


func test_buttons_dictionary_key_is_always_the_bare_reaction_id_never_the_enriched_label() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt(["block", "parry"], PATIENCE_DEFENSE_CONTEXT)

	assert_not_null(ui.get_button("block"), "_buttons must be keyed by the bare id 'block'")
	assert_not_null(ui.get_button("parry"), "_buttons must be keyed by the bare id 'parry'")
	assert_null(ui.get_button("Block (Small Shield 1d10+4)"), "_buttons must never be keyed by the enriched label string")
	assert_null(ui.get_button("Parry (Mace +1)"), "_buttons must never be keyed by the enriched label string")

	assert_eq(ui.get_displayed_options(), ["block", "parry", ReactionChooserPortClass.PASS],
		"the legal_reactions contract must stay bare reaction ids, unaffected by label enrichment")


func test_open_prompt_without_context_renders_plain_labels_backward_compatibly() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt(["block", "parry", "dodge"], {})

	assert_eq(ui.get_button("block").text, "Block")
	assert_eq(ui.get_button("parry").text, "Parry")
	assert_eq(ui.get_button("dodge").text, "Dodge")


func test_pass_button_and_other_reaction_pressing_behavior_are_unaffected_by_label_enrichment() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["block", "parry"], PATIENCE_DEFENSE_CONTEXT)

	var received: Array = []
	ui.reaction_chosen.connect(func(choice): received.append(choice))

	assert_eq(ui.get_button(ReactionChooserPortClass.PASS).text, "Pass")
	ui.get_button("block").pressed.emit()

	assert_eq(received, ["block"], "pressing the enriched-label Block button must still resolve to the bare id 'block'")
