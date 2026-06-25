## core/combat/encounter.gd — Headless Round-Based Encounter Loop
##
## Domain layer (ADR-001): pure GDScript class — no Node/Control inheritance.
## Constructor accepts party: Array, enemies: Array, rng (injected RNG instance).
##
## Orchestrates the complete round-based combat loop:
##   - Initiative rolling and turn-order sorting (descending by d20+intuition+dexterity)
##   - Per-combatant ActionEconomy lifecycle (start_of_turn / end_of_round)
##   - Weapon attack resolution via Resolution
##   - Damage application and win/loss detection after each attack
##   - Round history recording for replay and logging
##
## Combatants are plain Dictionaries with at minimum:
##   name, hp_current, ac, <attribute>, weapon: {damage_modifier_attribute, proficiency_bonus, damage_die}
##   intuition, dexterity  (used for initiative)
##
## FEAT-024: spend_action() is now called before each Strike. The combatant
## loops through all 7 actions per turn (striking until Spent or no target).
## If spend_action() returns {success: false}, the Strike is aborted.
##
## Satisfies: US-007, US-009, ADR-006

class_name Encounter

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


var _party: Array            ## Combatant dicts for the player party
var _enemies: Array          ## Combatant dicts for enemy combatants
var _rng                     ## Injected RNG (ADR-002 — never instantiated here)
var _turn_order: Array       ## All combatants sorted descending by initiative roll
var _action_economies: Array ## One ActionEconomy per combatant (parallel to _turn_order)
var _outcome: String         ## 'won', 'lost', or '' while combat is ongoing
var _round_count: int        ## Number of complete rounds elapsed
var _round_history: Array    ## [{attacker, action, target, roll, damage_final, budget_remaining, round}, ...]
var _resolution              ## Resolution instance (wraps the shared _rng)
var _initialized: bool       ## True once initialize() has been called


# ── Constructor ────────────────────────────────────────────────────────────────

## _init(party, enemies, rng) — stores parameters; does not roll initiative yet.
##
## party   — Array of combatant Dictionaries representing the player party.
## enemies — Array of combatant Dictionaries representing enemies.
## rng     — An RNG instance (core/rules/rng.gd) injected from outside (ADR-002).
func _init(party: Array, enemies: Array, rng) -> void:
	_party            = party
	_enemies          = enemies
	_rng              = rng
	_resolution       = ResolutionClass.new(rng)
	_outcome          = ""
	_round_count      = 0
	_round_history    = []
	_turn_order       = []
	_action_economies = []
	_initialized      = false


# ── Encounter setup ────────────────────────────────────────────────────────────

## initialize() — rolls initiative for each combatant and builds the sorted turn order.
##
## For each combatant in (party + enemies):
##   initiative = rng.d20() + combatant.intuition + combatant.dexterity
## The roll is stored on the combatant dict as "_initiative_roll" for inspection.
## A "_is_enemy" tag is also added to each combatant so run_round() can determine
## the opposing target pool without relying on Dictionary value-equality.
##
## Creates one ActionEconomy instance per combatant (parallel to _turn_order).
func initialize() -> void:
	# Tag each combatant with their faction (used in run_round targeting)
	for combatant in _party:
		combatant["_is_enemy"] = false
	for combatant in _enemies:
		combatant["_is_enemy"] = true

	# Roll initiative: d20 + intuition + dexterity (per ADR-006)
	var entries: Array = []
	for combatant in (_party + _enemies):
		var roll: int = _rng.d20() \
			+ combatant.get("intuition", 0) \
			+ combatant.get("dexterity", 0)
		combatant["_initiative_roll"] = roll
		entries.append({"combatant": combatant, "roll": roll})

	# Sort descending — highest initiative acts first
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["roll"] > b["roll"]
	)

	_turn_order       = []
	_action_economies = []
	for entry in entries:
		_turn_order.append(entry["combatant"])
		_action_economies.append(ActionEconomyClass.new())

	_initialized = true


# ── Round execution ────────────────────────────────────────────────────────────

