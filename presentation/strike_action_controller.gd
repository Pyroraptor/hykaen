extends "res://presentation/action_controller.gd"

## StrikeActionController — the STRIKE verb (FEAT-004/005/006/008, iteration K).
## The richest verb: availability/enter_selection gate on the in-reach target set;
## execute() rejects a non-reachable/stale target id, resolves the Strike through
## resolve_action_use_case.resolve_reactive() (which opens the enemy target's
## PreHit/OnHit reaction windows synchronously via the injected reaction chooser),
## reflects any enemy reaction budget spend on the status panel, records + rich-
## renders exactly one combat-log row for the attack, and finally lets the enemy
## target take its own Dodge-Step (delegated to the injected ReactionController).
##
## Concrete ActionController subclass (presentation/action_controller.gd),
## extracted from MainScene's _verb_bar_strike_* + _strike_* targeting helpers
## (composition-root de-bloat, 2026-07-10). The strike-targeting helpers and the
## per-attack event-id counter move in here; resolve_action_use_case /
## event_log_view / status_panel_view / enemy_reaction_chooser are injected refs;
## _action_economy_for, ROUND_NUMBER, the living-enemy pool, and the step-hex query
## are injected Callables (MainScene still owns encounter/_enemies); the enemy
## Dodge-Step is delegated to the injected ReactionController. MainScene keeps thin
## _verb_bar_strike_* + _strike_reachable_target_ids shims (the ones tests and the
## VerbBarRegistry call).

const HexMathClass                = preload("res://core/geometry/hex_math.gd")
const AttackEventClass            = preload("res://core/log/attack_event.gd")
const RenderCombatLogUseCaseClass = preload("res://core/application/render_combat_log_use_case.gd")

const ACTION_NAME_STRIKE: String = "Strike"

var _resolve_action_use_case
var _event_log_view
var _status_panel_view
var _enemy_reaction_chooser
var _reaction
var _action_economy_fn: Callable
var _round_number_fn: Callable
var _living_enemies_fn: Callable
var _query_step_hexes_fn: Callable

## Per-attack event-id counter (moved in from MainScene): the only mutable state
## strike resolution owns, so it lives with the verb it belongs to.
var _player_attack_event_id_counter: int = 0


## Reads (data-driven verb table, 2026-07-11 — see action_controller.gd's _init
## doc): `resolve_action_use_case`, `event_log_view`, `status_panel_view`,
## `enemy_reaction_chooser`, the shared `reaction` ReactionController (also used by
## Stride), and the Callables `action_economy_for`, `current_round_number`,
## `living_enemy_reactors` (the living-enemy pool this verb reads as its target
## candidates), `query_selectable_step_hexes`. `session_holder` is consumed by
## super().
func _init(deps: Dictionary) -> void:
	super(deps)
	_resolve_action_use_case = deps.get("resolve_action_use_case", null)
	_event_log_view = deps.get("event_log_view", null)
	_status_panel_view = deps.get("status_panel_view", null)
	_enemy_reaction_chooser = deps.get("enemy_reaction_chooser", null)
	_reaction = deps.get("reaction", null)
	_action_economy_fn = deps.get("action_economy_for", Callable())
	_round_number_fn = deps.get("current_round_number", Callable())
	_living_enemies_fn = deps.get("living_enemy_reactors", Callable())
	_query_step_hexes_fn = deps.get("query_selectable_step_hexes", Callable())


func availability() -> bool:
	var action_economy = current_action_economy()
	var can_act: bool = action_economy.can_take_action() if action_economy != null else false
	return can_act and reachable_target_ids().size() > 0


func enter_selection() -> Dictionary:
	return {"verb_id": "STRIKE", "candidate_targets": reachable_target_ids(), "candidate_hexes": []}


