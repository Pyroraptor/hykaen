## core/rules/action_economy.gd — Seven-Action Round Economy State Machine
##
## Domain layer (ADR-001): no Node/Control inheritance — pure game logic only.
## Manages the 7-action budget per combatant ROUND (ADR-006 / US-007 / CR-001).
##
## State managed:
##   _budget        — actions remaining this ROUND (0–7); shared across all of
##                    a combatant's turns AND reactions within the round
##                    (CR-001 AC-1/AC-2/AC-3) — only reset at the round
##                    boundary, NEVER by start_of_turn()
##   _is_spent      — true once all 7 actions are consumed for the round;
##                    persists across turns until the round boundary
##   _movement_used — per-TURN flag: true once a Movement action or
##                    use_step() is used this turn; cleared by start_of_turn()
##   _action_used   — per-TURN flag (ADR-103 / FEAT-003): true once
##                    spend_action() has succeeded this turn; cleared by
##                    start_of_turn() and _reset_round_state(). Enforces the
##                    "exactly one action per turn" business rule (FR-002):
##                    a second in-turn spend_action() call is rejected with
##                    reason ACTION_ALREADY_USED BEFORE any budget mutation.
##                    spend_reaction() and Step (use_step()/mark_movement_used())
##                    are unaffected by this flag.
##   _dazed         — persists across rounds; gates action combining
##
## Usage example:
##   var ae = ActionEconomy.new()
##   ae.start_of_turn()
##   var result = ae.spend_action({"traits": ["Strike"]})
##   # → {success: true, remaining: 6}
##
## Callers (US-001 / FR-001, ADR-010): every resolvable action funnels
## through this SAME spend_action() gate, including the explicit WAIT action
## an idle/unreachable combatant resolves via core/rules/actions.gd
## (Actions.resolve_wait()) — WAIT carries no "Movement" trait and no
## target, but is otherwise an ordinary spend_action() call, guaranteeing an
## idle combatant's budget still counts down across its own turns.

class_name ActionEconomy

## Maximum action budget per round (ADR-006).
const MAX_BUDGET: int = 7

## RESERVE (iteration K FEAT-003 / US-003, ADR-003) — the minimum number of
## actions a combatant's shared per-round budget_remaining must retain AFTER
## spending a reaction, so the combatant never reacts itself into having
## zero actions available for its own next turn. Consulted by
## infrastructure/ai_reaction_policy.gd's budget-aware reserve GATE, which
## applies to BOTH the PreHitAvoidance (Dodge) and OnHitMitigation
## (Parry/Block) windows: reacting costs exactly one action
## (spend_reaction()); the gate forces Pass whenever
## action_current - 1 < RESERVE, even when the Dodge/Parry/Block rules
## themselves would otherwise choose to react. Surfaced here (rather than
## buried as a literal in the policy) so the constant has exactly one
## authoritative source, matching MAX_BUDGET's own role.
const RESERVE: int = 1


var _budget: int = MAX_BUDGET
var _is_spent: bool = false
var _movement_used: bool = false
var _action_used: bool = false
var _dazed: bool = false

## _self_spend_suppressed — FEAT-008 (US-008; FR-007; ADR-003): the
## no-self-spend execution-mode flag. While true, spend_action() reports its
## ordinary SUCCESS Result-style Dictionary WITHOUT mutating _budget/
## _action_used/_movement_used at all — i.e. the caller's own
## action-economy self-charge becomes a pure no-op, though the caller's own
## game EFFECT (a Stride's move, a Strike's damage) still proceeds exactly
## as it would on a genuine spend. This is the seam
## presentation/combine_action_controller.gd's execute() threads through
## StrideActionController/StrikeActionController's own execute() calls when
## resolving them AS Combine sub-actions (never for a standalone verb-bar
## call), so a queued Stride+Strike Charge applies BOTH sub-actions' effects
## without EACH also draining the shared per-round budget — Combine's own
## execute() charges the ONE real action (tagged "Movement" when the queue
## contained a Stride, applying the Movement-trait lockout exactly once) at
## the Combine level instead, once its whole sub-action queue has resolved.
## Defaults to false, so every pre-existing spend_action()/spend_reaction()
## caller (every verb registered before FEAT-008) is completely unaffected.
var _self_spend_suppressed: bool = false


