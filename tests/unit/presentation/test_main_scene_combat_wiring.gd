extends GutTest
## tests/unit/presentation/test_main_scene_combat_wiring.gd
##
## GUT suite for FEAT-007 (US-007; FR-007/NFR-001/NFR-003; ADR-004/ADR-005):
## MainScene.gd's composition-root combat pathfinding wiring.
## _rewire_combat_pathfinder() builds passable_fn/move_cost_fn/pathfinder_fn
## from EncounterTileAdapter.make_combat_is_passable()/make_move_cost() and
## HexPathfinder.find_path() and injects the SAME pathfinder_fn Callable into
## both the player Stride controller (verb-deps "pathfinder_fn" key) and the
## enemy AI decision port (set_stride_pathfinder_fn()) -- one algorithm
## driving both movers symmetrically. round_session.set_token_animate_path_fn()
## is wired to a per-hex closure over hex_grid_view.animate_token_to(), and
## hex_grid_view itself is present in the Stride/Step verb-deps dictionary at
## verb-table construction. This is the single composition-root choke point
## (ADR-005) -- no other file constructs these Callables.
##
## Verifies (test_criteria):
##   1. pathfinder_fn is injected into the player Stride controller after
##      _rewire_combat_pathfinder() runs.
##   2. The enemy stride pathfinder is wired to the AI decision port
##      (set_stride_pathfinder_fn) after rewire.
##   3. round_session.set_token_animate_path_fn()'s closure is wired and,
##      when invoked, delegates to hex_grid_view.animate_token_to() per hex.
##   4. hex_grid_view is present in the Stride/Step deps dictionaries at
##      verb-table construction.
##   5. All of the above hold after a real _on_combat_triggered('prologue')
##      call against a real (test) MainScene instance.
##   6. The SAME pathfinder_fn Callable drives both the player Stride
##      controller and the AI decision port (ADR-004's "one algorithm, both
##      movers" guarantee).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const AutoReactionChooserClass = preload("res://infrastructure/auto_reaction_chooser.gd")

const PINNED_SEED: int = 42


## _boot_main_scene() -- mirrors tests/unit/test_main_scene_interactive_wiring.gd's
## established boot helper: real res://MainScene.tscn, pinned seed=42 (the
## prologue fixture's known-good initiative roll), the headless
## AutoReactionChooser swapped in so no test here can block on a real player
## reaction prompt.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PINNED_SEED
	add_child_autofree(instance)
	if instance.turn_controller != null and instance.reaction_window != null:
		instance.turn_controller.configure_reactions(instance.reaction_window, AutoReactionChooserClass.new("pass"))
	return instance


## _boot_and_trigger_combat() -- boots MainScene and drives the real
## _on_combat_triggered('prologue') handoff (this feature's own trigger for
## _rewire_combat_pathfinder()), then settles a couple of frames so any
## deferred wiring completes.
func _boot_and_trigger_combat():
	var instance = _boot_main_scene()
	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame
	return instance


## _SpyTokenView -- mirrors tests/unit/presentation/test_hex_grid_view_token_animation.gd's
## established double: a minimal Node2D standing in for a CombatantTokenView,
## recording every reposition() call (the sole method move_token() -- itself
## invoked only once a real animate_token_to() tween completes -- ever calls
## on a token), so per-hex animate_token_to() delegation is provable without
## reaching into HexGridView internals.
class _SpyTokenView:
	extends Node2D
	var reposition_calls: Array = []
	var hex_coord = null

	func reposition(new_hex_coord, _offset: Vector2 = Vector2.ZERO) -> void:
		reposition_calls.append(new_hex_coord)
		hex_coord = new_hex_coord


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: pathfinder_fn is injected into the player Stride controller
# after _rewire_combat_pathfinder() runs.
# ══════════════════════════════════════════════════════════════════════════

func test_pathfinder_fn_is_injected_into_the_player_stride_controller_after_rewire() -> void:
	var instance = await _boot_and_trigger_combat()

	var stride_controller = instance._controller("STRIDE")
	assert_not_null(stride_controller, "MainScene must be able to construct the STRIDE controller after combat is triggered")
	assert_true(
		stride_controller._pathfinder_fn.is_valid(),
		"the player Stride controller's pathfinder_fn seam must be a valid, wired Callable after _rewire_combat_pathfinder() runs"
	)

	# Behavioral proof this is a real HexPathfinder.find_path()-shaped
	# Callable, not just any valid Callable: start == goal must answer the
	# single-element [start] path per HexPathfinder's own documented
	# contract (core/geometry/hex_pathfinder.gd's file-level doc).
	var hex := HexCoordClass.new(0, 0)
	var result: Array = stride_controller._pathfinder_fn.call(hex, hex)
	assert_eq(result.size(), 1, "pathfinder_fn(start, start) must answer the single-element [start] path")
	assert_true(result[0].equals(hex), "pathfinder_fn(start, start)'s single element must equal start")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: the enemy stride pathfinder is wired to the AI decision port
