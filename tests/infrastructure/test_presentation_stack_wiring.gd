extends GutTest
## tests/infrastructure/test_presentation_stack_wiring.gd — FEAT-002 (US-002 /
## FR-006, iteration D "UI Consolidation + Movement UX").
##
## FEAT-001 (tests/infrastructure/test_mainscene_no_battlefield_refs.gd /
## test_mainscene_headless_boot.gd) already proved the removed
## scenes/battlefield/* stack carries no reference/instance/connection
## anywhere in MainScene. This suite is FEAT-002's positive complement: it
## proves the SURVIVING presentation/* stack is not merely "not the
## battlefield stack" but is EXACTLY the expected composition —
##   1. MainScene's direct children are EXACTLY HexGridView, StatusPanelView,
##      InitiativeView, EventLogView, TurnController, EndTurnControl,
##      VerbBarView, ResultScreenView — no more, no less
##      (movement_input_controller is a further presentation/* component, but
##      a plain RefCounted adapter, not a scene Node, so it deliberately does
##      not appear as a child — see
##      test_mainscene_wires_movement_input_controller below). FEAT-006
##      (US-006) removed the earlier StrikeActionControl child -- Strike is
##      now driven solely through MainScene's `_verb_registry` STRIKE entry
##      (see test_strike_verb_is_wired_to_the_presentation_stack_and_resolves_a_strike
##      below), never a dedicated presentation/* node of its own. FEAT-007
##      (this iteration's US-007/FR-010) removed the earlier
##      MoveActionControl child (presentation/MoveActionControl.gd has been
##      deleted entirely) -- Step/Stride are likewise now driven solely
##      through `_verb_registry`'s STEP/STRIDE entries (see
##      test_step_and_stride_verbs_are_wired_to_the_presentation_stack_and_move_the_token
##      below), never a passive indicator Control of their own.
##   2. Every player-facing interaction signal — TurnController's "turn
##      started" signal (active_actor_changed — the design notes' API
##      contract #1's turn_started, realized under that name in this
##      codebase), EndTurnControl's turn_ended, and an End Turn button press —
##      is connected exclusively to a handler that is either a presentation/*
##      component's own method or this composition root's (MainScene.gd's)
##      forwarding method, never a scenes/battlefield/* handler; a Strike/
##      Step/Stride verb-registry execute() also resolves through the SAME,
##      REUSED resolve_action_use_case / movement_input_controller. FEAT-007
##      removed HexGridView.hex_clicked's earlier legacy "click a
##      highlighted hex to auto Step-or-Stride" wiring, deliberately leaving
##      it unconnected for "a future Layer 2 SelectionOverlay" to subscribe
##      to. FEAT-008 (US-008) is that feature: hex_clicked is now connected
##      to exactly one handler — presentation/selection_overlay.gd
##      SelectionOverlay's own internal click resolver, wired by
##      MainScene.gd — see
##      test_hex_clicked_signal_is_wired_to_the_selection_overlay below.
##   3. MainScene.tscn still boots headlessly with zero compile/runtime
##      errors after this feature's re-verification (a fast regression signal
##      local to this suite, mirroring test_mainscene_headless_boot.gd's
##      established convention).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass             = preload("res://presentation/hex_grid_view.gd")
const StatusPanelViewClass         = preload("res://presentation/status_panel_view.gd")
const InitiativeViewClass          = preload("res://presentation/initiative_view.gd")
const EventLogViewClass            = preload("res://presentation/event_log_view.gd")
const EndTurnControlClass          = preload("res://presentation/end_turn_control.gd")
const ResultScreenViewClass        = preload("res://presentation/result_screen_view.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")
const MovementInputControllerClass = preload("res://presentation/movement_input_controller.gd")
const VerbBarViewClass             = preload("res://presentation/verb_bar_view.gd")
const ReactionPromptUIClass        = preload("res://scenes/ui/reaction_prompt_ui.gd")

## Every path under presentation/* is a legitimate signal-handler home; the
## composition root itself (MainScene.gd, res:// root, NOT presentation/*) is
## also legitimate — it is the single place Infrastructure/Application
## adapters are wired to Presentation (ADR-002), so its own forwarding
## methods (e.g. _on_end_turn_control_turn_ended) are the expected target for
## several of these signals.
const _PRESENTATION_SCRIPT_PREFIX: String = "res://presentation/"
const _COMPOSITION_ROOT_SCRIPT_PATH: String = "res://MainScene.gd"

