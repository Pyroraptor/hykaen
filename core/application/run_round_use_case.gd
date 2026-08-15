## core/application/run_round_use_case.gd — RunRoundUseCase
## (FEAT-098 / US-003/US-004/US-005, CR-001 AC-4; FEAT-110 / US-010, ADR-007)
##
## Application layer (Clean Architecture): implements the AC-4 interleaved
## cycle algorithm extracted out of core/combat/encounter.gd's run_round().
## Orchestration ONLY — no rule logic duplicated from domain; depends on the
## injected ports (TurnOrderPort, EventSinkPort, RoundHistoryPort,
## AIDecisionPort) and the sibling use cases ResolveActionUseCase /
## DetermineOutcomeUseCase, never on a concrete adapter/infrastructure class.
##
## FEAT-110 / ADR-007 amendment: the AC-4 cycle state that used to live
## entirely as local variables inside execute()'s while-loop is now a
## first-class RoundSession (core/application/round_session.gd), obtained
## via begin_round(). execute() is re-expressed on top of
## begin_round()+RoundSession.run_autonomous_to_completion()+finish() —
## behavior-preserving relative to the pre-FEAT-110 inline implementation
## (see tests/test_run_round_use_case.gd, unchanged and still green). The
## SAME RoundSession also exposes the interactive stepwise API
## (current_actor/advance_ai_turn/end_current_turn/is_round_over) that
## Presentation (presentation/turn_controller.gd, presentation/
## end_turn_control.gd) drives one turn at a time (US-010/US-011) — the
## interleaved-cycle algorithm therefore exists in exactly ONE place
## (RoundSession), not duplicated between the batch sim and the interactive
## path.
##
## Algorithm (carries forward the FIX-001-corrected cycle algorithm,
## byte-for-byte behavior-preserving relative to the pre-extraction
## core/combat/encounter.gd, including the FEAT-097/CWE-835/FIND-095 guards):
##   0. Guard: an empty TurnOrderPort.get_turn_order() result -> RoundResult
##      {outcome: 'DRAW', history: []} without mutating any state, logged via
##      push_warning() rather than thrown.
##   1. Guard: if one (or both) side(s) has zero living combatants BEFORE the
##      cycle loop begins, decide the outcome immediately via
##      DetermineOutcomeUseCase and return — NEVER enters the cycle loop
##      (prevents the CWE-835 unbounded-loop hang fixed by FEAT-097).
##   2. start_of_round() is granted once to every combatant's ActionEconomy
##      (CR-001 AC-2).
##   3. Repeatedly cycles TurnOrderPort.get_turn_order(): each living,
##      non-Spent combatant takes EXACTLY ONE action per cycle pass (Strikes
##      therefore INTERLEAVE in turn order, e.g. A,B,A,B,...). Dead/Spent
##      combatants are skipped WITHOUT consuming a cycle slot. A failed
##      ResolveActionUseCase Result (ALREADY_SPENT) causes the loop to skip
##      that combatant and CONTINUE rather than abort/crash.
##   4. After every resolved action, DetermineOutcomeUseCase is consulted;
##      once 'won'/'lost' is decided, a typed RoundEvents.EncounterResultEvent
##      (FEAT-099/FIND-096, built via DetermineOutcomeUseCase.build_event())
##      is emitted via EventSinkPort and the loop halts.
##   5. The round terminates when every living combatant is Spent OR the
##      outcome is decided. A defensive backstop: if a full cycle pass
##      resolves ZERO actions, the loop force-terminates with a safe 'DRAW'
##      RoundResult (NOT the overall encounter outcome) rather than spinning
##      forever (FEAT-097 CWE-835/FIND-095 backstop).
##   6. end_of_round() is called on every combatant's ActionEconomy.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var use_case := RunRoundUseCase.new(
##       turn_order_port, event_sink_port, round_history_port, ai_decision_port,
##       resolve_action_use_case, determine_outcome_use_case
##   )
##   var result: Dictionary = use_case.execute(round_number, party, enemies)
##   # result -> {round_number: int, outcome: String, history: Array,
##   #            encounter_outcome: String}

class_name RunRoundUseCase
extends RefCounted

const RoundSessionClass = preload("res://core/application/round_session.gd")

