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
## FEAT-006 (CR-001 AC-4): run_round() now executes a round as repeated
## CYCLES through _turn_order — each living, non-Spent combatant takes
## EXACTLY ONE action per cycle pass (Strikes therefore INTERLEAVE in
## initiative order, e.g. A,B,A,B,... for two combatants) instead of one
## side firing all 7 Strikes before the other acts. Dead/Spent combatants
## are skipped within a cycle WITHOUT consuming a cycle slot. The round
## terminates when every living combatant is Spent or the outcome is
## decided. start_of_round() is called once per combatant at the top of
## the round (NOT start_of_turn() — the per-round budget is granted via
## start_of_round(), per ADR-001/CR-001 AC-2); start_of_turn() is called
## once per combatant per cycle pass to clear per-TURN flags only (it is a
## documented no-op w.r.t. budget_remaining/is_spent — see action_economy.gd).
##
## FEAT-007 (CR-001 AC-4/AC-5, US-004/US-005): the _round_events and
## _round_history Arrays populated by run_round() below ARE the observability
## wiring this feature covers — 'attack'/'combatant_defeated'/'encounter_result'
## entries emitted in resolved order via EventSinkPort-shaped Array appends,
## and one RoundHistoryEntry-shaped Dictionary per resolved action/reaction
## carrying the correct post-spend budget_remaining and cycle_index. See
## tests/test_encounter_round_loop.gd for the dedicated FEAT-007 assertions.
##
## FEAT-008 (CR-001 AC-5, US-005 regression pass): _init() now accepts an
## OPTIONAL 4th constructor parameter, `ai_decision_port`, implementing the
## design's AIDecisionPort contract (duck-typed: must expose
## decide_action(combatant: Dictionary, targets: Array) -> Dictionary,
## identical to core/combat/ai.gd's AI class). When omitted (null, the
## default), behavior is UNCHANGED from pre-FEAT-008 — a plain AIClass.new()
## is constructed internally exactly as before, so every existing 3-arg call
## site (simulator.gd, sim_demo.gd, all pre-existing tests) is unaffected.
## The injection point exists purely to let regression tests substitute a
## counting/spy double to verify enemies are delegated to AI via
## AIDecisionPort EXACTLY ONCE per their cycle turn — see
## tests/test_encounter_regression.gd.
##
## Satisfies: US-007, US-009, ADR-006, US-004, US-005, CR-001 AC-4, CR-001 AC-5

class_name Encounter

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const AIClass            = preload("res://core/combat/ai.gd")


var _party: Array            ## Combatant dicts for the player party
var _enemies: Array          ## Combatant dicts for enemy combatants
var _rng                     ## Injected RNG (ADR-002 — never instantiated here)
var _turn_order: Array       ## All combatants sorted descending by initiative roll
var _action_economies: Array ## One ActionEconomy per combatant (parallel to _turn_order)
var _outcome: String         ## 'won', 'lost', or '' while combat is ongoing
var _round_count: int        ## Number of complete rounds elapsed
var _round_history: Array    ## [{attacker, action, target, roll, damage_final, budget_remaining, round}, ...]
var _round_events: Array     ## Observer event queue; reset each run_round() call (FEAT-025)
var _resolution              ## Resolution instance (wraps the shared _rng)
var _ai                      ## AI instance for enemy action selection (FEAT-089)
var _initialized: bool       ## True once initialize() has been called


# ── Constructor ────────────────────────────────────────────────────────────────

## _init(party, enemies, rng, ai_decision_port) — stores parameters; does not
## roll initiative yet.
##
## party            — Array of combatant Dictionaries representing the player party.
## enemies          — Array of combatant Dictionaries representing enemies.
## rng              — An RNG instance (core/rules/rng.gd) injected from outside (ADR-002).
## ai_decision_port — OPTIONAL (FEAT-008); an AIDecisionPort-shaped object
##                     (duck-typed: decide_action(combatant, targets) -> Dictionary).
##                     Defaults to null, in which case a plain AIClass.new() is
##                     constructed internally — IDENTICAL to pre-FEAT-008
##                     behavior. Pass a double here only to observe/intercept
##                     AI delegation (e.g. regression tests).
func _init(party: Array, enemies: Array, rng, ai_decision_port = null) -> void:
	_party            = party
	_enemies          = enemies
	_rng              = rng
	_resolution       = ResolutionClass.new(rng)
	_ai               = ai_decision_port if ai_decision_port != null else AIClass.new()
	_outcome          = ""
	_round_count      = 0
	_round_history    = []
	_round_events     = []
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

