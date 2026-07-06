extends GutTest
## tests/integration/test_steel_thread_e2e.gd — FEAT-010 (US-010; NFR-003/
## NFR-004/NFR-005), Iteration F steel-thread capstone integration +
## regression suite.
##
## THE named, final smoke suite for the two P0 defects/features this
## iteration closes end-to-end:
##
##   P0-1 (FEAT-001/FEAT-002, US-001/US-002, FR-001..FR-006, ADR-003) — a
##   Movement-trait Step and Stride share ONE per-turn lockout gate
##   (core/rules/action_economy.gd's `_movement_used`, read via
##   can_take_movement_action()): once either is taken, the OTHER (and
##   itself) is locked out for the rest of that turn, the Layer 1 verb bar
##   ($VerbBarView, driven by MainScene.gd's _verb_bar_step_availability()/
##   _verb_bar_stride_availability()) visibly disables the locked-out
##   button, and the gate resets at the next turn boundary via the SAME
##   existing ActionEconomy.start_of_turn() reset (no new flag/state
##   machine, per this feature's design notes).
##
##   P0-2 (FEAT-003..FEAT-006, US-003..US-006, FR-007..FR-011, ADR-002/
##   ADR-004..ADR-006) — core/combat/ai.gd's decide_action(), invoked on the
##   enemy's turn, Strides toward the nearest living target when out of
##   reach (spending exactly one action through the SAME ActionEconomy gate
##   a player-driven Stride uses) and re-checks reach in the SAME decision
##   cycle to Strike immediately if an action remains -- with the enemy's
##   on-screen HexGridView token visibly repositioned via the SAME
##   move_token() call the player's own Step/Stride path uses (ADR-006, no
##   duplicate reposition implementation). An enemy already in reach Strikes
##   immediately with ZERO Stride issued.
##
## Every named test below drives EITHER the real, shipped res://MainScene.tscn
## composition root (P0-1 -- the player-facing verb bar entry point) OR a
## fully-wired, REAL RunRoundUseCase/RoundSession + a REAL, instantiated
## presentation/hex_grid_view.gd (P0-2 -- the enemy-AI-turn entry point,
## mirroring tests/integration/test_ai_token_reposition.gd's established
## rig) -- never a test-local re-derivation of the Movement/ActionEconomy/AI
## rules themselves (ADR-001/ADR-002/CR-001). This file introduces NO new
## production code (files_to_modify is empty for this feature): every
## collaborator driven below is the exact, already-implemented, already
## individually-tested production object (core/rules/action_economy.gd,
## core/rules/movement.gd, core/combat/ai.gd, core/application/
## round_session.gd, presentation/hex_grid_view.gd, presentation/
## verb_bar_view.gd, MainScene.gd) -- this suite's sole job is proving they
## ALL still compose correctly together, end to end, at the steel thread's
## two named entry points.
##
## This suite does NOT re-test (and therefore does not duplicate) the
## individual unit-level proofs already established by:
##   tests/unit/core/rules/test_movement_lockout.gd (domain-level lockout)
##   tests/unit/presentation/test_verb_bar_lockout.gd (verb-bar-level lockout)
##   tests/unit/core/combat/test_ai_stride_then_strike.gd (Stride-then-Strike
##     decision logic)
##   tests/unit/core/combat/test_ai_reach_strike.gd / test_ai_target_selection.gd
##     (reach-check / nearest-target selection)
##   tests/unit/core/combat/test_ai_action_budget.gd (AI never double-spends)
##   tests/unit/core/combat/test_ai_determinism.gd (tie-break determinism)
##   tests/integration/test_ai_token_reposition.gd (AI-Stride token reposition)
## Nor the rest of Iteration E's regression surface (verb->target UX, End
## Turn, panels, hex grid, token move, flanking Off-Guard +2, ranged reach,
## seed randomize, status bar, control lock) -- ALL of that is exercised by
## its own already-existing, individually-named GUT suite and is picked up
## automatically, alongside this file, by scripts/test_command.sh stage 7
## (`godot --headless -- --gut-run-all`, tests/.gutconfig.json's
## `res://tests`+include_subdirs=true) -- this project's whole-project
## regression gate (ADR-002/CR-001: no re-derived/duplicate coverage).
##
## test_criteria satisfied by this file:
##   - Named P0-1 lockout test: verb bar + domain gate, both Step-blocks-
##     Stride and Stride-blocks-Step directions, and turn-boundary reset.
##   - Named P0-2 AI movement test: out-of-reach enemy strides then strikes
##     the nearest living target, with token visibly repositioned on-screen.
##   - Named P0-2 in-reach test: enemy strikes only, with zero Stride issued.
##   - action-economy/lockout compliance and determinism tests across
##     multiple simulated turns and repeated pinned-seed runs.
## (Full existing GUT UI regression suite / headless-boot-zero-error gate /
## multi-run CI flakiness are satisfied by tests/integration/
## test_headless_boot.gd, this file's sibling, plus the pre-existing
## whole-project `--gut-run-all` gate.)

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")