# (set_stride_pathfinder_fn) after rewire.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_stride_pathfinder_is_wired_to_the_ai_decision_port_after_rewire() -> void:
	var instance = await _boot_and_trigger_combat()

	assert_not_null(instance.run_round_use_case, "MainScene must wire a real RunRoundUseCase after combat is triggered")
	var ai_decision_port = instance.run_round_use_case._ai_decision_port
	assert_not_null(ai_decision_port, "RunRoundUseCase must carry the real AI decision port injected by _on_combat_triggered()")

	assert_true(
		ai_decision_port._stride_pathfinder_fn.is_valid(),
		"the AI decision port's stride pathfinder seam must be wired via set_stride_pathfinder_fn() after _rewire_combat_pathfinder() runs"
	)


## Criterion 6 (folded in here since it needs both controllers constructed):
## the SAME pathfinder_fn Callable drives both the player Stride controller
## and the AI decision port -- one pathfinding algorithm, both movers.
func test_the_same_pathfinder_fn_drives_both_the_player_stride_controller_and_the_ai_decision_port() -> void:
	var instance = await _boot_and_trigger_combat()

	var stride_controller = instance._controller("STRIDE")
	var ai_decision_port = instance.run_round_use_case._ai_decision_port

	assert_eq(
		stride_controller._pathfinder_fn, ai_decision_port._stride_pathfinder_fn,
		"the player Stride controller and the AI decision port must share the SAME pathfinder_fn Callable (ADR-004: one algorithm, both movers)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: round_session.set_token_animate_path_fn()'s closure is wired
# and, when invoked, delegates to hex_grid_view.animate_token_to() per hex.
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_animate_path_fn_is_wired_to_main_scenes_per_hex_closure() -> void:
	var instance = await _boot_and_trigger_combat()

	assert_not_null(instance.round_session, "MainScene must have a real round_session after combat is triggered")
	assert_eq(
		instance.round_session._token_animate_path_fn, Callable(instance, "_animate_token_along_stride_path"),
		"round_session's animate-path seam must be wired to MainScene's own per-hex animation closure"
	)


func test_animate_token_along_stride_path_delegates_to_hex_grid_view_animate_token_to_per_hex() -> void:
	var instance = await _boot_and_trigger_combat()

	var actor = instance._party[0]
	var actor_id: String = actor.display_id()
	var start_hex = actor.hex_coord

	var h1 := HexCoordClass.new(start_hex.q + 1, start_hex.r)
	var h2 := HexCoordClass.new(start_hex.q + 2, start_hex.r)

	var spy_token := _SpyTokenView.new()
	add_child_autofree(spy_token)
	instance.hex_grid_view._tokens[actor_id] = spy_token

	await instance._animate_token_along_stride_path(actor_id, [start_hex, h1, h2])

	assert_eq(
		spy_token.reposition_calls.size(), 2,
		"the per-hex closure must delegate to hex_grid_view.animate_token_to() once per transit hex (excluding the already-occupied start hex)"
	)
	if spy_token.reposition_calls.size() == 2:
		assert_true(spy_token.reposition_calls[0].equals(h1), "the first delegated hex must be the first transit hex after start")
		assert_true(spy_token.reposition_calls[1].equals(h2), "the second delegated hex must be the final goal hex")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: hex_grid_view is present in the Stride/Step deps dictionaries
# at verb-table construction.
# ══════════════════════════════════════════════════════════════════════════

func test_hex_grid_view_is_present_in_the_verb_deps_dictionary() -> void:
	var instance = await _boot_and_trigger_combat()

	var deps: Dictionary = instance._verb_deps()
	assert_eq(
		deps.get("hex_grid_view"), instance.hex_grid_view,
		"MainScene's verb-deps dictionary must carry the real hex_grid_view at verb-table construction"
	)


func test_hex_grid_view_is_wired_into_the_stride_controller() -> void:
	var instance = await _boot_and_trigger_combat()

	var stride_controller = instance._controller("STRIDE")
	assert_eq(
		stride_controller._hex_grid_view, instance.hex_grid_view,
		"the player Stride controller must receive the real hex_grid_view via the verb-deps dictionary"
	)


func test_hex_grid_view_is_wired_into_the_step_controller() -> void:
	var instance = await _boot_and_trigger_combat()

	var step_controller = instance._controller("STEP")
	assert_eq(
		step_controller._hex_grid_view, instance.hex_grid_view,
		"the player Step controller must receive the real hex_grid_view via the verb-deps dictionary"
	)
