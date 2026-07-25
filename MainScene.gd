extends Node
## MainScene.gd — composition root (ADR-002: single DI wiring point, no framework).
## FEAT-316: combat pipeline dormant until _on_combat_triggered(); boots into EXPLORATION.
const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")
const SeedPolicyClass                  = preload("res://infrastructure/seed_policy.gd")
const GodotRandomAdapterClass          = preload("res://core/combat/godot_random_adapter.gd")
const EncounterClass                   = preload("res://core/combat/encounter.gd")
const RNGClass                         = preload("res://core/rules/rng.gd")
const CombatantFactoryClass            = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")

const CombatSessionFactoryClass        = preload("res://core/application/combat_session_factory.gd")
const GdResourceLoaderAdapterClass     = preload("res://presentation/adapters/gd_resource_loader_adapter.gd")

const ExplorationModeControllerClass   = preload("res://presentation/exploration_mode_controller.gd")
const ViewModelBuilderClass            = preload("res://presentation/view_model_builder.gd")
const RoundSessionHolderClass          = preload("res://infrastructure/round_session_holder.gd")
const TurnPresentationControllerClass  = preload("res://presentation/turn_presentation_controller.gd")
const ReactionControllerClass          = preload("res://presentation/reaction_controller.gd")
const EndTurnActionControllerClass     = preload("res://presentation/end_turn_action_controller.gd")
const StepActionControllerClass        = preload("res://presentation/step_action_controller.gd")
const StrideActionControllerClass      = preload("res://presentation/stride_action_controller.gd")
const StrikeActionControllerClass      = preload("res://presentation/strike_action_controller.gd")
const SpellActionControllerClass       = preload("res://presentation/verbs/spell_action_controller.gd")

const ResolveSpellControllerClass      = preload("res://presentation/verbs/resolve_spell_controller.gd")

const CombineActionControllerClass     = preload("res://presentation/combine_action_controller.gd")

const MultiPhaseTargetingControllerClass = preload("res://core/application/combine/multi_phase_targeting_controller.gd")
const CoreCombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const CoreStrideActionControllerClass = preload("res://core/controllers/stride_action_controller.gd")
const CoreStrikeActionControllerClass = preload("res://core/controllers/strike_action_controller.gd")

const CoreCastSpellAdapterClass = preload("res://presentation/adapters/core_cast_spell_adapter.gd")
const GdVerbRegistryPortClass = preload("res://presentation/adapters/gd_verb_registry_port.gd")
const GdCombineActionEconomyPortClass = preload("res://presentation/adapters/gd_combine_action_economy_port.gd")

const CombineQueueBuildSessionClass = preload("res://presentation/combine_queue_build_session.gd")

const CombineTargetingSessionClass = preload("res://presentation/combine_targeting_session.gd")

const RoundFlowControllerClass = preload("res://presentation/round_flow_controller.gd")
## VerbDispatchControllerClass — FEAT-007/FEAT-320 (US-005/US-009; FR-006/
## FR-009; ADR-002): owns verb-bar dispatch (build_verb_registry()/
const VerbDispatchControllerClass = preload("res://presentation/verb_dispatch_controller.gd")
const CombatQueryServiceClass = preload("res://presentation/combat_query_service.gd")


const SpellPickerPanelControllerClass = preload("res://presentation/spell_picker_panel_controller.gd")

const TargetingPortClass               = preload("res://core/application/ports/targeting_port.gd")

const ResolutionPortClass              = preload("res://core/application/ports/resolution_port.gd")

const CombatLogPanelAdapterClass       = preload("res://presentation/ui/combat_log_panel_adapter.gd")

## VERB_TABLE — the single data-driven verb registry (composition-root de-bloat,
## 2026-07-11): verb_id → concrete ActionController subclass. This one table is
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

const OpenReactionWindowUseCaseClass   = preload("res://core/application/open_reaction_window_use_case.gd")

const ResolveStrideUseCaseClass        = preload("res://core/application/use_cases/resolve_stride_use_case.gd")