const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")

## The pinned deterministic-test fixture seed (matches
## data/encounters/prologue_encounter.tres' own `seed` field, 42) -- this
## codebase's established integration/E2E convention.
const SEED: int = 42

## Safety bound on any drive/cycle loop below (CWE-835 "never loop
## unbounded" guard, mirroring this codebase's established `_MAX_*`
## convention, e.g. tests/e2e/test_full_steel_thread_e2e.gd's
## `_MAX_DRIVE_ITERATIONS`).
const _MAX_CYCLES: int = 20

## Number of independent MainScene boots exercised by the multi-run
## determinism check below (the design notes' "repeated pinned-seed runs" /
## "zero flakiness across multiple consecutive CI runs" criteria).
const _DETERMINISM_RUN_COUNT: int = 5


# ══════════════════════════════════════════════════════════════════════════
# Shared fixture/double collaborators -- mirrors tests/integration/
# test_ai_token_reposition.gd's / tests/unit/core/application/
# test_round_session_ai_turn.gd's identically-named/-shaped rig exactly, so
# this suite drives the SAME RunRoundUseCase/RoundSession wiring every other
# AI-turn integration suite in this codebase already uses.
# ══════════════════════════════════════════════════════════════════════════

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


## ScriptedRandomNumberPort -- deterministic, hand-scripted dice rolls (never
## a real seeded RNG) so a resolved Strike's hit/damage outcome is exactly
## known, mirroring tests/unit/core/application/test_round_session_ai_turn.gd's
## identically-named double.
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


func _entry(combatant: Dictionary) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## Builds a fully-wired, REAL RunRoundUseCase plus fake ports -- mirrors
## tests/integration/test_ai_token_reposition.gd's identically-named helper.
func _make_use_case(entries: Array, ai_port, random_number_port, event_sink_port) -> Dictionary:
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	return {"use_case": run_round_use_case, "history": round_history_port}


## _melee_enemy(hex_coord, hp) -> Dictionary -- mirrors tests/unit/core/
## combat/test_ai_stride_then_strike.gd's `_melee_combatant()` fixture
## exactly, so this suite's Stride-distance/reach math matches an
## already-proven fixture rather than a newly-invented one.
func _melee_enemy(combatant_id: String, hex_coord, hp: int = 8) -> Dictionary:
	return {
		"name": "Goblin", "combatant_id": combatant_id, "hp_current": hp, "ac": 12,
		"strength": 2, "hex_coord": hex_coord, "_is_enemy": true,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 1, "damage_die": 6},
	}


func _player_target(combatant_id: String, hex_coord, hp: int = 20) -> Dictionary:
	return {
		"name": "Titus", "combatant_id": combatant_id, "hp_current": hp, "ac": 14,
		"strength": 5, "hex_coord": hex_coord, "_is_enemy": false,
	}


## _boot_main_scene_with_seed(seed_value) -> Node -- instantiates the REAL,
## shipped res://MainScene.tscn composition root, pinned to a deterministic
## seed_override, mirroring this codebase's established convention (tests/
## unit/presentation/test_verb_bar_lockout.gd, tests/gut/test_steel_thread_e2e.gd).
func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn (the real project.godot run/main_scene target) must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Named P0-1 test: verb bar + domain gate lockout -- Step-blocks-Stride,
# Stride-blocks-Step, and turn-boundary reset.
# ══════════════════════════════════════════════════════════════════════════

