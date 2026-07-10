extends Node
## MainScene.gd — project composition root (ADR-006 / US-004 / FEAT-005;
## FEAT-123 / US-004,009,010,011,012, FIND-120; FEAT-001/US-001 UI
## consolidation, iteration D; FEAT-006 / US-006, iteration E; FEAT-176 /
## US-012, cancel/back affordance, ADR-005)
##
## This is the SINGLE place Infrastructure adapters are wired to Application
## ports for the whole game (manual DI via the scene tree — no DI framework,
## per ADR-002). project.godot's run/main_scene points at MainScene.tscn
## (which attaches this script), so launching the project boots directly
## into the prologue encounter (US-004) — the steel thread's entry_point.
##
## Iteration D / FEAT-001 (US-001, ADR-002 single composition root): this
## composition root now wires EXACTLY ONE presentation stack — HexGridView,
## StatusPanelView, InitiativeView, EventLogView, EndTurnControl,
## TurnController, ResultScreenView, and the movement_input_controller. The
## earlier, duplicate widget stack this file used to also instantiate
## alongside it has been removed entirely — no parallel hex grid, status
## readout, turn/initiative tracker, or result screen remains wired here.
##
## Iteration E / FEAT-006 (US-006, FR-009): the legacy immediate-resolve-on-
## click StrikeActionControl node/script (presentation/strike_action_control.gd)
## has been REMOVED entirely -- it rendered one Button per in-reach enemy and
## resolved a Strike the instant that button was pressed, competing with the
## Layer 1 (verb bar) / Layer 2 (target selection) flow FEAT-003/004/005
## introduced. Strike is now driven SOLELY through `_verb_registry`'s STRIKE
## entry (_verb_bar_strike_availability()/_enter_selection()/_execute() below),
## which computes the same in-reach target filter (mirroring
## resolve_action_use_case.gd's own reach precondition, ADR-001) directly
## against the LIVE round_session.current_actor()/`_enemies`, and forwards a
## chosen target_id straight to the SAME, REUSED resolve_action_use_case
## (ADR-002/CR-001: no duplicate action path, no new port/use case) — there is
## now exactly ONE Strike code path for a future Layer 2 SelectionOverlay /
## post-resolution lock to hook into (design notes' stated purpose of this
## feature), rather than two competing ones.
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
##      FEAT-009 / US-009 / FR-014 (ADR-003): every subsequent Strike this
##      pipeline resolves emits an AttackEvent additionally carrying the
##      ACTING combatant's post-resolution actor_updated_action_budget
##      ({remaining, spent} — core/application/resolve_action_use_case.gd).
##      That AttackEvent reaches $StatusPanelView through the EXACT SAME
##      ConsoleEventSinkAdapter.forward_to broadcast every other round event
##      already uses (step 3/6 below) — $StatusPanelView.on_attack_event()
##      resolves the attacker's combatant_id and pushes the snapshot via
##      update_action_budget() itself; this composition root introduces no
##      new event-routing of its own for it (ADR-002/CR-001 guardrail).
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
##      handed the RoundSession plus the already-instantiated $EndTurnControl
##      child control via set_session() (US-010/US-011): it immediately
##      auto-drives any leading Enemy turns and configures $EndTurnControl's
##      enabled state for whoever the session now sits on. This node
##      subscribes to TurnController's active_actor_changed/round_over
##      signals (FIND-120) to refresh `_verb_registry`'s STRIKE availability
##      (FEAT-006) for the new active player combatant and to re-gate it once
##      the round is over — TurnController itself has no live-target data of
##      its own to re-derive that from (see presentation/turn_controller.gd's
##      documented division of responsibility).
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
##  11. $ResultScreenView (presentation/result_screen_view.gd, US-012;
##      FEAT-005 / US-005 / FR-011 / ADR-005; FEAT-167) is configured with
##      $EndTurnControl/movement_input_controller (its first,
##      strike_action_control, argument is no longer supplied -- FEAT-006
##      removed that node; see this file's FEAT-006 doc above) so that once
##      the EncounterResultEvent this pipeline emits reaches it (via the SAME
##      event-sink forwarding every other projection uses), it renders
##      Win/Loss and uniformly locks all remaining combat/movement input
##      controls via lock_all_controls() (idempotent, ADR-005 -- no new event
##      bus, the SAME EventSinkPort subscription drives every post-resolution
##      lock). FEAT-007 (this iteration): the fourth, move_action_control,
##      argument is likewise no longer supplied -- presentation/
##      MoveActionControl.gd (the passive "Move" indicator FEAT-167 above
##      used to also lock here) has been deleted entirely; Step/Stride are
##      now driven solely through `_verb_registry`'s STEP/STRIDE entries,
##      re-gated by the SAME $VerbBarView.refresh_availability() every other
##      verb already relies on -- there is no separate visible-affordance
##      Control left needing its own lock() call. FEAT-177 (US-013 /
##      FR-013): `verb_bar_view`/`selection_overlay` are additionally
##      injected (fifth/sixth arguments) so lock_all_controls() ALSO locks
##      the Layer 1 verb bar (VerbBarView.lock()) and any open Layer 2
##      selection (SelectionOverlay.lock()) -- extending the SAME lock
##      mechanism rather than reimplementing it, closing the steel thread's
##      exit-point guarantee that "controls lock post-resolution" across
##      every remaining interactive surface.
##  12. $ReactionPromptUI (scenes/ui/reaction_prompt_ui.tscn, FEAT-207 /
##      US-013 / FR-015) — the player-facing blocking reaction pop-up — is
##      wrapped by a freshly-constructed PlayerReactionChooser
##      (presentation/player_reaction_chooser.gd), and both it and a
##      freshly-constructed ReactionWindow (core/application/
##      reaction_window.gd, wired to the SAME `event_sink` every other use
##      case emits through) are injected into $TurnController via
##      configure_reactions() — the live integration point for
##      presentation/turn_controller.gd's resolve_reaction().
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
const MovementInputControllerClass     = preload("res://presentation/movement_input_controller.gd")
const FlankingClass                    = preload("res://core/rules/flanking.gd")
const CoordinateTransformClass         = preload("res://presentation/infrastructure/coordinate_transform.gd")
const HexGridViewClass                 = preload("res://presentation/hex_grid_view.gd")
const HexCoordClass                    = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                     = preload("res://core/geometry/hex_math.gd")
const VerbBarViewClass                 = preload("res://presentation/verb_bar_view.gd")
const SelectionOverlayClass            = preload("res://presentation/selection_overlay.gd")
const CancelControllerClass            = preload("res://presentation/cancel_controller.gd")
const ReactionWindowClass              = preload("res://core/application/reaction_window.gd")
const PlayerReactionChooserClass       = preload("res://presentation/player_reaction_chooser.gd")
const HexChoiceResolverPortClass       = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const AttackEventClass                 = preload("res://core/log/attack_event.gd")
const RenderCombatLogUseCaseClass      = preload("res://core/application/render_combat_log_use_case.gd")

## AIReactionPolicyClass — iteration K FEAT-004 (US-004, ADR-004):
## infrastructure/ai_reaction_policy.gd's AIReactionPolicy, the enemy AI's
## deterministic, synchronous ReactionChooserPort implementation. Wired ONLY
## here (see `enemy_reaction_chooser` field below) — MainScene is the ONE
## place a concrete adapter is ever bound to a port (ADR-002/G2), mirroring
## `player_reaction_chooser`'s identical precedent for the player-facing pop-up.
const AIReactionPolicyClass            = preload("res://infrastructure/ai_reaction_policy.gd")

## The steel-thread's entry_point: the one encounter this composition root boots into.
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## FEAT-002 (US-002 / FR-012, ADR-003): fallback viewport dimensions used to
## derive the boot-time centering offset (see _compute_boot_centering_offset())
## when project.godot declares no explicit display/window/size override --
## matching this project's actual default window size (verified by
## tests/gut/test_viewport_centering.gd against ProjectSettings directly).
const DEFAULT_VIEWPORT_WIDTH: int = 1152
const DEFAULT_VIEWPORT_HEIGHT: int = 648

## ROUND_NUMBER — FEAT-006 (US-004/FR-004, ADR-012): the round this
## composition root is CURRENTLY driving interactively (FEAT-123 / ADR-007's
## RoundSession stepwise API). A runtime `var`, NOT a `const` — _on_round_over()
## increments it by exactly 1 immediately before calling rewire_session()
## again whenever a round concludes WITHOUT a decided encounter outcome
## (natural full-budget exhaustion, or the no-progress backstop's forced
## per-round DRAW — see round_session.gd's finish() doc), so the steel
## thread's exit point ("a combat round runs end-to-end without hanging,
## including across multiple undecided rounds") is realized as repeated
## RunRoundUseCase.begin_round(ROUND_NUMBER, ...) calls stamping the correct,
## ever-increasing round number on every event/history entry the next round
## emits. Starts at 1 for the very first round, exactly as the pre-FEAT-006
## constant did.
var ROUND_NUMBER: int = 1

## ACTION_NAME_STRIKE — FEAT-006: the action name passed to
## resolve_action_use_case.resolve() for a Strike, mirroring the removed
## presentation/strike_action_control.gd's identically-valued ACTION_NAME
## constant ("Strike" is the one melee action that exists in the current
## ruleset).
const ACTION_NAME_STRIKE: String = "Strike"


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


## _UIHexChoiceResolver — the production, composition-root-only default
## implementation of core/application/ports/hex_choice_resolver_port.gd's
## HexChoiceResolverPort (FEAT-001 / US-004, ADR-002/G2). Wired ONLY here
## (see `hex_choice_resolver` field + resolve_hex_choice() below) — this
## class is never instantiated by a test, mirroring the ADR-002/G2
## discipline every other seam in this file already follows
## (PlayerReactionChooser, the AI-Stride token-reposition Callable, etc.).
## Establishes the seam a future Dodge-Step selection window (US-005/US-006/
## US-007) will use; nothing in this feature yet wires it into
## round_session/turn_controller.
##
## resolve(legal_hexes) blocks on `hex_grid_view`'s REAL hex_clicked signal
## (presentation/hex_grid_view.gd — the same click channel the Step/Stride
## Layer-2 selection flow already uses) and loops until the player actually
## clicks one of `legal_hexes` — an off-target click is silently ignored and
## the wait continues, so this adapter can NEVER fabricate/guess an answer
## of its own (this feature's G3 anti-punt discipline: "requires/blocks on
## real human/UI input when not scripted, never silently returns an
## arbitrary hex"). An empty `legal_hexes` short-circuits to null
## immediately — there is nothing to click, so there is nothing to wait for
## (the one legal case for a null return, per the port's own contract).
class _UIHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var _hex_grid_view

	func _init(p_hex_grid_view) -> void:
		_hex_grid_view = p_hex_grid_view

	func resolve(legal_hexes: Array):
		if legal_hexes.is_empty():
			return null
		# Highlight the legal Dodge-Step destinations on the battlefield, reusing
		# the SAME hex_grid_view.set_selectable_hexes() overlay the Step verb's
		# movement_input_controller uses — so a Dodge-Step reads visually
		# identical to a normal Step instead of silently waiting for a click.
		# Cleared the instant a legal hex is picked so the highlight never
		# lingers into the attacker's continuing turn or the next actor.
		_hex_grid_view.set_selectable_hexes(legal_hexes)
		while true:
			var clicked = await _hex_grid_view.hex_clicked
			for hex in legal_hexes:
				if hex.equals(clicked):
					_hex_grid_view.set_selectable_hexes([])
					return hex


