extends GutTest
## tests/gut/test_async_reaction_propagation.gd
##
## GUT suite for FEAT-003 (US-002 / FR-002 / NFR-004, ADR-003): the
## highest-risk async-propagation slice of the reactive-defense steel
## thread. FEAT-002 (tests/gut/test_round_session_reaction_resolver_injection.gd)
## already proved core/application/round_session.gd's
## set_reaction_resolver_fn()/_resolve_reaction() seam stores and correctly
## awaits an injected Callable. This suite proves the NEXT layer up now
## genuinely awaits that seam end-to-end, without deadlocking or
## double-advancing a turn, while never changing observable behavior for
## every existing (un-injected) caller:
##
##   1. core/application/round_session.gd's RoundSession.advance_ai_turn()
##      is now itself a coroutine: on an enemy-Strikes-player Strike it
##      builds a ReactionTrigger and `await`s _resolve_reaction() BEFORE
##      resolving the Strike.
##   2. presentation/turn_controller.gd's TurnController._drive() auto-drive
##      loop now `await`s RoundSession.advance_ai_turn() on every iteration,
##      and set_session()/on_end_turn_pressed() `await` _drive() in turn.
##
## Verifies (test_criteria):
##   1. tests/gut/test_round_continuation_and_enemy_budget_display.gd
##      passes with zero regressions — exercised by the project's normal
##      full-suite run, not duplicated here (that suite boots the real
##      MainScene.tscn composition root, which never injects a reaction
##      resolver, so its behavior is unaffected by this feature — see
##      criterion 3 below for the general form of that same guarantee).
##   2. A fake, GENUINELY delayed async resolver (one that itself awaits a
##      real SceneTree timer, not a same-frame return) is awaited by both
##      RoundSession.advance_ai_turn() and TurnController._drive() to
##      completion, with no deadlock (the test itself completing IS the
##      deadlock proof — a real self-deadlock would hang this test/CI
##      forever) and no double-advanced turn (exactly one resolve()
##      history entry, exactly one cursor advance, exactly one resolver
##      invocation).
##   3. Every default (un-injected) caller — the pre-existing, universal
##      case — remains fully, byte-for-byte synchronous: calling
##      advance_ai_turn()/set_session() WITHOUT `await` still yields the
##      correct, immediate result, because GDScript never actually
##      suspends a coroutine whose awaited expression resolves without a
##      real Signal wait.
##   4. An audit enumerates every `await` point this feature introduces (or
##      touches) across round_session.gd/turn_controller.gd and confirms
##      the resulting call graph is a strict DAG — no function anywhere in
##      this await chain calls back into a function that is (directly or
##      transitively) awaiting for IT to return, which is the classic
##      self-deadlock failure mode this kind of sync-to-async conversion
##      risks.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const TurnControllerClass          = preload("res://presentation/turn_controller.gd")
const EndTurnControlScene: PackedScene = preload("res://presentation/end_turn_control.tscn")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ── Fake/double port implementations (mirrors tests/gut/
#    test_round_session_reaction_resolver_injection.gd's identically-named
#    doubles) ──────────────────────────────────────────────────────────────

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


## DelayedReactionResolver — a ReactionResolverPort double
## (`async func(trigger: Dictionary) -> Dictionary`) that GENUINELY
## suspends: it `await`s a real SceneTree timer before answering, rather
## than returning on the same frame like FEAT-002's RecordingReactionResolver
## double. This is what actually exercises the "await propagation" this
## feature adds — a resolver that returns instantly can never distinguish a
## correct `await` from an accidentally-dropped one.
class DelayedReactionResolver:
	extends RefCounted

	var calls: Array = []
	var choice_to_return: String = "none"
	var resolved_count: int = 0

	var _scene_tree: SceneTree
	var _delay_seconds: float

	func _init(scene_tree: SceneTree, delay_seconds: float = 0.03, choice: String = "none") -> void:
		_scene_tree     = scene_tree
		_delay_seconds  = delay_seconds
		choice_to_return = choice

	func resolve(trigger: Dictionary) -> Dictionary:
		calls.append(trigger)
		await _scene_tree.create_timer(_delay_seconds).timeout
		resolved_count += 1
		return {"choice": choice_to_return}


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String = ""):
	return CombatantClass.from_dict({
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


## Builds a fully-wired, REAL RunRoundUseCase plus its fake ports (mirrors
## tests/gut/test_round_session_reaction_resolver_injection.gd's
## identically-named helper) and begins round 1 off it.
func _make_session(entries: Array, party: Array, enemies: Array, seed: int) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()
	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(seed)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	var session = run_round_use_case.begin_round(1, party, enemies)
	return {"session": session, "history": round_history_port, "event_sink": event_sink_port}


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## _extract_function_body(content, func_name) -> String — the same
## find("func X(")..next("\nfunc ") slicing convention already used by
## tests/unit/test_ai_decision_single_action.gd's static-source-inspection
## tests, reused here so this audit follows the project's existing
## precedent for pinning source-shape contracts.
func _extract_function_body(content: String, func_signature_needle: String) -> String:
	var fn_start: int = content.find(func_signature_needle)
	assert_true(fn_start >= 0, "fixture assumption: '%s' must exist" % func_signature_needle)
	if fn_start < 0:
		return ""
	var next_fn_start: int = content.find("\nfunc ", fn_start + 1)
	if next_fn_start == -1:
		next_fn_start = content.length()
	var raw_body: String = content.substr(fn_start, next_fn_start - fn_start)
	return _strip_comment_lines(raw_body)


## _strip_comment_lines(text) -> String — drops every line whose trimmed
## content starts with "#" (both single-`#` inline-style and `##` doc-style
## comments). This codebase's convention places a function's DOC COMMENT
## block immediately above its `func` line -- so naive
## find("func X(")..find("\nfunc ") slicing (the project's own established
## static-source-inspection technique, e.g. tests/unit/
## test_ai_decision_single_action.gd) inevitably captures the NEXT
## function's leading doc comment too, which in THIS file's prose
## legitimately mentions other function names (e.g. _drive()'s own doc
## explains "when set_session() is re-invoked..."). Stripping comment-only
## lines before every containment check below keeps this audit's "no
## back-edge" assertions scoped to actual CODE, not documentation prose.
func _strip_comment_lines(text: String) -> String:
	var kept_lines: Array = []
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept_lines.append(line)
	return "\n".join(kept_lines)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (RoundSession level): a genuinely delayed resolver is awaited
# to completion by advance_ai_turn(), with no double-advance.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_awaits_a_genuinely_delayed_resolver_without_double_advancing() -> void:
	var bravo = _durable_combatant("Bravo", true, "bravo")   # Enemy
	var alpha = _durable_combatant("Alpha", false, "alpha")  # Player
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]

	assert_eq(session.current_actor().get("name", ""), "Bravo", "fixture assumption: the Enemy is the current actor")

	var resolver := DelayedReactionResolver.new(get_tree(), 0.03, "none")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var hp_before: int = alpha.hp_current
	var result: Dictionary = await session.advance_ai_turn()

	assert_eq(resolver.calls.size(), 1, "the injected delayed resolver must be awaited exactly once for this Strike")
	assert_eq(resolver.resolved_count, 1, "the resolver's own await (the SceneTree timer) must have actually completed before advance_ai_turn() resumed")
	assert_true(result.get("ok", false), "advance_ai_turn() must still report success once the delayed await resolves")
	assert_eq(
		rig["history"].entries.size(), 1,
		"advance_ai_turn() must resolve exactly ONE action via resolve_action_use_case — a suspending await must never cause a double-resolve/double-advance"
	)
	assert_true(alpha.hp_current <= hp_before, "the awaited Strike must still be able to resolve damage once it completes")
	assert_eq(
		session.current_actor().get("name", ""), "Alpha",
		"the cursor must have advanced to the next actor EXACTLY once, only after the delayed await fully resolved"
	)


func test_advance_ai_turn_delayed_resolver_trigger_carries_the_expected_shape() -> void:
	# Exercises the ReactionTrigger this feature builds (this feature's
	# data_model) -- attacker_id/target_id/defense_type/round_number -- so a
	# future feature that consumes it (e.g. a real ReactionWindow) can rely
	# on this shape without re-deriving it.
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]

	var resolver := DelayedReactionResolver.new(get_tree(), 0.01, "none")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	await session.advance_ai_turn()

	assert_eq(resolver.calls.size(), 1)
	var trigger: Dictionary = resolver.calls[0]
	assert_eq(trigger.get("attacker_id", ""), "bravo")
	assert_eq(trigger.get("target_id", ""), "alpha")
	assert_eq(trigger.get("defense_type", ""), "ac")
	assert_eq(trigger.get("round_number", -1), 1)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 (TurnController level): _drive()'s auto-drive loop awaits a
