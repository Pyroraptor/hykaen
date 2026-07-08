extends GutTest
## tests/gut/test_mainscene_reaction_resolver_wiring.gd
##
## GUT test suite for FEAT-006 (US-005 / FR-005, ADR-002): wiring the
## reaction resolver into MainScene.gd's composition root.
##
## core/application/round_session.gd already exposes
## set_reaction_resolver_fn(fn: Callable) (FEAT-002 / US-002 / FR-002) as a
## Dependency-Inversion seam — a typed-Callable contract RoundSession invokes
## without ever importing/referencing presentation/turn_controller.gd by
## type (see tests/gut/test_round_session_reaction_resolver_injection.gd).
## This feature is the composition-root half of that seam: MainScene.gd (the
## ONE place both sides of the port are ever named concretely, ADR-002) must
## call round_session.set_reaction_resolver_fn(Callable(turn_controller,
## "resolve_reaction")) — mirroring the EXISTING
## set_token_reposition_fn(Callable(hex_grid_view, "move_token")) wiring
## pattern immediately above it in rewire_session() — both at initial boot
## AND every time rewire_session() re-runs on automatic round continuation
## (_on_round_over(), when the round concludes without a decided outcome).
##
## Verifies (test_criteria):
##   1. set_reaction_resolver_fn is called with
##      Callable(turn_controller, "resolve_reaction") during MainScene
##      initialization.
##   2. rewire_session() re-applies the identical wiring on round
##      continuation (a freshly begin_round()'d RoundSession is never left
##      without a resolver).
##   3. turn_controller.configure_reactions() invocation and signature are
##      unchanged from the pre-change baseline (this feature touches ONLY
##      MainScene.gd's rewire_session(), never presentation/turn_controller.gd).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=42 (the prologue fixture's known-
## good seed, matching this codebase's established convention — see
## tests/infrastructure/test_presentation_stack_wiring.gd) so every scenario
## below can rely on a deterministic first-actor/target layout.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — set_reaction_resolver_fn is called with
# Callable(turn_controller, "resolve_reaction") during MainScene
# initialization.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_resolver_is_wired_to_turn_controller_resolve_reaction_on_boot() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after boot")
	assert_not_null(instance.turn_controller, "MainScene.turn_controller must be wired after boot")

	var fn: Callable = instance.round_session._reaction_resolver_fn
	assert_true(fn.is_valid(), "MainScene must inject a reaction resolver Callable onto round_session during initialization")
	assert_eq(fn.get_object(), instance.turn_controller, "the injected Callable must target MainScene's own turn_controller instance")
	assert_eq(fn.get_method(), &"resolve_reaction", "the injected Callable must target turn_controller.resolve_reaction exactly")


## Behavioral complement to the structural assertion above: the injected
## Callable must actually be *the* live resolve_reaction() method (not a
## same-named decoy) — proven by invoking it directly and observing the
## same no-op contract resolve_reaction() itself documents when the
## reactor is already Spent (reaction_window.open() returns "opened: false"
## WITHOUT ever awaiting the player-facing chooser -- see
## core/application/reaction_window.gd's open() doc). Deliberately uses an
## already-Spent reactor_action_economy so this assertion can complete
## synchronously in a headless test: a trigger that genuinely opened a
## window would `await` the real PlayerReactionChooser wrapping
## $ReactionPromptUI, which blocks on player input that never arrives
## headlessly (correctly so -- the SAME behavior a real, live pop-up would
## exhibit; not a bug in this test's target).
func test_injected_reaction_resolver_callable_actually_invokes_turn_controller_resolve_reaction() -> void:
	var instance = _boot_main_scene()

	var fn: Callable = instance.round_session._reaction_resolver_fn
	assert_true(fn.is_valid(), "fixture assumption: the resolver must already be wired after boot")

	var spent_action_economy = ActionEconomyClass.new()
	while not spent_action_economy.is_spent():
		spent_action_economy.spend_reaction()
	assert_true(spent_action_economy.is_spent(), "fixture assumption: the reactor_action_economy must be fully Spent")

	var trigger: Dictionary = {
		"attacker_id": "nobody",
		"target_id": "nobody-else",
		"defense_type": "ac",
		"reactor_action_economy": spent_action_economy,
	}
	var result: Dictionary = await fn.call(trigger)

	# resolve_reaction() opens `trigger` on the real ReactionWindow; an
	# already-Spent reactor can never open a live window, so it must resolve
	# via the documented ALREADY_SPENT no-op branch rather than hang, crash,
	# or silently no-op with an empty Dictionary -- proving this really is
	# turn_controller.resolve_reaction(), not a stub.
	assert_true(result.has("ok"), "invoking the injected Callable must return turn_controller.resolve_reaction()'s real Dictionary contract")
	assert_eq(result.get("opened", true), false, "an already-Spent reactor must never open a live reaction window")
	assert_eq(result.get("choice", ""), "none", "an already-Spent reactor's reaction must resolve to the documented 'none' no-op choice")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — rewire_session() re-applies the identical wiring on round