## _VerbBarRegistryAdapter — the presentation/verb_bar_view.gd VerbBarView
## registry contract (FEAT-004 / US-004/FR-001), realized here as a small,
## GENERIC, data-driven dispatch table exactly mirroring the shape/discipline
## of core/application/verb_registry.py's pytest-only VerbRegistry (ADR-004):
## register() is the ONLY way a verb enters `_descriptors`, and
## list_verbs()/is_available()/enter_selection()/execute() are plain dict
## lookups followed by a delegate Callable.call() — there is deliberately NO
## verb-name branching in ANY of those four methods, so a hypothetical fifth
## verb could be registered here without touching this class (the SAME
## extensibility guarantee the Python VerbRegistry proves at the pytest
## layer). The only place verb-specific wiring exists is where this
## composition root calls register() below (MainScene._ready()), via small
## Callables bound to this file's own _verb_bar_*_availability/
## _verb_bar_*_enter_selection/_verb_bar_*_execute helper methods — those
## helpers, in turn, introduce NO new domain/application logic of their own;
## each simply forwards to the SAME already-instantiated, already-tested
## presentation control (strike_action_control / movement_input_controller /
## end_turn_control) this composition root wires elsewhere (ADR-002/CR-001:
## no duplicate action/movement/turn-ending path).
class _VerbBarRegistryAdapter:
	var _availability_fns: Dictionary = {}
	var _enter_selection_fns: Dictionary = {}
	var _execute_fns: Dictionary = {}
	var _order: Array = []

	## register(verb_id, availability_fn, enter_selection_fn, execute_fn) —
	## the ONLY method that special-cases a verb_id; every dispatch method
	## below is a generic dict lookup over whatever has been register()ed.
	func register(verb_id: String, availability_fn: Callable, enter_selection_fn: Callable, execute_fn: Callable) -> void:
		if not _availability_fns.has(verb_id):
			_order.append(verb_id)
		_availability_fns[verb_id] = availability_fn
		_enter_selection_fns[verb_id] = enter_selection_fn
		_execute_fns[verb_id] = execute_fn

	func list_verbs() -> Array:
		var descriptors: Array = []
		for verb_id in _order:
			descriptors.append({"verb_id": verb_id})
		return descriptors

	func is_available(verb_id: String) -> bool:
		return bool(_availability_fns[verb_id].call())

	func enter_selection(verb_id: String):
		return _enter_selection_fns[verb_id].call()

	func execute(verb_id: String, selection = null):
		return _execute_fns[verb_id].call(selection)


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

## _player_attack_event_id_counter — FEAT-005 (US-005, Iteration J-R2 Part
## D): monotonically incremented once per resolved PLAYER Strike
## (_verb_bar_strike_execute() below), the source of the attack_event_id
## this call site's structured/rich log entries are keyed by. Uses a
## "R<round>-P<n>" shape -- a "P" (Player) infix distinct from
## core/application/round_session.gd's own "R<round>-A<n>" AI-path
## generator (_generate_attack_event_id()) -- so ids from these two
## independent call sites can never collide within the SAME event_log_view
## instance's structured storage.
var _player_attack_event_id_counter: int = 0

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
## all combatants at boot. This is the ONE hex grid renderer this
## composition root wires (FEAT-001 / US-001, iteration D UI consolidation).
@onready var hex_grid_view = $HexGridView

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

## event_log_view — the EventLogView (presentation/event_log_view.gd)
## instanced in MainScene.tscn (FEAT-010 / US-008). Append-only — starts
## empty and receives every round event as the interactive session
## progresses, so a person running the project (not headless) sees a
## chronologically ordered, human-readable combat log for the whole
## encounter.
@onready var event_log_view = $EventLogView

## movement_input_controller — the MovementInputController (presentation/
## movement_input_controller.gd) instantiated directly (FEAT-013 / US-013 --
## no companion .tscn, code-only instantiation). Reconfigured alongside
## the STRIKE verb closures every time TurnController's active_actor_changed
## signal fires, so the SAME live actor/occupancy data drives it. Handed
## `hex_grid_view` (FEAT-007) so a successful Step/Stride visibly repositions
## the mover's token there.
##
## FEAT-007 (this iteration's US-007/FR-010): Step/Stride are now driven
## SOLELY through `_verb_registry`'s STEP/STRIDE entries
## (_verb_bar_step_execute()/_verb_bar_stride_execute() below), which forward
## a Layer-2-selected destination hex straight to step_to()/stride_to() --
## there is no longer a standing hex_grid_view.hex_clicked subscription that
## auto-resolves a Step-or-Stride the instant ANY highlighted hex is clicked
## (the legacy behavior presentation/MoveActionControl.gd's passive "Move"
## indicator advertised). HexGridView.hex_clicked still exists as a signal
## (a future Layer 2 SelectionOverlay may subscribe to it) but this
## composition root no longer connects to it directly. A Step never goes
## through resolve_action_use_case (it has no action-economy/event side
## effects, core/rules/movement.gd, ADR-002) -- but it DOES move the SAME
## live combatant Dictionary Strike reach reads from, so
## _on_active_actor_changed() is re-invoked after every successful
## Step/Stride (see _after_successful_move() below) to re-gate STRIKE's
## in-reach target set from the new position. Also handed the active
## combatant's live ActionEconomy (FEAT-014) so a Stride can spend the one
## action it requires from the SAME shared budget the STRIKE verb closures
## already read from.
var movement_input_controller = MovementInputControllerClass.new()

## turn_controller — the TurnController (presentation/turn_controller.gd)
## instanced in MainScene.tscn (FEAT-110/111, US-010/US-011). Handed the
## live round_session by this composition root (FEAT-123).
@onready var turn_controller = $TurnController

## end_turn_control — the EndTurnControl (presentation/end_turn_control.gd)
## instanced in MainScene.tscn (FEAT-110, US-010).
@onready var end_turn_control = $EndTurnControl

## verb_bar_view — the VerbBarView (presentation/verb_bar_view.gd) instanced
## in MainScene.tscn (FEAT-004 / US-004/FR-001): the Layer 1 verb bar,
## rendered generically from `_verb_registry` below (one button per
## registered verb -- Strike/Step/Stride/End Turn -- no hardcoded per-verb
## UI). Configured once `_verb_registry` is built in _ready() (see
## _build_verb_registry()), and re-gated (refresh_availability()) every time
## _on_active_actor_changed()/_on_round_over() fires, so a stale-availability
## button is never left clickable after the game state that determined it
## has changed.
@onready var verb_bar_view = $VerbBarView

## _verb_registry — the _VerbBarRegistryAdapter instance this composition
## root builds in _ready() (see _build_verb_registry()) and hands to
## verb_bar_view.configure(). Exposed for verification.
var _verb_registry = null

## selection_overlay — the SelectionOverlay (presentation/selection_overlay.gd,
## FEAT-008 / US-008) instantiated directly (code-only, no companion .tscn —
## mirrors movement_input_controller's precedent). Configured in _ready()
## (see _build_verb_registry()'s caller below) with `_verb_registry` and
## `hex_grid_view`, and wired to $VerbBarView.verb_selection_entered so
## EVERY Layer 1 verb press's Layer 2 selection (Strike this feature; Step/
## Stride generically, with zero forked logic of this file's own — see
## selection_overlay.gd's file-level doc) highlights its candidates and
## resolves a click straight through `_verb_registry.execute()`. Exposed for
## verification.
var selection_overlay = SelectionOverlayClass.new()

## cancel_controller — the CancelController (presentation/cancel_controller.gd,
## FEAT-176 / US-012 / FR-007, ADR-005) instantiated directly (code-only, no
## companion .tscn, plain RefCounted — mirrors selection_overlay's/
## movement_input_controller's precedent EXACTLY, including never being
## add_child()ed, so it never grows MainScene's exact-child-set — see
## tests/infrastructure/test_presentation_stack_wiring.gd). This composition
## root's own _unhandled_input() (below) forwards every event to it, since a
## RefCounted has no engine input callback of its own. Configured with ONLY
## `selection_overlay` in _ready() — this composition root never hands it
## `_verb_registry` or any port/use case, so the "CancelController never
## invokes ActionResolverPort/MovementPort/TurnPort methods" guarantee holds
## at the wiring level too. Exposed for verification.
var cancel_controller = CancelControllerClass.new()

## reaction_prompt_ui — the ReactionPromptUI (scenes/ui/reaction_prompt_ui.gd,
## FEAT-207 / US-013 / FR-015) instanced in MainScene.tscn — the player-facing
## blocking reaction pop-up, the steel thread's on-screen entry point for
## reactions. Hidden (visible = false) until a live reaction trigger's
## legal_reactions are handed to it via open_prompt() (see
## presentation/player_reaction_chooser.gd's PlayerReactionChooser, which
## wraps this node below).
@onready var reaction_prompt_ui = $ReactionPromptUI

## player_reaction_chooser — the PlayerReactionChooser (presentation/
## player_reaction_chooser.gd, FEAT-207) this composition root constructs in
## _ready() around `reaction_prompt_ui`, implementing
## core/application/ports/reaction_chooser_port.gd's ReactionChooserPort
## contract. Injected into $TurnController via configure_reactions() so
## turn_controller.gd's resolve_reaction() can `await` it. Exposed for
## verification.
var player_reaction_chooser = null

## enemy_reaction_chooser — iteration K FEAT-004 (US-004, ADR-004): the
## AIReactionPolicy (infrastructure/ai_reaction_policy.gd) this composition
## root constructs in _ready() and hands to `resolve_action_use_case`'s
## resolve_reactive() as the enemy DEFENDER's ReactionChooserPort for the
## player-Strikes-enemy path (_verb_bar_strike_execute() below) — a
## deterministic, RNG-free, SYNCHRONOUS chooser: no pop-up, no `await`, no
## coroutine ever opens for the enemy's own reaction decision (this feature's
## "no pop-up UI opens during the enemy's reaction window" test_criterion).
## Distinct from `player_reaction_chooser` (which wraps the REAL, blocking
## `reaction_prompt_ui` pop-up for the player's own reactions on the
## enemy-Strikes-player path, core/application/round_session.gd) — the two
## are independent adapters behind the SAME ReactionChooserPort, never
## confused with one another. Exposed for verification.
var enemy_reaction_chooser = null

## hex_choice_resolver — the HexChoiceResolverPort (core/application/ports/
## hex_choice_resolver_port.gd, FEAT-001 / US-004, ADR-002/G2) this
## composition root wires in _ready() around `hex_grid_view`
## (_UIHexChoiceResolver above) — the seam a future Dodge-Step selection
## window (US-005/US-006/US-007) will use, mirroring player_reaction_chooser's
## identical "constructed here, exposed for verification/injection"
## precedent. A test may overwrite this field directly with a scripted
## double WITHOUT ever constructing its own HexChoiceResolverPort in
## isolation — every resolution still routes through resolve_hex_choice()
## below, this composition root's own real call path (see
## tests/application/test_hex_choice_resolver_seam.gd's "no test self-wiring"
## criterion).
var hex_choice_resolver = null

## reaction_window — the ReactionWindow (core/application/reaction_window.gd,
## FEAT-009/US-009) this composition root constructs in _ready(), wired to
## the SAME `event_sink` every other use case emits through (ADR-003 — no
## second/parallel event-sink adapter). Injected into $TurnController via
## configure_reactions(). Exposed for verification.
var reaction_window = null

## result_screen_view — the ResultScreenView (presentation/
## result_screen_view.gd) instanced in MainScene.tscn (FEAT-112, US-012).
## This is the ONE result screen this composition root wires (FEAT-001 /
## US-001, iteration D UI consolidation).
@onready var result_screen_view = $ResultScreenView

## _party / _enemies — the live combatant Dictionaries built at boot,
## mutated in place by every resolved Strike throughout the interactive
## session (Dictionaries are reference types in GDScript). Kept as fields so
## this composition root's own signal handlers (reacting to
## TurnController's active_actor_changed/round_over) can rebuild
## StrikeActionControl's live target list without re-deriving it from
## Infrastructure.
var _party: Array = []
var _enemies: Array = []

