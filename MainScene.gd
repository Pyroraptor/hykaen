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
##      FEAT-316 (resolves DEF-001/PR-001): steps 8-9's rewire_session() call
##      and this active_actor_changed/round_over subscription -- along with
##      step 11's verb_bar_view.configure()/selection_overlay.configure()
##      below -- no longer happen unconditionally here in _ready(). They now
##      happen ONLY inside _on_combat_triggered() (see its own FEAT-316 doc),
##      once a real exploration trigger commits `_game_mode` to
##      GameMode.COMBAT, so the legacy combat pipeline this whole numbered
##      list describes stays entirely dormant throughout EXPLORATION mode.
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
const CombatantFactoryClass            = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")

## CombatSessionFactoryClass / GdResourceLoaderAdapterClass — FEAT-003
## (US-001 / FR-008, ADR-004): core/application/combat_session_factory.gd's
## CombatSessionFactory.build(deps) now assembles hex_combatants/party/
## enemies from PROLOGUE_ENCOUNTER_PATH — the composition root's former
## inline init block below — via the injected GdResourceLoaderAdapter (the
## sole load()/ResourceLoader caller for that seam, ADR-005; a fake
## CombatResourceLoaderPort is injected instead under GUT, see
## tests/gut/test_combat_session_factory.gd).
const CombatSessionFactoryClass        = preload("res://core/application/combat_session_factory.gd")
const GdResourceLoaderAdapterClass     = preload("res://presentation/adapters/gd_resource_loader_adapter.gd")

## ScenarioSessionClass / ExplorationControllerClass — FEAT-006 (US-005 /
## FR-004): core/application/scenario_session.gd's ScenarioSession
## (FEAT-003) and core/application/exploration_controller.gd's
## ExplorationController (FEAT-005), the two Application-layer collaborators
## this composition root wires so the game boots into an exploration-mode
## state instead of the pre-existing hardcoded combat setup below. Preloaded
## alongside every other use case/adapter this composition root wires
## (ADR-006).
const ScenarioSessionClass             = preload("res://core/application/scenario_session.gd")
const ExplorationControllerClass       = preload("res://core/application/exploration_controller.gd")

## LoadScenarioEncounterUseCaseClass — FEAT-010 (US-009 / FR-008, NFR-001):
## core/application/use_cases/load_scenario_encounter_use_case.gd's
## LoadScenarioEncounterUseCase (FEAT-008/FEAT-009), driven by the new
## load_encounter_from_scenario() method below. Preloaded alongside every
## other use case/adapter this composition root wires (ADR-006) — this is
## the ONLY new const this feature adds to MainScene.gd.
const LoadScenarioEncounterUseCaseClass = preload("res://core/application/use_cases/load_scenario_encounter_use_case.gd")
const ViewModelBuilderClass            = preload("res://presentation/view_model_builder.gd")
const RoundSessionHolderClass          = preload("res://infrastructure/round_session_holder.gd")
const TurnPresentationControllerClass  = preload("res://presentation/turn_presentation_controller.gd")
const ReactionControllerClass          = preload("res://presentation/reaction_controller.gd")
const EndTurnActionControllerClass     = preload("res://presentation/end_turn_action_controller.gd")
const StepActionControllerClass        = preload("res://presentation/step_action_controller.gd")
const StrideActionControllerClass      = preload("res://presentation/stride_action_controller.gd")
const StrikeActionControllerClass      = preload("res://presentation/strike_action_controller.gd")
const SpellActionControllerClass       = preload("res://presentation/verbs/spell_action_controller.gd")

## ResolveSpellControllerClass — FEAT-283 (resolves PR-001): preloaded here
## ONLY so this file can doc-reference/typecheck it; MainScene never
## constructs a ResolveSpellController directly (SpellActionController does,
## from `deps["resolution_port"]`/`deps["combat_log_port"]`/
## `deps["energy_pool_fn"]` below — see that file's own `_init()`).
const ResolveSpellControllerClass      = preload("res://presentation/verbs/resolve_spell_controller.gd")

## CombineActionControllerClass — FEAT-001 (US-001, FR-003, ADR-001),
## Iteration N (Combinations) kickoff: presentation/combine_action_controller.gd's
## CombineActionController, the COMBINE meta-verb's entry-point scaffold.
## Registered below in VERB_TABLE exactly like every other verb — reached
## via `_controller("COMBINE")` — so a later feature's real sub-action queue
## orchestration reaches STRIDE/STRIKE through THIS SAME `_controller(verb_id)`
## lookup rather than a hard-coded reference.
const CombineActionControllerClass     = preload("res://presentation/combine_action_controller.gd")

## MultiPhaseTargetingControllerClass / CoreCombineActionControllerClass —
## FEAT-005 (Iteration O "Combine Selection UX"; US-005; FR-004/FR-013;
## NFR-002/NFR-003; ADR-002): core/application/combine/
## multi_phase_targeting_controller.gd's MultiPhaseTargetingController (the
## generalized, length-agnostic N-entry sequential targeting loop) and
## core/controllers/combine_action_controller.gd's CombineActionController
## (Iteration O's own DEF-001 re-validation-gated `execute()`, FEAT-004) —
## a DIFFERENT class from `CombineActionControllerClass` immediately above
## (presentation/combine_action_controller.gd, the OLDER Iteration N
## scaffold still registered in VERB_TABLE below), hence the distinct
## `CoreCombineActionControllerClass` alias here rather than a colliding
## name. Wired minimally in _ready() (see that method's own FEAT-005 doc)
## — this feature's OWN scope is the standalone targeting loop itself,
## proven in isolation with injected fakes by tests/unit/application/
## combine/test_multi_phase_targeting_controller.gd; hooking this
## composition-root instance up to a live selection_resolved signal flow is
## a LATER feature (US-006) layered on top of this same seam.
const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const CoreCombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const CoreStrideActionControllerClass = preload("res://core/controllers/stride_action_controller.gd")
const CoreStrikeActionControllerClass = preload("res://core/controllers/strike_action_controller.gd")

## CoreCastSpellAdapterClass / GdVerbRegistryPortClass /
## GdCombineActionEconomyPortClass — FEAT-002 (US-002; FR-001; ADR-002):
## three of the five inner adapter/port classes formerly defined inline
## inside this file (`_CoreCastSpellAdapter` / `_GdVerbRegistryPort` /
## `_GdCombineActionEconomyPort`) now live as standalone top-level classes
## under presentation/adapters/ — extracted VERBATIM (same method
## bodies/signatures), preload()ed here instead of defined inline, per the
## design notes' "adapters are concrete GDScript classes ... in
## presentation/adapters/" architecture section. This is the foundational
## dependency-inversion seam US-003/004/005/007 build on. The other two,
## `_CombineBuildRegistryProxy`/CombineBuildRegistryProxy and
## `_CombineTargetingRegistryProxy`/CombineTargetingRegistryProxy, are no
## longer preloaded HERE at all — FEAT-004/FEAT-005 moved their sole
## construction sites into presentation/combine_queue_build_session.gd /
## presentation/combine_targeting_session.gd (CombineQueueBuildSessionClass /
## CombineTargetingSessionClass immediately below), which now own them
## directly.
const CoreCastSpellAdapterClass = preload("res://presentation/adapters/core_cast_spell_adapter.gd")
const GdVerbRegistryPortClass = preload("res://presentation/adapters/gd_verb_registry_port.gd")
const GdCombineActionEconomyPortClass = preload("res://presentation/adapters/gd_combine_action_economy_port.gd")

## CombineQueueBuildSessionClass — FEAT-004 (US-003; FR-003; ADR-005): the
## extracted interactive Combine QUEUE-BUILD pick-loop state machine
## (presentation/combine_queue_build_session.gd). Owns the domain/
## application-layer collaborators (CombineQueue/VerbQueueEntry,
## BuildVerbQueueUseCase/ConfirmQueueUseCase/CancelCombineUseCase) and the
## CombineBuildRegistryProxy adapter (FEAT-002) a real player's COMBINE
## press now drives, via `combine_queue_build_session.start(actor)`, so a
## real COMBINE press builds a genuine incremental CombineQueue instead of
## the historical hardcoded queue_entries=[STRIDE, STRIKE]. This
## composition root no longer references any of those collaborators
## directly (see combine_queue_build_session.gd's own file-level doc for
## the full dependency list this class now owns instead).
const CombineQueueBuildSessionClass = preload("res://presentation/combine_queue_build_session.gd")

## CombineTargetingSessionClass — FEAT-005 (US-004; FR-004; ADR-003): the
## extracted interactive Combine sub-action TARGETING pick-loop state machine
## (presentation/combine_targeting_session.gd). Wraps the composition-root-
## owned `multi_phase_targeting_controller` (UNCHANGED, RISK-002) via
## composition only -- see that file's own file-level doc for the full
## dependency list and the "no domain/phase-evaluation logic duplicated"
## guarantee. This composition root no longer owns the interactive per-phase
## loop's own state or algorithm directly (formerly a set of private fields/
## helper methods on this very file, FEAT-007 -- see
## presentation/combine_targeting_session.gd's own file-level doc for the
## complete before/after mapping).
const CombineTargetingSessionClass = preload("res://presentation/combine_targeting_session.gd")

## RoundFlowControllerClass — FEAT-006 (US-006 / FR-007): the extracted,
## independently-testable turn-order / round-lifecycle controller
## (presentation/round_flow_controller.gd). This composition root
## constructs/`setup(deps)`s a REAL instance (wired against the SAME
## `run_round_use_case` and `_party`/`_enemies` — the CombatSessionFactory.
## build() output, FEAT-003 — this file already drives) and connects to its
## own `round_over()` signal for UI-cleanup-only observability. See that
## file's own extensive doc for exactly why this composition root's
## PRE-EXISTING, pinned `rewire_session()`/`_on_round_over()` pair (below)
## remains the sole live driver of the real encounter's round-flow — this
## class's own `rewire_session()` is exercised for real only by its own
## dedicated GUT suite (tests/gut/test_round_flow_controller.gd), against a
## fake run_round_use_case/turn_controller, so wiring it here never risks a
## second, parallel `RunRoundUseCase.begin_round()` call site.
const RoundFlowControllerClass = preload("res://presentation/round_flow_controller.gd")


## SpellPickerPanelControllerClass — FEAT-008 (US-007 / FR-002): the
## extracted leaf UI controller for the floating spell-picker panel
## (presentation/spell_picker_panel_controller.gd), formerly this file's own
## `_setup_spell_picker_panel()` / `_show_spell_picker()` /
## `_on_spell_option_pressed()` / `_hide_spell_picker()` quartet. This
## composition root still creates/add_child()s the underlying Panel node
## itself (scene-tree wiring stays here — see `_spell_picker` field's own
## doc) but owns none of the populate/show/hide UI logic anymore.
const SpellPickerPanelControllerClass = preload("res://presentation/spell_picker_panel_controller.gd")

## TargetingPortClass — core/application/ports/targeting_port.gd's abstract
## base (FEAT-283), extended BY PATH below (_FirstLegalTargetingPort) —
## mirrors this project's established preload-typing convention for
## concrete adapters/subtypes (see presentation/ui/combat_log_panel_adapter.gd's
## own doc for why a bare global class_name is avoided as an `extends`
## target).
const TargetingPortClass               = preload("res://core/application/ports/targeting_port.gd")

## ResolutionPortClass — core/application/ports/resolution_port.gd's
## ResolutionPort (FEAT-283); this composition root wires its own
## `ResolutionRulesAdapter` inner class (unmodified, nested in that file)
## around the SAME `random_port` RandomPort adapter every other interactive
## Strike resolution already uses (step 2 of this file's own doc above) —
## no second/parallel RNG stream.
const ResolutionPortClass              = preload("res://core/application/ports/resolution_port.gd")

## CombatLogPanelAdapterClass — presentation/ui/combat_log_panel_adapter.gd's
## CombatLogPanelAdapter (FEAT-283), the ONE production CombatLogPort
## implementation this codebase ships — wired here so CAST_SPELL's
## ResolveCastUseCase (invoked from ResolveSpellController, via
## SpellActionController's `_maybe_resolve_cast()`) has a real place to emit
## CAST_BEGIN/CAST_CONTINUE/CAST_RESOLVE/CAST_CANCELLED entries to, mirroring
## every other Presentation projection this composition root already wires
## (`event_log_view`, `status_panel_view`, …).
const CombatLogPanelAdapterClass       = preload("res://presentation/ui/combat_log_panel_adapter.gd")

## VERB_TABLE — the single data-driven verb registry (composition-root de-bloat,
## 2026-07-11): verb_id → concrete ActionController subclass. This one table is
## the sole place a verb is enumerated; _build_verb_registry() loops it to wire
## the VerbBarRegistry, and _controller(verb_id) instantiates from it lazily. So
## adding a verb is ~one entry here (+ its controller file + the three thin
## _verb_bar_<verb>_* shims tests call on `self`), NOT scattered edits. A future
## CombineActionController resolves its sub-action controllers via the same
## _controller(verb_id) lookup this table backs.
##
## CAST_SPELL (FEAT-004 / US-004, FR-003) — registered pointing at
## presentation/verbs/spell_action_controller.gd's SpellActionController.
## FEAT-283 (resolves PR-001) completed this verb's composition-root
## wiring: `_verb_deps()` below now carries real `targeting_port`/
## `resolution_port`/`combat_log_port`/`energy_pool_fn` entries alongside
## the SelectionPort/ReactionWindowPort/SpellCatalogPort collaborators
## SpellActionController already read out of it, so
## `_controller("CAST_SPELL")` resolves every dependency
## ResolveCastUseCase's full pipeline needs from the REAL scene composition
## root, with zero test-only overrides.
const VERB_TABLE := {
	"STRIKE": StrikeActionControllerClass,
	"STEP": StepActionControllerClass,
	"STRIDE": StrideActionControllerClass,
	"END_TURN": EndTurnActionControllerClass,
	"CAST_SPELL": SpellActionControllerClass,
	"COMBINE": CombineActionControllerClass,
}
const ConsoleEventSinkAdapterClass     = preload("res://infrastructure/console_event_sink_adapter.gd")
const EncounterTurnOrderAdapterClass   = preload("res://infrastructure/encounter_turn_order_adapter.gd")
const InMemoryRoundHistoryAdapterClass = preload("res://infrastructure/in_memory_round_history_adapter.gd")
const UIHexChoiceResolverClass         = preload("res://infrastructure/ui_hex_choice_resolver.gd")
const VerbBarRegistryAdapterClass      = preload("res://infrastructure/verb_bar_registry_adapter.gd")
const ResolveActionUseCaseClass        = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass     = preload("res://core/application/determine_outcome_use_case.gd")
const RunRoundUseCaseClass             = preload("res://core/application/run_round_use_case.gd")
const AIClass                          = preload("res://core/combat/ai.gd")
const MovementInputControllerClass     = preload("res://presentation/movement_input_controller.gd")
const PlayerTargetingPortClass         = preload("res://presentation/ui/player_targeting_port.gd")
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

