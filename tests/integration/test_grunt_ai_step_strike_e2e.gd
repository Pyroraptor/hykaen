extends GutTest
## tests/integration/test_grunt_ai_step_strike_e2e.gd — FEAT-402 (US-011 /
## FR-019 part 2): the steel thread's own EXIT-POINT capstone test.
##
## Builds a Skeleton combatant via the REAL infrastructure/combatant_factory.gd
## CombatantFactory (reading the REAL data/enemies/skeleton.tres, no mocked
## ResourceLoader), then overrides its authored ai_tier ('mindless',
## skeleton.tres's own default) to 'grunt' — exactly the US-011 override
## scenario the design notes describe — and wires it through the REAL
## composition root: RunRoundUseCase.begin_round() (core/application/
## run_round_use_case.gd) calls the REAL, un-doubled AITierRegistry
## (core/combat/ai_tier_registry.gd) to resolve 'grunt' -> a genuine GruntAI
## instance (core/combat/grunt_ai.gd), stored on the entry as
## entry['ai_planner'] per FEAT-401. A single real advance_ai_turn() call
## (core/application/round_session.gd) is then exercised — no mocks anywhere
## on the dispatch path (_decide_ai_action() -> GruntAI.plan_turn() ->
## _execute_ai_plan() -> Movement.step() + the existing frozen
## reaction-window/two-phase-commit Strike resolution logic).
##
## The full steel-thread trace this test proves, end-to-end, in ONE
## advance_ai_turn() call:
##   data (.tres ai_tier, overridden) -> business_logic (GruntAI/
##   AITierRegistry) -> infrastructure (CombatantFactory) -> api (RoundSession
##   dispatch/execute) -> presentation (composition-root wiring,
##   RunRoundUseCase.begin_round()).
##
## Fixture geometry: the skeleton starts hex_distance 2 from the party member
## (a 1-hex gap) — GruntAI's own documented Step-then-Strike branch
## (core/combat/grunt_ai.gd's file-level doc, item 4) — so a single
## advance_ai_turn() call must Step to the nearest legal adjacent hex, THEN
## attempt a Strike against the now-adjacent party member, both within that
## one call.
##
## Verifies (this feature's test_criteria):
##   1. The skeleton's overridden ai_tier='grunt' resolves to a REAL GruntAI
##      instance via the real composition-root wiring (entries[0]['ai_planner'],
##      RunRoundUseCase.begin_round()) — AITierRegistry itself is never
##      doubled/mocked.
##   2. After one advance_ai_turn() call, the skeleton's token hex position has
##      changed to the hex adjacent to the party member (Step executed), and
##      the Step spent NO action-economy budget of its own.
##   3. A Strike resolution was attempted against the party member within that
##      SAME advance_ai_turn() call (the reaction-window/two-phase-commit
##      dispatch path — resolve_action_use_case.resolve() — was entered).
##   4. any_action_taken == true and no WAIT was recorded for this turn.
##   5. Runs headless via GUT alongside the full regression suite.

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass               = preload("res://core/domain/combatant.gd")
const CombatantFactoryClass        = preload("res://infrastructure/combatant_factory.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const GruntAIClass                 = preload("res://core/combat/grunt_ai.gd")
const RoundEventsClass             = preload("res://core/rules/round_events.gd")

const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"


# ── Fake/double port implementations (mirrors tests/unit/application/
#    test_composition_root_ai_planner_wiring.gd's identically-named doubles —
#    these stand in ONLY for the outer TurnOrderPort/EventSinkPort/
#    RoundHistoryPort/session-level-fallback AIDecisionPort seams;
#    AITierRegistry/GruntAI/RoundSession/RunRoundUseCase/CombatantFactory are
#    ALL real, un-doubled production classes). ──────────────────────────────

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


## FakeAIDecisionPort2Arg — the pre-existing legacy AIDecisionPort shape (no
## plan_turn method). Wired as RunRoundUseCase's REQUIRED session-level
## fallback port, but never actually consulted for the skeleton's turn: once
## begin_round() wires entries[0]['ai_planner'] to a real GruntAI instance,
## RoundSession._decide_ai_action()'s entry-level-overrides-session-level
## precedence rule (FEAT-401) means this double's decide_action() is never
## called — see test_grunt_ai_ai_planner_never_falls_back_to_session_port()
## below, which asserts exactly that.
class FakeAIDecisionPort2Arg:
	extends "res://core/application/ai_decision_port.gd"

	var decide_action_calls: int = 0

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		decide_action_calls += 1
		return {"action_type": "", "target": null}


## GruntTierCombatant — a minimal, test-local Combatant subclass that adds an
## `ai_tier` property. core/domain/combatant.gd's REAL Combatant entity does
## not (yet) carry an ai_tier field across its from_dict()/to_dict() round
## trip (see core/application/run_round_use_case.gd's own FEAT-401 doc on
## `_read_ai_tier_if_present()`), so a plain `CombatantClass.from_dict()`
## instance has nowhere to durably carry the overridden tier for the
## composition root to read. This subclass exists SOLELY to give a real,
## fully-populated Combatant (built from CombatantFactory's own production
## output) a place to carry that tier — it introduces no new behavior of its
## own and is never substituted for AITierRegistry, GruntAI, or any other
## part of the actual dispatch path.
class GruntTierCombatant:
	extends "res://core/domain/combatant.gd"

	var ai_tier: String = ""


## _with_ai_tier(base, tier) -> GruntTierCombatant — copies every declared
## Combatant field off `base` (a real Combatant instance) onto a fresh
## GruntTierCombatant, then stamps `ai_tier`. A generic property-list copy
## (rather than a hand-maintained field list) so this test-local helper can
## never silently drift out of sync with core/domain/combatant.gd's own,
## separately-evolving field set.
func _with_ai_tier(base, tier: String) -> GruntTierCombatant:
	var wrapped := GruntTierCombatant.new()
	for prop in base.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			wrapped.set(prop["name"], base.get(prop["name"]))
	wrapped.ai_tier = tier
	return wrapped


## _build_session() -> Dictionary — assembles the full REAL composition root
## (RunRoundUseCase + RoundSession + ResolveActionUseCase +
## DetermineOutcomeUseCase, all real production classes) around a Titus party
## member (hex 0,0) and a Skeleton enemy (hex 2,0 — hex_distance 2, a 1-hex
## gap) built via the REAL CombatantFactory.build_enemy_combatant() reading
## the REAL data/enemies/skeleton.tres. The skeleton's authored ai_tier
## ('mindless') is overridden to 'grunt' (US-011) before entries are wired.
## Returns {} (with a failure already asserted) if the real resource load
## itself fails — callers must check `.is_empty()`.
func _build_session() -> Dictionary:
	var titus_hex := HexCoordClass.new(0, 0)
	var skeleton_hex := HexCoordClass.new(2, 0)

	var titus := CombatantClass.from_dict({
		"name": "Titus", "combatant_id": "titus", "team": "Player", "_is_enemy": false,
		"hp_current": 20, "hp_max": 20, "ac": 14, "fortitude": 12, "reflex": 12, "will": 12,
		"strength": 3, "dexterity": 2, "intuition": 2,
		"hex_coord": titus_hex,
		"weapon": {"damage_modifier_attribute": "strength", "proficiency_bonus": 2, "damage_die": 6},
	})

	var factory := CombatantFactoryClass.new()
	var built: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, skeleton_hex, "skeleton_e2e")
	assert_false(built.has("error"), "CombatantFactory.build_enemy_combatant() must succeed against the real skeleton.tres fixture; got: %s" % str(built))
	if built.has("error"):
		return {}

	assert_eq(
		built.get("ai_tier", ""), "mindless",
		"fixture assumption: skeleton.tres authors ai_tier='mindless' by default — this test overrides it to 'grunt' below (US-011)"
	)
	built["ai_tier"] = "grunt"

	var skeleton := _with_ai_tier(CombatantClass.from_dict(built), "grunt")
	# CombatantFactory.build_enemy_combatant() emits no "_is_enemy"/"team" key
	# of its own (see infrastructure/combatant_factory.gd) — in real play,
	# core/combat/encounter.gd's initialize() is the seam that stamps
	# combatant.is_enemy = true/false onto every party/enemy Combatant AFTER
	# construction. This test builds entries directly (no Encounter object),
	# so it must reproduce that SAME stamping step here.
	skeleton.is_enemy = true

	var skeleton_action_economy := ActionEconomyClass.new()
	var titus_action_economy := ActionEconomyClass.new()
	var entries: Array = [
		{"combatant": skeleton, "action_economy": skeleton_action_economy},
		{"combatant": titus,    "action_economy": titus_action_economy},
	]

	var turn_order_port    := FakeTurnOrderPort.new(entries)
	var event_sink_port    := FakeEventSinkPort.new()
	var round_history_port := FakeRoundHistoryPort.new()
	var random_number_port := SeededRandomAdapterClass.new(7)

	var resolve_action_use_case := ResolveActionUseCaseClass.new(random_number_port, event_sink_port, round_history_port)
	var determine_outcome_use_case := DetermineOutcomeUseCaseClass.new()
	var ai_decision_port := FakeAIDecisionPort2Arg.new()

	var run_round_use_case := RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	# THE composition root: real AITierRegistry.get_planner('grunt') is called
	# here, inside begin_round() (core/application/run_round_use_case.gd) —
	# never substituted.
	var session = run_round_use_case.begin_round(1, [titus], [skeleton])

	return {
		"session": session,
		"entries": entries,
		"skeleton": skeleton,
		"titus": titus,
		"skeleton_action_economy": skeleton_action_economy,
		"event_sink_port": event_sink_port,
		"round_history_port": round_history_port,
		"ai_decision_port": ai_decision_port,
	}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — the overridden ai_tier='grunt' resolves to a REAL GruntAI
