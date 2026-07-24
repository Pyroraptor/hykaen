extends GutTest
## tests/gut/test_seam_composition_root_wiring.gd — FEAT-218 (US-001 / US-004
## / US-009; closes PR-001/G2): an explicit identity/regression check that
## the hex-choice (FEAT-001), token-reposition (`_token_reposition_fn`), and
## combat-log Callables a booted `round_session` actually holds are the
## EXACT SAME production objects/methods MainScene.gd's composition root
## (`rewire_session()` / `_ready()`) binds — never a second, parallel,
## test-local seam double left wired after boot.
##
## Peer review (the change-deployment gate) flagged that the R-2/R-3/G6
## boot-real-MainScene suites (tests/gut/test_e2e_dodge_step_capstone.gd,
## tests/integration/test_mainscene_r1_e2e.gd) proved these seams are
## INVOKED and OBSERVABLE (the token relocates, the log row renders) but
## never asserted the underlying Callables/objects driving those effects are
## themselves the composition root's own production bindings rather than
## some other object that merely behaves the same way. This suite closes
## that specific gap: every assertion below inspects `Callable.get_object()`
## / `Callable.get_method()` (or direct field identity) against the REAL,
## booted `res://MainScene.tscn` instance's own live child nodes — it never
## constructs a resolver/adapter of its own and never substitutes one before
## asserting (that would be exactly the "self-wired seam double" this
## feature exists to rule out).
##
## Verifies (test_criteria):
##   1. `round_session._token_reposition_fn.get_object()` is the SAME
##      `hex_grid_view` instance actually attached to the booted real
##      MainScene tree (and bound to the real `move_token` method).
##   2. The hex-choice seam bound on the running scene
##      (`round_session._hex_choice_resolver_fn`) is the SAME
##      object/method FEAT-001's original caller uses
##      (`Callable(main_scene, "resolve_hex_choice")`), which itself
##      forwards, without a second/parallel instance, to the ONE
##      `hex_choice_resolver` (`_UIHexChoiceResolver`) constructed in
##      `_ready()` and wrapped around the SAME live `hex_grid_view`.
##   3. The combat-log Callables (`_event_log_record_attack_fn`,
##      `_event_log_render_attack_entry_fn`, `_event_log_record_reaction_fn`)
##      are all bound to the SAME live `event_log_view` instance's real
##      `record_attack`/`render_attack_entry`/`record_reaction` methods.
##   4. These identities survive a round-continuation re-wire
##      (`rewire_session()` called a second time) — proving the composition
##      root never silently swaps in a second, parallel seam instance across
##      round boundaries either.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root (this codebase's established convention; mirrors
## tests/gut/test_e2e_dodge_step_capstone.gd's own `_boot_main_scene()`),
## pinning seed_override=42 for a deterministic boot. This suite NEVER
## constructs/injects a resolver, Callable, or adapter of its own — it only
## inspects what booting the real scene already wired.
## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with round_session/verb_bar_view/
## selection_overlay/turn_controller signal wiring gated behind a real
## _on_combat_triggered() handoff (see MainScene.gd's own FEAT-316 doc). This
## suite inspects round_session's own seam Callables directly, so this helper
## now also drives the SAME real handoff tests/boot/
## test_exploration_to_combat_handoff_trigger.gd exercises directly, landing
## the instance in GameMode.COMBAT with a live round_session before returning
## -- still never constructing/injecting a resolver, Callable, or adapter of
## its own.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — token-reposition seam: round_session._token_reposition_fn is
# bound to the EXACT hex_grid_view instance attached to the booted real
# MainScene tree, via its real move_token() method.
# ══════════════════════════════════════════════════════════════════════════

