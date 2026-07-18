extends GutTest
## tests/gut/test_presentation_controls_sticky_lock.gd — FEAT-137 (DEF-004 /
## US-010 / FR-010), retargeted by FEAT-181 (DEF-001 / FR-009/NFR-003).
##
## GUT test suite reproducing DEF-004: presentation/result_screen_view.gd's
## _disable_combat_controls() used to perform a one-time
## configure()-clear on its input controls rather than a persistent lock,
## unlike scenes/battlefield/ResultScreen.gd's sticky lock()/is_locked()
## guard on StrikeInputController/EndTurnController. A stray reconfigure()
## call after EncounterResultEvent fired could therefore re-enable input
## through the presentation/* path.
##
## FEAT-006 (US-006) removed the legacy immediate-resolve
## presentation/strike_action_control.gd/.tscn control entirely — Strike is
## now driven SOLELY through the Layer 1 verb bar
## (presentation/verb_bar_view.gd) -> `_verb_registry`'s STRIKE entry (see
## MainScene.gd's file-level FEAT-006 doc). FEAT-181 (DEF-001) retargets this
## suite's Strike-lock coverage onto that real two-layer flow, driven through
## a REAL, shipped res://MainScene.tscn instance (mirroring the
## `_boot_main_scene_with_seed()` convention already established by
## tests/gut/test_strike_layer2_integration.gd and friends) instead of the
## deleted control — preserving this suite's original regression intent
## (sticky lock survives a stray reconfigure/refresh, DEF-004's exact
## reproduction scenario) — while EndTurnControl (never deleted) keeps its
## own standalone-fixture coverage unchanged.
##
## Verifies (test_criteria):
##   1. VerbBarView.press("STRIKE") (via the real `_verb_registry`) and
##      EndTurnControl.press() are rejected once lock() has been engaged, and
##      that rejection persists across a later, stray configure()/
##      refresh_availability() call (the reproduction of DEF-004's
##      regression scenario).
##   2. is_locked() returns true on both VerbBarView and EndTurnControl after
##      ResultScreenView observes an EncounterResultEvent, and stays true
##      through any subsequent configure() call on either control.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const EndTurnControlScene: PackedScene   = preload("res://presentation/end_turn_control.tscn")
const ResultScreenViewScene: PackedScene = preload("res://presentation/result_screen_view.tscn")
const CombatantClass                     = preload("res://core/domain/combatant.gd")

const ERR_ENCOUNTER_ALREADY_RESOLVED: String = "ENCOUNTER_ALREADY_RESOLVED"


## FakeRoundSession — minimal stand-in for core/application/round_session.gd's
## RoundSession, exposing only what EndTurnControl.is_enabled()/press() rely
## on (mirrors tests/unit/presentation/test_result_screen_view.gd's
## identically-named fixture) — used ONLY by the standalone EndTurnControl
## fixture below, which needs no real MainScene at all.
class FakeRoundSession:
	var _actor
	var _round_over: bool = false
	var end_current_turn_call_count: int = 0

	func _init(actor) -> void:
		_actor = actor

	func current_actor():
		return null if _round_over else _actor

	func is_round_over() -> bool:
		return _round_over

	func end_current_turn() -> Dictionary:
		end_current_turn_call_count += 1
		return {"ok": true, "round_over": false}


## _boot_main_scene_with_seed(seed_value) -> Node — instantiates the REAL
## res://MainScene.tscn composition root, pinned to a deterministic seed
## (mirrors tests/gut/test_strike_layer2_integration.gd's identically-named
## fixture) so this suite's Strike-lock coverage exercises the real
## VerbBarView -> `_verb_registry` -> resolve_action_use_case flow, never a
## mock/stub standing in for any of them.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a — VerbBarView's STRIKE verb (via the real `_verb_registry`
# and a real MainScene instance) is rejected once ResultScreenView's
# lock_all_controls() has engaged it, and rejection persists across a later,
# stray reconfigure()/refresh_availability() call — the DEF-004 regression
# scenario, retargeted onto the real Layer 1/Layer 2 flow (FEAT-181).
# ══════════════════════════════════════════════════════════════════════════