# instance via the real composition-root wiring; AITierRegistry is never
# doubled.
# ══════════════════════════════════════════════════════════════════════════

func test_grunt_tier_override_resolves_to_real_grunt_ai_via_composition_root() -> void:
	var rig: Dictionary = _build_session()
	if rig.is_empty():
		return

	var entries: Array = rig["entries"]
	assert_true(entries[0].has("ai_planner"), "begin_round() must wire an 'ai_planner' entry for the grunt-tier skeleton")
	assert_true(
		is_instance_of(entries[0]["ai_planner"], GruntAIClass),
		"the overridden ai_tier='grunt' must resolve to a REAL GruntAI instance via AITierRegistry.get_planner(), not a test double"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criteria 2-4 — one real advance_ai_turn() call: Step to the adjacent hex
# (free of action-economy spend), THEN an attempted Strike against Titus,
# any_action_taken == true, no WAIT recorded.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_steps_then_strikes_within_one_call() -> void:
	var rig: Dictionary = _build_session()
	if rig.is_empty():
		return

	var session          = rig["session"]
	var skeleton          = rig["skeleton"]
	var titus             = rig["titus"]
	var skeleton_action_economy = rig["skeleton_action_economy"]
	var event_sink_port    = rig["event_sink_port"]
	var round_history_port = rig["round_history_port"]
	var ai_decision_port    = rig["ai_decision_port"]

	assert_eq(session.current_actor(), skeleton, "fixture assumption: the skeleton (Enemy) must be the first actionable entry")

	var skeleton_hex_before = skeleton.hex_coord
	assert_eq(
		HexMathClass.hex_distance(skeleton_hex_before, titus.hex_coord), 2,
		"fixture assumption: the skeleton starts a 1-hex gap (hex_distance 2) from Titus — GruntAI's Step-then-Strike branch"
	)

	var result: Dictionary = await session.advance_ai_turn()
	assert_true(result.get("ok", false), "advance_ai_turn() must resolve successfully")

	# ── Criterion 1 (re-verified against the SAME session that actually acted) ──
	assert_true(
		is_instance_of(rig["entries"][0]["ai_planner"], GruntAIClass),
		"the acting entry's ai_planner must still be the real GruntAI instance at the moment advance_ai_turn() ran"
	)

	# ── Criterion 2 — Step executed: hex changed to the one adjacent to Titus,
	# and the Step itself spent no action-economy budget of its own (Step is
	# dispatched via Movement.step() WITHOUT an action_economy argument —
	# core/application/round_session.gd's _execute_ai_plan() "Step" case). ──
	assert_false(
		skeleton.hex_coord.equals(skeleton_hex_before),
		"the skeleton's hex_coord must change — a Step must have executed"
	)
	assert_true(
		skeleton.hex_coord.equals(HexCoordClass.new(1, 0)),
		"the skeleton must Step to (1,0) — the legal Step destination nearest Titus"
	)
	assert_eq(
		HexMathClass.hex_distance(skeleton.hex_coord, titus.hex_coord), 1,
		"after the Step, the skeleton's hex must be adjacent (hex_distance 1) to Titus"
	)

	# ── Criterion 3 — a Strike resolution was attempted against Titus within
	# THIS SAME advance_ai_turn() call (the reaction-window/two-phase-commit
	# dispatch path — resolve_action_use_case.resolve() — was entered and
	# recorded a history entry + emitted an AttackBroadcast). A Step alone
	# never appends round history or emits an AttackBroadcast, so this is
	# conclusive proof a Strike (not merely a Step) was attempted. ──
	assert_eq(
		round_history_port.entries.size(), 1,
		"exactly one resolved action (the Strike attempt) must be recorded this turn"
	)
	var strike_entry: Dictionary = round_history_port.entries[0]
	assert_eq(strike_entry.get("action", ""), "Strike", "the recorded action must be a Strike attempt")
	assert_eq(strike_entry.get("attacker", null).name, "Skeleton", "the Strike's attacker must be the Skeleton")
	assert_eq(strike_entry.get("target", null).name, "Titus", "the Strike's target must be Titus")

	var attack_events: Array = []
	for event in event_sink_port.events:
		if event is RoundEventsClass.AttackBroadcast:
			attack_events.append(event)
	assert_eq(attack_events.size(), 1, "exactly one AttackBroadcast must be emitted — the attempted Strike against Titus")
	if attack_events.size() == 1:
		assert_eq(attack_events[0].attacker_name, "Skeleton")
		assert_eq(attack_events[0].target_name, "Titus")

	# ── Criterion 4 — any_action_taken == true and no WAIT was recorded for
	# this turn. RoundSession never exposes any_action_taken/WAIT flags
	# directly on advance_ai_turn()'s return value, so this is proven via the
	# observable side effects a WAIT could never produce: WAIT
	# (core/rules/actions.gd Actions.resolve_wait()) never moves a token and
	# never appends a round-history entry — both of which are already proven
	# above — and, like every resolvable action, spends exactly ONE of the
	# skeleton's 7 per-round actions (the Strike; the Step was free). ──
	assert_eq(
		skeleton_action_economy.get_remaining(), ActionEconomyClass.MAX_BUDGET - 1,
		"exactly one action (the Strike) must be spent this turn — the Step must be free of action-economy spend"
	)

	# The session-level legacy AIDecisionPort must never be consulted once the
	# entry-level GruntAI planner is wired (FEAT-401 precedence rule) —
	# confirms the dispatch genuinely went through GruntAI.plan_turn(), not a
	# fallback path.
	assert_eq(
		ai_decision_port.decide_action_calls, 0,
		"the session-level legacy AIDecisionPort must never be consulted once entries[0]['ai_planner'] (GruntAI) is wired"
	)