const ResolveDodgeStepUseCaseClass     = preload("res://core/application/resolve_dodge_step_use_case.gd")

const AIHexChoiceResolverClass         = preload("res://infrastructure/ai_hex_choice_resolver.gd")

const AIReactionPolicyClass            = preload("res://infrastructure/ai_reaction_policy.gd")

## The steel-thread's entry_point: the one encounter this composition root boots into.
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## PROLOGUE_SCENARIO_PATH — FEAT-006 (US-005 / FR-004): the ScenarioResource
## (data/scenarios/scenario_resource.gd, FEAT-006/Iteration-P) this
const PROLOGUE_SCENARIO_PATH: String = "res://data/scenarios/prologue_scenario.tres"

## FEAT-002 (US-002 / FR-012, ADR-003): fallback viewport dimensions used to
## derive the boot-time centering offset (see _compute_boot_centering_offset())
const DEFAULT_VIEWPORT_WIDTH: int = 1152
const DEFAULT_VIEWPORT_HEIGHT: int = 648

var ROUND_NUMBER: int = 1

## ACTION_NAME_STRIKE — FEAT-006: the action name passed to
## resolve_action_use_case.resolve() for a Strike, mirroring the removed
const ACTION_NAME_STRIKE: String = "Strike"


var seed_override = null

var resolved_seed: int = -1

## GameMode — FEAT-006 (US-005 / FR-004): the two top-level modes this
## composition root can be in. EXPLORATION is the primary user-facing entry
enum GameMode { EXPLORATION, COMBAT }

var _game_mode: GameMode = GameMode.EXPLORATION

var _active_encounter_id: String = ""

var _exploration = ExplorationModeControllerClass.new()

var scenario_session:
	get:
		return _exploration.scenario_session
	set(value):
		_exploration.scenario_session = value

var exploration_controller:
	get:
		return _exploration.exploration_controller
	set(value):
		_exploration.exploration_controller = value

var encounter_repository

var random_port

var event_sink

var encounter

var _round_session_holder := RoundSessionHolderClass.new()

var round_session:
	get:
		return _round_session_holder.get_current()
	set(value):
		_round_session_holder.set_current(value)

var run_round_use_case
var resolve_action_use_case
var determine_outcome_use_case
var round_history_port

var outcome: String = ""

@onready var hex_grid_view = $HexGridView

@onready var status_panel_view = $StatusPanelView

@onready var initiative_view = $InitiativeView

@onready var event_log_view = $EventLogView

var movement_input_controller = MovementInputControllerClass.new()

@onready var turn_controller = $TurnController

@onready var end_turn_control = $EndTurnControl

@onready var verb_bar_view = $VerbBarView

var _verb_registry = null

var selection_overlay = SelectionOverlayClass.new()

var cancel_controller = CancelControllerClass.new()

@onready var reaction_prompt_ui = $ReactionPromptUI

var player_reaction_chooser = null

var enemy_reaction_chooser = null

var hex_choice_resolver = null

var reaction_window = null

@onready var result_screen_view = $ResultScreenView

var _turn_presentation_instance = null

var _reaction_instance = null

var _controllers: Dictionary = {}
var _verb_deps_cache = null

var _combat_query_service = null

var multi_phase_targeting_controller = null
var _core_combine_action_controller = null

var _combine_controller_registry: Dictionary = {}

var combine_targeting_session = null

var combine_queue_build_session = null

var round_flow_controller = RoundFlowControllerClass.new()
var verb_dispatch_controller = VerbDispatchControllerClass.new()

var _spell_picker = SpellPickerPanelControllerClass.new()

var _party: Array = []
var _enemies: Array = []
var _combatant_factory := CombatantFactoryClass.new()
var _view_model_builder := ViewModelBuilderClass.new()


var centering_offset: Vector2 = Vector2.ZERO


## _FirstLegalTargetingPort — SUPERSEDED by presentation/ui/player_targeting_port.gd
## PlayerTargetingPort (wired below). Retained only to avoid breaking any


var spell_targeting_port = null
var spell_resolution_port = null
var spell_combat_log_port = null


