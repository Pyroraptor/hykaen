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
const ActionsClass = preload("res://core/rules/actions.gd")

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

## _token_reposition_fn — OPTIONAL (FEAT-008 / US-008 / FR-012, ADR-006): an
## injected, duck-typed Callable(combatant_id: String, new_hex_coord)
## advance_ai_turn() invokes immediately after an AI-issued Stride, so the
## enemy's on-screen token repositions through the EXACT SAME function
## presentation/movement_input_controller.gd's _resync_token_renderers()
## already calls for a player-driven Step/Stride — presentation/
## hex_grid_view.gd HexGridView.move_token() — never a second, parallel
## reposition implementation. RoundSession never imports/depends on
## HexGridView or any other Presentation type (ADR-001/ADR-002): it only
## calls whichever Callable the composition root (MainScene.gd) injects via
## set_token_reposition_fn(). Left as an invalid (unbound) Callable — the
## default — for every pre-existing caller/test double, including the
## autonomous run_autonomous_to_completion() path, which never sets one; a
## rendering-only concern is entirely optional and never required for the
## domain/application cycle logic to function correctly.
var _token_reposition_fn: Callable = Callable()

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
##
## ADR-101/ADR-102/FEAT-004: this initial cursor assignment is one of the TWO
## call sites (the other being _advance_cursor() below) that together form
## the SINGLE authoritative seam for ActionEconomy.start_of_turn() — for
## BOTH player and AI actors alike. start_of_turn() is invoked exactly once
## here, immediately after the cursor is positioned on the first living,
## un-Spent combatant, so that combatant's per-turn flags
## (movement_used_this_turn/action_used_this_turn) are guaranteed clear
## before anything (Presentation's verb bar, an AI decision) ever inspects
## them. Closes the P0-1 movement-lockout defect for the very first actor of
## a round, which the pre-FEAT-004 code never cleared for a Player actor at
## all. start_of_turn() itself is documented as idempotent and
## budget/is_spent-neutral (ADR-102), so this call is always safe even
## though RunRoundUseCase.begin_round() already called start_of_round() on
## every entry moments earlier.
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
	else:
		_entries[_cursor]["action_economy"].start_of_turn()