## OpenReactionWindowUseCaseClass — iteration K FEAT-006 (US-006): the SAME
## generalized reaction-window opener core/application/
## resolve_action_use_case.gd's resolve_reactive() already uses for the
## enemy-target-of-a-Strike path, reused here (unmodified) to open the
## player-mover Stride path's OpportunisticStrike window synchronously
## against `enemy_reaction_chooser` (AIReactionPolicy) — see
## _resolve_enemy_opportunistic_strike_reaction() below.
const OpenReactionWindowUseCaseClass   = preload("res://core/application/open_reaction_window_use_case.gd")

## ResolveStrideUseCaseClass — iteration K FEAT-006 (US-006): core/application/
## use_cases/resolve_stride_use_case.gd's ResolveStrideUseCase — the
## Application-layer use case that filters eligible OpportunisticStrike
## reactors (core/domain/opportunistic_strike_eligibility.gd) and drives their
## resolution BEFORE a Stride commits, on BOTH the player-mover path
## (_verb_bar_stride_execute() below) and, via
## _resolve_enemy_stride_opportunistic_window(), the enemy-mover path
## (core/combat/ai.gd's injected `_stride_reaction_resolver_fn`).
const ResolveStrideUseCaseClass        = preload("res://core/application/use_cases/resolve_stride_use_case.gd")

## ResolveDodgeStepUseCaseClass — FEAT-005 (US-005, ADR-004): the SAME
## Application-layer use case core/application/round_session.gd's
## `_resolve_dodge_step_prompt()` already drives for the PLAYER's own
## Dodge-Step (enemy-Strikes-player path) — reused verbatim here for the
## ENEMY's own Dodge-Step (player-Strikes-enemy path,
## `_resolve_enemy_dodge_step()` below), never a second/duplicated
## reposition-step implementation (ADR-001/ADR-002 "no duplicate seam" —
## this feature's own code-inspection test_criterion).
const ResolveDodgeStepUseCaseClass     = preload("res://core/application/resolve_dodge_step_use_case.gd")

## AIHexChoiceResolverClass — FEAT-005 (US-005, ADR-004):
## infrastructure/ai_hex_choice_resolver.gd's AIHexChoiceResolver, the enemy
## AI's deterministic, synchronous HexChoiceResolverPort implementation
## (prefer the legal adjacent hex that keeps melee reach on the original
## attacker, else the first legal hex — never a pop-up/highlight). Wired
## ONLY here (see `_resolve_enemy_dodge_step()` below) — MainScene is the
## ONE place a concrete adapter is ever bound to a port (ADR-002/G2),
## mirroring `AIReactionPolicyClass`'s identical precedent for
## ReactionChooserPort. Distinct from `_UIHexChoiceResolver` (which BLOCKS
## on a live hex_grid_view.hex_clicked signal for the PLAYER's own
## Dodge-Step) — the two are independent, swappable adapters behind the
## SAME HexChoiceResolverPort seam, never confused with one another.
const AIHexChoiceResolverClass         = preload("res://infrastructure/ai_hex_choice_resolver.gd")

## AIReactionPolicyClass — iteration K FEAT-004 (US-004, ADR-004):
## infrastructure/ai_reaction_policy.gd's AIReactionPolicy, the enemy AI's
## deterministic, synchronous ReactionChooserPort implementation. Wired ONLY
## here (see `enemy_reaction_chooser` field below) — MainScene is the ONE
## place a concrete adapter is ever bound to a port (ADR-002/G2), mirroring
## `player_reaction_chooser`'s identical precedent for the player-facing pop-up.
const AIReactionPolicyClass            = preload("res://infrastructure/ai_reaction_policy.gd")

## The steel-thread's entry_point: the one encounter this composition root boots into.
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## PROLOGUE_SCENARIO_PATH — FEAT-006 (US-005 / FR-004): the ScenarioResource
## (data/scenarios/scenario_resource.gd, FEAT-006/Iteration-P) this
## composition root loads at boot to construct `scenario_session` /
## `exploration_controller` below. Its sole encounter_entries member wraps
## the SAME PROLOGUE_ENCOUNTER_PATH resource above (no duplicated/forked
## encounter definition, ADR-002).
const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"

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

## GameMode — FEAT-006 (US-005 / FR-004): the two top-level modes this
## composition root can be in. EXPLORATION is the primary user-facing entry
## point (US-005) — the game boots into it by default, walking the party
## around the hex map via `exploration_controller` until a proximity trigger
## fires `combat_triggered`. COMBAT is the pre-existing hardcoded
## round/turn-based pipeline built below in _ready() (RISK-001: reserved for
## a LATER feature's real trigger-driven handoff into it -- this feature only
## introduces the label and the EXPLORATION-side wiring, never flips
## `_game_mode` itself).
enum GameMode { EXPLORATION, COMBAT }

## _game_mode — defaults to GameMode.EXPLORATION (US-005's "boot into
## exploration mode" requirement). Exposed (not private-only in spirit, just
## GDScript's underscore-prefix convention for a composition-root field
## mirroring this file's other exposed-for-verification fields, e.g.
## `centering_offset`) so boot-real tests can assert the default directly.
var _game_mode: GameMode = GameMode.EXPLORATION

## _active_encounter_id — FEAT-008 (US-007 / FR-006): the encounter_id of
## the combat currently in progress. Left at its default "" (unset) until
## `_on_combat_triggered()` commits its atomic mode-switch to
## GameMode.COMBAT -- a FAILED handoff (LoadScenarioEncounterUseCase
## ok=false) never touches this field, matching the atomic-failure contract
## documented on `_on_combat_triggered()` below. Cleared again by a LATER
## feature's `_on_combat_won()` once the encounter concludes.
var _active_encounter_id: String = ""

## scenario_session — the ScenarioSession (core/application/scenario_session.gd,
## FEAT-003) this composition root constructs at boot from
## PROLOGUE_SCENARIO_PATH (FEAT-006 / US-005). Null only if the scenario
## resource itself fails to load (push_error'd, see _boot_exploration_mode()).
var scenario_session = null

## exploration_controller — the ExplorationController (core/application/
## exploration_controller.gd, FEAT-005) this composition root constructs
## around `scenario_session` at boot (FEAT-006 / US-005), with its
## `combat_triggered` signal wired to `_on_combat_triggered()` below (a stub
## at this stage -- the real trigger-driven combat handoff is a LATER
## feature's scope).
var exploration_controller = null

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
##
## Composition-root de-bloat (2026-07-10): `round_session` is now a transparent
## get/set property facade over the stable RoundSessionHolder below. Reads return
## the live session; the single assignment in rewire_session() flows through the
## setter into the holder. This keeps every existing `round_session` call site
## unchanged while giving extracted controllers a stable seam
## (_round_session_holder) to inject ONCE, instead of a reference that is
## replaced every round (which would leave a cross-object captor stale).
var _round_session_holder := RoundSessionHolderClass.new()
var round_session:
	get:
		return _round_session_holder.get_current()
	set(value):
		_round_session_holder.set_current(value)

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

## _turn_presentation_instance / _turn_presentation() — the extracted
## TurnPresentationController (presentation/turn_presentation_controller.gd),
## built lazily on first use by _turn_presentation() below. Lazy (not @onready)
## so it is available BOTH when MainScene is booted normally (TurnController's
## active_actor_changed drives it) AND when a unit/integration test `.new()`s
## MainScene, injects spy collaborators, and calls _on_active_actor_changed()
## directly without a scene-tree _ready(). Its collaborators (the stable
## RoundSessionHolder, the view nodes, the movement_input_controller, a Callable
## to _other_living_combatants) are none of them reassigned after first access,
## so building once is behavior-identical to the old inline live reads.
var _turn_presentation_instance = null
var _reaction_instance = null

## _controllers / _verb_deps_cache — the memoized ActionController pool and the
## single shared deps dict backing the data-driven VERB_TABLE (2026-07-11).
## _controller(verb_id) builds each verb's controller once from _verb_deps(); both
## are lazy so they serve a booted MainScene AND a `.new()` test that drives a verb
## without _ready(). Replaced the four per-verb _<verb>_action_instance fields.
var _controllers: Dictionary = {}
var _verb_deps_cache = null

## multi_phase_targeting_controller / _core_combine_action_controller —
## FEAT-005 (US-005; ADR-002): the composition-root-owned
## MultiPhaseTargetingController instance and its own
## `combine_action_controller` collaborator (core/controllers/
## combine_action_controller.gd's CombineActionController — Iteration O's
## DEF-001-gated `execute()`, FEAT-004), both constructed once in _ready()
## (see that method's own FEAT-005 doc for the registry this is built
## with). Exposed as fields — rather than kept as _ready() locals — so
## tests can verify them directly, mirroring `spell_targeting_port`/
## `reaction_window`'s identical "constructed here, exposed for
## verification/injection" precedent.
var multi_phase_targeting_controller = null
var _core_combine_action_controller = null

## _combine_controller_registry — FEAT-007 (US-007; NFR-001): the SAME
## verb_id -> VerbControllerPort registry Dictionary handed to
## `multi_phase_targeting_controller` above (as its own "controller_registry"
## dep) AND injected into `combine_targeting_session` below (FEAT-005,
## US-004) as its own "controller_registry" dep, reused by that session's
## interactive per-phase Combine targeting loop — one registry, resolved
## once in _ready(), never a second/forked verb_id -> controller lookup path
## (ADR-002's "verb_id whitelisting" security note).
var _combine_controller_registry: Dictionary = {}

## combine_targeting_session — FEAT-005 (US-004; FR-004; ADR-003): the
## composition-root-owned CombineTargetingSession instance
## (presentation/combine_targeting_session.gd) this feature extracts the
## FEAT-007 interactive Combine sub-action TARGETING pick-loop's former
## private per-phase state fields and helper methods (formerly a set of
## `_combine`-prefixed `targeting`-suffixed private fields/methods on this
## very file) into wholesale — see presentation/combine_targeting_session.gd's
## own file-level doc for the full list of what moved and the RISK-002
## "wraps, never re-implements, MultiPhaseTargetingController" guarantee.
## `.new()`d and `.setup(deps)`-wired once in _ready() with
## `multi_phase_targeting_controller` (UNCHANGED) and
## `_combine_controller_registry` (UNCHANGED, still resolved here — see that
## field's own doc) injected as dependencies; this composition root drives
## it purely through its own start(queue_entries, actor, context,
## combine_queue)/abort()/try_advance(verb_id) surface plus its
## targeting_complete(result)/aborted() signals (`_on_combine_targeting_complete()`
## below) — it never reaches into the session's internal state itself.
## Exposed as a field (rather than a _ready() local) so tests can verify it
## directly, mirroring `combine_queue_build_session`'s identical "constructed
## here, exposed for verification" precedent.
var combine_targeting_session = null

## combine_queue_build_session — FEAT-004 (US-003; FR-003; ADR-005): the
## composition-root-owned CombineQueueBuildSession instance
## (presentation/combine_queue_build_session.gd) this feature extracts the
## FEAT-296 (DEF-NEW-001) queue-build pick-loop's former private state
## fields and helper methods into wholesale -- see
## presentation/combine_queue_build_session.gd's own file-level doc for the
## full list of what moved. The Layer 2a incremental STRIDE/STRIKE/Confirm/
## Cancel picker a real COMBINE press now drives BEFORE any targeting phase
## begins (see the "interactive Combine QUEUE-BUILD pick loop" section doc,
## below `_on_combine_queue_built()`) lives entirely inside that class now.
## `.new()`d and `.setup(deps)`-wired once in _ready(); this composition
## root drives it purely through its own start(actor)/abort() surface plus
## its queue_built(queue)/aborted() signals (`_on_combine_queue_built()`
## below) -- it never reaches into the session's internal state itself.
## Exposed as a field (rather than a _ready() local) so tests can verify it
## directly, mirroring `multi_phase_targeting_controller`'s/
## `_core_combine_action_controller`'s identical "constructed here, exposed
## for verification" precedent.
var combine_queue_build_session = null

## round_flow_controller — FEAT-006 (US-006 / FR-007): the composition-root-
## owned RoundFlowController instance (presentation/round_flow_controller.gd).
## `.new()`d and `.setup(deps)`-wired once in _ready(), against the SAME
## `run_round_use_case` and `_party`/`_enemies` this composition root already
## drives. This composition root connects to its `round_over()` signal
## (`_on_round_flow_controller_round_over()` below) for UI cleanup ONLY —
## see that handler's own doc, and round_flow_controller.gd's own file-level
## doc, for why this file's PRE-EXISTING `rewire_session()`/`_on_round_over()`
## pair (below) remains the sole live driver of the real encounter's
## round-flow. Exposed as a field so tests can verify it directly, mirroring
## `combine_queue_build_session`'s/`combine_targeting_session`'s identical
## "constructed here, exposed for verification" precedent.
var round_flow_controller = RoundFlowControllerClass.new()

## _spell_picker — FEAT-008 (US-007 / FR-002): the composition-root-owned
## SpellPickerPanelController instance (presentation/
## spell_picker_panel_controller.gd). `.new()`d here; `.setup(panel_node)`-
## wired once in _ready() against a Panel node this composition root still
## creates/add_child()s itself (the ONE piece of spell-picker scene-tree
## wiring left in this file — see test_infrastructure/
## test_presentation_stack_wiring.gd's "SpellPickerPanel" child-node
## invariant, unaffected by this extraction). This composition root drives
## it purely through its own setup(panel_node)/show(options, on_selected)/
## hide() surface — see spell_picker_panel_controller.gd's own file-level
## doc for the full before/after mapping of what moved out of this file.
var _spell_picker = SpellPickerPanelControllerClass.new()

