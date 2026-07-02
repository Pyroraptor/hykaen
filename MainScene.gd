extends Node
## MainScene.gd — project composition root (ADR-006 / US-004 / FEAT-005;
## FEAT-123 / US-004,009,010,011,012, FIND-120)
##
## This is the SINGLE place Infrastructure adapters are wired to Application
## ports for the whole game (manual DI via the scene tree — no DI framework,
## per ADR-002). project.godot's run/main_scene points at MainScene.tscn
## (which attaches this script), so launching the project boots directly
## into the prologue encounter (US-004) — the steel thread's entry_point.
##
## Wiring performed in _ready():
##   1. ResourceEncounterRepository (infrastructure/resource_encounter_repository.gd)
##      loads data/encounters/prologue_encounter.tres and builds the domain
##      hex-positioned Combatant list (US-001) — the repository adapter.
##   2. GodotRandomAdapter (core/combat/godot_random_adapter.gd) is
##      constructed from `resolved_seed` (FEAT-002/003 / US-002/003) — the
##      RandomPort adapter for the interactive ResolveActionUseCase pipeline
##      below (step 9). `resolved_seed` is resolved via
##      infrastructure/seed_policy.gd's SeedPolicy.resolve_from_environment()
##      (ADR-004), which honors, in order: `seed_override` (an in-process
##      injectable property GUT tests may set BEFORE add_child()/_ready()
##      completes composition, e.g. to pin the prologue fixture's seed=42
##      for the double-boot determinism regression), then the HYKAEN_SEED
##      environment variable (fails open to random on a malformed/absent
##      value, NFR-006), then a fresh Time.get_ticks_usec()-derived value so
##      real (non-test) launches never replay the same fixed playthrough
##      (FR-001/NFR-002). data/encounters/prologue_encounter.tres' `seed`
##      field (42) remains the deterministic fixture used by
##      core/sim/simulator.gd and other tests that construct their own RNG
##      directly — it is intentionally no longer read here.
##   3. ConsoleEventSinkAdapter (defined below) implements EventSinkPort by
##      mirroring every round event to stdout AND forwarding it to every
##      subscribed Presentation projection (StatusPanelView/InitiativeView/
##      EventLogView/ResultScreenView) — the ONE event-sink adapter every
##      Strike/AI-turn/turn-advance flows through, whether it happens at boot
##      or later in response to player input (ADR-003).
##   4. HexGridView (presentation/hex_grid_view.gd, instanced as this node's
##      "HexGridView" child in MainScene.tscn) is handed the SAME
##      hex-positioned Combatant list from step 1 via load_combatants(), so a
##      person running the project (not headless) sees the flat-top hex
##      battlefield with all combatants placed on load (US-005).
##   5. StatusPanelView / InitiativeView (FEAT-008/US-006, FEAT-009/US-007)
##      are handed an initial snapshot (name/HP/Stamina/action-budget/Spent/
##      conditions, and name/initiative_order respectively) built from the
##      SAME Encounter composition helper (core/combat/encounter.gd) used to
##      roll initiative and grant each combatant an ActionEconomy — Encounter
##      is reused ONLY for that initiative/ActionEconomy bookkeeping here; its
##      autonomous run_round() while-loop is never invoked (see step 8-10).
##   6. EventLogView (presentation/event_log_view.gd) has no snapshot step (it
##      is append-only, starting empty) and receives every round event via
##      the event-sink adapter's forwarding (step 3) exactly like
##      StatusPanelView/InitiativeView — no Presentation projection ever
##      reaches into Encounter/ActionEconomy itself (read-only, ADR-003).
##   7. Encounter (core/combat/encounter.gd) is constructed and initialize()d
##      SOLELY to roll initiative and build one ActionEconomy per combatant
##      (reusing that existing, tested bookkeeping) — its run_round() method
##      is intentionally NEVER called by this composition root (FEAT-123 /
##      FIND-120): the old "while outcome == '' : encounter.run_round()"
##      autonomous batch loop that resolved the whole encounter on boot with
##      no player input has been removed.
##   8. RunRoundUseCase.begin_round(1, party, enemies) (core/application/
##      run_round_use_case.gd, ADR-007) is called instead, wired with a
##      TurnOrderPort adapter reading Encounter's turn order/ActionEconomy
##      bookkeeping from step 7, the EventSinkPort from step 3, an in-memory
##      RoundHistoryPort, the REAL core/combat/ai.gd AIDecisionPort, and a
##      ResolveActionUseCase wired to the RandomPort from step 2. This
##      returns a real, non-null RoundSession (core/application/
##      round_session.gd) — the resumable, stepwise interactive cycle state
##      a human drives one turn at a time, exposed on this node as
##      `round_session` for verification.
##   9. TurnController ($TurnController, presentation/turn_controller.gd) is
##      handed the RoundSession plus the already-instantiated
##      $EndTurnControl/$StrikeActionControl child controls via set_session()
##      (US-010/US-011): it immediately auto-drives any leading Enemy turns
##      and configures $EndTurnControl's enabled state for whoever the
##      session now sits on. This node subscribes to TurnController's
##      active_actor_changed/round_over signals (FIND-120) to reconfigure
##      $StrikeActionControl's live targets for the new active player
##      combatant and to clear it once the round is over — TurnController
##      itself has no live-target data of its own to re-derive that from
##      (see presentation/turn_controller.gd's documented division of
##      responsibility).
##  10. $EndTurnControl's own turn_ended signal (emitted after its press()
##      forwards directly to RoundSession.end_current_turn(), US-010) is
##      subscribed here so this composition root can re-invoke
##      TurnController.set_session() with the SAME RoundSession afterward —
##      TurnController's set_session() is documented safe to call repeatedly
##      and always re-drives any consecutive Enemy turns via
##      RoundSession.advance_ai_turn() before yielding back to the player
##      (US-011) — giving the player-presses-EndTurn -> AI-turns-resolve flow
##      a single, non-duplicated entry point without introducing any new
##      public API on either control (ADR-002/CR-001 guardrail).
##  11. $ResultScreenView (presentation/result_screen_view.gd, US-012) is
##      configured with $StrikeActionControl/$EndTurnControl so that once the
##      EncounterResultEvent this pipeline emits reaches it (via the SAME
##      event-sink forwarding every other projection uses), it renders
##      Win/Loss and disables both combat input controls.
##
## No new ports or use cases are introduced here beyond the ADR-007-declared
## RoundSession stepwise API RunRoundUseCase already exposes (ADR-002 / CR-001
## guardrail) — this file only constructs adapters around the pre-existing
## ports/use cases/Presentation controls and wires them together.

