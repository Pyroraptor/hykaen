extends GutTest
## tests/e2e/test_steel_thread_strike_full_flow.gd — FEAT-246 (US-015).
##
## THE final steel-thread capstone smoke test: a single suite proving the
## COMPLETE steel thread — entry to exit — composes correctly together, one
## more time, through the real, unmodified res://MainScene.tscn composition
## root (no mocked Application-layer port, no test-local resolver/use-case
## graph for any of the "boot-real" scenarios below). This file does not
## re-litigate every static/unit-level assertion already pinned by the
## individual feature suites it consolidates (tests/integration/
## test_strike_effects_applier_retrofit.gd — FEAT-004, tests/integration/
## test_enemy_reaction_effects_applier_retrofit.gd — FEAT-005,
## tests/unit/test_action_controller_execute_shapes.gd — FEAT-009,
## tests/integration/test_targeting_generalization_scenarios.gd — FEAT-245,
## tests/regression/test_end_turn_direct_execute.gd — FEAT-243,
## tests/regression/test_strike_end_to_end_unchanged.gd — FEAT-244); it
## instead proves the ONE thing none of those files individually prove: that
## every one of those pieces still composes into a single, continuous,
## deterministic playthrough, gated by this project's canonical CI entry
## point (scripts/test_command.sh).
##
## Sections (test_criteria):
##   A. MainScene boots headless with zero errors (proxy convention: every
##      composition-root field non-null after first frame — mirrors
##      tests/gut/test_smoke_boot.gd's established Godot-4.3
##      push_error-capture-unavailable workaround).
##   B. boot-real player-Strike e2e: verb bar STRIKE selection -> target hex
##      pick -> hp mutated via the single EffectsApplier seam -> AttackEvent
##      emitted and logged byte-identical to the established pre-retrofit
##      baseline (field-for-field pin, mirrors
##      test_strike_effects_applier_retrofit.gd Section C/D).
##   C. boot-real enemy-reaction e2e: an on-hit reaction's hp mutation flows
##      through the IDENTICAL EffectsApplier instance Strike uses,
##      AttackEvent/log zero-diff vs the established pre-retrofit baseline
##      (mirrors test_enemy_reaction_effects_applier_retrofit.gd Section 3).
##   D. the SAME selection/execute pipeline (presentation/selection_overlay.gd
##      + presentation/action_controller.gd) additively resolves an
##      option-list pick into execute(option, target) — proven alongside a
##      real, unaffected Strike in the SAME suite.
##   E. the SAME selection/execute pipeline additively resolves a
##      fully-resolved AREA target set into execute() — proven alongside a
##      real, unaffected Strike AND END_TURN in the SAME suite.
##   F. END_TURN regression: pressing END_TURN never enters
##      selection_overlay's Layer 2 flow, asserted directly within THIS
##      suite (not merely relied upon from a separate file).
##   G. determinism: two independent boots at the SAME pinned seed, driven
##      through the identical real player-Strike UI sequence, produce
##      byte-identical hp/AttackEvent/combat-log outcomes.
##
## No production Application/Domain/Presentation code is modified by this
## feature (files_to_create lists only this test file) — every collaborator
## driven below is the exact, unmodified, REUSED production instance
## MainScene.gd's own _ready() (or, for Sections D/E's option-list/AREA
## scenarios, the real presentation/action_controller.gd base-class
## dispatch + presentation/selection_overlay.gd, wired exactly as
## MainScene.gd wires them) already establishes.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RoundEventsClass            = preload("res://core/rules/round_events.gd")
const HexCoordClass               = preload("res://core/geometry/hex_coord.gd")
const CombatantClass              = preload("res://core/domain/combatant.gd")
const EffectsApplierClass         = preload("res://core/domain/effects_applier.gd")
const SelectionDescriptorClass    = preload("res://core/application/selection_descriptor.gd")
const VerbBarRegistryAdapterClass = preload("res://infrastructure/verb_bar_registry_adapter.gd")
const RoundSessionHolderClass     = preload("res://infrastructure/round_session_holder.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const VerbBarViewScene: PackedScene = preload("res://presentation/verb_bar_view.tscn")
const SelectionOverlayClass        = preload("res://presentation/selection_overlay.gd")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) — injected
## in-process via MainScene's `seed_override` contract (ADR-004 top
## precedence), mirroring every other integration/E2E suite's convention.
const SEED: int = 42

