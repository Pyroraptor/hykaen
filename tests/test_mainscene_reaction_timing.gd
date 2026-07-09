extends GutTest
## tests/test_mainscene_reaction_timing.gd
##
## GUT suite for FEAT-006 (US-006 / FR-006, Iteration J Part A): a
## boot-real-MainScene test proving the TWO-PHASE reaction window ordering
## FEAT-005 wired into core/application/round_session.gd's
## advance_ai_turn() -- "PreHitAvoidance" (Dodge/Steel, asked BEFORE the
## attack roll) THEN, conditionally, "OnHitMitigation" (Parry/Block, asked
## AFTER the hit result is known) -- actually holds end-to-end through the
## REAL composition root, res://MainScene.tscn, rather than only against a
## hand-built fixture (mirrors tests/gut/test_mainscene_reaction_resolver_wiring.gd's
## own "boot the REAL scene, wire nothing by hand" discipline).
##
## Drives an enemy (Skeleton) Strike against the REAL player combatant
## (Titus) by pressing the real Layer 1 END_TURN verb: Titus free-passes
## (US-002, costs nothing), TurnController auto-drives the Skeleton's turn
## (US-011), and the Skeleton -- starting adjacent to Titus at this
## project's established prologue fixture seed (42; see
## tests/gut/test_end_turn_integration.gd's
## "the enemy starts adjacent and STRIKES" doc, and
## tests/gut/test_round_continuation_and_enemy_budget_display.gd) -- Strikes.
## The REAL scenes/ui/reaction_prompt_ui.gd pop-up (wrapped by the REAL
## presentation/player_reaction_chooser.gd PlayerReactionChooser, per
## MainScene.gd's rewire_session() wiring) is driven directly via its own
## press_option() -- deliberately NOT swapped for
## infrastructure/auto_reaction_chooser.gd's AutoReactionChooser the way
## other headless suites do (e.g. tests/gut/test_end_turn_integration.gd) --
## because this suite's entire point is observing the REAL pop-up's
## open/close timing, exactly as a real player's click would drive it.
##
## Hit/miss is made deterministic WITHOUT touching RNG/seed math or
## core/rules/resolution.gd (this feature's design notes: "Determinism...
## of the RNG seed... is preserved unchanged (no math edits)") by mutating
## the REAL Titus combatant Dictionary's "ac" field directly, immediately
## after boot, before the Skeleton's Strike ever resolves: an absurdly low
## AC guarantees a hit (no roll_total can fail to clear it), an absurdly
## high AC guarantees a miss (no roll_total can ever clear it) --
## resolution.gd's resolve_to_hit() hit check is a plain
## `roll_total >= defense_value` comparison with no natural-1/natural-20
## auto-fail/auto-succeed special case in this ruleset -- so this is a
## fully deterministic, zero-RNG-dependent control lever that never touches
## the pinned resolution math itself.
##
## Verifies (test_criteria):
##   1. Boots the REAL res://MainScene.tscn (not a hand-built fixture) and
##      drives an enemy Strike against Titus via the real END_TURN verb +
##      real TurnController auto-drive + real ReactionWindow/pop-up chain.
##   2. Passed-Dodge + hit scenario: the PreHitAvoidance pop-up fires (opens,
##      offering Dodge), and — once Passed and the Strike is confirmed to
##      hit — the OnHitMitigation pop-up fires (opens, offering Parry/
##      Block) STRICTLY AFTER it, in that order.
##   3. Miss scenario: the OnHitMitigation pop-up never fires (no
##      ReactionWindowOpenedEvent for it, and the pop-up never reopens)
##      once the Strike has missed.
##   4. Dodge-attempted scenario: the OnHitMitigation pop-up never fires once
##      Dodge was chosen on the PreHitAvoidance window (regardless of
##      whether the Dodge itself went on to succeed or fail), and at most
##      one reaction is spent from Titus's own ActionEconomy for the whole
##      Strike (the <=1-reaction-per-Strike budget invariant).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const RoundEventsClass = preload("res://core/rules/round_events.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed: Titus
## (the player) acts first and the Skeleton (the sole enemy) starts adjacent
## to him, so ending Titus's turn immediately drives an in-reach enemy
## Strike (see tests/gut/test_end_turn_integration.gd /
## tests/gut/test_round_continuation_and_enemy_budget_display.gd, which both
## rely on this exact same fixture behavior).
const PROLOGUE_SEED: int = 42