const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")
const SeedPolicyClass                  = preload("res://infrastructure/seed_policy.gd")
const GodotRandomAdapterClass          = preload("res://core/combat/godot_random_adapter.gd")
const EncounterClass                   = preload("res://core/combat/encounter.gd")
const RNGClass                         = preload("res://core/rules/rng.gd")
const AttributesClass                  = preload("res://core/rules/attributes.gd")
const WeaponResourceClass              = preload("res://core/model/weapon_resource.gd")
const ArmorResourceClass               = preload("res://core/model/armor_resource.gd")
const ResolveActionUseCaseClass        = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass     = preload("res://core/application/determine_outcome_use_case.gd")
const RunRoundUseCaseClass             = preload("res://core/application/run_round_use_case.gd")
const AIClass                          = preload("res://core/combat/ai.gd")
const StrikeInputControllerClass       = preload("res://scenes/battlefield/StrikeInputController.gd")
const EndTurnControllerClass           = preload("res://scenes/battlefield/EndTurnController.gd")
const MovementInputControllerClass     = preload("res://presentation/movement_input_controller.gd")

## The steel-thread's entry_point: the one encounter this composition root boots into.
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## EnemyResource carries no AC field in the v0 schema; 12 mirrors the
## production convention already established for enemies built from
## EnemyResource data (core/sim/simulator.gd / tests/integration/test_steel_thread_e2e.gd).
const DEFAULT_ENEMY_AC: int = 12

## The single round this composition root drives interactively this
## iteration (FEAT-123 / ADR-007's RoundSession stepwise API). Multi-round
## continuation (calling begin_round() again once a round ends without a
## decided outcome) is out of this feature's scope.
const ROUND_NUMBER: int = 1


## ConsoleEventSinkAdapter — concrete EventSinkPort adapter (ADR-006):
## mirrors every emitted round event to stdout via print() AND forwards it to
## every Presentation projection registered in `forward_to` (FEAT-123) — the
## ONE integration point between the Application-layer round events this
## composition root's use cases emit and every subscribed Presentation
## projection (StatusPanelView/InitiativeView/EventLogView/ResultScreenView),
## whether the event happens synchronously at boot or later as a result of
## live player/AI input.
class ConsoleEventSinkAdapter:
	extends "res://core/application/event_sink_port.gd"

	var log: Array = []

	## forward_to — Presentation nodes exposing on_round_event(event); set by
	## this composition root once every subscriber has been instantiated.
	var forward_to: Array = []

	func emit(event) -> void:
		log.append(event)
		if event.has_method("to_dict"):
			print("INFO: round event ", event.to_dict())
		else:
			print("INFO: round event ", event)
		for target in forward_to:
			if target != null:
				target.on_round_event(event)


## _EncounterTurnOrderAdapter — implements TurnOrderPort (core/application/
## turn_order_port.gd) over an already-initialize()d Encounter's PUBLIC
## accessors (get_turn_order() / get_action_economy()) — reusing Encounter's
## existing, tested initiative-rolling/ActionEconomy bookkeeping (step 7
## above) without reaching into its private fields or calling its
## autonomous run_round() (FEAT-123 / FIND-120).
class _EncounterTurnOrderAdapter:
	extends "res://core/application/turn_order_port.gd"

	var _encounter

	func _init(p_encounter) -> void:
		_encounter = p_encounter

	func get_turn_order() -> Array:
		var order: Array = _encounter.get_turn_order()
		var entries: Array = []
		for i in range(order.size()):
			entries.append({"combatant": order[i], "action_economy": _encounter.get_action_economy(i)})
		return entries