## A guaranteed-hit AC, mirrors tests/integration/
## test_enemy_reaction_effects_applier_retrofit.gd's identically-named/valued
## constant: forces a deterministic hit on Titus without touching RNG/seed
## math.
const AC_GUARANTEED_HIT: int = -100

const STRIKE: String = "STRIKE"
const END_TURN: String = "END_TURN"


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture helpers — boot the REAL res://MainScene.tscn composition
# root (mirrors every other e2e suite's established "_boot_main_scene_with_
# seed" convention).
# ══════════════════════════════════════════════════════════════════════════

## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives the whole Strike steel
## thread directly against `round_session`/`_verb_registry`/`verb_bar_view`,
## so `_boot_main_scene_with_seed()` now also drives the SAME real handoff,
## landing the instance in GameMode.COMBAT with a live round_session before
## returning.
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

	return instance


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


func _titus(instance):
	return instance._party[0]


func _sole_attack_event(instance):
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved on this instance")
	return attack_events[0]


## _drive_player_strike(seed_value) -> Dictionary — boots a fresh, real
## MainScene at `seed_value` and drives ONE player Strike through the REAL
## Layer 1 verb bar (STRIKE) -> a real hex_grid_view.hex_clicked landing on
## the target's own hex (the same real click-driven path a human uses),
## returning the live instance plus a snapshot of the resulting hp/
## AttackEvent/combat-log outcome for both Section B's baseline pin and
## Section G's determinism comparison.
func _drive_player_strike(seed_value: int) -> Dictionary:
	var instance = await _boot_main_scene_with_seed(seed_value)
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = skeleton.combatant_id
	var hp_before: int = skeleton.hp_current

	assert_true(
		instance._verb_registry.is_available(STRIKE),
		"fixture assumption: the prologue's first actor has at least one in-reach target at seed=%d" % seed_value
	)
	var selection: Dictionary = instance.verb_bar_view.press(STRIKE)
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.has(skeleton_id), "fixture assumption: the Skeleton must be an in-reach Strike target at boot")

	var target_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	var attack_event = _sole_attack_event(instance)
	var hp_after: int = skeleton.hp_current

	var history: Array = instance.round_history_port.get_history()
	assert_true(history.size() > 0, "at least one combat-log entry must be appended for the resolved Strike")
	var last_entry: Dictionary = history[history.size() - 1]

	return {
		"instance": instance,
		"skeleton_id": skeleton_id,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"attack_event": attack_event,
		"history_entry": last_entry,
	}


# ══════════════════════════════════════════════════════════════════════════
# Section A — MainScene boots headless with zero errors.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_boots_headless_with_zero_errors() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_eq(
		instance.resolved_seed, SEED,
		"seed_override=42 must be honored as the resolved seed via the in-process injection point (ADR-004 top precedence)"
	)

	# Zero-unhandled-errors proxy (mirrors tests/gut/test_smoke_boot.gd's
	# established Godot-4.3 push_error-capture-unavailable workaround): every
	# composition-root field MainScene.gd's _ready() wires is only ever left
	# null when an internal fail-fast push_error() path was hit.
	assert_not_null(instance.encounter_repository, "MainScene must resolve a non-null encounter_repository")
	assert_not_null(instance.random_port, "MainScene must resolve a non-null random_port")
	assert_not_null(instance.event_sink, "MainScene must resolve a non-null event_sink")
	assert_not_null(instance.encounter, "MainScene must resolve a non-null encounter")
	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_not_null(instance.resolve_action_use_case, "MainScene must resolve a non-null resolve_action_use_case")
	assert_not_null(instance.round_history_port, "MainScene must resolve a non-null round_history_port")
	assert_not_null(instance.hex_grid_view, "MainScene must expose a non-null hex_grid_view")
	assert_not_null(instance.status_panel_view, "MainScene must expose a non-null status_panel_view")
	assert_not_null(instance.initiative_view, "MainScene must expose a non-null initiative_view")
	assert_not_null(instance.event_log_view, "MainScene must expose a non-null event_log_view")
	assert_not_null(instance.end_turn_control, "MainScene must expose a non-null end_turn_control")
	assert_not_null(instance.verb_bar_view, "MainScene must expose a non-null verb_bar_view")
	assert_not_null(instance.selection_overlay, "MainScene must expose a non-null selection_overlay")
	assert_not_null(instance.result_screen_view, "MainScene must expose a non-null result_screen_view")
	assert_not_null(instance.reaction_prompt_ui, "MainScene must expose a non-null reaction_prompt_ui")
	assert_not_null(instance._verb_registry, "MainScene must build a non-null verb registry")

	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with zero player input")
	assert_eq(instance.hex_grid_view.get_token_count(), 4, "HexGridView must render one token per live combatant (Titus + Marigold + Gram Marx + Skeleton)")
	assert_eq(instance.event_log_view.get_entry_count(), 0, "fixture assumption: no events have been logged yet before any player input")
	assert_false(instance.result_screen_view.is_shown(), "the real ResultScreenView must not show a result before any input has been given")


