extends GutTest
## tests/integration/test_ai_decide_action_opportunistic_strike_trigger.gd —
## FEAT-233 (US-005, resolves DEF-001's remaining coverage gap, depends on
## FIX-001).
##
## FR-005's exit criterion ("a Stride by either side" can trigger an
## OpportunisticStrike window) has TWO legs. Every existing test that drives
## the ENEMY-mover leg (tests/e2e/test_reactions_fully_live.gd's "LEG B",
## tests/integration/test_opportunistic_strike_ranged_reactor_excluded.gd)
## calls `MainScene._resolve_enemy_stride_opportunistic_window()` DIRECTLY —
## bypassing core/combat/ai.gd's own `decide_action()`/
## `set_stride_reaction_resolver_fn()` seam entirely (see
## test_reactions_fully_live.gd's own file-level doc: in this project's
## single-enemy/single-party prologue fixture, `_select_target()`'s
## nearest-living-target rule makes it structurally impossible for
## `decide_action()` to organically issue a Stride toward an out-of-reach
## target while ALSO having that SAME target be an eligible (adjacent)
## OpportunisticStrike reactor — the two conditions are mutually exclusive
## for the single hostile combatant the prologue fixture supplies as
## `decide_action()`'s `targets` argument). No test anywhere in this
## codebase has ever driven a Stride THROUGH `decide_action()` itself with a
## genuinely eligible candidate reactor present, so the actual
## `await _stride_reaction_resolver_fn.call(...)` line inside
## core/combat/ai.gd's `_stride_toward_target()` — and its FEAT-008
## `"mover_downed"` read — has never been organically exercised end-to-end.
##
## This suite closes that gap using the SAME construction
## tests/unit/core/combat/test_ai_stride_then_strike.gd / tests/integration/
## test_ai_token_reposition.gd already establish (hand-built combatant
## Dictionaries + a REAL, directly-`.new()`-constructed core/combat/ai.gd AI
## instance — this project's own established pattern for exercising
## `decide_action()` as a genuine public entry point, distinct from booting
## the full res://MainScene.tscn scene tree, which this exact scenario
## cannot reach): `decide_action()`'s own documented `other_combatants`
## parameter ("every OTHER combatant on the battlefield ... besides
## `combatant` and `targets`") is populated with a SEPARATE, living, hostile,
## melee-armed combatant standing adjacent to the mover's START hex — never
## part of `targets` (so `_select_target()`'s nearest-living-target search
## never considers it, and it can never usurp the mover's actual, distant,
## out-of-reach chosen target) — while `targets` itself carries only the
## genuinely far-away target that forces the Stride. This is a legitimate
## reading of `decide_action()`'s own contract, not a fabricated shortcut:
## core/application/round_session.gd's `_decide_ai_action()` already proves
## `other_combatants` is a caller-supplied, non-target-selection-affecting
## occupancy list (it populates it from the mover's OWN allies for the
## exact same reason) — this suite simply supplies a hostile occupant
## instead, which `decide_action()`'s own signature never forbids.
##
## The resolver Callable itself wires the SAME REAL production collaborators
## resolve_stride_use_case.gd's own doc describes (a REAL
## core/application/use_cases/resolve_stride_use_case.gd ResolveStrideUseCase,
## a REAL core/application/resolve_action_use_case.gd ResolveActionUseCase
## backed by a REAL seeded RNG port) — only the OUTERMOST reactor-chooser
## Callable (standing in for whichever ReactionChooserPort/pop-up a real
## composition root would route to) is a lightweight spy, mirroring
## tests/integration/test_ai_token_reposition.gd's own FakeEventSinkPort/
## FakeRoundHistoryPort convention for peripheral collaborators while every
## CORE domain/application class stays real and unmodified.
##
## Verifies (test_criteria):
##   test_enemy_mover_stride_via_ai_decide_action_organically_triggers_opportunistic_strike_window
##   passes: `decide_action()` — driven as a genuine public entry point, not
##   a hand-invoked internal method — organically Strides the enemy mover
##   toward its out-of-reach target AND, strictly BEFORE that Stride commits
##   (core/rules/movement.gd's Movement.stride() is never reached until
##   AFTER the resolver is awaited to completion), genuinely offers and
##   resolves a real OpportunisticStrike window for the ONE eligible
##   (adjacent/hostile/melee) candidate reactor — never for the far-away
##   chosen target itself, which is correctly filtered out.

