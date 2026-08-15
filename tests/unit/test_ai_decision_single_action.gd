extends GutTest
## tests/unit/test_ai_decision_single_action.gd
##
## GUT unit test suite for FEAT-007 (US-007 / FR-005, ADR-105): Enemy AI is
## reworked to take EXACTLY ONE action per turn, mirroring the SAME
## one-action gate (core/rules/action_economy.gd's can_take_action()/
## _action_used) the player is already bound to.
##
## core/combat/ai.gd's decide_action() now:
##   - Returns a Strike ActionDecision when a living target is already in
##     reach.
##   - Otherwise Strides toward the best (nearest, stable lowest-(q,r)
##     tie-break) target using the existing
##     core/rules/movement.gd Movement.get_stride_destinations() distance
##     logic (ADR-105) — NEVER both a Stride and a Strike in the same call.
## The FEAT-005 composite "Stride-then-Strike" will_strike path is fully
## removed from both core/combat/ai.gd and
## core/application/round_session.gd's advance_ai_turn().
##
## Test criteria (feature spec):
##   1. decide_action() returns a Strike ActionDecision when a living target
##      is already in reach.
##   2. decide_action() returns a Stride ActionDecision toward the best
##      target when no target is in reach (never both in one call).
##   3. The will_strike composite path is fully removed from ai.gd and
##      round_session.advance_ai_turn().
##   4. Under a pinned seed, Stride tie-breaks are deterministic (stable
##      lowest-(q,r) selection) across repeated runs.
##   5. advance_ai_turn() results in exactly one spend_action() call per AI
##      turn (verified via an ActionEconomy spy).

const AIClass                      = preload("res://core/combat/ai.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeedPolicyClass              = preload("res://infrastructure/seed_policy.gd")
const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")


# ── Test doubles ─────────────────────────────────────────────────────────

## SpyActionEconomy — a real ActionEconomy that additionally counts every
## spend_action() call it receives, so criterion 5 can assert the EXACT call
## count observed by round_session.gd's advance_ai_turn(), rather than only
## inferring it indirectly from budget_remaining deltas.
class SpyActionEconomy:
	extends "res://core/rules/action_economy.gd"

	var spend_action_call_count: int = 0

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_action_call_count += 1
		return super.spend_action(action_metadata)


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


# ── Real-environment isolation for HYKAEN_SEED (criterion 4) ──────────────

var _had_env_var_before: bool = false
var _original_env_value: String = ""


func before_each() -> void:
	_had_env_var_before = OS.has_environment(SeedPolicyClass.ENV_VAR_NAME)
	if _had_env_var_before:
		_original_env_value = OS.get_environment(SeedPolicyClass.ENV_VAR_NAME)


func after_each() -> void:
	if _had_env_var_before:
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, _original_env_value)
	else:
		OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)


# ── Fixture helpers ─────────────────────────────────────────────────────

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


func _entry(combatant, action_economy = null) -> Dictionary:
	return {"combatant": combatant, "action_economy": action_economy if action_economy != null else ActionEconomyClass.new()}


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

	return {"use_case": run_round_use_case, "history": round_history_port, "events": event_sink_port}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: decide_action() returns a Strike ActionDecision when a living
# target is already in reach.
# ══════════════════════════════════════════════════════════════════════════

func test_decide_action_returns_strike_when_target_already_in_reach() -> void:
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(1, 0))  # adjacent
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Strike", "a living target already in reach must be Struck immediately")
	assert_eq(result.get("target").name, "Titus")
	assert_true(result.get("will_strike", false), "a Strike decision must report will_strike:true")
	assert_null(result.get("destination", "MISSING"), "no Stride destination is issued for an immediate Strike")


func test_decide_action_returns_strike_for_ranged_target_already_in_range() -> void:
	var ai = AIClass.new()
	var combatant = CombatantClass.from_dict({
		"name": "Archer", "hp_current": 8, "ac": 12, "dexterity": 2,
		"hex_coord": HexCoordClass.new(0, 0),
		"weapon": {"damage_modifier_attribute": "dexterity", "proficiency_bonus": 1, "damage_die": 6, "range_hexes": 8},
	})
	var target = _target("Titus", HexCoordClass.new(5, 0))  # distance 5, within range 8
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Strike")
	assert_true(result.get("will_strike", false))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: decide_action() returns a Stride ActionDecision toward the