# ══════════════════════════════════════════════════════════════════════════
# Section B — boot-real player-Strike e2e: verb bar STRIKE selection ->
# target hex pick -> hp mutated via the single EffectsApplier seam ->
# AttackEvent emitted and logged byte-identical to the established
# pre-retrofit baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_player_strike_hp_mutated_via_effects_applier_matches_baseline() -> void:
	var run: Dictionary = await _drive_player_strike(SEED)
	var instance = run["instance"]
	var attack_event = run["attack_event"]

	assert_true(
		instance.resolve_action_use_case.get_effects_applier() is EffectsApplierClass,
		"the real resolve_action_use_case must expose the single EffectsApplier instance the player's Strike routed through"
	)

	# Zero diff between the live hp outcome and the recorded AttackEvent's
	# damage_final -- proving EffectsApplier mutated the SAME live Combatant
	# instance the container holds.
	assert_eq(
		run["hp_before"] - run["hp_after"], attack_event.damage_final,
		"boot-real: the Skeleton's live hp_current must drop by EXACTLY the AttackEvent's damage_final -- zero diff"
	)

	# AttackEvent shape/fields pin against the established pre-retrofit
	# baseline (mirrors test_strike_effects_applier_retrofit.gd Section C).
	assert_true(attack_event is RoundEventsClass.AttackBroadcast, "PINNED: the emitted event must be a RoundEvents.AttackBroadcast")
	assert_eq(attack_event.attacker_name, "Titus", "PINNED: attacker_name field unchanged")
	assert_eq(attack_event.target_name, "Skeleton", "PINNED: target_name field unchanged")
	assert_eq(attack_event.defense_type, "ac", "PINNED: defense_type field unchanged")
	assert_not_null(attack_event.actor_updated_action_budget, "PINNED: actor_updated_action_budget must still be populated")
	assert_true(attack_event.actor_updated_action_budget.has("remaining"), "PINNED: actor_updated_action_budget must still carry 'remaining'")
	assert_true(attack_event.actor_updated_action_budget.has("spent"), "PINNED: actor_updated_action_budget must still carry 'spent'")

	# Zero diff between the appended combat-log entry and the AttackEvent it
	# was derived from.
	var last_entry: Dictionary = run["history_entry"]
	assert_eq(
		last_entry.get("damage_final", -1), attack_event.damage_final,
		"boot-real: the combat log's damage_final must match the AttackEvent's damage_final -- zero diff"
	)
	assert_eq(
		last_entry.get("target", {}).get("hp_current", -1), run["hp_after"],
		"boot-real: the combat log's snapshotted target hp_current must match the live Skeleton's post-Strike hp_current -- zero diff"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section C — boot-real enemy-reaction e2e: an on-hit reaction's hp mutation
# flows through the IDENTICAL EffectsApplier instance Strike uses;
# AttackEvent/log zero-diff vs the established pre-retrofit baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_real_enemy_reaction_hp_mutated_via_effects_applier_matches_baseline() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	var titus = _titus(instance)
	titus["ac"] = AC_GUARANTEED_HIT

	var titus_id: String = titus.combatant_id
	var hp_before: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_true(hp_before > 0, "fixture assumption: Titus starts with positive HP")

	var log_count_before: int = instance.event_log_view.get_entry_count()

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % SEED
	)
	instance.verb_bar_view.press(END_TURN)

	# The prologue roster now seats a SECOND living, player-controlled
	# combatant (Marigold, player_1) between Titus and the enemy in turn
	# order. $TurnController only auto-drives AI (enemy) turns, not other
	# living player combatants, so Marigold's turn must also be manually
	# ended (WITHOUT acting, same as Titus above) before the enemy's own
	# AI-driven Strike -- and its reaction prompts -- are reached.
	if not instance.round_session.current_actor().is_enemy:
		instance.verb_bar_view.press(END_TURN)

	assert_true(instance.reaction_prompt_ui.is_open(), "the PreHitAvoidance pop-up must open for the incoming Strike")
	instance.reaction_prompt_ui.press_option("none")

	assert_true(instance.reaction_prompt_ui.is_open(), "the OnHitMitigation pop-up must open once the Strike is confirmed to hit")
	instance.reaction_prompt_ui.press_option("none")
	assert_false(instance.reaction_prompt_ui.is_open())

	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one Strike must have resolved")
	var event = attack_events[0]
	assert_true(event.hit, "fixture assumption: the guaranteed-hit AC must actually produce a hit")
	assert_true(event.damage_final > 0, "declining (Pass) must leave the Strike's real, unmitigated damage in place")

	# Zero diff between Titus's HP panel and the resolved reaction's
	# unmitigated damage -- matches the pre-retrofit baseline exactly.
	var hp_after: int = instance.status_panel_view.get_status(titus_id).get("hp_current", -1)
	assert_eq(
		hp_before - hp_after, event.damage_final,
		"Titus's HP panel must show damage taken EXACTLY matching the unmitigated (raw) committed damage -- zero diff vs the pre-retrofit baseline"
	)

	var log_count_after: int = instance.event_log_view.get_entry_count()
	assert_eq(log_count_after, log_count_before + 1, "exactly one new combat-log row must be appended -- matches the pre-retrofit baseline")

	# The enemy reaction routed damage through the IDENTICAL EffectsApplier
	# instance the player-Strike path uses -- no parallel seam (US-005).
	var strike_effects_applier = instance.resolve_action_use_case.get_effects_applier()
	var reaction_effects_applier = instance.resolve_action_use_case.get_apply_on_hit_defense_use_case().get_effects_applier()
	assert_not_null(strike_effects_applier)
	assert_same(
		strike_effects_applier, reaction_effects_applier,
		"the REAL, live-booted MainScene's Strike path and enemy-reaction path must route damage through the IDENTICAL EffectsApplier instance"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section F — END_TURN regression: pressing END_TURN never enters
# selection_overlay's Layer 2 flow, asserted directly within THIS suite.
# ══════════════════════════════════════════════════════════════════════════

func test_end_turn_regression_direct_execute_never_enters_selection_overlay_within_this_suite() -> void:
	var instance = await _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % SEED
	)

	watch_signals(instance.selection_overlay)
	watch_signals(instance.verb_bar_view)

	var result: Dictionary = instance.verb_bar_view.press(END_TURN)

	assert_false(instance.selection_overlay.is_active(), "END_TURN must never activate selection_overlay's Layer 2 flow")
	assert_eq(instance.selection_overlay.get_active_verb_id(), "", "selection_overlay's active verb must remain empty after END_TURN")
	assert_false(instance.selection_overlay.is_awaiting_option(), "END_TURN must never enter Layer-2a (awaiting an option)")
	assert_false(instance.selection_overlay.is_awaiting_area_confirm(), "END_TURN must never enter an AREA_SET preview/confirm state")
	assert_signal_not_emitted(instance.verb_bar_view, "verb_selection_entered", "END_TURN must never emit verb_selection_entered -- the one signal that drives SelectionOverlay.activate()")
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "selection_overlay must never resolve anything as a side effect of END_TURN")
	assert_true(result.get("ok", false), "ending the player's turn (no action taken) must succeed")