## _last_highlight_debug_log — FEAT-006 / US-006 (FR-001, ADR-004): the most
## recent debug log line emitted by _highlight_legal_moves() (observability
## requirement — see that method's doc). Exposed for GUT test verification
## since stdout itself is not readily interceptable from a headless test;
## mirrors this file's own ConsoleEventSinkAdapter.log Array's established
## "store for verification, also print" convention.
var _last_highlight_debug_log: String = ""

## centering_offset — FEAT-002 (US-002 / FR-012, ADR-003): the shared
## screen-space origin offset this composition root computes at boot via
## CoordinateTransform.compute_centering_offset() and hands to
## hex_grid_view.set_origin_offset() -- the SAME offset every other
## consumer of the FEAT-001 shared transform (token drawing, click mapping,
## highlight rendering) then reads back via hex_grid_view.get_origin_offset(),
## never a second/independent offset of its own. Exposed for GUT test
## verification and observability (mirrors this file's other
## boot-computed-value convention, e.g. `resolved_seed`).
var centering_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	encounter_repository = ResourceEncounterRepositoryClass.new()
	var hex_combatants: Array = encounter_repository.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	# ── FEAT-002 / US-002 / FR-012 (ADR-003): derive the ONE shared
	# viewport-centering offset from the grid's own rendered extent corners
	# (HexGridViewClass.GRID_RADIUS) unioned with every occupied hex loaded
	# above, then hand it to hex_grid_view.set_origin_offset() BEFORE
	# load_combatants() below so tokens are drawn centered on the very first
	# frame -- never a token positioned first at Vector2.ZERO and only later
	# shifted. This is the SAME CoordinateTransform.axial_to_pixel()/
	# pixel_to_axial() shared transform every other consumer (drawing, click
	# mapping, highlighting) already reads _origin_offset from (FEAT-001), so
	# centering can never drift out of sync with them. ─────────────────────
	centering_offset = _compute_boot_centering_offset(hex_combatants)
	if hex_grid_view != null:
		hex_grid_view.set_origin_offset(centering_offset)
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
		_refresh_off_guard_conditions()

	var initiative_view_models: Array = _build_initiative_view_models(hex_combatants, _party, _enemies, encounter)

	if initiative_view != null:
		initiative_view.load_combatants(initiative_view_models)

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

	if result_screen_view != null:
		# FEAT-006: no strike_action_control node exists anymore -- its
		# first (optional, default-null) argument is simply omitted; see
		# this file's FEAT-006 doc above and presentation/result_screen_view.gd.
		# FEAT-007 (this iteration): no move_action_control node exists
		# anymore either -- its fourth (optional, default-null) argument is
		# likewise simply omitted; see this file's FEAT-007 doc above.
		# FEAT-177 (US-013 / FR-013): `verb_bar_view`/`selection_overlay` are
		# additionally injected (fifth/sixth arguments) so lock_all_controls()
		# uniformly locks the Layer 1 verb bar and any open Layer 2 selection
		# the moment EncounterResultEvent fires -- see this file's #11 doc
		# above and presentation/result_screen_view.gd.
		result_screen_view.configure(null, end_turn_control, movement_input_controller, null, verb_bar_view, selection_overlay)

	if turn_controller != null:
		turn_controller.active_actor_changed.connect(_on_active_actor_changed)
		turn_controller.round_over.connect(_on_round_over)

	# ── FEAT-207 (US-013 / FR-015): construct the ReactionWindow (wired to
	# the SAME `event_sink` every other use case emits through, ADR-003) and
	# the PlayerReactionChooser wrapping `reaction_prompt_ui`, then inject
	# both into $TurnController via configure_reactions() so its
	# resolve_reaction() (presentation/turn_controller.gd) can drive the
	# player-facing blocking reaction pop-up end-to-end. ──────────────────
	reaction_window = ReactionWindowClass.new(event_sink)
	if reaction_prompt_ui != null:
		player_reaction_chooser = PlayerReactionChooserClass.new(reaction_prompt_ui)
	if turn_controller != null:
		turn_controller.configure_reactions(reaction_window, player_reaction_chooser)

	# ── iteration K FEAT-004 (US-004, ADR-004): construct the enemy AI's own
	# deterministic, synchronous ReactionChooserPort (AIReactionPolicy) — the
	# composition-root seam _verb_bar_strike_execute() below hands to
	# resolve_action_use_case.resolve_reactive() so a player Strike's target
	# (the enemy) genuinely reacts (Dodge/Parry/Block) with NO pop-up. ───────
	enemy_reaction_chooser = AIReactionPolicyClass.new()

	# ── FEAT-001 (US-004, ADR-002/G2): construct the production default
	# HexChoiceResolverPort adapter around `hex_grid_view` — the ONE place
	# both sides of this seam are ever named concretely. Establishes the
	# seam a future Dodge-Step selection window (US-005/US-006/US-007) will
	# use; see hex_choice_resolver's own field doc above and
	# _UIHexChoiceResolver's doc. ───────────────────────────────────────────
	if hex_grid_view != null:
		hex_choice_resolver = _UIHexChoiceResolver.new(hex_grid_view)

	if end_turn_control != null:
		end_turn_control.turn_ended.connect(_on_end_turn_control_turn_ended)
		# BUGFIX (post-iteration-E): End Turn is now a first-class verb in the
		# Layer 1 verb bar (registry END_TURN entry, whose execute() delegates to
		# end_turn_control.press()). EndTurnControl is retained ONLY as that
		# headless logic delegate (press()/turn_ended + TurnController-managed
		# enabled state), so its own on-screen Button is hidden to avoid a second,
		# duplicate "End Turn" control alongside the verb-bar button.
		end_turn_control.visible = false

	# ── FEAT-006 (US-004/FR-004, ADR-012): obtains this round's RoundSession
	# via RunRoundUseCase.begin_round(ROUND_NUMBER, ...), wires its AI-Stride
	# token-reposition hook (FEAT-008, unchanged), and hands it to
	# TurnController.set_session() -- a harmless no-op on Strike/Stride/Step
	# availability this early, since $VerbBarView is not yet configure()d
	# (that happens immediately below); it becomes effective from the very
	# next call site (_on_end_turn_control_turn_ended(), or a later
	# _on_round_over() round continuation) onward. See rewire_session()'s own
	# doc below for why this is the ONE place that wiring is expressed. ─────
	rewire_session()

	# ── FEAT-004 / US-004/FR-001: build the Layer 1 verb registry and hand it
	# to $VerbBarView (see _build_verb_registry()'s doc). Built AFTER
	# set_session() above so the initial is_available() gating already
	# reflects whichever actor/targets/hexes that first active_actor_changed
	# settled on. ────────────────────────────────────────────────────────────
	_verb_registry = _build_verb_registry()
	if verb_bar_view != null:
		verb_bar_view.configure(_verb_registry)

	# ── FEAT-008 / US-008 (FR-003, ADR-002): wire the generic Layer 2
	# SelectionOverlay (presentation/selection_overlay.gd) over the SAME
	# `_verb_registry` and `hex_grid_view` this composition root already
	# built/wires above -- no new port, no forked resolution logic. This is
	# the SAME hex_grid_view.hex_clicked signal FEAT-007's doc (immediately
	# below, historically) noted "a future Layer 2 SelectionOverlay may
	# subscribe to it" -- this is that subscriber, connected generically to
	# EVERY non-END_TURN verb's Layer 2 entry (VerbBarView.verb_selection_entered)
	# rather than special-cased to STRIKE, mirroring VerbBarView's/
	# verb_registry.py's own verb-agnostic dispatch discipline. ─────────────
	selection_overlay.configure(_verb_registry, hex_grid_view)
	if verb_bar_view != null:
		verb_bar_view.verb_selection_entered.connect(_on_verb_bar_selection_entered)
	selection_overlay.selection_resolved.connect(_on_selection_overlay_resolved)

	# ── FEAT-176 / US-012 (FR-007, ADR-005): wire the generic Layer 2 cancel/
	# back affordance (Esc/right-click/Cancel button) over the SAME
	# `selection_overlay` above -- instantiated directly, never add_child()ed
	# (it is a plain RefCounted adapter, mirroring selection_overlay/
	# movement_input_controller -- see tests/infrastructure/
	# test_presentation_stack_wiring.gd's exact-child-set invariant, which
	# this composition root must not grow). This node's OWN
	# _unhandled_input() (below) forwards Esc-key/right-click events to it
	# instead. Configured with ONLY `selection_overlay` -- never
	# `_verb_registry` -- so no ActionResolverPort/MovementPort/TurnPort call
	# is reachable from it (see cancel_controller.gd's file-level doc). ──────
	cancel_controller.configure(selection_overlay)

	print(
		"INFO: Hykaen MainScene booted into the prologue encounter (interactive) -- "
		+ "current_actor=" + str(round_session.current_actor().get("name", ""))
		+ " round_over=" + str(round_session.is_round_over())
	)

	# ── FEAT-002 / US-002 (observability, per design notes): surface the
	# resolved centering_offset once at boot so any future transform-drift
	# regression (a token/grid rendering at the wrong screen position) is
	# immediately visible in headless-boot logs, mirroring the ADR-003
	# rationale already established for `resolved_seed`. ───────────────────
	print("DEBUG: viewport_centering centering_offset=" + str(centering_offset))


## resolve_hex_choice(legal_hexes) -> HexCoord | null — FEAT-001 (US-004,
## ADR-002/G2): the ONE call path through which this composition root's
## injected `hex_choice_resolver` is ever invoked — the seam-level test
## (tests/application/test_hex_choice_resolver_seam.gd) proves a scripted
## hex_choice_resolver flows through THIS method, never a resolver a test
## constructed and invoked directly in isolation (self-wiring). Delegates
## verbatim to hex_choice_resolver.resolve(legal_hexes) — see that port's
## own contract doc (core/application/ports/hex_choice_resolver_port.gd)
## for the "null only when legal_hexes is empty" invariant this composition
## root never second-guesses or overrides. Returns null defensively if
## `hex_choice_resolver` itself is somehow unwired (hex_grid_view missing) —
## a structural impossibility for the real res://MainScene.tscn, never
## exercised in normal play.
func resolve_hex_choice(legal_hexes: Array):
	if hex_choice_resolver == null:
		return null
	return await hex_choice_resolver.resolve(legal_hexes)