## _party / _enemies — the live combatant Dictionaries built at boot,
## mutated in place by every resolved Strike throughout the interactive
## session (Dictionaries are reference types in GDScript). Kept as fields so
## this composition root's own signal handlers (reacting to
## TurnController's active_actor_changed/round_over) can rebuild
## StrikeActionControl's live target list without re-deriving it from
## Infrastructure.
var _party: Array = []
var _enemies: Array = []
var _combatant_factory := CombatantFactoryClass.new()
var _view_model_builder := ViewModelBuilderClass.new()


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


## _FirstLegalTargetingPort — SUPERSEDED by presentation/ui/player_targeting_port.gd
## PlayerTargetingPort (wired below). Retained only to avoid breaking any
## external reference by name; no longer instantiated by this composition root.


## spell_targeting_port / spell_resolution_port / spell_combat_log_port —
## FEAT-283 (resolves PR-001): the CAST_SPELL verb's real
## TargetingPort/ResolutionPort/CombatLogPort adapters, constructed ONCE in
## _ready() (see that method's own FEAT-283 doc) and registered under
## `_verb_deps()`'s "targeting_port"/"resolution_port"/"combat_log_port"
## keys below — the four keys design notes' architecture section and
## PR-001's blocker finding called out as never having been wired into the
## real composition root. Exposed as fields (rather than kept as _ready()
## locals) so tests can verify them directly, mirroring
## `enemy_reaction_chooser`/`hex_choice_resolver`/`reaction_window`'s
## identical "constructed here, exposed for verification/injection"
## precedent.
var spell_targeting_port = null
var spell_resolution_port = null
var spell_combat_log_port = null


func _ready() -> void:
	encounter_repository = ResourceEncounterRepositoryClass.new()

	# ── FEAT-003 (US-001 / FR-008, ADR-004): delegate hex_combatants/party/
	# enemies assembly to CombatSessionFactory.build(deps) -- the ONE seam
	# this composition root's former inline resource-loading + party/enemy
	# construction init block now flows through. `resource_loader` is a
	# GdResourceLoaderAdapter (the sole load()/ResourceLoader caller for the
	# encounter resource, ADR-005) so GUT can inject a fake
	# CombatResourceLoaderPort in isolation; `encounter_repository`/
	# `_combatant_factory` are the SAME collaborator instances this
	# composition root always used, simply handed to the factory instead of
	# read as bare fields/consts inline below. On failure (missing/invalid
	# resource path, or a fail-fast enemy-build error) build() push_error()s
	# and returns an empty Dictionary (ADR-005: no exceptions) -- mirrored
	# here with the required `.is_empty()` check + early return. ──────────
	var session: Dictionary = CombatSessionFactoryClass.build({
		"resource_loader": GdResourceLoaderAdapterClass.new(),
		"encounter_repository": encounter_repository,
		"combatant_factory": _combatant_factory,
		"encounter_path": PROLOGUE_ENCOUNTER_PATH,
	})
	if session.is_empty():
		return

	var hex_combatants: Array = session.get("hex_combatants", [])
	_party = session.get("party", [])
	_enemies = session.get("enemies", [])

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

	# ── FEAT-006 (US-005 / FR-004, RISK-001): boot into EXPLORATION mode --
	# construct `scenario_session`/`exploration_controller` from
	# PROLOGUE_SCENARIO_PATH and wire their signals. Party/enemy tokens for
	# the scenario's active encounter entry are already rendered above (the
	# SAME hex_combatants loaded from PROLOGUE_ENCOUNTER_PATH, which is the
	# exact resource the scenario's sole entry wraps -- ADR-002, no
	# duplicated encounter definition), so no second token-loading call is
	# needed here. See _boot_exploration_mode()'s own doc below. ───────────
	_boot_exploration_mode(hex_combatants)

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
	event_sink = ConsoleEventSinkAdapterClass.new()

	# ── FEAT-283 (resolves PR-001): construct CAST_SPELL's real
	# TargetingPort/ResolutionPort/CombatLogPort adapters as early as
	# `random_port` is available (ResolutionPort's ResolutionRulesAdapter is
	# built around it — the SAME RandomPort stream every other interactive
	# resolution in this pipeline already consumes, no second/parallel RNG).
	# Constructed well before `_verb_deps()` is first read (_build_verb_registry()
	# below), so `_controller("CAST_SPELL")` never observes a null value for
	# any of the three. See these fields' own doc above. ────────────────────
	spell_targeting_port = PlayerTargetingPortClass.new(hex_grid_view)
	spell_resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(random_port)
	spell_combat_log_port = CombatLogPanelAdapterClass.new()
	if event_log_view != null:
		spell_combat_log_port.configure(event_log_view)

	# ── FEAT-003 (US-001 / FR-008): `_party`/`_enemies` (Combatant instances)
	# and `hex_combatants` were already assembled above by
	# CombatSessionFactory.build() -- see this method's own FEAT-003 doc.
	var rng := RNGClass.new(resolved_seed)
	encounter = EncounterClass.new(_party, _enemies, rng)
	encounter.initialize()

	var status_view_models: Array = _view_model_builder.build_status_view_models(hex_combatants, _party, _enemies, encounter)

	if status_panel_view != null:
		status_panel_view.load_combatants(status_view_models)
		_refresh_off_guard_conditions()

	var initiative_view_models: Array = _view_model_builder.build_initiative_view_models(hex_combatants, _party, _enemies, encounter)

	if initiative_view != null:
		initiative_view.load_combatants(initiative_view_models)

	event_sink.forward_to = _presentation_event_subscribers()

	# ── FEAT-123 / FIND-120: build the interactive pipeline (RunRoundUseCase
	# .begin_round() -> RoundSession) instead of driving the autonomous
	# core/combat/encounter.gd run_round() while-loop. ─────────────────────
	var turn_order_port = EncounterTurnOrderAdapterClass.new(encounter)
	round_history_port = InMemoryRoundHistoryAdapterClass.new()
	resolve_action_use_case = ResolveActionUseCaseClass.new(random_port, event_sink, round_history_port)
	determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var ai_decision_port = AIClass.new()

	# ── iteration K FEAT-006 (US-006, ADR-004): wire the enemy-mover Stride
	# path's OpportunisticStrike reaction-window seam (core/combat/ai.gd's
	# `_stride_reaction_resolver_fn`) to this composition root's own
	# _resolve_enemy_stride_opportunistic_window() — see that method's own
	# doc. Wired exactly once, on this ONE `ai_decision_port` instance reused
	# across every round via `run_round_use_case`/rewire_session() below, so
	# it stays wired for the whole game session. ───────────────────────────
	ai_decision_port.set_stride_reaction_resolver_fn(Callable(self, "_resolve_enemy_stride_opportunistic_window"))

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

	# ── FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): the
	# turn_controller.active_actor_changed/round_over connections used to be
	# established HERE, unconditionally, regardless of `_game_mode` -- which
	# meant the legacy hardcoded combat pipeline's round-over/active-actor
	# plumbing booted live alongside EXPLORATION mode instead of staying
	# dormant until a real trigger fired (the FR-004 acceptance-criteria gap
	# "_on_round_over is NOT connected at boot"). This connection now happens
	# ONLY inside _on_combat_triggered() below, the real trigger-driven
	# handoff into GameMode.COMBAT -- see that method's own FEAT-316 doc. ────

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
		hex_choice_resolver = UIHexChoiceResolverClass.new(hex_grid_view)

	if end_turn_control != null:
		end_turn_control.turn_ended.connect(_on_end_turn_control_turn_ended)
		# BUGFIX (post-iteration-E): End Turn is now a first-class verb in the
		# Layer 1 verb bar (registry END_TURN entry, whose execute() delegates to
		# end_turn_control.press()). EndTurnControl is retained ONLY as that
		# headless logic delegate (press()/turn_ended + TurnController-managed
		# enabled state), so its own on-screen Button is hidden to avoid a second,
		# duplicate "End Turn" control alongside the verb-bar button.
		end_turn_control.visible = false

	# ── FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001):
	# rewire_session() -- which obtains this round's RoundSession via
	# RunRoundUseCase.begin_round() and hands it to TurnController.set_session()
	# -- used to be invoked HERE, unconditionally, on every boot regardless of
	# `_game_mode`. That meant `round_session` was always live (and the legacy
	# hardcoded combat pipeline always running) even while the game sat in
	# EXPLORATION mode with no trigger yet fired -- the FR-004 acceptance gap
	# this feature closes ("round_session is null ... rewire_session() was not
	# called" at boot). rewire_session() is now called ONLY from
	# _on_combat_triggered() below, the real trigger-driven handoff into
	# GameMode.COMBAT -- see that method's own FEAT-316 doc. ─────────────────

	# ── FEAT-004 / US-004/FR-001: build the Layer 1 verb registry so it is
	# ready the instant _on_combat_triggered() configures $VerbBarView with it
	# (FEAT-316) -- building it here (rather than inside the handoff itself)
	# costs nothing at boot: _build_verb_registry() only wires Callables that
	# read `round_session`/`_party`/`_enemies` fresh off `self` on every call
	# (see its own doc), never a snapshot, so it observes whichever round is
	# live the moment it is actually queried. `verb_bar_view.configure()`
	# itself -- the call that would actually render/activate any verb button --
	# is deferred to _on_combat_triggered() (FEAT-316): see that method's own
	# doc for why. ──────────────────────────────────────────────────────────
	_verb_registry = _build_verb_registry()

	# ── FEAT-005 (US-005; FR-004/FR-013; NFR-002/NFR-003; ADR-002): minimal
	# composition-root wiring for MultiPhaseTargetingController -- this
	# feature's OWN scope is the standalone N-length sequential targeting
	# loop itself (proven in isolation, with injected fakes, by
	# tests/unit/application/combine/test_multi_phase_targeting_controller.gd
	# -- see that file's own doc), so this wiring purposefully stays
	# minimal: a real MultiPhaseTargetingController instance, backed by a
	# verb_id -> controller registry resolved through THIS SAME
	# `_controller(verb_id)` lookup every other verb already resolves
	# through (no second/forked controller-resolution path, ADR-002's
	# "verb_id whitelisting" security note), and the real Iteration O
	# CombineActionController (core/controllers/combine_action_controller.gd,
	# FEAT-004's DEF-001 gate) as its `combine_action_controller`
	# collaborator. Hooking this instance up to a live selection_resolved
	# signal flow -- so a real Combine's queued sub-actions are actually
	# driven through it end-to-end -- is explicitly a LATER feature (US-006)
	# layered on top of this same seam; this composition root neither
	# invokes nor connects it to anything yet. ──────────────────────────────
	# FEAT-297 (resolves DEF-NEW-002): `controller_for` wires the REAL
	# sub-action dispatch this feature merges into
	# core/controllers/combine_action_controller.gd's own execute() —
	# `Callable(self, "_controller")` is the EXACT SAME `_controller(verb_id)`
	# table lookup every other verb (including STRIDE/STRIKE's own real,
	# live presentation controllers) is resolved through below, never a
	# second/forked resolution path. This is what lets the controller
	# instance actually invoked by the live signal chain
	# (`multi_phase_targeting_controller`, wired just below) perform real
	# movement + Strike resolution, not just validate-then-charge.
	# FEAT-298 (resolves DEF-NEW-003): `action_economy_port` wires a real
	# ActionEconomyPort adapter (`GdCombineActionEconomyPortClass`, FEAT-002:
	# presentation/adapters/gd_combine_action_economy_port.gd) so
	# `_core_combine_action_controller`'s own `_charge_action_economy()`
	# (core/controllers/combine_action_controller.gd) actually charges the
	# documented 1-action cost (FR-007) alongside the 1-Stamina cost it
	# already charged, rather than silently skipping the action charge
	# because `_action_economy_port` was null (DEF-NEW-003). The adapter
	# resolves the CURRENT actor's live ActionEconomy lazily, on every
	# spend_action() call, via `_verb_bar_current_action_economy()` — the
	# SAME `round_session.current_action_economy()` read every other verb's
	# own availability gate already uses — rather than capturing a single
	# ActionEconomy instance up front, so it stays correct across
	# `rewire_session()`/round-boundary ActionEconomy instance swaps.
	_core_combine_action_controller = CoreCombineActionControllerClass.new({
		"verb_registry_port": GdVerbRegistryPortClass.new(),
		"action_economy_port": GdCombineActionEconomyPortClass.new(self),
		"controller_for": Callable(self, "_controller"),
	})
	# FEAT-007 (US-007; NFR-001): built as its own named field
	# (`_combine_controller_registry`) rather than an inline anonymous dict
	# literal, so `combine_targeting_session` below (FEAT-005, US-004) can
	# reuse the EXACT SAME verb_id -> VerbControllerPort instances
	# `multi_phase_targeting_controller` is constructed with — one registry,
	# resolved once, never a second/forked lookup (ADR-002's "verb_id
	# whitelisting" security note).
	_combine_controller_registry = {
		"STRIDE": CoreStrideActionControllerClass.new({
			"other_combatants_fn": func(): return _party + _enemies,
		}),
		"STRIKE": CoreStrikeActionControllerClass.new({
			"candidate_targets_fn": Callable(self, "_living_enemy_reactors"),
		}),
		"CAST_SPELL": CoreCastSpellAdapterClass.new({
			"get_ctrl_fn": func(): return _controller("CAST_SPELL"),
		}),
	}
	multi_phase_targeting_controller = MultiPhaseTargetingControllerClass.new({
		"controller_registry": _combine_controller_registry,
		"combine_action_controller": _core_combine_action_controller,
	})
	# FEAT-004 (US-003; FR-003; ADR-005): the extracted interactive Combine
	# QUEUE-BUILD pick-loop state machine (presentation/
	# combine_queue_build_session.gd) -- constructed and wired here, driven
	# purely through its own start(actor)/abort() surface plus its
	# queue_built(queue)/aborted() signals from this point on (see
	# `_on_combine_queue_built()`'s own doc below). Owns the
	# CombineBuildRegistryProxy adapter (FEAT-002) internally -- this
	# composition root no longer constructs one itself.
	combine_queue_build_session = CombineQueueBuildSessionClass.new()
	combine_queue_build_session.setup({
		"combine_action_controller": _core_combine_action_controller,
		"selection_overlay": selection_overlay,
		"hex_grid_view": hex_grid_view,
		"verb_registry": _verb_registry,
		# FEAT-008 (US-007 / FR-002): these Callables now point at the
		# extracted SpellPickerPanelController's own show(options, on_selected)/
		# hide() methods (formerly this file's own private
		# _show_spell_picker()/_hide_spell_picker() wrapper methods).
		# show_spell_picker_fn is invoked here as `.call(options)` (see
		# combine_queue_build_session.gd's own call site) -- `.bind(...)`
		# appends the pre-bound on_selected Callable AFTER that call-time
		# `options` argument, so the actual invocation is
		# `_spell_picker.show(options, on_selected)`, matching
		# SpellPickerPanelController's public signature exactly.
		"show_spell_picker_fn": Callable(_spell_picker, "show").bind(Callable(selection_overlay, "choose_option")),
		"hide_spell_picker_fn": Callable(_spell_picker, "hide"),
	})
	combine_queue_build_session.queue_built.connect(_on_combine_queue_built)

	# FEAT-005 (US-004; FR-004; ADR-003): the extracted interactive Combine
	# sub-action TARGETING pick-loop state machine (presentation/
	# combine_targeting_session.gd) -- constructed and wired here, driven
	# purely through its own start(queue_entries, actor, context,
	# combine_queue)/abort()/try_advance(verb_id) surface plus its
	# targeting_complete(result)/aborted() signals from this point on (see
	# `_on_combine_targeting_complete()`'s own doc below). Wraps
	# `multi_phase_targeting_controller` (UNCHANGED, RISK-002) and reuses the
	# EXACT SAME `_combine_controller_registry` above via composition only --
	# this composition root no longer owns the interactive per-phase loop's
	# own state or algorithm directly. Owns the CombineTargetingRegistryProxy
	# adapter (FEAT-002) internally, mirroring `combine_queue_build_session`
	# immediately above's own "thin, self-only proxy" pattern one phase
	# earlier.
	combine_targeting_session = CombineTargetingSessionClass.new()
	combine_targeting_session.setup({
		"controller_registry": _combine_controller_registry,
		"targeting_controller": multi_phase_targeting_controller,
		"selection_overlay": selection_overlay,
		"hex_grid_view": hex_grid_view,
		"verb_registry": _verb_registry,
		# FEAT-008 (US-007 / FR-002): see the identical comment on
		# combine_queue_build_session.setup()'s own "show_spell_picker_fn" key
		# immediately above for why `.bind(...)` here yields the exact
		# `_spell_picker.show(options, on_selected)` call this session's own
		# `.call(options)` call site expects.
		"show_spell_picker_fn": Callable(_spell_picker, "show").bind(Callable(selection_overlay, "choose_option")),
	})
	combine_targeting_session.targeting_complete.connect(_on_combine_targeting_complete)

	# ── FEAT-006 (US-006 / FR-007): construct/wire the extracted
	# RoundFlowController (presentation/round_flow_controller.gd) against the
	# SAME `run_round_use_case` and `_party`/`_enemies` (CombatSessionFactory.
	# build()'s own output, FEAT-003) this composition root already drives —
	# see round_flow_controller.gd's own file-level doc for why this
	# composition root's PRE-EXISTING `rewire_session()`/`_on_round_over()`
	# pair (below) remains the sole live driver of the real encounter's
	# round-flow (never this controller's own rewire_session(), which would
	# otherwise call RunRoundUseCase.begin_round() a second, parallel time
	# per round). Deliberately OMITS the "turn_controller" deps key -- setup()
	# would otherwise connect its own internal handler to
	# turn_controller.round_over immediately, regressing the pinned FEAT-316/
	# DEF-001 acceptance criterion that turn_controller.round_over must have
	# ZERO connections at boot (tests/boot/test_combat_pipeline_gated_by_game_mode.gd).
	# Connected to round_flow_controller's own round_over() signal for UI
	# cleanup ONLY (_on_round_flow_controller_round_over() below) -- no
	# game-state mutation. This file's OWN _on_round_over() (below) calls
	# round_flow_controller.notify_round_concluded() at the very end of its
	# existing work, so round_over() still fires for real, live round
	# conclusions -- see that method's own doc. ─────────────────────────────
	round_flow_controller.setup({
		"run_round_use_case": run_round_use_case,
		"end_turn_control": end_turn_control,
		"verb_bar_view": verb_bar_view,
		"party_fn": Callable(self, "_current_party"),
		"enemies_fn": Callable(self, "_current_enemies"),
		"round_number": ROUND_NUMBER,
	})
	round_flow_controller.round_over.connect(_on_round_flow_controller_round_over)

	# ── FEAT-008 / US-008 (FR-003, ADR-002): wire the generic Layer 2
	# SelectionOverlay (presentation/selection_overlay.gd) over the SAME
	# `_verb_registry` and `hex_grid_view` this composition root already
	# built/wires above -- no new port, no forked resolution logic. This is
	# the SAME hex_grid_view.hex_clicked signal FEAT-007's doc (immediately
	# below, historically) noted "a future Layer 2 SelectionOverlay may
	# subscribe to it" -- this is that subscriber, connected generically to
	# EVERY non-END_TURN verb's Layer 2 entry (VerbBarView.verb_selection_entered)
	# rather than special-cased to STRIKE, mirroring VerbBarView's/
	# verb_registry.py's own verb-agnostic dispatch discipline.
	# FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001):
	# `selection_overlay.configure(_verb_registry, hex_grid_view)` itself --
	# the call that actually arms Layer 2 targeting -- used to happen HERE,
	# unconditionally, on every boot. It is now deferred to
	# _on_combat_triggered() below (see that method's own doc), so
	# SelectionOverlay stays unconfigured/inert throughout EXPLORATION mode.
	# The signal wiring immediately below is left in place -- it is harmless
	# with an unconfigured overlay (verb_selection_entered can only fire once
	# $VerbBarView has rendered buttons, which itself only happens once
	# _on_combat_triggered() calls verb_bar_view.configure()). ──────────────
	if verb_bar_view != null:
		verb_bar_view.verb_selection_entered.connect(_on_verb_bar_selection_entered)
	selection_overlay.selection_resolved.connect(_on_selection_overlay_resolved)

	# FEAT-008 (US-007 / FR-002): this composition root still creates/
	# add_child()s the "SpellPickerPanel" Panel node itself (scene-tree
	# wiring stays here -- see tests/infrastructure/
	# test_presentation_stack_wiring.gd's own "SpellPickerPanel" child-node
	# invariant, unaffected by this extraction) then hands it to
	# `_spell_picker.setup(panel_node)`, which owns everything else (the
	# "SpellList" VBoxContainer child + every populate/show/hide concern --
	# see presentation/spell_picker_panel_controller.gd's own file-level
	# doc). UNCHANGED node shape/anchors from the pre-extraction
	# `_setup_spell_picker_panel()`.
	var spell_picker_panel := Panel.new()
	spell_picker_panel.name = "SpellPickerPanel"
	spell_picker_panel.visible = false
	spell_picker_panel.custom_minimum_size = Vector2(220, 40)
	spell_picker_panel.anchor_left = 0.5
	spell_picker_panel.anchor_right = 0.5
	spell_picker_panel.anchor_top = 1.0
	spell_picker_panel.anchor_bottom = 1.0
	spell_picker_panel.offset_left = -110
	spell_picker_panel.offset_right = 110
	spell_picker_panel.offset_top = -220
	spell_picker_panel.offset_bottom = -100
	add_child(spell_picker_panel)
	_spell_picker.setup(spell_picker_panel)
	selection_overlay.selection_cancelled.connect(func(_v): _spell_picker.hide())

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

	# FEAT-316 (resolves DEF-001/PR-001): round_session is no longer
	# guaranteed non-null here -- it stays null throughout EXPLORATION mode
	# until a real combat trigger's _on_combat_triggered() calls
	# rewire_session() (see that method's own FEAT-316 doc) -- so this
	# observability line must not unconditionally dereference it.
	if round_session != null:
		print(
			"INFO: Hykaen MainScene booted into the prologue encounter (interactive) -- "
			+ "current_actor=" + (round_session.current_actor().name if round_session.current_actor() != null else "")
			+ " round_over=" + str(round_session.is_round_over())
		)
	else:
		print("INFO: Hykaen MainScene booted into EXPLORATION mode -- no active round_session yet (FEAT-316)")

	# ── FEAT-002 / US-002 (observability, per design notes): surface the
	# resolved centering_offset once at boot so any future transform-drift
	# regression (a token/grid rendering at the wrong screen position) is
	# immediately visible in headless-boot logs, mirroring the ADR-003
	# rationale already established for `resolved_seed`. ───────────────────
	print("DEBUG: viewport_centering centering_offset=" + str(centering_offset))