## Expected exact child-node set: node name -> expected presentation/* class.
## "No more, no less" (test_criteria #1) is enforced by comparing this
## Dictionary's size against the live child count, not merely checking each
## expected name is present.
##
## VerbBarView (FEAT-004 / US-004/FR-001) was added here alongside the
## original FEAT-002 set: the Layer 1 verb bar is a legitimate, additional
## presentation/* component wired into MainScene.tscn, not a re-introduction
## of the removed scenes/battlefield/* stack this suite guards against.
## FEAT-007 (this iteration's US-007/FR-010) removed MoveActionControl from
## this set entirely -- presentation/MoveActionControl.gd (the passive "Move"
## indicator) has been deleted; Step/Stride are surfaced solely through
## VerbBarView's own STEP/STRIDE buttons now.
## FEAT-207 (US-013 / FR-015) added ReactionPromptUI here: the player-facing
## blocking reaction pop-up (scenes/ui/reaction_prompt_ui.gd) is a
## legitimate, additional presentation/* component (it lives under
## scenes/ui/, the Presentation layer's scene-tree home for a modal pop-up,
## mirroring every other *_view.tscn instanced directly on MainScene) — not
## a re-introduction of the removed scenes/battlefield/* stack this suite
## guards against. It starts hidden (visible = false) and only becomes
## visible once a live reaction trigger is opened via
## presentation/player_reaction_chooser.gd's PlayerReactionChooser.
const _EXPECTED_CHILDREN: Dictionary = {
	"HexGridView":         HexGridViewClass,
	"StatusPanelView":     StatusPanelViewClass,
	"InitiativeView":      InitiativeViewClass,
	"EventLogView":        EventLogViewClass,
	"TurnController":      TurnControllerClass,
	"EndTurnControl":      EndTurnControlClass,
	"VerbBarView":         VerbBarViewClass,
	"ResultScreenView":    ResultScreenViewClass,
	"ReactionPromptUI":    ReactionPromptUIClass,
}


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=42 (the prologue fixture's known-
## good seed, matching this codebase's established convention — see
## tests/unit/test_main_scene_interactive_wiring.gd) so every scenario below
## can rely on a deterministic first-actor/target layout.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


## _is_expected_handler_script(script) -> bool — true iff `script` belongs to
## the composition root (MainScene.gd) or to any presentation/* module — the
## ONLY legitimate homes for a player-facing signal handler post-FEAT-001/
## FEAT-002 (no scenes/battlefield/* handler may ever appear here).
func _is_expected_handler_script(script) -> bool:
	if script == null:
		return false
	if not (script is Script):
		return false
	var path: String = script.resource_path
	return path == _COMPOSITION_ROOT_SCRIPT_PATH or path.begins_with(_PRESENTATION_SCRIPT_PREFIX)


## _assert_signal_connected_to_presentation_stack(emitter, signal_name,
## description) -> void — shared assertion used by every signal-wiring test
## below: the named signal must have at least one connection, and EVERY
## connection's target object's script must satisfy
## _is_expected_handler_script() (never dangle on a removed battlefield
## handler, never point outside the presentation/composition-root stack).
func _assert_signal_connected_to_presentation_stack(emitter: Object, signal_name: String, description: String) -> void:
	assert_true(emitter.has_signal(signal_name), "%s: emitter must declare signal '%s'" % [description, signal_name])

	var connections: Array = emitter.get_signal_connection_list(signal_name)
	assert_true(connections.size() > 0, "%s: signal '%s' must be connected to at least one handler" % [description, signal_name])

	for connection in connections:
		var callable: Callable = connection.get("callable")
		assert_not_null(callable, "%s: connection must carry a callable" % description)
		var target: Object = callable.get_object()
		assert_not_null(target, "%s: connection target object must be alive" % description)
		if target != null:
			assert_true(
				_is_expected_handler_script(target.get_script()),
				"%s: signal '%s' must be connected exclusively to a presentation/* handler or the MainScene.gd composition root; found target script: %s"
				% [description, signal_name, (target.get_script().resource_path if target.get_script() != null else "<none>")]
			)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — MainScene's children are EXACTLY the expected presentation/*
# component set, no more no less.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_children_are_exactly_the_expected_presentation_stack() -> void:
	var instance = _boot_main_scene()

	var actual_children: Array = instance.get_children()
	var actual_names_by_node: Dictionary = {}
	for child in actual_children:
		actual_names_by_node[child.name] = child

	for expected_name in _EXPECTED_CHILDREN.keys():
		assert_true(
			actual_names_by_node.has(expected_name),
			"MainScene must have a child node named '%s' (FEAT-002 kept presentation/* stack)" % expected_name
		)

	assert_eq(
		actual_children.size(), _EXPECTED_CHILDREN.size(),
		"MainScene must have EXACTLY the expected presentation/* child set, no more no less; found children: %s"
		% [actual_names_by_node.keys()]
	)

	for child_name in actual_names_by_node.keys():
		var expected_class = _EXPECTED_CHILDREN.get(child_name, null)
		assert_not_null(expected_class, "unexpected child node '%s' present on MainScene -- only the FEAT-002 presentation/* set may be wired" % child_name)
		if expected_class != null:
			assert_true(
				is_instance_of(actual_names_by_node[child_name], expected_class),
				"MainScene child '%s' must be an instance of its expected presentation/* class" % child_name
			)


## movement_input_controller (FEAT-013) is the 9th expected presentation/*
## component per the feature spec, but it is a plain RefCounted adapter (see
## presentation/movement_input_controller.gd), not a Control/Node -- so it is
## instantiated as a plain field, not added to the scene tree, and therefore
## deliberately does NOT appear in get_children() / the exact-child-set
## assertion above. Verified here instead, directly on the field, so a future
## accidental re-implementation as a Node (which WOULD grow the child count
## above) is caught by test_mainscene_children_are_exactly_the_expected_presentation_stack.
func test_mainscene_wires_movement_input_controller_as_the_sole_movement_pathway() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.movement_input_controller, "MainScene must wire a movement_input_controller (FEAT-002 kept presentation/* stack)")
	assert_true(
		is_instance_of(instance.movement_input_controller, MovementInputControllerClass),
		"MainScene.movement_input_controller must be a real presentation/movement_input_controller.gd MovementInputController"
	)
	assert_false(
		instance.movement_input_controller is Node,
		"movement_input_controller must remain a plain RefCounted adapter, never a scene Node (it must not appear in get_children())"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — every expected player-facing interaction signal is connected
# exclusively to a presentation/*-or-composition-root handler.
# ══════════════════════════════════════════════════════════════════════════

## FEAT-007 (iteration D) deleted the legacy "click any highlighted hex to
## auto Step-or-Stride" affordance, deliberately leaving HexGridView.
## hex_clicked unconnected from the composition root for "a future Layer 2
## SelectionOverlay" to subscribe to. FEAT-008 (US-008, this iteration) is
## that feature: hex_clicked is now connected to exactly ONE handler --
## presentation/selection_overlay.gd SelectionOverlay's own internal click
## resolver (_on_hex_clicked), wired by MainScene.gd's composition root via
## selection_overlay.configure() -- never a re-introduction of the deleted
## auto-move handler itself. Step/Stride still resolve exclusively through
## the verb registry (SelectionOverlay.execute()-dispatches into it, no
## forked path) -- see
## test_step_and_stride_verbs_are_wired_to_the_presentation_stack_and_move_the_token
## below.
func test_hex_clicked_signal_is_wired_to_the_selection_overlay() -> void:
	var instance = _boot_main_scene()

	assert_true(instance.hex_grid_view.has_signal("hex_clicked"), "HexGridView must still declare the hex_clicked signal")
	var connections: Array = instance.hex_grid_view.get_signal_connection_list("hex_clicked")
	assert_eq(
		connections.size(), 1,
		"HexGridView.hex_clicked must carry EXACTLY ONE connection from this composition root -- the FEAT-008 SelectionOverlay subscriber, never the deleted legacy auto Step-or-Stride handler"
	)
	if connections.size() > 0:
		var target: Object = connections[0].get("callable").get_object()
		assert_eq(
			target, instance.selection_overlay,
			"HexGridView.hex_clicked's sole connection must target MainScene's own selection_overlay (presentation/selection_overlay.gd), not a re-introduced legacy handler"
		)


## "Step"/"Stride" verb-registry wiring -- FEAT-007 (this iteration's
## US-007/FR-010) removed the earlier MoveActionControl node and the
## hex_grid_view.hex_clicked auto-resolve handler; Step/Stride are now driven
## exclusively through $VerbBarView pressing "STEP"/"STRIDE" (entering Layer 2
## selection) followed by `_verb_registry.execute(verb_id, destination_hex)` --
## proven here both statically (VerbBarView's own rendered "STEP"/"STRIDE"
## Buttons are wired to a presentation/* handler --
## VerbBarView._on_verb_button_pressed) and behaviorally (driving the full
## verb-bar-press -> registry.execute() path genuinely moves the active
## combatant's token through the injected movement_input_controller, exactly
## as a real player interaction would).
func test_step_and_stride_verbs_are_wired_to_the_presentation_stack_and_move_the_token() -> void:
	var instance = _boot_main_scene()

	assert_true(
		instance._verb_registry.is_available("STEP"),
		"fixture assumption: the prologue's first actor has at least one legal Step destination at boot"
	)

	var button: Button = instance.verb_bar_view.get_button("STEP")
	assert_not_null(button, "VerbBarView must render a STEP button when the verb is available")
	_assert_signal_connected_to_presentation_stack(button, "pressed", "VerbBarView's rendered STEP Button.pressed (step pressed)")

	var selection: Dictionary = instance.verb_bar_view.press("STEP")
	var destination_hexes: Array = selection.get("candidate_hexes", [])
	assert_true(destination_hexes.size() > 0, "entering STEP's Layer 2 selection must surface at least one legal destination hex")

	var actor_id: String = instance.round_session.current_actor().display_id()
	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "fixture assumption: the active actor already has a rendered token")
	var destination = destination_hexes[0]
	assert_false(token_before.hex_coord.equals(destination), "sanity check: the chosen destination differs from the actor's starting hex")

	var result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(result.get("ok", false), "executing STEP against the selected destination must resolve a real Step")

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_true(
		token_after.hex_coord.equals(destination),
		"resolving STEP through the verb registry must flow through movement_input_controller and move the real HexGridView token"
	)


