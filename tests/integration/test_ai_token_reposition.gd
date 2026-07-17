extends GutTest
## tests/integration/test_ai_token_reposition.gd — FEAT-008 (US-008 / FR-012,
## ADR-006): Enemy token visually repositions via the existing move-token
## path.
##
## core/combat/ai.gd's decide_action() already repositions the DOMAIN
## combatant Dictionary's "hex_coord" in place when it issues a Stride
## (FEAT-004/005) -- but that alone never touches the SEPARATE, already-
## instantiated presentation/combatant_token_view.gd CombatantTokenView the
## player actually sees on screen (presentation/hex_grid_view.gd's `_tokens`
## Dictionary). Before this feature, an AI-driven Stride therefore left the
## enemy's on-screen token stuck at its pre-Stride position, even though the
## domain state itself had already moved -- an invisible move.
##
## This suite proves core/application/round_session.gd's advance_ai_turn()
## now closes that gap by invoking the injected `_token_reposition_fn`
## Callable -- wired by MainScene.gd (this composition root's ONLY new wiring
## for this feature) to Callable(hex_grid_view, "move_token") -- the EXACT
## SAME function presentation/movement_input_controller.gd's
## _resync_token_renderers() already calls for a player-driven Step/Stride
## (ADR-006: same call site, different actor_id/destination, no parallel
## reposition implementation).
##
## Verifies (test_criteria):
##   1. Integration test confirms the enemy token's on-screen hex position
##      updates after an AI-driven Stride.
##   2. Test/inspection confirms only one reposition function exists
##      (HexGridView.move_token()) and is called by both the player Step/
##      Stride path and the AI Stride path (no duplicate implementation).

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


# ── Fake/double port implementations (mirrors tests/unit/core/application/test_round_session_ai_turn.gd) ──

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase plus fake ports -- mirrors
## tests/unit/core/application/test_round_session_ai_turn.gd's identically-
## named helper exactly.
func _make_use_case(entries: Array, ai_port, random_number_port, event_sink_port) -> Dictionary:
	var turn_order_port     = FakeTurnOrderPort.new(entries)
	var round_history_port  = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 (US-008): the enemy token's on-screen hex position updates