## Boot: load encounter, wire all controllers, start EXPLORATION mode.
func _ready() -> void:
	encounter_repository = ResourceEncounterRepositoryClass.new()

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

	centering_offset = _compute_boot_centering_offset(hex_combatants)
	if hex_grid_view != null:
		hex_grid_view.set_origin_offset(centering_offset)
		hex_grid_view.load_combatants(hex_combatants)

	_game_mode = GameMode.EXPLORATION
	_exploration.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": PROLOGUE_SCENARIO_PATH,
		"on_hex_clicked": Callable(self, "_on_exploration_hex_clicked"),
		"on_combat_triggered": Callable(self, "_on_combat_triggered"),
	})
	_exploration.boot(hex_combatants)

	resolved_seed = SeedPolicyClass.resolve_from_environment(seed_override, int(Time.get_ticks_usec()))

	random_port = GodotRandomAdapterClass.new(resolved_seed)
	event_sink = ConsoleEventSinkAdapterClass.new()

	spell_targeting_port = PlayerTargetingPortClass.new(hex_grid_view)
	spell_resolution_port = ResolutionPortClass.ResolutionRulesAdapter.new(random_port)
	spell_combat_log_port = CombatLogPanelAdapterClass.new()
	if event_log_view != null:
		spell_combat_log_port.configure(event_log_view)

	var rng := RNGClass.new(resolved_seed)
	encounter = EncounterClass.new(_party, _enemies, rng)

	_combat_query_service = CombatQueryServiceClass.new(
		Callable(self, "_current_party"),
		Callable(self, "_current_enemies")
	)

	var status_view_models: Array = _view_model_builder.build_status_view_models(hex_combatants, _party, _enemies, encounter)

	if status_panel_view != null:
		status_panel_view.load_combatants(status_view_models)
		_refresh_off_guard_conditions()

	var initiative_view_models: Array = _view_model_builder.build_initiative_view_models(hex_combatants, _party, _enemies, encounter)

	if initiative_view != null:
		initiative_view.load_combatants(initiative_view_models)

	event_sink.forward_to = _presentation_event_subscribers()

	var turn_order_port = EncounterTurnOrderAdapterClass.new(encounter)
	round_history_port = InMemoryRoundHistoryAdapterClass.new()
	resolve_action_use_case = ResolveActionUseCaseClass.new(random_port, event_sink, round_history_port)
	determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	enemy_reaction_chooser = AIReactionPolicyClass.new()
	_reaction_instance = ReactionControllerClass.new(
		Callable(self, "_action_economy_for"),
		Callable(self, "_current_round_number"),
		resolve_action_use_case,
		turn_controller,
		enemy_reaction_chooser,
		hex_grid_view
	)

	var ai_decision_port = AIClass.new()

	ai_decision_port.set_stride_reaction_resolver_fn(Callable(_reaction_instance, "resolve_enemy_stride_opportunistic_window"))

	run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	if result_screen_view != null:
		# FEAT-006: no strike_action_control node exists anymore -- its
		result_screen_view.configure(null, end_turn_control, movement_input_controller, null, verb_bar_view, selection_overlay)


	reaction_window = ReactionWindowClass.new(event_sink)
	if reaction_prompt_ui != null:
		player_reaction_chooser = PlayerReactionChooserClass.new(reaction_prompt_ui)
	if turn_controller != null:
		turn_controller.configure_reactions(reaction_window, player_reaction_chooser)

	if hex_grid_view != null:
		hex_choice_resolver = UIHexChoiceResolverClass.new(hex_grid_view)

	if end_turn_control != null:
		end_turn_control.turn_ended.connect(_on_end_turn_control_turn_ended)
		# BUGFIX (post-iteration-E): End Turn is now a first-class verb in the
		end_turn_control.visible = false


	_verb_registry = verb_dispatch_controller.build_verb_registry(VERB_TABLE)

	_core_combine_action_controller = CoreCombineActionControllerClass.new({
		"verb_registry_port": GdVerbRegistryPortClass.new(),
		"action_economy_port": GdCombineActionEconomyPortClass.new(self),
		"controller_for": Callable(self, "_controller"),
	})
	# FEAT-007 (US-007; NFR-001): built as its own named field
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
	combine_queue_build_session = CombineQueueBuildSessionClass.new()
	combine_queue_build_session.setup({
		"combine_action_controller": _core_combine_action_controller,
		"selection_overlay": selection_overlay,
		"hex_grid_view": hex_grid_view,
		"verb_registry": _verb_registry,
		# FEAT-008 (US-007 / FR-002): these Callables now point at the
		"show_spell_picker_fn": Callable(_spell_picker, "show").bind(Callable(selection_overlay, "choose_option")),
		"hide_spell_picker_fn": Callable(_spell_picker, "hide"),
	})
	combine_queue_build_session.queue_built.connect(_on_combine_queue_built)

	# FEAT-005 (US-004; FR-004; ADR-003): the extracted interactive Combine
	combine_targeting_session = CombineTargetingSessionClass.new()
	combine_targeting_session.setup({
		"controller_registry": _combine_controller_registry,
		"targeting_controller": multi_phase_targeting_controller,
		"selection_overlay": selection_overlay,
		"hex_grid_view": hex_grid_view,
		"verb_registry": _verb_registry,
		# FEAT-008 (US-007 / FR-002): see the identical comment on
		"show_spell_picker_fn": Callable(_spell_picker, "show").bind(Callable(selection_overlay, "choose_option")),
	})
	combine_targeting_session.targeting_complete.connect(_on_combine_targeting_complete)

	verb_dispatch_controller.setup({
		"controller_fn": Callable(self, "_controller"),
		"round_session_fn": func(): return round_session,
		"combine_queue_build_session": combine_queue_build_session,
		"combine_targeting_session": combine_targeting_session,
		"selection_overlay": selection_overlay,
		"spell_picker": _spell_picker,
		"verb_bar_view": verb_bar_view,
		"status_panel_view": status_panel_view,
		"party_fn": Callable(self, "_current_party"),
		"enemies_fn": Callable(self, "_current_enemies"),
		"turn_presentation_fn": Callable(self, "_turn_presentation"),
	})

	round_flow_controller.setup({
		"run_round_use_case": run_round_use_case,
		"end_turn_control": end_turn_control,
		"verb_bar_view": verb_bar_view,
		"party_fn": Callable(self, "_current_party"),
		"enemies_fn": Callable(self, "_current_enemies"),
		"round_number": ROUND_NUMBER,
	})
	round_flow_controller.round_over.connect(_on_round_flow_controller_round_over)

	if verb_bar_view != null:
		verb_bar_view.verb_selection_entered.connect(verb_dispatch_controller._on_verb_bar_selection_entered)
	selection_overlay.selection_resolved.connect(verb_dispatch_controller._on_selection_overlay_resolved)

	# FEAT-008 (US-007 / FR-002): this composition root still creates/
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

	cancel_controller.configure(selection_overlay)

	# FEAT-316 (resolves DEF-001/PR-001): round_session is no longer
	if round_session != null:
		print(
			"INFO: Hykaen MainScene booted into the prologue encounter (interactive) -- "
			+ "current_actor=" + (round_session.current_actor().name if round_session.current_actor() != null else "")
			+ " round_over=" + str(round_session.is_round_over())
		)
	else:
		print("INFO: Hykaen MainScene booted into EXPLORATION mode -- no active round_session yet (FEAT-316)")

	print("DEBUG: viewport_centering centering_offset=" + str(centering_offset))


