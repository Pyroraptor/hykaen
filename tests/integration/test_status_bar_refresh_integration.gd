extends GutTest
## tests/integration/test_status_bar_refresh_integration.gd — FEAT-165
## (US-011 / FR-015, ADR-003).
##
## Integration-test complement to tests/business_logic/
## test_action_budget_projection.gd's criterion-1b MainScene boot check:
## this suite is its own dedicated, self-contained integration test proving
## the status-bar action-budget refresh works end-to-end through the REAL
## res://MainScene.tscn composition root with NO mocked/stubbed
## ActionResolutionPort (core/application/resolve_action_use_case.gd) --
## a genuine Strike is resolved through the exact call path a real player
## drives ($VerbBarView.press("STRIKE") -> `_verb_registry`.enter_selection()/
## execute() -> resolve_action_use_case.resolve(), the codebase's
## "resolve_strike()" call path per the design notes' API contract #5), and
## this suite asserts presentation/status_panel_view.gd's projected
## action_budget_remaining/Spent values track the domain core/rules/
## action_economy.gd ActionEconomy instance exactly.
##
## FEAT-181 (DEF-001 / FR-009/NFR-003): FEAT-006 (US-006) later removed the
## legacy presentation/strike_action_control.gd/.tscn control entirely --
## Strike is now driven SOLELY through the Layer 1 verb bar
## (presentation/verb_bar_view.gd) -> `_verb_registry`'s STRIKE entry (see
## MainScene.gd's file-level FEAT-006 doc). This suite is retargeted onto
## that real two-layer flow instead of the deleted control, preserving its
## original Iteration D status-bar-decrement regression intent unchanged.
##
## test_criteria satisfied:
##   1. test_real_main_scene_boots_headlessly_and_resolves_a_strike_through_the_real_resolve_action_use_case()
##   2. test_status_panel_view_action_budget_remaining_decreases_by_exactly_one_for_the_acting_combatant()
##   3. test_status_panel_view_spent_value_matches_the_domain_action_economys_spent_value()
##   4. (whole-suite regression) -- enforced by scripts/test_command.sh, not this file.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const VerbBarViewClass          = preload("res://presentation/verb_bar_view.gd")
const StatusPanelViewClass      = preload("res://presentation/status_panel_view.gd")


## _boot_main_scene_with_seed(seed_value) -- boots the REAL,
## res://MainScene.tscn composition root headless, pinned to a deterministic
## seed (mirroring the established convention in tests/integration/
## test_movement_affordance_integration.gd and tests/business_logic/
## test_action_budget_projection.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — the REAL MainScene.tscn boots headlessly, wiring the REAL
# (not mocked/stubbed) ActionResolutionPort (resolve_action_use_case), and a
# Strike is resolved through the REAL call path a player drives:
# $VerbBarView.press("STRIKE") -> `_verb_registry`.enter_selection()/
# execute() -> resolve_action_use_case.resolve().
# ══════════════════════════════════════════════════════════════════════════

