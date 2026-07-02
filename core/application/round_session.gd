## core/application/round_session.gd — RoundSession (FEAT-110 / US-010, ADR-007)
##
## Application layer (Clean Architecture): the resumable, stepwise cycle
## state for ONE round, returned by RunRoundUseCase.begin_round(). This is
## the declared ADR-007 amendment to RunRoundUseCase's surface: the AC-4
## interleaved-cycle state that used to live entirely as local variables
## inside execute()'s while-loop is now a first-class RefCounted object a
## human can drive one turn at a time (US-010/US-011), instead of the whole
## round resolving autonomously in a single call.
##
## Depends ONLY on the same collaborators RunRoundUseCase already depends on
## (ResolveActionUseCase, DetermineOutcomeUseCase, AIDecisionPort,
## EventSinkPort, RoundHistoryPort) plus the plain combatant/ActionEconomy
## Dictionaries pulled from TurnOrderPort — never on a concrete
## adapter/infrastructure class. No new port is introduced (ADR-002/ADR-007).
##
## Two independent ways this session's cycle can be driven, both funnelling
## every actual rule decision through the SAME resolve_action_use_case /
## determine_outcome_use_case instances (never a parallel rules path):
##
##   1. Interactive, one-turn-at-a-time (US-010/US-011 — the Presentation
##      turn-driver, presentation/turn_controller.gd, calls these):
##        current_actor() / current_action_economy() — who acts now.
##        advance_ai_turn()  — resolves the current Enemy actor's turn via
##          AIDecisionPort + resolve_action_use_case, then advances the
##          cursor. Defensive fallback: an AI decision that fails to resolve
##          still advances the cursor so the loop can never stall (US-011).
##        end_current_turn() — ends the current PLAYER actor's turn. ALWAYS
##          available regardless of whether/what action was spent (US-010);
##          the actor's own Strike (if any) was already resolved directly by
##          StrikeActionControl via resolve_action_use_case.resolve() (US-009,
##          unchanged) — this method owns only the post-action outcome check
##          + cursor advance, never the resolve() call itself.
##      Each cursor advance emits a RoundEvents.TurnAdvancedEvent via
##      EventSinkPort (ADR-003's one integration surface with Presentation).
##
##   2. Autonomous, whole-round-at-once (used ONLY by
##      RunRoundUseCase.execute(), the pre-existing headless N=1000 balance
##      sim entry point): run_autonomous_to_completion() replays the
##      byte-for-byte-identical AC-4 nested-cycle algorithm (incl. the
##      FEAT-097/CWE-835 no-progress backstop) that used to live inline in
##      execute() — auto-selecting a target for BOTH sides (AI for Enemy,
##      "first living target" for Player, matching execute()'s pre-FEAT-110
##      behavior exactly) rather than waiting on human input.
##
## finish() (used by both callers) mirrors execute()'s pre-FEAT-110 tail:
## end_of_round() on every combatant, then the round-scoped history slice.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
class_name RoundSession
extends RefCounted

const RoundEventsClass = preload("res://core/rules/round_events.gd")

var _entries: Array
var _party: Array
var _enemies: Array
var _round_number: int

var _resolve_action_use_case      ## ResolveActionUseCase — injected
var _determine_outcome_use_case   ## DetermineOutcomeUseCase — injected
var _ai_decision_port             ## AIDecisionPort — injected (duck-typed)
var _event_sink_port              ## EventSinkPort — injected
var _round_history_port           ## RoundHistoryPort — injected

## _cursor — index into _entries of the current actor; -1 once the round is
## over (no living, un-Spent actor remains, or the outcome was decided).
var _cursor: int = -1

## _cycle_index — the AC-4 interleave cycle pass the CURRENT actor's action
## belongs to (0-based), stamped on resolve_action_use_case calls made via
## advance_ai_turn(). Incremented whenever the cursor wraps back around
## _entries (one full pass completed).
var _cycle_index: int = 0

## _outcome — '' | 'won' | 'lost'; NEVER 'DRAW' (mirrors outcome()'s
## documented contract — a per-round DRAW is reported only via finish()'s
## Dictionary "outcome" key, see _forced_draw below).
var _outcome: String = ""

## _round_over — true once every living combatant is Spent, the outcome was
## decided, or (autonomous path only) the stalled-cycle backstop fired.
var _round_over: bool = false

## _forced_draw — true only when run_autonomous_to_completion()'s
## CWE-835/FIND-095 backstop fired (a full cycle pass resolved zero
## actions). Never set by the interactive cursor path. Drives finish()'s
## per-round "outcome": "DRAW" vs "encounter_outcome": "" distinction,
## exactly matching RunRoundUseCase.execute()'s pre-FEAT-110 contract.
var _forced_draw: bool = false


