extends GutTest

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const STRIKE: String = "STRIKE"
const STRIDE: String = "STRIDE"
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const PROLOGUE_ENCOUNTER_ID: String = "prologue"

## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This probe drives Strike/Stride directly
## against a live round_session/verb registry, so it must drive the SAME real
## handoff tests/boot/test_exploration_to_combat_handoff_trigger.gd exercises
## directly before returning.
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered(PROLOGUE_ENCOUNTER_ID)
	await get_tree().process_frame
	await get_tree().process_frame

	return instance

## Seed 1106 (formerly pinned here) is no longer usable as of FEAT-201: fixing
## the intuition-hardcoding bug (MainScene._build_enemy_combatant() /
## Simulator._build_skeleton_combatant() now read enemy.intuition off
## EnemyResource instead of a hardcoded literal) changed the Skeleton's
## initiative roll (d20+intuition+dexterity, core/combat/encounter.gd),
## which flipped turn order for that specific seed (the enemy now wins
## initiative and acts first, consuming an extra roll off the shared
## random_port stream before this probe's loop begins). Reselected to seed
## 959, under which Titus still wins initiative and the same real-budget-
## depletion scenario this probe exercises holds under the CORRECTED
## initiative computation.
##
## Iteration M ("Cast a Spell"): the prologue roster now also includes
## Marigold (a spellcaster, "player_1"), whose own initiative roll consumes
## an extra draw off the SAME shared, seeded random_port stream ahead of
## Titus's — for BOTH of this probe's pinned seeds (959, 13269), the turn
## order under the three-combatant roster is now Marigold (player_1) ->
## Titus (player_0) -> Skeleton (enemy_0), verified directly against this
## exact boot. This probe's actual concern is real per-ROUND ActionEconomy
## budget depletion for a Strike-capable combatant (Marigold, a spellcaster,
## has no Strike verb available at all) — so Marigold's own leading turn is
## ended first (via the SAME real verb_bar_view.press("END_TURN") flow the
## rest of this suite already uses) to reach Titus, the fixture's intended
## melee striker, before the probe's loop begins.
func test_probe_real_depletion(seed_value = use_parameters([959, 13269])) -> void:
	var instance = await _boot_main_scene_with_seed(seed_value)
	await get_tree().process_frame

	# At these seeds the prologue turn order may seat Marigold or Gram Marx
	# ahead of Titus. Skip ALL non-player_0, non-enemy actors via a while
	# loop (not just the first one) before the probe's loop begins.
	while not instance.round_session.current_actor().is_enemy and instance.round_session.current_actor().display_id() != "player_0":
		instance.verb_bar_view.press("END_TURN")
		await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().display_id()
	assert_eq(actor_id, "player_0", "fixture assumption: Titus (player_0), the melee striker, must be the actor driving this probe")
	var enemy_id: String = ""
	for e in instance._enemies:
		enemy_id = e.combatant_id
		break

	var action_economy = instance.round_session.current_action_economy()

	for i in range(6):
		# FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so
		# each of these repeated real Strikes against the SAME per-round
		# budget simulates its own turn boundary via start_of_turn() (AC-4
		# interleaving) directly on the live domain ActionEconomy -- this
		# probe's actual concern is real per-ROUND budget depletion, not
		# turn-cycling machinery.
		action_economy.start_of_turn()
		assert_true(instance._verb_registry.is_available(STRIKE), "strike should be available at i=%d" % i)
		var selection = instance.verb_bar_view.press(STRIKE)
		var target_ids = selection.get("candidate_targets", [])
		assert_true(target_ids.size() > 0, "must have a target at i=%d" % i)
		var target_id = target_ids[0]
		var target_token = instance.hex_grid_view.get_token(target_id)
		instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
		var hp = instance.status_panel_view.get_status(enemy_id).get("hp_current", -999)
		print("PROBE seed=", seed_value, " i=", i, " remaining=", action_economy.get_remaining(), " enemy_hp=", hp)
		assert_true(hp > 0, "enemy must survive strike %d (seed=%d)" % [i, seed_value])

	print("PROBE after 6 strikes remaining=", action_economy.get_remaining())
	assert_eq(action_economy.get_remaining(), 1, "should have 1 action left after 6 strikes")

	# Now stride to a different hex still adjacent to the enemy.
	var enemy_hex = null
	for e in instance._enemies:
		if e.combatant_id == enemy_id:
			enemy_hex = e.hex_coord
			break

	action_economy.start_of_turn()
	var selection = instance.verb_bar_view.press(STRIDE)
	var candidates = selection.get("candidate_hexes", [])
	var dest = null
	for c in candidates:
		if HexMathClass.hex_distance(c, enemy_hex) == 1:
			dest = c
			break
	assert_not_null(dest, "must find an adjacent stride destination")
	instance.hex_grid_view.hex_clicked.emit(dest)

	# FEAT-007 (US-007 / FR-006, NFR-001): MainScene now wires a real
	# hex_grid_view into StrideActionController's deps, so a successful
	# Stride animates the token via a genuine, real-time Tween
	# (hex_grid_view.animate_token_to()) before the action is spent. The
	# hex_clicked signal above is not awaited (Godot's signal.emit() does
	# not await suspended handlers), so give the Tween chain enough
	# wall-clock time to actually finish before reading the post-Stride
	# action budget below.
	await get_tree().create_timer(0.5).timeout

	print("PROBE after stride remaining=", action_economy.get_remaining())
	assert_eq(action_economy.get_remaining(), 0, "budget should now be fully depleted")

	var hp_final = instance.status_panel_view.get_status(enemy_id).get("hp_current", -999)
	assert_true(hp_final > 0, "enemy must still be alive")
	print("PROBE strike_avail=", instance._verb_registry.is_available(STRIKE), " stride_avail=", instance._verb_registry.is_available(STRIDE))
	assert_false(instance._verb_registry.is_available(STRIKE), "strike must be unavailable now")
	assert_false(instance._verb_registry.is_available(STRIDE), "stride must be unavailable now")
	assert_false(instance.round_session.is_round_over(), "round must not be over")
	assert_false(instance.verb_bar_view.is_locked(), "verb bar must not be locked")
	assert_false(instance.selection_overlay.is_locked(), "selection overlay must not be locked")