# continuation.
# ══════════════════════════════════════════════════════════════════════════

func test_rewire_session_reapplies_identical_wiring_on_round_continuation() -> void:
	var instance = _boot_main_scene()

	var session_before = instance.round_session
	var fn_before: Callable = session_before._reaction_resolver_fn
	assert_true(fn_before.is_valid(), "fixture assumption: the initial boot already wired a resolver")

	# Simulate a round continuation: rewire_session() is the SAME single
	# reusable method _on_round_over() invokes when a round concludes
	# without a decided outcome (see MainScene.gd's own doc) — calling it
	# again here exercises that exact re-wiring path without needing to
	# drive an entire round to completion.
	await instance.rewire_session()

	var session_after = instance.round_session
	assert_ne(session_after, session_before, "rewire_session() must obtain a fresh RoundSession on continuation (begin_round() returns a new instance)")

	var fn_after: Callable = session_after._reaction_resolver_fn
	assert_true(fn_after.is_valid(), "the freshly-begun RoundSession must also have a reaction resolver injected -- never left unwired for even one round")
	assert_eq(fn_after.get_object(), instance.turn_controller, "the re-applied wiring must target the SAME turn_controller instance")
	assert_eq(fn_after.get_method(), &"resolve_reaction", "the re-applied wiring must target resolve_reaction exactly, identical to the initial boot wiring")

	# The OLD session's own Callable is untouched (this composition root
	# never mutates a RoundSession it has already handed off) -- proving
	# this is genuinely a fresh re-application, not a mutation of shared
	# state that happens to be observed twice.
	assert_true(fn_before.is_valid(), "the prior round's own resolver wiring must remain valid/untouched by continuation")


func test_rewire_session_reapplies_wiring_across_multiple_continuations() -> void:
	var instance = _boot_main_scene()

	var seen_session_ids: Array = []
	for i in range(3):
		var session = instance.round_session
		assert_false(seen_session_ids.has(session.get_instance_id()), "round continuation #%d must obtain a genuinely fresh RoundSession, never one already seen" % i)
		seen_session_ids.append(session.get_instance_id())

		var fn: Callable = session._reaction_resolver_fn
		assert_true(fn.is_valid(), "round continuation #%d must leave the current RoundSession with a valid reaction resolver" % i)
		assert_eq(fn.get_object(), instance.turn_controller, "round continuation #%d's wiring must target turn_controller" % i)
		assert_eq(fn.get_method(), &"resolve_reaction", "round continuation #%d's wiring must target resolve_reaction" % i)

		await instance.rewire_session()


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — turn_controller.configure_reactions() invocation and
# signature are unchanged from the pre-change baseline.
# ══════════════════════════════════════════════════════════════════════════

func test_configure_reactions_is_still_invoked_once_with_reaction_window_and_chooser() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.reaction_window, "MainScene must still construct reaction_window (FEAT-207, unchanged)")
	assert_not_null(instance.player_reaction_chooser, "MainScene must still construct player_reaction_chooser (FEAT-207, unchanged)")

	assert_eq(
		instance.turn_controller._reaction_window, instance.reaction_window,
		"turn_controller.configure_reactions() must still be invoked with MainScene's own reaction_window, unchanged by this feature"
	)
	assert_eq(
		instance.turn_controller._reaction_chooser, instance.player_reaction_chooser,
		"turn_controller.configure_reactions() must still be invoked with MainScene's own player_reaction_chooser, unchanged by this feature"
	)


func test_configure_reactions_signature_is_unchanged() -> void:
	var instance = _boot_main_scene()

	var found: bool = false
	for method in instance.turn_controller.get_method_list():
		if method.get("name", "") == "configure_reactions":
			found = true
			assert_eq(
				method.get("args", []).size(), 2,
				"configure_reactions() must still take exactly 2 positional parameters (reaction_window, reaction_chooser) -- this feature must not alter its signature"
			)
	assert_true(found, "turn_controller must still declare a configure_reactions() method")


func test_headless_boot_still_succeeds_after_reaction_resolver_rewiring() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	if packed == null:
		return

	var instance = packed.instantiate()
	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup")
	if instance == null:
		return

	add_child_autofree(instance)
	await get_tree().process_frame

	assert_not_null(instance.round_session, "MainScene.round_session must be a real RoundSession after first frame")
	assert_false(instance.round_session.is_round_over(), "the freshly-begun RoundSession must not already be over with no player input")
	assert_true(instance.round_session._reaction_resolver_fn.is_valid(), "the reaction resolver must be wired by the first frame")