## set_token_reposition_fn(fn) -> void — FEAT-008 (US-008 / FR-012, ADR-006):
## injects the Callable advance_ai_turn() invokes to visually reposition an
## AI-Stride actor's on-screen token. `fn` is expected to accept
## (combatant_id: String, new_hex_coord) — the exact signature of
## presentation/hex_grid_view.gd HexGridView.move_token(), the SAME function
## the player Step/Stride path (presentation/movement_input_controller.gd)
## already calls. Intended to be called once by the composition root
## (MainScene.gd) right after obtaining this RoundSession from
## RunRoundUseCase.begin_round(), e.g.:
##   round_session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))
## Never calling this method (every pre-existing caller/test double) leaves
## advance_ai_turn()'s behavior completely unchanged — see
## _reposition_token_after_ai_stride()'s no-op guard below.
func set_token_reposition_fn(fn: Callable) -> void:
	_token_reposition_fn = fn


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
## consults DetermineOutcomeUseCase, and advances the cursor. Calling this
## after is_round_over(), or when the current actor is not on the Enemy
## team, is a no-op returning {"ok": false}.
##
## WAIT (US-001 / FR-001, ADR-010): when core/combat/ai.gd's decide_action()
## reports its null-action sentinel ({"action_type": "", "target": {}, ...}
## — no living target, or the nearest one is out of reach and cannot be
## closed this turn), this method resolves that sentinel as an explicit
## WAIT (core/rules/actions.gd Actions.resolve_wait()) rather than a bare,
## budget-neutral cursor advance. WAIT spends exactly one action from the
## SAME ActionEconomy budget every other resolvable action draws from, so a
## permanently idle/unreachable enemy still depletes to Spent within
## ActionEconomy.MAX_BUDGET (7) of its OWN turns — the steel-thread
## round-termination guarantee this feature exists for (e.g. a kiting 1v1
## where the enemy can never close the distance). Defensive fallback (US-011
## error_handling): on the rare occasion WAIT itself is rejected (e.g. a
## stale/misbehaving AIDecisionPort double already spent this turn's one
## action), that is logged via push_warning() and the cursor is STILL
## advanced, so the loop can never stall/deadlock.
##
## FEAT-007 (US-007 / FR-005, ADR-105): the AIDecision obtained via
## _decide_ai_action() below carries EXACTLY ONE action — "Strike" or
## "Stride", never both (core/combat/ai.gd's FEAT-005 composite
## "Stride-then-Strike" path, and its will_strike-driven handling here, are
## REMOVED). When action_type is "Stride", core/combat/ai.gd's
## decide_action() has already EXECUTED the Stride itself (repositioning
## `combatant` and spending its ActionEconomy's Movement-trait action
## directly through core/rules/movement.gd, the SAME domain path a
## player-driven Stride uses) as part of building that decision — ai.gd is
## the single mover for both paths (ADR-001), so this method never re-spends
## or re-resolves the Stride half, and never attempts a same-turn Strike
## after it (any Strike the Stride enabled is decided on the enemy's NEXT
## turn). When action_type is "Strike", this method resolves it via
## _resolve_action_use_case.resolve() — the IDENTICAL pipeline the player's
## own Strike already goes through. No new port or use-case is introduced
## (ADR-002): the decision flows through the existing
## AIDecisionPort/ResolveActionUseCase contracts. Together with
## core/combat/ai.gd's one-decision-per-call contract, this guarantees
## advance_ai_turn() triggers at most ONE ActionEconomy.spend_action() call
## per AI turn — the same one-action gate the player is bound to.
func advance_ai_turn() -> Dictionary:
	if _round_over or _cursor == -1:
		return {"ok": false}

	var entry: Dictionary = _entries[_cursor]
	var combatant: Dictionary = entry["combatant"]
	if not combatant.get("_is_enemy", false):
		return {"ok": false, "error": "ERR_NOT_ENEMY_TURN"}

	var action_economy = entry["action_economy"]
	# ADR-101/ADR-102/FEAT-004: start_of_turn() for this actor was already
	# invoked exactly once by whichever cursor-positioning call site (_init,
	# or the prior _advance_cursor()) made this actor the current_actor() —
	# see the file-level and _advance_cursor() doc comments. Calling it again
	# here would be a redundant second call site for the SAME turn boundary,
	# which is exactly the P0-1/duplication defect this feature closes; the
	# call is intentionally NOT repeated here.
	var ai_decision: Dictionary = _decide_ai_action(combatant, action_economy)
	var action_name: String = ai_decision.get("action_type", "")
	var target: Dictionary = ai_decision.get("target", {})

	var any_action_taken: bool = false

	if action_name == "Stride":
		# The Stride itself already happened inside decide_action() (see
		# file-level doc above) — nothing further to resolve for it here.
		# FEAT-007: never a composite — the Strike half (if any) is decided
		# on this combatant's next turn, never resolved in this same call.
		any_action_taken = true
		_reposition_token_after_ai_stride(combatant, ai_decision)
	elif action_name != "" and not target.is_empty():
		var resolve_result: Dictionary = _resolve_action_use_case.resolve(
			combatant, action_economy, target, action_name, _round_number, _cycle_index
		)
		any_action_taken = resolve_result.get("resolved", false)
	else:
		# US-001 / FR-001 (ADR-010): the null-action AI sentinel — resolve it
		# as an explicit WAIT (see the doc block above) instead of a bare,
		# budget-neutral cursor advance, so this combatant's action budget
		# genuinely depletes turn over turn.
		var wait_result: Dictionary = ActionsClass.resolve_wait(action_economy)
		any_action_taken = wait_result.get("success", false)

	if not any_action_taken:
		push_warning(
			"RoundSession.advance_ai_turn: no action resolved for '%s'; advancing turn regardless (CWE-835 guard)"
			% combatant.get("name", "")
		)
		_advance_cursor()
		return {"ok": true, "resolved": false}

	return _after_action_resolved()


## _decide_ai_action(combatant, action_economy) -> Dictionary — FEAT-006
## (US-006 / FR-010, ADR-002): drives the injected AIDecisionPort's
## decide_action(). Every pre-existing 2-argument adapter/test-double
## (core/application/ai_decision_port.gd's documented contract:
## decide_action(combatant, targets) -> Dictionary — e.g. this suite's own
## FakeAIDecisionPort/BrokenAIDecisionPort doubles) is called EXACTLY as
## before. When the injected port is the REAL core/combat/ai.gd — whose
## decide_action() additionally accepts the FEAT-004/005 OPTIONAL
## (action_economy, other_combatants) parameters — the extended 4-argument
## call is used instead, so the Stride-closing / Stride-then-Strike decision
## flow can actually execute through this orchestration. Which shape to call
## is determined via Callable.get_argument_count() (reflection over the
## port's own declared method signature), never a new static port/use-case
## type — no new port or use-case class is introduced by this feature.
func _decide_ai_action(combatant: Dictionary, action_economy) -> Dictionary:
	var decide_callable := Callable(_ai_decision_port, "decide_action")
	if decide_callable.get_argument_count() < 4:
		return decide_callable.call(combatant, _party)

	var other_combatants: Array = []
	for enemy in _enemies:
		if not is_same(enemy, combatant):
			other_combatants.append(enemy)

	return decide_callable.call(combatant, _party, action_economy, other_combatants)


