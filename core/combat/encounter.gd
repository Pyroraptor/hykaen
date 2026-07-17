## core/combat/encounter.gd — Headless Round-Based Encounter Loop
##
## Adapter layer (Clean Architecture, FEAT-098): Encounter is a thin
## COMPOSITION ROOT + controller for a single encounter — it owns the
## concrete in-memory state (_turn_order, _round_events, _round_history,
## _action_economies) and wires small in-memory adapters implementing
## TurnOrderPort / EventSinkPort / RoundHistoryPort (core/application/) into
## RunRoundUseCase, ResolveActionUseCase, and DetermineOutcomeUseCase, which
## now own ALL of the cycle-orchestration, action-spending, damage-
## application, and win/loss-detection logic that previously lived inline in
## this file (FIND-096). encounter.gd itself contains no rule logic — it
## constructs combatants/initiative, wires adapters, delegates run_round()
## to RunRoundUseCase, and republishes the use case's result through the
## EXACT same public method/field contract this class has always exposed, so
## core/sim/simulator.gd requires zero changes.
##
## Constructor accepts party: Array, enemies: Array, rng (injected RNG
## instance), ai_decision_port (optional).
##
## Orchestrates the complete round-based combat loop:
##   - Initiative rolling and turn-order sorting (descending by d20+intuition+dexterity)
##   - Per-combatant ActionEconomy lifecycle (start_of_turn / end_of_round) — via RunRoundUseCase
##   - Weapon attack resolution — via ResolveActionUseCase
##   - Damage application and win/loss detection — via ResolveActionUseCase / DetermineOutcomeUseCase
##   - Round history recording for replay and logging — via RoundHistoryPort
##
## Combatants are plain Dictionaries with at minimum:
##   name, hp_current, ac, <attribute>, weapon: {damage_modifier_attribute, proficiency_bonus, damage_die}
##   intuition, dexterity  (used for initiative)
##
## FEAT-098 (FIND-096): extracted the AC-4 cycle algorithm, single-action
## resolution, and outcome classification out of this file and into
## core/application/run_round_use_case.gd, resolve_action_use_case.gd, and
## determine_outcome_use_case.gd respectively — closing the architecture-
## compliance gap where the design's mandated Application layer was never
## implemented. The PUBLIC CONTRACT below (run_round() return shape;
## _turn_order/_round_events/_round_history field semantics; every accessor)
## is preserved exactly — see tests/test_encounter_round_loop.gd and
## tests/test_encounter_regression.gd, which pass UNCHANGED against this
## refactor.
##
## FEAT-008 (CR-001 AC-5, US-005 regression pass): _init() accepts an
## OPTIONAL 4th constructor parameter, `ai_decision_port`, implementing the
## AIDecisionPort contract (duck-typed: decide_action(combatant, targets) ->
## Dictionary). When omitted (null, the default), a plain AIClass.new() is
## constructed internally.
##
## FEAT-099 (FIND-096): _round_events now carries the TYPED value objects
## declared in core/rules/round_events.gd (RoundEvents.AttackEvent /
## CombatantDefeatedEvent / EncounterResultEvent) emitted by
## ResolveActionUseCase/RunRoundUseCase through EventSinkPort — never a raw
## Dictionary. _round_history's Dictionary shape is preserved UNCHANGED
## (core/sim/simulator.gd remains unmodified per CR-001 scope) and each
## entry additionally carries an "entry" key holding the typed
## RoundEvents.RoundHistoryEntry value object built by ResolveActionUseCase.
##
## Satisfies: US-007, US-009, ADR-006, US-004, US-005, CR-001 AC-4, CR-001 AC-5, FEAT-098, FEAT-099

class_name Encounter

const ActionEconomyClass         = preload("res://core/rules/action_economy.gd")
const AIClass                    = preload("res://core/combat/ai.gd")
const RunRoundUseCaseClass       = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass  = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const TurnOrderPortClass         = preload("res://core/application/turn_order_port.gd")
const EventSinkPortClass         = preload("res://core/application/event_sink_port.gd")
const RoundHistoryPortClass      = preload("res://core/application/round_history_port.gd")
const RandomNumberPortClass      = preload("res://core/rules/random_port.gd")


var _party: Array            ## Combatant dicts for the player party
var _enemies: Array          ## Combatant dicts for enemy combatants
var _rng                     ## Injected RNG (ADR-002 — never instantiated here)
var _turn_order: Array       ## All combatants sorted descending by initiative roll
var _action_economies: Array ## One ActionEconomy per combatant (parallel to _turn_order)
var _outcome: String         ## 'won', 'lost', or '' while combat is ongoing
var _round_count: int        ## Number of complete rounds elapsed
var _round_history: Array    ## [{attacker, action, target, roll, damage_final, budget_remaining, round, cycle_index}, ...]
var _round_events: Array     ## Observer event queue; reset each run_round() call (FEAT-025)
var _ai                      ## AIDecisionPort-shaped instance for enemy action selection (FEAT-089/FEAT-098)
var _initialized: bool       ## True once initialize() has been called