func test_p0_1_step_blocks_stride_via_verb_bar_and_domain_gate() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any Movement-trait action")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42 before any Movement-trait action")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")

	var step_hexes: Array = instance.movement_input_controller.get_selectable_step_hexes()
	assert_true(step_hexes.size() > 0, "fixture assumption: at least one legal Step destination exists")

	var step_result: Dictionary = instance._verb_registry.execute("STEP", step_hexes[0])
	assert_true(step_result.get("ok", false), "fixture assumption: the Step itself must succeed")

	# Domain gate: the SAME ActionEconomy the verb bar reads from is tripped.
	assert_false(action_economy.can_take_movement_action(), "a resolved Step must trip the domain Movement-trait gate for the rest of this turn")

	# Verb bar: STRIDE (the OTHER Movement-trait verb) is now unavailable and
	# its rendered button is visibly disabled for the rest of the turn.
	assert_false(instance._verb_registry.is_available("STRIDE"), "STRIDE must be locked out for the rest of the turn once a Step has been taken")
	assert_true(instance.verb_bar_view.get_button("STRIDE").disabled, "the Layer 1 verb bar's rendered STRIDE button must be visibly disabled once locked out")

	# Self-lockout: STEP is also disabled (a Movement-trait action locks out
	# FURTHER Movement-trait actions, including itself).
	assert_false(instance._verb_registry.is_available("STEP"), "STEP must also be locked out after itself -- the shared gate blocks any further Movement-trait action")
	assert_true(instance.verb_bar_view.get_button("STEP").disabled, "the Layer 1 verb bar's rendered STEP button must be visibly disabled once locked out")


func test_p0_1_stride_blocks_step_via_verb_bar_and_domain_gate() -> void:
	var instance = _boot_main_scene_with_seed(SEED)
	await get_tree().process_frame

	assert_true(instance._verb_registry.is_available("STEP"), "fixture assumption: STEP is available at seed=42 before any Movement-trait action")
	assert_true(instance._verb_registry.is_available("STRIDE"), "fixture assumption: STRIDE is available at seed=42 before any Movement-trait action")

	var action_economy = instance.round_session.current_action_economy()
	assert_not_null(action_economy, "fixture assumption: the active actor carries a live domain ActionEconomy")
	var remaining_before: int = action_economy.get_remaining()

	var stride_hexes: Array = instance.movement_input_controller.get_selectable_stride_hexes()
	assert_true(stride_hexes.size() > 0, "fixture assumption: at least one legal Stride destination exists")

	var stride_result: Dictionary = instance._verb_registry.execute("STRIDE", stride_hexes[0])
	assert_true(stride_result.get("ok", false), "fixture assumption: the Stride itself must succeed")
	assert_eq(action_economy.get_remaining(), remaining_before - 1, "a Stride must spend exactly one action")

	# Domain gate tripped.
	assert_false(action_economy.can_take_movement_action(), "a resolved Stride must trip the domain Movement-trait gate for the rest of this turn")

	# Verb bar: STEP (the OTHER Movement-trait verb) is now unavailable and
	# its rendered button is visibly disabled for the rest of the turn.
	assert_false(instance._verb_registry.is_available("STEP"), "STEP must be locked out for the rest of the turn once a Stride has been taken")
	assert_true(instance.verb_bar_view.get_button("STEP").disabled, "the Layer 1 verb bar's rendered STEP button must be visibly disabled once locked out")

	# STRIKE remains a wholly separate concern, gated only by reach/budget --
	# never by the Movement-trait lockout (already proven in isolation by
	# tests/unit/presentation/test_verb_bar_lockout.gd's own regression guard;
	# not re-asserted here since an arbitrary chosen Stride destination may
	# legitimately move the actor OUT of melee reach of the fixture's enemy,
	# which would be a reach-driven unavailability, not a lockout regression).