# best target when no target is in reach -- NEVER both in one call.
# ══════════════════════════════════════════════════════════════════════════

func test_decide_action_returns_stride_toward_best_target_when_none_in_reach() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(6, 0)
	var target = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var expected_destinations: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [target])
	assert_false(expected_destinations.is_empty(), "fixture assumption: at least one legal Stride destination must exist")
	var original_distance: int = HexMathClass.hex_distance(origin_hex, target_hex)

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "an out-of-reach enemy must Stride toward the best target")
	var destination = result.get("destination", null)
	assert_not_null(destination, "a Stride decision must carry a non-null destination")

	var is_legal: bool = false
	for candidate in expected_destinations:
		if candidate.equals(destination):
			is_legal = true
			break
	assert_true(is_legal, "the chosen destination must be a legal Movement.get_stride_destinations() candidate")

	var new_distance: int = HexMathClass.hex_distance(destination, target_hex)
	assert_true(new_distance < original_distance, "the Stride must strictly reduce distance to the best target")


func test_decide_action_never_returns_both_stride_and_strike_in_one_call() -> void:
	# A target close enough that a single Speed-4 Stride closes it fully
	# into melee reach -- the scenario most likely to tempt a composite
	# decision back in, if the FEAT-005 path were not truly removed.
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "fixture assumption: the enemy must Stride to close distance")
	# A single ActionDecision must describe exactly one action: when it is a
	# Stride, will_strike must never be true (no composite), and no
	# ActionDecision ever carries a second "action_type"-shaped payload.
	assert_false(
		result.get("will_strike", true),
		"decide_action() must never report a composite Stride-then-Strike decision, even when the Stride closes the target into reach"
	)
	# US-004 (FR-004, NFR-001/NFR-003, ADR-003 -- "AI Stride pathfinder seam
	# in ai.gd"): a Stride decision additively gained a 5th "path" key (the
	# transit hex sequence the Stride traveled -- real pathfinder result or
	# the [origin, best_destination] fallback). This remains a SINGLE,
	# non-composite ActionDecision -- "path" describes the ONE Stride action
	# already reported via action_type/destination, never a second action.
	# A 6th "animation_complete" key (bool) is propagated from the OS resolver
	# so round_session skips re-animation when the interleaved-OS path already
	# animated the full path -- still a single Stride decision, never composite.
	assert_eq(
		result.keys().size(), 6,
		"an ActionDecision must carry exactly its six documented keys (action_type/target/destination/will_strike/path/animation_complete) -- no extra composite payload"
	)