## run_round() — executes one complete combat round as interleaved cycles
## through _turn_order (CR-001 AC-4 / FEAT-006).
##
## Algorithm:
##   0. Guard: if _turn_order is empty/invalid, push_warning() and return a
##      RoundResult with outcome 'DRAW' without mutating combat state — no
##      crash on malformed/empty encounter setup.
##   1. Calls start_of_round() once on every combatant's ActionEconomy
##      (grants the fresh per-round budget; CR-001 AC-2).
##   2. Repeatedly cycles through _turn_order:
##      For each pass ("cycle") over _turn_order, every living, non-Spent
##      combatant takes EXACTLY ONE action:
##        a. Dead combatants are skipped — they do NOT consume a cycle slot.
##        b. Spent combatants (is_spent()==true) are skipped — they do NOT
##           consume a cycle slot.
##        c. start_of_turn() is called (clears per-TURN flags only; a
##           documented no-op w.r.t. budget/is_spent — see action_economy.gd).
##        d. Action + target selection: enemies delegate to AI (FEAT-089);
##           party members use the hardcoded Strike action against the
##           first living opposing combatant. No living target → the
##           combatant is skipped for this cycle (defensive guard; in
##           practice this implies the outcome was already decided).
##        e. spend_action() is called. A failed Result (ok:false /
##           success:false, e.g. ALREADY_SPENT) causes this combatant's
##           action to be skipped for the cycle — the loop CONTINUES rather
##           than aborting (CR-001 error handling contract).
##        f. On a successful spend, resolves the weapon attack, applies
##           damage, emits 'attack' / 'combatant_defeated' events, and
##           appends a _round_history entry (with budget_remaining and the
##           cycle_index it occurred in).
##        g. Checks win/loss after every resolved attack; once decided, an
##           'encounter_result' event is emitted and the round loop halts.
##   3. The round terminates when every living combatant is Spent OR the
##      outcome has been decided — never an unbounded loop, since each
##      successful spend strictly decreases the spending combatant's budget.
##   4. Calls end_of_round() on every ActionEconomy and increments _round_count.
##
## Returns a RoundResult Dictionary: {round_number: int, outcome: String,
## history: Array} — outcome is 'DRAW' only for the empty/invalid turn-order
## guard case; otherwise it mirrors get_outcome() ('won' / 'lost' / '' while
## undecided). history contains only THIS round's _round_history entries.
func run_round() -> Dictionary:
	var this_round: int = _round_count + 1

	# Clear the per-round observer queue — fresh log for each round (FEAT-025)
	_round_events = []

	# ── Guard: empty/invalid turn order — never throw, return a DRAW (FEAT-006) ──
	if _turn_order.is_empty():
		push_warning("run_round called with empty/invalid turn order")
		_round_count += 1
		return {
			"round_number": this_round,
			"outcome":      "DRAW",
			"history":      []
		}

	# ── Step 1: grant the fresh per-round budget to every combatant (AC-2) ──────
	for ae in _action_economies:
		ae.start_of_round()

	# ── Step 2: cycle through _turn_order until Spent-out or outcome decided ────
	var cycle_index: int = 0
	while _outcome == "" and _round_has_living_unspent_combatant():
		for i in range(_turn_order.size()):
			if _outcome != "":
				break

			var combatant: Dictionary = _turn_order[i]

			# Dead combatants are skipped — no cycle slot consumed (AC-4)
			if combatant.get("hp_current", 0) <= 0:
				continue

			# Spent combatants are skipped — no cycle slot consumed (AC-4)
			if _action_economies[i].is_spent():
				continue

			# Per-TURN flag reset only — documented no-op on budget/is_spent
			# when called repeatedly within the same round (AC-1/AC-4).
			_action_economies[i].start_of_turn()

			# Select opposing target pool using the faction tag set in initialize()
			var is_enemy: bool     = combatant.get("_is_enemy", false)
			var target_pool: Array = _party if is_enemy else _enemies

			# Determine action and target — enemies delegate to AI (FEAT-089),
			# party members use the hardcoded Strike action.
			var target: Dictionary  = {}
			var action_name: String = ""

			if is_enemy:
				# Enemy action selection: delegate to AI module (FR-012)
				var ai_decision: Dictionary = _ai.decide_action(combatant, target_pool)
				action_name = ai_decision.get("action_type", "")
				target      = ai_decision.get("target", {})
			else:
				# Party: pick first living target, hardcoded Strike action
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

			# Spend action — a failed Result (e.g. ALREADY_SPENT, a contract
			# violation since is_spent() was already checked above) causes
			# this combatant's action to be skipped; the cycle CONTINUES
			# rather than aborting/crashing (CR-001 error handling contract).
			var spend_result: Dictionary = _action_economies[i].spend_action(
				{"name": action_name, "traits": []}
			)
			if not spend_result["success"]:
				continue

			# Resolve weapon attack against the target's AC
			var weapon: Dictionary = combatant.get("weapon", {})
			var result: Dictionary = _resolution.resolve_weapon_attack(
				combatant, target, weapon, "ac"
			)

			# Capture defense value before modifying target state (FEAT-025)
			var defense_value: int = target.get("ac", 0)

			# Apply damage to target
			var damage: int = result.get("damage_final", 0)
			if damage > 0:
				target["hp_current"] = target.get("hp_current", 0) - damage

			# Append structured attack event to the per-round observer queue (FEAT-025)
			_round_events.append({
				"type":          "attack",
				"round":         this_round,
				"attacker_name": combatant.get("name", ""),
				"target_name":   target.get("name", ""),
				"roll":          result.get("roll_total", 0),
				"defense_type":  "ac",
				"defense_value": defense_value,
				"hit":           result.get("hit", false),
				"crit":          result.get("crit", false),
				"damage_final":  result.get("damage_final", 0)
			})

			# Emit combatant_defeated event if the target's HP just reached zero (FEAT-025)
			if target.get("hp_current", 0) <= 0:
				_round_events.append({
					"type":        "combatant_defeated",
					"round":       this_round,
					"name":        target.get("name", ""),
					"defeated_by": combatant.get("name", "")
				})

			# Record the attack for logging / replay — cycle_index records
			# which AC-4 interleave pass this entry occurred in.
			_round_history.append({
				"attacker":         combatant,
				"action":           action_name,
				"target":           target,
				"roll":             result.get("roll_total", 0),
				"damage_final":     result.get("damage_final", 0),
				"budget_remaining": spend_result.get("remaining", -1),
				"round":            this_round,
				"cycle_index":      cycle_index
			})

			# Check win/loss after each attack (ADR-006)
			var all_enemies_dead: bool = true
			for e in _enemies:
				if e.get("hp_current", 0) > 0:
					all_enemies_dead = false
					break

			if all_enemies_dead:
				_outcome = "won"
				# Emit encounter_result event when the encounter ends (FEAT-025)
				_round_events.append({
					"type":    "encounter_result",
					"round":   this_round,
					"outcome": _outcome
				})
				break

			var all_party_dead: bool = true
			for p in _party:
				if p.get("hp_current", 0) > 0:
					all_party_dead = false
					break

			if all_party_dead:
				_outcome = "lost"
				# Emit encounter_result event when the encounter ends (FEAT-025)
				_round_events.append({
					"type":    "encounter_result",
					"round":   this_round,
					"outcome": _outcome
				})
				break

		cycle_index += 1

	# End of round — reset every combatant's ActionEconomy
	for ae in _action_economies:
		ae.end_of_round()

	_round_count += 1

	var this_round_history: Array = []
	for entry in _round_history:
		if entry.get("round", -1) == this_round:
			this_round_history.append(entry)

	return {
		"round_number": this_round,
		"outcome":      _outcome,
		"history":      this_round_history
	}


