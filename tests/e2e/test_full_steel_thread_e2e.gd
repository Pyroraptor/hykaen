extends GutTest
## tests/e2e/test_full_steel_thread_e2e.gd — FEAT-167
## (US-005..US-011, iteration D "UI Consolidation + Movement UX" capstone);
## retargeted by FEAT-006/FEAT-007 (this iteration's two-layer verb->target/
## destination UX, US-006/US-007/FR-009/FR-010).
##
## THE final E2E smoke test exercising the COMPLETE steel thread, entry to
## exit, through the real, fully-consolidated res://MainScene.tscn
## composition root (project.godot's own run/main_scene target) — no
## test-local resolver/use-case/session graph, no mocked Application-layer
## port anywhere in this file. Every collaborator driven below (HexGridView,
## EndTurnControl, StatusPanelView, VerbBarView, ResultScreenView,
## movement_input_controller, TurnController, resolve_action_use_case,
## RoundSession, `_verb_registry`) is the exact, unmodified, REUSED
## production instance MainScene.gd's own _ready() wires — this file's job is
## proving they ALL compose correctly together, one continuous playthrough,
## from turn start through post-resolution lock.
##
## The single continuous journey this file drives:
##   1. Boot -> the active player's turn_started (TurnController.
##      active_actor_changed, this codebase's realization of the design
##      notes' API contract #1) highlights the EXACT union(Step, Stride) hex
##      set on the real HexGridView (US-006).
##   2. Executing the Layer 1 STEP verb (VerbBarView.press("STEP") ->
##      `_verb_registry`'s enter_selection()/execute()) against one of those
##      highlighted hexes moves the token via movement_input_controller's
##      real step_to() dispatch, resyncs HexGridView's rendered token
##      position, and the highlight is cleared then re-derived from the
##      mover's NEW position (US-006/US-008). FEAT-007 (this iteration's
##      US-007/FR-010): this is now the SOLE way a Step/Stride can be
##      performed — the legacy "click any highlighted hex to auto
##      Step-or-Stride" affordance (and its passive presentation/
##      MoveActionControl.gd "Move" indicator) has been deleted; a stray
##      hex_grid_view.hex_clicked emission is proven to be a pure no-op below.
##   3. A real Strike, driven through the Layer 1 STRIKE verb
##      (VerbBarView.press("STRIKE") -> `_verb_registry`'s
##      enter_selection()/execute()) -> resolve_action_use_case.resolve(),
##      decrements the acting combatant's action budget as reflected by the
##      real StatusPanelView's projection (US-009).
##   4. The encounter is driven to resolution (bounded, real VerbBarView/
##      EndTurnControl input, exactly as a human would drive it) — once
##      EncounterResolved (EncounterResultEvent) fires, VerbBarView's
##      STRIKE/STEP/STRIDE verbs and EndTurnControl are all
##      unavailable/disabled, the hex highlight is cleared, and no further
##      hex_clicked/verb-execute/EndTurn signal produces any state mutation
##      (US-005/US-008/US-010/US-011).
##
## FEAT-167's original gap-closing rationale (presentation/
## result_screen_view.gd's lock_all_controls() must lock EVERY combat/
## movement input surface, regardless of which of RoundSession's two
## outcome-decision call paths — advance_ai_turn()/end_current_turn() —
## actually decided the encounter) still holds; this suite still drives
## exactly that path (the player's own Strike/EndTurn deciding "won") so the
## fix stays exercised. FEAT-007 (this iteration) removed
## presentation/MoveActionControl.gd (the one Control that gap used to
## additionally lock) entirely — Step/Stride are surfaced solely through
## $VerbBarView's own STEP/STRIDE buttons now, re-gated by the SAME
## verb_bar_view.refresh_availability() every other verb already relies on,
## so there is no separate visible-affordance Control left needing its own
## lock() call.
##
## No production Application/Domain code is modified for this feature —
## ADR-001: no file gains a Node/Control import it didn't already have,
## nothing re-implements any rule.
##
## FEAT-198 (DEF-QA-001): this file's original continuous playthrough above
## exercises the PLAYER leg of the steel thread in detail but, before this
## feature, asserted NOTHING about the enemy AI leg — no checks for AI
## Stride-toward-nearest-target, hex-distance reduction, conditional Strike,
## action-economy/lockout compliance, or on-screen token reposition for the
## enemy actor. Against THIS fixture (seed=42, prologue_encounter.tres),
## Titus's own Layer 1 STRIKE verb (Step 3 above) lands a critical hit that
## defeats the sole Skeleton enemy before the encounter is ever handed back
## to it — round_session.advance_ai_turn() is never even reached by the
## continuous playthrough, which is exactly the documented DEF-QA-001
## coverage gap. The two suites appended at the bottom of this file close
## that gap by driving the SAME real, unmodified res://MainScene.tscn
## composition root (no new test file, no duplicate steel-thread
## playthrough) with the enemy's pre-turn position relocated (via the SAME
## "hex_coord" Dictionary-key mutation point core/rules/movement.gd's own
## _set_hex() uses) so the real AI (core/combat/ai.gd) actually reaches its
## Stride / Stride-then-Strike / Stride-with-no-action-remaining branches
## this run, through the EXACT SAME advance_ai_turn()/move_token() call path
## already exercised (for the "already in reach" branch) by the continuous
## playthrough above. No production Application/Domain/Presentation code is
## modified by this feature either — only this test file gains assertions.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const HexGridViewClass    = preload("res://presentation/hex_grid_view.gd")
const RoundEventsClass    = preload("res://core/rules/round_events.gd")
const HexMathClass        = preload("res://core/geometry/hex_math.gd")
const HexCoordClass       = preload("res://core/geometry/hex_coord.gd")
const ActionEconomyClass  = preload("res://core/rules/action_economy.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) — injected
## in-process via MainScene's `seed_override` contract (ADR-004 top
## precedence), mirroring every other integration/E2E suite's convention
## (tests/integration/test_steel_thread_prologue_encounter.gd,
## tests/integration/test_movement_affordance_integration.gd,
## tests/integration/test_status_bar_refresh_integration.gd).
const SEED: int = 42

## Safety bound on the Strike/End-Turn drive loop (CWE-835 "never loop
## unbounded" guard, mirroring tests/integration/
## test_steel_thread_prologue_encounter.gd's `_MAX_DRIVE_ITERATIONS` and
## tests/e2e/test_steel_thread_post_remediation_smoke.gd's
## `_MAX_TURN_EXCHANGES`).
const _MAX_DRIVE_ITERATIONS: int = 20


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture: boot the REAL res://MainScene.tscn composition root.
# ══════════════════════════════════════════════════════════════════════════

## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives the whole steel thread
## directly against `round_session`/`_verb_registry`/`movement_input_controller`,
## so `_boot_main_scene_with_seed()` now also drives the SAME real handoff,
## landing the instance in GameMode.COMBAT with a live round_session before
## returning.
##
## FEAT-007 (US-007 / FR-007, ADR-004): MainScene now wires a REAL
## pathfinder_fn into the AI decision port (_rewire_combat_pathfinder()), so
## an AI-controlled Stride computes a genuine multi-hex path instead of the
## pre-feature direct [origin, destination] fallback -- meaning a transit hex
## can now legitimately sit adjacent to a living reactor mid-Stride and open
## a real Opportunistic Strike window (exactly the "evaluate per transit hex"
## behavior this steel thread's own OS feature was built for). This suite's
## enemy-relocation suites below deliberately place the enemy far enough away
## that its Stride's path passes adjacent to the player, so a real window can
## now open where none did before this feature wired the AI pathfinder seam.
## The SAME headless AutoReactionChooser("pass") double every other
## reaction-system suite already uses (see
## tests/unit/test_main_scene_interactive_wiring.gd's identical swap-in) is
## wired here immediately after boot so any such window auto-resolves
## instead of hanging on an unattended real player reaction prompt -- the
## REAL PlayerReactionChooser is still what MainScene.gd wires for an actual
## player session; only this headless suite swaps it out.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
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


## _find_combatant_by_id(instance, combatant_id) -> Dictionary — looks up a
## live combatant Dictionary (MainScene's own _party/_enemies fields, the
## SAME Dictionaries core/rules/movement.gd/resolve_action_use_case.gd mutate
## in place), mirroring the identically-named helper already established by
## tests/integration/test_steel_thread_prologue_encounter.gd /
## tests/integration/test_movement_affordance_integration.gd.
func _find_combatant_by_id(instance, combatant_id: String):
	for combatant in instance._party + instance._enemies:
		if combatant.combatant_id == combatant_id:
			return combatant
	return null


## _find_action_economy_by_id(instance, combatant_id) -> ActionEconomy or
## null — FEAT-198 (DEF-QA-001): looks up the live ActionEconomy paired with
## `combatant_id` in the real, booted RoundSession's own turn-order entries
## (`_entries`, the SAME per-actor {combatant, action_economy} pairing
## RoundSession.advance_ai_turn()/current_action_economy() already read from
## — see core/application/round_session.gd). Read directly off the
## underscore-prefixed field, mirroring the established non-invasive
## observation convention this suite already uses for `hex_grid_view.
## _selectable_hexes` and tests/integration/test_ai_token_reposition.gd's
## `round_session._token_reposition_fn` inspection — never a mock/stub, just
## reading state off the real, unmodified production RoundSession instance.
func _find_action_economy_by_id(instance, combatant_id: String):
	for entry in instance.round_session._entries:
		var c = entry.get("combatant")
		if c != null and c.combatant_id == combatant_id:
			return entry.get("action_economy")
	return null


## _as_key_set(hexes) -> Dictionary — a "q,r" -> true set built from an
## Array of core/geometry/hex_coord.gd HexCoords, mirroring
## tests/integration/test_movement_affordance_integration.gd's
## identically-named helper (HexCoord is a value object with no custom
## `==`/hash, so this is the correct value-equality comparison,
## order/instance-identity independent).
func _as_key_set(hexes: Array) -> Dictionary:
	var set: Dictionary = {}
	for hex_coord in hexes:
		set["%d,%d" % [hex_coord.q, hex_coord.r]] = true
	return set


## _assert_highlight_matches_controller_union(instance, context) -> void —
## asserts the REAL HexGridView's currently-highlighted set (read directly
## off `_selectable_hexes`, the established non-invasive convention — see
## tests/integration/test_movement_affordance_integration.gd's file-level
## doc for why this is the correct way to observe it without a stub/mock)
## exactly equals union(movement_input_controller.get_selectable_step_hexes(),
## get_selectable_stride_hexes()) computed RIGHT NOW (API contract #3: "no
## filtering/re-derivation in the view").
func _assert_highlight_matches_controller_union(instance, context: String) -> void:
	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	var expected_keys: Dictionary = _as_key_set(step_hexes)
	for key in _as_key_set(stride_hexes).keys():
		expected_keys[key] = true

	var highlighted: Array = instance.hex_grid_view._selectable_hexes
	var highlighted_keys: Dictionary = _as_key_set(highlighted)

	assert_eq(
		highlighted_keys.keys().size(), expected_keys.keys().size(),
		"[%s] the real HexGridView's highlighted hex count must exactly equal union(Step, Stride)" % context
	)
	for key in expected_keys.keys():
		assert_true(highlighted_keys.has(key), "[%s] expected union hex %s to be highlighted" % [context, key])
	for key in highlighted_keys.keys():
		assert_true(expected_keys.has(key), "[%s] highlighted hex %s must be present in union(Step, Stride) -- no extra/filtered hex" % [context, key])


# ══════════════════════════════════════════════════════════════════════════
# THE full steel thread, one continuous playthrough through the real,
# fully-consolidated MainScene composition root.
# ══════════════════════════════════════════════════════════════════════════

func test_full_steel_thread_from_turn_start_to_post_resolution_lock() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	# ── Fixture assumptions (seed=42, prologue_encounter.tres) ─────────────
	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: the first actor must be the living player combatant (Titus) per prologue_encounter.tres' hex layout at seed=42"
	)
	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")


	# ══════════════════════════════════════════════════════════════════════
	# Step 1 (US-006) — on the active player's turn_started, the real
	# HexGridView highlights the EXACT legal Step/Stride union.
	# ══════════════════════════════════════════════════════════════════════

	var step_hexes_at_start: Array = instance.movement_input_controller.get_selectable_step_hexes()
	var stride_hexes_at_start: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	assert_true(step_hexes_at_start.size() > 0, "sanity check: the active player actor has at least one legal Step destination")
	assert_true(
		stride_hexes_at_start.size() >= step_hexes_at_start.size(),
		"sanity check: Stride (up to Speed hexes) must legally reach at least as many hexes as Step (1 hex)"
	)

	_assert_highlight_matches_controller_union(instance, "turn_started")

	assert_true(
		instance._verb_registry.is_available("STEP"),
		"the STEP verb must be available (a non-empty selectable-hex set) on the active player's turn_started"
	)


	# ══════════════════════════════════════════════════════════════════════
	# Step 2 (US-006/US-007/US-008) — pressing the Layer 1 STEP verb, then
	# executing it against a highlighted destination, moves the token via
	# step_to(), resyncs HexGridView, then the highlight is cleared and
	# re-derived from the mover's NEW position. FEAT-007 (this iteration's
	# US-007/FR-010): this is the SOLE way Step/Stride can be performed now —
	# there is no standing hex_grid_view.hex_clicked subscription to drive
	# this through anymore.
	# ══════════════════════════════════════════════════════════════════════

	var step_button: Button = instance.verb_bar_view.get_button("STEP")
	assert_not_null(step_button, "VerbBarView must render a STEP button when the verb is available")

	var step_selection: Dictionary = instance.verb_bar_view.press("STEP")
	var candidate_hexes: Array = step_selection.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "entering STEP's Layer 2 selection must surface at least one legal destination hex")

	var destination = candidate_hexes[0]
	var token_before = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_before, "the real HexGridView must already carry a token for the active actor")
	assert_false(
		token_before.hex_coord.equals(destination),
		"sanity check: the chosen destination hex must differ from the actor's starting hex"
	)

	var step_result: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_true(step_result.get("ok", false), "executing STEP against the selected destination must resolve a real Step")

	var moved_combatant = _find_combatant_by_id(instance, actor_id)
	assert_not_null(moved_combatant, "fixture assumption: the moved actor must be one of MainScene's live combatants")
	assert_true(
		moved_combatant.hex_coord.equals(destination),
		"Combatant.position (the live combatant Dictionary's hex_coord) must change to the selected legal hex via step_to()"
	)

	var token_after = instance.hex_grid_view.get_token(actor_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved actor")
	assert_true(
		token_after.hex_coord.equals(destination),
		"the real HexGridView's token must resync its hex_coord to the new hex after the move"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(destination),
		"the real HexGridView's token must resync its rendered screen position to the new hex's ADR-004 axial-to-pixel "
		+ "projection, honoring the composition root's FEAT-002 viewport-centering origin offset"
	)

	# The highlight is cleared then re-derived from the mover's NEW
	# position -- proven the same way as the turn_started assertion above:
	# it must exactly equal union(Step, Stride) computed AFTER the move
	# (never left stale/pointing at the pre-move destination set).
	_assert_highlight_matches_controller_union(instance, "post-move")


	# ══════════════════════════════════════════════════════════════════════
	# Step 3 (US-009) — a real Strike, driven through the Layer 1 STRIKE verb,
	# decrements the acting combatant's action budget as reflected by the
	# real StatusPanelView's projection.
	# ══════════════════════════════════════════════════════════════════════

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: the actor is still the living player combatant after their own Step/Stride"
	)

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant has a positive action budget before Striking")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor has a live domain ActionEconomy")

	assert_true(
		instance._verb_registry.is_available("STRIKE"),
		"fixture assumption: the active actor has at least one in-reach target after moving"
	)
	var strike_selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = strike_selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "entering STRIKE's Layer 2 selection must surface at least one in-reach target")
	var target_id: String = target_ids[0]

	var strike_result: Dictionary = instance._verb_registry.execute("STRIKE", target_id)
	assert_true(strike_result.get("resolved", false), "the real resolve_action_use_case must resolve the player's Strike")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"StatusPanelView.action_budget_remaining for the acting combatant must decrease by EXACTLY 1 after the real Strike resolves"
	)
	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must match the domain ActionEconomy.is_spent() value after the real Strike"
	)


	# ══════════════════════════════════════════════════════════════════════
	# Step 4 (US-005/US-008/US-010/US-011) — drive the encounter to
	# resolution through the real VerbBarView/EndTurnControl nodes, exactly
	# as a human would (every enemy turn in between auto-driven by the real
	# $TurnController via MainScene's EndTurnControl.turn_ended handoff),
	# then assert every combat/movement input surface is unavailable/
	# disabled, the hex highlight is cleared, and it cannot be re-triggered.
	# ══════════════════════════════════════════════════════════════════════

	var guard: int = 0
	while not instance.round_session.is_round_over() and guard < _MAX_DRIVE_ITERATIONS:
		if not instance.round_session.current_actor().is_enemy and instance._verb_registry.is_available("STRIKE"):
			var live_selection: Dictionary = instance.verb_bar_view.press("STRIKE")
			var live_target_ids: Array = live_selection.get("candidate_targets", [])
			if live_target_ids.size() > 0:
				instance._verb_registry.execute("STRIKE", live_target_ids[0])
		instance.end_turn_control.press()
		guard += 1

	assert_true(
		instance.round_session.is_round_over(),
		"driving the real VerbBarView/EndTurnControl nodes must eventually conclude the round (guard=%d/%d)" % [guard, _MAX_DRIVE_ITERATIONS]
	)
	var decided_outcome: String = instance.round_session.outcome()
	assert_true(
		decided_outcome == "won" or decided_outcome == "lost",
		"RoundSession.outcome() must be a decided terminal outcome ('won' or 'lost') once the round concludes; got '%s'" % decided_outcome
	)
	assert_true(
		instance.result_screen_view.is_shown(),
		"the real $ResultScreenView must have processed the EncounterResolved (EncounterResultEvent) through MainScene's real event-sink pipeline"
	)

	# ── Strike/Step/Stride/EndTurn all unavailable/disabled ─────────────────
	assert_false(instance._verb_registry.is_available("STRIKE"), "the STRIKE verb must be unavailable once the encounter has concluded")
	assert_false(instance._verb_registry.is_available("STEP"), "the STEP verb must be unavailable once the encounter has concluded")
	assert_false(instance._verb_registry.is_available("STRIDE"), "the STRIDE verb must be unavailable once the encounter has concluded")

	assert_false(instance.end_turn_control.is_enabled(), "EndTurnControl must be disabled once the encounter has concluded")
	assert_true(instance.end_turn_control.is_locked(), "EndTurnControl.is_locked() must be true once the encounter has concluded")

	assert_true(instance.movement_input_controller.is_locked(), "movement_input_controller.is_locked() must be true once the encounter has concluded")

	# ── The hex highlight is cleared ────────────────────────────────────────
	assert_eq(
		instance.hex_grid_view._selectable_hexes.size(), 0,
		"the real HexGridView's highlighted hex set must be empty once the encounter has concluded"
	)

	# ── ...and cannot be re-triggered: capture every live combatant's
	# position/HP/action-economy state, fire every input signal a stray UI
	# event could still emit, and assert NONE of it produced any mutation. ──
	var positions_before: Dictionary = {}
	var hp_before: Dictionary = {}
	for combatant in instance._party + instance._enemies:
		var id: String = combatant.combatant_id
		positions_before[id] = combatant.hex_coord
		hp_before[id] = combatant.hp_current
	var attack_event_count_before: int = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast).size()

	# A stray hex_clicked on an arbitrary hex (even one that WAS legal before
	# resolution, e.g. the fixture's original starting hex) must be a no-op --
	# FEAT-007 (this iteration): this signal carries no connection at all
	# anymore, so emitting it can never reach any handler in the first place.
	instance.hex_grid_view.hex_clicked.emit(destination)

	var strike_reject: Dictionary = instance._verb_registry.execute("STRIKE", target_id)
	assert_false(strike_reject.get("ok", true), "STRIKE execute() must be rejected after the encounter has concluded")
	assert_eq(strike_reject.get("error", ""), "ERR_TARGET_NOT_SELECTABLE")

	var step_reject: Dictionary = instance._verb_registry.execute("STEP", destination)
	assert_false(step_reject.get("ok", true), "STEP execute() must be rejected after the encounter has concluded")

	var end_turn_reject: Dictionary = instance.end_turn_control.press()
	assert_false(end_turn_reject.get("ok", true), "press() must be rejected after the encounter has concluded")
	assert_eq(end_turn_reject.get("error", ""), "ENCOUNTER_ALREADY_RESOLVED")

	# No domain mutation whatsoever resulted from any of the above.
	for combatant in instance._party + instance._enemies:
		var id: String = combatant.combatant_id
		assert_true(
			combatant.hex_coord.equals(positions_before[id]),
			"combatant %s's position must be unchanged by any post-resolution input" % id
		)
		assert_eq(
			combatant.hp_current, hp_before[id],
			"combatant %s's HP must be unchanged by any post-resolution input" % id
		)
	assert_eq(
		instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast).size(), attack_event_count_before,
		"no additional AttackEvent may be emitted by any post-resolution input"
	)

	# ...and the highlight/affordance state remains cleared/locked -- it
	# cannot be re-triggered by the stray input above.
	assert_eq(instance.hex_grid_view._selectable_hexes.size(), 0, "the hex highlight must remain empty after a stray post-resolution hex_clicked signal")
	assert_false(instance._verb_registry.is_available("STRIKE"), "the STRIKE verb must remain unavailable after the rejected post-resolution execute()")
	assert_false(instance._verb_registry.is_available("STEP"), "the STEP verb must remain unavailable after the rejected post-resolution execute()")
	assert_false(instance.end_turn_control.is_enabled(), "EndTurnControl must remain disabled after the rejected post-resolution press()")


