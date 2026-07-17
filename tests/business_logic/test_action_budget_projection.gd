extends GutTest
## tests/business_logic/test_action_budget_projection.gd — FEAT-009 (US-009 /
## FR-014, ADR-003)
##
## GUT test suite for the post-Strike action-budget projection: core/rules/
## round_events.gd's RoundEvents.AttackBroadcast now additionally carries
## actor_updated_action_budget ({remaining: int, spent: bool}), populated by
## core/application/resolve_action_use_case.gd immediately after the acting
## combatant's ActionEconomy.spend_action() call, and pushed by MainScene.gd
## (via the SAME ConsoleEventSinkAdapter.forward_to broadcast every other
## round event already flows through — no new event-routing is introduced)
## into presentation/status_panel_view.gd's update_action_budget() — a pure,
## read-only projection.
##
## Verifies (test_criteria):
##   1. StatusPanelView.action_budget_remaining decreases by exactly 1 and
##      Spent reflects it after a Strike resolves.
##   2. StatusPanelView performs no independent recomputation — source-
##      inspection guardrail: status_panel_view.gd never calls into
##      core/rules/action_economy.gd directly, only reads the value pushed
##      to it.
##   3. update_action_budget() no-ops and logs a warning (push_warning(),
##      never throws) when actor_updated_action_budget is missing from the
##      event.
##
## Criterion 1 is exercised at two levels, per this codebase's established
## convention (see tests/business_logic/test_result_screen_lock.gd /
## tests/unit/test_main_scene_interactive_wiring.gd):
##   (a) a direct-construction unit-level check driving
##       ResolveActionUseCase.resolve() -> StatusPanelView.on_round_event(),
##       proving the exact "decreases by exactly 1" arithmetic in isolation.
##   (b) a full MainScene.gd composition-root boot, driving a REAL Strike via
##       $StrikeActionControl.select_target() end-to-end, proving the feature
##       actually works when the application runs (not just against mocks).

const StatusPanelViewScene: PackedScene = preload("res://presentation/status_panel_view.tscn")
const ResolveActionUseCaseClass         = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass                = preload("res://core/rules/action_economy.gd")
const RoundEventsClass                  = preload("res://core/rules/round_events.gd")
const CombatantClass                    = preload("res://core/domain/combatant.gd")