## AITierRegistryClass — FEAT-401 (US-011 / FR-019 part 1, ADR-003): the
## DOMAIN-layer tier-string -> AIPlannerPort factory (core/combat/
## ai_tier_registry.gd) this composition root calls, per enemy entry, to wire
## a per-combatant planner ahead of RoundSession ever dispatching that
## combatant's turn. Preloaded here (not by round_session.gd) because THIS
## file is the composition root — the one layer allowed to know about every
## concrete planner type (see this iteration's design notes, "PRESENTATION /
## composition root" section); round_session.gd only ever consumes whatever
## the resulting entry['ai_planner'] duck-types as (a plain Callable check),
## never importing AITierRegistry or any concrete planner class itself.
const AITierRegistryClass = preload("res://core/combat/ai_tier_registry.gd")

var _turn_order_port             ## TurnOrderPort — injected
var _event_sink_port             ## EventSinkPort — injected
var _round_history_port          ## RoundHistoryPort — injected
var _ai_decision_port            ## AIDecisionPort — injected (duck-typed, no static type)
var _resolve_action_use_case     ## ResolveActionUseCase — injected
var _determine_outcome_use_case  ## DetermineOutcomeUseCase — injected


## _init(turn_order_port, event_sink_port, round_history_port,
##       ai_decision_port, resolve_action_use_case, determine_outcome_use_case)
## — stores the injected ports/use cases. Ports are duck-typed (no static
## port type on the parameters) so any object implementing the documented
## method contracts may be substituted (test doubles in particular).
func _init(
	turn_order_port,
	event_sink_port,
	round_history_port,
	ai_decision_port,
	resolve_action_use_case,
	determine_outcome_use_case
) -> void:
	_turn_order_port            = turn_order_port
	_event_sink_port             = event_sink_port
	_round_history_port          = round_history_port
	_ai_decision_port            = ai_decision_port
	_resolve_action_use_case     = resolve_action_use_case
	_determine_outcome_use_case  = determine_outcome_use_case


## execute(round_number, party, enemies) -> Dictionary
##
## round_number — the 1-based number of the round about to execute.
## party        — Array of player-side combatant Dictionaries.
## enemies      — Array of enemy-side combatant Dictionaries.
##
## Returns a Dictionary:
##   {round_number: int, outcome: String, history: Array, encounter_outcome: String}
##     "outcome"           — the RoundResult-level outcome: '', 'won', 'lost',
##                            or 'DRAW' (DRAW is a per-round degrade-gracefully
##                            signal, never persisted as the encounter's
##                            overall outcome).
##     "history"            — this round's resolved-action entries only.
##     "encounter_outcome"  — the value the caller should persist as the
##                             OVERALL encounter outcome ('', 'won', or
##                             'lost' — never 'DRAW'; a DRAW round leaves the
##                             overall encounter outcome untouched).
func execute(round_number: int, party: Array, enemies: Array) -> Dictionary:
	var entries: Array = _turn_order_port.get_turn_order()

	# ── Guard: empty/invalid turn order — never throw, return a DRAW ───────
	if entries.is_empty():
		push_warning("run_round called with empty/invalid turn order")
		return {"round_number": round_number, "outcome": "DRAW", "history": [], "encounter_outcome": ""}

	# ── Guard (CWE-835/FIND-095): one (or both) side(s) has zero living
	# combatants — decide the outcome immediately and NEVER enter the cycle
	# loop, which would otherwise never terminate (a combatant whose target
	# pool never contains a living member never spends an action, never
	# becomes Spent). ──────────────────────────────────────────────────────
	var upfront_outcome: String = _determine_outcome_use_case.classify(party, enemies)
	if upfront_outcome == "DRAW":
		push_warning("run_round called with zero living combatants on both sides")
		return {"round_number": round_number, "outcome": "DRAW", "history": [], "encounter_outcome": ""}
	if upfront_outcome == "won" or upfront_outcome == "lost":
		_event_sink_port.emit(_determine_outcome_use_case.build_event(round_number, upfront_outcome))
		return {
			"round_number":      round_number,
			"outcome":           upfront_outcome,
			"history":           [],
			"encounter_outcome": upfront_outcome
		}

	# ── FEAT-110/ADR-007: the cycle algorithm now lives entirely on
	# RoundSession — begin_round() grants the fresh per-round budget (AC-2)
	# and snapshots turn order, run_autonomous_to_completion() replays the
	# AC-4 interleaved cycle (auto-selecting a target for every combatant,
	# matching this method's pre-FEAT-110 inline behavior byte-for-byte),
	# and finish() produces the identical RoundResult tail (end_of_round()
	# on every combatant + the round-scoped history slice). ────────────────
	var session: RoundSessionClass = begin_round(round_number, party, enemies)
	session.run_autonomous_to_completion()
	return session.finish()