const END_TURN: String = "END_TURN"

## AC_GUARANTEED_HIT / AC_GUARANTEED_MISS — see file-level "Hit/miss is made
## deterministic" doc above.
const AC_GUARANTEED_HIT: int = -100
const AC_GUARANTEED_MISS: int = 9999


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=PROLOGUE_SEED so every scenario
## below can rely on a deterministic Titus-acts-first / Skeleton-adjacent
## layout (test_criteria #1: "boots real MainScene.tscn, not a hand-built
## fixture" — mirrors tests/gut/test_mainscene_reaction_resolver_wiring.gd's
## identically-named helper).
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


## _press_end_turn_and_drive_enemy_strike(instance) -> void — presses the
## REAL Layer 1 END_TURN verb (Titus free-passes, US-002), which drives
## TurnController's auto-drive loop (US-011) straight into the Skeleton's
## turn. The Skeleton Strikes Titus at this fixture's seed/positions —
## RoundSession.advance_ai_turn()'s coroutine chain genuinely suspends the
## instant it reaches the first actually-opened reaction window (a real
## Signal await on reaction_prompt_ui.reaction_chosen — see
## presentation/player_reaction_chooser.gd's file-level doc), so this call
## returns to the caller either the moment the pop-up opens, or once the
## Strike has fully concluded with no window ever offered.
func _press_end_turn_and_drive_enemy_strike(instance) -> void:
	assert_false(
		instance.round_session.current_actor().get("_is_enemy", true),
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)
	instance.verb_bar_view.press(END_TURN)


## _reaction_window_opened_events(instance, trigger_type) -> Array — every
## RoundEvents.ReactionWindowOpenedEvent the REAL event_sink has recorded so
## far for the given trigger_type, in emission order — read straight off
## MainScene's own ConsoleEventSinkAdapter.log (ADR-003's single
## observability surface), never a second/parallel event capture.
func _reaction_window_opened_events(instance, trigger_type: String) -> Array:
	var matches: Array = []
	for event in instance.event_sink.log:
		if event is RoundEventsClass.ReactionWindowOpenedEvent and event.trigger_type == trigger_type:
			matches.append(event)
	return matches


## _event_index(instance, event) -> int — the position of `event` (identity
## match) within the real event_sink's log, so window-ordering assertions
## compare actual emission order rather than re-deriving it.
func _event_index(instance, event) -> int:
	for i in range(instance.event_sink.log.size()):
		if instance.event_sink.log[i] == event:
			return i
	return -1


