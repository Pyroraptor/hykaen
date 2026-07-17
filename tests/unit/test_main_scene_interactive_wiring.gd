extends GutTest
## tests/unit/test_main_scene_interactive_wiring.gd
##
## GUT test suite for FEAT-123 (US-004/US-009/US-010/US-011/US-012,
## FIND-120): MainScene.gd's _ready() now builds the INTERACTIVE pipeline —
## RunRoundUseCase.begin_round() -> RoundSession, driven by
## $TurnController/$VerbBarView(`_verb_registry`'s STRIKE entry)/
## $EndTurnControl/$ResultScreenView — instead of autonomously resolving the
## whole prologue encounter via core/combat/encounter.gd's run_round()
## while-loop with no player input.
##
## FEAT-182 (DEF-001 / FR-009/NFR-003): FEAT-006 (US-006) later removed the
## legacy immediate-resolve-on-click Strike control entirely (its .gd/.tscn
## pair, formerly under presentation/) -- Strike is now driven SOLELY
## through the Layer 1 verb bar
## ($VerbBarView, presentation/verb_bar_view.gd) -> `_verb_registry`'s
## STRIKE entry (see MainScene.gd's file-level FEAT-006 doc). This file's
## Strike-driving criteria below (2 and 3) are retargeted onto that real
## verb-registry flow (`_verb_registry.is_available()`/`enter_selection()`/
## `execute()`, entered via the real `verb_bar_view.press("STRIKE")`)
## instead of the deleted control, preserving their original regression
## intent unchanged.
##
## Verifies (test_criteria):
##   1. MainScene._ready() invokes RunRoundUseCase.begin_round() and
##      TurnController.set_session() with a real, non-null RoundSession.
##   2. `_verb_registry`'s STRIKE entry (via $VerbBarView), $EndTurnControl,
##      and $ResultScreenView are configured (non-null session/live-target
##      references) immediately after MainScene._ready() completes.
##   3. Simulating a Strike via the real $VerbBarView -> `_verb_registry`
##      path on the real MainScene instance emits an AttackEvent through the
##      real event-sink adapter, observable via the real
##      EventLogView/StatusPanelView.
##   4. Pressing $EndTurnControl invokes RoundSession.end_current_turn(), the
##      turn cursor advances, and TurnController disables player input while
##      the enemy turn resolves via RoundSession.advance_ai_turn().
##   5. Regression: MainScene no longer auto-resolves the entire encounter
##      on boot with no input (the old autonomous run_round() while-loop
##      path is not exercised).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundSessionClass    = preload("res://core/application/round_session.gd")
const RunRoundUseCaseClass = preload("res://core/application/run_round_use_case.gd")
const RoundEventsClass     = preload("res://core/rules/round_events.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")


## FEAT-002 / US-002: this whole file's scenarios assume the prologue
## fixture's known-good playthrough (Titus, the party member, acts first;
## no round event is logged before a test's own simulated Strike/End Turn) --
## an assumption that only holds for the prologue fixture's original seed=42
## initiative roll. A real (non-override) MainScene launch now resolves a
## fresh, randomized play seed every boot (which could just as validly seat
## the Skeleton first), so every boot in this file pins that known-good seed
## explicitly via the in-process `seed_override` composition-root contract
## instead of relying on MainScene's randomized default.
## FEAT-006 (US-005/FR-005, ADR-002): MainScene now wires RoundSession's
## enemy-strikes-player reaction window to the REAL, blocking
## TurnController.resolve_reaction() -> PlayerReactionChooser ->
## $ReactionPromptUI chain, which has "no auto-timeout" by design and
## suspends until an actual player clicks an option. This suite's End-Turn
## criteria drive Skeleton's real AI-controlled Strike against Titus
## headlessly with no player present, so the injected ReactionChooserPort is
## swapped for infrastructure/auto_reaction_chooser.gd's
## AutoReactionChooser("pass") immediately after boot -- the SAME headless
## double every other reaction-system suite already uses -- via
## TurnController.configure_reactions()'s own documented "safe to call any
## number of times" contract. Reproduces the exact pre-FEAT-006 "none"/PASS
## default this suite's assertions were written against; the REAL
## PlayerReactionChooser is still what MainScene.gd wires for an actual
## player session.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _strike_candidate_target_ids(instance) -> Array — obtains the currently
## selectable Strike target ids through the REAL $VerbBarView.press("STRIKE")
## -> `_verb_registry.enter_selection("STRIKE")` path (FEAT-182), mirroring
## $VerbBarView.press()'s own non-END_TURN dispatch exactly (see
## presentation/verb_bar_view.gd) rather than reaching into `_verb_registry`
## directly for this step.
func _strike_candidate_target_ids(instance) -> Array:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	return selection.get("candidate_targets", [])


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: _ready() invokes RunRoundUseCase.begin_round() and
# TurnController.set_session() with a real, non-null RoundSession.
# ══════════════════════════════════════════════════════════════════════════