## rewire_session() -> void — FEAT-006 (US-004/FR-004, ADR-012): the SINGLE
## reusable composition-root rewiring method this file invokes both at
## startup (_ready() above, for ROUND_NUMBER's initial value of 1) AND on
## automatic round continuation (_on_round_over() below, once a round
## concludes WITHOUT a decided encounter outcome) — there is no second,
## duplicated copy of this wiring anywhere else in this file (FEAT-006's
## "no duplicated wiring code" test criterion).
##
## Obtains a fresh RoundSession for the CURRENT `ROUND_NUMBER` via
## RunRoundUseCase.begin_round(_party, _enemies) (which itself grants every
## combatant's ActionEconomy a fresh start-of-round budget, CR-001 AC-2),
## wires its AI-Stride token-reposition hook to the SAME
## hex_grid_view.move_token() the player Step/Stride path already calls
## (FEAT-008 / ADR-006, unchanged), and hands the new session to
## TurnController.set_session() — which immediately auto-drives any leading
## Enemy turn(s) for the new round (US-011) and refreshes end_turn_control/
## `verb_bar_view` for whoever the new round's first actor is.
##
## Deliberately does NOT (re)connect turn_controller.active_actor_changed/
## round_over or end_turn_control.turn_ended — those signal subscriptions are
## one-time, established ONCE in _ready() above; reconnecting them here on
## every round continuation would register a duplicate handler for the
## lifetime of the SAME MainScene node/signal (a leak this method must never
## introduce). `_verb_registry`/`selection_overlay` likewise need no rebuild
## on continuation — their closures read `round_session`/`_party`/`_enemies`
## fresh off `self` on every call (see e.g. _verb_bar_strike_availability()'s
## doc), never a snapshot captured at registry-build time, so simply
## reassigning `round_session` below is sufficient for every one of them to
## observe the new round immediately.
## FEAT-003 (US-002 / FR-002, ADR-003): now a coroutine — TurnController.
## set_session() below is itself a coroutine as of this feature (it awaits
## TurnController._drive(), which awaits RoundSession.advance_ai_turn()).
## `await`ing it here preserves this method's pre-existing contract that
## `outcome`/every UI control it wires is fully settled for the new round by
## the time rewire_session() returns.
## FEAT-006 (US-005/FR-005, ADR-002): this composition root now DOES inject
## a reaction resolver on `round_session` (set_reaction_resolver_fn(), below
## — see its own doc) before awaiting TurnController.set_session(), so an
## enemy Strike auto-driven during that very call can already await a real,
## player-facing reaction window. For headless/sim callers that never boot
## this composition root at all (RunRoundUseCase/RoundSession used directly,
## e.g. the balance sim), nothing here ever runs, so that path's await still
## never actually suspends and remains byte-for-byte unchanged (NFR-004).
func rewire_session() -> void:
	round_session = run_round_use_case.begin_round(ROUND_NUMBER, _party, _enemies)

	# ── FEAT-008 (US-008 / FR-012, ADR-006): wire RoundSession's execution of
	# an AI-issued Stride to the SAME hex_grid_view.move_token() reposition
	# function the player Step/Stride path already calls (via
	# movement_input_controller.gd's _resync_token_renderers()) -- same call
	# site, different actor_id/destination, no parallel reposition
	# implementation. RoundSession itself never imports/depends on
	# HexGridView (ADR-001/ADR-002); it only invokes whichever Callable this
	# composition root injects here. ────────────────────────────────────────
	if round_session != null and hex_grid_view != null:
		round_session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))

	# ── FEAT-006 (US-005/FR-005, ADR-002): wire RoundSession's enemy-strikes-
	# player reaction window to the SAME TurnController.resolve_reaction()
	# every player-facing reaction resolves through (turn_controller.gd,
	# FEAT-207/configure_reactions(), unchanged by this feature) -- the
	# IDENTICAL Dependency-Inversion pattern immediately above for
	# set_token_reposition_fn(): RoundSession itself never imports/references
	# TurnController by type (ADR-002; see
	# tests/gut/test_round_session_reaction_resolver_injection.gd's static
	# source-inspection criterion), it only invokes whichever Callable this
	# composition root injects here. Re-applied on every rewire_session()
	# call -- both _ready()'s initial call and every _on_round_over() round
	# continuation -- so a freshly begin_round()'d RoundSession is never left
	# without a resolver for even one frame, mirroring the token-reposition
	# re-wiring immediately above. ──────────────────────────────────────────
	if round_session != null and turn_controller != null:
		round_session.set_reaction_resolver_fn(Callable(turn_controller, "resolve_reaction"))

		# ── FEAT-005 (US-005 / FR-005, Iteration J Part A): wire RoundSession's
		# TWO newer, correctly-timed reaction windows -- "PreHitAvoidance"
		# (Dodge/Steel, asked BEFORE the attack roll) and "OnHitMitigation"
		# (Parry/Block, asked AFTER the hit result is known) -- to the SAME
		# real TurnController.resolve_reaction() adapter immediately above,
		# rather than leaving them permanently unset (their pre-FEAT-005 state,
		# under which RoundSession's own default-safety fallback silently
		# resolved both to Pass for EVERY real playthrough, so only the legacy
		# combined "WeaponAttack" window above was ever actually reachable in
		# real play). resolve_reaction() is trigger-type-agnostic (it merely
		# forwards whatever trigger Dictionary it is handed to
		# reaction_window.gd's open()/resume(), which already branches on
		# trigger["trigger_type"] -- see reaction_window.gd's own doc), so the
		# SAME real ReactionResolverPort adapter (and, transitively, the SAME
		# real EventLogPort-equivalent event_sink every ReactionWindowOpenedEvent/
		# ReactionResolvedEvent already flows through, ADR-003) correctly
		# serves all three seams without a second/parallel adapter. Re-applied
		# on every rewire_session() call, mirroring the reaction_resolver_fn
		# wiring immediately above -- a freshly begin_round()'d RoundSession is
		# never left without either resolver for even one frame.
		round_session.set_prehit_avoidance_resolver_fn(Callable(turn_controller, "resolve_reaction"))
		round_session.set_onhit_mitigation_resolver_fn(Callable(turn_controller, "resolve_reaction"))

		# FEAT-213 (Iteration J V&V fix): wire the structured combat-log recorder
		# into the REAL composition root, mirroring the reaction-resolver seams
		# above. round_session's inline recording (inside advance_ai_turn, on
		# every resolved Strike) forwards the AttackEvent to this Callable;
		# without this binding the live log only ever rendered the old plain
		# on_attack_event() string ("Hit for D damage."), never Part D-1's rich
		# roll/defense-outcome format — the composition-root gap V&V flagged.
		# Re-applied on every rewire_session() call like the resolvers above.
		#
		# FEAT-006 (US-006 / FR-006, Iteration J-R2 Part D): additionally wires
		# the entry-count query + render_attack_entry()/overwrite_entry_as_rich()
		# seams round_session.advance_ai_turn() uses to render the SAME rich,
		# single-row format for the enemy-strikes-player path that MainScene.gd's
		# `_verb_bar_strike_execute()` (FEAT-005) already renders directly for
		# the player-strikes-enemy path -- exactly one rich row per resolved
		# enemy Strike, never a basic+rich duplicate pair. Re-applied on every
		# rewire_session() call like every other seam above.
		if event_log_view != null:
			round_session.set_event_log_record_attack_fn(Callable(event_log_view, "record_attack"))
			round_session.set_event_log_entry_count_fn(Callable(event_log_view, "get_entry_count"))
			round_session.set_event_log_render_attack_entry_fn(Callable(event_log_view, "render_attack_entry"))
			round_session.set_event_log_overwrite_entry_fn(Callable(event_log_view, "overwrite_entry_as_rich"))
			# FEAT-008 (US-008 / FR-007): wire the structured reaction recorder
			# into the REAL composition root -- mirrors the record_attack seam
			# immediately above. Without this binding, RenderCombatLogUseCase
			# (invoked from round_session.gd's advance_ai_turn()) still derives
			# the correct ReactionResolvedEvent but never records it anywhere
			# observable, leaving the enemy-strikes-player path's Defense
			# segment stuck on its "none" default.
			round_session.set_event_log_record_reaction_fn(Callable(event_log_view, "record_reaction"))

		# ── FEAT-002 (US-002, Dodge-Step steel thread): wire RoundSession's
		# Dodge-Step seams to the REAL composition-root adapters -- the SAME
		# Dependency-Inversion pattern every other seam in this method already
		# follows. `hex_choice_resolver` (set up in _ready(), see that field's
		# own doc) is reused verbatim via resolve_hex_choice() -- the EXACT
		# SAME FEAT-001 seam tests/gut/test_hex_choice_seam_dodge_step.gd
		# already proves flows through this composition root (ADR-001/ADR-002
		# "no duplicate seam"). `_query_selectable_step_hexes()` reuses the
		# unchanged movement_input_controller.get_selectable_step_hexes_for()
		# query (no new adjacency rule). Re-applied on every rewire_session()
		# call like every other seam above, so a freshly begin_round()'d
		# RoundSession is never left without either for even one frame.
		round_session.set_hex_choice_resolver_fn(Callable(self, "resolve_hex_choice"))
		round_session.set_step_hex_query_fn(Callable(self, "_query_selectable_step_hexes"))

	if turn_controller != null:
		# FEAT-006: strike_action_control no longer exists; set_session()'s
		# third argument is optional (default null) and simply omitted.
		# FEAT-003: set_session() is now a coroutine — awaited (see this
		# method's own FEAT-003 doc above).
		await turn_controller.set_session(round_session, end_turn_control, null, verb_bar_view)

	outcome = round_session.outcome()


## _unhandled_input(event) -> void — FEAT-176 (US-012 / FR-007, ADR-005):
## forwards EVERY unhandled input event straight to
## `cancel_controller`.handle_input() -- the ONE place an Esc-key-pressed or
## right-click-pressed event is translated into a Layer 2 cancel, mirroring
## presentation/hex_grid_view.gd's own _unhandled_input() (left-click ->
## hex_clicked) convention. `cancel_controller` is a plain RefCounted adapter
## (never add_child()ed -- see this file's `cancel_controller` field doc), so
## this composition root -- already a live SceneTree Node -- is the one place
## that must own this translation. Marks the event handled only when a real
## cancel occurred, so an Esc/right-click with no active Layer 2 selection is
## left for any other listener (e.g. a future menu) to handle.
func _unhandled_input(event: InputEvent) -> void:
	if cancel_controller.handle_input(event):
		get_viewport().set_input_as_handled()


## _compute_boot_centering_offset(hex_combatants) -> Vector2 — FEAT-002
## (US-002 / FR-012, ADR-003): builds the set of HexCoords whose combined
## pixel extents this boot's centering offset must place within the
## viewport -- the union of:
##   1. the six corner HexCoords of the fixed hex-shaped background grid
##      HexGridView renders (radius HexGridViewClass.GRID_RADIUS around the
##      origin), and
##   2. every occupied combatant hex_coord loaded from the prologue
##      encounter (`hex_combatants`, from ResourceEncounterRepository) --
## then delegates to presentation/infrastructure/coordinate_transform.gd
## CoordinateTransform.compute_centering_offset() (FEAT-001's shared
## transform module) for the actual pixel-space centering math, rather than
## computing a second/independent offset here (ADR-003). The viewport size
## is read from ProjectSettings' configured display/window size (falling
## back to this project's actual configured default, DEFAULT_VIEWPORT_WIDTH/
## HEIGHT, when unset) -- the game's real rendered window size in a normal
## (non-headless) launch -- rather than the live Viewport's reported size,
## which a headless test harness may report as an arbitrary small stub size
## unrelated to how the project is actually meant to render (verified
## against ProjectSettings directly by tests/gut/test_viewport_centering.gd).
func _compute_boot_centering_offset(hex_combatants: Array) -> Vector2:
	var extent_hexes: Array = _grid_extent_corner_hexes()
	for combatant in hex_combatants:
		if combatant.hex_coord != null:
			extent_hexes.append(combatant.hex_coord)

	var viewport_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", DEFAULT_VIEWPORT_WIDTH),
		ProjectSettings.get_setting("display/window/size/viewport_height", DEFAULT_VIEWPORT_HEIGHT)
	)

	return CoordinateTransformClass.compute_centering_offset(extent_hexes, viewport_size, HexGridViewClass.HEX_SIZE)


## _grid_extent_corner_hexes() -> Array — the six HexCoords marking the
## corners of the hex-shaped background grid HexGridView._draw() renders
## (radius HexGridViewClass.GRID_RADIUS around the origin) -- the same
## fixed rendered extent _compute_boot_centering_offset() above unions with
## the occupied combatant hexes, so centering accounts for the visible
## background grid, not merely the (much smaller) occupied-hex cluster.
func _grid_extent_corner_hexes() -> Array:
	var radius: int = HexGridViewClass.GRID_RADIUS
	return [
		HexCoordClass.new(radius, 0),
		HexCoordClass.new(radius, -radius),
		HexCoordClass.new(0, -radius),
		HexCoordClass.new(-radius, 0),
		HexCoordClass.new(-radius, radius),
		HexCoordClass.new(0, radius),
	]