## _titus_action_budget_remaining(instance) -> int — Titus's own live
## ActionEconomy.get_remaining(), read via RoundSession's own
## action_budget_snapshot() (never a second/independent derivation of the
## budget).
func _titus_action_budget_remaining(instance) -> int:
	var titus: Dictionary = instance._party[0]
	var titus_id: String = titus.get("combatant_id", titus.get("name", ""))
	for row in instance.round_session.action_budget_snapshot():
		if row["combatant_id"] == titus_id:
			return row["remaining"]
	return -1


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — Passed-Dodge + hit: PreHitAvoidance fires, THEN (once Passed
# and the Strike hits) OnHitMitigation fires, strictly in that order.
# ══════════════════════════════════════════════════════════════════════════

func test_passed_dodge_then_hit_opens_prehit_then_onhit_in_order() -> void:
	var instance = _boot_main_scene()
	instance._party[0]["ac"] = AC_GUARANTEED_HIT

	_press_end_turn_and_drive_enemy_strike(instance)

	assert_true(
		instance.reaction_prompt_ui.is_open(),
		"the REAL PreHitAvoidance pop-up must fire (open) for Titus's incoming Strike"
	)
	assert_eq(
		instance.reaction_prompt_ui.get_displayed_options(), ["dodge", "none"],
		"PreHitAvoidance must offer exactly Dodge + Pass for this fixture (an 'ac' Strike never legalizes Steel)"
	)

	var prehit_events: Array = _reaction_window_opened_events(instance, "PreHitAvoidance")
	assert_eq(prehit_events.size(), 1, "exactly one PreHitAvoidance window must have opened so far")

	# "Passed-Dodge": the player declines the pre-hit window.
	instance.reaction_prompt_ui.press_option("none")

	assert_true(
		instance.reaction_prompt_ui.is_open(),
		"the REAL OnHitMitigation pop-up must fire (open) once the Strike is confirmed to hit"
	)
	var onhit_options: Array = instance.reaction_prompt_ui.get_displayed_options()
	assert_true(onhit_options.has("parry"), "OnHitMitigation must offer Parry for Titus's real longsword (parry_bonus > 0)")
	assert_true(onhit_options.has("block"), "OnHitMitigation must offer Block for Titus's real longsword (block_value > 0)")
	assert_true(onhit_options.has("none"), "Pass must always remain an offered option")

	var onhit_events: Array = _reaction_window_opened_events(instance, "OnHitMitigation")
	assert_eq(onhit_events.size(), 1, "exactly one OnHitMitigation window must have opened so far")

	assert_true(
		_event_index(instance, prehit_events[0]) < _event_index(instance, onhit_events[0]),
		"PreHitAvoidance must open STRICTLY BEFORE OnHitMitigation -- the correct reaction-timing order this feature verifies"
	)

	# Close out the scenario cleanly (Pass again) so the driven coroutine
	# settles rather than leaving a dangling suspended await.
	instance.reaction_prompt_ui.press_option("none")
	assert_false(
		instance.reaction_prompt_ui.is_open(),
		"no further reaction window may remain open once this Strike's OnHitMitigation choice has resolved"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — Miss: OnHitMitigation never fires.
# ══════════════════════════════════════════════════════════════════════════

func test_miss_never_opens_onhit_mitigation() -> void:
	var instance = _boot_main_scene()
	instance._party[0]["ac"] = AC_GUARANTEED_MISS

	_press_end_turn_and_drive_enemy_strike(instance)

	assert_true(
		instance.reaction_prompt_ui.is_open(),
		"the REAL PreHitAvoidance pop-up must still fire for the incoming Strike, regardless of its eventual hit/miss outcome"
	)

	instance.reaction_prompt_ui.press_option("none")

	assert_false(
		instance.reaction_prompt_ui.is_open(),
		"the OnHitMitigation pop-up must NEVER fire once the Strike has missed"
	)
	assert_eq(
		_reaction_window_opened_events(instance, "OnHitMitigation").size(), 0,
		"no OnHitMitigation ReactionWindowOpenedEvent may ever be emitted for a missed Strike"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — Dodge attempted: OnHitMitigation never fires, and at most
# one reaction is spent for the whole Strike.
# ══════════════════════════════════════════════════════════════════════════

func test_dodge_attempted_skips_onhit_mitigation_and_spends_at_most_one_reaction() -> void:
	var instance = _boot_main_scene()
	# AC is irrelevant once Dodge substitutes the Mobility check for it
	# (resolution.gd's resolve_to_hit() doc) -- pinned to the guaranteed-hit
	# value purely so this scenario is not accidentally coupled to the
	# guaranteed-miss one above.
	instance._party[0]["ac"] = AC_GUARANTEED_HIT

	var budget_before: int = _titus_action_budget_remaining(instance)

	_press_end_turn_and_drive_enemy_strike(instance)

	assert_true(
		instance.reaction_prompt_ui.is_open(),
		"the REAL PreHitAvoidance pop-up must fire for the incoming Strike"
	)

	# The player attempts Dodge.
	instance.reaction_prompt_ui.press_option("dodge")

	assert_false(
		instance.reaction_prompt_ui.is_open(),
		"the OnHitMitigation pop-up must NEVER fire once Dodge was already attempted this Strike -- the <=1-reaction-per-Strike budget forbids a second window, regardless of whether the Dodge itself went on to succeed or fail"
	)
	assert_eq(
		_reaction_window_opened_events(instance, "OnHitMitigation").size(), 0,
		"no OnHitMitigation ReactionWindowOpenedEvent may ever be emitted once a pre-hit reaction was chosen"
	)

	var budget_after: int = _titus_action_budget_remaining(instance)
	assert_true(
		budget_before - budget_after <= 1,
		"at most one reaction may be spent from Titus's own ActionEconomy for this ENTIRE Strike (<=1-reaction-per-Strike invariant)"
	)
	assert_eq(
		instance.round_session.get_reaction_budget_violations(), [],
		"the shared budget-delta gate must record zero violations for this Strike"
	)
