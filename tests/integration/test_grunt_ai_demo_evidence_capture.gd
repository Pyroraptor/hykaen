extends GutTest
## tests/integration/test_grunt_ai_demo_evidence_capture.gd — FEAT-406
## (US-011; resolves FINDING-007, mitigates RISK-007).
##
## Replaces the unrecorded, manual "run full demo scenario and confirm
## observable behavior" task from US-011 with a reproducible,
## headless-runnable GUT integration test. Drives the SAME real
## composition-root/RoundSession path tests/integration/
## test_grunt_ai_step_strike_e2e.gd already exercises end-to-end
## (data/enemies/skeleton.tres -> infrastructure/combatant_factory.gd's
## CombatantFactory -> core/combat/ai_tier_registry.gd's AITierRegistry ->
## RoundSession entries[0]['ai_planner'] -> core/combat/grunt_ai.gd's
## GruntAI.plan_turn() -> RoundSession._execute_ai_plan()'s real Step +
## frozen two-phase-commit Strike resolution) — no mocks anywhere on that
## dispatch path — and additionally writes a structured evidence log via
## core/tooling/demo_evidence_writer.gd's DemoEvidenceWriter to a fixed
## artifact path, then RE-READS that log from disk and asserts its
## contents match what this test itself observed in-process (so the
## artifact can never be silently stale/mismatched evidence).
##
## Fixture geometry mirrors test_grunt_ai_step_strike_e2e.gd exactly: the
## skeleton starts hex_distance 2 from the party member (a 1-hex gap), so
## GruntAI's plan_turn() must return the ordered two-item
## [Step, Strike] plan (core/combat/grunt_ai.gd's file-level doc, item 4).
##
## Verifies (this feature's test_criteria):
##   1. Running the test produces an evidence log file at the documented
##      fixed artifact path (DemoEvidenceWriter.ARTIFACT_PATH).
##   2. That log contains the skeleton's starting token hex, ending token
##      hex, the ordered action plan executed (Step then Strike), and the
##      Strike resolution outcome (target id, hit/miss).
##   3. Re-parsing the written log yields all required keys with values
##      consistent with the in-test observed state.
##   4. No mocks on the core dispatch path: CombatantFactory ->
##      AITierRegistry -> RoundSession entries[0]['ai_planner'] are all
##      real, un-doubled production classes, matching the existing
##      steel-thread E2E test's wiring.
##   5. Runs headless via the existing GUT runner alongside the full
##      regression suite (this file lives under res://tests, already
##      scoped by both tests/.gutconfig.json and the root .gutconfig.json).

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
const DemoEvidenceWriterClass      = preload("res://core/tooling/demo_evidence_writer.gd")

const SKELETON_PATH: String = "res://data/enemies/skeleton.tres"
const ARTIFACT_PATH: String = DemoEvidenceWriterClass.ARTIFACT_PATH


# ── Fake/double port implementations (mirrors tests/integration/
#    test_grunt_ai_step_strike_e2e.gd's identically-named doubles — these
#    stand in ONLY for the outer TurnOrderPort/EventSinkPort/
#    RoundHistoryPort/session-level-fallback AIDecisionPort seams;
#    AITierRegistry/GruntAI/RoundSession/RunRoundUseCase/CombatantFactory
#    are ALL real, un-doubled production classes). ─────────────────────────

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
## fallback port, but never actually consulted for the skeleton's turn once
## entries[0]['ai_planner'] (a real GruntAI instance) is wired — mirrors
## test_grunt_ai_step_strike_e2e.gd's identical double and its
## decide_action_calls == 0 assertion.
class FakeAIDecisionPort2Arg:
	extends "res://core/application/ai_decision_port.gd"

	var decide_action_calls: int = 0

	func decide_action(_combatant, _targets: Array) -> Dictionary:
		decide_action_calls += 1
		return {"action_type": "", "target": null}


## GruntTierCombatant — mirrors test_grunt_ai_step_strike_e2e.gd's
## identically-named/documented test-local Combatant subclass: gives a
## real, fully-populated Combatant built from CombatantFactory's own
## production output a place to durably carry an overridden ai_tier for
## the composition root to read (core/domain/combatant.gd's Combatant does
## not itself carry an ai_tier field across from_dict()/to_dict()).
class GruntTierCombatant:
	extends "res://core/domain/combatant.gd"

	var ai_tier: String = ""


func _with_ai_tier(base, tier: String) -> GruntTierCombatant:
	var wrapped := GruntTierCombatant.new()
	for prop in base.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			wrapped.set(prop["name"], base.get(prop["name"]))
	wrapped.ai_tier = tier
	return wrapped