## _presentation_event_subscribers() -> Array — every instantiated
## Presentation projection that subscribes to the EventSinkPort broadcast
## (ADR-003): StatusPanelView/InitiativeView/EventLogView/ResultScreenView.
## HexGridView (the positional-only hex renderer) is NOT an EventSinkPort
## subscriber (a Strike never moves a combatant in this steel thread) — see
## presentation/turn_controller.gd's file-level doc for the precedent this
## mirrors. This is the single, non-duplicated set of subscribers this
## composition root wires (FEAT-001 / US-001, iteration D UI consolidation).
func _presentation_event_subscribers() -> Array:
	var subscribers: Array = []
	for view in [
		status_panel_view, initiative_view, event_log_view, result_screen_view,
	]:
		if view != null:
			subscribers.append(view)
	return subscribers


## _build_verb_registry() -> _VerbBarRegistryAdapter — FEAT-004 (US-004/
## FR-001): composes the four in-scope verb entries (Strike/Step/Stride/End
## Turn — the SAME four US-003 scoped in core/application/verb_registry.py's
## build_default_registry(), mirrored here for the Godot runtime, which
## cannot reach that pytest-only Python module directly, ADR-001) over the
## ALREADY-INSTANTIATED, already-tested presentation controls this
## composition root wires elsewhere. This is the ONE place verb-specific
## wiring exists (mirroring build_default_registry()'s own file-level doc);
## _VerbBarRegistryAdapter itself stays completely verb-agnostic.
##
## No new domain/application logic is introduced here (ADR-002/CR-001): each
## availability/enter_selection/execute closure below is a thin forward to
## _strike_reachable_target_ids()/_find_strike_reachable_target() +
## resolve_action_use_case.resolve() (FEAT-006 -- see this file's FEAT-006
## doc: the removed strike_action_control.gd's reach-filter UX mirror lives
## here now, since Strike has no dedicated presentation control of its own
## anymore), movement_input_controller.get_selectable_step_hexes()/step_to()/
## get_selectable_stride_hexes()/stride_to(), or end_turn_control.press() --
## the SAME reach/movement/turn-ending paths those controls already expose
## and this file already relies on elsewhere.
func _build_verb_registry() -> _VerbBarRegistryAdapter:
	var registry := _VerbBarRegistryAdapter.new()

	registry.register(
		"STRIKE",
		Callable(self, "_verb_bar_strike_availability"),
		Callable(self, "_verb_bar_strike_enter_selection"),
		Callable(self, "_verb_bar_strike_execute"),
	)
	registry.register(
		"STEP",
		Callable(self, "_verb_bar_step_availability"),
		Callable(self, "_verb_bar_step_enter_selection"),
		Callable(self, "_verb_bar_step_execute"),
	)
	registry.register(
		"STRIDE",
		Callable(self, "_verb_bar_stride_availability"),
		Callable(self, "_verb_bar_stride_enter_selection"),
		Callable(self, "_verb_bar_stride_execute"),
	)
	registry.register(
		"END_TURN",
		Callable(self, "_verb_bar_end_turn_availability"),
		Callable(self, "_verb_bar_end_turn_enter_selection"),
		Callable(self, "_verb_bar_end_turn_execute"),
	)

	return registry


## _verb_bar_current_action_economy() -> ActionEconomy or null — the SAME
## live ActionEconomy round_session.current_action_economy() already exposes
## elsewhere in this file, read here only for its get_remaining() count (US-
## 004's "an action remains" gate for Strike/Stride availability, mirroring
## core/application/verb_registry.py's build_default_registry() strike_
## availability()/stride_availability() closures exactly).
func _verb_bar_current_action_economy():
	if round_session == null:
		return null
	return round_session.current_action_economy()


## _verb_bar_strike_availability() -> bool — FEAT-009 (US-009 / FR-004):
## gates on the active actor's live ActionEconomy.can_take_action()
## (core/rules/action_economy.gd, read-only, ADR-003) rather than the
## coarser "an action point remains" (get_remaining() > 0) check this used to
## perform. The two are NOT equivalent: can_take_action() additionally
## reports false the instant this turn's ONE action has been spent, even
## though the shared 7-action round budget may still have several points
## left (e.g. immediately after a Strike, remaining could still be 6) — this
## is the "one action per turn" gate the steel thread's exit criterion (the
## verb bar visibly greying Strike/Stride until the actor's NEXT turn) is
## built on, mirroring can_take_action()'s own file-level doc ("the SINGLE
## SOURCE OF TRUTH ... presentation ... is intended to read from"). This
## function only READS can_take_action(); it never mutates the domain gate
## itself.
func _verb_bar_strike_availability() -> bool:
	var action_economy = _verb_bar_current_action_economy()
	var can_act: bool = action_economy.can_take_action() if action_economy != null else false
	return can_act and _strike_reachable_target_ids().size() > 0


func _verb_bar_strike_enter_selection() -> Dictionary:
	return {"verb_id": "STRIKE", "candidate_targets": _strike_reachable_target_ids(), "candidate_hexes": []}


## _verb_bar_strike_execute(selection) -> Dictionary — FEAT-006: `selection`
## is the chosen target's id (String, the SAME "combatant_id" falling back to
## "name" convention _strike_target_id() below uses). Rejects HERE, before
## ever reaching resolve_action_use_case, when selection does not name a
## currently in-reach target -- including a stale/spoofed id -- exactly as
## the removed strike_action_control.gd's select_target() used to (no
## action-budget spend, no event emission, no use-case call at all).
##
## FEAT-005 (US-004 / FR-004, ADR-005 — CR-001 accepted debt; docs/
## iterations/iteration-I-reactions-live-wiring-and-offensive-reactions.org
## Part A-3): this is the PLAYER-strikes-ENEMY call site (historically
## documented as "MainScene.gd:1008").
##
## Iteration K FEAT-004 (US-004, ADR-004) — Part B: the enemy target now
## GENUINELY reacts on this path. `enemy_reaction_chooser` (AIReactionPolicy,
## constructed in _ready()) and the target's own live ActionEconomy
## (`_action_economy_for()` below) are handed to
## resolve_action_use_case.resolve_reactive() (core/application/
## resolve_action_use_case.gd), which opens the target's PreHitAvoidance
## window BEFORE the to-hit roll and OnHitMitigation window AFTER a hit,
## synchronously — no `await`, no coroutine, so NO pop-up/UI ever opens for
## the enemy's own reaction (this feature's "no pop-up UI opens" test
## criterion; contrast with core/application/round_session.gd's
## enemy-Strikes-PLAYER path, where the PLAYER reacts via the REAL,
## awaited `reaction_prompt_ui` pop-up). This supersedes the earlier "Part A
## pass-through" (the enemy always Passing, pinned by tests/gut/
## test_player_strikes_enemy_pass_through.gd) — that suite has been updated
## for Part B by this same feature.
func _verb_bar_strike_execute(selection) -> Dictionary:
	if round_session == null or resolve_action_use_case == null:
		return {"ok": false}

	var target: Dictionary = _find_strike_reachable_target(str(selection))
	if target.is_empty():
		return {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}

	var actor: Dictionary = round_session.current_actor()
	var action_economy = round_session.current_action_economy()

	# ── iteration K FEAT-004 (US-004, ADR-004): the enemy target's OWN live
	# ActionEconomy — required so a chosen reaction genuinely spends a budget
	# point (visible on StatusPanelView below) and so the RESERVE gate reads
	# real data. May resolve to null (a target this session has no bookkeeping
	# for, e.g. a test double) — resolve_reactive()/resolution.gd both
	# degrade safely to "reaction untracked" in that case. ──────────────────
	var target_action_economy = _action_economy_for(target)
	var target_budget_before: int = target_action_economy.get_remaining() if target_action_economy != null else -1

	# FEAT-005 (US-005, Iteration J-R2 Part D): capture the append-order index
	# the plain-format row event_log_view's on_attack_event() is ABOUT to
	# append at -- inside resolve_action_use_case.resolve_reactive()'s
	# synchronous EventSinkPort emit, immediately below -- BEFORE resolving,
	# so that index can be overwritten in place with the rich rendering once
	# resolve_reactive() returns with the resolved roll/damage fields.
	# Capturing the index up front (rather than suppressing the append and
	# appending a fresh row afterward) keeps the row's ORIGINAL chronological
	# position intact even when this SAME call also synchronously emits a
	# CombatantDefeatedEvent immediately after the AttackEvent (a killing
	# blow) -- the attack's own row must stay chronologically BEFORE that
	# consequence, never appended after it.
	var pending_entry_index: int = event_log_view.get_entry_count() if event_log_view != null else -1

	var result: Dictionary = resolve_action_use_case.resolve_reactive(
		actor, action_economy, target, ACTION_NAME_STRIKE, ROUND_NUMBER, 0,
		target_action_economy, enemy_reaction_chooser
	)

	# ── iteration K FEAT-004: reflect the enemy's own reaction spend (if any)
	# on the REAL StatusPanelView -- "the Skeleton's action budget visibly
	# drops by the reaction spend amount when it reacts" test criterion --
	# reusing the SAME on_verb_action_budget_changed() seam
	# presentation/status_panel_view.gd already exposes for a Stride's budget
	# spend (FEAT-178), never a new/second projection path. A no-op when
	# nothing was spent (remaining unchanged) or when the target has no
	# tracked ActionEconomy/status row at all. ──────────────────────────────
	if target_action_economy != null and status_panel_view != null:
		var target_budget_after: int = target_action_economy.get_remaining()
		if target_budget_after != target_budget_before:
			var target_id: String = target.get("combatant_id", target.get("name", ""))
			status_panel_view.on_verb_action_budget_changed(
				target_id, target_budget_after, target_action_economy.is_spent()
			)

	# FEAT-005: wire record_attack()/render_attack_entry() into this LIVE
	# player-attack call site. Builds a core/log/attack_event.gd AttackEvent
	# from `result["event"]` -- the SAME RoundEvents.AttackEvent instance
	# resolve_action_use_case.gd already emitted via EventSinkPort above,
	# never a second, re-derived roll/damage computation (mirrors
	# core/application/round_session.gd's own _record_structured_attack()
	# convention for the enemy-strikes-player path). record_attack() stores
	# it into the REAL, live event_log_view; render_attack_entry() formats
	# the roll/raw/final-damage rich text, which overwrites the plain-format
	# row captured above in place -- so exactly one, rich-format row is
	# visible for this Strike (steel-thread exit condition), never a
	# basic+rich duplicate pair.
	if event_log_view != null and pending_entry_index != -1 and result.get("resolved", false):
		var resolved_attack_event = result.get("event", null)
		if resolved_attack_event != null:
			_player_attack_event_id_counter += 1
			var attack_event_id: String = "R%d-P%d" % [ROUND_NUMBER, _player_attack_event_id_counter]

			var weapon: Dictionary = actor.get("weapon", {})
			var structured_attack_event = AttackEventClass.new(
				attack_event_id,
				ROUND_NUMBER,
				actor.get("combatant_id", actor.get("name", "")),
				target.get("combatant_id", target.get("name", "")),
				weapon.get("weapon_id", weapon.get("name", "")),
				resolved_attack_event.roll,
				resolved_attack_event.hit,
				resolved_attack_event.crit,
				resolved_attack_event.damage_final,
				resolved_attack_event.damage_final,
				result.get("on_hit_suppressed", false),
				false
			)

			event_log_view.record_attack(structured_attack_event)

			# FEAT-008 (US-008 / FR-007): pair this Strike's reaction outcome
			# to the JUST-recorded structured AttackEvent via
			# RenderCombatLogUseCase.record_reaction_outcome() -- mirrors
			# core/application/round_session.gd's identical wiring for the
			# enemy-strikes-player path.
			#
			# Iteration K FEAT-004 (US-004, ADR-004) — Part B: `choice` now
			# reflects the enemy's REAL reaction outcome
			# (resolve_action_use_case.gd's resolve_reactive() additive
			# "reaction_choice"/"on_hit_suppressed" keys — see that method's
			# own doc) instead of always "none". `window_id` is selected to
			# match which window the choice actually belongs to (Dodge/Steel
			# are PreHitAvoidance; Parry/Block are OnHitMitigation) so the
			# rich log's Defense segment attributes the outcome to the
			# correct window, mirroring core/application/round_session.gd's
			# own per-window recording.
			var enemy_reaction_choice: String = result.get("reaction_choice", "none")
			var enemy_reaction_window: String = (
				RenderCombatLogUseCaseClass.WINDOW_ON_HIT_MITIGATION
				if (enemy_reaction_choice == "parry" or enemy_reaction_choice == "block")
				else RenderCombatLogUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE
			)
			var render_combat_log_use_case := RenderCombatLogUseCaseClass.new()
			render_combat_log_use_case.record_reaction_outcome(
				attack_event_id, enemy_reaction_window, enemy_reaction_choice,
				"auto", result.get("on_hit_suppressed", false), 0,
				Callable(event_log_view, "record_reaction")
			)

			var rich_text: String = event_log_view.render_attack_entry(attack_event_id)
			event_log_view.overwrite_entry_as_rich(pending_entry_index, rich_text, attack_event_id)

	return result


