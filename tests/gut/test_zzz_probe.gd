extends GutTest

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const STRIKE: String = "STRIKE"
const STRIDE: String = "STRIDE"
const HexMathClass = preload("res://core/geometry/hex_math.gd")

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance

func test_probe_real_depletion(seed_value = use_parameters([1106, 13269])) -> void:
	var instance = _boot_main_scene_with_seed(seed_value)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var enemy_id: String = ""
	for e in instance._enemies:
		enemy_id = e.get("combatant_id", e.get("name", ""))
		break

	var action_economy = instance.round_session.current_action_economy()

	for i in range(6):
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
		if e.get("combatant_id", e.get("name","")) == enemy_id:
			enemy_hex = e.get("hex_coord")
			break

	var selection = instance.verb_bar_view.press(STRIDE)
	var candidates = selection.get("candidate_hexes", [])
	var dest = null
	for c in candidates:
		if HexMathClass.hex_distance(c, enemy_hex) == 1:
			dest = c
			break
	assert_not_null(dest, "must find an adjacent stride destination")
	instance.hex_grid_view.hex_clicked.emit(dest)

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