# ── Turn lifecycle ─────────────────────────────────────────────────────────────

## start_of_turn(combatant) — clears ONLY per-TURN flags (TurnFlags:
## _movement_used, _action_used — ADR-103 / FEAT-003). Call once at the
## start of each combatant's turn.
##
## CR-001 AC-1: the 7-action budget is a per-ROUND resource, not a per-turn
## one. start_of_turn() therefore must NOT refill _budget, must NOT clear
## _is_spent, and must NOT touch _dazed — a combatant who became Spent
## earlier in the round stays Spent until the round boundary
## (end_of_round() / start_of_round()). Calling start_of_turn() repeatedly
## across multiple turns within the same round (AC-4 interleaving) is a
## no-op with respect to budget_remaining/is_spent.
##
## combatant — optional context parameter identifying the combatant whose
## turn is starting. Defaults to this ActionEconomy instance (which already
## represents a single combatant's economy). Passing null explicitly is
## treated as a contract violation: push_error() and no-op (no flags
## cleared).
func start_of_turn(combatant = self) -> void:
	if combatant == null:
		push_error("start_of_turn called on null combatant")
		return
	_movement_used = false
	_action_used = false


## start_of_round(combatant) / end_of_round(combatant) — the SOLE operations
## permitted to reset the per-ROUND budget (CR-001 AC-2 / ADR-001).
##
## Effect: budget_remaining = MAX_BUDGET; is_spent = false; movement_used is
## also cleared (a new round implies a new turn's worth of per-turn flags).
## MUST NOT touch _dazed — _dazed persists across rounds and is changed only
## via the explicit set_dazed() call.
##
## combatant — optional context parameter identifying the combatant whose
## round boundary this is. Defaults to this ActionEconomy instance. Passing
## null explicitly is treated as a contract violation: push_error() and
## no-op (no state mutated), matching start_of_turn()'s null-guard contract.
func start_of_round(combatant = self) -> void:
	if combatant == null:
		push_error("start_of_round called on null combatant")
		return
	_reset_round_state()


## end_of_round(combatant) — see start_of_round() above; identical contract.
## Both are the sole operations permitted to set budget_remaining =
## MAX_BUDGET and clear is_spent at a round boundary.
func end_of_round(combatant = self) -> void:
	if combatant == null:
		push_error("end_of_round called on null combatant")
		return
	_reset_round_state()


## _reset_round_state() — internal helper shared by start_of_round() and
## end_of_round() so the round-boundary reset logic exists in exactly one
## place. NEVER touches _dazed.
func _reset_round_state() -> void:
	_budget = MAX_BUDGET
	_is_spent = false
	_movement_used = false
	_action_used = false


# ── Action spending ────────────────────────────────────────────────────────────