# ══════════════════════════════════════════════════════════════════════════
# FEAT-198 (DEF-QA-001) — the enemy AI leg, driven through the SAME real,
# unmodified res://MainScene.tscn composition root the continuous
# playthrough above drives (no new test file, no duplicate steel-thread
# playthrough). See the file-level doc's FEAT-198 note for why the
# continuous playthrough above never actually reaches
# round_session.advance_ai_turn() against this fixture (Titus's own Step 3
# critical hit defeats the sole Skeleton before its turn ever comes up) --
# these two suites relocate the enemy's pre-turn position so the real AI
# (core/combat/ai.gd) actually reaches its Stride / Stride-then-Strike /
# Stride-with-no-action-remaining branches, through the EXACT SAME
# EndTurnControl.press() -> TurnController -> RoundSession.advance_ai_turn()
# -> HexGridView.move_token() call path already exercised (for the
# "already in reach, zero Stride" branch) by the continuous playthrough.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_ai_leg_strides_toward_nearest_target_but_does_not_strike_same_turn() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	var enemy = instance._enemies[0]
	var enemy_id: String = enemy.combatant_id
	assert_ne(enemy_id, "", "fixture assumption: the enemy combatant carries a non-empty combatant_id")

	var player = instance._party[0]
	var player_hex = player.hex_coord
	assert_not_null(player_hex, "fixture assumption: the player combatant carries positional hex_coord data")

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: the player still acts first, before the enemy's own turn"
	)

	# Relocate the enemy out of melee reach of the player -- neither Titus's
	# longsword nor the Skeleton's own weapon carry a "range_hexes" key
	# (data/characters/titus.tres / data/enemies/skeleton.tres), so reach for
	# BOTH sides is the SAME adjacency-only rule (core/geometry/hex_math.gd
	# HexMath.hex_neighbors()) -- but within a single Stride's reach
	# (core/rules/movement.gd Movement.DEFAULT_SPEED == 4 hexes). This
	# mutates the SAME "hex_coord" Dictionary key core/rules/movement.gd's
	# own _set_hex() writes, then resyncs the on-screen token via the SAME
	# hex_grid_view.move_token() call the AI-Stride path itself invokes
	# (ADR-006), so the pre-turn domain state and rendered token agree
	# before the real AI turn runs below.
	var far_hex = HexCoordClass.new(player_hex.q + 3, player_hex.r)
	var pre_distance: int = HexMathClass.hex_distance(far_hex, player_hex)
	assert_true(pre_distance > 1, "sanity check: the relocated enemy must start OUT of melee reach of the nearest living target")
	assert_true(pre_distance <= 4, "sanity check: the relocated enemy must remain within a single Stride's reach")

	enemy["hex_coord"] = far_hex
	instance.hex_grid_view.move_token(enemy_id, far_hex)

	var token_before = instance.hex_grid_view.get_token(enemy_id)
	assert_not_null(token_before, "fixture setup: the real HexGridView must still carry a token for the relocated enemy")
	assert_true(token_before.hex_coord.equals(far_hex), "fixture setup: the enemy's on-screen token must be relocated before its turn runs")

	var enemy_action_economy = _find_action_economy_by_id(instance, enemy_id)
	assert_not_null(enemy_action_economy, "fixture assumption: the enemy carries a live domain ActionEconomy")
	assert_true(enemy_action_economy.can_take_movement_action(), "sanity check: the enemy has not used its per-turn Movement action yet")

	var attack_events_before: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackBroadcast and e.attacker_name == enemy.name
	).size()

	# End the player's turn WITHOUT acting -- this suite isolates the enemy
	# AI leg only. $EndTurnControl.press() is the SAME real control node the
	# continuous playthrough above drives; MainScene's own turn_ended wiring
	# then re-invokes the real $TurnController, which auto-resolves the
	# enemy's turn via RoundSession.advance_ai_turn() -- no direct
	# advance_ai_turn()/AI call is made by this test.
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "ending the player's turn (no action taken) must succeed")

	# The prologue roster now seats a SECOND living, player-controlled
	# combatant (Marigold, player_1) between Titus and the enemy in turn
	# order. $TurnController only auto-drives AI (enemy) turns, not other
	# living player combatants, so this suite must also manually end
	# Marigold's turn (WITHOUT acting, same as Titus above) before the
	# enemy's own AI turn is reached.
	if not instance.round_session.current_actor().is_enemy:
		var marigold_end_turn_result: Dictionary = instance.end_turn_control.press()
		assert_true(marigold_end_turn_result.get("ok", false), "ending Marigold's turn (no action taken) must succeed")

	# ── Wait for the AI Stride to fully complete (domain commit + animation) ─
	# The OS reaction window interleaves per-hop animation with OS evaluation
	# BEFORE MovementClass.stride() commits hex_coord.  EndTurnControl.press()
	# does not await advance_ai_turn(), so this suite must give the full
	# animation chain (up to speed=4 hops × TOKEN_MOVE_DURATION = 0.48 s) plus
	# any OS popup coroutine overhead enough wall-clock time to finish before
	# reading domain state or asserting on token position.
	await get_tree().create_timer(2.0).timeout

	# ── Stride toward the nearest living target (US-004) ────────────────────
	var moved_hex = enemy.hex_coord
	assert_false(
		moved_hex.equals(far_hex),
		"the enemy's hex position after its AI turn must differ from its pre-turn position when the nearest target started out of reach"
	)
	var post_distance: int = HexMathClass.hex_distance(moved_hex, player_hex)
	assert_true(post_distance < pre_distance, "hex_distance(enemy, nearest_target) must strictly decrease after the AI's Stride")
	assert_eq(post_distance, 1, "sanity check: a legal Stride destination adjacent to the nearest target must have been available and chosen")

	# ── ActionEconomy.movement_used gate (US-006) ───────────────────────────
	assert_false(
		enemy_action_economy.can_take_movement_action(),
		"ActionEconomy.movement_used must be true after the AI's Stride within the same turn"
	)

	# ── FEAT-003 (ADR-103): the per-turn one-action gate means the Stride
	# already spent this turn's ONE action, so no Strike may be attempted/
	# recorded in the SAME turn even though reach is now satisfied post-
	# Stride — core/combat/ai.gd's decide_action() (reworked by FEAT-007/
	# US-007) returns EXACTLY ONE Strike-or-Stride decision per turn, so this
	# turn's decision is the Stride alone (will_strike: false, no composite
	# Stride-then-Strike decision is ever produced); the enemy's NEXT
	# decide_action() call (its following turn) is what would evaluate
	# whether the now-adjacent target is in reach for a Strike (US-005)
	# ────────────────────────────────────────────────────────────────────────
	var attack_events_after: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackBroadcast and e.attacker_name == enemy.name
	).size()
	assert_eq(
		attack_events_after, attack_events_before,
		"no Strike outcome may be recorded in the same turn as the Stride -- only one action is permitted per turn (FEAT-003)"
	)
	assert_eq(
		enemy_action_economy.get_remaining(), ActionEconomyClass.MAX_BUDGET - 1,
		"the enemy must have spent ONLY the Stride action from its per-round budget this turn -- the Strike attempt must not decrement it further"
	)

	# ── The enemy token's on-screen hex position matches the AIDecision's
	# destination, via the SAME move_token() path player movement uses
	# (US-008) ───────────────────────────────────────────────────────────────
	var token_after = instance.hex_grid_view.get_token(enemy_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved enemy")
	assert_true(
		token_after.hex_coord.equals(moved_hex),
		"the enemy token's on-screen hex position must resync to the AI Stride destination"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(moved_hex),
		"the enemy token's rendered screen position must resync to the AI Stride destination's axial-to-pixel projection -- the SAME move_token() path player movement uses"
	)


func test_enemy_ai_leg_strides_but_does_not_strike_when_no_action_remains_after_the_stride() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(instance._enemies.size(), 1, "fixture assumption: the prologue encounter has exactly one enemy")
	var enemy = instance._enemies[0]
	var enemy_id: String = enemy.combatant_id
	assert_ne(enemy_id, "", "fixture assumption: the enemy combatant carries a non-empty combatant_id")

	var player = instance._party[0]
	var player_hex = player.hex_coord

	# Same out-of-reach-but-Stride-reachable relocation as the sibling suite
	# above.
	var far_hex = HexCoordClass.new(player_hex.q + 3, player_hex.r)
	var pre_distance: int = HexMathClass.hex_distance(far_hex, player_hex)
	assert_true(pre_distance > 1 and pre_distance <= 4, "sanity check: the relocated enemy starts out of melee reach but within a single Stride's reach")

	enemy["hex_coord"] = far_hex
	instance.hex_grid_view.move_token(enemy_id, far_hex)

	var enemy_action_economy = _find_action_economy_by_id(instance, enemy_id)
	assert_not_null(enemy_action_economy, "fixture assumption: the enemy carries a live domain ActionEconomy")

	# Drain the enemy's per-ROUND action budget down to exactly ONE action
	# remaining -- via the SAME Result-style spend_action() API
	# core/rules/movement.gd's own stride() spends through (untagged with
	# the "Movement" trait, so the per-turn Movement gate this suite means to
	# exercise via the AI's OWN Stride stays untouched by this setup step) --
	# so the Stride the AI is about to issue is the LAST action available
	# this round; no action remains afterward for the composite
	# Stride-then-Strike branch (core/combat/ai.gd's FEAT-005 extension) to
	# fire. FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so
	# each drain spend simulates its own turn boundary via start_of_turn()
	# (AC-4 interleaving) -- the enemy's REAL AI turn below issues its own
	# start_of_turn() (core/application/round_session.gd advance_ai_turn())
	# which clears this fixture's per-turn flags again before the Stride.
	for i in range(ActionEconomyClass.MAX_BUDGET - 1):
		enemy_action_economy.start_of_turn()
		var drain_result: Dictionary = enemy_action_economy.spend_action({})
		assert_true(drain_result.get("success", false), "fixture setup: draining the enemy's action budget must succeed")
	assert_eq(enemy_action_economy.get_remaining(), 1, "fixture setup: exactly one action must remain before the enemy's AI turn")
	assert_true(enemy_action_economy.can_take_movement_action(), "fixture setup: draining the budget must not itself trip the Movement gate")

	var attack_events_before: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackBroadcast and e.attacker_name == enemy.name
	).size()

	assert_false(instance.round_session.current_actor().is_enemy, "fixture assumption: the player still acts first")
	var end_turn_result: Dictionary = instance.end_turn_control.press()
	assert_true(end_turn_result.get("ok", false), "ending the player's turn (no action taken) must succeed")

	# The prologue roster now seats a SECOND living, player-controlled
	# combatant (Marigold, player_1) between Titus and the enemy in turn
	# order. $TurnController only auto-drives AI (enemy) turns, not other
	# living player combatants, so this suite must also manually end
	# Marigold's turn (WITHOUT acting, same as Titus above) before the
	# enemy's own AI turn is reached.
	if not instance.round_session.current_actor().is_enemy:
		var marigold_end_turn_result: Dictionary = instance.end_turn_control.press()
		assert_true(marigold_end_turn_result.get("ok", false), "ending Marigold's turn (no action taken) must succeed")

	# Wait for per-hop animation + OS evaluation + domain commit — see the
	# sibling suite's identical comment for the full timing rationale.
	await get_tree().create_timer(2.0).timeout

	# The AI must still issue its Stride with the one remaining action...
	var moved_hex = enemy.hex_coord
	assert_false(moved_hex.equals(far_hex), "the AI must still issue its Stride toward the nearest living target with its one remaining action")
	assert_eq(HexMathClass.hex_distance(moved_hex, player_hex), 1, "sanity check: the Stride must have closed into melee reach")
	assert_false(enemy_action_economy.can_take_movement_action(), "ActionEconomy.movement_used must be true after the AI's Stride")
	assert_eq(enemy_action_economy.get_remaining(), 0, "sanity check: the Stride must have spent the enemy's LAST remaining action this round")
	assert_true(enemy_action_economy.is_spent(), "sanity check: the enemy must be Spent once its last action is spent on the Stride")

	# ...but with NO action remaining, no Strike may be attempted/recorded,
	# even though reach is now satisfied.
	var attack_events_after: int = instance.event_sink.log.filter(
		func(e): return e is RoundEventsClass.AttackBroadcast and e.attacker_name == enemy.name
	).size()
	assert_eq(
		attack_events_after, attack_events_before,
		"no Strike may be attempted/recorded against the nearest living target when no action remains after the AI's Stride"
	)

	var token_after = instance.hex_grid_view.get_token(enemy_id)
	assert_not_null(token_after, "the real HexGridView must still carry a token for the moved enemy")
	assert_true(
		token_after.hex_coord.equals(moved_hex),
		"the enemy token's on-screen hex position must resync to the AI Stride destination even when no Strike follows"
	)
	assert_eq(
		token_after.position, instance.hex_grid_view.axial_to_pixel(moved_hex),
		"the enemy token's rendered screen position must resync to the AI Stride destination's axial-to-pixel projection"
	)