const AIClass                      = preload("res://core/combat/ai.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const ResolveStrideUseCaseClass    = preload("res://core/application/use_cases/resolve_stride_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")


# ── Fake/double port implementations for the PERIPHERAL collaborators only
# (mirrors tests/integration/test_ai_token_reposition.gd's identically-named
# helpers) -- ResolveStrideUseCase/ResolveActionUseCase/ActionEconomy/AI
# themselves are all real, unmodified production classes. ───────────────────

class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var log: Array = []

	func emit(event) -> void:
		log.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


# ── Spy state for the resolver seam under test -- reset per test. ──────────

var _resolver_invocation_count: int = 0
var _resolver_received_candidate_reactor_ids: Array = []
var _resolver_mover_hex_snapshot_at_invocation: Array = []
var _last_stride_reaction_result: Dictionary = {}

var _reactor_reaction_calls: Array = []
var _reactor_economy_map: Dictionary = {}

var _resolve_stride_use_case
var _strike_use_case


func _skeleton(hex_coord) -> Dictionary:
	return {
		"name": "Skeleton", "combatant_id": "skeleton", "hp_current": 500, "hp_max": 500,
		"ac": -1000, "strength": 2, "hex_coord": hex_coord, "_is_enemy": true,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6},
	}


func _titus_far(hex_coord) -> Dictionary:
	return {
		"name": "Titus", "combatant_id": "titus", "hp_current": 20, "ac": 14,
		"strength": 5, "hex_coord": hex_coord, "_is_enemy": false,
	}


## _reactor_adjacent(hex_coord) -> Dictionary -- a SEPARATE living, hostile,
## melee-armed party combatant (never `targets` itself) standing adjacent to
## the mover's start hex -- see this file's header doc for why this is the
## only organically-reachable way to pair a Stride with a genuinely eligible
## OpportunisticStrike candidate.
func _reactor_adjacent(hex_coord) -> Dictionary:
	return {
		"name": "Aldric", "combatant_id": "aldric", "hp_current": 20, "ac": 14,
		"strength": 3, "hex_coord": hex_coord, "_is_enemy": false,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 3, "damage_die": 6, "parry_bonus": 4, "block_value": 1},
	}


func _reactor_spent_fn(reactor: Dictionary) -> bool:
	var ae = _reactor_economy_map.get(reactor.get("combatant_id", ""), null)
	return ae.is_spent() if ae != null else false


func _reactor_action_economy_fn(reactor: Dictionary):
	return _reactor_economy_map.get(reactor.get("combatant_id", ""), null)


## _reactor_chooser_fn(reactor, context) -> Dictionary -- the ONLY spied
## collaborator: stands in for whichever real ReactionChooserPort/pop-up a
## composition root would route to, recording every call it receives so this
## suite can assert exactly which candidate(s) were genuinely offered a
## window, then always answers "opportunistic_strike" (a real, resolved
## choice, never a no-op).
func _reactor_chooser_fn(reactor: Dictionary, context: Dictionary) -> Dictionary:
	_reactor_reaction_calls.append({"reactor_id": reactor.get("combatant_id", ""), "context": context})
	return {"choice": "opportunistic_strike"}


