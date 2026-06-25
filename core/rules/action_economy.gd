## core/rules/action_economy.gd — Seven-Action Round Economy State Machine
##
## Domain layer (ADR-001): no Node/Control inheritance — pure game logic only.
## Manages the 7-action budget per combatant turn (ADR-006 / US-007).
##
## State managed:
##   _budget        — actions remaining this turn (0–7)
##   _is_spent      — true once all 7 actions are consumed
##   _movement_used — true once a Movement action or use_step() is used
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

## start_of_turn() — resets budget to 7, clears spent and movement flags.
## Call once at the start of each combatant's turn.
func start_of_turn() -> void:
	_budget = MAX_BUDGET
	_is_spent = false
	_movement_used = false


## end_of_round() — resets budget and clears turn flags.
## _dazed persists — it is cleared only via set_dazed(false).
func end_of_round() -> void:
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


# ── Action combining (Iteration 2 stub) ───────────────────────────────────────

## combine_actions(action_a, action_b, stamina_pool) → Dictionary
##
## Combining two actions is not yet implemented (planned for Iteration 2).
## If the combatant is Dazed, combining is explicitly forbidden.
##
## Returns:
##   {success: false, error: "Combining forbidden: Dazed"} when dazed
##   {success: false, error: "Not implemented — Iteration 2"} otherwise
func combine_actions(_action_a, _action_b, _stamina_pool) -> Dictionary:
	if _dazed:
		return {"success": false, "error": "Combining forbidden: Dazed"}
	return {"success": false, "error": "Not implemented — Iteration 2"}


# ── Inspection ────────────────────────────────────────────────────────────────

## get_remaining() → int
## Returns the current action budget for test inspection and UI display.
func get_remaining() -> int:
	return _budget


## is_spent() → bool
## Returns true if all 7 actions have been consumed this turn.
func is_spent() -> bool:
	return _is_spent