## _boot_exploration_mode(hex_combatants) -> void — FEAT-006 (US-005 / FR-004,
## RISK-001).
##
## Constructs this composition root's EXPLORATION-mode state:
##   - `_game_mode` is (re)confirmed as GameMode.EXPLORATION (already its
##     field default -- restated here for clarity/observability).
##   - `scenario_session` is a fresh ScenarioSession (FEAT-003) with its
##     `.scenario` set from PROLOGUE_SCENARIO_PATH, and
##     `.party_hex_positions` seeded combatant_id -> HexCoord for every party
##     member (the scenario's own PartyResource.character_resource_paths
##     count, ADR-002 -- the SAME party-authority convention
##     LoadScenarioEncounterUseCase already establishes) from `hex_combatants`
##     (already loaded by _ready() above from PROLOGUE_ENCOUNTER_PATH -- the
##     exact resource the scenario's sole entry wraps, so no second/forked
##     load).
##   - `exploration_controller` is a fresh ExplorationController (FEAT-005)
##     wrapping `scenario_session`, with its `combat_triggered` signal wired
##     to `_on_combat_triggered()` below -- a STUB at this stage; the real
##     trigger-driven combat handoff is a LATER feature's scope.
##   - `hex_grid_view.hex_clicked` is wired to `_on_exploration_hex_clicked()`
##     below -- also a STUB at this stage (interactive exploration movement
##     is a LATER feature's scope). This is purely additive: `hex_clicked`
##     already has an independent subscriber (presentation/selection_overlay.gd's
##     own `_on_hex_clicked()`, wired via `selection_overlay.configure()`
##     elsewhere in _ready()) -- both fire independently on every click, and
##     neither depends on the other.
##
## A missing/malformed scenario resource push_error()s and leaves
## `scenario_session.scenario` null (ScenarioSession's own documented
## null-scenario contract already fails closed/open appropriately at every
## call site -- see that file's doc) rather than aborting boot: EXPLORATION
## mode still exists in a degenerate (no scenario) state instead of crashing.
func _boot_exploration_mode(hex_combatants: Array) -> void:
	_game_mode = GameMode.EXPLORATION
	scenario_session = ScenarioSessionClass.new()

	var scenario_resource = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	if scenario_resource == null:
		push_error("MainScene: failed to load " + PROLOGUE_SCENARIO_PATH)
	else:
		scenario_session.scenario = scenario_resource
		var party_count: int = 0
		if scenario_resource.party != null:
			party_count = scenario_resource.party.character_resource_paths.size()
		for i in range(min(party_count, hex_combatants.size())):
			var party_hex_combatant = hex_combatants[i]
			scenario_session.party_hex_positions[party_hex_combatant.combatant_id] = party_hex_combatant.hex_coord

	exploration_controller = ExplorationControllerClass.new(scenario_session)
	exploration_controller.combat_triggered.connect(_on_combat_triggered)

	if hex_grid_view != null:
		hex_grid_view.hex_clicked.connect(_on_exploration_hex_clicked)