## test_p0_1_movement_lockout_resets_at_the_next_turn_boundary_via_the_real_advance_ai_turn_path()
##
## Proves the "turn-boundary reset" half of P0-1 through the REAL production
## call path that actually invokes ActionEconomy.start_of_turn() today --
## core/application/round_session.gd's advance_ai_turn() (called once per
## Enemy activation) -- rather than re-deriving the reset via a bare,
## test-local ActionEconomy.start_of_turn() call (already covered in
## isolation by tests/unit/core/rules/test_movement_lockout.gd). The
## interactive player-facing path (MainScene.gd) never itself calls
## start_of_turn() for the player mid-round (a player's ActionEconomy is
## granted fresh only at round start, per RunRoundUseCase.begin_round()) --
## so this suite proves the reset through the ONE actor/path that DOES
## re-invoke it every activation within a round: the enemy's own repeated
## turns, driven by the SAME advance_ai_turn() a real MainScene boot uses.
func test_p0_1_movement_lockout_resets_at_the_next_turn_boundary_via_the_real_advance_ai_turn_path() -> void:
	var enemy_hex := HexCoordClass.new(0, 0)
	# Far enough that even TWO full Speed-4 Strides toward it never close
	# into melee reach -- isolates this test to proving the movement gate's
	# reset behavior across turns, never depending on a Strike being resolved.
	var target_hex := HexCoordClass.new(20, 0)

	var enemy: Dictionary = _melee_enemy("goblin", enemy_hex)
	var titus: Dictionary = _player_target("titus", target_hex, 2000)
	var entries: Array = [_entry(enemy), _entry(titus)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = ScriptedRandomNumberPort.new([])
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [enemy])

	assert_eq(session.current_actor().get("name", ""), "Goblin", "fixture assumption: the out-of-reach Enemy must act first")
	var enemy_action_economy = session.current_action_economy()
	var budget_before_any_turn: int = enemy_action_economy.get_remaining()

	# ── Enemy turn 1: Strides, tripping the Movement gate. ──────────────────
	var result_1: Dictionary = session.advance_ai_turn()
	assert_true(result_1.get("ok", false))
	var position_after_turn_1 = enemy.get("hex_coord")
	assert_false(position_after_turn_1.equals(enemy_hex), "fixture assumption: turn 1 must actually Stride the enemy toward the far-off target")
	assert_false(enemy_action_economy.can_take_movement_action(), "the Movement gate must be tripped immediately after turn 1's Stride")
	assert_eq(enemy_action_economy.get_remaining(), budget_before_any_turn - 1, "turn 1's Stride must spend exactly one action")

	assert_eq(session.current_actor().get("name", ""), "Titus", "the cursor must advance to the player after the enemy's turn 1")
	var end_turn_result: Dictionary = session.end_current_turn()
	assert_true(end_turn_result.get("ok", false))

	# ── Enemy turn 2 (same round, next activation): the gate must have reset,
	# allowing a SECOND Stride to actually occur -- the observable proof that
	# advance_ai_turn()'s action_economy.start_of_turn() call reset the
	# per-turn Movement lockout at this turn boundary. ──────────────────────
	assert_eq(session.current_actor().get("name", ""), "Goblin", "the cursor must return to the Enemy for its second turn this round")
	var result_2: Dictionary = session.advance_ai_turn()
	assert_true(result_2.get("ok", false))
	var position_after_turn_2 = enemy.get("hex_coord")

	assert_false(
		position_after_turn_2.equals(position_after_turn_1),
		"turn 2 must Stride the enemy FURTHER toward the target -- only possible if the Movement gate reset at the turn boundary; "
		+ "if the lockout had incorrectly persisted, ai.gd's own can_take_movement_action() guard would have refused to move it a second time"
	)
	assert_false(enemy_action_economy.can_take_movement_action(), "the freshly re-tripped gate must again be locked immediately after turn 2's Stride")
	assert_eq(enemy_action_economy.get_remaining(), budget_before_any_turn - 2, "turn 2's Stride must spend exactly one more action from the SAME shared round budget")


# ══════════════════════════════════════════════════════════════════════════
# Named P0-2 tests: enemy AI decide_action() movement, driven through the
# real RunRoundUseCase/RoundSession + a REAL HexGridView (mirrors tests/
# integration/test_ai_token_reposition.gd's established rig).
# ══════════════════════════════════════════════════════════════════════════