func test_ready_obtains_a_real_round_session_via_run_round_use_case() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.run_round_use_case, "MainScene must wire a RunRoundUseCase")
	assert_is(instance.run_round_use_case, RunRoundUseCaseClass, "MainScene.run_round_use_case must be a real RunRoundUseCase")

	assert_not_null(instance.round_session, "MainScene.round_session must be non-null after _ready()")
	assert_is(instance.round_session, RoundSessionClass, "MainScene.round_session must be a real RoundSession (begin_round()'s return value)")


func test_ready_hands_the_round_session_to_turn_controller() -> void:
	var instance = _boot_main_scene()

	# TurnController.set_session() was called with the live RoundSession --
	# proven behaviorally (no private-field reach-through, matching this
	# codebase's established testing convention): EndTurnControl's enabled
	# state is derived exclusively from a RoundSession injected via
	# set_session()/configure(), and it reflects the session's actual
	# current_actor() (Titus, the party member, per prologue_encounter.tres'
	# hex layout already established by tests/integration/
	# test_steel_thread_prologue_encounter.gd).
	assert_true(
		instance.end_turn_control.is_enabled(),
		"TurnController must have configured EndTurnControl from the live RoundSession, enabled for the first (player) actor"
	)
	assert_false(instance.round_session.current_actor().get("_is_enemy", true))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: `_verb_registry`'s STRIKE entry (via $VerbBarView) /
# $EndTurnControl / $ResultScreenView are configured (non-null session/
# live-target references) immediately after MainScene._ready() completes.
# ══════════════════════════════════════════════════════════════════════════

func test_verb_registry_strike_is_configured_with_live_targets_after_ready() -> void:
	var instance = _boot_main_scene()

	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"`_verb_registry`'s STRIKE entry must be available immediately after _ready() with a live, in-reach target"
	)
	var selectable: Array = _strike_candidate_target_ids(instance)
	assert_true(
		selectable.size() > 0,
		"`_verb_registry`'s STRIKE entry must be configured with the active player's live, in-reach targets immediately after _ready()"
	)


func test_end_turn_control_is_configured_after_ready() -> void:
	var instance = _boot_main_scene()

	assert_true(
		instance.end_turn_control.is_enabled(),
		"EndTurnControl must be configured (enabled for the active player combatant) immediately after _ready()"
	)