## TurnController's "turn started" signal (design notes' API contract #1's
## turn_started) is realized in this codebase as active_actor_changed --
## emitted whenever the turn driver settles on a new (player) current actor,
## i.e. it becomes that combatant's turn.
func test_turn_started_signal_is_connected_to_the_presentation_stack() -> void:
	var instance = _boot_main_scene()
	_assert_signal_connected_to_presentation_stack(
		instance.turn_controller, "active_actor_changed",
		"TurnController.active_actor_changed (turn_started)"
	)


func test_turn_ended_signal_is_connected_to_the_presentation_stack() -> void:
	var instance = _boot_main_scene()
	_assert_signal_connected_to_presentation_stack(
		instance.end_turn_control, "turn_ended",
		"EndTurnControl.turn_ended"
	)


## "strike pressed" -- FEAT-006 (US-006) removed the old immediate-click
## StrikeActionControl (and its rendered per-target Button) entirely; Strike
## is now driven exclusively through $VerbBarView pressing "STRIKE" (entering
## Layer 2 selection) followed by `_verb_registry.execute("STRIKE",
## target_id)` -- proven here both statically (VerbBarView's own rendered
## "STRIKE" Button.pressed is wired to a presentation/* handler --
## VerbBarView._on_verb_button_pressed) and behaviorally (driving the full
## verb-bar-press -> registry.execute() path genuinely resolves a real Strike
## through the injected resolve_action_use_case, exactly as a real player
## interaction would, so this is proven to be a LIVE connection, not merely a
## same-named but dead one).
func test_strike_verb_is_wired_to_the_presentation_stack_and_resolves_a_strike() -> void:
	var instance = _boot_main_scene()

	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"fixture assumption: the prologue's first actor has at least one in-reach target at boot"
	)

	var button: Button = instance.verb_bar_view.get_button("STRIKE")
	assert_not_null(button, "VerbBarView must render a STRIKE button when the verb is available")
	_assert_signal_connected_to_presentation_stack(button, "pressed", "VerbBarView's rendered STRIKE Button.pressed (strike pressed)")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "entering STRIKE's Layer 2 selection must surface at least one in-reach target")

	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events logged yet before the simulated Strike")
	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(result.get("ok", false), "executing STRIKE against the selected target must resolve a real Strike")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"resolving STRIKE through the verb registry must flow through the presentation/* handler and resolve a real Strike, observable via EventLogView"
	)