## spend_action(action_metadata: Dictionary) → Dictionary
##
## Spends one action from the SAME per-ROUND budget_remaining pool that
## spend_reaction() draws from (CR-001 AC-3 / FEAT-003) — actions and
## reactions are unified against a single ActionBudget regardless of mix
## or turn ownership.
## action_metadata may include: {"traits": Array[String]}
##   "Movement" trait: only one movement action permitted per turn. This is
##   the exact gate core/rules/movement.gd's Stride() (FR-013 / US-014) spends
##   through — Stride tags its spend_action() call {"name": "Stride",
##   "traits": ["Movement"]} so a Stride and any other Movement-trait action
##   remain mutually exclusive within the same turn, sharing this single
##   pre-existing per-turn gate rather than introducing a parallel one. Step
##   (core/rules/movement.gd) is unaffected — it never calls spend_action() at
##   all (see movement.gd's file-level doc), so it never touches this gate.
##
## Returns a Result-style Dictionary carrying BOTH the legacy
## success/error/remaining keys (preserved for existing callers) and the
## ADR-002 ok/reason/budget_remaining keys (FEAT-003):
##   {success: true,  remaining: int,
##    ok: true, budget_remaining: int}          — action spent successfully
##   {success: false, error: "Spent", remaining: 0,
##    ok: false, reason: "ALREADY_SPENT",
##    budget_remaining: 0}                      — budget already exhausted;
##                                                 no further decrement occurs
##   {success: false, error: "Movement already used",
##    ok: false, reason: "MOVEMENT_ALREADY_USED"} — movement already used
##   {success: false, error: "Action already used",
##    ok: false, reason: "ACTION_ALREADY_USED"}   — ADR-103 / FEAT-003: a
##                                                   spend_action() has
##                                                   already succeeded this
##                                                   turn; this gate is
##                                                   checked BEFORE any
##                                                   budget mutation, so a
##                                                   rejected second call
##                                                   never decrements
##                                                   actions_remaining
##                                                   (FR-002). start_of_turn()
##                                                   clears this gate for the
##                                                   combatant's next turn.
##                                                   spend_reaction() is
##                                                   unaffected by this gate.
func spend_action(action_metadata: Dictionary) -> Dictionary:
	if _self_spend_suppressed:
		# FEAT-008 (US-008; FR-007; ADR-003): the no-self-spend execution
		# mode — see `_self_spend_suppressed`'s own field-level doc above.
		# Reports the ordinary success shape (no mutation at all) so the
		# caller (movement.gd's Stride() / resolve_action_use_case.gd's
		# _check_preconditions_and_spend()) proceeds to apply its own game
		# effect exactly as it would on a genuine spend, while the shared
		# budget/_action_used/_movement_used gates are left completely
		# untouched — Combine charges the ONE real action separately, once
		# its whole sub-action queue has resolved.
		return _spend_success_result()

	if _is_spent:
		return _already_spent_result()

	if _action_used:
		return {
			"success": false,
			"error": "Action already used",
			"ok": false,
			"reason": "ACTION_ALREADY_USED",
		}

	var traits: Array = action_metadata.get("traits", [])
	if traits.has("Movement") and _movement_used:
		return {
			"success": false,
			"error": "Movement already used",
			"ok": false,
			"reason": "MOVEMENT_ALREADY_USED",
		}

	_budget -= 1
	_action_used = true

	# Movement trait gates subsequent Movement actions this turn.
	if traits.has("Movement"):
		_movement_used = true

	if _budget <= 0:
		_is_spent = true

	return _spend_success_result()


## spend_reaction() → Dictionary
##
## Spends one action (reaction) from the IDENTICAL budget_remaining pool
## used by spend_action() (CR-001 AC-3 / FEAT-003) — callable out-of-turn
## (e.g. on an opponent's turn), with the deduction persisting into this
## combatant's own subsequent turn within the same round. No Movement gate.
## Sets _is_spent when budget reaches 0, regardless of action/reaction mix.
##
## Returns the same Result-style Dictionary shape as spend_action():
##   {success: true,  remaining: int, ok: true, budget_remaining: int}
##   {success: false, error: "Spent", remaining: 0,
##    ok: false, reason: "ALREADY_SPENT", budget_remaining: 0}
func spend_reaction() -> Dictionary:
	if _is_spent:
		return _already_spent_result()

	_budget -= 1

	if _budget <= 0:
		_is_spent = true

	return _spend_success_result()


## _already_spent_result() — shared Result-style failure payload for
## spend_action()/spend_reaction() when called on an already-Spent
## combatant. Returns without throwing and without decrementing _budget
## any further (FEAT-003).
func _already_spent_result() -> Dictionary:
	return {
		"success": false,
		"error": "Spent",
		"remaining": 0,
		"ok": false,
		"reason": "ALREADY_SPENT",
		"budget_remaining": 0,
	}