## _init(entries, party, enemies, round_number, resolve_action_use_case,
##       determine_outcome_use_case, ai_decision_port, event_sink_port,
##       round_history_port) — stores the injected collaborators (all
## duck-typed, matching RunRoundUseCase's own constructor convention so test
## doubles may be substituted) and positions the cursor at the first living,
## un-Spent combatant in `entries` (or marks the round over immediately if
## none exists). Callers MUST have already granted each entry's
## ActionEconomy its start-of-round budget (RunRoundUseCase.begin_round()
## does this) — the constructor itself grants no budget.
func _init(
	entries: Array,
	party: Array,
	enemies: Array,
	round_number: int,
	resolve_action_use_case,
	determine_outcome_use_case,
	ai_decision_port,
	event_sink_port,
	round_history_port
) -> void:
	_entries                    = entries
	_party                      = party
	_enemies                    = enemies
	_round_number                = round_number
	_resolve_action_use_case    = resolve_action_use_case
	_determine_outcome_use_case = determine_outcome_use_case
	_ai_decision_port           = ai_decision_port
	_event_sink_port            = event_sink_port
	_round_history_port         = round_history_port

	_cursor = _find_first_actionable_index()
	if _cursor == -1:
		_round_over = true


# ── Interactive stepwise API (US-010/US-011) ───────────────────────────────

## current_actor() -> Dictionary — the combatant whose turn it is, or {}
## when the round is over.
func current_actor() -> Dictionary:
	if _round_over or _cursor == -1:
		return {}
	return _entries[_cursor]["combatant"]


## current_action_economy() -> ActionEconomy or null — the ActionEconomy
## paired with current_actor() (the TurnOrderEntry shape). Not itself part
## of the design's headline method list, but required so Presentation
## (turn_controller.gd) can hand the active player's budget to
## StrikeActionControl.configure() without reaching back into Infrastructure.
func current_action_economy():
	if _round_over or _cursor == -1:
		return null
	return _entries[_cursor]["action_economy"]


## is_round_over() -> bool — true when every living combatant is Spent OR an
## EncounterResultEvent has been emitted (or, autonomous path only, the
## stalled-cycle backstop forced a DRAW).
func is_round_over() -> bool:
	return _round_over


## outcome() -> String — '' | 'won' | 'lost' (never 'DRAW' — see finish()
## for the per-round DRAW distinction).
func outcome() -> String:
	return _outcome


## advance_ai_turn() -> Dictionary — for a current actor whose team is
## Enemy: obtains the action from AIDecisionPort, resolves it via the SAME
## resolve_action_use_case.resolve() the player's own Strike goes through,
## consults DetermineOutcomeUseCase, and advances the cursor. Defensive
## fallback (US-011 error_handling): an AI decision that is rejected or
## yields no usable action/target is logged via push_warning() and the
## cursor is STILL advanced, so the loop can never stall/deadlock. Calling
## this after is_round_over(), or when the current actor is not on the Enemy
## team, is a no-op returning {"ok": false}.
func advance_ai_turn() -> Dictionary:
	if _round_over or _cursor == -1:
		return {"ok": false}

	var entry: Dictionary = _entries[_cursor]
	var combatant: Dictionary = entry["combatant"]
	if not combatant.get("_is_enemy", false):
		return {"ok": false, "error": "ERR_NOT_ENEMY_TURN"}

	var action_economy = entry["action_economy"]
	action_economy.start_of_turn()

	var ai_decision: Dictionary = _ai_decision_port.decide_action(combatant, _party)
	var action_name: String = ai_decision.get("action_type", "")
	var target: Dictionary = ai_decision.get("target", {})

	var resolve_result: Dictionary = {}
	if action_name != "" and not target.is_empty():
		resolve_result = _resolve_action_use_case.resolve(
			combatant, action_economy, target, action_name, _round_number, _cycle_index
		)

	if not resolve_result.get("resolved", false):
		push_warning(
			"RoundSession.advance_ai_turn: no action resolved for '%s'; advancing turn regardless (CWE-835 guard)"
			% combatant.get("name", "")
		)
		_advance_cursor()
		return {"ok": true, "resolved": false}

	return _after_action_resolved()


## end_current_turn() -> Dictionary — ends the current (player) actor's
## turn: consults DetermineOutcomeUseCase (emitting EncounterResultEvent if
## the player's just-resolved Strike ended the encounter), then advances the
## cursor to the next living, un-Spent actor. ALWAYS available regardless of
## whether/what action was spent this turn (US-010) — this method never
## itself spends an action or calls resolve_action_use_case. A no-op
## ({"ok": false}) once is_round_over().
func end_current_turn() -> Dictionary:
	if _round_over or _cursor == -1:
		return {"ok": false}
	return _after_action_resolved()


## finish() -> Dictionary — ends the round: calls ActionEconomy.end_of_round
## on every combatant and returns the RoundResult Dictionary shaped
## identically to RunRoundUseCase.execute()'s pre-FEAT-110 return:
##   {round_number: int, outcome: String, history: Array, encounter_outcome: String}
func finish() -> Dictionary:
	for entry in _entries:
		entry["action_economy"].end_of_round()

	var this_round_history: Array = []
	for hist_entry in _round_history_port.get_history():
		if hist_entry.get("round", -1) == _round_number:
			this_round_history.append(hist_entry)

	var result_outcome: String = "DRAW" if _forced_draw else _outcome
	var encounter_outcome: String = "" if _forced_draw else _outcome

	return {
		"round_number":      _round_number,
		"outcome":           result_outcome,
		"history":           this_round_history,
		"encounter_outcome": encounter_outcome
	}


