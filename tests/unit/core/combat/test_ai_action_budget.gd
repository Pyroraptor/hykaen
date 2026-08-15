extends GutTest
## tests/unit/core/combat/test_ai_action_budget.gd
##
## GUT unit test suite for FEAT-006 (US-006 / FR-010, ADR-002): Enemy AI
## respects the SAME per-turn Movement-trait lockout and per-round
## ActionEconomy budget a player-driven Step/Stride/Strike is already gated
## by (core/rules/action_economy.gd) -- decide_action() must never issue a
## second Stride within a turn (no move-then-move) and must never exceed its
## per-turn/per-round action budget, whether driven directly or through
## core/application/round_session.gd's RoundSession.advance_ai_turn()
## orchestration.
##
## This suite deliberately does NOT re-test FEAT-003/FEAT-004/FEAT-005's
## reach/target-selection/Stride-closing/Stride-then-Strike criteria --
## those remain covered by tests/unit/core/combat/test_ai_reach_strike.gd,
## tests/unit/core/combat/test_ai_target_selection.gd, and
## tests/unit/core/combat/test_ai_stride_then_strike.gd.
##
## Verifies (test_criteria):
##   1. Enemy cannot issue two Strides in one turn (no move-then-move).
##   2. Enemy never exceeds its per-turn action budget across multiple
##      simulated turns.
##   3. AI decision executes through the existing AIDecisionPort contract
##      (core/application/round_session.gd's RoundSession.advance_ai_turn())
##      with no new port/use-case class present in core/application/.

const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


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


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _melee_combatant(hex_coord):
	return CombatantClass.from_dict({
		"name":        "Skeleton",
		"hp_current":  8,
		"ac":          12,
		"strength":    2,
		"hex_coord":   hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	})