## _spend_success_result() — shared Result-style success payload for
## spend_action()/spend_reaction(), reporting the post-spend value of the
## single shared budget_remaining counter (FEAT-003).
func _spend_success_result() -> Dictionary:
	return {
		"success": true,
		"remaining": _budget,
		"ok": true,
		"budget_remaining": _budget,
	}


## use_step() — marks movement as used this turn (free action; no budget cost).
## Subsequent spend_action calls with the "Movement" trait will fail.
func use_step() -> void:
	mark_movement_used()


## mark_movement_used() — FEAT-001 (US-001 / FR-001 / FR-002 / ADR-003): trips
## the SAME per-turn Movement-trait gate (_movement_used) that
## spend_action({"traits": ["Movement"]}) already trips for Stride, WITHOUT
## decrementing budget_remaining or touching is_spent. This is the hook
## core/rules/movement.gd's step() calls so a Step and a Stride share exactly
## one gate: once either has been taken this turn, the other is locked out
## until the next start_of_turn() (no new flag/state machine is introduced —
## this reuses _movement_used and start_of_turn()'s existing clearing of it).
## Idempotent: calling it again while already tripped is a no-op observable
## from the outside.
func mark_movement_used() -> void:
	_movement_used = true


## can_take_movement_action() → bool
##
## Pure query, no side effects (FEAT-001 / ADR-003): true iff no
## Movement-trait action (Step via mark_movement_used()/use_step(), or Stride
## via spend_action({"traits": ["Movement"]})) has been taken yet this turn.
## This is the SINGLE SOURCE OF TRUTH later UI (verb-bar availability) and AI
## decision logic (ai.gd's pre-Stride check) are intended to read from,
## rather than re-deriving the gate's state independently.
func can_take_movement_action() -> bool:
	return not _movement_used


# ── No-self-spend execution mode (FEAT-008 / US-008; FR-007; ADR-003) ───────────

## begin_self_spend_suppression() — turns on the no-self-spend execution
## mode: every subsequent spend_action() call reports success WITHOUT
## mutating budget_remaining/is_spent/can_take_movement_action() state (see
## `_self_spend_suppressed`'s own field-level doc above). Intended to be
## paired with a matching end_self_spend_suppression() call bracketing
## exactly the sub-controller `execute()` call whose self-charge must be
## suppressed (presentation/stride_action_controller.gd /
## presentation/strike_action_controller.gd, when invoked as a Combine
## sub-action). Idempotent: calling it again while already suppressed is a
## no-op observable from the outside.
func begin_self_spend_suppression() -> void:
	_self_spend_suppressed = true


## end_self_spend_suppression() — turns the no-self-spend execution mode
## back off; every subsequent spend_action() call resumes its ordinary,
## budget-mutating contract. Idempotent.
func end_self_spend_suppression() -> void:
	_self_spend_suppressed = false


## is_self_spend_suppressed() -> bool — pure query, no side effects; true iff
## the no-self-spend execution mode is currently active.
func is_self_spend_suppressed() -> bool:
	return _self_spend_suppressed


# ── Conditions ────────────────────────────────────────────────────────────────

## set_dazed(value: bool) — applies or clears the Dazed condition.
## Dazed persists across rounds until explicitly cleared.
## While dazed, combine_actions() is forbidden.
func set_dazed(value: bool) -> void:
	_dazed = value


## combining_forbidden() → bool
## Returns true if action combining is currently forbidden.
## Combining is forbidden when the combatant is Dazed.
func combining_forbidden() -> bool:
	return _dazed


# ── Action combining (FR-003 / FEAT-058) ─────────────────────────────────────