## _build_session() -> Dictionary — assembles the full REAL composition
## root exactly like test_grunt_ai_step_strike_e2e.gd's own helper of the
## same name: a Titus party member (hex 0,0) and a Skeleton enemy (hex
## 2,0 — hex_distance 2, a 1-hex gap) built via the REAL
## CombatantFactory.build_enemy_combatant() reading the REAL
## data/enemies/skeleton.tres, with its authored ai_tier ('mindless')
## overridden to 'grunt' (US-011) before entries are wired. Returns {}
## (with a failure already asserted) if the real resource load itself
## fails — callers must check `.is_empty()`.
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
	var built: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, skeleton_hex, "skeleton_evidence")
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
	# of its own — core/combat/encounter.gd's initialize() is the seam that
	# normally stamps combatant.is_enemy = true/false. This test builds
	# entries directly (no Encounter object), so it reproduces that
	# stamping step here, mirroring test_grunt_ai_step_strike_e2e.gd.
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
	}


## _delete_artifact_if_present() — best-effort removal of any leftover
## evidence file BEFORE this test acts, so a later existence assertion
## proves THIS run produced the file rather than observing a stale one
## left behind by a previous run.
func _delete_artifact_if_present() -> void:
	if FileAccess.file_exists(ARTIFACT_PATH):
		var err := DirAccess.remove_absolute(ARTIFACT_PATH)
		assert_eq(err, OK, "precondition: must be able to remove a stale evidence artifact before this test runs")


func before_each() -> void:
	_delete_artifact_if_present()


# ══════════════════════════════════════════════════════════════════════════
# The capstone evidence-capture test: drives one real advance_ai_turn()
# call through the real composition root, writes a structured evidence log
# of what happened, then re-reads and validates it.
# ══════════════════════════════════════════════════════════════════════════