## InMemoryRoundHistoryAdapter — implements RoundHistoryPort (core/
## application/round_history_port.gd) over a plain in-memory Array owned by
## this composition root, mirroring the pattern already established by
## core/combat/encounter.gd's own private _RoundHistoryAdapter.
class InMemoryRoundHistoryAdapter:
	extends "res://core/application/round_history_port.gd"

	var _entries: Array = []

	func append(entry: Dictionary) -> void:
		_entries.append(entry)

	func get_history() -> Array:
		return _entries


## seed_override — in-process injectable seed policy (FEAT-002 / US-002;
## precedence formalized by FEAT-003 / US-003 / ADR-004, see SeedPolicyClass
## above). null | int. Composition-root contract: GUT tests (or any other
## caller) may set this on a freshly-instantiated-but-not-yet-added-to-the-tree
## MainScene BEFORE add_child() triggers _ready() to pin `resolved_seed`
## to a known value (e.g. 42, matching the prologue fixture, for
## determinism regressions such as tests/integration/
## test_steel_thread_prologue_encounter.gd's double-boot diff). Left null
## (the default) so `resolved_seed` instead falls through to the HYKAEN_SEED
## environment variable, then to a random value — see `resolved_seed` below.
var seed_override = null

## resolved_seed — the actual int seed this boot's RNGClass/GodotRandomAdapter
## were constructed with, computed once in _ready() via
## SeedPolicyClass.resolve_from_environment() (FEAT-003 / US-003 / ADR-004):
##   1. seed_override (IN_PROCESS_INJECTED), when non-null
##   2. the HYKAEN_SEED environment variable, when it parses as a valid
##      integer (a malformed/unset value fails open to (3) rather than
##      blocking boot, NFR-006)
##   3. a fresh Time.get_ticks_usec()-derived value (RANDOM)
## Exposed (rather than left a private local) so tests can assert a real,
## non-override, no-env-var launch never resolves to data/encounters/
## prologue_encounter.tres' hardcoded fixture seed (42), and that two
## independent such launches resolve to different values (FR-001/NFR-002).
var resolved_seed: int = -1

## encounter_repository — the repository adapter instantiated at the
## composition root (ADR-006).
var encounter_repository

## random_port — the production RandomPort adapter instantiated at the
## composition root (ADR-006), seeded for determinism (NFR-002/006) and
## wired into resolve_action_use_case below (FEAT-123) for every Strike this
## interactive pipeline resolves, whether a player's or the AI's.
var random_port

## event_sink — the EventSinkPort adapter instantiated at the composition
## root (ADR-006); every round event this pipeline emits passes through it.
var event_sink

## encounter — the Encounter (core/combat/encounter.gd) reused SOLELY for
## initiative rolling / per-combatant ActionEconomy bookkeeping (FEAT-123);
## its run_round() is intentionally never invoked by this composition root.
var encounter

## round_session — the interactive RoundSession (core/application/
## round_session.gd) obtained via RunRoundUseCase.begin_round() (FEAT-123 /
## ADR-007). Non-null once _ready() completes — this is the resumable,
## stepwise cycle state $TurnController/$StrikeActionControl/$EndTurnControl
## drive one turn at a time, replacing the old autonomous run_round()
## while-loop.
var round_session

## run_round_use_case / resolve_action_use_case / determine_outcome_use_case /
## round_history_port — the Application-layer use cases/ports wired at this
## composition root for the interactive pipeline (FEAT-123), exposed for
## verification.
var run_round_use_case
var resolve_action_use_case
var determine_outcome_use_case
var round_history_port

## outcome — '' | 'won' | 'lost'; mirrors round_session.outcome() and is
## refreshed once the round concludes (see _on_round_over()). Exposed for
## verification (manual smoke test and automated GUT coverage) — no longer
## guaranteed non-empty immediately after _ready() (FEAT-123 / FIND-120):
## the encounter is no longer auto-resolved on boot without player input.
var outcome: String = ""

## hex_grid_view — the HexGridView (presentation/hex_grid_view.gd) instanced
## in MainScene.tscn (FEAT-007 / US-005). Populated with one
## CombatantTokenView per combatant loaded from the prologue encounter so a
## person running the project (not headless) sees the hex battlefield with
## all combatants at boot.
@onready var hex_grid_view = $HexGridView

## hex_battlefield — the HexBattlefield (scenes/battlefield/HexBattlefield.gd)
## instanced in MainScene.tscn (FEAT-005 / US-005). Populated with the same
## hex-positioned Combatant list as hex_grid_view above, PLUS the
## name/HP/Stamina/action-budget/Spent/conditions view-model snapshot
## already built for status_panel_view (step 5 in the file-level doc above)
## so each of its per-combatant CombatantReadout children renders the full
## US-005 readout in one composed widget. Subscribed to the same
## event-sink forwarding every other Presentation projection uses
## (ADR-003) so its readouts update live as Strikes resolve.
@onready var hex_battlefield = $HexBattlefield