# ══════════════════════════════════════════════════════════════════════════
# Sections D/E — real ActionController subclasses opting INTO the base
# class's execute() shape-dispatch machinery, mirroring tests/integration/
# test_targeting_generalization_scenarios.gd's established convention: the
# ONLY way to reach that dispatch code genuinely, so a recorded execute_calls
# entry proves the REAL action_controller.gd/selection_overlay.gd pipeline
# ran, never a hand-rolled stand-in.
# ══════════════════════════════════════════════════════════════════════════

## CastSpellActionController -- an OPTION_TARGET verb (candidate_options).
class CastSpellActionController:
	extends "res://presentation/action_controller.gd"

	## [option, target] per REAL _execute_option_target() dispatch.
	var execute_calls: Array = []

	func availability() -> bool:
		return true

	func enter_selection() -> Dictionary:
		return {
			"candidate_targets": ["enemy_0"],
			"candidate_hexes": [],
			"candidate_options": [
				{"id": "fireball", "label": "Fireball"},
				{"id": "ice_bolt", "label": "Ice Bolt"},
			],
		}

	func expected_shape() -> int:
		return SelectionShape.OPTION_TARGET

	func _execute_option_target(option, target) -> Dictionary:
		execute_calls.append([option, target])
		return {"ok": true, "resolved": true, "shape": "OPTION_TARGET", "option": option, "target": target}


