extends GutTest
## tests/integration/test_opportunistic_strike_ranged_reactor_excluded.gd —
## FEAT-232 (US-007, resolves DEF-005).
##
## DEF-005 named a second coverage gap alongside the assertion bug this
## feature's sibling fix (tests/gut/test_turn_controller_opportunistic_strike_
## reaction.gd) corrects: core/domain/opportunistic_strike_eligibility.gd's
## OpportunisticStrikeEligibility.eligible() has an isolated, pure-domain unit
## test (tests/unit/core/domain/test_opportunistic_strike_eligibility.gd)
## pinning its melee-reach predicate, but NO boot-real/integration test ever
## drove the REAL, fully-wired Stride path (core/application/use_cases/
## resolve_stride_use_case.gd's ResolveStrideUseCase, invoked through
## MainScene.gd's real composition-root seam) with a RANGED reactor standing
## adjacent to a mover to confirm the melee-only filter genuinely reaches
## live play — exactly the "green tests, dead in play" risk this project's
## guardrails (G2) exist to catch: a regression that broke the wiring
## between ResolveStrideUseCase and OpportunisticStrikeEligibility (e.g. a
## call site that stopped forwarding the reactor's weapon, or a mismatched
## key name) would sail through the existing pure-domain/unit suites
## untouched.
##
## This suite closes that gap with ONE dedicated boot-real MainScene test,
## mirroring tests/e2e/test_reactions_fully_live.gd's established
## conventions exactly: boots the REAL res://MainScene.tscn composition
## root (G2 — never a hand-wired double), then drives the SAME real,
## composition-root-bound seam that test's own "LEG B" drives —
## `instance._resolve_enemy_stride_opportunistic_window(mover,
## mover_start_hex, candidate_reactors)`, the EXACT unmodified Callable
## MainScene.gd binds onto `ai_decision_port.set_stride_reaction_resolver_fn()`
## and core/combat/ai.gd's `_stride_toward_target()` awaits immediately
## BEFORE its own Movement.stride() commit — with Titus (the candidate
## reactor, adjacent to the Skeleton at the PROLOGUE_SEED fixture's start
## position) given a RANGED weapon (a "range_hexes" key added to his real
## weapon Dictionary, the SAME field core/combat/ai.gd's/core/application/
## resolve_action_use_case.gd's own _is_ranged_weapon() helpers and
## OpportunisticStrikeEligibility._has_melee_reach() all consult) rather
## than a hand-built fixture Dictionary of this test's own.
##
## Verifies (test_criteria):
##   test_ranged_reactor_adjacent_to_mover_is_never_offered_opportunistic_strike_window
##   passes: a ranged reactor standing adjacent to the mover at the START of
##   its Stride is never offered an OpportunisticStrike window at all — no
##   reaction is recorded, no ReactionWindowOpenedEvent is ever emitted for
##   it, no pop-up ever opens, and its own live ActionEconomy budget is left
##   completely untouched.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed:
## Titus acts first and the sole enemy (Skeleton) starts adjacent to him
## (mirrors tests/e2e/test_reactions_fully_live.gd's / tests/integration/
## test_mainscene_hit_reaction_apply.gd's identically-named/valued constant).
const PROLOGUE_SEED: int = 42

## RANGED_WEAPON_RANGE_HEXES — an arbitrary positive range; only the KEY's
## presence matters to _is_ranged_weapon()/_has_melee_reach(), never this
## value.
const RANGED_WEAPON_RANGE_HEXES: int = 6


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _id(combatant: Dictionary) -> String:
	return combatant.get("combatant_id", combatant.get("name", ""))


## _make_ranged(combatant) -> void — stamps the SAME "range_hexes" key
## core/combat/ai.gd's _is_ranged_weapon() / core/application/
## resolve_action_use_case.gd's _is_ranged_weapon() / core/domain/
## opportunistic_strike_eligibility.gd's _has_melee_reach() all consult onto
## `combatant`'s own real, live weapon Dictionary — never a fabricated
## fixture weapon of this test's own.
func _make_ranged(combatant: Dictionary) -> void:
	combatant["weapon"]["range_hexes"] = RANGED_WEAPON_RANGE_HEXES