## "end_turn pressed" -- proven both statically (EndTurnControl's own Button's
## `pressed` signal is wired to a presentation/* handler --
## EndTurnControl._on_button_pressed) and behaviorally (emitting it genuinely
## forwards to RoundSession.end_current_turn(), exactly as a real player
## click would).
func test_end_turn_pressed_is_wired_to_the_presentation_stack_and_ends_the_turn() -> void:
	var instance = _boot_main_scene()

	var button: Button = instance.end_turn_control.get_node("Button")
	_assert_signal_connected_to_presentation_stack(button, "pressed", "EndTurnControl's Button.pressed (end_turn pressed)")

	var events_before: int = instance.event_sink.log.size()
	button.pressed.emit()

	assert_true(
		instance.event_sink.log.size() > events_before,
		"emitting EndTurnControl's Button.pressed signal must flow through the presentation/* handler and end the current turn, observable via the real event sink"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — MainScene.tscn still boots headlessly with zero compile/
# runtime errors after this feature's re-verification/re-wiring.
# ══════════════════════════════════════════════════════════════════════════

func test_headless_boot_still_succeeds_after_presentation_stack_rewiring() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup")
	if instance == null:
		return

	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after first frame")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")

	for expected_name in _EXPECTED_CHILDREN.keys():
		assert_not_null(instance.get_node_or_null(expected_name), "MainScene must still resolve child node '%s' after headless boot" % expected_name)