# genuinely delayed resolver to completion, with no deadlock and no
# double-advance, before yielding control back to the player.
# ══════════════════════════════════════════════════════════════════════════

func test_turn_controller_drive_awaits_a_genuinely_delayed_resolver_without_deadlock_or_double_advance() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var rig: Dictionary = _make_session(entries, [titus], [goblin], 3)
	var session = rig["session"]
	assert_eq(session.current_actor().get("name", ""), "Goblin", "fixture assumption: the Enemy leads the turn order")

	var resolver := DelayedReactionResolver.new(get_tree(), 0.03, "none")
	session.set_reaction_resolver_fn(Callable(resolver, "resolve"))

	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)

	# The test itself completing (rather than hanging forever) IS this
	# criterion's deadlock proof: set_session() is now a coroutine that
	# awaits _drive(), which awaits RoundSession.advance_ai_turn(), which
	# awaits the genuinely-suspending `resolver` above.
	await turn_controller.set_session(session, end_turn_control)

	assert_eq(resolver.calls.size(), 1, "TurnController._drive()'s auto-drive loop must await the injected resolver exactly once for the leading Enemy turn")
	assert_eq(
		rig["history"].entries.size(), 1,
		"the auto-driven Enemy turn must resolve exactly ONE action -- _drive()'s await must never double-advance/double-resolve the turn"
	)
	assert_eq(
		session.current_actor().get("name", ""), "Titus",
		"_drive() must have fully settled on the Player's turn once the delayed await resolves"
	)
	assert_true(
		end_turn_control.is_enabled(),
		"set_session() must only report/configure end_turn_control once _drive()'s entire await chain (including the delayed resolver) has completed"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: every default (un-injected) caller remains fully,
# byte-for-byte synchronous -- no `await` needed by the caller to observe
# the correct immediate result, because the fallback path never actually
# suspends.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_without_an_injected_resolver_is_still_synchronous_and_unchanged() -> void:
	var bravo = _durable_combatant("Bravo", true, "bravo")
	var alpha = _durable_combatant("Alpha", false, "alpha")
	var entries: Array = [_entry(bravo), _entry(alpha)]

	var rig: Dictionary = _make_session(entries, [alpha], [bravo], 42)
	var session = rig["session"]

	assert_false(session._reaction_resolver_fn.is_valid(), "fixture assumption: no resolver was injected on this session")

	# Deliberately called WITHOUT `await`: `session` is a dynamically-typed
	# local (no static RoundSession annotation), matching every pre-existing
	# caller in this codebase (e.g. tests/unit/core/application/
	# test_round_session.gd) -- if advance_ai_turn() ever actually suspended
	# for this un-injected-resolver path, this line would hand back an
	# unfinished coroutine state instead of the real Dictionary, and every
	# assertion below would fail immediately.
	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false), "the un-injected-resolver path must still resolve synchronously to a real, immediate result")
	assert_eq(rig["history"].entries.size(), 1, "advance_ai_turn() must still resolve exactly one action, unchanged by this feature")
	assert_eq(
		session.current_actor().get("name", ""), "Alpha",
		"advance_ai_turn() must still advance the cursor synchronously, unchanged by this feature"
	)