func test_decide_action_no_stride_available_returns_no_action_never_a_phantom_strike() -> void:
	# Movement already used this turn -- Stride is locked out, and the
	# target remains out of reach, so decide_action() must return a clean
	# no-op, never fabricate a Strike it cannot legally take.
	var ai = AIClass.new()
	var combatant = _melee_combatant(HexCoordClass.new(0, 0))
	var target = _target("Titus", HexCoordClass.new(6, 0))
	var action_economy = ActionEconomyClass.new()
	action_economy.mark_movement_used()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", "MISSING"), "")
	assert_false(result.get("will_strike", true))
	assert_null(result.get("destination", "MISSING"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the will_strike composite path is fully removed from ai.gd
# and round_session.advance_ai_turn().
# ══════════════════════════════════════════════════════════════════════════

func test_ai_gd_stride_branch_contains_no_post_stride_reach_recheck() -> void:
	# The FEAT-005 composite path re-checked reach against the combatant's
	# post-Stride position (`_is_in_reach(combatant, chosen_target)` inside
	# _stride_toward_target()). That call site must be gone entirely -- the
	# ONLY _is_in_reach() call left in ai.gd is decide_action()'s own
	# pre-Stride reach check.
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var stride_fn_start: int = content.find("func _stride_toward_target(")
	assert_true(stride_fn_start >= 0, "fixture assumption: _stride_toward_target() must exist")
	var next_fn_start: int = content.find("\nfunc ", stride_fn_start + 1)
	var stride_fn_body: String = content.substr(stride_fn_start, next_fn_start - stride_fn_start)

	assert_false(
		stride_fn_body.contains("_is_in_reach("),
		"_stride_toward_target() must not re-check reach against the post-Stride position -- the FEAT-005 composite recheck must be fully removed"
	)


func test_round_session_advance_ai_turn_contains_no_will_strike_branch() -> void:
	# The FEAT-005/006 handling of a composite decision branched on
	# `will_strike` inside advance_ai_turn() to attempt a second
	# resolve_action_use_case.resolve() call for the Strike half. That
	# branch, and any local `will_strike` variable, must be fully removed.
	#
	# FEAT-399/400 amendment (US-010 / FR-017, FR-018, ADR-007):
	# advance_ai_turn() was refactored into a two-call sequence --
	# _decide_ai_action() obtains the plan, and _execute_ai_plan() dispatches
	# every item in it (including the Strike branch's
	# resolve_action_use_case.resolve() call, cut-pasted verbatim out of this
	# method's old inline body). The single legal resolve() call site this
	# criterion guards against a second (Strike-after-Stride) call site now
	# therefore lives in _execute_ai_plan(), reached from advance_ai_turn(),
	# rather than inline in advance_ai_turn() itself -- so this check spans
	# BOTH function bodies (the whole advance_ai_turn()->_execute_ai_plan()
	# call chain this criterion actually cares about), not just the former's
	# textual body.
	var file := FileAccess.open("res://core/application/round_session.gd", FileAccess.READ)
	assert_not_null(file, "core/application/round_session.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var advance_fn_start: int = content.find("func advance_ai_turn(")
	assert_true(advance_fn_start >= 0, "fixture assumption: advance_ai_turn() must exist")
	var advance_next_fn_start: int = content.find("\nfunc ", advance_fn_start + 1)
	var advance_fn_body: String = content.substr(advance_fn_start, advance_next_fn_start - advance_fn_start)

	var execute_fn_start: int = content.find("func _execute_ai_plan(")
	assert_true(execute_fn_start >= 0, "fixture assumption: _execute_ai_plan() must exist")
	var execute_next_fn_start: int = content.find("\nfunc ", execute_fn_start + 1)
	var execute_fn_body: String = content.substr(execute_fn_start, execute_next_fn_start - execute_fn_start)

	var combined_body: String = advance_fn_body + execute_fn_body

	assert_false(
		combined_body.contains("will_strike"),
		"advance_ai_turn()/_execute_ai_plan() must no longer reference will_strike -- the composite Stride-then-Strike handling must be fully removed"
	)
	assert_eq(
		combined_body.count("_resolve_action_use_case.resolve("), 1,
		"advance_ai_turn()'s dispatch chain must call resolve_action_use_case.resolve() at most once per turn -- no second (Strike-after-Stride) call site may remain"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: under a pinned seed, Stride tie-breaks are deterministic
# (stable lowest-(q,r) selection) across repeated runs.
# ══════════════════════════════════════════════════════════════════════════

func test_stride_tie_break_is_deterministic_under_a_pinned_seed_across_repeated_runs() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, "4242")

	var origin_hex = HexCoordClass.new(0, 0)
	# (1, 4) is chosen so multiple legal Stride destinations tie for the
	# minimum hex_distance -- (0, 4) and (1, 3) both land exactly
	# hex_distance 1 from (1, 4) -- genuinely exercising the tie-break.
	var target_hex = HexCoordClass.new(1, 4)

	var candidates: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [])
	var expected_destination = null
	var expected_distance: int = -1
	for candidate in candidates:
		var distance: int = HexMathClass.hex_distance(candidate, target_hex)
		var is_better: bool = expected_destination == null or distance < expected_distance
		var is_tie_and_lower: bool = (
			expected_destination != null and distance == expected_distance
			and _is_lower_coord(candidate, expected_destination)
		)
		if is_better or is_tie_and_lower:
			expected_destination = candidate
			expected_distance = distance
	assert_not_null(expected_destination, "fixture assumption: an expected winning destination must be derivable")

	var tied_count: int = 0
	for candidate in candidates:
		if HexMathClass.hex_distance(candidate, target_hex) == expected_distance:
			tied_count += 1
	assert_true(tied_count >= 2, "fixture assumption: at least two destinations must tie, to genuinely exercise the tie-break")

	var chosen_destinations: Array = []
	for i in range(10):
		var ai = AIClass.new()
		var combatant = _melee_combatant(HexCoordClass.new(origin_hex.q, origin_hex.r))
		var target = _target("Titus", HexCoordClass.new(target_hex.q, target_hex.r))
		var action_economy = ActionEconomyClass.new()
		action_economy.start_of_turn()

		var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])
		assert_eq(result.get("action_type", ""), "Stride", "iteration %d: fixture assumption: the out-of-reach target must trigger a Stride" % i)
		var destination = result.get("destination", null)
		assert_not_null(destination, "iteration %d: a Stride decision must carry a non-null destination" % i)
		chosen_destinations.append(destination)

	for i in range(chosen_destinations.size()):
		assert_true(
			chosen_destinations[i].equals(expected_destination),
			"iteration %d: the chosen Stride destination (%s) must match the independently-derived stable lowest-(q,r) winner (%s) under the pinned seed, every single run" % [i, chosen_destinations[i], expected_destination]
		)


func _is_lower_coord(a, b) -> bool:
	if a.q != b.q:
		return a.q < b.q
	return a.r < b.r


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: advance_ai_turn() results in exactly one spend_action() call
# per AI turn (verified via an ActionEconomy spy).
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_spends_exactly_one_action_when_target_already_in_reach() -> void:
	var goblin = _melee_combatant(HexCoordClass.new(0, 0))
	goblin.is_enemy = true
	var titus = _target("Titus", HexCoordClass.new(1, 0), 200)  # adjacent -- in reach
	titus.is_enemy = false

	var goblin_action_economy = SpyActionEconomy.new()
	var entries: Array = [_entry(goblin, goblin_action_economy), _entry(titus)]

	# raw=12 -> roll_total = 12 + strength(2) + proficiency(1) = 15 vs ac=14 -> hit;
	# damage raw=4 -> 4 + 2 = 6 damage.
	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().name, "Skeleton")
	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_eq(
		goblin_action_economy.spend_action_call_count, 1,
		"advance_ai_turn() must trigger exactly one spend_action() call on the acting combatant's ActionEconomy this turn (Strike-in-reach case)"
	)