## combine_actions(action_a, action_b, stamina_pool) → Dictionary
##
## Validates and records a Combination of two actions (FR-003 / US-007;
## Iteration N's FEAT-006 / US-006 / FR-005 layers the DIFFERENT-VERB-OR-
## SAME-VERB-WITH-REPEAT rule on top of the original all-Repeat-required
## check). Prerequisites (checked in order):
##   1. Combatant must not be Dazed.
##   2. If action_a and action_b are the SAME verb (action_a["name"] ==
##      action_b["name"]), BOTH must carry the "Repeat" trait — an
##      identical, non-Repeat pair is rejected. Two DIFFERENT verbs never
##      need the Repeat trait at all (e.g. Charge's [Stride, Strike] pair,
##      the v0 default presentation/combine_action_controller.gd's
##      enter_selection() offers).
##   3. stamina_pool must be ≥ 1.
##
## On success, returns stamina_pool - 1 as stamina_remaining.
## Does NOT decrement _budget — caller must spend_action() separately for each.
##
## Returns a Result-style Dictionary carrying BOTH the legacy success/error
## keys (preserved for existing callers, e.g. tests/unit/test_action_economy.gd)
## and the ADR-002/ADR-004-style ok/reason keys (FEAT-003, Iteration N
## Combinations) — the latter is what
## presentation/combine_action_controller.gd's execute()/enter_selection()
## read to reject a Combine BEFORE any Stamina spend or sub-action queueing,
## mirroring spend_action()'s own dual-shape upgrade (ADR-103) so this is the
## SOLE Stamina/verb-pair-check code path every caller (present and future)
## shares rather than re-deriving:
##   {success: false, error: "Cannot combine: Dazed",
##    ok: false, reason: "DAZED"}
##       — when _dazed is true
##   {success: false, error: "Combination requires Repeat trait on both actions: <name> missing Repeat",
##    ok: false, reason: "IDENTICAL_NON_REPEAT_VERBS"}
##       — when action_a and action_b are the SAME verb (identical "name")
##         and either lacks the "Repeat" trait
##   {success: false, error: "Insufficient Stamina for combination",
##    ok: false, reason: "INSUFFICIENT_STAMINA"}
##       — when stamina_pool < 1
##   {success: true, stamina_remaining: int, ok: true}
##       — combination accepted; stamina_remaining = stamina_pool - 1
func combine_actions(action_a, action_b, stamina_pool) -> Dictionary:
	if _dazed:
		return {
			"success": false,
			"error": "Cannot combine: Dazed",
			"ok": false,
			"reason": "DAZED",
		}

	var name_a = action_a.get("name", "action_a")
	var name_b = action_b.get("name", "action_b")

	# Same-verb pair (FR-005): both entries must carry "Repeat". Two
	# DIFFERENT verbs (e.g. Stride + Strike) skip this check entirely — the
	# Repeat trait is only ever relevant to a self-combined, identical pair.
	if name_a == name_b:
		var traits_a: Array = action_a.get("traits", [])
		var traits_b: Array = action_b.get("traits", [])
		if not traits_a.has("Repeat") or not traits_b.has("Repeat"):
			return {
				"success": false,
				"error": "Combination requires Repeat trait on both actions: %s missing Repeat" % name_a,
				"ok": false,
				"reason": "IDENTICAL_NON_REPEAT_VERBS",
			}

	if stamina_pool < 1:
		return {
			"success": false,
			"error": "Insufficient Stamina for combination",
			"ok": false,
			"reason": "INSUFFICIENT_STAMINA",
		}

	return {"success": true, "stamina_remaining": stamina_pool - 1, "ok": true}


# ── Inspection ────────────────────────────────────────────────────────────────

## get_remaining() → int
## Returns the current action budget for test inspection and UI display.
func get_remaining() -> int:
	return _budget


## is_spent() → bool
## Returns true if all 7 actions have been consumed this turn.
func is_spent() -> bool:
	return _is_spent


## can_take_action() → bool
##
## Pure query, no side effects (FEAT-005 / FR-003): true iff the combatant
## has neither already used its one action this turn (_action_used) NOR
## exhausted its per-round budget (is_spent()):
##   can_take_action() == (NOT _action_used) AND (NOT is_spent())
##
## This is the SINGLE SOURCE OF TRUTH later presentation (verb-bar Strike/
## Stride availability greying) and AI decision logic are intended to read
## from, rather than re-deriving the gate's state independently -- mirrors
## can_take_movement_action()'s role for the Movement-only gate.
func can_take_action() -> bool:
	return not _action_used and not is_spent()