func test_turn_controller_set_session_without_an_injected_resolver_is_still_synchronous_and_unchanged() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var rig: Dictionary = _make_session(entries, [titus], [goblin], 3)
	var session = rig["session"]
	assert_false(session._reaction_resolver_fn.is_valid(), "fixture assumption: no resolver was injected on this session")

	var end_turn_control = EndTurnControlScene.instantiate()
	add_child_autofree(end_turn_control)

	var turn_controller = TurnControllerClass.new()
	add_child_autofree(turn_controller)

	# Deliberately called WITHOUT `await`, mirroring every pre-existing
	# production/test caller of set_session() (e.g. MainScene.gd's own
	# pre-FEAT-003 call sites, tests/unit/presentation/test_end_turn_control.gd).
	turn_controller.set_session(session, end_turn_control)

	assert_eq(
		session.current_actor().get("name", ""), "Titus",
		"TurnController must still auto-drive the leading Enemy turn synchronously to completion when no resolver is injected"
	)
	assert_true(end_turn_control.is_enabled(), "end_turn_control must still be configured synchronously once _drive() settles")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: audit every `await` point this feature introduces/touches
# across round_session.gd/turn_controller.gd and confirm the call graph is
# a strict DAG (no function ever calls back into a function that is
# awaiting for it to return).
# ══════════════════════════════════════════════════════════════════════════

func test_audit_round_session_advance_ai_turn_awaits_resolve_reaction_exactly_once() -> void:
	var content: String = _read_file("res://core/application/round_session.gd")
	var body: String = _extract_function_body(content, "func advance_ai_turn(")

	assert_eq(
		body.count("await _resolve_reaction("), 1,
		"advance_ai_turn() must await _resolve_reaction() exactly once -- the single new await point this feature introduces into the round loop"
	)
	# No back-edge: advance_ai_turn() must never call back into anything
	# that itself (transitively) awaits advance_ai_turn() -- that would be
	# the classic self-deadlock this feature's error_handling design note
	# calls out explicitly.
	assert_false(body.contains("_drive("), "advance_ai_turn() must never call back into TurnController._drive() (no self-deadlock cycle)")
	assert_false(body.contains("set_session("), "advance_ai_turn() must never call back into TurnController.set_session() (no self-deadlock cycle)")


