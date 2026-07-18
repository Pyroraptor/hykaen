extends GutTest
## tests/unit/presentation/test_status_panel_view_retargeted.gd — FEAT-004
## (US-004 / FR-013, iteration D "UI Consolidation + Movement UX").
##
## Retargets tests/gut/test_combatant_readout.gd (FEAT-005), whose subject --
## the duplicate scenes/battlefield/CombatantReadout.gd per-combatant
## readout -- was removed from MainScene's composition root (FEAT-001/P0-2).
## presentation/status_panel_view.gd is the ONE kept per-combatant status
## surface; this file closes the coverage gaps that suite's deletion would
## otherwise have left open, rather than re-testing what already has an
## equivalent home:
##
##   old criterion                                       | equivalent coverage
##   -------------------------------------------------------+---------------------------------------------------------
##   1. HP/Stamina/action-budget/Spent/conditions match      | tests/unit/presentation/test_status_panel_view.gd
##      live domain state after a round_event                (test_status_reflects_name_hp_stamina_budget_spent_...)
##   2a. updates on AttackEvent, no polling                  | test_status_panel_view.gd covers the AttackEvent path;
##                                                            "no polling" source-guardrail was NOT previously
##                                                            covered for status_panel_view.gd -- added below
##   2b. updates on CombatantDefeatedEvent (HP zeroed,        | StatusPanelView does not itself special-case
##       Defeated condition flagged)                          CombatantDefeatedEvent -- that responsibility moved to
##                                                            presentation/initiative_view.gd in the kept stack
##                                                            (test_initiative_view.gd's is_defeated()/"Defeated"
##                                                            marking). The HP-reaches-zero half of the old
##                                                            behavior is verified below to still hold via the
##                                                            killing AttackEvent itself (no separate event needed).
##   3. code-review guardrail: no reach/damage/hit            | NOT previously covered for status_panel_view.gd --
##      computation of its own (ADR-001)                      added below
##
## No production code is changed by this feature (FEAT-004 is test-suite-only
## consolidation) -- every assertion below exercises EXISTING
## presentation/status_panel_view.gd behavior.

const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const RoundEventsClass = preload("res://core/rules/round_events.gd")

const STATUS_PANEL_VIEW_SOURCE_PATH: String = "res://presentation/status_panel_view.gd"

var _panel = null


func before_each() -> void:
	_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(_panel)


func _sample_view_model() -> Dictionary:
	return {
		"combatant_id": "player_0",
		"name": "Titus",
		"hp_current": 10,
		"hp_max": 10,
		"stamina_current": 6,
		"stamina_max": 6,
		"action_budget_remaining": 7,
		"spent": false,
		"conditions": [],
	}


# ══════════════════════════════════════════════════════════════════════════
# Retarget of Criterion 2c (test_combatant_readout.gd): purely event-driven,
# no polling -- updates are reflected immediately with no frame wait, and the
# source declares no _process()/_physics_process() callback.
# ══════════════════════════════════════════════════════════════════════════

func test_updates_are_reflected_immediately_with_no_frame_wait() -> void:
	# No `await get_tree().process_frame` anywhere in this test -- the status
	# change from on_round_event() must be synchronous/immediate, proving
	# there is no polling loop involved in propagating it.
	_panel.load_combatants([_sample_view_model()])
	_panel.on_round_event(RoundEventsClass.AttackBroadcast.new(1, "Skeleton", "Titus", 17, "ac", 14, true, false, 3))
	assert_eq(_panel.get_status("player_0").get("hp_current"), 7)


func _read_source() -> String:
	var file := FileAccess.open(STATUS_PANEL_VIEW_SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % STATUS_PANEL_VIEW_SOURCE_PATH)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_declares_no_polling_process_callbacks() -> void:
	var source: String = _read_source()
	assert_eq(source.find("_process("), -1, "status_panel_view.gd must not poll domain state via _process()")
	assert_eq(source.find("_physics_process("), -1, "status_panel_view.gd must not poll domain state via _physics_process()")


# ══════════════════════════════════════════════════════════════════════════
# Retarget of Criterion 2b (test_combatant_readout.gd): a killing blow still
# drives the displayed HP to zero -- the same terminal outcome
# CombatantReadout's CombatantDefeatedEvent handler used to produce -- via
# the ordinary AttackEvent path StatusPanelView already implements, with no
# separate CombatantDefeatedEvent handling required in the kept stack
# (that responsibility lives on presentation/initiative_view.gd instead, see
# file header).
# ══════════════════════════════════════════════════════════════════════════

func test_lethal_attack_event_drives_displayed_hp_to_zero() -> void:
	_panel.load_combatants([_sample_view_model()])

	var lethal_attack := RoundEventsClass.AttackBroadcast.new(1, "Skeleton", "Titus", 17, "ac", 14, true, false, 999)
	_panel.on_round_event(lethal_attack)

	assert_eq(
		_panel.get_status("player_0").get("hp_current"), 0,
		"a lethal AttackEvent must drive the displayed HP to zero, clamped -- matching CombatantReadout's old CombatantDefeatedEvent-driven zeroing"
	)


func test_lethal_attack_event_via_explicit_target_hp_after_also_zeroes_hp() -> void:
	_panel.load_combatants([_sample_view_model()])
	_panel.on_round_event({"target_name": "Titus", "damage_final": 10, "target_hp_after": 0})
	assert_eq(_panel.get_status("player_0").get("hp_current"), 0)


# ══════════════════════════════════════════════════════════════════════════
# New coverage (code-review guardrail): status_panel_view.gd contains no
# reach/damage/hit computation of its own -- read-only projection (ADR-001).
# Retargets test_combatant_readout.gd's identically-purposed guardrail.
# ══════════════════════════════════════════════════════════════════════════

func test_source_contains_no_combat_computation_keywords() -> void:
	var source: String = _read_source().to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "is_adjacent", "compute_ac", "compute_hp",
		"hit_chance", "randi(", "randf(",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"presentation/status_panel_view.gd must contain no combat computation ('%s' found) -- read-and-render only (ADR-001)" % keyword
		)
