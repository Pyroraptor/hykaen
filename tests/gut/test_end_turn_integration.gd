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
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

const END_TURN: String = "END_TURN"


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL
## res://MainScene.tscn composition root, pinned to seed=42 (the prologue
## fixture's known-good seed, matching this codebase's established
## convention -- tests/gut/test_strike_layer2_integration.gd).
##
## FEAT-006 (US-005/FR-005, ADR-002): MainScene now wires RoundSession's
## enemy-strikes-player reaction window to the REAL, blocking
## TurnController.resolve_reaction() -> PlayerReactionChooser ->
## $ReactionPromptUI chain (see MainScene.gd's rewire_session() doc) --
## which, by design, has "no auto-timeout" (scenes/ui/reaction_prompt_ui.gd)
## and suspends until an actual player clicks an option. This suite drives
## End Turn headlessly with no player present, so it swaps the injected
## ReactionChooserPort for infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser("pass") immediately after boot -- the SAME headless
## double every other reaction-system suite already uses (e.g.
## tests/unit/test_dodge_reaction.gd) -- via TurnController.configure_reactions()'s
## own documented "safe to call any number of times" contract. This
## reproduces the exact pre-FEAT-006 "none"/PASS default this suite's
## assertions were written against (see core/application/round_session.gd's
## _resolve_reaction() doc), never a new production behavior; the REAL
## PlayerReactionChooser is still what MainScene.gd wires for an actual
## player session.
## FEAT-316 (resolves DEF-001/PR-001): MainScene now boots into
## GameMode.EXPLORATION with the legacy combat pipeline (round_session,
## verb_bar_view/selection_overlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives real End Turn presses
## directly against `round_session`/the real rendered verb bar, so this
## helper now also drives that SAME real handoff (mirrors
## tests/boot/test_first_cast_firebolt.gd's established `_boot_main_scene()`
## convention), landing the instance in GameMode.COMBAT with a live
## round_session before the AutoReactionChooser override below.
## turn_controller/reaction_window are constructed unconditionally in
## _ready() (unaffected by FEAT-316), so configure_reactions() can be applied
## either before or after the handoff -- applied after here so it always
## overrides whatever rewire_session() itself wired.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — pressing END_TURN calls execute() DIRECTLY: no Layer 2 is
# ever entered (no SelectionDescriptor consumed by SelectionOverlay, no
# verb_selection_entered emission), unlike every other verb.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_never_activates_selection_overlay_or_enters_layer2() -> void:
	var instance = await _boot_main_scene_with_seed(42)
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
	var instance = await _boot_main_scene_with_seed(42)
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
	var instance = await _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var first_actor_name: String = instance.round_session.current_actor().name
	assert_ne(first_actor_name, "", "fixture assumption: a living actor is active before End Turn is pressed")
	assert_false(instance.round_session.current_actor().is_enemy, "fixture assumption: Titus (the player) acts first at seed=42")

	var events_before: int = instance.event_sink.log.size()

	var result = instance.verb_bar_view.press(END_TURN)

	assert_true(result.get("ok", false), "End Turn must resolve successfully through the real TurnPort.end_turn() path")

	# TurnState genuinely advanced -- the real RoundSession.end_current_turn()
	# ran (this is the SAME TurnPort.end_turn() the design notes name), proven
	# through the real event sink's TurnAdvancedEvent trail. The prologue
	# roster now seats a SECOND living, player-controlled combatant
	# (Marigold, "player_1") between Titus and the Skeleton in turn order --
	# so this FIRST End Turn press settles the cursor on Marigold directly
	# (never auto-driven, since Marigold is not an Enemy), producing exactly
	# one TurnAdvancedEvent so far.
	var turn_advanced_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_true(
		instance.round_session.is_round_over() or turn_advanced_events.size() >= 1,
		"clicking End Turn must advance RoundSession's turn cursor to the next active combatant (or conclude the round)"
	)
	assert_true(instance.event_sink.log.size() > events_before, "ending the turn must emit at least one new round event through the real event sink")

	if not instance.round_session.is_round_over():
		# The cursor must never have landed on the Enemy without
		# TurnController auto-driving its turn -- true here trivially,
		# since the immediate next actor (Marigold) is herself a player.
		assert_false(
			instance.round_session.current_actor().is_enemy,
			"TurnController must never settle RoundSession on an un-auto-driven Enemy turn"
		)

		# Press End Turn again for Marigold's own turn (a free pass, no
		# action spent) -- THIS is the press that finally hands the cursor
		# to the Skeleton, whose Enemy turn TurnController._drive() must
		# then auto-drive (US-011), settling back on a LIVING PLAYER
		# combatant (Titus) -- never left sitting on the Enemy.
		var second_result = instance.verb_bar_view.press(END_TURN)
		assert_true(second_result.get("ok", false), "Marigold's own End Turn press must also resolve successfully through the same real TurnPort path")

		if not instance.round_session.is_round_over():
			assert_false(
				instance.round_session.current_actor().is_enemy,
				"TurnController must auto-drive any Enemy turn so RoundSession settles back on a player combatant"
			)
			turn_advanced_events = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
			assert_true(
				turn_advanced_events.size() >= 3,
				"Titus's own End Turn advance, Marigold's own End Turn advance, AND the auto-driven Enemy turn's cursor advance must all be observable through the real event sink"
			)


func test_clicking_end_turn_settles_the_ui_back_at_layer1_verb_select() -> void:
	var instance = await _boot_main_scene_with_seed(42)
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
			instance.round_session.current_actor().is_enemy,
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
	var instance = await _boot_main_scene_with_seed(42)
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
