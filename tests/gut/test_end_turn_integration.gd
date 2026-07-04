extends GutTest
## tests/gut/test_end_turn_integration.gd — FEAT-175 (US-011 / FR-006;
## ADR-002, ADR-004, ADR-005).
##
## Integration-test complement to tests/pytest/test_verb_registry.py's
## TestGenericDispatch.test_execute_end_turn_dispatches_to_turn_port and
## tests/gut/test_verb_bar_view.gd's End Turn Criterion-3 suite (the
## Python-/fake-registry-level pins of "End Turn calls execute() directly,
## no Layer 2 transition, no SelectionDescriptor produced"). This suite
## boots the REAL, shipped res://MainScene.tscn composition root headless
## (mirroring tests/gut/test_strike_layer2_integration.gd's / tests/gut/
## test_step_layer2_integration.gd's `_boot_main_scene_with_seed()` fixture)
## with NO stub/mock standing in for `_verb_registry`, `end_turn_control`,
## `turn_controller`, `round_session`, or presentation/selection_overlay.gd's
## SelectionOverlay -- proving End Turn's direct-execution path (the fourth
## and final Layer 1 verb, per ADR-005's phase model) works end-to-end
## through the exact objects a real player drives, with NO Layer 2 step at
## all.
##
## test_criteria satisfied:
##   1. Unit test: End Turn execute() calls TurnPort.end_turn() with no
##      SelectionDescriptor produced -- already pinned at the pytest layer
##      (tests/pytest/test_verb_registry.py) and the fake-registry GUT layer
##      (tests/gut/test_verb_bar_view.gd); this suite adds the REAL-registry
##      confirmation that pressing the real, rendered END_TURN button on the
##      real MainScene never activates SelectionOverlay / never emits
##      verb_selection_entered.
##   2. Integration test via real MainScene: clicking End Turn transitions
##      TurnState to the next active combatant and phase LAYER1_VERB_SELECT
##      -- realized in this codebase as RoundSession's turn cursor genuinely
##      advancing (proven via the real event-sink's TurnAdvancedEvent trail,
##      the SAME proof convention tests/unit/test_main_scene_interactive_
##      wiring.gd's End Turn criterion already established) and the UI
##      settling back at Layer 1 (SelectionOverlay inactive, VerbBarView
##      re-gated/available for the next active combatant), never left
##      stranded mid-Layer-2 or with stale availability.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const SelectionOverlayClass = preload("res://presentation/selection_overlay.gd")
const RoundEventsClass      = preload("res://core/rules/round_events.gd")

const END_TURN: String = "END_TURN"


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/gut/test_strike_layer2_integration.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — pressing END_TURN calls execute() DIRECTLY: no Layer 2 is
# ever entered (no SelectionDescriptor consumed by SelectionOverlay, no
# verb_selection_entered emission), unlike every other verb.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_never_activates_selection_overlay_or_enters_layer2() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_true(
		is_instance_of(instance.selection_overlay, SelectionOverlayClass),
		"MainScene must wire the REAL presentation/selection_overlay.gd SelectionOverlay -- no stub/mock"
	)
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must be inactive (Layer 1) before any verb is pressed")
	assert_true(instance._verb_registry.is_available(END_TURN), "End Turn must always be available")

	watch_signals(instance.verb_bar_view)
	watch_signals(instance.selection_overlay)

	var result = instance.verb_bar_view.press(END_TURN)

	assert_signal_emitted(instance.verb_bar_view, "verb_executed", "pressing End Turn must call execute() directly")
	assert_signal_not_emitted(instance.verb_bar_view, "verb_selection_entered", "pressing End Turn must NEVER enter Layer 2 (no enter_selection() call)")
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must remain inactive -- End Turn never produces a SelectionDescriptor to activate it with")
	assert_true(typeof(result) == TYPE_DICTIONARY, "execute() must return the ResolutionResult-shaped Dictionary produced by TurnPort.end_turn()")


func test_the_real_rendered_end_turn_button_press_never_activates_selection_overlay() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var button: Button = instance.verb_bar_view.get_button(END_TURN)
	assert_not_null(button, "a real End Turn Button must be rendered by VerbBarView")

	watch_signals(instance.selection_overlay)
	button.pressed.emit()

	assert_false(instance.selection_overlay.is_active(), "emitting the real rendered End Turn button's pressed signal must never enter Layer 2")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — clicking End Turn transitions TurnState to the next active