## status_panel_view — the StatusPanelView (presentation/status_panel_view.gd)
## instanced in MainScene.tscn (FEAT-008 / US-006). Populated with a
## name/HP/Stamina/action-budget/Spent/conditions snapshot for every
## combatant loaded from the prologue encounter, then updated per round
## event as the interactive session progresses.
@onready var status_panel_view = $StatusPanelView

## initiative_view — the InitiativeView (presentation/initiative_view.gd)
## instanced in MainScene.tscn (FEAT-009 / US-007). Populated with the
## domain-determined turn order (name + initiative_order) for every
## combatant loaded from the prologue encounter, then updated per round
## event as the interactive session progresses.
@onready var initiative_view = $InitiativeView

## turn_order_widget — the TurnOrderWidget (scenes/battlefield/
## TurnOrderWidget.gd) instanced as a child of $HexBattlefield in
## HexBattlefield.tscn (FEAT-006 / US-006), completing the steel thread's
## "turn order" surface alongside the hex battlefield renderer. Populated
## with the SAME turn-order view-model snapshot handed to `initiative_view`
## above (no separate initiative computation), then updated per
## TurnAdvancedEvent as run_round_use_case's interactive cycle advances the
## active combatant.
@onready var turn_order_widget = $HexBattlefield/TurnOrderWidget

## event_log_view — the EventLogView (presentation/event_log_view.gd)
## instanced in MainScene.tscn (FEAT-010 / US-008). Append-only — starts
## empty and receives every round event as the interactive session
## progresses, so a person running the project (not headless) sees a
## chronologically ordered, human-readable combat log for the whole
## encounter.
@onready var event_log_view = $EventLogView

## strike_action_control — the StrikeActionControl (presentation/
## strike_action_control.gd) instanced in MainScene.tscn (FEAT-109 /
## US-009). Reconfigured with the live active player combatant/targets by
## this composition root every time TurnController's active_actor_changed
## signal fires (FEAT-123 / FIND-120).
@onready var strike_action_control = $StrikeActionControl

## strike_input_controller — the StrikeInputController (scenes/battlefield/
## StrikeInputController.gd) instantiated directly (FEAT-007 / US-007 -- no
## companion .tscn, mirroring scenes/battlefield/CombatantReadout.gd's
## code-only-instantiation convention). Reconfigured alongside
## strike_action_control every time TurnController's active_actor_changed
## signal fires, so the SAME live actor/action-economy/targets data drives
## both -- StrikeInputController never derives its own copy of that data.
## Unlike strike_action_control, it is also handed `hex_battlefield`
## (FEAT-005) so it can reuse that widget's already-loaded hex positions and
## visibly mark in-range/out-of-range targets on it (US-007's UI-affordance
## criterion), and it is handed `active_combatant_id` so
## resolve_action_use_case can enforce turn order (defense in depth) on every
## Strike this control forwards.
var strike_input_controller = StrikeInputControllerClass.new()

## movement_input_controller — the MovementInputController (presentation/
## movement_input_controller.gd) instantiated directly (FEAT-013 / US-013 --
## no companion .tscn, mirroring strike_input_controller's own
## code-only-instantiation convention above). Reconfigured alongside
## strike_action_control/strike_input_controller every time TurnController's
## active_actor_changed signal fires, so the SAME live actor/occupancy data
## drives it. Handed `hex_grid_view` (FEAT-007) so a successful Step
## visibly repositions the mover's token there, and is wired to
## hex_grid_view's hex_clicked signal (below) so clicking a highlighted hex
## on the battlefield performs a Step -- the interactive destination-picking
## UI FEAT-013 adds. A Step never goes through resolve_action_use_case (it
## has no action-economy/event side effects, core/rules/movement.gd, ADR-002)
## -- but it DOES move the SAME live combatant Dictionary Strike reach reads
## from, so _on_active_actor_changed() is re-invoked after every successful
## Step to re-gate strike_action_control/strike_input_controller's in-reach
## target sets from the new position.
var movement_input_controller = MovementInputControllerClass.new()

## end_turn_controller — the EndTurnController (scenes/battlefield/
## EndTurnController.gd) instantiated directly (FEAT-008 / US-008 -- no
## companion .tscn, mirroring strike_input_controller's own
## code-only-instantiation convention above). Configured once with the live
## round_session (round_session's identity is stable for the single round
## this composition root drives, ADR-007), it is the round-advancement path
## a player-facing "pass"/"end turn" affordance forwards to. Its turn_ended
## signal is wired to the SAME _on_end_turn_control_turn_ended handler
## $EndTurnControl already uses (below), so either input path re-invokes
## TurnController.set_session() to auto-drive any consecutive Enemy turn(s)
## before yielding back to the player (US-011) -- no duplicated wiring.
var end_turn_controller = EndTurnControllerClass.new()

## turn_controller — the TurnController (presentation/turn_controller.gd)
## instanced in MainScene.tscn (FEAT-110/111, US-010/US-011). Handed the
## live round_session by this composition root (FEAT-123).
@onready var turn_controller = $TurnController

## end_turn_control — the EndTurnControl (presentation/end_turn_control.gd)
## instanced in MainScene.tscn (FEAT-110, US-010).
@onready var end_turn_control = $EndTurnControl