func test_p0_2_out_of_reach_enemy_strides_then_strikes_nearest_living_target_with_token_repositioned_on_screen() -> void:
	var enemy_hex := HexCoordClass.new(0, 0)
	# hex_distance 4 -- out of melee reach initially, but within a single
	# Speed-4 Stride's reach of landing adjacent (mirrors tests/unit/core/
	# combat/test_ai_stride_then_strike.gd's own proven fixture exactly).
	var titus_hex := HexCoordClass.new(4, 0)

	var goblin: Dictionary = _melee_enemy("goblin", enemy_hex)
	var titus: Dictionary  = _player_target("titus", titus_hex, 20)
	var entries: Array = [_entry(goblin), _entry(titus)]

	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	hex_grid_view.load_combatants([
		CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(enemy_hex.q, enemy_hex.r)),
		CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(titus_hex.q, titus_hex.r)),
	])

	var token_before = hex_grid_view.get_token("goblin")
	assert_not_null(token_before, "fixture assumption: HexGridView must already carry a token for the Enemy actor")
	assert_true(token_before.hex_coord.equals(enemy_hex), "fixture assumption: the token starts at the Enemy's pre-Stride hex")

	var event_sink_port = FakeEventSinkPort.new()
	# raw=12 -> roll_total = 12 + strength(2) + proficiency(1) = 15 vs ac=14 -> hit;
	# damage raw=4 -> 4 + strength(2) = 6 damage.
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])
	session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))

	assert_eq(session.current_actor().get("name", ""), "Goblin", "fixture assumption: the out-of-reach Enemy must act first")
	var hp_before: int = titus.get("hp_current", 0)

	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	# The enemy actually Strode (domain state moved and is now adjacent).
	var moved_hex = goblin.get("hex_coord")
	assert_false(moved_hex.equals(enemy_hex), "the out-of-reach AI must Stride toward its target rather than standing still")

	# ...then Struck the nearest living target in the SAME decision cycle.
	assert_eq(rig["history"].entries.size(), 1, "exactly one Strike must resolve via resolve_action_use_case -- the SAME pipeline the player's own Strike uses")
	assert_eq(titus.get("hp_current", -1), hp_before - 6, "the Stride-then-Strike must actually damage the nearest living target for the exact scripted amount")

	# The enemy's on-screen token must be visibly repositioned to match.
	var token_after = hex_grid_view.get_token("goblin")
	assert_not_null(token_after, "the Enemy's token must still be on record after the AI Stride")
	assert_true(token_after.hex_coord.equals(moved_hex), "the enemy token's on-screen hex position must update to the AI Stride's destination hex")
	assert_eq(
		token_after.position, hex_grid_view.axial_to_pixel_with_offset(moved_hex),
		"the enemy token's rendered screen position must resync to the AI Stride destination's axial-to-pixel projection"
	)


func test_p0_2_in_reach_enemy_strikes_only_with_zero_stride_issued_and_token_unmoved() -> void:
	var enemy_hex := HexCoordClass.new(0, 0)
	var titus_hex := HexCoordClass.new(1, 0)  # hex_distance 1 -- already adjacent/in melee reach

	var goblin: Dictionary = _melee_enemy("goblin", enemy_hex)
	var titus: Dictionary  = _player_target("titus", titus_hex, 20)
	var entries: Array = [_entry(goblin), _entry(titus)]

	var hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(hex_grid_view)
	hex_grid_view.load_combatants([
		CombatantClass.new("goblin", "Goblin", "Enemy", HexCoordClass.new(enemy_hex.q, enemy_hex.r)),
		CombatantClass.new("titus", "Titus", "Player", HexCoordClass.new(titus_hex.q, titus_hex.r)),
	])

	var token_before = hex_grid_view.get_token("goblin")
	var position_before = token_before.position

	var event_sink_port = FakeEventSinkPort.new()
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])
	session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))

	assert_eq(session.current_actor().get("name", ""), "Goblin", "fixture assumption: the in-reach Enemy must still act first")
	var enemy_action_economy = session.current_action_economy()
	var budget_before: int = enemy_action_economy.get_remaining()
	var hp_before: int = titus.get("hp_current", 0)

	var result: Dictionary = session.advance_ai_turn()
	assert_true(result.get("ok", false))

	# Zero Stride issued: the domain hex_coord never changed, and the
	# ActionEconomy's Movement gate was never touched.
	assert_true(goblin.get("hex_coord").equals(enemy_hex), "an already-in-reach enemy must issue ZERO Stride -- its position must be completely unchanged")
	assert_true(enemy_action_economy.can_take_movement_action(), "zero Stride issued means the Movement-trait gate must remain untouched (still available)")

	# Exactly one Strike resolved, spending exactly one action (never two).
	assert_eq(rig["history"].entries.size(), 1, "exactly one Strike must resolve -- no Stride action was taken alongside it")
	assert_eq(enemy_action_economy.get_remaining(), budget_before - 1, "only the Strike's own action may be spent -- zero additional action for a Stride that never happened")
	assert_eq(titus.get("hp_current", -1), hp_before - 6, "the immediate Strike must still damage the target for the exact scripted amount")

	# The enemy's on-screen token must remain exactly where it started.
	var token_after = hex_grid_view.get_token("goblin")
	assert_true(token_after.hex_coord.equals(enemy_hex), "the enemy token's on-screen hex must be completely unchanged when zero Stride was issued")
	assert_eq(token_after.position, position_before, "the enemy token's rendered screen position must be completely unchanged when zero Stride was issued")


# ══════════════════════════════════════════════════════════════════════════
# Action-economy/lockout compliance across multiple simulated turns.
# ══════════════════════════════════════════════════════════════════════════