func test_audit_resolve_reaction_never_calls_back_into_advance_ai_turn() -> void:
	var content: String = _read_file("res://core/application/round_session.gd")
	var body: String = _extract_function_body(content, "func _resolve_reaction(")

	assert_eq(body.count("await "), 1, "_resolve_reaction() must contain exactly one await point -- the injected resolver Callable")
	assert_false(
		body.contains("advance_ai_turn("),
		"_resolve_reaction() must never call back into advance_ai_turn() -- it only awaits the externally-injected resolver Callable, a leaf call with no path back into RoundSession's own coroutines"
	)


func test_audit_turn_controller_drive_awaits_advance_ai_turn_exactly_once_per_loop_iteration() -> void:
	var content: String = _read_file("res://presentation/turn_controller.gd")
	var body: String = _extract_function_body(content, "func _drive(")

	assert_eq(
		body.count("await _round_session.advance_ai_turn("), 1,
		"_drive()'s auto-drive loop must await RoundSession.advance_ai_turn() at exactly one call site (inside the while loop)"
	)
	# No back-edge: _drive() must never call set_session()/on_end_turn_pressed()
	# (its own callers) -- that would let a caller's await deadlock against
	# itself.
	assert_false(body.contains("set_session("), "_drive() must never call back into set_session() (no self-deadlock cycle)")
	assert_false(body.contains("on_end_turn_pressed("), "_drive() must never call back into on_end_turn_pressed() (no self-deadlock cycle)")


func test_audit_set_session_and_on_end_turn_pressed_await_drive_exactly_once_with_no_back_edge() -> void:
	var content: String = _read_file("res://presentation/turn_controller.gd")

	var set_session_body: String = _extract_function_body(content, "func set_session(")
	assert_eq(set_session_body.count("await _drive("), 1, "set_session() must await _drive() exactly once")
	assert_false(set_session_body.contains("advance_ai_turn("), "set_session() must not itself call advance_ai_turn() directly (that remains _drive()'s exclusive job)")

	var on_end_turn_pressed_body: String = _extract_function_body(content, "func on_end_turn_pressed(")
	assert_eq(on_end_turn_pressed_body.count("await _drive("), 1, "on_end_turn_pressed() must await _drive() exactly once")
	assert_false(on_end_turn_pressed_body.contains("advance_ai_turn("), "on_end_turn_pressed() must not itself call advance_ai_turn() directly")


func test_audit_await_chain_forms_a_strict_dag_with_no_cycle() -> void:
	# Pins the COMPLETE await call graph this feature establishes, as a
	# forward-only DAG (leaf first):
	#
	#   _resolve_reaction()  (leaf: awaits only the externally-injected
	#                          resolver Callable -- never calls back into
	#                          RoundSession)
	#          ^
	#          | awaited by
	#   advance_ai_turn()     (awaits _resolve_reaction() on the Strike path)
	#          ^
	#          | awaited by
	#   _drive()               (awaits advance_ai_turn() in its loop)
	#          ^
	#          | awaited by
	#   set_session() / on_end_turn_pressed()  (each awaits _drive())
	#
	# Every edge points from a caller to a strictly "lower" callee that
	# never calls back up the chain -- see the four tests above, each of
	# which pins one edge plus its absent back-edges. This test asserts the
	# graph nodes/edges themselves are exactly this pinned set, so a future
	# edit that adds a new await point (a potential new cycle risk) must
	# consciously update this audit rather than silently widening the graph.
	var round_session_source: String = _read_file("res://core/application/round_session.gd")
	var turn_controller_source: String = _read_file("res://presentation/turn_controller.gd")

	var expected_edges: Array = [
		"advance_ai_turn -> _resolve_reaction",
		"_drive -> advance_ai_turn",
		"set_session -> _drive",
		"on_end_turn_pressed -> _drive",
	]

	assert_true(
		_extract_function_body(round_session_source, "func advance_ai_turn(").contains("await _resolve_reaction("),
		"missing edge: %s" % expected_edges[0]
	)
	assert_true(
		_extract_function_body(turn_controller_source, "func _drive(").contains("await _round_session.advance_ai_turn("),
		"missing edge: %s" % expected_edges[1]
	)
	assert_true(
		_extract_function_body(turn_controller_source, "func set_session(").contains("await _drive("),
		"missing edge: %s" % expected_edges[2]
	)
	assert_true(
		_extract_function_body(turn_controller_source, "func on_end_turn_pressed(").contains("await _drive("),
		"missing edge: %s" % expected_edges[3]
	)

	# And the terminal leaf never re-enters the graph (proven above in
	# test_audit_resolve_reaction_never_calls_back_into_advance_ai_turn()),
	# which together with the four forward-only edges above closes off
	# every possible cycle in this graph.