func test_result_screen_view_is_configured_and_not_yet_shown_after_ready() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.result_screen_view, "MainScene must expose a non-null result_screen_view")
	assert_false(
		instance.result_screen_view.is_shown(),
		"ResultScreenView must not show a result immediately after _ready() -- no input has been given yet"
	)

	# ResultScreenView was configured with the live combat controls (US-012):
	# proven behaviorally by triggering its disable path and observing both
	# controls actually clear, rather than reaching into private fields.
	# FEAT-182: since FEAT-006 removed the legacy Strike control, Strike's own
	# lock proof is now $VerbBarView.is_locked()/press("STRIKE") rejection
	# (FEAT-177 / US-013's extension of this SAME lock mechanism to the verb
	# bar), rather than the deleted control's get_button_count().
	instance.result_screen_view.on_encounter_result_event(RoundEventsClass.EncounterResultEvent.new(1, "won"))
	assert_true(
		instance.verb_bar_view.is_locked(),
		"ResultScreenView must have been configured with verb_bar_view (US-012/US-013 disable-on-conclusion contract)"
	)
	assert_eq(
		instance.verb_bar_view.press("STRIKE"), {"ok": false, "error": "ENCOUNTER_ALREADY_RESOLVED"},
		"a locked $VerbBarView must reject a STRIKE press once the encounter has concluded"
	)
	assert_false(
		instance.end_turn_control.is_enabled(),
		"ResultScreenView must have been configured with end_turn_control (US-012 disable-on-conclusion contract)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: simulating a Strike via the real $VerbBarView ->
# `_verb_registry` path on the real MainScene instance emits an AttackEvent
# through the real event-sink adapter, observable via
# EventLogView/StatusPanelView.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_via_verb_registry_emits_attack_event_through_real_event_sink() -> void:
	var instance = _boot_main_scene()

	var target_ids: Array = _strike_candidate_target_ids(instance)
	assert_true(target_ids.size() > 0, "fixture assumption: the prologue's first actor has at least one in-reach target")
	var target_id: String = target_ids[0]

	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events logged yet before any Strike")

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_id)

	assert_true(result.get("resolved", false), "the real resolve_action_use_case must resolve the Strike")
	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the AttackEvent must flow through MainScene's real event sink to the real EventLogView"
	)

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "MainScene's real event-sink adapter must have observed exactly one AttackEvent")

	var target_combatant = null
	for enemy in instance._enemies:
		if enemy.display_id() == target_id:
			target_combatant = enemy
			break
	assert_false(target_combatant == null, "fixture assumption: the selected target must be one of MainScene's live enemy combatants")

	# StatusPanelView clamps a displayed HP at 0 (it never shows an "overkill"
	# negative value), while the live domain Dictionary MainScene mutates may
	# go negative -- compare against the same floor StatusPanelView applies.
	var status: Dictionary = instance.status_panel_view.get_status(target_id)
	assert_eq(
		status.get("hp_current", -1), maxi(target_combatant.hp_current, 0),
		"StatusPanelView must reflect the Strike's outcome (the SAME live combatant Dictionary MainScene mutated) via the real event-sink pipeline"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: pressing $EndTurnControl invokes RoundSession.end_current_turn(),
# the cursor advances, and TurnController disables player input while the
# enemy turn resolves via RoundSession.advance_ai_turn().
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_end_turn_control_advances_cursor_and_auto_drives_enemy_turn() -> void:
	var instance = _boot_main_scene()

	var first_actor_name: String = instance.round_session.current_actor().get("name", "")
	assert_ne(first_actor_name, "", "fixture assumption: a living actor is active before End Turn is pressed")

	var events_before: int = instance.event_sink.log.size()

	var press_result: Dictionary = instance.end_turn_control.press()
	assert_true(press_result.get("ok", false), "EndTurnControl.press() must forward to RoundSession.end_current_turn() successfully")

	# RoundSession.end_current_turn() must have run: with only two
	# combatants in the prologue encounter (Titus/Skeleton), the cursor
	# fully cycles back to the SAME first actor once TurnController has
	# auto-driven the Skeleton's Enemy turn in between (US-011) -- so the
	# turn cursor having genuinely moved is proven via the event trail
	# (at least one TurnAdvancedEvent), not by the settled actor's name
	# differing from where it started.
	var turn_advanced_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
	assert_true(
		instance.round_session.is_round_over() or turn_advanced_events.size() >= 1,
		"RoundSession.end_current_turn() must advance the turn cursor (or conclude the round)"
	)

	if not instance.round_session.is_round_over():
		# The prologue's only two combatants alternate; once end_current_turn()
		# moves the cursor off the player, TurnController must have auto-driven
		# the enemy's turn via advance_ai_turn() (US-011) and settled back on a
		# living player combatant -- proven via the TurnAdvancedEvent trail
		# through the real event sink (at least one for the player->enemy
		# transition end_current_turn() itself emits, plus one more for the
		# enemy->player transition advance_ai_turn() emits when it advances the
		# cursor again).
		assert_false(
			instance.round_session.current_actor().get("_is_enemy", false),
			"TurnController must auto-drive any Enemy turn so the session settles back on a player combatant"
		)

		var turn_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.TurnAdvancedEvent)
		assert_true(
			turn_events.size() >= 2,
			"both end_current_turn()'s and advance_ai_turn()'s cursor advances must be observable through the real event sink"
		)

		# `_verb_registry`'s STRIKE entry must have been unavailable while the
		# enemy turn was auto-driven, then reconfigured with live targets for
		# the player's new turn (FIND-120) -- i.e. it must NOT be left
		# unavailable once settled (FEAT-182: retargeted off the deleted
		# legacy Strike control onto the real verb-registry entry).
		assert_true(
			instance._verb_registry.is_available("STRIKE"),
			"`_verb_registry`'s STRIKE entry must be available once the driver settles back on the player"
		)
		assert_true(
			_strike_candidate_target_ids(instance).size() > 0,
			"`_verb_registry`'s STRIKE entry must be reconfigured with live targets once the driver settles back on the player"
		)

	assert_true(
		instance.event_sink.log.size() > events_before,
		"ending the turn must have emitted at least one new round event through the real event sink"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 (regression): MainScene no longer auto-resolves the entire
# encounter on boot without any input.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_does_not_auto_resolve_the_encounter_without_any_input() -> void:
	var instance = _boot_main_scene()

	assert_eq(
		instance.outcome, "",
		"MainScene must NOT auto-resolve the encounter to a terminal outcome on boot -- the old autonomous run_round() while-loop path must not run"
	)
	assert_false(
		instance.round_session.is_round_over(),
		"the freshly-begun RoundSession must not already be over immediately after _ready() with no player input"
	)
	assert_false(
		instance.result_screen_view.is_shown(),
		"ResultScreenView must not have received an EncounterResultEvent from an autonomous boot-time resolution"
	)

	# The pre-existing Encounter composition helper is reused ONLY for
	# initiative/ActionEconomy bookkeeping (see MainScene.gd step 7) --
	# its own round counter must never advance, proving run_round() was
	# never invoked.
	assert_eq(
		instance.encounter.get_round_count(), 0,
		"core/combat/encounter.gd's run_round() must never be invoked by this composition root (FIND-120)"
	)


# ══════════════════════════════════════════════════════════════════════════
# FEAT-015 / US-015 / FR-016: MainScene wires Flanking.is_off_guard()
# (core/rules/flanking.gd) into $StatusPanelView so Off-Guard is surfaced
# live in the per-combatant readout as combatants move around the field.
# The prologue fixture only seats one party member (Titus) and one enemy
# (Skeleton, at hex (1,0), with Titus already at hex (0,0) -- one of
# Skeleton's 6 flat-top axial neighbors), so a second, synthetic party
# combatant is appended directly to MainScene's live `_party` Array (a
# Dictionary of the SAME shape _build_party_combatant() already produces)
# to exercise the two-flanker positive case through the REAL composition-root
# wiring (_refresh_off_guard_conditions()), not a re-derived/mocked copy of
# the flanking rule.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_off_guard_is_false_when_only_a_single_combatant_is_adjacent() -> void:
	var instance = _boot_main_scene()
	var target_id: String = instance._enemies[0].display_id()

	assert_false(
		instance.status_panel_view.is_off_guard(target_id),
		"fixture assumption: only Titus is adjacent to Skeleton at boot -- one flanker alone must not flag Off-Guard"
	)


func test_off_guard_wiring_flags_target_once_two_opposing_combatants_flank_it() -> void:
	var instance = _boot_main_scene()
	var target_id: String = instance._enemies[0].display_id()

	# Skeleton sits at hex (1,0); Titus already occupies (0,0), the neighbor
	# directly opposite hex (2,0) around Skeleton. Appending a second party
	# combatant at (2,0) completes the opposite-adjacent flanking pair.
	var ally: Dictionary = {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "synthetic_ally_off_guard_test",
		"hex_coord": HexCoordClass.new(2, 0),
	}
	instance._party.append(ally)
	instance._refresh_off_guard_conditions()

	assert_true(
		instance.status_panel_view.is_off_guard(target_id),
		"MainScene must push Flanking.is_off_guard()'s true result into StatusPanelView via set_off_guard()"
	)
	assert_true(
		"Off-Guard" in instance.status_panel_view.get_status(target_id).get("conditions", []),
		"the readout's conditions list must contain Off-Guard once the target is flanked"
	)


func test_off_guard_wiring_does_not_flag_target_for_non_opposite_flankers() -> void:
	var instance = _boot_main_scene()
	var target_id: String = instance._enemies[0].display_id()

	# hex (1,-1) is adjacent to Skeleton (1,0) but NOT opposite Titus's
	# (0,0) -- a non-opposite second flanker must not flag Off-Guard.
	var ally: Dictionary = {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "synthetic_ally_non_opposite_test",
		"hex_coord": HexCoordClass.new(1, -1),
	}
	instance._party.append(ally)
	instance._refresh_off_guard_conditions()

	assert_false(
		instance.status_panel_view.is_off_guard(target_id),
		"a non-opposite second adjacent combatant must not flag Off-Guard (blanket rule requires directly-opposite hexes)"
	)


func test_off_guard_wiring_clears_once_a_flanker_moves_away() -> void:
	var instance = _boot_main_scene()
	var target_id: String = instance._enemies[0].display_id()

	var ally: Dictionary = {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": "synthetic_ally_unflank_test",
		"hex_coord": HexCoordClass.new(2, 0),
	}
	instance._party.append(ally)
	instance._refresh_off_guard_conditions()
	assert_true(instance.status_panel_view.is_off_guard(target_id), "fixture setup: target must be Off-Guard before the ally moves away")

	ally["hex_coord"] = HexCoordClass.new(9, 9)
	instance._refresh_off_guard_conditions()

	assert_false(
		instance.status_panel_view.is_off_guard(target_id),
		"Off-Guard must clear once a flanker moves off the opposite-adjacent hex (live recompute, not a sticky flag)"
	)