## Exploration→combat handoff: load encounter, commit COMBAT mode, await rewire_session().
func _on_combat_triggered(encounter_id: String) -> void:
	if hex_grid_view != null and hex_grid_view.hex_clicked.is_connected(_on_exploration_hex_clicked):
		hex_grid_view.hex_clicked.disconnect(_on_exploration_hex_clicked)

	var scenario = scenario_session.scenario if scenario_session != null else null
	var ok: bool = load_encounter_from_scenario(scenario, encounter_id)
	if not ok:
		# load_encounter_from_scenario() has already push_error()'d the
		if hex_grid_view != null and not hex_grid_view.hex_clicked.is_connected(_on_exploration_hex_clicked):
			hex_grid_view.hex_clicked.connect(_on_exploration_hex_clicked)
		return

	_game_mode = GameMode.COMBAT
	_active_encounter_id = encounter_id

	if hex_grid_view != null:
		hex_grid_view.add_combatants(_enemies)

	if turn_controller != null:
		if turn_controller.active_actor_changed.is_connected(_on_active_actor_changed):
			turn_controller.active_actor_changed.disconnect(_on_active_actor_changed)
		turn_controller.active_actor_changed.connect(_on_active_actor_changed)

		if turn_controller.round_over.is_connected(_on_round_over):
			turn_controller.round_over.disconnect(_on_round_over)
		turn_controller.round_over.connect(_on_round_over)

	var turn_order_port = EncounterTurnOrderAdapterClass.new(encounter)
	var ai_decision_port = AIClass.new()
	ai_decision_port.set_stride_reaction_resolver_fn(Callable(_reaction_instance, "resolve_enemy_stride_opportunistic_window"))
	run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink, round_history_port, ai_decision_port,
		resolve_action_use_case, determine_outcome_use_case
	)

	ROUND_NUMBER = 1
	await rewire_session()

	if verb_bar_view != null:
		verb_bar_view.configure(_verb_registry)
	selection_overlay.configure(_verb_registry, hex_grid_view)