## _strike_reachable_targets() -> Array — FEAT-006 (US-006): the in-reach
## target filter the now-removed presentation/strike_action_control.gd used
## to compute (a UX mirror of resolve_action_use_case.gd's OWN reach
## precondition, never a re-derived domain rule, ADR-001), relocated here
## since Strike no longer has a dedicated presentation control. Computed
## fresh from the LIVE round_session.current_actor()/`_enemies` on every
## call -- never a cached snapshot from a prior configure()-style call -- so
## this can never go stale between turns/moves.
##
## Mirrors resolve_action_use_case.gd's _is_ranged_weapon()/_is_in_range()
## branch exactly: an actor whose "weapon" Dictionary carries "range_hexes"
## reaches by HexMath.hex_distance() <= range_hexes; every other (melee)
## actor reaches by HexMath.hex_neighbors() membership.
func _strike_reachable_targets() -> Array:
	if round_session == null:
		return []

	var actor: Dictionary = round_session.current_actor()
	var actor_hex = actor.get("hex_coord", null)
	if actor_hex == null:
		return []

	var candidates: Array = _living_combatants(_enemies)
	var in_reach: Array = []

	if _strike_actor_is_ranged(actor):
		var range_hexes: int = actor.get("weapon", {}).get("range_hexes", 1)
		for target in candidates:
			var target_hex = target.get("hex_coord", null)
			if target_hex != null and HexMathClass.hex_distance(actor_hex, target_hex) <= range_hexes:
				in_reach.append(target)
		return in_reach

	var neighbors: Array = HexMathClass.hex_neighbors(actor_hex)
	for target in candidates:
		var target_hex = target.get("hex_coord", null)
		if target_hex == null:
			continue
		for neighbor in neighbors:
			if neighbor.equals(target_hex):
				in_reach.append(target)
				break
	return in_reach


## _strike_actor_is_ranged(actor) -> bool -- mirrors the removed
## strike_action_control.gd's/resolve_action_use_case.gd's identically-
## behaved _is_ranged_weapon() helper exactly.
func _strike_actor_is_ranged(actor: Dictionary) -> bool:
	return actor.get("weapon", {}).has("range_hexes")


## _strike_target_id(target) -> String -- the SAME "combatant_id" falling
## back to "name" identity convention used throughout this file/
## resolve_action_use_case.gd.
func _strike_target_id(target: Dictionary) -> String:
	return target.get("combatant_id", target.get("name", ""))


## _strike_reachable_target_ids() -> Array[String] -- the target_id of every
## currently in-reach Strike target, in the same order _strike_reachable_targets()
## returns them.
func _strike_reachable_target_ids() -> Array:
	var ids: Array = []
	for target in _strike_reachable_targets():
		ids.append(_strike_target_id(target))
	return ids


## _find_strike_reachable_target(target_id) -> Dictionary -- looks up
## target_id ONLY among the currently in-reach targets, never the wider
## `_enemies` list -- the enforcement point ensuring a non-reachable target
## can never be selected, even by id (mirrors the removed
## strike_action_control.gd's _find_selectable_target()). Returns an empty
## Dictionary (never null) when not found, matching this file's existing
## "empty Dictionary == not found" convention (e.g. resolve_action_use_case.gd's
## _is_target_invalid()).
func _find_strike_reachable_target(target_id: String) -> Dictionary:
	for target in _strike_reachable_targets():
		if _strike_target_id(target) == target_id:
			return target
	return {}


## _action_economy_for(combatant) -> ActionEconomy or null — iteration K
## FEAT-004 (US-004, ADR-004): looks up the live ActionEconomy `encounter`
## (core/combat/encounter.gd) already holds for `combatant`, so
## _verb_bar_strike_execute() can hand the enemy TARGET's own (not the
## acting player's) live budget into resolve_action_use_case.resolve_reactive()
## — the reactor's reaction must spend from ITS OWN budget, never the
## attacker's. Mirrors core/application/round_session.gd's private
## _find_action_economy_for() identity convention exactly (object-identity
## match first, falling back to the combatant_id/name convention used
## throughout this codebase) — a NEW, independent copy here since
## round_session.gd is out of this feature's file scope, but `encounter`'s
## ActionEconomy instances are the SAME live objects RunRoundUseCase.begin_round()
## handed to `round_session` (see rewire_session()'s own doc), so a spend here
## is visible everywhere else that reads the same instance.
## Returns null when `encounter` is unwired or no matching entry exists —
## resolve_reactive()/resolution.gd both degrade safely to "reaction
## untracked" in that case (never a crash).
func _action_economy_for(combatant: Dictionary):
	if encounter == null:
		return null

	var order: Array = encounter.get_turn_order()
	for i in range(order.size()):
		if is_same(order[i], combatant):
			return encounter.get_action_economy(i)

	var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
	if combatant_id != "":
		for i in range(order.size()):
			var candidate: Dictionary = order[i]
			if candidate.get("combatant_id", candidate.get("name", "")) == combatant_id:
				return encounter.get_action_economy(i)

	return null


## _verb_bar_step_availability() -> bool -- FEAT-002 (US-002 / FR-003 /
## FR-004; Iteration F P0-1): additionally queries the active actor's live
## ActionEconomy.can_take_movement_action() (core/rules/action_economy.gd,
## read-only, ADR-003) -- STEP is unavailable once EITHER Step or Stride has
## already been taken this turn (the SAME Movement-trait gate FEAT-001 wired
## into core/rules/movement.gd), in addition to the pre-existing "at least
## one legal Step destination" check. This function only READS
## can_take_movement_action(); it never mutates the domain gate itself.
func _verb_bar_step_availability() -> bool:
	var action_economy = _verb_bar_current_action_economy()
	if action_economy != null and not action_economy.can_take_movement_action():
		return false
	return movement_input_controller.get_selectable_step_hexes().size() > 0


func _verb_bar_step_enter_selection() -> Dictionary:
	return {"verb_id": "STEP", "candidate_hexes": movement_input_controller.get_selectable_step_hexes(), "candidate_targets": []}


## _verb_bar_step_execute(selection) -> Dictionary — FEAT-007 (this
## iteration's US-007/FR-010): `selection` is the Layer-2-picked destination
## HexCoord (see _verb_bar_step_enter_selection()'s candidate_hexes). Forwards
## directly to the injected, REUSED movement_input_controller.step_to() (ADR-
## 002: no duplicate movement path -- this is now the SOLE Step entry point,
## replacing the deleted hex_grid_view.hex_clicked auto-resolve handler). On
## success, runs the SAME post-move refresh
## (_after_successful_move()) that handler used to run.
func _verb_bar_step_execute(selection) -> Dictionary:
	var result: Dictionary = movement_input_controller.step_to(selection)
	if result.get("ok", false):
		_after_successful_move()
	return result


## _verb_bar_stride_availability() -> bool -- FEAT-002 (US-002 / FR-003 /
## FR-004; Iteration F P0-1): additionally queries the active actor's live
## ActionEconomy.can_take_movement_action() (read-only, ADR-003) -- STRIDE is
## unavailable once EITHER Step or Stride has already been taken this turn
## (the SAME Movement-trait gate Stride's own action_economy.spend_action()
## call already trips), in addition to the "an action remains AND at least
## one legal Stride destination" checks below.
##
## FEAT-009 (US-009 / FR-004): the "an action remains" half of that check is
## now can_take_action() (mirrors _verb_bar_strike_availability()'s identical
## FEAT-009 change, see its doc above) rather than the coarser
## get_remaining() > 0 -- STRIDE must grey out the instant this turn's ONE
## action has been spent (e.g. by a Strike), even while the shared 7-action
## round budget still has points left, exactly like STRIKE. This function
## only READS can_take_movement_action()/can_take_action(); it never mutates
## either domain gate itself.
func _verb_bar_stride_availability() -> bool:
	var action_economy = _verb_bar_current_action_economy()
	if action_economy != null and not action_economy.can_take_movement_action():
		return false
	var can_act: bool = action_economy.can_take_action() if action_economy != null else false
	return can_act and movement_input_controller.get_selectable_stride_hexes().size() > 0


func _verb_bar_stride_enter_selection() -> Dictionary:
	return {"verb_id": "STRIDE", "candidate_hexes": movement_input_controller.get_selectable_stride_hexes(), "candidate_targets": []}


## _verb_bar_stride_execute(selection) -> Dictionary — FEAT-007 (this
## iteration's US-007/FR-010): mirrors _verb_bar_step_execute() exactly, for
## Stride -- the SOLE Stride entry point now that the legacy
## hex_grid_view.hex_clicked auto-resolve handler is gone.
##
## FEAT-178 (US-014 / FR-014): a Stride spends one action from the SAME live
## ActionEconomy instance Strike's status-bar push already reads from -- but
## unlike Strike (whose post-resolution action-budget snapshot reaches
## StatusPanelView via an AttackEvent, see status_panel_view.gd's
## on_attack_event()), a Stride emits no event at all. `actor_id`/
## `action_economy` are captured BEFORE movement_input_controller.stride_to()
## runs (the Stride never changes whose turn it is, so this is exactly the
## SAME actor/economy the Stride itself spends from) so this composition
## root can explicitly push that snapshot to $StatusPanelView the moment the
## Stride resolves -- closing the gap where the status bar's Actions/Spent
## readout went stale after a Stride (regression coverage: tests/gut/
## test_status_bar_verb_flow_regression.gd).
func _verb_bar_stride_execute(selection) -> Dictionary:
	var actor_id: String = round_session.current_actor().get("combatant_id", "") if round_session != null else ""
	var action_economy = _verb_bar_current_action_economy()

	var result: Dictionary = movement_input_controller.stride_to(selection)
	if result.get("ok", false):
		_after_successful_move()
		if status_panel_view != null and actor_id != "" and action_economy != null:
			status_panel_view.on_verb_action_budget_changed(
				actor_id, action_economy.get_remaining(), action_economy.is_spent()
			)
	return result


func _verb_bar_end_turn_availability() -> bool:
	return true


## End Turn has no Layer 2 (design notes: "no Layer 2, per spec") -- this
## closure exists only so the generic dispatch contract is uniform across
## every verb; VerbBarView.press() calls execute() directly for END_TURN and
## never enter_selection() in practice (mirrors core/application/
## verb_registry.py's end_turn_enter_selection() doc exactly).
func _verb_bar_end_turn_enter_selection() -> Dictionary:
	return {"verb_id": "END_TURN", "candidate_hexes": [], "candidate_targets": []}


func _verb_bar_end_turn_execute(_selection = null) -> Dictionary:
	if end_turn_control == null:
		return {"ok": false}
	return end_turn_control.press()