func test_verb_bar_strike_stays_locked_even_after_a_stray_reconfigure_via_real_main_scene() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"fixture assumption: the prologue's first actor has at least one in-reach target at seed=42"
	)

	var actor_id: String = instance.round_session.current_actor().display_id()
	var budget_before: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	assert_true(selection.get("candidate_targets", []).size() > 0, "sanity check: STRIKE opens Layer 2 with a real in-reach target before lock()")
	assert_true(instance.selection_overlay.is_active(), "sanity check: SelectionOverlay is active (Layer 2) before lock()")

	# The real terminal event, via the SAME ResultScreenView the composition
	# root wires -- lock_all_controls() locks VerbBarView/SelectionOverlay
	# exactly as a real Strike/Step/Stride/End-Turn resolution would.
	instance.result_screen_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(instance.verb_bar_view.is_locked(), "VerbBarView must report is_locked() == true once EncounterResultEvent fires")
	assert_false(instance.selection_overlay.is_active(), "any open Layer 2 selection must be discarded once locked")
	for verb_id in instance.verb_bar_view.get_verb_ids():
		assert_true(instance.verb_bar_view.get_button(verb_id).disabled, "every verb button must be disabled once locked (verb=%s)" % verb_id)

	# The DEF-004 regression: a stray reconfigure()/refresh_availability()
	# call (e.g. a leftover active_actor_changed signal) after lock() must
	# NOT re-enable input.
	instance.verb_bar_view.configure(instance._verb_registry)
	instance.verb_bar_view.refresh_availability()

	assert_true(instance.verb_bar_view.is_locked(), "is_locked() must stay true through a later configure()/refresh_availability() call")
	assert_true(instance.verb_bar_view.get_button("STRIKE").disabled, "a stray reconfigure() must not re-enable the STRIKE button")

	var result: Dictionary = instance.verb_bar_view.press("STRIKE")
	assert_false(result.get("ok", true), "press(STRIKE) must be rejected once locked, even after a stray reconfigure()")
	assert_eq(result.get("error", ""), ERR_ENCOUNTER_ALREADY_RESOLVED)

	var budget_after: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		budget_after, budget_before,
		"a rejected post-lock press(STRIKE) must never reach resolve_action_use_case -- the actor's action budget must remain unspent"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b — EndTurnControl (never deleted -- retains its own standalone
# fixture, unaffected by FEAT-006's StrikeActionControl removal) stays
# locked even after a stray reconfigure() call.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_control_stays_locked_even_after_a_stray_reconfigure() -> void:
	var control = EndTurnControlScene.instantiate()
	add_child_autofree(control)

	var session := FakeRoundSession.new(CombatantClass.from_dict({"name": "Titus"}))
	control.configure(session)
	assert_true(control.is_enabled(), "sanity check: control is enabled before lock()")

	control.lock()

	assert_true(control.is_locked(), "EndTurnControl must report is_locked() == true once lock() is engaged")
	assert_false(control.is_enabled(), "EndTurnControl must be disabled once locked")

	# The DEF-004 regression: a stray reconfigure() call with a fresh
	# RoundSession must NOT re-enable input.
	var fresh_session := FakeRoundSession.new({"name": "Titus", "_is_enemy": false})
	control.configure(fresh_session)

	assert_true(control.is_locked(), "is_locked() must stay true through a later configure() call")
	assert_false(control.is_enabled(), "a stray reconfigure() must not re-enable the control")

	var result: Dictionary = control.press()
	assert_false(result.get("ok", true), "press() must be rejected once locked, even after a stray reconfigure()")
	assert_eq(result.get("error", ""), ERR_ENCOUNTER_ALREADY_RESOLVED)
	assert_eq(fresh_session.end_current_turn_call_count, 0, "end_current_turn() must never be invoked once locked")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — is_locked() returns true on both VerbBarView and
# EndTurnControl after the REAL ResultScreenView (wired by a real MainScene
# instance) observes an EncounterResultEvent, and stays true through any
# subsequent configure() call on either control.
# ══════════════════════════════════════════════════════════════════════════

func test_is_locked_true_on_verb_bar_and_end_turn_control_after_encounter_result_event_via_real_main_scene_and_stays_true_through_reconfigure() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(instance.verb_bar_view.is_locked())
	assert_false(instance.end_turn_control.is_locked())

	instance.result_screen_view.on_round_event({"round": 1, "outcome": "won"})

	assert_true(instance.verb_bar_view.is_locked(), "VerbBarView.is_locked() must be true after EncounterResultEvent fires")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl.is_locked() must be true after EncounterResultEvent fires")

	# A stray reconfigure() call on either control after the encounter has
	# concluded must not unlock either one (the DEF-004 regression).
	instance.verb_bar_view.configure(instance._verb_registry)
	instance.end_turn_control.configure(instance.round_session)

	assert_true(instance.verb_bar_view.is_locked(), "VerbBarView must stay locked through a later configure() call")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl must stay locked through a later configure() call")

	var strike_result: Dictionary = instance.verb_bar_view.press("STRIKE")
	assert_false(strike_result.get("ok", true))
	assert_eq(strike_result.get("error", ""), ERR_ENCOUNTER_ALREADY_RESOLVED)

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_false(press_result.get("ok", true))
	assert_eq(press_result.get("error", ""), ERR_ENCOUNTER_ALREADY_RESOLVED)