## Move party[0] to clicked hex in EXPLORATION mode.
func _on_exploration_hex_clicked(hex_coord) -> void:
	if _game_mode != GameMode.EXPLORATION:
		return

	if _party.is_empty() or exploration_controller == null:
		return

	var combatant_id: String = _party[0].combatant_id
	var moved: bool = exploration_controller.move_party_member(combatant_id, hex_coord)
	if moved and hex_grid_view != null:
		hex_grid_view.move_token(combatant_id, hex_coord)


## Delegates to _exploration.load_encounter_from_scenario(); copies party/enemies/encounter back.
func load_encounter_from_scenario(scenario, encounter_id: String) -> bool:
	var ok: bool = _exploration.load_encounter_from_scenario(scenario, encounter_id, resolved_seed)
	if ok:
		_party = _exploration.party
		_enemies = _exploration.enemies
		encounter = _exploration.encounter
	return ok


## UI hex-choice resolver seam (wired into round_session).
func resolve_hex_choice(legal_hexes: Array):
	if hex_choice_resolver == null:
		return null
	return await hex_choice_resolver.resolve(legal_hexes)


## Obtain fresh RoundSession via begin_round(), wire all seams, hand to TurnController.
## Pinned by test_multi_round_loop.gd source inspection — must remain in MainScene.
func rewire_session() -> void:
	round_session = run_round_use_case.begin_round(ROUND_NUMBER, _party, _enemies)

	if round_session != null and hex_grid_view != null:
		round_session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))

	if round_session != null and turn_controller != null:
		round_session.set_reaction_resolver_fn(Callable(turn_controller, "resolve_reaction"))

		# ── FEAT-005 (US-005 / FR-005, Iteration J Part A): wire RoundSession's
		round_session.set_prehit_avoidance_resolver_fn(Callable(turn_controller, "resolve_reaction"))
		round_session.set_onhit_mitigation_resolver_fn(Callable(turn_controller, "resolve_reaction"))

		# FEAT-213 (Iteration J V&V fix): wire the structured combat-log recorder
		if event_log_view != null:
			round_session.set_event_log_record_attack_fn(Callable(event_log_view, "record_attack"))
			round_session.set_event_log_entry_count_fn(Callable(event_log_view, "get_entry_count"))
			round_session.set_event_log_render_attack_entry_fn(Callable(event_log_view, "render_attack_entry"))
			round_session.set_event_log_overwrite_entry_fn(Callable(event_log_view, "overwrite_entry_as_rich"))
			# FEAT-008 (US-008 / FR-007): wire the structured reaction recorder
			round_session.set_event_log_record_reaction_fn(Callable(event_log_view, "record_reaction"))

		# ── FEAT-002 (US-002, Dodge-Step steel thread): wire RoundSession's
		round_session.set_hex_choice_resolver_fn(Callable(self, "resolve_hex_choice"))
		round_session.set_step_hex_query_fn(Callable(self, "_query_selectable_step_hexes"))

	if turn_controller != null:
		# FEAT-006: strike_action_control no longer exists; set_session()'s
		await turn_controller.set_session(round_session, end_turn_control, null, verb_bar_view)

	outcome = round_session.outcome()