# ── Autonomous whole-round API (used only by RunRoundUseCase.execute()) ────

## run_autonomous_to_completion() -> void — replays the AC-4 interleaved
## cycle algorithm to completion in one call, auto-selecting a target for
## EVERY combatant (AI for Enemy via AIDecisionPort, "first living target"
## for Player — mirroring the pre-FEAT-110 execute() body byte-for-byte,
## including the FEAT-097/CWE-835/FIND-095 stalled-cycle backstop). Marks
## the round over unconditionally when it returns. NOT used by the
## interactive stepwise API above — the human-paced path never auto-selects
## a Player target.
func run_autonomous_to_completion() -> void:
	var decided_outcome: String = ""
	var cycle_index: int = 0
	var force_draw_no_progress: bool = false

	while decided_outcome == "" and _has_living_unspent(_entries):
		var any_action_resolved_this_cycle: bool = false

		for entry in _entries:
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

			action_economy.start_of_turn()

			var is_enemy: bool = combatant.get("_is_enemy", false)
			var target_pool: Array = _party if is_enemy else _enemies

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

			# No living target found — skip this combatant for the cycle.
			if action_name == "" or target.is_empty():
				continue

			var resolve_result: Dictionary = _resolve_action_use_case.resolve(
				combatant, action_economy, target, action_name, _round_number, cycle_index
			)

			if not resolve_result.get("resolved", false):
				continue

			any_action_resolved_this_cycle = true

			var outcome_check: String = _determine_outcome_use_case.classify(_party, _enemies)
			if outcome_check == "won" or outcome_check == "lost":
				decided_outcome = outcome_check
				_event_sink_port.emit(_determine_outcome_use_case.build_event(_round_number, decided_outcome))
				break

		if decided_outcome == "" and not any_action_resolved_this_cycle:
			push_warning("run_round: a full cycle resolved zero actions; forcing a safe DRAW to prevent an unbounded loop")
			force_draw_no_progress = true
			break

		cycle_index += 1

	_outcome      = decided_outcome
	_forced_draw  = force_draw_no_progress
	_round_over   = true
	_cursor       = -1


# ── Internal helpers ────────────────────────────────────────────────────────

## _after_action_resolved() -> Dictionary — shared tail used by both
## advance_ai_turn() (after a resolved AI action) and end_current_turn()
## (regardless of whether an action was spent): consults
## DetermineOutcomeUseCase; if decided, emits EncounterResultEvent and ends
## the round; otherwise advances the cursor to the next living, un-Spent
## actor (emitting TurnAdvancedEvent).
func _after_action_resolved() -> Dictionary:
	var decided: String = _determine_outcome_use_case.classify(_party, _enemies)
	if decided == "won" or decided == "lost":
		_outcome    = decided
		_round_over = true
		_cursor     = -1
		_event_sink_port.emit(_determine_outcome_use_case.build_event(_round_number, decided))
		return {"ok": true, "round_over": true, "outcome": decided}

	_advance_cursor()
	return {"ok": true, "round_over": _round_over}


## _advance_cursor() -> void — moves the cursor forward to the next living,
## un-Spent entry (wrapping past the end of _entries increments
## _cycle_index, mirroring one AC-4 "cycle pass"). Emits a
## RoundEvents.TurnAdvancedEvent for the new current actor. When no living,
## un-Spent entry remains, marks the round over instead.
func _advance_cursor() -> void:
	var next_index: int = _find_next_actionable_index(_cursor)
	if next_index == -1:
		_cursor     = -1
		_round_over = true
		return

	if next_index <= _cursor:
		_cycle_index += 1
	_cursor = next_index

	var combatant: Dictionary = _entries[_cursor]["combatant"]
	_event_sink_port.emit(RoundEventsClass.TurnAdvancedEvent.new(
		_round_number,
		combatant.get("name", ""),
		combatant.get("combatant_id", "")
	))


func _find_first_actionable_index() -> int:
	for i in range(_entries.size()):
		if _is_actionable(_entries[i]):
			return i
	return -1


func _find_next_actionable_index(from_index: int) -> int:
	var n: int = _entries.size()
	if n == 0:
		return -1
	for step in range(1, n + 1):
		var idx: int = (from_index + step) % n
		if _is_actionable(_entries[idx]):
			return idx
	return -1


func _is_actionable(entry: Dictionary) -> bool:
	var combatant: Dictionary = entry["combatant"]
	if combatant.get("hp_current", 0) <= 0:
		return false
	return not entry["action_economy"].is_spent()


## _has_living_unspent(entries) -> bool — true if at least one living
## combatant in `entries` has not yet reached is_spent()==true. Identical
## contract to RunRoundUseCase's pre-FEAT-110 private helper of the same
## name, relocated here for run_autonomous_to_completion()'s exclusive use.
func _has_living_unspent(entries: Array) -> bool:
	for entry in entries:
		var combatant: Dictionary = entry["combatant"]
		if combatant.get("hp_current", 0) <= 0:
			continue
		if not entry["action_economy"].is_spent():
			return true
	return false