## _on_combat_triggered(encounter_id) -> void — FEAT-008 (US-007 / FR-006):
## the real exploration-to-combat handoff. `exploration_controller.
## combat_triggered` (emitted from ExplorationController._evaluate_triggers()
## when a party move enters a proximity trigger's hexes, FEAT-005/FEAT-006)
## reaches this handler, which drives the full handoff in the ordered steps
## design notes' api_contracts #2 documents:
##
##   1. Disconnect `hex_grid_view.hex_clicked` from
##      `_on_exploration_hex_clicked` FIRST, before any of the multi-step
##      work below begins (the signal-contract's own guard against a second
##      click racing the handoff -- see this feature's own boot-real
##      "disconnected before the handoff's multi-step work begins" test).
##   2 + 3. Resolve `encounter_id` against `scenario_session.scenario`'s
##      ScenarioEncounterEntryResource entries and assemble live party/enemy
##      Combatants via the SAME `load_encounter_from_scenario()` additive
##      hook FEAT-010 already established (itself a thin wrapper around
##      LoadScenarioEncounterUseCase.execute(), ADR-006 -- no second/forked
##      assembly path). On failure (ok=false), `load_encounter_from_scenario()`
##      has already push_error()'d the failure reason; this handler aborts
##      the handoff WITHOUT mutating `_game_mode`/`_active_encounter_id` at
##      all (atomic-failure contract) and re-connects hex-click handling so
##      exploration continues uninterrupted.
##   4. On success, commit the mode switch: `_game_mode = GameMode.COMBAT`
##      and `_active_encounter_id = encounter_id` -- only ever mutated
##      together, only ever after assembly has already succeeded.
##   5. Place enemy tokens on the SAME, unreset `hex_grid_view` instance via
##      `add_combatants()` (presentation/hex_grid_view.gd) -- which, unlike
##      `load_combatants()`, never clears pre-existing tokens, so the party
##      tokens already rendered at their exploration positions are left
##      completely untouched (ADR-001).
##   6 + 7. Roll initiative for the freshly-assembled `encounter` (built by
##      `load_encounter_from_scenario()` above) and stand up the full combat
##      pipeline via the SAME `rewire_session()` / TurnController wiring
##      `_ready()` already uses. `rewire_session()` itself is the only place
##      that calls RunRoundUseCase's begin_round entry point, on whichever
##      RunRoundUseCase instance was constructed at boot -- and that instance's injected
##      TurnOrderPort (infrastructure/encounter_turn_order_adapter.gd) holds
##      a captured reference to the ORIGINAL, boot-time `encounter` object,
##      not the fresh one `load_encounter_from_scenario()` just built. This
##      handler therefore rebuilds `run_round_use_case` around a fresh
##      TurnOrderPort/AIDecisionPort bound to the CURRENT `encounter` --
##      mirroring _ready()'s own construction verbatim (ADR-006, no second/
##      forked wiring shape) -- before awaiting `rewire_session()`, so
##      initiative is rolled from the SAME live Combatants this handoff just
##      assembled, not a stale boot-time roster.
##
## Known deviation (accepted for this steel thread, flagged as an extension
## point rather than fixed here): `round_history_port`/`resolve_action_use_case`
## are reused verbatim from `_ready()` rather than also rebuilt, so any round
## history recorded by the pre-existing hardcoded boot pipeline (which stands
## up its own RunRoundUseCase/RoundSession unconditionally in `_ready()`,
## independent of `_game_mode`) remains visible alongside this handoff's own
## history entries.
func _on_combat_triggered(encounter_id: String) -> void:
	if hex_grid_view != null and hex_grid_view.hex_clicked.is_connected(_on_exploration_hex_clicked):
		hex_grid_view.hex_clicked.disconnect(_on_exploration_hex_clicked)

	var scenario = scenario_session.scenario if scenario_session != null else null
	var ok: bool = load_encounter_from_scenario(scenario, encounter_id)
	if not ok:
		# load_encounter_from_scenario() has already push_error()'d the
		# failure reason (FEAT-010's established contract). Atomic-failure
		# contract: abort WITHOUT mutating _game_mode/_active_encounter_id,
		# and restore exploration's click-to-move handling.
		if hex_grid_view != null and not hex_grid_view.hex_clicked.is_connected(_on_exploration_hex_clicked):
			hex_grid_view.hex_clicked.connect(_on_exploration_hex_clicked)
		return

	_game_mode = GameMode.COMBAT
	_active_encounter_id = encounter_id

	if hex_grid_view != null:
		hex_grid_view.add_combatants(_enemies)

	# ── FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): the
	# turn_controller.active_actor_changed/round_over subscriptions used to be
	# established unconditionally in _ready() (see that method's own FEAT-316
	# doc), regardless of `_game_mode` -- the peer-review blocking finding
	# this feature resolves. They are now established HERE instead, the
	# instant a real combat trigger commits the mode switch above, so they
	# stay disconnected for the entire EXPLORATION-mode lifetime of a fresh
	# boot. Mirrors _on_combat_won()'s established disconnect-then-reconnect
	# idiom (below) so a later _on_combat_triggered() call -- entering a
	# SECOND encounter after _on_combat_won() already reconnected these very
	# signals for the return trip -- can never leave a duplicate/dangling
	# listener behind either. ────────────────────────────────────────────────
	if turn_controller != null:
		if turn_controller.active_actor_changed.is_connected(_on_active_actor_changed):
			turn_controller.active_actor_changed.disconnect(_on_active_actor_changed)
		turn_controller.active_actor_changed.connect(_on_active_actor_changed)

		if turn_controller.round_over.is_connected(_on_round_over):
			turn_controller.round_over.disconnect(_on_round_over)
		turn_controller.round_over.connect(_on_round_over)

	# ── Rebuild run_round_use_case's TurnOrderPort/AIDecisionPort around the
	# FRESH `encounter` load_encounter_from_scenario() just built above --
	# see this method's own doc for why rewire_session() alone is not enough.
	var turn_order_port = EncounterTurnOrderAdapterClass.new(encounter)
	var ai_decision_port = AIClass.new()
	ai_decision_port.set_stride_reaction_resolver_fn(Callable(self, "_resolve_enemy_stride_opportunistic_window"))
	run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	ROUND_NUMBER = 1
	await rewire_session()

	# ── FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): activate
	# the Layer 1 verb bar / Layer 2 selection overlay ONLY now that combat is
	# genuinely live -- these two configure() calls used to run
	# unconditionally in _ready() (see that method's own FEAT-316 doc),
	# meaning the "combat UI" was always armed even during EXPLORATION. Both
	# configure() calls are documented safe to call repeatedly (verb_bar_view.gd
	# FEAT-177 doc; selection_overlay.gd's own doc), so a later encounter after
	# a post-combat return to EXPLORATION reconfigures cleanly, with no stale
	# button/highlight state leaking across encounters. ─────────────────────
	if verb_bar_view != null:
		verb_bar_view.configure(_verb_registry)
	selection_overlay.configure(_verb_registry, hex_grid_view)


## _on_exploration_hex_clicked(hex_coord) -> void — FEAT-007 (US-006 / FR-005).
##
## Click-to-move the selected party member (_party[0], Titus) on the hex
## map while in EXPLORATION mode. Guard contract (design notes'
## api_contracts #5, verified directly by this feature's boot-real spy
## test): a no-op, WITHOUT ever touching `exploration_controller`, whenever
## `_game_mode != GameMode.EXPLORATION` -- this is the boundary that keeps
## combat-mode clicks from reaching ExplorationController at all.
##
## In EXPLORATION mode: forwards to
## `exploration_controller.move_party_member(combatant_id, hex_coord)` for
## `_party[0]`'s combatant_id. ExplorationController's own contract
## (core/application/exploration_controller.gd) is fail-closed -- an
## unknown combatant_id or a non-adjacent `hex_coord` returns `false` with
## NO mutation of `scenario_session.party_hex_positions` -- so on `false`
## this handler does nothing further: a silent no-op, no push_error, no
## visual change (matches FEAT-005's fail-closed contract; illegal moves
## are UX, not a developer-facing error per design notes' error_handling
## #2). On `true`, the move already succeeded in the session, so this
## handler repositions the ALREADY-rendered token via the existing
## `hex_grid_view.move_token()` reposition API (FEAT-013/US-013, the SAME
## hook the Step/Stride combat path and AI-Stride reposition already use --
## no second/parallel token-drawing path).
func _on_exploration_hex_clicked(hex_coord) -> void:
	if _game_mode != GameMode.EXPLORATION:
		return

	if _party.is_empty() or exploration_controller == null:
		return

	var combatant_id: String = _party[0].combatant_id
	var moved: bool = exploration_controller.move_party_member(combatant_id, hex_coord)
	if moved and hex_grid_view != null:
		hex_grid_view.move_token(combatant_id, hex_coord)


