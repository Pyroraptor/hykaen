extends GutTest
## tests/regression/test_flanking_offguard.gd — FEAT-166 (US-012 /
## FR-008,FR-009,FR-010,FR-012): regression verification of preserved
## behaviors on the KEPT single-stack MainScene composition root (post
## FEAT-001/FEAT-002 UI consolidation, iteration D).
##
## Re-runs the Flanking Off-Guard (+2) rule (core/rules/flanking.gd, FEAT-015
## / US-015 / FR-016) resolved through REAL MainScene Strike resolution --
## i.e. driven through the real, shipped Layer 1 verb bar
## ($VerbBarView, presentation/verb_bar_view.gd) -> `_verb_registry`'s
## STRIKE entry's execute(), which forwards to MainScene's real, wired
## resolve_action_use_case (not a test-local resolve_action_use_case
## instance standing in for it, unlike tests/unit/core/application/
## test_resolve_action_off_guard.gd's criterion 3, which constructs a fresh
## use case with a scripted RNG around the SAME live target Dictionary).
## That existing suite already proves the Off-Guard bonus reaches
## resolve_action_use_case.resolve() itself and that MainScene's
## _refresh_off_guard_conditions() writes into the live combatant
## Dictionaries resolve() reads; this suite closes the remaining gap by
## proving the SAME bonus survives being driven end-to-end through the real
## Presentation path a player actually clicks, against the kept
## single-stack MainScene (no scenes/battlefield/* duplicate remains wired).
##
## FEAT-182 (DEF-001 / FR-009/NFR-003): FEAT-006 (US-006) removed the legacy
## immediate-resolve-on-click Strike control (its .gd/.tscn pair, formerly
## under presentation/) this suite originally drove entirely -- every
## Strike below is retargeted onto the real `_verb_registry`'s STRIKE entry
## (`is_available()`/`enter_selection()`/`execute()`, entered via the real
## `verb_bar_view.press("STRIKE")`) instead, preserving this suite's +2
## Off-Guard flanking-bonus assertion unchanged (NFR-004).
##
## AttackEvent.defense_value is roll-independent (it is the target's
## effective AC after any Off-Guard reduction, computed before the d20 roll
## is applied) -- so this suite can assert the +2 bonus's effect exactly
## through MainScene's real (non-scripted) GodotRandomAdapter-backed
## resolve_action_use_case, without needing to control or predict the
## random roll itself.
##
## test_criteria satisfied: "Flanking Off-Guard (+2) test passes when
## resolved through real MainScene Strike resolution."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const FlankingClass = preload("res://core/rules/flanking.gd")
const RoundEventsClass = preload("res://core/rules/round_events.gd")

const PINNED_SEED: int = 42


func _boot_main_scene(seed_value: int = PINNED_SEED):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _flanking_ally(hex_coord, combatant_id) -> Dictionary -- the SAME synthetic
## ally shape tests/unit/test_main_scene_interactive_wiring.gd's Off-Guard
## scenarios already use, appended directly to MainScene's live `_party`
## Array so the real _refresh_off_guard_conditions() wiring (not a
## re-derived/mocked copy) computes Off-Guard from it.
func _flanking_ally(hex_coord, combatant_id: String) -> Dictionary:
	return {
		"name": "Marigold",
		"hp_current": 10,
		"combatant_id": combatant_id,
		"hex_coord": hex_coord,
	}


func _first_attack_event(instance) -> RoundEventsClass.AttackBroadcast:
	var attack_events: Array = instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast)
	assert_eq(attack_events.size(), 1, "exactly one AttackEvent must have been emitted by the single Strike this scenario drives")
	return attack_events[0]


## _strike_candidate_target_ids(instance) -> Array — obtains the currently
## selectable Strike target ids through the REAL $VerbBarView.press("STRIKE")
## -> `_verb_registry.enter_selection("STRIKE")` path (FEAT-182), mirroring
## $VerbBarView.press()'s own non-END_TURN dispatch exactly (see
## presentation/verb_bar_view.gd).
func _strike_candidate_target_ids(instance) -> Array:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	return selection.get("candidate_targets", [])


## _resolve_strike(instance, target_id) -> Dictionary — resolves a Strike
## against `target_id` through the REAL `_verb_registry.execute("STRIKE",
## ...)` path (FEAT-182), the SAME dispatch $VerbBarView's Layer 2 selection
## overlay itself invokes once a target is clicked (see
## presentation/selection_overlay.gd) -- never a re-derived/duplicate
## resolution path.
func _resolve_strike(instance, target_id: String) -> Dictionary:
	return instance._verb_registry.execute("STRIKE", target_id)


# ══════════════════════════════════════════════════════════════════════════
# Criterion — a Strike resolved through the REAL $VerbBarView ->
# `_verb_registry` STRIKE entry against a live Off-Guard target uses a
# defense_value exactly 2 lower than the identical scenario with no
# flanking set up, proving the +2 bonus reaches real MainScene Strike
# resolution end-to-end.
# ══════════════════════════════════════════════════════════════════════════

