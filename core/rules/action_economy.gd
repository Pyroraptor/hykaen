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
##   _dazed         — persists across rounds; gates action combining
##
## Usage example:
##   var ae = ActionEconomy.new()
##   ae.start_of_turn()
##   var result = ae.spend_action({"traits": ["Strike"]})
##   # → {success: true, remaining: 6}

class_name ActionEconomy

## Maximum action budget per turn (ADR-006).
const MAX_BUDGET: int = 7


var _budget: int = MAX_BUDGET
var _is_spent: bool = false
var _movement_used: bool = false
var _dazed: bool = false


# ── Turn lifecycle ─────────────────────────────────────────────────────────────

## start_of_turn(combatant) — clears ONLY per-TURN flags (TurnFlags:
## _movement_used). Call once at the start of each combatant's turn.
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


# ── Action spending ────────────────────────────────────────────────────────────

## spend_action(action_metadata: Dictionary) → Dictionary
##
## Spends one action from the budget.
## action_metadata may include: {"traits": Array[String]}
##   "Movement" trait: only one movement action permitted per turn.
##
## Returns:
##   {success: true,  remaining: int}           — action spent successfully
##   {success: false, error: "Spent",
##    remaining: 0}                             — budget already exhausted
##   {success: false, error: "Movement already used"} — movement already used
func spend_action(action_metadata: Dictionary) -> Dictionary:
	if _is_spent:
		return {"success": false, "error": "Spent", "remaining": 0}

	var traits: Array = action_metadata.get("traits", [])
	if traits.has("Movement") and _movement_used:
		return {"success": false, "error": "Movement already used"}

	_budget -= 1

	# Movement trait gates subsequent Movement actions this turn.
	if traits.has("Movement"):
		_movement_used = true

	if _budget <= 0:
		_is_spent = true

	return {"success": true, "remaining": _budget}


## spend_reaction() → Dictionary
##
## Spends one action (reaction) from the budget.
## Identical deduction logic to spend_action (no Movement gate).
## Sets _is_spent when budget reaches 0.
##
## Returns:
##   {success: true,  remaining: int}
##   {success: false, error: "Spent", remaining: 0}
func spend_reaction() -> Dictionary:
	if _is_spent:
		return {"success": false, "error": "Spent", "remaining": 0}

	_budget -= 1

	if _budget <= 0:
		_is_spent = true

	return {"success": true, "remaining": _budget}


## use_step() — marks movement as used this turn (free action; no budget cost).
## Subsequent spend_action calls with the "Movement" trait will fail.
func use_step() -> void:
	_movement_used = true


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
## Validates and records a Combination of two actions (FR-003 / US-007).
## Prerequisites (checked in order):
##   1. Combatant must not be Dazed.
##   2. action_a must have "Repeat" in its traits Array.
##   3. action_b must have "Repeat" in its traits Array.
##   4. stamina_pool must be ≥ 1.
##
## On success, returns stamina_pool - 1 as stamina_remaining.
## Does NOT decrement _budget — caller must spend_action() separately for each.
##
## Returns:
##   {success: false, error: "Cannot combine: Dazed"}
##       — when _dazed is true
##   {success: false, error: "Combination requires Repeat trait on both actions: <name> missing Repeat"}
##       — when action_a or action_b lacks the "Repeat" trait
##   {success: false, error: "Insufficient Stamina for combination"}
##       — when stamina_pool < 1
##   {success: true, stamina_remaining: int}
##       — combination accepted; stamina_remaining = stamina_pool - 1
func combine_actions(action_a, action_b, stamina_pool) -> Dictionary:
	if _dazed:
		return {"success": false, "error": "Cannot combine: Dazed"}

	var traits_a: Array = action_a.get("traits", [])
	if not traits_a.has("Repeat"):
		var name_a: String = action_a.get("name", "action_a")
		return {
			"success": false,
			"error": "Combination requires Repeat trait on both actions: %s missing Repeat" % name_a
		}

	var traits_b: Array = action_b.get("traits", [])
	if not traits_b.has("Repeat"):
		var name_b: String = action_b.get("name", "action_b")
		return {
			"success": false,
			"error": "Combination requires Repeat trait on both actions: %s missing Repeat" % name_b
		}

	if stamina_pool < 1:
		return {"success": false, "error": "Insufficient Stamina for combination"}

	return {"success": true, "stamina_remaining": stamina_pool - 1}


# ── Inspection ────────────────────────────────────────────────────────────────

## get_remaining() → int
## Returns the current action budget for test inspection and UI display.
func get_remaining() -> int:
	return _budget


## is_spent() → bool
## Returns true if all 7 actions have been consumed this turn.
func is_spent() -> bool:
	return _is_spent