func test_advance_ai_turn_spends_exactly_one_action_when_target_out_of_reach() -> void:
	var goblin = _melee_combatant(HexCoordClass.new(0, 0))
	goblin.is_enemy = true
	# Out of reach, but a single Speed-4 Stride closes it fully into melee
	# reach -- the scenario the removed FEAT-005 composite used to spend a
	# SECOND (rejected) spend_action() call for.
	var titus = _target("Titus", HexCoordClass.new(4, 0), 200)
	titus.is_enemy = false

	var goblin_action_economy = SpyActionEconomy.new()
	var entries: Array = [_entry(goblin, goblin_action_economy), _entry(titus)]

	var random_number_port = ScriptedRandomNumberPort.new([12, 4])
	var rig: Dictionary = _make_use_case(entries, random_number_port)
	var session = rig["use_case"].begin_round(1, [titus], [goblin])

	assert_eq(session.current_actor().name, "Skeleton")
	var result: Dictionary = session.advance_ai_turn()

	assert_true(result.get("ok", false))
	assert_true(
		HexMathClass.hex_distance(goblin["hex_coord"], titus["hex_coord"]) <= 1,
		"fixture assumption: the enemy must have Strode into melee reach of the target this turn"
	)
	assert_eq(
		goblin_action_economy.spend_action_call_count, 1,
		"advance_ai_turn() must trigger exactly one spend_action() call on the acting combatant's ActionEconomy this turn (Stride case) -- no second, rejected spend_action() attempt for a same-turn Strike"
	)
	assert_eq(rig["history"].entries.size(), 0, "no Strike may resolve in the same turn as the Stride")