## _reaction_window_opened_events_for(instance, reactor_name) -> Array —
## every REAL ReactionWindowOpenedEvent (core/rules/round_events.gd) emitted
## so far whose reactor_name matches `reactor_name`, read straight off the
## real, live-booted event_sink's own log (never a re-derived/recomputed
## trace of this test's own) -- so this suite can assert, directly against
## production observability output, that zero such events exist for the
## ranged reactor.
func _reaction_window_opened_events_for(instance, reactor_name: String) -> Array:
	var matches: Array = []
	for event in instance.event_sink.log:
		if event is RoundEventsClass.ReactionWindowOpenedEvent and event.reactor_name == reactor_name:
			matches.append(event)
	return matches


# ══════════════════════════════════════════════════════════════════════════
# The criterion: a ranged reactor adjacent to a mover is NEVER offered an
# OpportunisticStrike window — driven through the real, composition-root-
# bound Stride seam, never a hand-wired double.
# ══════════════════════════════════════════════════════════════════════════

func test_ranged_reactor_adjacent_to_mover_is_never_offered_opportunistic_strike_window() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton: Dictionary = instance._enemies[0]
	var titus: Dictionary = instance._party[0]
	var titus_id: String = _id(titus)

	assert_true(
		titus.has("weapon") and not titus["weapon"].has("range_hexes"),
		"fixture assumption: Titus starts with a genuine MELEE weapon (no 'range_hexes' key) before this test forces him ranged"
	)
	_make_ranged(titus)

	var titus_ae = instance._action_economy_for(titus)
	assert_not_null(titus_ae, "fixture assumption: Titus must have a live ActionEconomy wired at boot")
	var titus_budget_before: int = titus_ae.get_remaining()

	var mover_start_hex = skeleton.get("hex_coord", null)
	assert_not_null(mover_start_hex, "fixture assumption: the Skeleton carries a hex_coord before its Stride")

	assert_false(instance.reaction_prompt_ui.is_open(), "fixture assumption: no reaction pop-up is open before this Stride is driven")

	var stride_reaction_result: Dictionary = await instance._resolve_enemy_stride_opportunistic_window(
		skeleton, mover_start_hex, [titus]
	)

	# The criterion itself: a ranged reactor is filtered out BEFORE
	# reactor_resolver_fn is ever consulted (core/application/use_cases/
	# resolve_stride_use_case.gd's execute() enforces melee-only eligibility
	# strictly before asking any chooser for a decision) -- so no reaction
	# is ever recorded for Titus.
	var reactions: Array = stride_reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 0, "a ranged reactor adjacent to the mover must never have a reaction recorded -- no OpportunisticStrike window may ever be offered to it")

	assert_false(stride_reaction_result.get("mover_downed", true), "no reactor was ever offered a window, so the mover can never have been downed")
	assert_true(stride_reaction_result.get("stride_should_commit", false), "with no reaction offered at all, the Stride must remain free to commit")

	# No REAL pop-up must ever have opened for the ranged reactor -- proven
	# directly against the live, booted reaction_prompt_ui, not merely
	# inferred from the returned Dictionary.
	assert_false(instance.reaction_prompt_ui.is_open(), "no real OpportunisticStrike pop-up may ever open for a ranged reactor")

	# No ReactionWindowOpenedEvent may ever have been emitted for Titus --
	# proven directly against the real, live event_sink's own log.
	var opened_events_for_titus: Array = _reaction_window_opened_events_for(instance, titus.get("name", ""))
	assert_eq(opened_events_for_titus.size(), 0, "no ReactionWindowOpenedEvent may ever be emitted for a ranged reactor filtered out before a window is opened")

	# Titus's own live ActionEconomy budget must be left completely
	# untouched -- no reaction was ever offered, so none could have been
	# spent.
	assert_eq(
		titus_ae.get_remaining(), titus_budget_before,
		"a ranged reactor's own live ActionEconomy budget must be completely untouched -- it was never offered an OpportunisticStrike window to spend a reaction on"
	)