func _target(name: String, hex_coord, hp: int = 18):
	return CombatantClass.from_dict({"name": name, "hp_current": hp, "ac": 14, "strength": 5, "hex_coord": hex_coord})


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase plus its fake ports, exactly
## mirroring test_round_session_ai_turn.gd's rig, so this suite exercises
## RoundSession.advance_ai_turn() through the REAL AIDecisionPort
## (core/combat/ai.gd), never a stand-in for RoundSession itself.
func _make_use_case(entries: Array, random_number_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var event_sink_port    = FakeEventSinkPort.new()
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: Enemy cannot issue two Strides in one turn (no move-then-move).
# ══════════════════════════════════════════════════════════════════════════

func test_ai_never_issues_a_second_stride_within_the_same_turn() -> void:
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	# Far enough that a single Speed-4 Stride cannot close it into reach --
	# mirrors tests/unit/core/combat/test_ai_stride_then_strike.gd's own
	# "does not close into reach" guard fixture.
	var target = _target("Titus", HexCoordClass.new(9, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var first_result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])
	assert_eq(first_result.get("action_type", ""), "Stride", "fixture assumption: the first decision this turn must Stride")
	var position_after_first_stride = combatant["hex_coord"]
	var remaining_after_first_stride: int = action_economy.get_remaining()
	assert_false(action_economy.can_take_movement_action(), "fixture assumption: the Movement gate must now be tripped")

	# A SECOND decision cycle in the SAME turn (no start_of_turn() reset in
	# between) must NOT issue another Stride -- the enemy is still out of
	# reach, but Movement is locked out for the rest of this turn.
	var second_result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(
		second_result.get("action_type", ""), "",
		"a second decision cycle in the same turn must never issue a second Stride (no move-then-move)"
	)
	assert_null(second_result.get("destination", "MISSING"))
	assert_false(second_result.get("will_strike", true))
	assert_true(
		combatant["hex_coord"].equals(position_after_first_stride),
		"the combatant must not be repositioned a second time within the same turn"
	)
	assert_eq(
		action_economy.get_remaining(), remaining_after_first_stride,
		"a blocked second Stride attempt must not spend a further action"
	)


func test_ai_does_not_stride_when_a_step_already_used_the_movement_gate_this_turn() -> void:
	# The Movement-trait gate is shared across Step and Stride (FEAT-001) --
	# an enemy that has already Stepped this turn (e.g. via some other
	# domain path sharing the SAME ActionEconomy) must not then Stride
	# either, even though its action budget is untouched.
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(9, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var step_result: Dictionary = MovementClass.step(combatant, HexCoordClass.new(0, 1), [target], action_economy)
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")
	assert_false(action_economy.can_take_movement_action())
	var budget_before_decision: int = action_economy.get_remaining()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "", "the AI must not Stride once Movement is already locked out this turn, regardless of remaining budget")
	assert_eq(action_economy.get_remaining(), budget_before_decision, "no action may be spent on a blocked Stride attempt")
	assert_true(combatant["hex_coord"].equals(HexCoordClass.new(0, 1)), "the combatant must remain at its post-Step position")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: Enemy never exceeds its per-turn action budget across
# multiple simulated turns.
# ══════════════════════════════════════════════════════════════════════════

func test_ai_never_exceeds_its_action_budget_across_multiple_simulated_turns() -> void:
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	# A target far enough away that it can never be closed into reach no
	# matter how many Strides accumulate -- every simulated turn attempts
	# (and, while budget/gate allow, succeeds at) exactly one Stride.
	var target = _target("Titus", HexCoordClass.new(100, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_round()

	var strides_taken: int = 0
	for turn_index in range(ActionEconomyClass.MAX_BUDGET + 5):
		action_economy.start_of_turn()
		var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

		assert_true(
			action_economy.get_remaining() >= 0,
			"the per-round action budget must never go negative (simulated turn %d)" % turn_index
		)
		assert_true(
			action_economy.get_remaining() <= ActionEconomyClass.MAX_BUDGET,
			"the per-round action budget must never exceed its maximum (simulated turn %d)" % turn_index
		)

		if result.get("action_type", "") == "Stride":
			strides_taken += 1
			assert_true(
				strides_taken <= ActionEconomyClass.MAX_BUDGET,
				"the AI must never spend more Strides than the per-round budget allows (simulated turn %d)" % turn_index
			)
		else:
			# Once the round budget is exhausted, every further decision must
			# be a clean no-op -- never an over-budget spend attempt.
			assert_true(
				action_economy.is_spent(),
				"a decision cycle that issues no Stride once movement is otherwise legal must mean the budget is exhausted (simulated turn %d)" % turn_index
			)

	assert_eq(strides_taken, ActionEconomyClass.MAX_BUDGET, "exactly one Stride per turn must be taken until the per-round budget (7) is exhausted, never more")
	assert_true(action_economy.is_spent(), "the round budget must be fully (and only fully) exhausted after MAX_BUDGET Strides")
	assert_eq(action_economy.get_remaining(), 0)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: AI decision executes through the existing AIDecisionPort /
# ResolveActionUseCase / RoundSession.advance_ai_turn() orchestration, with
# no new port or use-case class introduced in core/application/.
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_advance_ai_turn_executes_stride_but_defers_strike_to_next_turn() -> void:
	var goblin = _melee_combatant(HexCoordClass.new(0, 0))
	goblin.is_enemy = true
	var titus = _target("Titus", HexCoordClass.new(4, 0), 200)
	titus.is_enemy = false
	var entries: Array = [_entry(goblin), _entry(titus)]

	# raw=12 -> roll_total = 12 + strength(2) + proficiency(1) = 15 vs ac=14 -> hit,
	# not a crit (15-14=1 < 10); damage roll raw=4 -> 4 + 2 = 6 damage.
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().name, "Skeleton", "the enemy must be the current actor")
	var goblin_action_economy = entries[0]["action_economy"]
	var budget_before: int = goblin_action_economy.get_remaining()

	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_true(
		HexMathClass.hex_distance(goblin["hex_coord"], titus["hex_coord"]) <= 1,
		"the enemy must have Strode into melee reach of the target this turn"
	)
	# FEAT-003 (ADR-103): the per-turn one-action gate means the Stride
	# already spent this turn's ONE action -- core/combat/ai.gd still reports
	# a composite will_strike:true decision (it has no visibility into the
	# new _action_used gate), but resolve_action_use_case.resolve()'s own
	# spend_action() call is rejected with ACTION_ALREADY_USED, so no Strike
	# resolves (no history entry, no damage) in the SAME turn as the Stride.
	assert_eq(
		rig["history"].entries.size(), 0,
		"no Strike may resolve in the same turn as the Stride -- only one action is permitted per turn (FEAT-003); the Stride half is executed directly by core/combat/ai.gd and records no history entry of its own"
	)
	assert_eq(
		goblin_action_economy.get_remaining(), budget_before - 1,
		"exactly one action must be spent this turn -- the Stride (core/rules/movement.gd); the Strike attempt must not decrement the budget further"
	)
	assert_eq(titus.hp_current, 200, "the target must be undamaged -- the Strike attempt must not resolve in the same turn as the Stride")
	assert_eq(session.current_actor().name, "Titus", "advance_ai_turn() must still advance the cursor after the composite decision")


func test_application_layer_contains_no_new_port_or_use_case_class() -> void:
	# ADR-002 enforcement (mirrors this project's CI static-check gate):
	# FEAT-006 wires the extended AI decision through the EXISTING
	# AIDecisionPort/ResolveActionUseCase/RoundSession orchestration only --
	# no new port or use-case file may appear in core/application/ beyond
	# what a later feature's own explicit spec calls for.
	#
	# FEAT-009 (US-009 / FR-005, ADR-014) deliberately extends this
	# whitelist by ONE file: core/application/reaction_window.gd -- the
	# pausable reaction-window use case, modeled on RoundSession's own
	# stepwise/resumable pattern (see that file's own header doc). Its two
	# NEW ports (ReactionWindowPort/ReactionChooserPort) live under
	# core/application/ports/ -- a subdirectory this flat, non-recursive
	# dir.list_dir_begin() scan never descends into -- so they never appear
	# in actual_files below and this whitelist does not need to name them.
	#
	# FEAT-002 (US-001, ADR-001) deliberately extends this whitelist by TWO
	# more files: core/application/resolve_to_hit_uc.gd (ResolveToHitUseCase)
	# and core/application/apply_on_hit_defense_uc.gd
	# (ApplyOnHitDefenseUseCase) -- the two APPLICATION-layer use cases the
	# ADR-001 two-phase Strike-resolution split introduces (see each file's
	# own header doc, and core/application/resolve_action_use_case.gd's
	# FEAT-002 doc).
	#
	# FEAT-002 (US-002, Dodge-Step steel thread) deliberately extends this
	# whitelist by ONE more file: core/application/resolve_dodge_step_use_case.gd
	# (ResolveDodgeStepUseCase) -- the APPLICATION-layer use case that decides
	# whether/how to prompt for a Dodge-Step destination hex once a Strike's
	# to-hit phase reports defender_stepped=true (see that file's own header
	# doc, and core/application/round_session.gd's `_resolve_dodge_step_prompt()`
	# doc).
	#
	# FEAT-008 (US-008 / FR-007, Dodge-Step steel thread) deliberately extends
	# this whitelist by ONE more file: core/application/render_combat_log_use_case.gd
	# (RenderCombatLogUseCase) -- the APPLICATION-layer use case that derives
	# the active-defense outcome ("Defense: <outcome>") from an
	# already-resolved reaction and records it via the injected
	# record_reaction Callable, so the rich combat log's Defense segment
	# reflects the ACTUAL dodge/parry/block/none outcome instead of always
	# defaulting to "none" (see that file's own header doc, and
	# core/application/round_session.gd's `advance_ai_turn()` /
	# MainScene.gd's `_verb_bar_strike_execute()` wiring doc).
	#
	# Iteration K FEAT-004 (US-004, ADR-004) deliberately extends this
	# whitelist by TWO more files: core/application/_build_defense_context.gd
	# (BuildDefenseContext) and core/application/open_reaction_window_use_case.gd
	# (OpenReactionWindowUseCase) -- the two APPLICATION-layer helpers that
	# wire the enemy's two-phase (PreHitAvoidance/OnHitMitigation) reaction
	# windows into the player-Strike path, synchronously, via
	# infrastructure/ai_reaction_policy.gd's AIReactionPolicy (see each
	# file's own header doc, and core/application/resolve_action_use_case.gd's
	# resolve_reactive() doc).
	#
	# FEAT-007 (US-007) deliberately extends this whitelist by ONE more file:
	# core/application/selection_descriptor.gd (SelectionDescriptor) -- a
	# plain RefCounted DATA value object (not a port, not a use case) mirroring
	# core/application/verb_registry.py's SelectionDescriptor dataclass shape,
	# additively extended with an optional `candidate_options` field. It
	# introduces no new port/use-case orchestration of its own (see that
	# file's own header doc) and is whitelisted here purely because this
	# check's dir.list_dir_begin() scan is name-based, not type-based.
	#
	# FEAT-008 (US-008) deliberately extends this whitelist by TWO more
	# files: core/application/resolved_selection.gd (ResolvedSelection --
	# a plain RefCounted DATA value object, not a port, mirroring
	# core/application/dto/effect_application_error.gd's fail-fast
	# is_valid()/validation_error() convention) and
	# core/application/selection_resolution_use_case.gd
	# (SelectionResolutionUseCase -- the application-layer use case that
	# resolves a SelectionDescriptor's SCALAR/OPTION_THEN_TARGET/AREA_SET
	# resolution_mode into a ResolvedSelection, computing AREA_SET's
	# affected-hex set via core/geometry's HexMath). No new port is
	# introduced (design notes: "no new ports beyond the applier seam") --
	# both files are whitelisted here purely because this check's
	# dir.list_dir_begin() scan is name-based, not type-based.
	#
	# FEAT-003 (US-002 / FR-001, exploration/scenario steel thread) deliberately
	# extends this whitelist by ONE more file: core/application/scenario_session.gd
	# (ScenarioSession) -- the RUNTIME-ONLY (ADR-002, not persisted) application
	# state tracking party_hex_positions/completed_encounter_ids/the active
	# ScenarioResource reference, per that feature's own explicit
	# files_to_create. Not a port (no ports/ subdirectory entry), a plain
	# RefCounted application-state object mirroring round_session.gd's own
	# layering, whitelisted here purely because this check's
	# dir.list_dir_begin() scan is name-based, not type-based.
	#
	# FEAT-005 (US-004 / FR-002, exploration/scenario steel thread) deliberately
	# extends this whitelist by ONE more file: core/application/
	# exploration_controller.gd (ExplorationController) -- the use-case
	# orchestrator for party movement + proximity-trigger evaluation over the
	# injected ScenarioSession, per that feature's own explicit
	# files_to_create. Not a port (no ports/ subdirectory entry), a plain
	# RefCounted use-case object depending only on ScenarioSession + DOMAIN
	# HexCoord/HexMath/TriggerType, whitelisted here purely because this
	# check's dir.list_dir_begin() scan is name-based, not type-based.
	#
	# FEAT-003 (US-001 / FR-008, ADR-004, composition-root de-bloat steel
	# thread) deliberately extends this whitelist by ONE more file:
	# core/application/combat_session_factory.gd (CombatSessionFactory) --
	# the entry-point-adjacent factory MainScene._ready() now delegates its
	# hex_combatants/party/enemies assembly to, per that feature's own
	# explicit files_to_create. Its companion port,
	# core/application/ports/combat_resource_loader_port.gd
	# (CombatResourceLoaderPort), lives under the ports/ subdirectory this
	# flat, non-recursive dir.list_dir_begin() scan never descends into (see
	# the FEAT-009 note above) so it never appears in actual_files and needs
	# no whitelist entry of its own.
	#
	# FEAT-002 (US-003 / FR-003, NFR-002, NFR-003, game-state/new-game steel
	# thread) deliberately extends this whitelist by ONE more file:
	# core/application/new_game_factory.gd (NewGameFactory) -- the pure
	# APPLICATION-layer use-case service that seeds a fresh GameStateData for
	# the prologue or an arbitrary scenario path, per that feature's own
	# explicit files_to_create. Not a port (no ports/ subdirectory entry), a
	# static-only RefCounted use-case service depending only on the DOMAIN
	# GameStateData/ScenarioResource/EncounterResource/PartyResource types,
	# whitelisted here purely because this check's dir.list_dir_begin() scan
	# is name-based, not type-based.
	#
	# Enemy AI sophistication iteration, FEAT-001 (US-001 / FR-001, ADR-001)
	# deliberately extends this whitelist by ONE more file:
	# core/application/ai_planner_port.gd (AIPlannerPort) -- a NEW, PARALLEL
	# APPLICATION-layer port (abstract plan_turn(combatant, world_context)
	# -> Array) that tier-specific DOMAIN AI planners (MindlessAI/GruntAI)
	# will implement and that RoundSession will duck-type against, per
	# ADR-001's explicit decision to add a parallel port rather than modify
	# the frozen core/application/ai_decision_port.gd. This is a genuinely
	# new port (unlike most other whitelist entries above, which are DTOs or
	# use cases), whitelisted here purely because this check's
	# dir.list_dir_begin() scan is name-based, not type-based, and this
	# feature's own explicit files_to_create names this exact path.
	var expected_files: Array = [
		"_build_defense_context.gd",
		"ai_decision_port.gd",
		"ai_planner_port.gd",
		"apply_on_hit_defense_uc.gd",
		"combat_session_factory.gd",
		"combatant_snapshot_seeder.gd",
		"determine_outcome_use_case.gd",
		"event_sink_port.gd",
		"exploration_controller.gd",
		"new_game_factory.gd",
		"open_reaction_window_use_case.gd",
		"reaction_window.gd",
		"render_combat_log_use_case.gd",
		"resolve_action_use_case.gd",
		"resolve_dodge_step_use_case.gd",
		"resolve_to_hit_uc.gd",
		"resolved_selection.gd",
		"round_history_port.gd",
		"round_session.gd",
		"run_round_use_case.gd",
		"scenario_session.gd",
		"selection_descriptor.gd",
		"selection_resolution_use_case.gd",
		"turn_order_port.gd",
	]

	var dir := DirAccess.open("res://core/application")
	assert_not_null(dir, "fixture assumption: core/application/ must exist")

	# Only .gd class files are in scope for this ADR-002 port/use-case check --
	# unrelated non-GDScript tooling artifacts (e.g. __pycache__/, *.py) are
	# not application-layer classes and are ignored here.
	var actual_files: Array = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			actual_files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	actual_files.sort()

	assert_eq(
		actual_files, expected_files,
		"core/application/ must contain no new port/use-case class beyond the pre-existing set (ADR-002)"
	)


func test_ai_decision_port_contract_is_unchanged_two_argument_shape() -> void:
	# The abstract base contract (core/application/ai_decision_port.gd) must
	# still declare exactly the pre-existing (combatant, targets) signature --
	# core/combat/ai.gd's FEAT-004/005 extra parameters are OPTIONAL additions
	# on the concrete adapter, never a change to the port's own contract.
	var port := AIDecisionPortStub.new()
	var callable := Callable(port, "decide_action")
	assert_eq(callable.get_argument_count(), 2, "AIDecisionPort.decide_action()'s declared contract must remain exactly 2 arguments")


class AIDecisionPortStub:
	extends "res://core/application/ai_decision_port.gd"