## result_screen_view — the ResultScreenView (presentation/
## result_screen_view.gd) instanced in MainScene.tscn (FEAT-112, US-012).
@onready var result_screen_view = $ResultScreenView

## result_screen — the ResultScreen (scenes/battlefield/ResultScreen.gd)
## instanced in MainScene.tscn (FEAT-010, US-010). Configured with the live
## _party/_enemies combatant Dictionaries plus strike_input_controller/
## end_turn_controller (scenes/battlefield/, FEAT-007/FEAT-008) so that once
## the EncounterResultEvent this pipeline emits reaches it (via the SAME
## event-sink forwarding every other projection uses), it renders Win/Loss
## with the final combatant snapshot and full event log, and locks both
## scenes/battlefield/ input controllers (US-010's exit_point).
@onready var result_screen = $ResultScreen

## _party / _enemies — the live combatant Dictionaries built at boot,
## mutated in place by every resolved Strike throughout the interactive
## session (Dictionaries are reference types in GDScript). Kept as fields so
## this composition root's own signal handlers (reacting to
## TurnController's active_actor_changed/round_over) can rebuild
## StrikeActionControl's live target list without re-deriving it from
## Infrastructure.
var _party: Array = []
var _enemies: Array = []


func _ready() -> void:
	encounter_repository = ResourceEncounterRepositoryClass.new()
	var hex_combatants: Array = encounter_repository.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	if hex_grid_view != null:
		hex_grid_view.load_combatants(hex_combatants)

	var encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	if encounter_resource == null:
		push_error("MainScene: failed to load " + PROLOGUE_ENCOUNTER_PATH)
		return

	# ── FEAT-002/003 / US-002/003: separate the real-play seed from the
	# fixture seed baked into prologue_encounter.tres (42), via
	# SeedPolicyClass's precedence rule (ADR-004): an explicit
	# `seed_override` (set in-process before this node was added to the
	# tree) always wins, for determinism tests/reproducible runs; otherwise
	# the HYKAEN_SEED environment variable is consulted (fails open to
	# random on a malformed/absent value, NFR-006); otherwise a fresh
	# Time.get_ticks_usec()-derived value is resolved so real launches are
	# never pinned to the fixture's replayable playthrough. ────────────────
	resolved_seed = SeedPolicyClass.resolve_from_environment(seed_override, int(Time.get_ticks_usec()))

	random_port = GodotRandomAdapterClass.new(resolved_seed)
	event_sink = ConsoleEventSinkAdapter.new()

	_party = []
	for i in range(encounter_resource.party_resource_paths.size()):
		var party_hex = hex_combatants[i].hex_coord if i < hex_combatants.size() else null
		var party_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		_party.append(_build_party_combatant(encounter_resource.party_resource_paths[i], party_hex, party_id))

	var party_count: int = encounter_resource.party_resource_paths.size()
	_enemies = []
	for j in range(encounter_resource.enemy_resource_paths.size()):
		var idx: int = party_count + j
		var enemy_hex = hex_combatants[idx].hex_coord if idx < hex_combatants.size() else null
		var enemy_id: String = hex_combatants[idx].combatant_id if idx < hex_combatants.size() else ""
		_enemies.append(_build_enemy_combatant(encounter_resource.enemy_resource_paths[j], enemy_hex, enemy_id))

	var rng := RNGClass.new(resolved_seed)
	encounter = EncounterClass.new(_party, _enemies, rng)
	encounter.initialize()

	var status_view_models: Array = _build_status_view_models(hex_combatants, _party, _enemies, encounter)

	if status_panel_view != null:
		status_panel_view.load_combatants(status_view_models)

	if hex_battlefield != null:
		hex_battlefield.load_combatants(hex_combatants, status_view_models)

	var initiative_view_models: Array = _build_initiative_view_models(hex_combatants, _party, _enemies, encounter)

	if initiative_view != null:
		initiative_view.load_combatants(initiative_view_models)

	if turn_order_widget != null:
		turn_order_widget.load_combatants(initiative_view_models)

	event_sink.forward_to = _presentation_event_subscribers()

	# ── FEAT-123 / FIND-120: build the interactive pipeline (RunRoundUseCase
	# .begin_round() -> RoundSession) instead of driving the autonomous
	# core/combat/encounter.gd run_round() while-loop. ─────────────────────
	var turn_order_port = _EncounterTurnOrderAdapter.new(encounter)
	round_history_port = InMemoryRoundHistoryAdapter.new()
	resolve_action_use_case = ResolveActionUseCaseClass.new(random_port, event_sink, round_history_port)
	determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var ai_decision_port = AIClass.new()
	run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	round_session = run_round_use_case.begin_round(ROUND_NUMBER, _party, _enemies)

	# ── FEAT-008 / US-008: bind the new EndTurnController to the SAME live
	# round_session -- the round-advancement path a "pass"/"end turn" input
	# forwards to (ADR-007: reuses run_round_use_case's RoundSession, no
	# duplicate turn-sequencing path). ──────────────────────────────────────
	end_turn_controller.configure(round_session)
	end_turn_controller.turn_ended.connect(_on_end_turn_control_turn_ended)

	if result_screen_view != null:
		result_screen_view.configure(strike_action_control, end_turn_control)

	if result_screen != null:
		result_screen.configure(_party + _enemies, strike_input_controller, end_turn_controller)

	if turn_controller != null:
		turn_controller.active_actor_changed.connect(_on_active_actor_changed)
		turn_controller.round_over.connect(_on_round_over)

	if end_turn_control != null:
		end_turn_control.turn_ended.connect(_on_end_turn_control_turn_ended)

	if turn_controller != null:
		turn_controller.set_session(round_session, end_turn_control, strike_action_control)

	# ── FEAT-013 / US-013: wire the interactive Step destination-picking UI --
	# clicking a hex highlighted by movement_input_controller performs a Step
	# on the currently active combatant. ────────────────────────────────────
	if hex_grid_view != null:
		hex_grid_view.hex_clicked.connect(_on_hex_grid_view_hex_clicked)

	outcome = round_session.outcome()

	print(
		"INFO: Hykaen MainScene booted into the prologue encounter (interactive) -- "
		+ "current_actor=" + str(round_session.current_actor().get("name", ""))
		+ " round_over=" + str(round_session.is_round_over())
	)