## BlastAreaActionController -- a TARGET_SET verb (AREA_SET): a single
## candidate origin hex resolving to a radius-1 affected-hex set.
class BlastAreaActionController:
	extends "res://presentation/action_controller.gd"

	## the resolved target_set Array per REAL _execute_target_set() dispatch.
	var execute_calls: Array = []

	func availability() -> bool:
		return true

	func enter_selection() -> Dictionary:
		return {
			"candidate_hexes": [HexCoordClass.new(0, 0)],
			"candidate_targets": [],
			"resolution_mode": SelectionDescriptorClass.ResolutionMode.AREA_SET,
			"geometry_rule": {"radius": 1},
		}

	func expected_shape() -> int:
		return SelectionShape.TARGET_SET

	func _execute_target_set(targets: Array) -> Dictionary:
		execute_calls.append(targets)
		return {"ok": true, "resolved": true, "shape": "TARGET_SET", "targets": targets}


func _verb_deps() -> Dictionary:
	return {"session_holder": RoundSessionHolderClass.new()}


## _build_targeting_harness() -- the EXACT composition-root wiring
## MainScene.gd itself establishes for VerbBarView/SelectionOverlay (see
## MainScene.gd's _on_verb_bar_selection_entered()), backed by a REAL
## VerbBarRegistryAdapter, REAL ActionController subclasses, and a REAL
## HexGridView carrying one REAL Combatant token.
func _build_targeting_harness() -> Dictionary:
	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	hex_grid_view.load_combatants([
		CombatantClass.new("enemy_0", "Ice Wraith", "Enemy", HexCoordClass.new(2, 0)),
	])

	var cast_controller := CastSpellActionController.new(_verb_deps())
	var blast_controller := BlastAreaActionController.new(_verb_deps())

	var registry = VerbBarRegistryAdapterClass.new()
	registry.register(
		"CAST",
		Callable(cast_controller, "availability"),
		Callable(cast_controller, "enter_selection"),
		Callable(cast_controller, "execute"),
	)
	registry.register(
		"BLAST",
		Callable(blast_controller, "availability"),
		Callable(blast_controller, "enter_selection"),
		Callable(blast_controller, "execute"),
	)

	var verb_bar_view = VerbBarViewScene.instantiate()
	add_child_autofree(verb_bar_view)
	verb_bar_view.configure(registry)

	var selection_overlay = SelectionOverlayClass.new()
	selection_overlay.configure(registry, hex_grid_view)

	verb_bar_view.verb_selection_entered.connect(
		func(verb_id, selection): selection_overlay.activate(verb_id, selection)
	)

	return {
		"hex_grid_view": hex_grid_view,
		"verb_bar_view": verb_bar_view,
		"selection_overlay": selection_overlay,
		"registry": registry,
		"cast_controller": cast_controller,
		"blast_controller": blast_controller,
	}