## load_encounter_from_scenario(scenario, encounter_id) -> bool — FEAT-010
## (US-009 / FR-008, NFR-001; ADR-005/RISK-004 mitigation).
##
## The new, strictly ADDITIVE public entry point that drives
## LoadScenarioEncounterUseCase (core/application/use_cases/
## load_scenario_encounter_use_case.gd, FEAT-008/FEAT-009) for a caller that
## already holds an in-memory ScenarioResource (e.g. a future menu/
## scenario-select flow) — a parallel, coexisting code path alongside this
## file's existing hardcoded _ready()/PROLOGUE_ENCOUNTER_PATH boot logic
## (strangler-fig coexistence, design notes' architecture section). Per
## RISK-004, _ready() above is completely UNTOUCHED by this feature — it is
## never called from within _ready(), and _ready()'s own regression suite
## (tests/unit/test_main_scene_entry_point.gd,
## tests/unit/test_main_scene_interactive_wiring.gd) is a blocking
## pre-check proving this diff introduced zero edits to that method.
##
## On success (result.ok == true): lifts the use case's
## party_combatants/enemy_combatants Dictionaries onto live Combatant
## instances via CombatantClass.from_dict() — mirroring EXACTLY how
## _ready() above lifts _build_party_combatant()/_build_enemy_combatant()'s
## own Dictionaries — assigns them into this composition root's `_party`/
## `_enemies` fields (the SAME fields _ready() populates), constructs and
## initialize()s a fresh EncounterClass around them with the SAME
## EncounterClass.new()/initialize() call _ready() makes (reused verbatim,
## ADR-006 — no second/forked encounter-construction path), and returns
## true.
##
## On failure (result.ok == false): push_error()s the use case's
## error_code and returns false WITHOUT mutating `_party`/`_enemies`/
## `encounter` at all — a caller may safely retry or fall back to the
## legacy _ready() path (design notes' api_contracts section; this
## feature's own "no partial mutation on failure" test_criterion).
func load_encounter_from_scenario(scenario, encounter_id: String) -> bool:
	var use_case := LoadScenarioEncounterUseCaseClass.new()
	var result: Dictionary = use_case.execute(scenario, encounter_id)

	if not result.get("ok", false):
		push_error(
			"MainScene.load_encounter_from_scenario: failed to load encounter_id '%s' (%s)"
			% [encounter_id, result.get("error_code", "UNKNOWN_ERROR")]
		)
		return false

	var new_party: Array = []
	for party_combatant_dict in result.get("party_combatants", []):
		new_party.append(CombatantClass.from_dict(party_combatant_dict))

	var new_enemies: Array = []
	for enemy_combatant_dict in result.get("enemy_combatants", []):
		new_enemies.append(CombatantClass.from_dict(enemy_combatant_dict))

	_party = new_party
	_enemies = new_enemies

	var rng := RNGClass.new(resolved_seed)
	encounter = EncounterClass.new(_party, _enemies, rng)
	encounter.initialize()

	return true


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
func _build_verb_registry() -> VerbBarRegistryAdapterClass:
	var registry := VerbBarRegistryAdapterClass.new()

	# Data-driven (2026-07-11): loop VERB_TABLE rather than four hand-written
	# register() blocks. Each verb wires the three thin _verb_bar_<verb>_* shim
	# Callables tests call on `self` — "END_TURN".to_lower() == "end_turn" matches
	# the shim names. Adding a VERB_TABLE entry auto-registers its verb here.
	for verb_id in VERB_TABLE:
		var suffix: String = verb_id.to_lower()
		registry.register(
			verb_id,
			Callable(self, "_verb_bar_%s_availability" % suffix),
			Callable(self, "_verb_bar_%s_enter_selection" % suffix),
			Callable(self, "_verb_bar_%s_execute" % suffix),
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
	return _controller("STRIKE").availability()


func _verb_bar_strike_enter_selection() -> Dictionary:
	return _controller("STRIKE").enter_selection()


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
	return await _controller("STRIKE").execute(selection)


## _resolve_enemy_dodge_step(target, resolve_result, attacker_hex, legal_hexes)
## -> void — thin shim to ReactionController.resolve_enemy_dodge_step()
## (presentation/reaction_controller.gd), restored per that file's own
## documented contract ("MainScene keeps thin _resolve_*/… shims that
## delegate here, so … the direct-call tests all keep working unchanged").
## presentation/strike_action_controller.gd's execute() already calls
## `_reaction.resolve_enemy_dodge_step()` directly for the live
## player-Strikes-enemy call path (ADR-002 — no duplicated resolution logic
## here, this is pure delegation); this shim exists solely so tests/other
## callers can drive the SAME seam via `instance._resolve_enemy_dodge_step()`
## on the composition root, exactly like `_resolve_enemy_stride_opportunistic_
## window()` below does for its own ReactionController method.
func _resolve_enemy_dodge_step(target, resolve_result: Dictionary, attacker_hex, legal_hexes: Array) -> void:
	await _reaction().resolve_enemy_dodge_step(target, resolve_result, attacker_hex, legal_hexes)


## _strike_reachable_target_ids() -> Array - thin shim to StrikeActionController
## (kept because tests call it directly). strike_execute + the targeting helpers
## (_strike_reachable_targets/_strike_actor_is_ranged/_strike_target_id/
## _find_strike_reachable_target) moved into
## presentation/strike_action_controller.gd.
func _strike_reachable_target_ids() -> Array:
	return _controller("STRIKE").reachable_target_ids()


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
func _action_economy_for(combatant):
	if encounter == null:
		return null

	var order: Array = encounter.get_turn_order()
	for i in range(order.size()):
		if is_same(order[i], combatant):
			return encounter.get_action_economy(i)

	var combatant_id: String = combatant.display_id()
	if combatant_id != "":
		for i in range(order.size()):
			var candidate = order[i]
			if candidate.display_id() == combatant_id:
				return encounter.get_action_economy(i)

	return null


## _is_reactor_reaction_spent(reactor) -> bool — iteration K FEAT-006
## (US-006): the `reactor_spent_fn` Callable core/application/use_cases/
## resolve_stride_use_case.gd's ResolveStrideUseCase awaits per candidate
## reactor, backed by the SAME live ActionEconomy lookup
## (_action_economy_for()) every other reaction seam in this file already
## uses. Defaults to "not spent" when no tracked ActionEconomy exists (a
## fixture/test-double reactor), mirroring _action_economy_for()'s own
## documented "reaction untracked" degrade-safely contract.
func _is_reactor_reaction_spent(reactor) -> bool:
	return _reaction().is_reactor_reaction_spent(reactor)


## _resolve_enemy_stride_opportunistic_window(mover, mover_start_hex,
## candidate_reactors) -> Dictionary — iteration K FEAT-006 (US-006, ADR-004):
## the Callable core/combat/ai.gd's `_stride_reaction_resolver_fn` seam awaits
## for the ENEMY-mover Stride path (a Skeleton Striding toward Titus) —
## injected onto `ai_decision_port` in _ready() above. Drives
## ResolveStrideUseCaseClass.execute() with this composition root's own
## per-reactor spent/resolver Callables, routing the PLAYER reactor (the only
## hostile candidate an enemy mover can ever have in this steel thread) to
## _resolve_player_opportunistic_strike_reaction() below — the real,
## awaited turn_controller.resolve_reaction() pop-up — BEFORE core/combat/
## ai.gd's own Movement.stride() call (immediately following this seam,
## still inside the SAME decide_action() call) ever mutates `mover`'s
## hex_coord.
##
## iteration K FEAT-008 (US-008): now wires `resolve_action_use_case`/
## `_action_economy_for` through as ResolveStrideUseCase.execute()'s
## `strike_use_case`/`reactor_action_economy_fn` (previously omitted
## entirely — an "opportunistic_strike" choice on this path resolved NO
## effect at all in live play, despite core/application/use_cases/
## resolve_stride_use_case.gd's own FEAT-007 effect-resolution machinery —
## see that file's own FEAT-008 doc), and now returns the use case's own
## result Dictionary (`-> void` previously) so core/combat/ai.gd's
## `_stride_toward_target()` can read `"mover_downed"` and cancel the Stride
## when a lethal opportunistic Strike defeats `mover`.
func _resolve_enemy_stride_opportunistic_window(mover, mover_start_hex, candidate_reactors: Array) -> Dictionary:
	return await _reaction().resolve_enemy_stride_opportunistic_window(mover, mover_start_hex, candidate_reactors)


## _resolve_player_opportunistic_strike_reaction(reactor, context) ->
## Dictionary — iteration K FEAT-006 (US-006): the player-reactor half of
## this feature's required routing ("reactor=player -> the real
## turn_controller.resolve_reaction pop-up"). Delegates to
## turn_controller.resolve_opportunistic_strike_reaction() (iteration K
## FEAT-008 — see that method's own doc for the "OpportunisticStrike"
## ReactionTrigger shape it builds internally) — the SAME live integration
## point the enemy-Strikes-player path already awaits via this composition
## root's own `reaction_window`/`player_reaction_chooser` (wired in
## _ready()), so a genuinely blocking pop-up decides whether the player
## takes the opportunistic strike, BEFORE the enemy mover's Stride below
## ever commits a position change. Degrades safely to Pass
## ({"choice": "none"}) when `turn_controller` is unwired (never
## crashes/hangs).
func _resolve_player_opportunistic_strike_reaction(reactor, context: Dictionary) -> Dictionary:
	return await _reaction().resolve_player_opportunistic_strike_reaction(reactor, context)


## _resolve_enemy_opportunistic_strike_reaction(reactor, context) ->
## Dictionary — iteration K FEAT-006 (US-006): the enemy-reactor half of this
## feature's required routing ("reactor=enemy -> ai_reaction_policy
## synchronously") — consulted by _verb_bar_stride_execute() below for the
## PLAYER-mover Stride path (Titus Striding, a Skeleton reacting).
## Synchronous end to end (OpenReactionWindowUseCase.open() never `await`s,
## and `enemy_reaction_chooser` — infrastructure/ai_reaction_policy.gd's
## AIReactionPolicy — never suspends either), so NO pop-up/UI ever opens for
## the enemy's own reaction decision here (mirrors
## _verb_bar_strike_execute()'s identical iteration-K "no pop-up UI opens
## during the enemy's reaction window" contract for Strikes).
func _resolve_enemy_opportunistic_strike_reaction(reactor, context: Dictionary) -> Dictionary:
	return _reaction().resolve_enemy_opportunistic_strike_reaction(reactor, context)


## _verb_bar_step_availability() -> bool -- FEAT-002 (US-002 / FR-003 /
## FR-004; Iteration F P0-1): additionally queries the active actor's live
## ActionEconomy.can_take_movement_action() (core/rules/action_economy.gd,
## read-only, ADR-003) -- STEP is unavailable once EITHER Step or Stride has
## already been taken this turn (the SAME Movement-trait gate FEAT-001 wired
## into core/rules/movement.gd), in addition to the pre-existing "at least
## one legal Step destination" check. This function only READS
## can_take_movement_action(); it never mutates the domain gate itself.
func _verb_bar_step_availability() -> bool:
	return _controller("STEP").availability()


func _verb_bar_step_enter_selection() -> Dictionary:
	return _controller("STEP").enter_selection()


## _verb_bar_step_execute(selection) -> Dictionary — FEAT-007 (this
## iteration's US-007/FR-010): `selection` is the Layer-2-picked destination
## HexCoord (see _verb_bar_step_enter_selection()'s candidate_hexes). Forwards
## directly to the injected, REUSED movement_input_controller.step_to() (ADR-
## 002: no duplicate movement path -- this is now the SOLE Step entry point,
## replacing the deleted hex_grid_view.hex_clicked auto-resolve handler). On
## success, runs the SAME post-move refresh
## (_after_successful_move()) that handler used to run.
func _verb_bar_step_execute(selection) -> Dictionary:
	return _controller("STEP").execute(selection)


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
	return _controller("STRIDE").availability()


func _verb_bar_stride_enter_selection() -> Dictionary:
	return _controller("STRIDE").enter_selection()


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
## iteration K FEAT-006 (US-006, ADR-004): BEFORE forwarding to
## movement_input_controller.stride_to() (this method's pre-existing sole
## commit point for the player's Stride), this now opens an
## OpportunisticStrike reaction window for every hostile (enemy) reactor
## eligible per core/domain/opportunistic_strike_eligibility.gd — routed
## synchronously through _resolve_enemy_opportunistic_strike_reaction()
## (ai_reaction_policy, no pop-up) — so the enemy's reaction is fully
## resolved before Titus's position ever changes, mirroring this feature's
## identical guarantee on the enemy-mover path (core/combat/ai.gd). A no-op
## when round_session/current_actor carries no hex_coord (e.g. a test double
## that never populates positional data) — the pre-existing Stride contract
## is otherwise completely unaffected.
##
## iteration K FEAT-008 (US-008): now wires `resolve_action_use_case`/
## `_action_economy_for` through as ResolveStrideUseCase.execute()'s
## `strike_use_case`/`reactor_action_economy_fn` (previously omitted
## entirely — see _resolve_enemy_stride_opportunistic_window()'s own
## FEAT-008 doc for the identical enemy-mover-path gap this closes), and now
## reads the returned Dictionary's `"stride_should_commit"` — when false (a
## lethal Opportunistic Strike defeated Titus before his Stride could ever
## commit), movement_input_controller.stride_to() is NEVER called: Titus
## remains at his start hex (no hex_coord mutation occurs), and this method
## returns a rejected result carrying ERR_MOVER_DOWNED_BY_OPPORTUNISTIC_STRIKE
## rather than the movement controller's own ok/resolved shape.
##
## FEAT-228 (resolves FIND-224 / FR-007): `_living_combatants(_enemies)`
## yields candidates in ENCOUNTER SPAWN ORDER (`_enemies`'s own array order,
## fixed at boot before `encounter.initialize()` ever rolls initiative) --
## NOT the rolled-initiative order this feature's ADR on deterministic-replay
## ordering requires ResolveStrideUseCase.execute() to receive (that use
## case's own doc explicitly states it "resolves reactors strictly in the
## order given, never re-sorting them itself" -- the caller, this method, is
## the sole party responsible for supplying initiative order). This method
## now runs that living-enemy pool through _order_candidate_reactors_by_initiative()
## (sorted by each combatant's own "_initiative_roll", stamped by
## `encounter.initialize()` before this method is ever reachable) before
## handing it to the use case, and additionally runs the SORTED result
## through _assert_candidate_reactors_ordering() -- a defensive, fail-loud
## check (mirrors core/application/reaction_window.gd's
## assert_reaction_budget_delta() convention: assert()+push_error(), plus a
## bool return so a GUT test can observe the violation directly, since this
## project's Godot 4.3 engine cannot capture assert()/push_error() output
## from GUT) confirming the sorted order is genuinely consistent with
## `encounter.get_turn_order()` (the authoritative initiative table) rather
## than merely internally sorted.
func _verb_bar_stride_execute(selection) -> Dictionary:
	return await _controller("STRIDE").execute(selection)


## The END_TURN verb's availability/enter_selection/execute are delegated to
## presentation/end_turn_action_controller.gd (EndTurnActionController, a concrete
## ActionController subclass). These thin shims keep the VerbBarRegistry's
## Callable(self, "_verb_bar_end_turn_*") registrations and the direct-call tests
## unchanged.
func _verb_bar_end_turn_availability() -> bool:
	return _controller("END_TURN").availability()


func _verb_bar_end_turn_enter_selection() -> Dictionary:
	return _controller("END_TURN").enter_selection()


func _verb_bar_end_turn_execute(_selection = null) -> Dictionary:
	return _controller("END_TURN").execute(_selection)


## The CAST_SPELL verb's availability/enter_selection/execute are delegated to
## presentation/verbs/spell_action_controller.gd (SpellActionController, a
## concrete ActionController subclass) — FEAT-004 (US-004, FR-003). These thin
## shims mirror the STRIKE/STEP/STRIDE/END_TURN shims exactly (see VERB_TABLE's
## own doc: "adding a verb is ~one entry ... + the three thin
## _verb_bar_<verb>_* shims"), keeping the VerbBarRegistry's
## Callable(self, "_verb_bar_cast_spell_*") registrations and any direct-call
## tests working unchanged. SpellActionController.execute() is currently a
## synchronous skeleton stub (no `await` inside it), so this shim does not
## `await` it either — mirrors _verb_bar_step_execute()/_verb_bar_end_turn_execute()'s
## identical non-async convention, not _verb_bar_strike_execute()/
## _verb_bar_stride_execute()'s awaited one.
func _verb_bar_cast_spell_availability() -> bool:
	return _controller("CAST_SPELL").availability()


func _verb_bar_cast_spell_enter_selection() -> Dictionary:
	return _controller("CAST_SPELL").enter_selection()


func _verb_bar_cast_spell_execute(selection = null) -> Dictionary:
	return await _controller("CAST_SPELL").execute(selection)


## The COMBINE verb's availability/enter_selection/execute are delegated to
## presentation/combine_action_controller.gd (CombineActionController, a
## concrete ActionController subclass) — FEAT-001 (US-001, FR-003), Iteration
## N (Combinations) kickoff. These thin shims mirror the STRIKE/STEP/STRIDE/
## END_TURN/CAST_SPELL shims exactly (see VERB_TABLE's own doc: "adding a
## verb is ~one entry ... + the three thin _verb_bar_<verb>_* shims"),
## keeping VerbBarRegistry's Callable(self, "_verb_bar_combine_*")
## registrations working the instant COMBINE is added to VERB_TABLE.
## CombineActionController.execute() (FEAT-007) now awaits each resolved
## sub-action's own controller.execute() call (STRIDE's own execute() itself
## awaits Opportunistic-Strike resolution), so this shim `await`s it too —
## mirrors _verb_bar_strike_execute()'s/_verb_bar_stride_execute()'s
## identical awaited convention (harmless even for the pre-FEAT-007
## no-`controller_for` degrade path: `await` on an already-resolved value is
## a documented GDScript no-op).
func _verb_bar_combine_availability() -> bool:
	return _controller("COMBINE").availability()


## _verb_bar_combine_enter_selection() -> Dictionary — FEAT-296
## (DEF-NEW-001), FEAT-004 (US-003): the LIVE entry point VerbBarRegistry
## actually registers/invokes for a real player's COMBINE press
## (`_verb_bar_combine_*` mirrors every other verb's own thin
## `_verb_bar_<verb>_*` shim, see VERB_TABLE's own doc). Delegates to
## `combine_queue_build_session.start(actor)` -- the extracted interactive
## BuildVerbQueueUseCase/ConfirmQueueUseCase-backed queue-builder loop
## (presentation/combine_queue_build_session.gd) -- which drives
## SelectionOverlay directly, exactly like combine_targeting_session.start()'s
## own established precedent for the targeting phase. No verb_id is ever
## hardcoded here (or anywhere else in this file) -- the real, live
## candidate pool (STRIDE/STRIKE today; any future combinable verb
## automatically, with zero change to this function) is asked for fresh on
## every pick via `_core_combine_action_controller`'s own
## BuildVerbQueueUseCase seam (wired into the session at setup() time).
func _verb_bar_combine_enter_selection() -> Dictionary:
	var actor = round_session.current_actor() if round_session != null else null
	combine_queue_build_session.start(actor)
	return {}  # combine_queue_build_session.start() drives SelectionOverlay directly


func _verb_bar_combine_execute(selection = null) -> Dictionary:
	return await _controller("COMBINE").execute(selection)


## _on_verb_bar_selection_entered(verb_id, selection) -> void — FEAT-008 /
## US-008: forwards VerbBarView's own verb_selection_entered signal
## (emitted immediately after registry.enter_selection(verb_id) inside
## VerbBarView.press(), see presentation/verb_bar_view.gd's file-level doc)
## straight to selection_overlay.activate() -- this composition root never
## re-derives or re-queries the descriptor itself, and never special-cases
## verb_id here (ADR-002/CR-001: no forked Layer 2 wiring per verb).
func _on_verb_bar_selection_entered(verb_id: String, selection) -> void:
	if combine_targeting_session.is_active() or combine_queue_build_session.is_active():
		return  # combine_targeting_session.start()/combine_queue_build_session.start() already drove SelectionOverlay directly
	selection_overlay.activate(verb_id, selection)
	if selection_overlay.is_awaiting_option():
		_spell_picker.show(selection_overlay.get_candidate_options(), Callable(selection_overlay, "choose_option"))


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
##
## FEAT-005 (US-004; FR-004; ADR-003): when `combine_targeting_session`'s OWN
## interactive Combine targeting loop is mid-flight AND this resolution is
## for the CURRENT targeting phase's own verb_id, this handler routes to
## `combine_targeting_session.try_advance(_verb_id)` instead -- the resolved
## value was already captured (via that session's own registry proxy,
## installed as selection_overlay's `_registry` for the duration) by that
## session's own `_on_combine_targeting_value_chosen()` BEFORE this signal
## ever fired, so this branch's ONLY job is advancing the loop, never
## touching `_verb_registry`/`verb_bar_view`/highlight state a standalone
## verb resolution would. Every standalone (non-Combine) verb resolution
## takes the EXACT SAME path below this guard as before this feature
## (`combine_targeting_session.is_active()` is false for the whole of a
## standalone Strike/Stride flow), which is this feature's own regression
## test_criteria.
func _on_selection_overlay_resolved(_verb_id: String, _result) -> void:
	# FEAT-296 (DEF-NEW-001), FEAT-004 (US-003): mirrors the FEAT-005
	# targeting-phase branch immediately below, one phase earlier -- a
	# resolved COMBINE pick while the interactive queue-BUILD loop is active
	# routes to `combine_queue_build_session.advance()` instead, never
	# touching `_verb_registry`/`verb_bar_view`/highlight state a standalone
	# verb resolution would.
	if combine_queue_build_session.is_active() and _verb_id == "COMBINE":
		combine_queue_build_session.advance()
		return
	if combine_targeting_session.try_advance(_verb_id):
		return
	_spell_picker.hide()
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()
	if round_session != null:
		# Phase C.3/C.4: highlight_legal_moves is instance-native (it configures the
		# mutating movement controller), so pass the LIVE actor instance.
		var actor = round_session.current_actor_entity()
		if actor != null:
			_turn_presentation().highlight_legal_moves(actor, actor.display_id())
			# Push action budget to StatusPanelView. Strike already does this via AttackEvent,
			# but Cast Spell / Continue Cast spend actions without emitting any event, so an
			# explicit push is required here (mirrors StrideActionController's pattern).
			var ae = round_session.current_action_economy()
			if ae != null and status_panel_view != null:
				status_panel_view.on_verb_action_budget_changed(
					actor.display_id(), ae.get_remaining(), ae.is_spent()
				)
		# Push fresh HP values for all combatants after any spell resolution.
		# Spell damage is applied via EffectsApplier (no AttackEvent emitted),
		# so on_attack_event() never fires — an explicit HP push is required
		# (mirrors the action-budget push above for the same reason).
		if status_panel_view != null:
			for combatant in _party + _enemies:
				status_panel_view.update_combatant_hp(combatant.display_id(), combatant.hp_current)


# ── FEAT-005 (US-004; FR-004; ADR-003) — interactive Combine sub-action
# TARGETING pick loop, extracted into presentation/combine_targeting_session.gd
#
# The former inline `start_combine_targeting()` / `_enter_combine_targeting_phase()`
# / `_on_combine_targeting_value_chosen()` / `_advance_combine_targeting_phase()`
# / `_finish_combine_targeting()` / `_abort_combine_targeting()` /
# `_reset_combine_targeting_state()` / `_combine_verb_id_of()` /
# `_combine_order_index_of()` methods (FEAT-007's own "interactive Combine
# sub-action targeting" loop) now live entirely inside
# presentation/combine_targeting_session.gd's CombineTargetingSession --
# `combine_targeting_session` (constructed/wired in _ready() above) wraps
# `multi_phase_targeting_controller` (UNCHANGED, RISK-002) via composition
# only. This composition root's ONLY remaining responsibilities are: (1)
# `combine_targeting_session.try_advance(verb_id)`, called from
# _on_selection_overlay_resolved() above once selection_overlay resolves a
# phase; (2) the hand-off below, once the session's own
# `queue_built(queue)` signal (from combine_queue_build_session) fires,
# forwarding the confirmed queue into `combine_targeting_session.start(...)`;
# and (3) `_on_combine_targeting_complete()` below, the sole consumer of
# `combine_targeting_session.targeting_complete`, which performs the SAME
# post-verb UI refresh (availability re-gate, legal-move highlight, action
# budget/HP/stamina push) the pre-extraction `_finish_combine_targeting()`
# performed inline on every successful loop exhaustion. See
# presentation/combine_targeting_session.gd's own file-level doc for the
# full interactive-loop algorithm now owned there.


## _on_combine_queue_built(queue) -> void — FEAT-004 (US-003): the sole
## consumer of `combine_queue_build_session.queue_built`. `queue` is the
## now-CONFIRMED CombineQueue instance (see combine_queue_build_session.gd's
## own signal doc) -- this composition root resolves the acting Combatant
## back off `queue.actor_id` (via `_find_combatant_by_id()`, the SAME
## lookup every other combatant-by-id resolution in this file already uses)
## and hands `queue.sorted_entries()` / that actor / `queue.context` /
## `queue` itself straight to `combine_targeting_session.start(...)`
## (FEAT-005) -- the SAME hand-off shape the pre-extraction queue-build
## loop's own Confirm branch used to perform inline.
func _on_combine_queue_built(queue) -> void:
	var entries: Array = queue.sorted_entries()
	var actor = _find_combatant_by_id(queue.actor_id)
	combine_targeting_session.start(entries, actor, queue.context, queue)


## _on_combine_targeting_complete(result) -> void — FEAT-005 (US-004;
## FR-004): the sole consumer of `combine_targeting_session.targeting_complete`.
## `result` is `multi_phase_targeting_controller.execute()`'s own Dictionary
## return value, passed straight through unmodified (see
## combine_targeting_session.gd's own `targeting_complete` signal doc for why
## this fires regardless of `result.ok`) -- unused here by name, since this
## handler's job (mirroring the pre-extraction `_finish_combine_targeting()`'s
## own unconditional tail) is purely the SAME post-verb UI refresh every
## standalone verb resolution already performs: re-gate availability (locks
## out Step after Stride), re-highlight legal moves, and push updated
## stamina/action budget to UI.
func _on_combine_targeting_complete(_result: Dictionary) -> void:
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()
	if round_session != null:
		var actor = round_session.current_actor_entity()
		if actor != null:
			_turn_presentation().highlight_legal_moves(actor, actor.display_id())
			var ae = round_session.current_action_economy()
			if ae != null and status_panel_view != null:
				status_panel_view.on_verb_action_budget_changed(
					actor.display_id(), ae.get_remaining(), ae.is_spent()
				)
		if status_panel_view != null:
			for combatant in _party + _enemies:
				status_panel_view.update_combatant_hp(combatant.display_id(), combatant.hp_current)
				status_panel_view.update_combatant_stamina(combatant.display_id(), combatant.stamina)


# ── Spell picker panel ───────────────────────────────────────────────────────
# FEAT-008 (US-007 / FR-002): the former `_setup_spell_picker_panel()` /
# `_show_spell_picker()` / `_on_spell_option_pressed()` / `_hide_spell_picker()`
# quartet that used to live here has been extracted into
# presentation/spell_picker_panel_controller.gd's SpellPickerPanelController
# (see that file's own file-level doc). This composition root now owns only
# the `_spell_picker` field (declared near `round_flow_controller`, above)
# and the `_spell_picker.setup(spell_picker_panel)` call inside `_ready()` —
# every populate/show/hide concern lives in the extracted controller.


## _turn_presentation() — lazily builds (once) and returns the extracted
## TurnPresentationController, injecting the stable RoundSessionHolder + view
## collaborators + a Callable to the _other_living_combatants roster query. See
## the _turn_presentation_instance field doc for why this is lazy, not @onready.
func _turn_presentation():
	if _turn_presentation_instance == null:
		_turn_presentation_instance = TurnPresentationControllerClass.new(
			_round_session_holder,
			movement_input_controller,
			hex_grid_view,
			verb_bar_view,
			status_panel_view,
			Callable(self, "_other_living_combatants")
		)
	return _turn_presentation_instance


## _current_round_number() -> int - live accessor for the mutable ROUND_NUMBER,
## injected into ReactionController as a Callable so its round-number reads never
## go stale across a round rollover.
func _current_round_number() -> int:
	return ROUND_NUMBER


## _reaction() - lazily builds (once) and returns the extracted
## ReactionController, injecting the shared _action_economy_for lookup and the
## live ROUND_NUMBER as Callables plus the stable composition-root references.
## Lazy (like _turn_presentation) so it works both booted and under a `.new()`
## test that drives a reaction seam without _ready().
func _reaction():
	if _reaction_instance == null:
		_reaction_instance = ReactionControllerClass.new(
			Callable(self, "_action_economy_for"),
			Callable(self, "_current_round_number"),
			resolve_action_use_case,
			turn_controller,
			enemy_reaction_chooser,
			hex_grid_view
		)
	return _reaction_instance


## _verb_deps() — the ONE memoized deps Dictionary every ActionController is built
## from (data-driven verb table, 2026-07-11). Holds every collaborator + Callable
## any verb needs, keyed by the documented names each controller reads (see
## action_controller.gd's _init doc). `reaction` is the shared _reaction()
## ReactionController used by both Strike and Stride. Built once — its members
## (the stable RoundSessionHolder, view nodes, movement_input_controller,
## resolve/reaction collaborators, and the live-accessor Callables) are none of
## them reassigned after first access, so a single dict is behavior-identical to
## the old per-verb positional constructors. Individual verbs read only their own
## keys; extra keys are harmless, which is what keeps adding a verb to ~one table
## entry.
##
## FEAT-283 (resolves PR-001): adds the four CAST_SPELL-only keys design
## notes' architecture section and PR-001's blocker finding called out as
## never having been wired into this dict — "targeting_port"/
## "resolution_port"/"combat_log_port" (the real `spell_targeting_port`/
## `spell_resolution_port`/`spell_combat_log_port` fields, constructed ONCE
## in _ready(), see those fields' own doc) and "energy_pool_fn" (a Callable
## bound to `_energy_pool_for()` below, mirroring "action_economy_for"'s
## identical "live accessor Callable, re-resolved through the stable
## RoundSessionHolder on every call" convention — never a stale per-round
## EnergyPool reference). Every OTHER pre-existing key above is left
## byte-for-byte unchanged, so STRIKE/STEP/STRIDE/END_TURN's own
## `_verb_deps()` reads are unaffected by this addition (extra keys are
## harmless — file-level doc above).
##
## FEAT-285 (resolves PR-002/PR-004): adds "targeting_candidates_fn" —
## presentation/verbs/spell_action_controller.gd's `_init()` already reads
## `deps.get("targeting_candidates_fn", Callable())` and forwards it to
## ResolveSpellController as its own "candidates_fn" (that file's own doc:
## "the candidate target pool BEFORE range filtering"), but this dict never
## supplied one — an unwired Callable() degrades to an EMPTY candidate
## Array (ResolveSpellController._in_range_candidates()'s own documented
## fallback), so `_targeting_port.request_single_target([])` always
## returned null and every real, composition-root-driven targeted spell
## cast (e.g. Fire Bolt) resolved as ERR_NO_VALID_TARGET — a wasted action,
## never a real hit — regardless of how close/legal the target actually
## was. FEAT-283's own boot-real proof (tests/boot/
## test_cast_spell_verb_deps_composition_root_wiring.gd) never caught this
## because it only drove Channel (a self/no-target ADD_ENERGY spell, which
## never reaches `_in_range_candidates()` at all); every EARLIER Fire-Bolt-
## carrying boot-real suite (tests/e2e/test_steel_thread_cast_a_spell.gd/
## tests/e2e/test_determinism_pinned_seed_cast_a_spell.gd) masked this exact
## gap by `_verb_deps().duplicate()`-ing and manually overriding
## "resolve_spell_controller" with its OWN hand-wired `candidates_fn` —
## PR-002/PR-004's blocker finding. Bound to `_living_enemy_reactors()`
## below — the SAME real living-enemy accessor "living_enemy_reactors"
## already reads for the Opportunistic-Strike reactor pool, so no new/
## duplicate seam is introduced (ci/check_no_duplicate_seams.sh) — spells
## only ever target living enemies in this codebase's current scope,
## mirroring presentation/strike_action_controller.gd's own `living_enemies_fn`
## precedent this key's own doc (resolve_spell_controller.gd) already
## pointed to.
##
## FEAT-007 (US-007; Iteration N Combinations, the steel thread's exit
## point) adds "controller_for" — `Callable(self, "_controller")`, the SAME
## method this composition root's OWN `_controller(verb_id)` lookup below is
## defined as. presentation/combine_action_controller.gd's
## CombineActionController reads this Callable (never a hard preload/
## class_name reference to StrideActionController/StrikeActionController) so
## a real, booted Combine resolves its queued STRIDE/STRIKE sub-actions to
## the EXACT SAME memoized `_controllers` instances every other verb is
## resolved through — one registry, one resolution path.
func _verb_deps() -> Dictionary:
	if _verb_deps_cache == null:
		_verb_deps_cache = {
			"session_holder": _round_session_holder,
			"end_turn_control": end_turn_control,
			"movement_input_controller": movement_input_controller,
			"status_panel_view": status_panel_view,
			"event_log_view": event_log_view,
			"resolve_action_use_case": resolve_action_use_case,
			"enemy_reaction_chooser": enemy_reaction_chooser,
			"reaction": _reaction(),
			"action_economy_for": Callable(self, "_action_economy_for"),
			"current_round_number": Callable(self, "_current_round_number"),
			"after_successful_move": Callable(self, "_after_successful_move"),
			"living_enemy_reactors": Callable(self, "_living_enemy_reactors"),
			"current_turn_order": Callable(self, "_current_turn_order"),
			"query_selectable_step_hexes": Callable(self, "_query_selectable_step_hexes"),
			"targeting_port": spell_targeting_port,
			"targeting_candidates_fn": Callable(self, "_living_enemy_reactors"),
			"resolution_port": spell_resolution_port,
			"combat_log_port": spell_combat_log_port,
			"energy_pool_fn": Callable(self, "_energy_pool_for"),
			"controller_for": Callable(self, "_controller"),
		}
	return _verb_deps_cache


## _energy_pool_for(caster) -> EnergyPool or null — FEAT-283 (resolves
## PR-001): the real "energy_pool_fn" Callable(caster) -> EnergyPool
## `_verb_deps()` now registers, so ResolveCastUseCase's ADD_ENERGY branch
## (e.g. Channel, core/application/use_cases/resolve_cast_use_case.gd's own
## FEAT-277 doc) mutates the SAME live, round-scoped EnergyPool every other
## CAST_SPELL collaborator reads/writes through, never a second/parallel
## pool. Delegates to the live `round_session`'s own
## get_energy_pool(caster) (core/application/round_session.gd), read
## through the `round_session` property so this Callable is never bound to
## a stale per-round instance — mirrors `_action_economy_for()`'s identical
## "re-fetch the live session on every call" discipline. Returns null
## (rather than crashing) when no round_session is live yet — a defensive
## fallback that should be unreachable once a real MainScene has completed
## _ready() (round_session is non-null immediately after, per
## tests/unit/test_main_scene_interactive_wiring.gd's own criterion 1).
func _energy_pool_for(caster):
	var session = round_session
	if session == null or caster == null:
		return null
	return session.get_energy_pool(caster)


## _controller(verb_id) — the single data-driven controller resolver (2026-07-11):
## memoizes VERB_TABLE[verb_id].new(_verb_deps()) into _controllers, so every verb
## (and a future Combine's sub-actions) is reached the SAME way. Lazy so it serves
## a booted MainScene and a `.new()` test driving a verb without _ready().
func _controller(verb_id: String):
	if not _controllers.has(verb_id):
		_controllers[verb_id] = VERB_TABLE[verb_id].new(_verb_deps())
	return _controllers[verb_id]


## _living_enemy_reactors() -> the living-enemy reactor pool (spawn order)
## StrideActionController orders by initiative. _current_turn_order() -> the
## authoritative rolled initiative table (or null when no encounter yet), for the
## fail-loud ordering guard.
func _living_enemy_reactors() -> Array:
	return _living_combatants(_enemies)


## _current_party() / _current_enemies() -> Array — FEAT-006 (US-006 /
## FR-007): the `party_fn`/`enemies_fn` Callables round_flow_controller is
## `setup()` with in _ready() above. Read `_party`/`_enemies` FRESH on every
## call (never a snapshot) -- mirrors every other extracted controller's
## closures in this file (e.g. `_verb_bar_strike_availability()`'s own doc).
func _current_party() -> Array:
	return _party


func _current_enemies() -> Array:
	return _enemies


func _current_turn_order():
	return encounter.get_turn_order() if encounter != null else null


## _on_active_actor_changed(combatant) -> void - thin delegation to
## presentation/turn_presentation_controller.gd (TurnPresentationController),
## which owns the turn-started presentation reaction (movement reconfigure +
## legal-move highlight + verb-bar re-gate + action-budget refresh). Retained as
## MainScene's seam: TurnController's active_actor_changed signal and the booted
## integration tests drive it here. The controller is built lazily on first use
## and reaches the live session via the RoundSessionHolder.
func _on_active_actor_changed(combatant) -> void:
	_turn_presentation().on_active_actor_changed(combatant)


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
## round_session.current_actor() returns null (see core/application/
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
##
## FEAT-009 (US-008 / FR-007): now branches on the just-refreshed `outcome`
## (round_session.outcome(), the SAME live source this method already read
## into `outcome` -- design notes' architecture section names
## `encounter.get_outcome()` as the branch source, but the interactive
## RunRoundUseCase/RoundSession pipeline this composition root actually
## drives (FEAT-123 / ADR-007) never calls the legacy `encounter`
## object's own run()/run_round() -- its `_outcome` field is therefore never
## populated and would stay "" forever; `round_session.outcome()` is the
## real, live equivalent this file already established as the single
## outcome-of-record, so this feature branches on THAT rather than
## introducing a second, always-empty read):
##   - "" (undecided, existing behavior, byte-for-byte unchanged): the round
##     continues -- ROUND_NUMBER increments and rewire_session() begins the
##     next round exactly as before this feature.
##   - "won": the full post-combat exploration-return handoff
##     (_on_combat_won() below) runs -- this is this feature's own new
##     branch.
##   - "lost": a placeholder push_error() only (no crash, no state mutation)
##     -- the real "lost" handoff (e.g. a defeat/retry screen) is an
##     explicitly deferred, LATER feature's scope; ResultScreenView has
##     already reacted to the EncounterResultEvent this round's own
##     resolution emitted (see this file's step 11 doc), so the player is
##     never left without ANY on-screen feedback even before that later
##     feature lands.
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
	elif outcome == "won":
		_on_combat_won()
	elif outcome == "lost":
		# FEAT-009 placeholder (US-008): a genuinely unexpected/unhandled
		# terminal state gets a developer/QA-facing signal (push_error, per
		# design notes' error_handling #2 "loud for genuinely unexpected
		# states") rather than a silent no-op -- but deliberately never
		# crashes and never mutates _game_mode/_active_encounter_id/
		# scenario_session, so the (already-locked, per ResultScreenView)
		# combat screen is left exactly as a decided "lost" round leaves it
		# today, with zero regression to that pre-existing behavior.
		push_error("MainScene: 'lost' outcome handling is not yet implemented (FEAT-009 placeholder)")

	# ── FEAT-006 (US-006 / FR-007): relay this round's conclusion to the
	# extracted RoundFlowController via its safe, additive
	# notify_round_concluded() helper -- a PURE signal relay (never calls
	# begin_round()/mutates round_session of its own accord, see that
	# method's own doc), so round_flow_controller.round_over() fires for this
	# real, live round conclusion too, for whatever UI-cleanup-only
	# subscriber is wired to it (_on_round_flow_controller_round_over()
	# below). ────────────────────────────────────────────────────────────────
	round_flow_controller.notify_round_concluded()


## _on_round_flow_controller_round_over() -> void — FEAT-006 (US-006 /
## FR-007): connected to the extracted RoundFlowController's own
## `round_over()` signal (_ready() above). UI CLEANUP ONLY — never mutates
## `ROUND_NUMBER`/`round_session`/`_game_mode`/`_active_encounter_id`/
## `scenario_session`, and never calls `rewire_session()` or begins a new
## round via the injected RunRoundUseCase — every one of those remains the
## sole responsibility of this file's own pre-existing, pinned `_on_round_over()`
## above (see round_flow_controller.gd's own file-level doc for why). Simply
## re-gates the Layer 1 verb bar's availability one more time, mirroring
## `_on_round_over()`'s own identical (idempotent) refresh_availability()
## call immediately above -- harmless to invoke twice.
func _on_round_flow_controller_round_over() -> void:
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()


## _on_combat_won() -> void — FEAT-009 (US-008 / FR-007): the post-combat
## return-to-exploration handoff, run once _on_round_over() above observes
## outcome == "won". Mirrors _on_combat_triggered()'s (FEAT-008) own ordered,
## atomic-transition style in reverse:
##
##   1. `_active_encounter_id` is marked complete in `scenario_session`
##      (ScenarioSession.mark_encounter_complete(), FEAT-003 -- already
##      idempotent/defensive against a dangling id, RISK-010) BEFORE any
##      other mutation below, so a future re-entry check
##      (ExplorationController._evaluate_triggers() ->
##      ScenarioSession.get_active_encounter_entries(), unmodified) already
##      excludes this encounter from the very next trigger evaluation.
##   2. Enemy tokens for the just-won encounter are stripped off
##      `hex_grid_view` via the new HexGridView.remove_combatants() (the
##      mirror operation to FEAT-008's add_combatants()) -- party tokens are
##      never touched (ADR-001) -- and `_enemies` is cleared to match.
##   3. Every combat-facing signal subscription this composition root owns
##      (`turn_controller.active_actor_changed`/`round_over`, and
##      `hex_grid_view.hex_clicked`) is torn down via an explicit
##      unsubscribe-before-resubscribe pattern (RISK-010 mitigation) -- a
##      disconnect-if-connected guard immediately followed by a fresh
##      connect -- so a repeated post-combat transition can never leave a
##      duplicate/dangling listener behind, mirroring
##      _on_combat_triggered()'s identical disconnect-then-conditionally-
##      reconnect convention for hex_clicked (FEAT-008).
##   4. `_game_mode` is committed back to GameMode.EXPLORATION and
##      `_active_encounter_id` is cleared -- only ever mutated together,
##      mirroring _on_combat_triggered()'s own atomic "only mutated
##      together" contract for the opposite transition.
func _on_combat_won() -> void:
	if scenario_session != null and _active_encounter_id != "":
		scenario_session.mark_encounter_complete(_active_encounter_id)

	if hex_grid_view != null:
		var enemy_ids: Array = []
		for enemy in _enemies:
			enemy_ids.append(enemy.combatant_id)
		hex_grid_view.remove_combatants(enemy_ids)
	_enemies = []

	# RISK-010 mitigation: explicit unsubscribe-before-resubscribe for every
	# combat-facing signal subscription this composition root owns, so this
	# (or a later) post-combat transition never leaves a duplicate/dangling
	# listener behind.
	if turn_controller != null:
		if turn_controller.active_actor_changed.is_connected(_on_active_actor_changed):
			turn_controller.active_actor_changed.disconnect(_on_active_actor_changed)
		turn_controller.active_actor_changed.connect(_on_active_actor_changed)

		if turn_controller.round_over.is_connected(_on_round_over):
			turn_controller.round_over.disconnect(_on_round_over)
		turn_controller.round_over.connect(_on_round_over)

	_game_mode = GameMode.EXPLORATION
	_active_encounter_id = ""

	if hex_grid_view != null:
		if hex_grid_view.hex_clicked.is_connected(_on_exploration_hex_clicked):
			hex_grid_view.hex_clicked.disconnect(_on_exploration_hex_clicked)
		hex_grid_view.hex_clicked.connect(_on_exploration_hex_clicked)


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
		# Phase C.3/C.4: on_active_actor_changed is instance-native (configures the
		# mutating movement controller) — pass the LIVE actor instance.
		_on_active_actor_changed(round_session.current_actor_entity())


## _other_living_combatants(combatant) -> Array — every living (hp_current >
## 0) combatant in _party + _enemies EXCEPT `combatant` itself, identified by
## the same "combatant_id" falling back to "name" convention used throughout
## this file -- the occupancy list movement_input_controller.configure()
## requires (core/rules/movement.gd Movement.step()'s `other_combatants`
## parameter must never include the mover itself).
func _other_living_combatants(combatant) -> Array:
	var self_id: String = combatant.display_id()
	var others: Array = []
	for c in _living_combatants(_party + _enemies):
		if c.display_id() != self_id:
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
func _find_combatant_by_id(combatant_id: String):
	for c in _party + _enemies:
		if c.display_id() == combatant_id:
			return c
	return null


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
	var combatant = _find_combatant_by_id(combatant_id)
	if combatant == null:
		return []
	return movement_input_controller.get_selectable_step_hexes_for(combatant, _other_living_combatants(combatant))


## _living_combatants(combatants) -> Array — the subset of `combatants` with
## hp_current > 0, mirroring the living-target filter core/combat/ai.gd and
## core/application/round_session.gd already apply internally, so
## StrikeActionControl is never offered an already-defeated target.
func _living_combatants(combatants: Array) -> Array:
	var living: Array = []
	for c in combatants:
		if c.hp_current > 0:
			living.append(c)
	return living


## _order_candidate_reactors_by_initiative(candidates) -> Array — FEAT-228
## (resolves FIND-224 / FR-007, US-008): returns a NEW Array containing every
## Dictionary in `candidates`, sorted DESCENDING by each combatant's own
## "_initiative_roll" (the value core/combat/encounter.gd's initialize()
## stamps onto every party/enemy combatant Dictionary while rolling and
## sorting the encounter's real turn order — see that file's own
## get_turn_order() doc: "combatant dicts in descending initiative order").
## `candidates` itself is never mutated (a fresh Array is returned) and a
## combatant missing "_initiative_roll" entirely (e.g. a bare unit-test
## fixture, or a caller invoked before encounter.initialize() ever ran) reads
## as roll 0 rather than crashing, matching this file's established
## default-safe Dictionary.get() convention throughout.
##
## Ties (equal "_initiative_roll") are broken by preserving `candidates`'
## OWN original relative order — i.e. this sort is STABLE — rather than
## leaving tie order to whatever Array.sort_custom()'s underlying
## implementation happens to do, which the ADR on deterministic-replay
## ordering this feature closes out requires: an identical (seed, roster)
## pairing must always yield the identical candidate order, never a
## once-in-a-while divergence from an unstable comparator.
##
## This is this feature's actual fix for FIND-224: prior to FEAT-228,
## _verb_bar_stride_execute() fed `_living_combatants(_enemies)` — plain
## ENCOUNTER SPAWN ORDER (`_enemies`'s own Array order, fixed at boot BEFORE
## encounter.initialize() ever rolls initiative) — directly into
## ResolveStrideUseCase.execute(), which resolves reactors "strictly in the
## order given, never re-sorting them itself" (that file's own doc). Any
## enemy roster whose spawn order didn't already happen to match its rolled
## initiative order silently resolved Opportunistic Strikes out of turn
## order, with nothing to catch the discrepancy.
func _order_candidate_reactors_by_initiative(candidates: Array) -> Array:
	return _reaction().order_candidate_reactors_by_initiative(candidates)


## _assert_candidate_reactors_ordering(ordered_candidates, turn_order) -> bool
## — FEAT-228 (resolves FIND-224 / FR-007, US-008): the defensive, fail-loud
## guard this feature's design notes require ("add a defensive assertion
## that fires if ordering is ever inconsistent with the initiative table")
## — checked immediately after _order_candidate_reactors_by_initiative()
## above, so a future regression (e.g. a caller bypassing that helper, or a
## bug in it) is caught at the exact seam FIND-224 identified, rather than
## silently resolving Opportunistic Strikes out of order again.
##
## `turn_order` is `encounter.get_turn_order()`'s own return value — the
## authoritative, already-rolled initiative table (descending, one entry per
## combatant, per that file's doc) — NOT re-derived or re-sorted here.
## `ordered_candidates` is genuinely consistent with that table iff, walking
## `ordered_candidates` in order, each combatant's position within
## `turn_order` is non-decreasing (i.e. `ordered_candidates` is a
## subsequence of `turn_order`, preserving the table's own relative order).
## Combatants are matched by the SAME "combatant_id" falling back to "name"
## identity convention used throughout this file (e.g.
## _other_living_combatants()).
##
## Returns true when consistent. On a violation (a candidate resolves out of
## the table's order, OR a candidate is entirely absent from `turn_order`),
## mirrors core/application/reaction_window.gd's own
## assert_reaction_budget_delta() convention exactly: a real GDScript
## assert() fires (failing loudly in a dev/test build — Godot only compiles
## assert() into debug builds) AND push_error() logs the same message as
## defense-in-depth (this project's Godot 4.3 engine cannot capture
## push_error() output from GUT — see resolution.gd's identical documented
## limitation) — then returns false so a GUT test can observe the violation
## directly via this method's own return value, exactly as
## assert_reaction_budget_delta() already established.
func _assert_candidate_reactors_ordering(ordered_candidates: Array, turn_order: Array) -> bool:
	return _reaction().assert_candidate_reactors_ordering(ordered_candidates, turn_order)


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
		var combatant_id: String = combatant.display_id()
		var off_guard: bool = FlankingClass.is_off_guard(combatant, living_enemies)
		combatant.conditions = FlankingClass.off_guard_conditions(combatant, living_enemies)
		if status_panel_view != null:
			status_panel_view.set_off_guard(combatant_id, off_guard)

	for combatant in _enemies:
		var combatant_id: String = combatant.display_id()
		var off_guard: bool = FlankingClass.is_off_guard(combatant, living_party)
		combatant.conditions = FlankingClass.off_guard_conditions(combatant, living_party)
		if status_panel_view != null:
			status_panel_view.set_off_guard(combatant_id, off_guard)


## _build_party_combatant / _build_enemy_combatant - thin delegations to
## infrastructure/combatant_factory.gd (CombatantFactory), where the party/enemy
## construction + FEAT-227 fail-fast validation now lives (composition-root
## de-bloat, 2026-07-10). These shims preserve the _ready() call sites and the
## existing direct-call test surface. See CombatantFactory for the typed ERR_
## codes and full rationale; a caller MUST still check result.has("error") on
## the enemy build before treating it as a playable combatant.
func _build_party_combatant(character_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	return _combatant_factory.build_party_combatant(character_path, hex_coord, combatant_id)


func _build_enemy_combatant(enemy_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	return _combatant_factory.build_enemy_combatant(enemy_path, hex_coord, combatant_id)