## _wrapped_stride_reaction_resolver(mover, mover_start_hex, candidate_reactors)
## -- the Callable bound onto the REAL AI instance's
## set_stride_reaction_resolver_fn() seam. Records that it was genuinely
## invoked (and with what args/mover-position snapshot) BEFORE delegating to a
## REAL ResolveStrideUseCase.execute() wired with a REAL ResolveActionUseCase
## as its strike_use_case -- exactly mirroring MainScene.gd's own
## _resolve_enemy_stride_opportunistic_window()/reaction_controller.gd's
## resolve_enemy_stride_opportunistic_window() production shape.
func _wrapped_stride_reaction_resolver(mover: Dictionary, mover_start_hex, candidate_reactors: Array) -> Dictionary:
	_resolver_invocation_count += 1
	for reactor in candidate_reactors:
		_resolver_received_candidate_reactor_ids.append(reactor.get("combatant_id", ""))
	var live_mover_hex = mover.get("hex_coord")
	_resolver_mover_hex_snapshot_at_invocation = [live_mover_hex.q, live_mover_hex.r]

	_last_stride_reaction_result = await _resolve_stride_use_case.execute(
		mover, mover_start_hex, candidate_reactors,
		Callable(self, "_reactor_spent_fn"),
		Callable(self, "_reactor_chooser_fn"),
		_strike_use_case,
		Callable(self, "_reactor_action_economy_fn"),
		1, 0
	)
	return _last_stride_reaction_result


# ══════════════════════════════════════════════════════════════════════════
# The criterion: decide_action() -- called as a genuine public entry point,
# never a hand-invoked internal seam method -- organically Strides the enemy
# mover AND genuinely offers/resolves a real OpportunisticStrike window for
# the one eligible adjacent reactor, strictly before the Stride commits.
# ══════════════════════════════════════════════════════════════════════════