# combatant (RoundSession's cursor genuinely advances, proven via the real
# event-sink's TurnAdvancedEvent trail) and settles the UI back at Layer 1
# (LAYER1_VERB_SELECT: SelectionOverlay inactive, VerbBarView re-gated).
# ══════════════════════════════════════════════════════════════════════════

func test_clicking_end_turn_advances_the_turn_cursor_through_the_real_turn_port() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var first_actor_name: String = instance.round_session.current_actor().get("name", "")
	assert_ne(first_actor_name, "", "fixture assumption: a living actor is active before End Turn is pressed")
	assert_false(instance.round_session.current_actor().get("_is_enemy", true), "fixture assumption: Titus (the player) acts first at seed=42")

	var events_before: int = instance.event_sink.log.size()

	var result = instance.verb_bar_view.press(END_TURN)

	assert_true(result.get("ok", false), "End Turn must resolve successfully through the real TurnPort.end_turn() path")

	# TurnState genuinely advanced -- the real RoundSession.end_current_turn()
	# ran (this is the SAME TurnPort.end_turn() the design notes name), proven
	# through the real event sink's TurnAdvancedEvent trail rather than by
	# comparing actor names (the prologue's two combatants alternate turns and
	# so settle back on the SAME named actor, Titus, once TurnController has
	# auto-driven the Skeleton's Enemy turn in between, US-011).
	var turn_advanced_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_true(
		instance.round_session.is_round_over() or turn_advanced_events.size() >= 1,
		"clicking End Turn must advance RoundSession's turn cursor to the next active combatant (or conclude the round)"
	)
	assert_true(instance.event_sink.log.size() > events_before, "ending the turn must emit at least one new round event through the real event sink")

	if not instance.round_session.is_round_over():
		# With only two combatants (Titus/Skeleton), TurnController must have
		# auto-driven the Skeleton's Enemy turn (US-011) and settled the
		# cursor back on a LIVING PLAYER combatant -- never left sitting on
		# the Enemy.
		assert_false(
			instance.round_session.current_actor().get("_is_enemy", false),
			"TurnController must auto-drive any Enemy turn so RoundSession settles back on a player combatant"
		)
		assert_true(
			turn_advanced_events.size() >= 2,
			"both End Turn's own cursor advance and the auto-driven Enemy turn's cursor advance must be observable through the real event sink"
		)


func test_clicking_end_turn_settles_the_ui_back_at_layer1_verb_select() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	instance.verb_bar_view.press(END_TURN)

	# Phase LAYER1_VERB_SELECT, realized here as: no Layer 2 selection is
	# pending (SelectionOverlay inactive) and the Layer 1 verb bar has been
	# re-gated (refresh_availability()) for whichever combatant the turn now
	# belongs to -- never left stranded with a stale/disabled control set
	# from the combatant whose turn just ended.
	assert_false(instance.selection_overlay.is_active(), "the UI must settle back at Layer 1 (no pending Layer 2 selection) after End Turn resolves")

	if not instance.round_session.is_round_over():
		assert_true(instance._verb_registry.is_available(END_TURN), "End Turn must remain available for the next active combatant's Layer 1 verb bar")
		assert_false(
			instance.round_session.current_actor().get("_is_enemy", false),
			"the settled active combatant must be a living player, ready for Layer 1 verb selection"
		)
		# The re-gated verb bar reflects LIVE state for the newly active
		# combatant -- proven behaviorally (not merely "no exception was
		# thrown") by confirming STRIKE's availability now agrees with the
		# freshly recomputed in-reach target set for whoever RoundSession
		# currently sits on, exactly as a fresh Layer 1 turn-start would.
		assert_eq(
			instance._verb_registry.is_available("STRIKE"),
			instance._strike_reachable_target_ids().size() > 0,
			"VerbBarView's STRIKE gating must reflect the newly active combatant's live reachable targets, not stale pre-End-Turn state"
		)


func test_pressing_end_turn_twice_in_a_row_keeps_advancing_through_the_real_turn_port() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var first_result = instance.verb_bar_view.press(END_TURN)
	assert_true(first_result.get("ok", false), "the first End Turn press must resolve successfully")

	if instance.round_session.is_round_over():
		return

	var events_after_first: int = instance.event_sink.log.size()
	var second_result = instance.verb_bar_view.press(END_TURN)
	assert_true(second_result.get("ok", false), "a second End Turn press must also resolve successfully through the same real TurnPort path")
	assert_true(
		instance.event_sink.log.size() > events_after_first,
		"a second End Turn press must advance the turn cursor again (or conclude the round)"
	)
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must still be inactive (Layer 1) after a second End Turn press")