## Route Esc/right-click to cancel_controller.
func _unhandled_input(event: InputEvent) -> void:
	if cancel_controller.handle_input(event):
		get_viewport().set_input_as_handled()


## Derive viewport centering offset from grid extent + combatant hex positions.
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


## Six corner hexes at GRID_RADIUS used for centering computation.
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


## Non-null view nodes that subscribe to event_sink broadcasts.
func _presentation_event_subscribers() -> Array:
	var subscribers: Array = []
	for view in [
		status_panel_view, initiative_view, event_log_view, result_screen_view,
	]:
		if view != null:
			subscribers.append(view)
	return subscribers


## Thin delegate to _reaction_instance.resolve_enemy_dodge_step().
func _resolve_enemy_dodge_step(target, resolve_result: Dictionary, attacker_hex, legal_hexes: Array) -> void:
	await _reaction_instance.resolve_enemy_dodge_step(target, resolve_result, attacker_hex, legal_hexes)


## Thin shim to StrikeActionController.reachable_target_ids().
func _strike_reachable_target_ids() -> Array:
	return _controller("STRIKE").reachable_target_ids()


## Live ActionEconomy lookup: object-identity match first, display_id fallback.
## Ensures reactor's own budget is charged, never the attacker's.
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




## Route confirmed combine queue → combine_targeting_session.start().
func _on_combine_queue_built(queue) -> void:
	var entries: Array = queue.sorted_entries()
	var actor = _combat_query_service.find_combatant_by_id(queue.actor_id)
	combine_targeting_session.start(entries, actor, queue.context, queue)


## Post-combine UI refresh: verb bar, legal-move highlight, HP/budget readouts.
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


## Lazy TurnPresentationController getter (also called by VerbDispatchController via _main_scene).
func _turn_presentation():
	if _turn_presentation_instance == null:
		_turn_presentation_instance = TurnPresentationControllerClass.new(
			_round_session_holder,
			movement_input_controller,
			hex_grid_view,
			verb_bar_view,
			status_panel_view,
			Callable(_combat_query_service, "other_living_combatants")
		)
	return _turn_presentation_instance


## Live ROUND_NUMBER accessor — injected into ReactionController as Callable.
func _current_round_number() -> int:
	return ROUND_NUMBER



## Memoized deps dict for all ActionControllers (data-driven VERB_TABLE).
## Callables read state fresh each call; extra keys are harmless.
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
			"reaction": _reaction_instance,
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


## Live EnergyPool for caster via round_session (re-fetched each call, never stale).
func _energy_pool_for(caster):
	var session = round_session
	if session == null or caster == null:
		return null
	return session.get_energy_pool(caster)


## Memoized VERB_TABLE[verb_id].new(_verb_deps()) resolver.
func _controller(verb_id: String):
	if not _controllers.has(verb_id):
		_controllers[verb_id] = VERB_TABLE[verb_id].new(_verb_deps())
	return _controllers[verb_id]


## Living enemies (hp > 0) — reactor pool for Stride opportunistic strikes.
func _living_enemy_reactors() -> Array:
	return _combat_query_service.living_combatants(_enemies)


## Fresh _party read (never a snapshot) — injected as party_fn Callable.
func _current_party() -> Array:
	return _party


## Fresh _enemies read.
func _current_enemies() -> Array:
	return _enemies