## _presentation_event_subscribers() -> Array — every instantiated
## Presentation projection that subscribes to the EventSinkPort broadcast
## (ADR-003): StatusPanelView/InitiativeView/EventLogView/ResultScreenView/
## HexBattlefield. HexGridView (the earlier, positional-only hex renderer)
## is NOT an EventSinkPort subscriber (a Strike never moves a combatant in
## this steel thread) — see presentation/turn_controller.gd's file-level doc
## for the precedent this mirrors. HexBattlefield (FEAT-005 / US-005) IS a
## subscriber because its per-combatant CombatantReadout children must
## update HP/conditions live as AttackEvent/CombatantDefeatedEvent fire.
## turn_order_widget (FEAT-006 / US-006) is likewise a subscriber, so its
## active-combatant highlight advances live on every TurnAdvancedEvent,
## exactly like initiative_view's existing subscription. result_screen
## (scenes/battlefield/ResultScreen.gd, FEAT-010) is also a subscriber, so it
## renders Win/Loss (with the final combatant snapshot and full event log)
## and locks the scenes/battlefield/ input controllers the moment
## EncounterResultEvent reaches it, exactly like result_screen_view's
## existing subscription for its presentation/ counterparts.
func _presentation_event_subscribers() -> Array:
	var subscribers: Array = []
	for view in [
		status_panel_view, initiative_view, event_log_view, result_screen_view,
		hex_battlefield, turn_order_widget, result_screen,
	]:
		if view != null:
			subscribers.append(view)
	return subscribers


## _on_active_actor_changed(combatant) -> void — TurnController
## (presentation/turn_controller.gd) emits this once it settles on a new
## (player) current actor, whether at boot or after auto-driving a run of
## Enemy turns (FEAT-123 / FIND-120). Reconfigures $StrikeActionControl with
## the live actor/action-economy/live-target data TurnController itself does
## not own (see turn_controller.gd's documented division of responsibility).
## Also reconfigures strike_input_controller (FEAT-007) with that SAME data
## plus hex_battlefield, so its in-range/out-of-range affordance and its
## resolve_action_use_case wiring both stay live for whichever combatant's
## turn it now is -- no separate data path of its own.
func _on_active_actor_changed(combatant: Dictionary) -> void:
	if round_session == null:
		return
	var action_economy = round_session.current_action_economy()
	var living_enemies: Array = _living_combatants(_enemies)
	var active_combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))

	if strike_action_control != null:
		strike_action_control.configure(
			combatant,
			action_economy,
			resolve_action_use_case,
			living_enemies,
			ROUND_NUMBER,
			0
		)

	strike_input_controller.configure(
		combatant,
		action_economy,
		resolve_action_use_case,
		living_enemies,
		active_combatant_id,
		ROUND_NUMBER,
		0,
		hex_battlefield
	)

	movement_input_controller.configure(
		combatant,
		_other_living_combatants(combatant),
		hex_grid_view,
		active_combatant_id
	)


## _on_round_over() -> void — TurnController emits this once the held
## RoundSession reports is_round_over(). Refreshes `outcome` and defensively
## clears $StrikeActionControl (no acting combatant, no selectable targets)
## even for the case where the round ends without a decided
## EncounterResultEvent (ResultScreenView only reacts to that terminal
## event; this is a defensive backstop for that gap, FEAT-123). Also clears
## strike_input_controller (FEAT-007) the same way.
func _on_round_over() -> void:
	if round_session != null:
		outcome = round_session.outcome()
	if strike_action_control != null:
		strike_action_control.configure({}, null, null, [])
	strike_input_controller.configure({}, null, null, [])
	movement_input_controller.configure({}, [])