func test_token_reposition_fn_is_bound_to_the_real_booted_hex_grid_view_move_token() -> void:
	var instance = await _boot_main_scene()

	assert_not_null(instance.round_session, "MainScene must boot with a live round_session")
	assert_not_null(instance.hex_grid_view, "MainScene must boot with a live hex_grid_view")
	assert_true(instance.hex_grid_view.is_inside_tree(), "hex_grid_view must actually be attached to the booted scene tree, not a detached stand-in")

	var reposition_fn: Callable = instance.round_session._token_reposition_fn
	assert_true(reposition_fn.is_valid(), "round_session._token_reposition_fn must be bound after boot (never left unwired for real play)")

	assert_same(
		reposition_fn.get_object(), instance.hex_grid_view,
		"round_session._token_reposition_fn must be bound to the EXACT hex_grid_view instance attached to the booted real MainScene tree -- never a second, test-local HexGridView/double"
	)
	assert_eq(
		reposition_fn.get_method(), StringName("move_token"),
		"round_session._token_reposition_fn must be bound to hex_grid_view's real move_token() method -- never a substitute method of the same name on a different object"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — hex-choice seam: the resolver bound in the running scene is
# the SAME object/method FEAT-001's original callers use (no second,
# parallel seam instance).
# ══════════════════════════════════════════════════════════════════════════

func test_hex_choice_resolver_fn_is_bound_to_the_real_mainscene_resolve_hex_choice() -> void:
	var instance = await _boot_main_scene()

	var hex_choice_fn: Callable = instance.round_session._hex_choice_resolver_fn
	assert_true(hex_choice_fn.is_valid(), "round_session._hex_choice_resolver_fn must be bound after boot")

	assert_same(
		hex_choice_fn.get_object(), instance,
		"round_session._hex_choice_resolver_fn must be bound to the booted MainScene instance itself -- the SAME object FEAT-001's own resolve_hex_choice() call path uses"
	)
	assert_eq(
		hex_choice_fn.get_method(), StringName("resolve_hex_choice"),
		"round_session._hex_choice_resolver_fn must be bound to MainScene's real resolve_hex_choice() method -- the ONE call path through which the composition root's hex_choice_resolver is ever invoked (per resolve_hex_choice()'s own doc)"
	)


func test_step_hex_query_fn_is_bound_to_the_real_mainscene_query_selectable_step_hexes() -> void:
	var instance = await _boot_main_scene()

	var step_hex_query_fn: Callable = instance.round_session._step_hex_query_fn
	assert_true(step_hex_query_fn.is_valid(), "round_session._step_hex_query_fn must be bound after boot")

	assert_same(
		step_hex_query_fn.get_object(), instance,
		"round_session._step_hex_query_fn must be bound to the booted MainScene instance itself -- never a second, parallel query implementation"
	)
	assert_eq(
		step_hex_query_fn.get_method(), StringName("_query_selectable_step_hexes"),
		"round_session._step_hex_query_fn must be bound to MainScene's real _query_selectable_step_hexes() method"
	)


func test_mainscene_hex_choice_resolver_field_wraps_the_same_live_hex_grid_view_no_second_instance() -> void:
	# FEAT-001's own default resolver (`_UIHexChoiceResolver`, constructed
	# EXACTLY once in _ready()) must wrap the SAME live hex_grid_view this
	# suite already proved the token-reposition seam is bound to above --
	# never a second `_UIHexChoiceResolver`/HexGridView pair constructed
	# anywhere else.
	var instance = await _boot_main_scene()

	assert_not_null(instance.hex_choice_resolver, "MainScene must wire a default hex_choice_resolver during initialization")
	assert_same(
		instance.hex_choice_resolver._hex_grid_view, instance.hex_grid_view,
		"the production hex_choice_resolver (_UIHexChoiceResolver) must wrap the EXACT SAME live hex_grid_view instance attached to the booted tree -- no second, parallel resolver/view pair"
	)

	# resolve_hex_choice() -- the ONE call path round_session's
	# _hex_choice_resolver_fn is bound to (criterion 2 above) -- must itself
	# forward to this SAME hex_choice_resolver instance, not re-derive/
	# reconstruct one of its own.
	var resolver_before_call = instance.hex_choice_resolver
	var empty_result = await instance.resolve_hex_choice([])
	assert_null(empty_result, "resolve_hex_choice() with no legal hexes must resolve to null (contract sanity, not a re-derived resolution)")
	assert_same(
		instance.hex_choice_resolver, resolver_before_call,
		"resolve_hex_choice() must never replace/reconstruct hex_choice_resolver -- it is the ONE seam instance for the lifetime of this composition root"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — combat-log ports: round_session's structured-log Callables
# are bound to the SAME live event_log_view instance's real methods.
# ══════════════════════════════════════════════════════════════════════════

func test_combat_log_callables_are_bound_to_the_real_booted_event_log_view() -> void:
	var instance = await _boot_main_scene()

	assert_not_null(instance.event_log_view, "MainScene must boot with a live event_log_view")
	assert_true(instance.event_log_view.is_inside_tree(), "event_log_view must actually be attached to the booted scene tree, not a detached stand-in")

	var record_attack_fn: Callable = instance.round_session._event_log_record_attack_fn
	var render_attack_entry_fn: Callable = instance.round_session._event_log_render_attack_entry_fn
	var record_reaction_fn: Callable = instance.round_session._event_log_record_reaction_fn
	var entry_count_fn: Callable = instance.round_session._event_log_entry_count_fn
	var overwrite_entry_fn: Callable = instance.round_session._event_log_overwrite_entry_fn

	for fn in [record_attack_fn, render_attack_entry_fn, record_reaction_fn, entry_count_fn, overwrite_entry_fn]:
		assert_true(fn.is_valid(), "every combat-log Callable must be bound after boot (never left unwired for real play)")
		assert_same(
			fn.get_object(), instance.event_log_view,
			"every combat-log Callable must be bound to the EXACT event_log_view instance attached to the booted real MainScene tree -- never a second, test-local EventLogView/double"
		)

	assert_eq(record_attack_fn.get_method(), StringName("record_attack"), "the record-attack seam must be bound to event_log_view's real record_attack() method")
	assert_eq(render_attack_entry_fn.get_method(), StringName("render_attack_entry"), "the render-attack-entry seam must be bound to event_log_view's real render_attack_entry() method")
	assert_eq(record_reaction_fn.get_method(), StringName("record_reaction"), "the record-reaction seam must be bound to event_log_view's real record_reaction() method")
	assert_eq(entry_count_fn.get_method(), StringName("get_entry_count"), "the entry-count seam must be bound to event_log_view's real get_entry_count() method")
	assert_eq(overwrite_entry_fn.get_method(), StringName("overwrite_entry_as_rich"), "the overwrite-entry seam must be bound to event_log_view's real overwrite_entry_as_rich() method")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — these identities survive a round-continuation re-wire
# (rewire_session() invoked a second time), proving no second, parallel
# seam instance is silently substituted across round boundaries.
# ══════════════════════════════════════════════════════════════════════════

func test_seam_identities_are_unchanged_across_a_round_continuation_rewire() -> void:
	var instance = await _boot_main_scene()

	var hex_grid_view_before = instance.round_session._token_reposition_fn.get_object()
	var event_log_view_before = instance.round_session._event_log_record_attack_fn.get_object()
	var hex_choice_object_before = instance.round_session._hex_choice_resolver_fn.get_object()
	var hex_choice_resolver_instance_before = instance.hex_choice_resolver

	# The SAME re-wiring hook MainScene.gd's own round-continuation path
	# (_on_round_over()) invokes -- never a second, test-authored wiring
	# routine.
	instance.rewire_session()

	assert_same(
		instance.round_session._token_reposition_fn.get_object(), hex_grid_view_before,
		"the token-reposition seam must still be bound to the SAME hex_grid_view instance after a round-continuation rewire -- never swapped for a second instance"
	)
	assert_same(
		instance.round_session._event_log_record_attack_fn.get_object(), event_log_view_before,
		"the combat-log seam must still be bound to the SAME event_log_view instance after a round-continuation rewire"
	)
	assert_same(
		instance.round_session._hex_choice_resolver_fn.get_object(), hex_choice_object_before,
		"the hex-choice seam must still be bound to the SAME object after a round-continuation rewire"
	)
	assert_same(
		instance.hex_choice_resolver, hex_choice_resolver_instance_before,
		"MainScene's own hex_choice_resolver field (constructed exactly once in _ready()) must never be reconstructed by rewire_session() -- the SAME _UIHexChoiceResolver instance for the composition root's whole lifetime"
	)