func test_real_main_scene_boots_headlessly_and_resolves_a_strike_through_the_real_resolve_action_use_case() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_not_null(instance.round_session, "MainScene must obtain a real RoundSession via RunRoundUseCase.begin_round()")
	assert_true(
		is_instance_of(instance.resolve_action_use_case, ResolveActionUseCaseClass),
		"MainScene must wire the REAL core/application/resolve_action_use_case.gd ActionResolutionPort -- no mocked/stubbed use case"
	)
	assert_true(
		is_instance_of(instance.verb_bar_view, VerbBarViewClass),
		"MainScene must wire the REAL presentation/verb_bar_view.gd VerbBarView -- no stub/mock"
	)
	assert_true(
		is_instance_of(instance.status_panel_view, StatusPanelViewClass),
		"MainScene must wire the REAL presentation/status_panel_view.gd StatusPanelView -- no stub/mock"
	)

	assert_true(instance._verb_registry.is_available("STRIKE"), "fixture assumption: the prologue's first actor has at least one in-reach target at seed=42")
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the prologue's first actor has at least one in-reach target at seed=42")

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(
		result.get("resolved", false),
		"the Strike must resolve through the REAL resolve_action_use_case.resolve() call path (no mocked ActionResolutionPort)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — StatusPanelView.action_budget_remaining for the acting
# combatant decreases by EXACTLY 1 after the real Strike above resolves.
# ══════════════════════════════════════════════════════════════════════════

func test_status_panel_view_action_budget_remaining_decreases_by_exactly_one_for_the_acting_combatant() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_true(before_remaining > 0, "sanity check: the acting combatant starts with a positive action budget")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the active actor has at least one in-reach target")

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(result.get("resolved", false), "fixture assumption: the real Strike must resolve")

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(
		after_remaining, before_remaining - 1,
		"StatusPanelView.action_budget_remaining for the acting combatant must decrease by EXACTLY 1 after the real Strike resolves"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the displayed Spent value tracks the domain ActionEconomy's
# is_spent() value exactly after a real Strike resolves. Exercised at two
# points: (a) immediately after the one real Strike this suite drives
# through the actual encounter's single living enemy (prologue_encounter.tres
# fields exactly one Skeleton, so this suite must not assume repeated
# Strikes against it stay resolvable once it is defeated -- see (b) below for
# how the "budget fully spent" state is reached deterministically instead),
# and (b) once the SAME actor's domain ActionEconomy independently reports
# is_spent() (driven directly, since the real encounter offers only one
# living target and defeating it makes further real Strikes correctly
# rejected by resolve_action_use_case's ERR_TARGET_INVALID precondition --
# this suite must not fight that real domain invariant to reach the
# fully-spent state).
# ══════════════════════════════════════════════════════════════════════════

func test_status_panel_view_spent_value_matches_the_domain_action_economys_spent_value() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the active actor carries a non-empty combatant_id")

	# The SAME live ActionEconomy instance MainScene wires into
	# strike_action_control/movement_input_controller for the current actor
	# (core/application/round_session.gd's current_action_economy()) -- the
	# domain source of truth this suite cross-checks the projected Spent
	# value against, never a second, independently-derived economy.
	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor has a live domain ActionEconomy")

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the active actor has at least one in-reach target")
	var target_id: String = target_ids[0]

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_id)
	assert_true(result.get("resolved", false), "fixture assumption: the real Strike must resolve")

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must match the domain ActionEconomy.is_spent() value after one real Strike"
	)

	# Reach the "budget fully spent" domain state directly on the SAME
	# ActionEconomy instance -- not via further real Strikes against the
	# encounter's one living enemy, which a prior Strike may already have
	# defeated -- then push the SAME actor_updated_action_budget-shaped
	# snapshot MainScene's real event-forwarding path (ConsoleEventSinkAdapter
	# -> StatusPanelView.on_attack_event() -> update_action_budget(), see
	# status_panel_view.gd) would push, proving the projection (not a second
	# recomputation) is what the panel displays.
	# FEAT-003 (ADR-103): spend_action() now permits only one success per
	# turn, so draining the remaining budget must simulate a fresh turn
	# boundary (start_of_turn()) before each further spend -- exactly the
	# AC-4 interleaved-turns model the shared per-round budget already
	# documents, not a same-turn double-spend.
	while not action_economy.is_spent():
		action_economy.start_of_turn()
		action_economy.spend_action({"name": "Strike", "traits": []})
	assert_true(action_economy.is_spent(), "sanity check: the domain ActionEconomy must report is_spent() once its budget reaches 0")

	instance.status_panel_view.update_action_budget(actor_id, {
		"actor_updated_action_budget": {
			"remaining": action_economy.get_remaining(),
			"spent": action_economy.is_spent(),
		}
	})

	assert_eq(
		instance.status_panel_view.get_status(actor_id).get("spent"), action_economy.is_spent(),
		"StatusPanelView's displayed Spent value must match the domain ActionEconomy.is_spent() value once the budget is exhausted"
	)
	assert_true(
		instance.status_panel_view.get_status(actor_id).get("spent"),
		"StatusPanelView must display Spent=true once the domain ActionEconomy reports is_spent()"
	)