## run_round() — executes one complete combat round.
##
## For each living combatant in _turn_order (in initiative order):
##   1. Calls start_of_turn() on their ActionEconomy (resets budget to 7).
##   2. Enters an action loop — each iteration:
##      a. Picks the first living combatant on the opposing side as target.
##         If no living target found, breaks the action loop.
##      b. Calls spend_action({name:'Strike', traits:[]}) on the ActionEconomy.
##         If {success: false} (Spent), breaks the action loop — no attack fired.
##      c. Resolves a weapon attack via Resolution (using "ac" as the defense type).
##      d. Applies damage_final to the target's hp_current.
##      e. Appends an attack record (including budget_remaining and round) to _round_history.
##      f. Checks win/loss:
##           all enemies hp <= 0 → _outcome = 'won'; break.
##           all party hp <= 0   → _outcome = 'lost'; break.
##   3. Continues action loop until Spent, no target, or combat ends.
##
## After iterating all combatants (or breaking early):
##   Calls end_of_round() on every ActionEconomy and increments _round_count.
func run_round() -> void:
	var this_round: int = _round_count + 1

	for i in range(_turn_order.size()):
		# Stop processing turns if the outcome has already been decided
		if _outcome != "":
			break

		var combatant: Dictionary = _turn_order[i]

		# Dead combatants skip their turn
		if combatant.get("hp_current", 0) <= 0:
			continue

		_action_economies[i].start_of_turn()

		# Select opposing target pool using the faction tag set in initialize()
		var is_enemy: bool    = combatant.get("_is_enemy", false)
		var target_pool: Array = _party if is_enemy else _enemies

		# ── Action loop: strike until Spent or no living target ───────────────
		while true:
			# Stop the action loop if the outcome was decided in a prior strike
			if _outcome != "":
				break

			# Pick first living target from the opposing pool
			var target: Dictionary = {}
			var found_target: bool = false
			for t in target_pool:
				if t.get("hp_current", 0) > 0:
					target       = t
					found_target = true
					break

			# No valid target on the opposing side — this combatant is done
			if not found_target:
				break

			# Spend action for Strike — if Spent, abort without resolving
			var spend_result: Dictionary = _action_economies[i].spend_action(
				{"name": "Strike", "traits": []}
			)
			if not spend_result["success"]:
				break  # Combatant is Spent; no attack fired for this iteration

			# Resolve weapon attack against the target's AC
			var weapon: Dictionary = combatant.get("weapon", {})
			var result: Dictionary = _resolution.resolve_weapon_attack(
				combatant, target, weapon, "ac"
			)

			# Apply damage to target
			var damage: int = result.get("damage_final", 0)
			if damage > 0:
				target["hp_current"] = target.get("hp_current", 0) - damage

			# Record the attack for logging / replay
			_round_history.append({
				"attacker":         combatant,
				"action":           "Strike",
				"target":           target,
				"roll":             result.get("roll_total", 0),
				"damage_final":     result.get("damage_final", 0),
				"budget_remaining": spend_result.get("remaining", -1),
				"round":            this_round
			})

			# Check win/loss after each attack (ADR-006)
			var all_enemies_dead: bool = true
			for e in _enemies:
				if e.get("hp_current", 0) > 0:
					all_enemies_dead = false
					break

			if all_enemies_dead:
				_outcome = "won"
				break

			var all_party_dead: bool = true
			for p in _party:
				if p.get("hp_current", 0) > 0:
					all_party_dead = false
					break

			if all_party_dead:
				_outcome = "lost"
				break

	# End of round — reset every combatant's ActionEconomy
	for ae in _action_economies:
		ae.end_of_round()

	_round_count += 1


# ── Main loop ──────────────────────────────────────────────────────────────────

## run() — runs the encounter to completion.
##
## Calls initialize() if it has not been called yet, then loops run_round()
## until _outcome is set to 'won' or 'lost'.
func run() -> void:
	if not _initialized:
		initialize()
	while _outcome == "":
		run_round()


# ── Accessors ─────────────────────────────────────────────────────────────────

## get_outcome() → String — 'won', 'lost', or '' while combat is ongoing.
func get_outcome() -> String:
	return _outcome


## get_turn_order() → Array — combatant dicts in descending initiative order.
## Each dict has "_initiative_roll" set after initialize().
func get_turn_order() -> Array:
	return _turn_order


## get_round_count() → int — number of complete rounds elapsed.
func get_round_count() -> int:
	return _round_count


## get_round_history() → Array — attack records from all rounds.
## Each entry: {attacker: Dictionary, action: String, target: Dictionary,
##              roll: int, damage_final: int,
##              budget_remaining: int, round: int}
func get_round_history() -> Array:
	return _round_history


## get_action_economy(index: int) → ActionEconomy — returns the ActionEconomy
## for the combatant at the given turn-order index. Useful for test inspection.
func get_action_economy(index: int):
	return _action_economies[index]