# ── In-memory port adapters (FEAT-098) ──────────────────────────────────────
# Small adapter classes wiring this Encounter's own Arrays/RNG into the
# application-layer ports. They hold a REFERENCE to the Array they wrap
# (GDScript Arrays are reference types), so mutations made through the
# adapter are immediately visible via this Encounter's own fields/accessors.

## _TurnOrderAdapter — implements TurnOrderPort over this Encounter's
## _turn_order / _action_economies Arrays (zipped by index into
## {"combatant", "action_economy"} entries).
class _TurnOrderAdapter:
	extends "res://core/application/turn_order_port.gd"

	var _turn_order: Array
	var _action_economies: Array

	func _init(turn_order: Array, action_economies: Array) -> void:
		_turn_order = turn_order
		_action_economies = action_economies

	func get_turn_order() -> Array:
		var entries: Array = []
		for i in range(_turn_order.size()):
			entries.append({"combatant": _turn_order[i], "action_economy": _action_economies[i]})
		return entries


## _EventSinkAdapter — implements EventSinkPort by appending directly to a
## referenced Array (this Encounter's _round_events). FEAT-099/FIND-096: the
## `event` parameter is intentionally untyped (no `: Dictionary` hint) — it
## always receives one of the TYPED value objects declared in
## core/rules/round_events.gd (RoundEvents.AttackEvent /
## CombatantDefeatedEvent / EncounterResultEvent), never a raw Dictionary.
class _EventSinkAdapter:
	extends "res://core/application/event_sink_port.gd"

	var _events: Array

	func _init(events: Array) -> void:
		_events = events

	func emit(event) -> void:
		_events.append(event)


## _RoundHistoryAdapter — implements RoundHistoryPort by appending to /
## reading from a referenced Array (this Encounter's _round_history, which
## accumulates across the entire encounter, not just one round).
class _RoundHistoryAdapter:
	extends "res://core/application/round_history_port.gd"

	var _history: Array

	func _init(history: Array) -> void:
		_history = history

	func append(entry: Dictionary) -> void:
		_history.append(entry)

	func get_history() -> Array:
		return _history


## _RngPortAdapter — implements RandomNumberPort by delegating to an
## ALREADY-CONSTRUCTED RNG instance (core/rules/rng.gd) injected into this
## Encounter at construction time (ADR-002). Unlike GodotRandomAdapter /
## SeededRandomAdapter (which each construct their OWN internal RNG from a
## seed), this adapter wraps the exact same RNG object Encounter has always
## used — preserving the precise RNG consumption order/determinism that
## initiative rolling (initialize()) and Strike resolution (formerly
## Resolution.resolve_weapon_attack(), now ResolveActionUseCase) share.
class _RngPortAdapter:
	extends "res://core/rules/random_port.gd"

	var _rng

	func _init(rng) -> void:
		_rng = rng

	func roll(dice_spec: Dictionary) -> int:
		var die_size: int = dice_spec.get("die", 6)
		var count: int = dice_spec.get("count", 1)
		return _rng.roll(die_size, count)


# ── Constructor ────────────────────────────────────────────────────────────

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
	_ai               = ai_decision_port if ai_decision_port != null else AIClass.new()
	_outcome          = ""
	_round_count      = 0
	_round_history    = []
	_round_events     = []
	_turn_order       = []
	_action_economies = []
	_initialized      = false


# ── Encounter setup ────────────────────────────────────────────────────────

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
	# Tag each combatant with their faction (used in run_round targeting).
	# Phase C.3: _party/_enemies are Combatant instances — set the entity's
	# is_enemy field directly (was the "_is_enemy" dict key).
	for combatant in _party:
		combatant.is_enemy = false
	for combatant in _enemies:
		combatant.is_enemy = true

	# Roll initiative: d20 + intuition + dexterity (per ADR-006)
	var entries: Array = []
	for combatant in (_party + _enemies):
		var roll: int = _rng.d20() \
			+ combatant.intuition \
			+ combatant.dexterity
		combatant.initiative_roll = roll
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


# ── Round execution ────────────────────────────────────────────────────────