# after an AI-driven Stride -- driven through the REAL core/combat/ai.gd and
# a REAL, instantiated presentation/hex_grid_view.gd, exactly the way
# MainScene.gd wires them (round_session.set_token_reposition_fn(Callable(
# hex_grid_view, "move_token"))).
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_token_repositions_on_screen_after_ai_driven_stride() -> void:
	var goblin_hex := HexCoordClass.new(0, 0)
	var titus_hex := HexCoordClass.new(9, 0)  # hex_distance 9 -- beyond a single Speed-4 Stride's reach (mirrors tests/unit/core/combat/test_ai_stride_then_strike.gd's guard fixture): the AI Strides but does NOT close into reach, so this test never depends on resolve_action_use_case's Strike math -- it isolates the Stride-reposition behavior this feature adds.

	var goblin = CombatantClass.from_dict({
		"name": "Goblin", "combatant_id": "goblin", "hp_current": 8, "ac": 12,
		"strength": 2, "hex_coord": goblin_hex, "_is_enemy": true,
	})
	var titus = CombatantClass.from_dict({
		"name": "Titus", "combatant_id": "titus", "hp_current": 20, "ac": 14,
		"strength": 5, "hex_coord": titus_hex, "_is_enemy": false,
	})
	var entries: Array = [_entry(goblin), _entry(titus)]

	# The REAL HexGridView -- a separate rendering-layer object from the
	# `goblin`/`titus` domain Dictionaries above, carrying its own
	# CombatantTokenView copy of "goblin"'s hex_coord. Nothing in
	# core/rules/movement.gd/core/combat/ai.gd's domain mutation of `goblin`
	# ever reaches into this view on its own -- only an explicit reposition
	# call (this feature's subject) can move the rendered token.
	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	hex_grid_view.load_combatants([
		CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(goblin_hex.q, goblin_hex.r)),
		CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(titus_hex.q, titus_hex.r)),
	])

	var token_before = hex_grid_view.get_token("goblin")
	assert_not_null(token_before, "fixture assumption: HexGridView must already carry a token for the Enemy actor")
	assert_true(token_before.hex_coord.equals(goblin_hex), "fixture assumption: the token starts at the Enemy's pre-Stride hex")

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(7)
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().get("name", ""), "Goblin", "fixture assumption: the out-of-reach Enemy must act first")

	# The ONLY new wiring this feature introduces: point RoundSession's
	# AI-Stride reposition hook at the SAME hex_grid_view.move_token()
	# MainScene.gd wires in production.
	session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))

	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	# Sanity check: the AI must have actually issued a Stride (domain
	# hex_coord changed) -- otherwise this test would prove nothing.
	var moved_hex = goblin.hex_coord
	assert_false(moved_hex.equals(goblin_hex), "fixture assumption: the out-of-reach AI must Stride toward its target")

	var token_after = hex_grid_view.get_token("goblin")
	assert_not_null(token_after, "the Enemy's token must still be on record after the AI Stride")
	assert_true(
		token_after.hex_coord.equals(moved_hex),
		"the enemy token's on-screen hex position must update to the AI Stride's destination hex"
	)
	assert_eq(
		token_after.position, hex_grid_view.axial_to_pixel_with_offset(moved_hex),
		"the enemy token's rendered screen position must resync to the AI Stride destination's ADR-004 axial-to-pixel projection"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (part A): static source inspection -- exactly one move_token()
# reposition function is DEFINED anywhere in the codebase (on HexGridView),
# and neither MovementInputController nor RoundSession define a second,
# duplicate implementation of their own.
# ══════════════════════════════════════════════════════════════════════════

func test_exactly_one_move_token_reposition_function_is_defined_anywhere() -> void:
	var hex_grid_view_source: String = _read_file("res://presentation/hex_grid_view.gd")
	assert_eq(
		hex_grid_view_source.count("func move_token("), 1,
		"exactly one move_token() reposition function must be defined -- on HexGridView"
	)

	var movement_input_controller_source: String = _read_file("res://presentation/movement_input_controller.gd")
	assert_eq(
		movement_input_controller_source.count("func move_token("), 0,
		"MovementInputController must not define its own duplicate move_token() -- it must call HexGridView's"
	)
	assert_true(
		movement_input_controller_source.contains(".move_token("),
		"the player Step/Stride path must call the shared move_token() function"
	)

	var round_session_source: String = _read_file("res://core/application/round_session.gd")
	assert_eq(
		round_session_source.count("func move_token("), 0,
		"RoundSession must not define its own duplicate move_token()/reposition implementation -- it must invoke the SAME injected function"
	)
	assert_true(
		round_session_source.contains("_token_reposition_fn.call("),
		"RoundSession's AI-Stride path must invoke the SAME injected reposition Callable, not a parallel implementation of its own"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (part B): the REAL MainScene.tscn composition root wires
# RoundSession's AI-Stride reposition hook to the SAME HexGridView instance
# (and the SAME move_token() method) the player Step/Stride path
# (movement_input_controller) already repositions tokens through -- proving
# both paths share the ONE reposition call site at the composition-root
# wiring level, not merely by coincidence of identical method names.
# ══════════════════════════════════════════════════════════════════════════

func test_mainscene_wires_the_ai_stride_reposition_hook_to_the_same_hex_grid_view_move_token_the_player_path_uses() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")

	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "MainScene must inject a token-reposition Callable into RoundSession for AI-issued Strides")
	assert_eq(
		reposition_fn.get_object(), instance.hex_grid_view,
		"the AI-Stride reposition path must target the SAME HexGridView instance the player Step/Stride path renders tokens on"
	)
	assert_eq(
		reposition_fn.get_method(), &"move_token",
		"the AI-Stride reposition path must call move_token() -- the SAME function movement_input_controller.gd's _resync_token_renderers() calls for a player-driven Stride"
	)

	# Sanity check: the player Step/Stride path (movement_input_controller)
	# is configured against this SAME HexGridView instance -- confirming
	# there is exactly ONE HexGridView/move_token() call site both the
	# player and AI Stride paths ultimately reach.
	assert_eq(
		instance.movement_input_controller._hex_grid_view, instance.hex_grid_view,
		"the player Step/Stride path's own hex_grid_view collaborator must be this SAME HexGridView instance"
	)