## _on_end_turn_control_turn_ended(_result) -> void — either $EndTurnControl's
## own press() OR end_turn_controller's press() (FEAT-008 / US-008 — both
## forward directly to the SAME RoundSession.end_current_turn(), US-010) emit
## this signal (connected to both, above) with that call's result. This
## composition root reacts by re-invoking TurnController.set_session() with
## the SAME RoundSession (documented safe to call repeatedly) so any
## consecutive Enemy turn(s) the cursor now sits on are auto-driven via
## RoundSession.advance_ai_turn() before yielding back to the player
## (US-011) — the single, non-duplicated entry point for "player passes ->
## AI turns resolve" (FEAT-123 / FIND-120), without introducing any new
## public API on either control (ADR-002/CR-001 guardrail).
func _on_end_turn_control_turn_ended(_result: Dictionary) -> void:
	if turn_controller == null or round_session == null:
		return
	if round_session.is_round_over():
		return
	turn_controller.set_session(round_session)


## _on_hex_grid_view_hex_clicked(hex_coord) -> void — FEAT-013 / US-013:
## hex_grid_view's hex_clicked signal handler. Forwards directly to the
## injected, REUSED movement_input_controller.step_to() (ADR-002: no
## duplicate movement path) -- a click on a hex that controller never offered
## as a selectable Step destination (including before any actor has been
## configured, e.g. before the first active_actor_changed signal) is simply
## rejected there with no effect. On a successful Step, re-invokes
## _on_active_actor_changed() with the SAME (now-moved) current actor so
## strike_action_control/strike_input_controller re-gate their in-reach
## target sets from the new position (Strike reach re-gate, FEAT-013's
## test_criteria) -- this composition root never re-derives that reach logic
## itself, it only re-triggers the SAME reconfiguration path US-009 already
## established.
func _on_hex_grid_view_hex_clicked(hex_coord) -> void:
	if round_session == null:
		return
	var result: Dictionary = movement_input_controller.step_to(hex_coord)
	if result.get("ok", false):
		_on_active_actor_changed(round_session.current_actor())


## _other_living_combatants(combatant) -> Array — every living (hp_current >
## 0) combatant in _party + _enemies EXCEPT `combatant` itself, identified by
## the same "combatant_id" falling back to "name" convention used throughout
## this file -- the occupancy list movement_input_controller.configure()
## requires (core/rules/movement.gd Movement.step()'s `other_combatants`
## parameter must never include the mover itself).
func _other_living_combatants(combatant: Dictionary) -> Array:
	var self_id: String = combatant.get("combatant_id", combatant.get("name", ""))
	var others: Array = []
	for c in _living_combatants(_party + _enemies):
		if c.get("combatant_id", c.get("name", "")) != self_id:
			others.append(c)
	return others


## _living_combatants(combatants) -> Array — the subset of `combatants` with
## hp_current > 0, mirroring the living-target filter core/combat/ai.gd and
## core/application/round_session.gd already apply internally, so
## StrikeActionControl is never offered an already-defeated target.
func _living_combatants(combatants: Array) -> Array:
	var living: Array = []
	for c in combatants:
		if c.get("hp_current", 0) > 0:
			living.append(c)
	return living