const STATUS_PANEL_VIEW_SOURCE_PATH: String = "res://presentation/status_panel_view.gd"
const MAIN_SCENE_PATH: String = "res://MainScene.tscn"


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0

	func _init(values: Array) -> void:
		_values = values

	func roll(_dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


var _panel = null


func before_each() -> void:
	_panel = StatusPanelViewScene.instantiate()
	add_child_autofree(_panel)


func _sample_view_models() -> Array:
	return [
		{
			"combatant_id": "player_0",
			"name": "Titus",
			"hp_current": 10,
			"hp_max": 10,
			"stamina_current": 6,
			"stamina_max": 6,
			"action_budget_remaining": 7,
			"spent": false,
			"conditions": [],
		},
		{
			"combatant_id": "enemy_0",
			"name": "Skeleton",
			"hp_current": 8,
			"hp_max": 8,
			"stamina_current": 0,
			"stamina_max": 0,
			"action_budget_remaining": 7,
			"spent": false,
			"conditions": [],
		},
	]


func _attacker():
	return CombatantClass.from_dict({
		"name": "Titus",
		"combatant_id": "player_0",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	})


func _target():
	return CombatantClass.from_dict({"name": "Skeleton", "combatant_id": "enemy_0", "hp_current": 8, "ac": 10})


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a: direct-construction check — action_budget_remaining
# decreases by exactly 1 and Spent reflects it after a Strike resolves.
# ══════════════════════════════════════════════════════════════════════════

func test_action_budget_remaining_decreases_by_exactly_one_after_strike_resolves() -> void:
	_panel.load_combatants(_sample_view_models())
	assert_eq(
		_panel.get_status("player_0").get("action_budget_remaining"), 7,
		"sanity check: the attacker starts with a full 7-action budget"
	)

	var rng_port   = ScriptedRandomNumberPort.new([12, 4])  # attack roll hits, damage roll
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	var action_economy = ActionEconomyClass.new()

	var result: Dictionary = use_case.resolve(_attacker(), action_economy, _target(), "Strike", 1, 0)
	assert_true(result.get("resolved", false), "fixture assumption: the Strike must resolve")

	# The composition root (MainScene.gd) forwards every emitted event to
	# every subscribed Presentation projection's on_round_event() through the
	# SAME broadcast mechanism (ConsoleEventSinkAdapter.forward_to) — this
	# mirrors that exact call, without needing a full MainScene boot.
	_panel.on_round_event(result["event"])

	assert_eq(
		_panel.get_status("player_0").get("action_budget_remaining"), 6,
		"action_budget_remaining must decrease by exactly 1 after one resolved Strike"
	)
	assert_eq(
		action_economy.get_remaining(), 6,
		"fixture cross-check: the domain ActionEconomy itself also reports 6 remaining"
	)
	assert_eq(
		_panel.get_status("player_0").get("spent"), action_economy.is_spent(),
		"Spent must reflect the SAME value the domain ActionEconomy reports (false after only 1 of 7 actions spent)"
	)
	assert_false(_panel.get_status("player_0").get("spent"), "1 of 7 actions spent must not yet flag Spent")


func test_action_budget_remaining_and_spent_true_after_seventh_strike() -> void:
	_panel.load_combatants(_sample_view_models())

	var action_economy = ActionEconomyClass.new()
	var last_event = null
	# FEAT-003 (ADR-103): only one spend_action() succeeds per turn, so each
	# of these 7 Strikes simulates its own turn boundary (start_of_turn())
	# against the same shared per-round budget (AC-4 interleaving).
	for i in range(7):
		action_economy.start_of_turn()
		var rng_port   = ScriptedRandomNumberPort.new([12, 4])
		var event_sink = FakeEventSinkPort.new()
		var history    = FakeRoundHistoryPort.new()
		var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
		var target = _target()  # a fresh, undefeated target for each iteration
		var result: Dictionary = use_case.resolve(_attacker(), action_economy, target, "Strike", 1, i)
		assert_true(result.get("resolved", false), "fixture assumption: each of the 7 Strikes must resolve")
		last_event = result["event"]

	_panel.on_round_event(last_event)

	assert_eq(
		_panel.get_status("player_0").get("action_budget_remaining"), 0,
		"action_budget_remaining must reflect 0 once all 7 actions are spent"
	)
	assert_true(
		_panel.get_status("player_0").get("spent"),
		"Spent must reflect true once the acting combatant's ActionBudget is exhausted"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b: full MainScene.gd boot — a real Strike via
# `_verb_registry.execute("STRIKE", target_id)` pushes an updated
# action-budget snapshot into $StatusPanelView through the real
# composition-root wiring (FEAT-006: Strike no longer has a dedicated
# strike_action_control node -- it is driven solely through the verb
# registry now).
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


func test_main_scene_pushes_updated_action_budget_into_status_panel_view_after_strike() -> void:
	var instance = _boot_main_scene()

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	assert_ne(actor_id, "", "fixture assumption: the first active actor has a stable combatant_id")

	var before_status: Dictionary = instance.status_panel_view.get_status(actor_id)
	var before_remaining: int = before_status.get("action_budget_remaining", -1)
	assert_eq(before_remaining, 7, "fixture assumption: the acting combatant starts with a full 7-action budget")

	var target_ids: Array = instance._verb_registry.enter_selection("STRIKE").get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the prologue's first actor has at least one in-reach target")

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(result.get("resolved", false), "the real resolve_action_use_case must resolve the Strike")

	var after_status: Dictionary = instance.status_panel_view.get_status(actor_id)
	assert_eq(
		after_status.get("action_budget_remaining"), before_remaining - 1,
		"MainScene must push the post-resolution snapshot into StatusPanelView, decrementing action_budget_remaining by exactly 1"
	)
	assert_eq(
		after_status.get("spent"), false,
		"1 of 7 actions spent must not yet flag Spent on the real, MainScene-driven pipeline"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: StatusPanelView performs NO independent recomputation —
# source-inspection guardrail: status_panel_view.gd never calls into
# core/rules/action_economy.gd directly, only reads the pushed value.
# ══════════════════════════════════════════════════════════════════════════

func _read_status_panel_view_source() -> String:
	var file := FileAccess.open(STATUS_PANEL_VIEW_SOURCE_PATH, FileAccess.READ)
	assert_not_null(file, "presentation/status_panel_view.gd must be readable to verify its source")
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_never_preloads_action_economy_gd() -> void:
	var source: String = _read_status_panel_view_source()
	assert_eq(
		source.findn("preload(\"res://core/rules/action_economy.gd\")"),
		-1,
		"status_panel_view.gd must never preload() core/rules/action_economy.gd — read-only projection (ADR-003)"
	)


func test_source_never_calls_action_economy_methods_directly() -> void:
	var source: String = _read_status_panel_view_source()
	var forbidden_calls: Array = [".spend_action(", ".spend_reaction(", ".get_remaining(", ".is_spent("]
	for call in forbidden_calls:
		assert_eq(
			source.find(call), -1,
			"status_panel_view.gd must never call '%s' — it only reads a value pushed to it, never recomputes the budget (ADR-003)" % call
		)


func test_source_never_references_action_economy_class_identifier() -> void:
	var source: String = _read_status_panel_view_source()
	assert_eq(
		source.find("ActionEconomy"),
		-1,
		"status_panel_view.gd must never reference the ActionEconomy class identifier directly — read-only projection (ADR-003)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: update_action_budget() no-ops and logs a warning (never
# throws) when actor_updated_action_budget is missing from the event.
# ══════════════════════════════════════════════════════════════════════════

func test_update_action_budget_noops_when_field_missing_from_dictionary_event() -> void:
	_panel.load_combatants(_sample_view_models())

	# No exception/crash: calling update_action_budget() with an event that
	# carries no actor_updated_action_budget key must not throw.
	_panel.update_action_budget("player_0", {"attacker_name": "Titus"})

	assert_eq(
		_panel.get_status("player_0").get("action_budget_remaining"), 7,
		"update_action_budget() must no-op (leave action_budget_remaining unchanged) when the field is missing"
	)
	assert_eq(
		_panel.get_status("player_0").get("spent"), false,
		"update_action_budget() must no-op (leave Spent unchanged) when the field is missing"
	)


func test_update_action_budget_noops_when_field_is_null_on_production_attack_event() -> void:
	_panel.load_combatants(_sample_view_models())

	# A production RoundEvents.AttackBroadcast constructed without the additive
	# 10th constructor argument (every pre-FEAT-009 call site) defaults
	# actor_updated_action_budget to null -- this must be treated identically
	# to "missing from the event", never thrown.
	var legacy_shaped_event = RoundEventsClass.AttackBroadcast.new(
		1, "Titus", "Skeleton", 17, "ac", 14, true, false, 3
	)
	_panel.update_action_budget("player_0", legacy_shaped_event)

	assert_eq(
		_panel.get_status("player_0").get("action_budget_remaining"), 7,
		"update_action_budget() must no-op when actor_updated_action_budget defaults to null"
	)


func test_update_action_budget_does_not_throw_for_unknown_actor_id() -> void:
	_panel.load_combatants(_sample_view_models())

	# An actor_id with no loaded row must also be a safe no-op, matching
	# every other unknown-combatant_id contract on this class.
	_panel.update_action_budget("does_not_exist", {"actor_updated_action_budget": {"remaining": 3, "spent": false}})

	assert_eq(_panel.get_row_count(), 2, "an update for an unknown actor_id must not create/remove rows")


func test_source_logs_push_warning_for_missing_actor_updated_action_budget() -> void:
	# GUT cannot reliably capture push_warning() output on this Godot
	# version (see tests/test_encounter_round_loop.gd's file-level note on
	# the same limitation) -- a source-inspection check stands in, mirroring
	# that established convention.
	var source: String = _read_status_panel_view_source()
	assert_true(
		source.contains("push_warning") and source.contains("update_action_budget"),
		"status_panel_view.gd must log a push_warning() when actor_updated_action_budget is missing (FEAT-009)"
	)


func test_update_action_budget_applies_pushed_dictionary_directly_without_throwing() -> void:
	_panel.load_combatants(_sample_view_models())

	_panel.update_action_budget("player_0", {"actor_updated_action_budget": {"remaining": 2, "spent": false}})

	assert_eq(_panel.get_status("player_0").get("action_budget_remaining"), 2)
	assert_eq(_panel.get_status("player_0").get("spent"), false)