## _on_verb_bar_selection_entered(verb_id, selection) -> void — FEAT-008 /
## US-008: forwards VerbBarView's own verb_selection_entered signal
## (emitted immediately after registry.enter_selection(verb_id) inside
## VerbBarView.press(), see presentation/verb_bar_view.gd's file-level doc)
## straight to selection_overlay.activate() -- this composition root never
## re-derives or re-queries the descriptor itself, and never special-cases
## verb_id here (ADR-002/CR-001: no forked Layer 2 wiring per verb).
func _on_verb_bar_selection_entered(verb_id: String, selection) -> void:
	selection_overlay.activate(verb_id, selection)


## _on_selection_overlay_resolved(_verb_id, _result) -> void — FEAT-008 /
## US-008: fires once selection_overlay resolves a highlighted target/hex
## click through `_verb_registry.execute()` (whichever verb it was -- this
## handler is generic, mirroring selection_overlay.gd's own verb-agnostic
## discipline). Re-gates $VerbBarView (a Strike/Stride spends an action,
## which may flip STRIKE/STRIDE availability) via the SAME
## refresh_availability() every other verb-state change already relies on,
## and re-derives the Layer 1 Step/Stride highlight for whoever the current
## actor now is via the SAME _highlight_legal_moves() helper
## _on_active_actor_changed()/_after_successful_move() already call -- a
## resolved Strike does not itself move anyone, so nothing else already
## re-pushes that highlight after selection_overlay.clear() blanks it.
func _on_selection_overlay_resolved(_verb_id: String, _result) -> void:
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()
	if round_session != null:
		var actor: Dictionary = round_session.current_actor()
		var actor_id: String = actor.get("combatant_id", actor.get("name", ""))
		_highlight_legal_moves(actor, actor_id)


## _on_active_actor_changed(combatant) -> void — TurnController
## (presentation/turn_controller.gd) emits this once it settles on a new
## (player) current actor, whether at boot or after auto-driving a run of
## Enemy turns (FEAT-123 / FIND-120). Reconfigures movement_input_controller
## with the live actor/action-economy/live-target data TurnController itself
## does not own (see turn_controller.gd's documented division of
## responsibility) so its Step/Stride affordance stays live for whichever
## combatant's turn it now is -- no separate data path of its own.
##
## FEAT-006: this no longer also reconfigures a strike_action_control (that
## node was removed) -- STRIKE's availability/candidate-target closures
## (_verb_bar_strike_availability()/_verb_bar_strike_enter_selection()/
## _verb_bar_strike_execute()) read round_session.current_actor()/`_enemies`
## directly and fresh on every call instead, so there is no per-turn snapshot
## to (re)push here at all.
func _on_active_actor_changed(combatant: Dictionary) -> void:
	if round_session == null:
		return
	var action_economy = round_session.current_action_economy()
	var active_combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))

	movement_input_controller.configure(
		combatant,
		_other_living_combatants(combatant),
		hex_grid_view,
		active_combatant_id,
		action_economy
	)

	_highlight_legal_moves(combatant, active_combatant_id)

	# FEAT-004 / US-004/FR-001: re-gate the Layer 1 verb bar for whoever the
	# turn now belongs to -- movement_input_controller above is now configured
	# for the NEW actor, and STRIKE's closures read round_session/`_enemies`
	# live, so is_available() reflects current state, never a stale
	# prior-actor's gating.
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()

	# FEAT-006 (enemy-Stride display fix): re-push EVERY combatant's action
	# budget now that control has settled back on a player after any auto-driven
	# Enemy turn(s). A player Stride pushes its own snapshot inline
	# (_verb_bar_stride_execute), and any Strike updates the panel via its
	# AttackEvent — but an Enemy Stride/WAIT (round_session.advance_ai_turn())
	# spends a budget action while emitting no event at all, so the enemy row's
	# Actions/Spent readout would otherwise stay stale. Reuses the SAME
	# StatusPanelView.on_verb_action_budget_changed() the player-Stride path
	# uses, driven off round_session.action_budget_snapshot() (the live,
	# authoritative per-entry economies).
	_refresh_all_action_budgets()


## _refresh_all_action_budgets() -> void — pushes each combatant's current
## Actions-remaining/Spent state to $StatusPanelView from
## round_session.action_budget_snapshot(). Idempotent and safe to call whenever
## control settles (after AI turns, on round-over) — it only READS the live
## economies and forwards them through StatusPanelView's existing per-combatant
## update contract; it never mutates a budget or derives one itself. A no-op
## when no session/panel is wired.
func _refresh_all_action_budgets() -> void:
	if round_session == null or status_panel_view == null:
		return
	for row in round_session.action_budget_snapshot():
		status_panel_view.on_verb_action_budget_changed(
			row["combatant_id"], row["remaining"], row["spent"]
		)


## _highlight_legal_moves(combatant, active_combatant_id) -> void — FEAT-006 /
## US-006 (FR-001, ADR-004): the turn_started handler's highlight step
## (design notes' API contract #1 — this codebase realizes "turn_started" as
## TurnController.active_actor_changed, see presentation/turn_controller.gd
## and tests/infrastructure/test_presentation_stack_wiring.gd). Computes
## union(movement_input_controller.get_selectable_step_hexes(),
## get_selectable_stride_hexes()) for the NOW-configured actor and pushes it
## to hex_grid_view.set_selectable_hexes() — fixing the P0-1 bug where this
## call was never made at all: movement_input_controller.configure()'s own
## internal push (presentation/movement_input_controller.gd's
## _recompute_selectable_destinations()) only ever reports Step destinations,
## never Stride, so this composition root explicitly re-asserts the WIDER
## union here immediately afterward rather than relying on that internal
## push alone.
##
## FEAT-007 (this iteration's US-007/FR-010): the union computed here is no
## longer also handed to a move_action_control.configure() call --
## presentation/MoveActionControl.gd (the passive "Move" indicator this used
## to also drive) has been deleted; Step/Stride availability is now surfaced
## entirely through $VerbBarView's STEP/STRIDE buttons (re-gated via
## verb_bar_view.refresh_availability(), called by this method's caller,
## _on_active_actor_changed(), immediately after this method returns).
##
## When `combatant` is not the active PLAYER (an enemy's turn), no highlight
## may be shown at all (API contract #1) — this defensively clears
## hex_grid_view instead, even though TurnController.active_actor_changed
## only ever fires for a settled player actor today (see
## presentation/turn_controller.gd's _drive()); this handler must not rely on
## that invariant holding forever.
##
## Emits a structured debug log line (observability requirement) including
## combatant_id and the Step/Stride hex counts that produced the highlighted
## union, both to stdout (print(), matching this file's existing
## ConsoleEventSinkAdapter.emit() convention) AND recorded on
## `_last_highlight_debug_log` so GUT tests can assert on it directly.
func _highlight_legal_moves(combatant: Dictionary, active_combatant_id: String) -> void:
	var is_enemy_turn: bool = combatant.get("_is_enemy", false)

	if is_enemy_turn:
		if hex_grid_view != null:
			hex_grid_view.set_selectable_hexes([])
		_last_highlight_debug_log = (
			"DEBUG: highlight_legal_moves combatant_id=" + active_combatant_id
			+ " step_hex_count=0 stride_hex_count=0 (non-player turn, highlight suppressed)"
		)
		print(_last_highlight_debug_log)
		return

	var step_hexes: Array = movement_input_controller.get_selectable_step_hexes()
	var stride_hexes: Array = movement_input_controller.get_selectable_stride_hexes()
	var union_hexes: Array = _union_hexes(step_hexes, stride_hexes)

	if hex_grid_view != null:
		hex_grid_view.set_selectable_hexes(union_hexes)

	_last_highlight_debug_log = (
		"DEBUG: highlight_legal_moves combatant_id=" + active_combatant_id
		+ " step_hex_count=" + str(step_hexes.size())
		+ " stride_hex_count=" + str(stride_hexes.size())
	)
	print(_last_highlight_debug_log)


## _union_hexes(step_hexes, stride_hexes) -> Array — the deduplicated union of
## two HexCoord arrays, compared via core/geometry/hex_coord.gd's equals()
## (the same equality convention used throughout this codebase, e.g.
## presentation/movement_input_controller.gd's _find_selectable()). Every
## legal Step destination is currently also always a legal Stride
## destination (both apply the identical unoccupied check at distance 1 —
## see core/rules/movement.gd's file-level doc), so this reduces to
## stride_hexes today — but is computed as an explicit union (never just
## returning stride_hexes) so this stays correct even if that relationship
## between the two rules ever changes.
func _union_hexes(step_hexes: Array, stride_hexes: Array) -> Array:
	var union_hexes: Array = []
	for hex_coord in step_hexes:
		union_hexes.append(hex_coord)
	for hex_coord in stride_hexes:
		var already_included: bool = false
		for existing in union_hexes:
			if existing.equals(hex_coord):
				already_included = true
				break
		if not already_included:
			union_hexes.append(hex_coord)
	return union_hexes


## _on_round_over() -> void — TurnController emits this once the held
## RoundSession reports is_round_over(). Refreshes `outcome` and defensively
## clears movement_input_controller's selectable destinations (no acting
## combatant, no selectable targets) even for the case where the round ends
## without a decided EncounterResultEvent (ResultScreenView only reacts to
## that terminal event; this is a defensive backstop for that gap,
## FEAT-123).
##
## FEAT-006: no longer also clears a strike_action_control (that node was
## removed) -- once round_session.is_round_over() is true,
## round_session.current_actor() returns {} (see core/application/
## round_session.gd), so _strike_reachable_targets() (and therefore STRIKE's
## availability/enter_selection/execute closures) already naturally report
## no actor/no targets with zero extra bookkeeping here.
##
## FEAT-007 (this iteration): no longer also clears a move_action_control
## (that node was deleted) -- Step/Stride availability is re-gated below via
## verb_bar_view.refresh_availability(), the SAME mechanism every other verb
## already relies on.
##
## FEAT-006 (US-004/FR-004, ADR-012 -- multi-round continuation): this
## composition root's held RoundSession is now finish()ed the instant the
## round is over (previously finish() was never called by this interactive
## pipeline at all) — resetting every combatant's ActionEconomy back to a
## fresh 7-action budget when (and ONLY when) THIS round's own outcome is
## still undecided (round_session.gd's finish() doc; CR-001 AC-2's per-round
## budget contract). When that is the case, ROUND_NUMBER is incremented by
## exactly one and rewire_session() — the SAME single reusable method
## _ready() already called at startup, no duplicated begin_round()/
## set_token_reposition_fn()/TurnController.set_session() wiring here —
## begins the next round immediately, so the steel thread never stalls
## waiting on further player input it will never receive for a round that
## has already concluded. A DECIDED ('won'/'lost') outcome is a terminal
## state instead: ResultScreenView already reacted to the
## EncounterResultEvent resolve_action_use_case/RoundSession emitted the
## instant the decision was made (see round_session.gd's
## _after_action_resolved()), so no further round is ever started here.
## FEAT-003 (US-002 / FR-002, ADR-003): now a coroutine — rewire_session()
## below is itself a coroutine as of this feature; `await`ing it here keeps
## this handler's existing contract that the next round is fully wired
## before it returns. Safe to connect as a Signal handler
## (turn_controller.round_over.connect(_on_round_over), _ready() above)
## exactly as before — Godot never requires (or permits) a signal `emit()`
## call to `await` its own connected handlers, so TurnController.round_over
## firing from inside a suspended _drive() is unaffected by this handler
## also being a coroutine.
func _on_round_over() -> void:
	if round_session == null:
		return

	round_session.finish()
	outcome = round_session.outcome()

	movement_input_controller.configure({}, [])
	# FEAT-004 / US-004/FR-001: re-gate the verb bar now that no actor/targets
	# remain configured (Strike/Step/Stride all become unavailable; End Turn
	# stays always-available per its own availability closure).
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()

	if outcome == "":
		ROUND_NUMBER += 1
		# FEAT-003: rewire_session() is now a coroutine — awaited (see this
		# method's own FEAT-003 doc above).
		await rewire_session()