func execute(selection = null) -> Dictionary:
	var session = _session()
	if session == null or _resolve_action_use_case == null:
		return {"ok": false}

	# Phase C.3/C.4: target + actor are LIVE Combatant instances (the same the
	# container holds), so resolve_reactive()'s take_damage()/spend land on them
	# by reference. _find_reachable_target() returns null (not {}) when not found.
	var target = _find_reachable_target(str(selection))
	if target == null:
		return {"ok": false, "resolved": false, "error": "ERR_TARGET_NOT_SELECTABLE"}

	var actor = session.current_actor_entity()
	var action_economy = session.current_action_economy()

	# The enemy target's OWN live ActionEconomy — so a chosen reaction genuinely
	# spends a budget point and the RESERVE gate reads real data. May be null (a
	# test double); resolve_reactive()/resolution.gd degrade safely then.
	var target_action_economy = _action_economy_fn.call(target)
	var target_budget_before: int = target_action_economy.get_remaining() if target_action_economy != null else -1

	# Capture the append-order index event_log_view is ABOUT to append at (inside
	# resolve_reactive()'s synchronous emit) BEFORE resolving, so it can be
	# overwritten in place with the rich rendering afterward — keeping the row's
	# chronological position even when a killing blow also emits a defeat event.
	var pending_entry_index: int = _event_log_view.get_entry_count() if _event_log_view != null else -1

	var result: Dictionary = _resolve_action_use_case.resolve_reactive(
		actor, action_economy, target, ACTION_NAME_STRIKE, _round_number_fn.call(), 0,
		target_action_economy, _enemy_reaction_chooser
	)

	# Reflect the enemy's own reaction budget spend (if any) on the status panel,
	# reusing the same on_verb_action_budget_changed() seam a Stride's spend uses.
	if target_action_economy != null and _status_panel_view != null:
		var target_budget_after: int = target_action_economy.get_remaining()
		if target_budget_after != target_budget_before:
			var target_id: String = target.display_id()
			_status_panel_view.on_verb_action_budget_changed(
				target_id, target_budget_after, target_action_economy.is_spent()
			)

	# Build an AttackEvent from result["event"] (the SAME instance resolve_reactive
	# emitted, never re-derived), record it, and overwrite the plain row in place
	# with the rich rendering — so exactly one rich row is visible for this Strike.
	if _event_log_view != null and pending_entry_index != -1 and result.get("resolved", false):
		var resolved_attack_event = result.get("event", null)
		if resolved_attack_event != null:
			_player_attack_event_id_counter += 1
			var attack_event_id: String = "R%d-P%d" % [_round_number_fn.call(), _player_attack_event_id_counter]

			var weapon: Dictionary = actor.weapon
			var structured_attack_event = AttackEventClass.new(
				attack_event_id,
				_round_number_fn.call(),
				actor.display_id(),
				target.display_id(),
				weapon.get("weapon_id", weapon.get("name", "")),
				resolved_attack_event.roll,
				resolved_attack_event.hit,
				resolved_attack_event.crit,
				resolved_attack_event.damage_final,
				resolved_attack_event.damage_final,
				result.get("on_hit_suppressed", false),
				false
			)

			_event_log_view.record_attack(structured_attack_event)

			# Pair this Strike's reaction outcome to the just-recorded AttackEvent;
			# window_id matches which window the choice belongs to (Dodge/Steel are
			# PreHitAvoidance; Parry/Block are OnHitMitigation).
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
				Callable(_event_log_view, "record_reaction")
			)

			var rich_text: String = _event_log_view.render_attack_entry(attack_event_id)
			_event_log_view.overwrite_entry_as_rich(pending_entry_index, rich_text, attack_event_id)

	# The enemy target's OWN Dodge-Step on a successful reactive Dodge — resolved
	# synchronously (no player pop-up) by the ReactionController.
	await _reaction.resolve_enemy_dodge_step(
		target, result, actor.hex_coord, _query_step_hexes_fn.call(_target_id(target))
	)

	return result


## reachable_target_ids() -> Array — the target_id of every currently in-reach
## Strike target, in the same order _reachable_targets() returns them. Public
## because MainScene's _strike_reachable_target_ids() shim (called by tests) and
## availability()/enter_selection() read it.
func reachable_target_ids() -> Array:
	var ids: Array = []
	for target in _reachable_targets():
		ids.append(_target_id(target))
	return ids


func _reachable_targets() -> Array:
	if _session() == null:
		return []

	# Phase C.3/C.4: actor + candidates are LIVE Combatant instances (candidates
	# from _living_enemies_fn are the container's _enemies by reference, so the
	# selected target take_damage()s correctly in execute()). null actor = no turn.
	var actor = current_actor_entity()
	if actor == null:
		return []
	var actor_hex = actor.hex_coord
	if actor_hex == null:
		return []

	var candidates: Array = _living_enemies_fn.call()
	var in_reach: Array = []

	if _actor_is_ranged(actor):
		var range_hexes: int = actor.weapon.get("range_hexes", 1)
		for target in candidates:
			var target_hex = target.hex_coord
			if target_hex != null and HexMathClass.hex_distance(actor_hex, target_hex) <= range_hexes:
				in_reach.append(target)
		return in_reach

	var neighbors: Array = HexMathClass.hex_neighbors(actor_hex)
	for target in candidates:
		var target_hex = target.hex_coord
		if target_hex == null:
			continue
		for neighbor in neighbors:
			if neighbor.equals(target_hex):
				in_reach.append(target)
				break
	return in_reach


func _actor_is_ranged(actor) -> bool:
	return actor.weapon.has("range_hexes")


func _target_id(target) -> String:
	return target.display_id()


## _find_reachable_target(target_id) -> Combatant or null — looks up target_id
## ONLY among the currently in-reach targets (never the wider enemy list), the
## enforcement point ensuring a non-reachable target can never be selected even
## by id. Returns null (never {}) when not found — the live-instance "no target"
## sentinel execute() checks via `== null`.
func _find_reachable_target(target_id: String):
	for target in _reachable_targets():
		if _target_id(target) == target_id:
			return target
	return null
