extends GutTest
## tests/regression/test_ranged_reach_targeting.gd — FEAT-166 (US-012 /
## FR-008,FR-009,FR-010,FR-012): regression verification of preserved
## behaviors on the KEPT single-stack MainScene composition root (post
## FEAT-001/FEAT-002 UI consolidation, iteration D).
##
## Re-runs ranged-weapon reach/target-selection (FEAT-140/FEAT-154, resolves
## FIND-143/FIND-146) against the CONSOLIDATED single-stack MainScene:
## tests/unit/core/application/test_resolve_action_ranged_reach.gd already
## proves the domain/application reach gate (core/application/
## resolve_action_use_case.gd) in isolation. Nothing drives ranged
## reach/targeting through a REAL, booted res://MainScene.tscn on its own --
## this suite closes that gap, proving the ranged reach precondition and
## `_verb_registry`'s STRIKE entry's target-selection filter both still hold
## once wired through the ONE kept composition root (no
## scenes/battlefield/* duplicate stack remains to diverge from).
##
## FEAT-182 (DEF-001 / FR-009/NFR-003): FEAT-006 (US-006) removed the legacy
## immediate-resolve-on-click Strike control (its .gd/.tscn pair, formerly
## under presentation/) this suite originally drove entirely -- every
## Strike below is retargeted onto the real `_verb_registry`'s STRIKE entry
## (`is_available()`/`enter_selection()`/`execute()`, entered via the real
## `verb_bar_view.press("STRIKE")`) instead, preserving this suite's
## "only in-reach ranged targets are selectable/resolvable" assertions
## unchanged.
##
## The prologue fixture's party member (Titus) is equipped with a melee
## weapon (longsword) by data/characters/titus.tres -- there is no ranged
## party-member fixture in this steel thread yet. Mirroring the established
## convention already used by this codebase's own Off-Guard regression
## suites (mutating a live combatant Dictionary directly, e.g.
## MainScene._party.append()/_refresh_off_guard_conditions() in
## tests/unit/test_main_scene_interactive_wiring.gd), this suite equips the
## REAL, live Titus Dictionary MainScene built at boot with a ranged
## "range_hexes" weapon key and re-invokes MainScene's own real
## _on_active_actor_changed() re-entry point (the SAME handler
## TurnController's active_actor_changed signal already drives) so
## `_verb_registry`'s STRIKE entry re-derives its live in-reach filter
## (_strike_reachable_targets(), MainScene.gd) from that live data -- never a
## test-local stand-in for the real composition root.
##
## test_criteria satisfied: "Ranged reach and target-selection tests pass
## unchanged against the kept presentation/* stack."

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const RoundEventsClass = preload("res://core/rules/round_events.gd")

const PINNED_SEED: int = 42
const RANGE_HEXES: int = 8  # mirrors shortbow's data/weapons/shortbow.tres range_hexes fixture


func _boot_main_scene(seed_value: int = PINNED_SEED):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _equip_active_actor_with_ranged_weapon(instance, range_hexes) -> Dictionary
## -- mutates the LIVE current-actor combatant Dictionary's "weapon" key to
## carry "range_hexes" (the SAME discriminant core/application/
## resolve_action_use_case.gd's _is_ranged_weapon() and presentation/
## strike_action_control.gd's _is_ranged_weapon() both key off of), then
## re-invokes MainScene's real _on_active_actor_changed() re-entry point so
## $StrikeActionControl/movement_input_controller re-derive their live state
## from the mutated weapon -- returns the live actor Dictionary for further
## mutation (e.g. repositioning the target) by the caller.
func _equip_active_actor_with_ranged_weapon(instance, range_hexes: int) -> Dictionary:
	var actor: Dictionary = instance.round_session.current_actor()
	actor["weapon"]["range_hexes"] = range_hexes
	instance._on_active_actor_changed(actor)
	return actor


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
## resolution path. Rejects (returning {"ok": false, "error":
## "ERR_TARGET_NOT_SELECTABLE"}) HERE, before ever reaching
## resolve_action_use_case, for a target_id outside the current in-reach
## filter -- including a stale/spoofed id -- exactly as the removed legacy
## Strike control used to (see MainScene.gd's _verb_bar_strike_execute()).
func _resolve_strike(instance, target_id: String) -> Dictionary:
	return instance._verb_registry.execute("STRIKE", target_id)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a target within range_hexes but beyond melee adjacency is
