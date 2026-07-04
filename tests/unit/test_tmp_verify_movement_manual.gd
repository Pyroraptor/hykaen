extends GutTest

const MainScenePath := "res://MainScene.tscn"

func test_manual_verify_step_through_real_main_scene() -> void:
	var packed: PackedScene = ResourceLoader.load(MainScenePath)
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)

	var actor_before = instance.round_session.current_actor()
	gut.p("actor before: " + str(actor_before.get("name")) + " hex=" + str(actor_before.get("hex_coord")))
	gut.p("selectable step hexes: " + str(instance.movement_input_controller.get_selectable_step_hexes()))
	gut.p("selectable strike targets before: " + str(instance._verb_registry.enter_selection("STRIKE").get("candidate_targets", [])))

	var dest = instance.movement_input_controller.get_selectable_step_hexes()[0]
	gut.p("stepping to: " + str(dest))
	instance.hex_grid_view.hex_clicked.emit(dest)

	var actor_after = instance.round_session.current_actor()
	gut.p("actor after: " + str(actor_after.get("name")) + " hex=" + str(actor_after.get("hex_coord")))
	gut.p("selectable strike targets after: " + str(instance._verb_registry.enter_selection("STRIKE").get("candidate_targets", [])))

	var token = instance.hex_grid_view.get_token(actor_after.get("combatant_id"))
	gut.p("token position after move: " + str(token.position) + " expected: " + str(instance.hex_grid_view.axial_to_pixel_with_offset(dest)))

	assert_true(actor_after.get("hex_coord").equals(dest), "actor must have actually moved to the clicked hex")
	assert_almost_eq(token.position, instance.hex_grid_view.axial_to_pixel_with_offset(dest), Vector2(0.01, 0.01))