## begin_round(round_number, party, enemies) -> RoundSession [FEAT-110 / ADR-007]
##
## Grants each combatant's start-of-round ActionEconomy budget (AC-2) and
## snapshots the turn order via TurnOrderPort, returning a RoundSession
## positioned at the first living, un-Spent combatant. Runs NO turns itself
## — the caller (execute()'s autonomous batch loop, or Presentation's
## turn_controller.gd for the interactive path) drives the returned session.
func begin_round(round_number: int, party: Array, enemies: Array) -> RoundSessionClass:
	var entries: Array = _turn_order_port.get_turn_order()

	for entry in entries:
		entry["action_economy"].start_of_round()

		# FEAT-401 (US-011 / FR-019 part 1, ADR-003): per-enemy AIPlannerPort
		# wiring. When `entry`'s combatant carries EXPLICIT ai_tier data
		# (infrastructure/combatant_factory.gd's build_enemy_combatant()
		# output, or any future combatant shape that authors the field),
		# AITierRegistry.get_planner() maps it to a freshly-constructed
		# planner instance, stored as entry['ai_planner']. This is a PER-ENTRY
		# override — RoundSession._decide_ai_action() (core/application/
		# round_session.gd) reads entry.get('ai_planner', null) and PREFERS
		# it over the single, session-wide _ai_decision_port whenever both are
		# present, so heterogeneous AI tiers can coexist within one encounter
		# without per-combatant RoundSession instances (see that method's own
		# doc for the full precedence rule).
		#
		# Deliberately gated on ai_tier being genuinely PRESENT (not merely
		# defaulted): core/domain/combatant.gd's Combatant entity does not
		# (yet) carry an ai_tier field across its from_dict()/to_dict()
		# round-trip (see infrastructure/combatant_factory.gd's FEAT-007 doc),
		# so every entry built from today's real composition-root pipeline
		# (CombatSessionFactory) resolves no ai_tier here and is left
		# untouched — entry['ai_planner'] is simply never set, and every
		# pre-existing caller keeps relying on the session-level
		# _ai_decision_port exactly as before (NFR-004 default-safety). Were
		# this instead gated on AITierRegistry's own "" -> MindlessAI
		# fallback (i.e. always wiring SOME planner for every is_enemy
		# combatant), it would silently override every pre-existing test's
		# hand-injected _ai_decision_port test double for every enemy in the
		# entire suite — a correctness regression this gate exists to avoid.
		var ai_tier = _read_ai_tier_if_present(entry.get("combatant"))
		if ai_tier != null:
			entry["ai_planner"] = AITierRegistryClass.get_planner(String(ai_tier))

	return RoundSessionClass.new(
		entries,
		party,
		enemies,
		round_number,
		_resolve_action_use_case,
		_determine_outcome_use_case,
		_ai_decision_port,
		_event_sink_port,
		_round_history_port
	)


## _read_ai_tier_if_present(combatant) -> Variant (String or null) —
## FEAT-401 (US-011): returns `combatant`'s authored ai_tier verbatim when
## genuinely present, else null. Duck-typed across BOTH shapes this
## composition root may see:
##   - a Dictionary carrying an "ai_tier" key (e.g. infrastructure/
##     combatant_factory.gd's build_enemy_combatant() output) —
##     Dictionary.get("ai_tier", null).
##   - an Object exposing an "ai_tier" property — Object.get("ai_tier"),
##     which itself already returns null for a property the Object does not
##     declare (e.g. today's core/domain/combatant.gd Combatant entity), no
##     try/catch or has_method() probe required.
## Deliberately distinguishes "field absent" (null, this combatant carries no
## ai_tier data at all) from "field present but empty string" (a genuine,
## if minimal, authored value — still routed through AITierRegistry, whose
## own "" -> MindlessAI fallback is a SEPARATE, later degradation) — see
## begin_round()'s own doc for why this distinction matters.
func _read_ai_tier_if_present(combatant):
	if combatant == null:
		return null
	if combatant is Dictionary:
		return combatant.get("ai_tier", null)
	return combatant.get("ai_tier")