## _reposition_token_after_ai_stride(combatant, ai_decision) -> void —
## FEAT-008 (US-008 / FR-012, ADR-006): invokes the injected
## `_token_reposition_fn` (see set_token_reposition_fn()'s doc) with the
## acting combatant's id and the Stride's destination hex — the EXACT SAME
## call presentation/movement_input_controller.gd's _resync_token_renderers()
## already makes for a player-driven Stride
## (hex_grid_view.move_token(actor_id, destination_hex)): same function, same
## call shape, only the actor_id/destination differ. A no-op when no
## reposition fn was injected (every headless test/the autonomous
## run_autonomous_to_completion() path never calls
## set_token_reposition_fn()) or when the decision carries no destination
## (defensive — decide_action() always supplies one for action_type
## "Stride", but this guards regardless of caller shape).
func _reposition_token_after_ai_stride(combatant: Dictionary, ai_decision: Dictionary) -> void:
	if not _token_reposition_fn.is_valid():
		return
	var destination = ai_decision.get("destination", null)
	if destination == null:
		return
	var actor_id: String = combatant.get("combatant_id", combatant.get("name", ""))
	_token_reposition_fn.call(actor_id, destination)


## end_current_turn() -> Dictionary — ends the current (player) actor's
## turn: consults DetermineOutcomeUseCase (emitting EncounterResultEvent if
## the player's just-resolved Strike ended the encounter), then advances the
## cursor to the next living, un-Spent actor. ALWAYS available regardless of
## whether/what action was spent this turn (US-010) — this method never
## itself spends an action or calls resolve_action_use_case. A no-op
## ({"ok": false}) once is_round_over().
##
## FEAT-004 (US-002 / FR-002, ADR-010): this is the PLAYER's free-pass path —
## deliberately distinct from advance_ai_turn()'s handling of an Enemy's
## null-action AI sentinel, which resolves as an explicit WAIT
## (core/rules/actions.gd Actions.resolve_wait()) that DOES spend one action
## via ActionEconomy.spend_action(). A player who ends their turn having
## chosen no action at all is never routed through resolve_wait() or any
## other spend_action()/spend_reaction() call here — end_current_turn()
## forwards straight to the shared _after_action_resolved() tail below,
## leaving the free-passing combatant's ActionEconomy.budget_remaining and
## is_spent() completely untouched, so that combatant's full budget remains
## available for a later reaction (Dodge/Parry/Block) this same round. The
## enemy WAIT path exists to guarantee round termination for an idle/
## unreachable Enemy (US-001); the player free-pass path exists so choosing
## not to act never costs the player anything (US-002) — the two are
## intentionally asymmetric.
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
##
## ADR-101/ADR-102/FEAT-004: together with the initial cursor assignment in
## _init() above, this is the SINGLE authoritative call site for
## ActionEconomy.start_of_turn() — for BOTH player and AI actors, with no
## distinction between the two. Every cursor movement (whether driven by a
## player's end_current_turn() or an AI's advance_ai_turn()) funnels through
## this one method, so start_of_turn() is invoked here EXACTLY ONCE per
## cursor advance, immediately after `_cursor` is updated to the new actor
## and before the TurnAdvancedEvent is emitted — replacing the previous,
## redundant, enemy-only call that used to live directly inside
## advance_ai_turn() (which never fired for a Player actor at all, the
## P0-1 movement-lockout defect this feature closes). start_of_turn() only
## clears the two per-turn flags (movement_used_this_turn/
## action_used_this_turn) and is documented as idempotent/budget-neutral
## (ADR-102) — it never mutates actions_remaining or is_spent.
func _advance_cursor() -> void:
	var next_index: int = _find_next_actionable_index(_cursor)
	if next_index == -1:
		_cursor     = -1
		_round_over = true
		return

	if next_index <= _cursor:
		_cycle_index += 1
	_cursor = next_index

	_entries[_cursor]["action_economy"].start_of_turn()

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