## Authoritative initiative table from encounter.
func _current_turn_order():
	return encounter.get_turn_order() if encounter != null else null


## Delegate to TurnPresentationController.
func _on_active_actor_changed(combatant) -> void:
	_turn_presentation().on_active_actor_changed(combatant)


## Finish round: undecided→ROUND_NUMBER++ + rewire_session(); won→_on_combat_won().
## Relays to round_flow_controller.notify_round_concluded() at end.
func _on_round_over() -> void:
	if round_session == null:
		return

	round_session.finish()
	outcome = round_session.outcome()

	movement_input_controller.configure({}, [])
	# FEAT-004 / US-004/FR-001: re-gate the verb bar now that no actor/targets
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()

	if outcome == "":
		ROUND_NUMBER += 1
		# FEAT-003: rewire_session() is now a coroutine — awaited (see this
		await rewire_session()
	elif outcome == "won":
		_on_combat_won()
	elif outcome == "lost":
		# FEAT-009 placeholder (US-008): a genuinely unexpected/unhandled
		push_error("MainScene: 'lost' outcome handling is not yet implemented (FEAT-009 placeholder)")

	round_flow_controller.notify_round_concluded()


## UI-only cleanup on round_flow_controller.round_over (no game-state mutation).
func _on_round_flow_controller_round_over() -> void:
	if verb_bar_view != null:
		verb_bar_view.refresh_availability()


## Post-combat: mark encounter complete, remove enemy tokens, return to EXPLORATION.
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


## Re-drive TurnController after player ends turn.
func _on_end_turn_control_turn_ended(_result: Dictionary) -> void:
	if turn_controller == null or round_session == null:
		return
	# FEAT-006 (round-stall fix): when end_current_turn() above ALREADY drove
	if round_session.is_round_over():
		await _on_round_over()
		return
	await turn_controller.set_session(round_session, null, null, verb_bar_view)


## Post-move: clear highlights, refresh off-guard, re-invoke active_actor_changed.
func _after_successful_move() -> void:
	if hex_grid_view != null:
		hex_grid_view.set_selectable_hexes([])
	_refresh_off_guard_conditions()
	if round_session != null:
		# Phase C.3/C.4: on_active_actor_changed is instance-native (configures the
		_on_active_actor_changed(round_session.current_actor_entity())


## Callable seam: Dodge-Step selectable hex options for a combatant.
func _query_selectable_step_hexes(combatant_id: String) -> Array:
	var combatant = _combat_query_service.find_combatant_by_id(combatant_id)
	if combatant == null:
		return []
	return movement_input_controller.get_selectable_step_hexes_for(combatant, _combat_query_service.other_living_combatants(combatant))


## Order reactor candidates by initiative via ReactionController.
func _order_candidate_reactors_by_initiative(candidates: Array) -> Array:
	return _reaction_instance.order_candidate_reactors_by_initiative(candidates)


## Defensive ordering guard (FIND-224): assert+push_error if candidates violate initiative order.
## Returns true when consistent, false on violation.
func _assert_candidate_reactors_ordering(ordered_candidates: Array, turn_order: Array) -> bool:
	return _reaction_instance.assert_candidate_reactors_ordering(ordered_candidates, turn_order)


## Recompute Off-Guard for all combatants via Flanking rules.
## Writes into combatant.conditions (affects live Strike resolution) AND pushes to StatusPanelView.
func _refresh_off_guard_conditions() -> void:
	var living_party: Array = _combat_query_service.living_combatants(_party)
	var living_enemies: Array = _combat_query_service.living_combatants(_enemies)

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


## Test seam — called directly by test_intuition_*.gd and test_build_enemy_combatant_defenses.gd.
func _build_party_combatant(character_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	return _combatant_factory.build_party_combatant(character_path, hex_coord, combatant_id)


## Test seam — called directly by test_intuition_*.gd and test_build_enemy_combatant_defenses.gd.
func _build_enemy_combatant(enemy_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	return _combatant_factory.build_enemy_combatant(enemy_path, hex_coord, combatant_id)