## _on_end_turn_control_turn_ended(_result) -> void — $EndTurnControl's own
## press() forwards directly to RoundSession.end_current_turn() (US-010),
## then emits this signal (connected above) with that call's result. This
## composition root reacts by re-invoking TurnController.set_session() with
## the SAME RoundSession (documented safe to call repeatedly) so any
## consecutive Enemy turn(s) the cursor now sits on are auto-driven via
## RoundSession.advance_ai_turn() before yielding back to the player
## (US-011) — the single, non-duplicated entry point for "player passes ->
## AI turns resolve" (FEAT-123 / FIND-120), without introducing any new
## public API on either control (ADR-002/CR-001 guardrail).
##
## FEAT-009 (US-009 / FR-004): `verb_bar_view` (fourth argument) is ALSO
## re-passed here -- the cursor has already advanced past the player onto
## whichever Enemy turn(s) `_round_session.end_current_turn()` above just
## uncovered, so this is the real, effective call site: TurnController's own
## _drive() (see its FEAT-009 doc) refreshes $VerbBarView.refresh_availability()
## BOTH immediately (while an Enemy is still the current actor) AND once the
## auto-drive settles back on the player (or the round ends), so Strike/
## Stride never render a stale (pre-AI-turn) grey/enabled state for even one
## frame once control returns to the player.
## FEAT-003 (US-002 / FR-002, ADR-003): now a coroutine — both
## TurnController.set_session() and _on_round_over() below are themselves
## coroutines as of this feature; `await`ing them here keeps this handler's
## existing contract (see file-level doc above). Safe to connect as a Signal
## handler (end_turn_control.turn_ended.connect(...), _ready() above)
## exactly as before, for the same reason documented on _on_round_over().
func _on_end_turn_control_turn_ended(_result: Dictionary) -> void:
	if turn_controller == null or round_session == null:
		return
	# FEAT-006 (round-stall fix): when end_current_turn() above ALREADY drove
	# the round to its end — every living combatant Spent, so
	# round_session.is_round_over() is now true — TurnController.set_session()/
	# _drive() must NOT be the path we take (there is no enemy turn left to
	# auto-drive), but we must STILL trigger the round-over continuation. The
	# round_over signal only ever fires from inside _drive() (see
	# presentation/turn_controller.gd), which this branch skips — so a bare
	# `return` here silently swallows the round-over transition and the round
	# stalls forever (End Turn appears to do nothing, no next round begins).
	# Invoke _on_round_over() directly — the SAME handler TurnController.round_over
	# is wired to — so finish()/ROUND_NUMBER++/rewire_session() run and the next
	# round begins.
	if round_session.is_round_over():
		await _on_round_over()
		return
	await turn_controller.set_session(round_session, null, null, verb_bar_view)


## _after_successful_move() -> void — FEAT-007 (this iteration's US-007/
## FR-010): the shared post-move refresh both _verb_bar_step_execute() and
## _verb_bar_stride_execute() run the moment movement_input_controller
## reports a successful Step/Stride. Replaces the deleted
## _on_hex_grid_view_hex_clicked()'s identical inline logic (FEAT-013/
## FEAT-014's original click-to-move handler, removed by this feature since
## Step/Stride are now driven solely through the verb registry, never a
## standing hex_grid_view.hex_clicked subscription) — behavior is otherwise
## UNCHANGED: re-invokes _on_active_actor_changed() with the SAME (now-moved)
## current actor so STRIKE's in-reach target set (and STEP/STRIDE's own
## availability) re-gates from the new position (Strike reach re-gate,
## FEAT-013/FEAT-014's test_criteria) — this composition root never
## re-derives that reach logic itself, it only re-triggers the SAME
## reconfiguration path US-009 already established.
##
## FEAT-008 / US-008 (FR-003, design notes' API contract #4): on a successful
## Step OR Stride, hex_grid_view.set_selectable_hexes([]) is pushed
## IMMEDIATELY -- before _on_active_actor_changed() below re-derives and
## re-pushes whatever legal-move set now applies from the mover's new
## position -- so the stale, pre-move highlight is never left visibly
## selectable for even one frame while _refresh_off_guard_conditions()/
## _on_active_actor_changed() do their (synchronous, but non-trivial) work.
## movement_input_controller.step_to()/stride_to() themselves already push
## their own (Step-only) selectable set to hex_grid_view as part of
## re-deriving their internal destination cache (presentation/
## movement_input_controller.gd's _recompute_selectable_destinations()) --
## this explicit clear is pushed AFTER that internal push completes, so it is
## always the last word before this composition root's own re-highlight.
func _after_successful_move() -> void:
	if hex_grid_view != null:
		hex_grid_view.set_selectable_hexes([])
	_refresh_off_guard_conditions()
	if round_session != null:
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


## _find_combatant_by_id(combatant_id) -> Dictionary -- looks up
## combatant_id (the SAME "combatant_id" falling back to "name" identity
## convention used throughout this file) among the FULL `_party + _enemies`
## roster, never only the living subset -- a defensive-but-defeated
## combatant is still a valid lookup target, mirroring
## _other_living_combatants()'s own identity matching. Returns an empty
## Dictionary (never null) when not found, matching this file's existing
## "empty Dictionary == not found" convention (e.g. _find_strike_reachable_target()).
func _find_combatant_by_id(combatant_id: String) -> Dictionary:
	for c in _party + _enemies:
		if c.get("combatant_id", c.get("name", "")) == combatant_id:
			return c
	return {}


## _query_selectable_step_hexes(combatant_id) -> Array -- FEAT-002 (US-002,
## Dodge-Step steel thread): the IStepHexQueryPort Callable
## round_session.set_step_hex_query_fn() is wired to in rewire_session()
## above. Looks `combatant_id` up via _find_combatant_by_id() and forwards
## to the unchanged movement_input_controller.get_selectable_step_hexes_for()
## query (the SAME domain adjacency rule get_selectable_step_hexes() itself
## already reuses -- ADR-002 "no duplicate seam") -- deliberately a STATELESS
## query against a scratch (combatant, other_combatants) pair, rather than
## reconfigure()ing the shared movement_input_controller instance, so asking
## for a Dodge-Step prompt mid-way through an ENEMY's turn never disturbs
## that shared controller's own currently-configured actor/highlight state
## (e.g. the enemy's own Step/Stride affordance, or whichever player actor it
## was last configure()d for). Returns an empty Array (never fabricates a
## hex) when `combatant_id` cannot be found on the current roster.
func _query_selectable_step_hexes(combatant_id: String) -> Array:
	var combatant: Dictionary = _find_combatant_by_id(combatant_id)
	if combatant.is_empty():
		return []
	return movement_input_controller.get_selectable_step_hexes_for(combatant, _other_living_combatants(combatant))


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


## _refresh_off_guard_conditions() -> void — FEAT-015 (US-015 / FR-016);
## FEAT-153 (US-015 / FR-016, resolves FIND-142/FIND-145): recomputes
## Off-Guard for every living combatant on the field via core/rules/
## flanking.gd's Flanking.is_off_guard() (pure domain positional detector)
## and:
##   1. pushes the result into $StatusPanelView via
##      StatusPanelView.set_off_guard(), so the readout stays live as
##      combatants Step/Stride around the field (US-015's "surfaced in
##      the per-combatant readout" criterion), AND
##   2. writes Flanking.off_guard_conditions() directly into the LIVE
##      combatant Dictionary's "conditions" key (the SAME `_party`/`_enemies`
##      entries core/application/resolve_action_use_case.gd's resolve()
##      reads as its `target` argument via StrikeActionControl/RoundSession)
##      so the FR-016 blanket +2 bonus this composition root's readout has
##      always displayed also reaches the actual live Strike resolution path
##      (FEAT-153 / FIND-142 -- previously this method only updated the
##      read-only StatusPanelView projection, leaving the bonus dead in the
##      real game loop even though core/rules/resolution.gd implemented it
##      correctly for the unused legacy path).
## Team affiliation -- which this composition root, not the team-agnostic
## domain detector, is responsible for supplying (see flanking.gd's
## file-level doc) -- is derived from which of `_party`/`_enemies` a
## combatant belongs to: a party member's candidate flankers are the living
## enemies, and vice versa. Called once at boot (right after the initial
## StatusPanelView snapshot) and again after every successful Step/Stride
## (_after_successful_move()), since either side's move can flank OR unflank
## any combatant on the field, not only the mover itself.
func _refresh_off_guard_conditions() -> void:
	var living_party: Array = _living_combatants(_party)
	var living_enemies: Array = _living_combatants(_enemies)

	for combatant in _party:
		var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
		var off_guard: bool = FlankingClass.is_off_guard(combatant, living_enemies)
		combatant["conditions"] = FlankingClass.off_guard_conditions(combatant, living_enemies)
		if status_panel_view != null:
			status_panel_view.set_off_guard(combatant_id, off_guard)

	for combatant in _enemies:
		var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
		var off_guard: bool = FlankingClass.is_off_guard(combatant, living_party)
		combatant["conditions"] = FlankingClass.off_guard_conditions(combatant, living_party)
		if status_panel_view != null:
			status_panel_view.set_off_guard(combatant_id, off_guard)


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
			"damage_die":                weapon_res.damage_die,
			# FEAT-006 real-play fix: carry the DEFENSIVE reaction fields too, so
			# the live reaction window can offer Parry/Block (not just Dodge) and
			# resolution.gd's Parry/Block math has the values it needs. Without
			# these, is_parry_eligible()/is_block_eligible() read 0 and the pop-up
			# only ever shows Dodge — the reaction-window aggregation + weapon data
			# (parry_bonus/block_value on the WeaponResource) were correct, this
			# composition-root combatant build was the sole missing link.
			"parry_bonus":               weapon_res.parry_bonus,
			"block_value":               weapon_res.block_value,
			"block_die":                 weapon_res.block_die
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
##
## FEAT-008 (US-008 / FR-008, ADR-106): ac/fortitude/reflex/will are read
## DIRECTLY from the loaded EnemyResource's own authored fields (data/
## enemies/enemy_resource.gd, populated e.g. by data/enemies/skeleton.tres —
## ac=14, fortitude=13, reflex=12, will=12) — never a hard-coded fallback
## constant. The previous placeholder AC constant this file used to fall
## back to has been removed entirely: a Strike against an EnemyResource-built
## target rolls against that resource's OWN authored AC (14 for the
## Skeleton), closing the steel thread's exit criterion. core/sim/
## simulator.gd's own combatant-construction path reads these same four
## fields from the same EnemyResource source (see that file), so the sim
## and the live game can never silently diverge on enemy defenses.
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
		"ac":         enemy.ac,
		"fortitude":  enemy.fortitude,
		"reflex":     enemy.reflex,
		"will":       enemy.will,
		"strength":   enemy.str,
		"dexterity":  enemy.dex,
		"intuition":  enemy.intuition,
		"weapon": {
			"damage_modifier_attribute": weapon_attribute,
			"proficiency_bonus":         enemy.weapon.get("proficiency_bonus", 1),
			"damage_die":                enemy.weapon.get("die", 6),
			# FEAT-001 (iteration K): carry the DEFENSIVE reaction fields too
			# (mirrors _build_party_combatant()'s identical FEAT-006 fix above)
			# so is_parry_eligible()/is_block_eligible() read non-zero values
			# for enemy defenders too — without these, an enemy's weapon dict
			# always read 0 and the reaction window could never offer the
			# enemy a Parry/Block choice.
			"parry_bonus":               enemy.parry_bonus,
			"block_value":               enemy.block_value,
			"block_die":                 enemy.block_die
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