# offered as a selectable target by the real `_verb_registry` STRIKE entry
# and resolves successfully through the kept single-stack MainScene.
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_target_beyond_melee_adjacency_but_within_range_hexes_is_selectable_and_resolves() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor: Dictionary = _equip_active_actor_with_ranged_weapon(instance, RANGE_HEXES)
	var target_id: String = instance._enemies[0].get("combatant_id", "")
	assert_ne(target_id, "", "fixture assumption: the prologue's enemy carries a non-empty combatant_id")

	# Reposition the enemy to hex_distance 3 from the actor -- well beyond
	# melee's 6-neighbor (distance 1) adjacency check, but comfortably inside
	# an 8-hex ranged weapon's reach.
	var actor_hex = actor.get("hex_coord")
	instance._enemies[0]["hex_coord"] = HexCoordClass.new(actor_hex.q + 3, actor_hex.r)
	instance._on_active_actor_changed(actor)

	var selectable_ids: Array = _strike_candidate_target_ids(instance)
	assert_true(
		selectable_ids.has(target_id),
		"the real `_verb_registry` STRIKE entry must offer a non-adjacent-but-in-range target as selectable once the actor's weapon carries range_hexes"
	)

	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_true(result.get("ok", false), "a ranged Strike within range_hexes must resolve ok through the real `_verb_registry` STRIKE entry")
	assert_true(result.get("resolved", false), "a ranged Strike within range_hexes must be marked resolved")

	var attack_event: RoundEventsClass.AttackBroadcast = _first_attack_event(instance)
	assert_eq(attack_event.target_name, instance._enemies[0].get("name", ""), "the AttackEvent must target the repositioned enemy")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a target beyond range_hexes is neither offered as selectable
# nor resolvable (defense in depth), through the kept single-stack MainScene.
# ══════════════════════════════════════════════════════════════════════════

func test_target_beyond_range_hexes_is_not_selectable_and_select_target_is_rejected_with_no_side_effects() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor: Dictionary = _equip_active_actor_with_ranged_weapon(instance, RANGE_HEXES)
	var target_id: String = instance._enemies[0].get("combatant_id", "")

	var actor_hex = actor.get("hex_coord")
	instance._enemies[0]["hex_coord"] = HexCoordClass.new(actor_hex.q + RANGE_HEXES + 5, actor_hex.r)
	instance._on_active_actor_changed(actor)

	var selectable_ids: Array = _strike_candidate_target_ids(instance)
	assert_false(
		selectable_ids.has(target_id),
		"the real `_verb_registry` STRIKE entry must NOT offer a target beyond range_hexes as selectable"
	)
	assert_false(
		instance._verb_registry.is_available("STRIKE"),
		"`_verb_registry`'s STRIKE entry must be unavailable when the only enemy is out of range_hexes"
	)

	var hp_before: int = instance._enemies[0].get("hp_current", -1)
	var budget_before: int = instance.round_session.current_action_economy().get_remaining()

	# Defense in depth: even a stale/spoofed id (never among the offered
	# candidate_targets) must be rejected before ever reaching
	# resolve_action_use_case.
	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_false(result.get("ok", true), "a Strike on an out-of-range target must report ok:false")
	assert_eq(result.get("error", ""), "ERR_TARGET_NOT_SELECTABLE")

	assert_eq(instance._enemies[0].get("hp_current", -2), hp_before, "an out-of-range Strike attempt must not change the target's HP")
	assert_eq(
		instance.round_session.current_action_economy().get_remaining(), budget_before,
		"an out-of-range Strike attempt must not spend any of the actor's action budget"
	)
	assert_eq(
		instance.event_sink.log.filter(func(e): return e is RoundEventsClass.AttackBroadcast).size(), 0,
		"no AttackEvent may be emitted for a rejected out-of-range ranged Strike"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the shortbow WeaponResource fixture's range_hexes wires
# through the SAME reach gate end-to-end, against the kept stack.
# ══════════════════════════════════════════════════════════════════════════

func test_shortbow_resource_range_hexes_gates_targeting_through_real_mainscene() -> void:
	var shortbow = ResourceLoader.load("res://data/weapons/shortbow.tres")
	assert_not_null(shortbow, "data/weapons/shortbow.tres must load")
	if shortbow == null:
		return
	assert_true(shortbow.range_hexes > 1, "shortbow.range_hexes must exceed melee's default of 1")

	var instance = _boot_main_scene()
	await get_tree().process_frame

	var actor: Dictionary = _equip_active_actor_with_ranged_weapon(instance, shortbow.range_hexes)
	var target_id: String = instance._enemies[0].get("combatant_id", "")

	var actor_hex = actor.get("hex_coord")
	instance._enemies[0]["hex_coord"] = HexCoordClass.new(actor_hex.q + shortbow.range_hexes, actor_hex.r)
	instance._on_active_actor_changed(actor)

	assert_true(
		_strike_candidate_target_ids(instance).has(target_id),
		"a target at exactly shortbow.range_hexes must be selectable through the real `_verb_registry` STRIKE entry"
	)
	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_true(result.get("ok", false), "a Strike at exactly shortbow.range_hexes must resolve ok")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — existing melee target-selection (no range_hexes key) is
# unaffected, unchanged against the kept stack (the prologue's own default
# boot behavior).
# ══════════════════════════════════════════════════════════════════════════

func test_melee_target_selection_is_unaffected_by_this_suites_ranged_scenarios() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var target_id: String = instance._enemies[0].get("combatant_id", "")
	assert_true(
		_strike_candidate_target_ids(instance).has(target_id),
		"the prologue's default melee-adjacent target selection must remain unchanged (Titus/Skeleton start adjacent)"
	)

	var result: Dictionary = _resolve_strike(instance, target_id)
	assert_true(result.get("resolved", false), "the unmodified prologue melee Strike must still resolve through the kept single-stack MainScene")