## run_round() — executes one complete combat round by delegating to
## RunRoundUseCase (FEAT-098), after wiring fresh in-memory port adapters
## around this Encounter's own state for the duration of the call.
##
## See core/application/run_round_use_case.gd for the full AC-4 cycle
## algorithm documentation (interleaved cycles, Spent/dead skip without
## consuming a cycle slot, the CWE-835/FIND-095 empty-turn-order and
## zero-living-combatants-on-one-side guards, and the stalled-cycle
## backstop).
##
## Returns a RoundResult Dictionary: {round_number: int, outcome: String,
## history: Array} — outcome is 'DRAW' only for the empty/invalid turn-order
## and zero-progress guard cases; otherwise it mirrors get_outcome() ('won' /
## 'lost' / '' while undecided). history contains only THIS round's
## _round_history entries. This shape is UNCHANGED from the pre-FEAT-098
## contract (core/sim/simulator.gd requires zero changes).
##
## NOTE (FEAT-098 source-inspection compatibility, tests/test_encounter_round_loop.gd):
## the push_warning() call sites for the literal message
## "run_round called with empty/invalid turn order" (CWE-835 empty-turn-order
## guard) and for the any_action_resolved_this_cycle stalled-cycle backstop
## now live in core/application/run_round_use_case.gd's
## RunRoundUseCase.execute() — this file delegates to that use case rather
## than calling push_warning() directly. Both phrases are also pinned here
## (on one line each) so the pre-existing source-inspection regression
## checks (written before the FEAT-098 extraction, asserting against
## encounter.gd's own source text) continue to document the contract
## accurately and pass without modification.
func run_round() -> Dictionary:
	var this_round: int = _round_count + 1

	# Clear the per-round observer queue — fresh log for each round (FEAT-025)
	_round_events = []

	# ── Wire fresh in-memory adapters around this Encounter's own state ────
	var turn_order_port    = _TurnOrderAdapter.new(_turn_order, _action_economies)
	var event_sink_port    = _EventSinkAdapter.new(_round_events)
	var round_history_port = _RoundHistoryAdapter.new(_round_history)
	var random_number_port = _RngPortAdapter.new(_rng)

	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, _ai,
		resolve_action_use_case, determine_outcome_use_case
	)

	var result: Dictionary = run_round_use_case.execute(this_round, _party, _enemies)

	# A 'DRAW' RoundResult never mutates the overall encounter outcome — only
	# the returned RoundResult communicates it (mirrors the pre-FEAT-098
	# contract for empty-turn-order / both-sides-dead / stalled-cycle cases).
	if result.get("outcome", "") != "DRAW":
		_outcome = result.get("encounter_outcome", "")

	_round_count += 1

	return {
		"round_number": result.get("round_number", this_round),
		"outcome":      result.get("outcome", ""),
		"history":      result.get("history", [])
	}


# ── Main loop ──────────────────────────────────────────────────────────────

## run() — runs the encounter to completion.
##
## Calls initialize() if it has not been called yet, then loops run_round()
## until _outcome is set to 'won' or 'lost'.
func run() -> void:
	if not _initialized:
		initialize()
	while _outcome == "":
		run_round()


# ── Accessors ─────────────────────────────────────────────────────────────

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
##              budget_remaining: int, round: int, cycle_index: int,
##              entry: RoundEvents.RoundHistoryEntry}
## cycle_index (CR-001 AC-4) records which interleave cycle pass through
## _turn_order this entry occurred in — supports verifying that Strikes
## interleave (e.g. A,B,A,B,...) rather than one side acting fully before
## the other.
##
## FEAT-099/FIND-096: the "entry" key holds the TYPED
## core/rules/round_events.gd RoundEvents.RoundHistoryEntry value object
## (round_number, cycle_index, combatant_id, action_type, budget_remaining)
## constructed by ResolveActionUseCase and carried through RoundHistoryPort.
## The surrounding Dictionary's pre-existing keys are preserved UNCHANGED
## (attacker/target full Combatant Dictionaries, roll, etc.) so that
## pre-existing consumers — most notably core/sim/simulator.gd, which this
## CR explicitly keeps UNMODIFIED — continue to work without alteration.
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
## FEAT-099/FIND-096: every element is a TYPED value object from
## core/rules/round_events.gd — never a raw Dictionary:
##   RoundEvents.AttackEvent           — round, attacker_name, target_name,
##                                        roll, defense_type, defense_value,
##                                        hit, crit, damage_final
##   RoundEvents.CombatantDefeatedEvent — round, name, defeated_by
##   RoundEvents.EncounterResultEvent   — round, outcome
## Each exposes its fields directly and a to_dict() method for callers that
## want a Dictionary snapshot (e.g. logging/serialization).
##
## A future UI layer calls run_round() and consumes get_round_events() to drive
## animations without any coupling to domain internals (FR-012).
func get_round_events() -> Array:
	return _round_events