func test_advance_ai_turn_writes_and_reproduces_demo_evidence() -> void:
	var rig: Dictionary = _build_session()
	if rig.is_empty():
		return

	var session                 = rig["session"]
	var entries: Array          = rig["entries"]
	var skeleton                = rig["skeleton"]
	var titus                   = rig["titus"]
	var skeleton_action_economy = rig["skeleton_action_economy"]
	var event_sink_port         = rig["event_sink_port"]
	var round_history_port      = rig["round_history_port"]

	assert_false(FileAccess.file_exists(ARTIFACT_PATH), "precondition: no evidence artifact must exist before this test acts")

	assert_true(entries[0].has("ai_planner"), "begin_round() must wire an 'ai_planner' entry for the grunt-tier skeleton")
	assert_true(
		is_instance_of(entries[0]["ai_planner"], GruntAIClass),
		"the overridden ai_tier='grunt' must resolve to a REAL GruntAI instance via AITierRegistry.get_planner(), not a test double"
	)

	assert_eq(session.current_actor(), skeleton, "fixture assumption: the skeleton (Enemy) must be the first actionable entry")

	var start_hex = skeleton.hex_coord
	assert_eq(
		HexMathClass.hex_distance(start_hex, titus.hex_coord), 2,
		"fixture assumption: the skeleton starts a 1-hex gap (hex_distance 2) from Titus — GruntAI's Step-then-Strike branch"
	)
	var start_token_hex: Dictionary = start_hex.to_dict()

	# ── Capture the ordered plan via the REAL entries[0]['ai_planner']
	# (GruntAI) and the REAL AIWorldContext DTO RoundSession itself builds
	# (session._build_ai_world_context() — the SAME private-by-convention
	# helper tests/unit/application/test_decide_ai_action_dispatch.gd and
	# test_execute_ai_plan_strike.gd already call directly). GruntAI.plan_turn()
	# is a pure domain function (no side effects, no I/O), so calling it here
	# — before advance_ai_turn() drives the actual turn below — cannot alter
	# any state; it only observes, in advance, the SAME deterministic plan
	# advance_ai_turn()'s own internal _decide_ai_action() call will compute
	# and dispatch a moment later. Nothing on the dispatch path is mocked:
	# this is the real GruntAI instance the real composition root wired. ──
	var world_context: Dictionary = session._build_ai_world_context(skeleton, skeleton_action_economy)
	var observed_plan: Array = entries[0]["ai_planner"].plan_turn(skeleton, world_context)
	assert_eq(observed_plan.size(), 2, "fixture assumption: a 1-hex-gap target must yield a two-item [Step, Strike] plan")
	var action_plan: Array = []
	for item in observed_plan:
		action_plan.append(item.get("action_type", ""))
	assert_eq(action_plan, ["Step", "Strike"], "GruntAI's Step-then-Strike branch must produce this exact ordered plan")

	# ── Drive the SAME real dispatch path test_grunt_ai_step_strike_e2e.gd
	# exercises: one advance_ai_turn() call, Step then Strike, no mocks. ──
	var result: Dictionary = await session.advance_ai_turn()
	assert_true(result.get("ok", false), "advance_ai_turn() must resolve successfully")

	var end_hex = skeleton.hex_coord
	assert_false(end_hex.equals(start_hex), "the skeleton's hex_coord must change — a Step must have executed")
	assert_eq(
		HexMathClass.hex_distance(end_hex, titus.hex_coord), 1,
		"after the Step, the skeleton's hex must be adjacent (hex_distance 1) to Titus"
	)
	var end_token_hex: Dictionary = end_hex.to_dict()

	# ── Observed Strike resolution outcome (target id, hit/miss) — read
	# from the SAME two independent real side effects
	# test_grunt_ai_step_strike_e2e.gd already asserts prove a Strike (not
	# merely a Step) was attempted: exactly one round-history entry, and
	# exactly one AttackBroadcast event. ──
	assert_eq(round_history_port.entries.size(), 1, "exactly one resolved action (the Strike attempt) must be recorded this turn")
	var strike_entry: Dictionary = round_history_port.entries[0]
	assert_eq(strike_entry.get("action", ""), "Strike", "the recorded action must be a Strike attempt")

	var attack_events: Array = []
	for event in event_sink_port.events:
		if event is RoundEventsClass.AttackBroadcast:
			attack_events.append(event)
	assert_eq(attack_events.size(), 1, "exactly one AttackBroadcast must be emitted — the attempted Strike against Titus")

	var observed_target_id: String = titus.combatant_id
	var observed_hit: bool = false
	if attack_events.size() == 1:
		assert_eq(attack_events[0].target_name, "Titus")
		observed_hit = attack_events[0].hit

	var strike_outcome: Dictionary = {
		"target_id": observed_target_id,
		"hit": observed_hit,
	}

	# ══════════════════════════════════════════════════════════════════════
	# Write the structured evidence log, then re-read it from disk and
	# assert every required key/value matches what THIS test observed
	# in-process — no silently stale/mismatched evidence.
	# ══════════════════════════════════════════════════════════════════════
	var evidence: Dictionary = {
		"schema_version":  1,
		"start_token_hex": start_token_hex,
		"end_token_hex":   end_token_hex,
		"action_plan":     action_plan,
		"strike_outcome":  strike_outcome,
	}

	var write_ok: bool = DemoEvidenceWriterClass.write_evidence(evidence)
	assert_true(write_ok, "DemoEvidenceWriter.write_evidence() must succeed")

	assert_true(
		FileAccess.file_exists(ARTIFACT_PATH),
		"running the test must produce an evidence log file at the documented fixed artifact path (%s)" % ARTIFACT_PATH
	)

	var reread: Dictionary = DemoEvidenceWriterClass.read_evidence()
	assert_false(reread.is_empty(), "DemoEvidenceWriter.read_evidence() must successfully re-parse the just-written evidence log")

	for key in ["schema_version", "start_token_hex", "end_token_hex", "action_plan", "strike_outcome"]:
		assert_true(reread.has(key), "re-read evidence log must contain required key '%s'" % key)

	assert_eq(int(reread.get("schema_version", -1)), 1, "re-read schema_version must match what was written")

	var reread_start: Dictionary = reread.get("start_token_hex", {})
	assert_eq(int(reread_start.get("q", -999)), start_token_hex["q"], "re-read start_token_hex.q must match the in-test observed starting hex")
	assert_eq(int(reread_start.get("r", -999)), start_token_hex["r"], "re-read start_token_hex.r must match the in-test observed starting hex")

	var reread_end: Dictionary = reread.get("end_token_hex", {})
	assert_eq(int(reread_end.get("q", -999)), end_token_hex["q"], "re-read end_token_hex.q must match the in-test observed ending hex")
	assert_eq(int(reread_end.get("r", -999)), end_token_hex["r"], "re-read end_token_hex.r must match the in-test observed ending hex")
	assert_true(
		int(reread_start.get("q", -999)) != int(reread_end.get("q", -998)) or int(reread_start.get("r", -999)) != int(reread_end.get("r", -998)),
		"start/end token hex must genuinely differ (a Step occurred) — evidence must not silently mask a no-op turn"
	)

	var reread_plan: Array = reread.get("action_plan", [])
	assert_eq(reread_plan, action_plan, "re-read action_plan must match the in-test observed ordered plan ([\"Step\", \"Strike\"])")

	var reread_strike: Dictionary = reread.get("strike_outcome", {})
	assert_eq(reread_strike.get("target_id", ""), observed_target_id, "re-read strike_outcome.target_id must match the in-test observed Strike target")
	assert_eq(reread_strike.get("hit", null), observed_hit, "re-read strike_outcome.hit must match the in-test observed AttackBroadcast.hit")