func test_baseline_strike_through_real_verb_registry_uses_plain_ac_as_defense_value() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = instance._enemies[0].get("combatant_id", "")
	assert_ne(target_id, "", "fixture assumption: the prologue's enemy carries a non-empty combatant_id")
	assert_eq(
		instance._enemies[0].get("conditions", []), [],
		"fixture assumption: before any flanking is set up, the live enemy carries no conditions"
	)

	var target_ids: Array = _strike_candidate_target_ids(instance)
	assert_true(target_ids.has(target_id), "fixture assumption: the enemy is an in-reach Strike target before any flanking is set up")

	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_true(result.get("resolved", false), "the baseline Strike must resolve through the real `_verb_registry` STRIKE entry")

	var attack_event: RoundEventsClass.AttackBroadcast = _first_attack_event(instance)
	var target_ac: int = instance._enemies[0].get("ac", -1)
	assert_eq(
		attack_event.defense_value, target_ac,
		"without Off-Guard, a Strike resolved through the real `_verb_registry` STRIKE entry must use the target's plain ac as defense_value"
	)


func test_off_guard_flanking_reduces_defense_value_by_exactly_two_through_real_verb_registry() -> void:
	var baseline_instance = _boot_main_scene()
	await get_tree().process_frame

	var baseline_target_id: String = baseline_instance._enemies[0].get("combatant_id", "")
	var baseline_result: Dictionary = _resolve_strike(baseline_instance, baseline_target_id)
	assert_true(baseline_result.get("resolved", false), "the baseline (no-flanking) Strike must resolve")
	var baseline_defense_value: int = _first_attack_event(baseline_instance).defense_value

	# ── A SEPARATE, independent MainScene boot with flanking arranged BEFORE
	# the single Strike this scenario drives -- avoids any risk of the
	# baseline Strike above having already defeated/moved the shared target,
	# and mirrors this codebase's established "two independent boots, one
	# variable changed" determinism-style comparison convention. ────────────
	var off_guard_instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = off_guard_instance._enemies[0].get("combatant_id", "")
	assert_eq(target_id, baseline_target_id, "fixture assumption: both independent boots resolve the same prologue enemy id")

	# Skeleton sits at hex (1,0); Titus already occupies (0,0), the neighbor
	# directly opposite hex (2,0) around Skeleton (established fixture
	# layout, tests/unit/test_main_scene_interactive_wiring.gd). Appending a
	# second party combatant at (2,0) completes the opposite-adjacent
	# flanking pair.
	var ally: Dictionary = _flanking_ally(HexCoordClass.new(2, 0), "synthetic_ally_regression_off_guard_strike")
	off_guard_instance._party.append(ally)
	off_guard_instance._refresh_off_guard_conditions()

	assert_true(
		FlankingClass.OFF_GUARD_CONDITION in off_guard_instance._enemies[0].get("conditions", []),
		"fixture setup: the live enemy target must carry the Off-Guard condition before the Strike is driven"
	)

	var target_ids: Array = _strike_candidate_target_ids(off_guard_instance)
	assert_true(target_ids.has(target_id), "the flanked enemy must remain an in-reach Strike target (Off-Guard never affects reach)")

	var off_guard_result: Dictionary = _resolve_strike(off_guard_instance, target_id)
	assert_true(off_guard_result.get("resolved", false), "the Off-Guard Strike must resolve through the real `_verb_registry` STRIKE entry")

	var off_guard_defense_value: int = _first_attack_event(off_guard_instance).defense_value

	assert_eq(
		off_guard_defense_value, baseline_defense_value - 2,
		"a Strike resolved through the real `_verb_registry` STRIKE entry against a live Off-Guard target must use a defense_value exactly " +
		"2 lower than the identical scenario with no flanking -- proving the blanket +2 bonus reaches real MainScene Strike resolution"
	)


func test_off_guard_condition_is_absent_when_only_a_single_combatant_flanks_through_real_wiring() -> void:
	# Negative case, retargeted against the kept stack: a lone adjacent
	# combatant (no opposite partner) must never flag Off-Guard, so a Strike
	# resolved afterward must still use the plain ac.
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = instance._enemies[0].get("combatant_id", "")
	assert_false(
		instance.status_panel_view.is_off_guard(target_id),
		"fixture assumption: only Titus (a single flanker) is adjacent to the Skeleton at boot -- must not flag Off-Guard"
	)

	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_true(result.get("resolved", false))

	var attack_event: RoundEventsClass.AttackBroadcast = _first_attack_event(instance)
	assert_eq(
		attack_event.defense_value, instance._enemies[0].get("ac", -1),
		"a single, non-opposed flanker must not reduce defense_value through real MainScene Strike resolution"
	)