func test_enemy_mover_stride_via_ai_decide_action_organically_triggers_opportunistic_strike_window() -> void:
	_resolver_invocation_count = 0
	_resolver_received_candidate_reactor_ids = []
	_resolver_mover_hex_snapshot_at_invocation = []
	_last_stride_reaction_result = {}
	_reactor_reaction_calls = []

	var origin_hex = HexCoordClass.new(0, 0)
	var far_target_hex = HexCoordClass.new(9, 0)  # beyond a single Speed-4 Stride's reach -- mirrors this codebase's established convention (tests/integration/test_ai_token_reposition.gd)
	var reactor_hex = HexMathClass.hex_neighbors(origin_hex)[0]  # adjacent to the mover's START hex

	var skeleton: Dictionary = _skeleton(origin_hex)
	var titus: Dictionary = _titus_far(far_target_hex)
	var reactor: Dictionary = _reactor_adjacent(reactor_hex)

	var skeleton_action_economy = ActionEconomyClass.new()
	skeleton_action_economy.start_of_turn()

	var reactor_action_economy = ActionEconomyClass.new()
	reactor_action_economy.start_of_turn()
	_reactor_economy_map = {"aldric": reactor_action_economy}

	var event_sink = FakeEventSinkPort.new()
	var round_history = FakeRoundHistoryPort.new()
	var random_port = SeededRandomAdapterClass.new(7)
	_strike_use_case = ResolveActionUseCaseClass.new(random_port, event_sink, round_history)
	_resolve_stride_use_case = ResolveStrideUseCaseClass.new()

	var ai = AIClass.new()
	ai.set_stride_reaction_resolver_fn(Callable(self, "_wrapped_stride_reaction_resolver"))

	var skeleton_hp_before: int = skeleton.get("hp_current")
	var reactor_budget_before: int = reactor_action_economy.get_remaining()

	var decision: Dictionary = await ai.decide_action(skeleton, [titus], skeleton_action_economy, [reactor])

	# ── The organic seam genuinely fired -- exactly once, with the SAME
	# occupancy (targets + other_combatants) ai.gd's own _stride_toward_target()
	# documents passing through. ─────────────────────────────────────────────
	assert_eq(_resolver_invocation_count, 1, "decide_action()'s own Stride path must genuinely await the injected _stride_reaction_resolver_fn exactly once")
	assert_eq(_resolver_received_candidate_reactor_ids.size(), 2, "the resolver must receive targets+other_combatants (Titus + Aldric) as candidate reactors")
	assert_true(_resolver_received_candidate_reactor_ids.has("aldric"), "Aldric (the adjacent reactor) must be among the candidates the organic seam forwarded")
	assert_true(_resolver_received_candidate_reactor_ids.has("titus"), "Titus (the far, out-of-reach chosen target) must still be forwarded as a candidate -- eligibility filtering happens downstream, never at this call site")

	# ── Ordering: the resolver was awaited BEFORE the mover's own hex_coord
	# changed -- Movement.stride() is the sole hex_coord mutation point, and it
	# runs strictly AFTER this awaited call in core/combat/ai.gd's own source. ──
	assert_eq(_resolver_mover_hex_snapshot_at_invocation, [origin_hex.q, origin_hex.r], "the mover's hex_coord must be UNCHANGED at the moment the organic resolver call fires")

	# ── The mover organically Strode (a real Movement.stride() commit
	# happened AFTER the reaction genuinely resolved). ───────────────────────
	assert_eq(decision.get("action_type", ""), "Stride", "the enemy AI must organically issue a Stride toward its out-of-reach target")
	assert_false(decision.get("will_strike", true), "FEAT-007: a Stride decision never also reports will_strike true")
	assert_not_null(decision.get("destination", null), "a Stride decision must carry a non-null destination")
	assert_false(skeleton["hex_coord"].equals(origin_hex), "the mover must have actually relocated once the Stride committed")
	assert_true(skeleton["hex_coord"].equals(decision.get("destination")), "the mover's live hex_coord must equal the committed Stride destination")

	# ── Titus (out of reach, therefore NOT adjacent to the mover's start hex)
	# must never have been offered a window -- only the genuinely eligible
	# Aldric was. ─────────────────────────────────────────────────────────────
	assert_eq(_reactor_reaction_calls.size(), 1, "exactly one candidate (Aldric -- adjacent, hostile, melee, unspent) may ever be offered a real OpportunisticStrike window")
	assert_eq(_reactor_reaction_calls[0]["reactor_id"], "aldric", "the far, out-of-reach Titus must never be offered a window -- OpportunisticStrikeEligibility correctly filters him out")

	# ── The 'opportunistic_strike' choice genuinely RESOLVED a real Strike
	# (never merely recorded with no effect) -- real damage, real reaction
	# spend, both driven through the REAL ResolveActionUseCase/ActionEconomy. ──
	var reactions: Array = _last_stride_reaction_result.get("reactions", [])
	assert_eq(reactions.size(), 1, "exactly one reaction must have been recorded")
	var strike_result: Dictionary = reactions[0].get("strike_result", {})
	assert_true(strike_result.get("resolved", false), "an 'opportunistic_strike' choice organically driven through decide_action() must FULLY resolve a real Strike")
	assert_true(strike_result.get("ok", false), "the resolved Strike must succeed")
	assert_false(strike_result.get("target_defeated", true), "fixture assumption: the mover's overwhelming hp must survive this single Strike")
	assert_true(strike_result.get("damage_final", 0) > 0, "the guaranteed-hit Strike must apply real, positive damage")

	assert_eq(skeleton.get("hp_current"), skeleton_hp_before - strike_result.get("damage_final"), "the mover's own hp_current must drop by EXACTLY the resolved Strike's damage")

	assert_eq(
		reactor_action_economy.get_remaining(), reactor_budget_before - 1,
		"the reactor's own live ActionEconomy budget must drop by exactly 1 -- paid via spend_reaction(), never a second spend_action()"
	)

	assert_false(_last_stride_reaction_result.get("mover_downed", true), "the mover must not be downed by its own survivable-hp fixture")
	assert_true(_last_stride_reaction_result.get("stride_should_commit", false), "a non-lethal Opportunistic Strike must leave the Stride free to commit")