## Extends the turn-boundary-reset proof above across several MORE
## activations (four full enemy turns within one round), asserting the
## shared per-round action budget decrements by EXACTLY one per Stride with
## no drift/double-spend, and that the Movement gate is correctly
## tripped-then-reset on every single cycle -- a compliance guard against
## any regression that might only manifest after several repeated
## activations (e.g. an accidental double-decrement or a gate that fails to
## reset after the second-or-later turn).
func test_action_economy_and_lockout_compliance_across_multiple_simulated_enemy_turns() -> void:
	var enemy_hex := HexCoordClass.new(0, 0)
	var target_hex := HexCoordClass.new(30, 0)  # far enough that no number of Strides within budget ever closes into reach

	var enemy: Dictionary = _melee_enemy("goblin", enemy_hex)
	var titus: Dictionary = _player_target("titus", target_hex, 2000)
	var entries: Array = [_entry(enemy), _entry(titus)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = ScriptedRandomNumberPort.new([])
	var rig: Dictionary = _make_use_case(entries, AIClass.new(), random_number_port, event_sink_port)
	var session = rig["use_case"].begin_round(1, [titus], [enemy])

	var enemy_action_economy = session.current_action_economy()
	var expected_remaining: int = enemy_action_economy.get_remaining()

	var cycles: int = 0
	var enemy_turns_taken: int = 0

	while enemy_turns_taken < 4 and cycles < _MAX_CYCLES:
		cycles += 1
		if session.current_actor().get("name", "") != "Goblin":
			session.end_current_turn()
			continue

		var before_this_turn_position = enemy.get("hex_coord")
		var result: Dictionary = session.advance_ai_turn()
		assert_true(result.get("ok", false), "cycle %d: advance_ai_turn() must never fail/stall (CWE-835 guard)" % cycles)

		enemy_turns_taken += 1
		expected_remaining -= 1

		assert_eq(
			enemy_action_economy.get_remaining(), expected_remaining,
			"enemy turn %d: the shared per-round action budget must decrement by EXACTLY one per Stride, with no drift across repeated activations" % enemy_turns_taken
		)
		assert_false(
			enemy_action_economy.can_take_movement_action(),
			"enemy turn %d: the Movement gate must be tripped immediately after this turn's Stride" % enemy_turns_taken
		)
		assert_false(
			enemy.get("hex_coord").equals(before_this_turn_position),
			"enemy turn %d: each activation must actually Stride further -- proving the gate reset correctly on every single prior turn boundary" % enemy_turns_taken
		)

	assert_eq(enemy_turns_taken, 4, "fixture assumption: exactly four enemy activations must have been driven within the safety bound")
	assert_eq(
		enemy_action_economy.get_remaining(), ActionEconomyClass.MAX_BUDGET - 4,
		"after four Strides, the shared round budget must reflect EXACTLY four spent actions -- no double-spend, no under-spend"
	)


# ══════════════════════════════════════════════════════════════════════════
# Determinism across repeated pinned-seed runs (zero flakiness).
# ══════════════════════════════════════════════════════════════════════════

## Extends tests/regression/test_seed_determinism.gd's two-boot diff to
## _DETERMINISM_RUN_COUNT (5) independent, freshly-instantiated real
## MainScene.tscn boots at the SAME pinned seed=42 -- proving the full
## interactive steel thread's event sequence at boot is byte-identical
## across many repeated runs, not merely two (the design notes'/test
## criteria's "zero flakiness observed across multiple consecutive CI runs
## at the pinned seed").
func test_ai_decision_and_event_sequence_determinism_across_repeated_pinned_seed_mainscene_boots() -> void:
	var logs: Array = []

	for i in range(_DETERMINISM_RUN_COUNT):
		var instance = _boot_main_scene_with_seed(SEED)
		await get_tree().process_frame
		assert_eq(instance.resolved_seed, SEED, "run %d: seed_override must resolve to the pinned seed" % i)
		logs.append(instance.event_sink.log)

	for i in range(1, logs.size()):
		assert_eq(
			logs[i].size(), logs[0].size(),
			"run %d: every independent boot at the pinned seed must emit the same NUMBER of events as run 0" % i
		)
		var count: int = mini(logs[0].size(), logs[i].size())
		for j in range(count):
			assert_eq(
				logs[i][j].to_dict(), logs[0][j].to_dict(),
				"run %d: event[%d] must be byte-identical to run 0's event[%d] -- zero flakiness across repeated pinned-seed runs" % [i, j, j]
			)