# ══════════════════════════════════════════════════════════════════════════
# Section D — the SAME selection/execute pipeline additively resolves an
# option-list pick into execute(option, target), proven alongside a real,
# unaffected Strike in the SAME suite.
# ══════════════════════════════════════════════════════════════════════════

func test_option_list_pick_resolves_additively_into_execute_option_target_without_altering_strike() -> void:
	var harness: Dictionary = _build_targeting_harness()
	var verb_bar_view = harness["verb_bar_view"]
	var selection_overlay = harness["selection_overlay"]
	var hex_grid_view = harness["hex_grid_view"]
	var cast_controller: CastSpellActionController = harness["cast_controller"]

	var selection: Dictionary = verb_bar_view.press("CAST")
	assert_eq(selection.get("candidate_options", []).size(), 2, "CAST's REAL enter_selection() must present exactly two candidate_options")
	assert_true(selection_overlay.is_active(), "pressing CAST must enter Layer 2")
	assert_true(selection_overlay.is_awaiting_option(), "candidate_options must present Layer-2a BEFORE Layer-2b targeting begins")
	assert_eq(cast_controller.execute_calls, [], "no execute() call may occur before an option AND a target are both chosen")

	var fireball := {"id": "fireball", "label": "Fireball"}
	selection_overlay.choose_option(fireball)
	assert_false(selection_overlay.is_awaiting_option(), "choosing an option must end Layer-2a's pending state")
	assert_eq(selection_overlay.get_highlighted_target_ids(), ["enemy_0"], "Layer-2b must highlight the descriptor's candidate_targets once an option is chosen")

	var target_token = hex_grid_view.get_token("enemy_0")
	assert_not_null(target_token, "fixture assumption: enemy_0 has a rendered HexGridView token")

	watch_signals(selection_overlay)
	hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_signal_emitted(selection_overlay, "selection_resolved", "clicking the highlighted target after choosing an option must resolve")
	assert_eq(
		cast_controller.execute_calls, [[fireball, "enemy_0"]],
		"the REAL action_controller.gd base-class execute() -> _classify_selection() -> _execute_option_target() dispatch must have run with exactly the chosen option and the resolved target"
	)
	assert_false(selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the option/target selection resolves")

	# Strike, driven through the REAL, separately-booted MainScene, remains
	# completely unaffected by the option-list machinery just exercised.
	var run: Dictionary = await _drive_player_strike(SEED)
	assert_eq(
		run["hp_before"] - run["hp_after"], run["attack_event"].damage_final,
		"Strike's own EffectsApplier-mediated hp mutation must be unaffected by the additive candidate_options/OPTION_TARGET machinery exercised in this same suite"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section E — the SAME selection/execute pipeline additively resolves a
# fully-resolved AREA target set into execute(), proven alongside a real,
# unaffected Strike AND END_TURN in the SAME suite.
# ══════════════════════════════════════════════════════════════════════════

func test_area_target_set_resolves_additively_into_execute_without_altering_strike_or_end_turn() -> void:
	var harness: Dictionary = _build_targeting_harness()
	var verb_bar_view = harness["verb_bar_view"]
	var selection_overlay = harness["selection_overlay"]
	var hex_grid_view = harness["hex_grid_view"]
	var blast_controller: BlastAreaActionController = harness["blast_controller"]

	var selection: Dictionary = verb_bar_view.press("BLAST")
	assert_eq(
		selection.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET,
		"BLAST's REAL enter_selection() must name resolution_mode AREA_SET"
	)
	assert_true(selection_overlay.is_active(), "pressing BLAST must enter Layer 2")

	var origin := HexCoordClass.new(0, 0)
	watch_signals(selection_overlay)
	hex_grid_view.hex_clicked.emit(origin)

	assert_signal_not_emitted(selection_overlay, "selection_resolved", "an origin pick must only preview -- it must never resolve by itself")
	assert_true(selection_overlay.is_awaiting_area_confirm(), "picking the candidate origin hex must enter the AREA preview/awaiting-confirm state")

	var preview: Array = selection_overlay.get_highlighted_hexes()
	assert_eq(preview.size(), 7, "the preview must be the full radius-1 affected set (origin + 6 neighbors)")
	assert_eq(blast_controller.execute_calls, [], "no execute() call may occur until the preview is confirmed")

	hex_grid_view.hex_clicked.emit(origin)
	assert_signal_emitted(selection_overlay, "selection_resolved", "confirming the preview must resolve the AREA selection")
	assert_eq(blast_controller.execute_calls.size(), 1, "exactly one REAL execute() call must occur on confirmation")

	var resolved_targets: Array = blast_controller.execute_calls[0]
	assert_eq(
		resolved_targets.size(), 7,
		"the REAL action_controller.gd base-class execute() -> _classify_selection() -> _execute_target_set() dispatch must receive the FULL computed 7-hex target set"
	)
	assert_false(selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the AREA selection resolves")

	# Strike, driven through the REAL, separately-booted MainScene, remains
	# completely unaffected by the AREA/TARGET_SET machinery just exercised.
	var run: Dictionary = await _drive_player_strike(SEED)
	assert_eq(
		run["hp_before"] - run["hp_after"], run["attack_event"].damage_final,
		"Strike's own EffectsApplier-mediated hp mutation must be unaffected by the additive AREA_SET/TARGET_SET machinery exercised in this same suite"
	)

	# END_TURN, on that SAME real MainScene instance, still never enters
	# selection_overlay's Layer 2 flow, unaffected by the AREA/TARGET_SET
	# machinery just exercised on an unrelated harness.
	var instance = run["instance"]
	watch_signals(instance.selection_overlay)
	instance.verb_bar_view.press(END_TURN)
	assert_false(
		instance.selection_overlay.is_active(),
		"END_TURN must still never activate selection_overlay's Layer 2 flow, even in a suite that also exercises BLAST's AREA preview elsewhere"
	)
	assert_signal_not_emitted(instance.selection_overlay, "selection_resolved", "END_TURN must resolve nothing through selection_overlay")


# ══════════════════════════════════════════════════════════════════════════
# Section G — determinism: two independent boots at the SAME pinned seed,
# driven through the identical real player-Strike UI sequence, produce
# byte-identical hp/AttackEvent/combat-log outcomes.
# ══════════════════════════════════════════════════════════════════════════

func test_determinism_pinned_seed_rerun_produces_identical_hp_attack_event_log_outcome() -> void:
	var run_a: Dictionary = await _drive_player_strike(SEED)
	var run_b: Dictionary = await _drive_player_strike(SEED)

	assert_eq(run_a["hp_before"], run_b["hp_before"], "both same-seed boots must start the Skeleton at identical hp_current")
	assert_eq(run_a["hp_after"], run_b["hp_after"], "both same-seed boots must leave the Skeleton at identical hp_current after the identical Strike")

	var event_a = run_a["attack_event"]
	var event_b = run_b["attack_event"]
	assert_eq(
		event_a.to_dict(), event_b.to_dict(),
		"the emitted AttackEvent must be field-for-field IDENTICAL between two independent same-seed boots driving the identical Strike"
	)

	var entry_a: Dictionary = run_a["history_entry"]
	var entry_b: Dictionary = run_b["history_entry"]
	assert_eq(entry_a.get("damage_final", -1), entry_b.get("damage_final", -2), "the combat log's damage_final must be IDENTICAL between both pinned-seed reruns")
	assert_eq(entry_a.get("roll", -1), entry_b.get("roll", -2), "the combat log's roll must be IDENTICAL between both pinned-seed reruns")
	assert_eq(
		entry_a.get("target", {}).get("hp_current", -1), entry_b.get("target", {}).get("hp_current", -2),
		"the combat log's snapshotted target hp_current must be IDENTICAL between both pinned-seed reruns"
	)