## _build_party_combatant(character_path, hex_coord, combatant_id) -> Dictionary
##
## Builds the Dictionary shape core/application/resolve_action_use_case.gd
## expects (US-004 reuses the existing party pipeline) from a
## CharacterResource, its class_ref, and the first WeaponResource /
## ArmorResource found among its starting_equipment. hex_coord (a
## core/geometry/hex_coord.gd HexCoord, or null) is attached so melee
## reach-gating (US-003) applies when present. combatant_id (the domain
## Combatant's stable id from ResourceEncounterRepository, or "") is
## attached so Presentation controls (StrikeActionControl/StatusPanelView)
## can identify this combatant consistently with HexGridView's tokens.
func _build_party_combatant(character_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	var character = ResourceLoader.load(character_path)
	var class_data = character.class_ref

	var weapon_res = null
	var armor_res = null
	for equip_path in character.starting_equipment:
		var equip = ResourceLoader.load(equip_path)
		if equip is WeaponResourceClass:
			weapon_res = equip
		elif equip is ArmorResourceClass:
			armor_res = equip

	var attrs := AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(character.attributes, class_data)
	var ac: int = attrs.compute_ac(character.attributes, armor_res.ac_base, armor_res.category)
	var stamina: int = attrs.compute_stamina(character.attributes, class_data)

	var combatant: Dictionary = {
		"name":       character.name,
		"hp_current": hp,
		"hp_max":     hp,
		"stamina":    stamina,
		"ac":         ac,
		"strength":   character.attributes.get("strength",  0),
		"dexterity":  character.attributes.get("dexterity", 0),
		"intuition":  character.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
			"proficiency_bonus":         weapon_res.proficiency_bonus,
			"damage_die":                weapon_res.damage_die
		}
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	if combatant_id != "":
		combatant["combatant_id"] = combatant_id
	return combatant


## _build_enemy_combatant(enemy_path, hex_coord, combatant_id) -> Dictionary
##
## Builds the Dictionary shape core/application/resolve_action_use_case.gd
## expects from an EnemyResource. hex_coord (a core/geometry/hex_coord.gd
## HexCoord, or null) is attached so melee reach-gating (US-003) applies
## when present. combatant_id (see _build_party_combatant() above) is
## attached so Presentation controls can identify this combatant
## consistently with HexGridView's tokens.
func _build_enemy_combatant(enemy_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	var enemy = ResourceLoader.load(enemy_path)

	var attribute_map: Dictionary = {"str": "strength", "dex": "dexterity"}
	var raw_attribute: String = enemy.weapon.get("attribute", "strength")
	var weapon_attribute: String = attribute_map.get(raw_attribute, raw_attribute)

	var combatant: Dictionary = {
		"name":       enemy.name,
		"hp_current": enemy.hp,
		"hp_max":     enemy.hp,
		"stamina":    0,
		"ac":         DEFAULT_ENEMY_AC,
		"strength":   enemy.str,
		"dexterity":  enemy.dex,
		"intuition":  0,
		"weapon": {
			"damage_modifier_attribute": weapon_attribute,
			"proficiency_bonus":         enemy.weapon.get("proficiency_bonus", 1),
			"damage_die":                enemy.weapon.get("die", 6)
		}
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	if combatant_id != "":
		combatant["combatant_id"] = combatant_id
	return combatant


## _build_status_view_models(hex_combatants, party, enemies, encounter) -> Array
##
## Builds the read-only view-model list handed to
## presentation/status_panel_view.gd's load_combatants() (FEAT-008 / US-006):
## one Dictionary per combatant with keys combatant_id/name/hp_current/
## hp_max/stamina_current/stamina_max/action_budget_remaining/spent/
## conditions. hex_combatants[i] (the domain Combatant built in step 1,
## carrying combatant_id) corresponds index-for-index to `party` then
## `enemies` (the SAME correspondence already relied on above for hex_coord
## assignment) -- combatant identity is joined by that shared index, never by
## reaching back into Encounter/ActionEconomy from StatusPanelView itself.
##
## action_budget_remaining/spent are read once, immediately after
## encounter.initialize(), from each combatant's freshly-constructed
## ActionEconomy (core/rules/action_economy.gd) -- resolved by name via
## encounter.get_turn_order()/get_action_economy(), since initiative sorting
## reorders combatants relative to `party`/`enemies`. conditions defaults to
## an empty Array -- no per-combatant Condition list exists in the domain
## model yet (a later iteration-B feature), so the panel simply shows none
## until that data exists.
func _build_status_view_models(hex_combatants: Array, party: Array, enemies: Array, encounter_instance) -> Array:
	var action_economy_by_name: Dictionary = {}
	var turn_order: Array = encounter_instance.get_turn_order()
	for i in range(turn_order.size()):
		action_economy_by_name[turn_order[i].get("name", "")] = encounter_instance.get_action_economy(i)

	var all_combatants: Array = party + enemies
	var view_models: Array = []
	for i in range(all_combatants.size()):
		var combatant: Dictionary = all_combatants[i]
		var combatant_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		var action_economy = action_economy_by_name.get(combatant.get("name", ""), null)

		view_models.append({
			"combatant_id":             combatant_id,
			"name":                     combatant.get("name", ""),
			"hp_current":               combatant.get("hp_current", 0),
			"hp_max":                   combatant.get("hp_max", combatant.get("hp_current", 0)),
			"stamina_current":          combatant.get("stamina", 0),
			"stamina_max":              combatant.get("stamina", 0),
			"action_budget_remaining":  action_economy.get_remaining() if action_economy != null else 0,
			"spent":                    action_economy.is_spent() if action_economy != null else false,
			"conditions":               [],
		})
	return view_models


## _build_initiative_view_models(hex_combatants, party, enemies, encounter_instance) -> Array
##
## Builds the read-only view-model list handed to
## presentation/initiative_view.gd's load_combatants() (FEAT-009 / US-007):
## one Dictionary per combatant with keys combatant_id/name/initiative_order.
## combatant_id is resolved via the SAME name-keyed join already used by
## _build_status_view_models() above (hex_combatants[i] corresponds
## index-for-index to `party` then `enemies`) -- InitiativeView never reaches
## back into Encounter itself to obtain this data.
##
## encounter_instance.get_turn_order() (core/combat/encounter.gd) is already
## the domain-determined turn order -- sorted descending by each
## combatant's "_initiative_roll" (d20 + intuition + dexterity, per ADR-006)
## -- so that per-combatant roll is passed through unchanged as
## initiative_order; InitiativeView performs its own descending sort at load
## time, so the exact order handed in here is not itself load-bearing.
func _build_initiative_view_models(hex_combatants: Array, party: Array, enemies: Array, encounter_instance) -> Array:
	var combatant_id_by_name: Dictionary = {}
	var all_combatants: Array = party + enemies
	for i in range(all_combatants.size()):
		var combatant_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		combatant_id_by_name[all_combatants[i].get("name", "")] = combatant_id

	var view_models: Array = []
	for combatant in encounter_instance.get_turn_order():
		var name: String = combatant.get("name", "")
		view_models.append({
			"combatant_id":     combatant_id_by_name.get(name, ""),
			"name":             name,
			"initiative_order": combatant.get("_initiative_roll", 0),
		})
	return view_models