## _round_has_living_unspent_combatant() → bool — true if at least one living
## combatant in _turn_order has not yet reached is_spent()==true. Used by the
## AC-4 cycle loop to determine when to stop cycling (every living combatant
## Spent) without relying on a fixed iteration count.
func _round_has_living_unspent_combatant() -> bool:
	for i in range(_turn_order.size()):
		var combatant: Dictionary = _turn_order[i]
		if combatant.get("hp_current", 0) <= 0:
			continue
		if not _action_economies[i].is_spent():
			return true
	return false


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
##              budget_remaining: int, round: int, cycle_index: int}
## cycle_index (FEAT-006 / CR-001 AC-4) records which interleave cycle pass
## through _turn_order this entry occurred in — supports verifying that
## Strikes interleave (e.g. A,B,A,B,...) rather than one side acting fully
## before the other.
func get_round_history() -> Array:
	return _round_history


## get_action_economy(index: int) → ActionEconomy — returns the ActionEconomy
## for the combatant at the given turn-order index. Useful for test inspection.
func get_action_economy(index: int):
	return _action_economies[index]


## get_round_events() → Array — per-round observer event queue (FEAT-025).
##
## Returns the structured event list populated during the most recent run_round() call.
## The queue is cleared at the start of each run_round() so observers poll after each round.
##
## Event types emitted:
##   {type:'attack', round:int, attacker_name:String, target_name:String,
##    roll:int, defense_type:String, defense_value:int, hit:bool, crit:bool, damage_final:int}
##   {type:'combatant_defeated', round:int, name:String, defeated_by:String}
##   {type:'encounter_result', round:int, outcome:String}
##
## A future UI layer calls run_round() and consumes get_round_events() to drive
## animations without any coupling to domain internals (FR-012).
func get_round_events() -> Array:
	return _round_events
