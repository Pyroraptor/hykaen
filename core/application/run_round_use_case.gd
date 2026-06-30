## core/application/run_round_use_case.gd — RunRoundUseCase
## (FEAT-098 / US-003/US-004/US-005, CR-001 AC-4)
##
## Application layer (Clean Architecture): implements the AC-4 interleaved
## cycle algorithm extracted out of core/combat/encounter.gd's run_round().
## Orchestration ONLY — no rule logic duplicated from domain; depends on the
## injected ports (TurnOrderPort, EventSinkPort, RoundHistoryPort,
## AIDecisionPort) and the sibling use cases ResolveActionUseCase /
## DetermineOutcomeUseCase, never on a concrete adapter/infrastructure class.
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
##      once 'won'/'lost' is decided, an 'encounter_result' event is emitted
##      and the loop halts.
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
		_event_sink_port.emit({"type": "encounter_result", "round": round_number, "outcome": upfront_outcome})
		return {
			"round_number":      round_number,
			"outcome":           upfront_outcome,
			"history":           [],
			"encounter_outcome": upfront_outcome
		}

	# ── Step 1: grant the fresh per-round budget to every combatant (AC-2) ─
	for entry in entries:
		entry["action_economy"].start_of_round()

	# ── Step 2: cycle through entries until Spent-out or outcome decided ───
	var decided_outcome: String = ""
	var cycle_index: int = 0
	var force_draw_no_progress: bool = false

	while decided_outcome == "" and _has_living_unspent(entries):
		var any_action_resolved_this_cycle: bool = false

		for entry in entries:
			if decided_outcome != "":
				break

			var combatant: Dictionary = entry["combatant"]
			var action_economy = entry["action_economy"]

			# Dead combatants are skipped — no cycle slot consumed (AC-4)
			if combatant.get("hp_current", 0) <= 0:
				continue

			# Spent combatants are skipped — no cycle slot consumed (AC-4)
			if action_economy.is_spent():
				continue

			# Per-TURN flag reset only — documented no-op on budget/is_spent
			# when called repeatedly within the same round (AC-1/AC-4).
			action_economy.start_of_turn()

			var is_enemy: bool = combatant.get("_is_enemy", false)
			var target_pool: Array = party if is_enemy else enemies

			var target: Dictionary = {}
			var action_name: String = ""

			if is_enemy:
				var ai_decision: Dictionary = _ai_decision_port.decide_action(combatant, target_pool)
				action_name = ai_decision.get("action_type", "")
				target      = ai_decision.get("target", {})
			else:
				for t in target_pool:
					if t.get("hp_current", 0) > 0:
						target = t
						break
				if not target.is_empty():
					action_name = "Strike"

			# No living target found — skip this combatant for the cycle
			# (defensive guard; normally unreachable since a fully-dead
			# opposing side already decided the outcome above).
			if action_name == "" or target.is_empty():
				continue

			var resolve_result: Dictionary = _resolve_action_use_case.resolve(
				combatant, action_economy, target, action_name, round_number, cycle_index
			)

			# A failed spend (ALREADY_SPENT — a contract violation since
			# is_spent() was already checked above) skips this combatant;
			# the cycle CONTINUES rather than aborting/crashing.
			if not resolve_result.get("resolved", false):
				continue

			any_action_resolved_this_cycle = true

			var outcome_check: String = _determine_outcome_use_case.classify(party, enemies)
			if outcome_check == "won" or outcome_check == "lost":
				decided_outcome = outcome_check
				_event_sink_port.emit({
					"type":    "encounter_result",
					"round":   round_number,
					"outcome": decided_outcome
				})
				break

		# ── Backstop (CWE-835/FIND-095): a full cycle pass that resolved
		# ZERO actions means every still-unspent living combatant found no
		# usable action/target this pass — break safely with a DRAW rather
		# than looping forever. Does NOT mutate the overall encounter
		# outcome. ───────────────────────────────────────────────────────
		if decided_outcome == "" and not any_action_resolved_this_cycle:
			push_warning("run_round: a full cycle resolved zero actions; forcing a safe DRAW to prevent an unbounded loop")
			force_draw_no_progress = true
			break

		cycle_index += 1

	# ── End of round — reset every combatant's ActionEconomy ───────────────
	for entry in entries:
		entry["action_economy"].end_of_round()

	var this_round_history: Array = []
	for hist_entry in _round_history_port.get_history():
		if hist_entry.get("round", -1) == round_number:
			this_round_history.append(hist_entry)

	var result_outcome: String = "DRAW" if force_draw_no_progress else decided_outcome
	var encounter_outcome: String = "" if force_draw_no_progress else decided_outcome

	return {
		"round_number":      round_number,
		"outcome":           result_outcome,
		"history":           this_round_history,
		"encounter_outcome": encounter_outcome
	}


## _has_living_unspent(entries) -> bool — true if at least one living
## combatant in `entries` has not yet reached is_spent()==true. Used to
## determine when to stop cycling (every living combatant Spent) without
## relying on a fixed iteration count.
func _has_living_unspent(entries: Array) -> bool:
	for entry in entries:
		var combatant: Dictionary = entry["combatant"]
		if combatant.get("hp_current", 0) <= 0:
			continue
		if not entry["action_economy"].is_spent():
			return true
	return false
