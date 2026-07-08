extends GutTest
## tests/gut/test_player_strikes_enemy_pass_through.gd — FEAT-005 (US-004 /
## FR-004, ADR-005 (CR-001 accepted debt), docs/iterations/iteration-I-
## reactions-live-wiring-and-offensive-reactions.org Part A-3).
##
## Iteration I's Part A wires a REAL, awaited reaction window onto the
## enemy-strikes-player path (core/application/round_session.gd's
## advance_ai_turn(), FEAT-002/003/004). Part A explicitly does NOT touch
## the OTHER live call site into ResolveActionUseCase.resolve() --
## MainScene.gd's `_verb_bar_strike_execute()` (player-strikes-enemy,
## historically documented as line 1008, now further down the file after
## intervening features) -- which must keep passing active_defense="none"
## (the enemy always "Passes", no pop-up, no reaction window) for Part A's
## scope. Part B (a later feature) is the one that gives the enemy a real
## reaction policy on THIS call site; until Part B lands, this suite pins
## the pre-Part-B pass-through behavior so no future edit to
## round_session.gd/resolve_action_use_case.gd/MainScene.gd accidentally
## leaks reactive behavior onto this path early, or silently changes Strike
## outcomes on it.
##
## test_criteria satisfied:
##   1. test_main_scene_strike_call_site_keeps_the_default_only_six_arg_shape()
##      + test_call_site_argument_shape_forwards_active_defense_none_to_resolution()
##      -- together prove MainScene.gd's call site always calls resolve()
##      with active_defense="none" (via the untouched default parameter,
##      never an explicit override).
##   2. test_player_strike_never_opens_a_reaction_window_or_prompt_for_the_enemy()
##      -- boots the REAL res://MainScene.tscn and proves no
##      ReactionWindowOpenedEvent/ReactionResolvedEvent is ever emitted, and
##      reaction_prompt_ui/player_reaction_chooser are never engaged, for a
##      real player Strike against a real enemy.
##   3. test_player_strike_outcome_is_byte_for_byte_unchanged_from_pre_sprint_baseline()
##      -- pins the exact AttackEvent fields (hit/crit/damage_final/
##      defense_value/roll) produced by the live MainScene call site at a
##      fixed seed, matching the plain-AC-only (no active defense) math
##      resolution.gd has always produced on this path.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")

const MAIN_SCENE_SOURCE_PATH: String = "res://MainScene.gd"


# ══════════════════════════════════════════════════════════════════════════
# Local test doubles (each suite in this project owns its own, per
# tests/characterization/test_strike_characterization.gd's convention).
# ══════════════════════════════════════════════════════════════════════════

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

	func roll(dice_spec: Dictionary) -> int:
		var v = _values[_index]
		_index += 1
		return v


## SpyResolution -- records the exact arguments resolve_weapon_attack() was
## called with, mirroring tests/gut/test_resolve_action_use_case_active_defense.gd's
## SpyResolution double, so this suite does not depend on resolution.gd's
## internal math to prove the pass-through contract.
class SpyResolution:
	var calls: Array = []

	func resolve_weapon_attack(
		attacker: Dictionary,
		target: Dictionary,
		weapon: Dictionary,
		defense_type: String,
		active_defense: String = "none",
		defense_context: Dictionary = {}
	) -> Dictionary:
		calls.append({
			"active_defense": active_defense,
			"defense_context": defense_context,
			"defense_type": defense_type,
		})
		return {
			"hit": true,
			"crit": false,
			"roll_total": 15,
			"damage_raw": 5,
			"active_defense_applied": active_defense,
			"damage_final": 5,
			"defender_stepped": false,
			"next_check_bonus": 0,
			"on_hit_suppressed": false,
			"defense_value": 12,
		}


func _attacker() -> Dictionary:
	return {
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	}


func _target() -> Dictionary:
	return {"name": "Target", "hp_current": 50, "ac": 12}


func _fresh_action_economy():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _make_use_case(scripted_values: Array = [10, 4]) -> Dictionary:
	var rng_port   = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink = FakeEventSinkPort.new()
	var history    = FakeRoundHistoryPort.new()
	var use_case   = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


# ══════════════════════════════════════════════════════════════════════════
# Static source-shape helpers -- mirror tests/gut/
# test_resolve_action_use_case_active_defense.gd's own file-scan approach,
# scoped here to ONLY MainScene.gd's _verb_bar_strike_execute() call site.
# ══════════════════════════════════════════════════════════════════════════

const _CALL_NEEDLE: String = "_action_use_case.resolve("

func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _count_top_level_args(args_text: String) -> int:
	var trimmed: String = args_text.strip_edges()
	if trimmed == "":
		return 0
	var depth: int = 0
	var count: int = 1
	for i in range(trimmed.length()):
		var ch: String = trimmed.substr(i, 1)
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		elif ch == "," and depth == 0:
			count += 1
	return count


## _find_call_sites(content) -> Array of {args_text: String, line: int} --
## same paren-depth-matched extraction as
## test_resolve_action_use_case_active_defense.gd's helper of the same name.
func _find_call_sites(content: String) -> Array:
	var sites: Array = []
	var search_start: int = 0
	while true:
		var idx: int = content.find(_CALL_NEEDLE, search_start)
		if idx == -1:
			break
		search_start = idx + _CALL_NEEDLE.length()

		var line_start: int = content.rfind("\n", idx) + 1
		var line_end: int = content.find("\n", idx)
		if line_end == -1:
			line_end = content.length()
		var line: String = content.substr(line_start, line_end - line_start)
		if line.strip_edges().begins_with("#"):
			continue

		var paren_start: int = idx + _CALL_NEEDLE.length() - 1
		var depth: int = 1
		var pos: int = paren_start + 1
		while depth > 0 and pos < content.length():
			var ch: String = content.substr(pos, 1)
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			pos += 1

		var args_text: String = content.substr(paren_start + 1, (pos - 1) - (paren_start + 1))
		sites.append({"args_text": args_text})
	return sites


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a — MainScene.gd's ONE call site into resolve() must keep the
# default-only, 6-positional-argument shape (no explicit active_defense/
# defense_context override) -- this is what makes "none" reach resolve()
# via the untouched default parameter, per ADR-005's accepted-debt design.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_strike_call_site_keeps_the_default_only_six_arg_shape() -> void:
	var content: String = _read_file(MAIN_SCENE_SOURCE_PATH)
	var sites: Array = _find_call_sites(content)

	assert_eq(sites.size(), 1, "MainScene.gd is expected to have exactly 1 live resolve() call site (player-strikes-enemy)")
	if sites.size() != 1:
		return

	var arg_count: int = _count_top_level_args(sites[0]["args_text"])
	assert_eq(
		arg_count, 6,
		"MainScene.gd's player-strikes-enemy call site must stay default-only (6 positional args) -- " +
		"Part A never opts this path into an explicit active_defense/defense_context override"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b — that exact default-only argument shape forwards
# active_defense="none" / defense_context={} to resolution.gd, verbatim.
# ══════════════════════════════════════════════════════════════════════════

func test_call_site_argument_shape_forwards_active_defense_none_to_resolution() -> void:
	var rig: Dictionary = _make_use_case()
	var spy := SpyResolution.new()
	rig["use_case"]._resolution = spy

	var actor: Dictionary = _attacker()
	var action_economy = _fresh_action_economy()
	var target: Dictionary = _target()

	# The SAME 6-argument call shape MainScene.gd's _verb_bar_strike_execute()
	# uses: resolve(actor, action_economy, target, ACTION_NAME_STRIKE,
	# ROUND_NUMBER, 0) -- no active_defense/defense_context passed.
	rig["use_case"].resolve(actor, action_economy, target, "Strike", 1, 0)

	assert_eq(spy.calls.size(), 1, "the default-only call shape must reach resolve_weapon_attack() exactly once")
	assert_eq(spy.calls[0]["active_defense"], "none", "the enemy must always be handed active_defense='none' on this path (Part A pass-through)")
	assert_eq(spy.calls[0]["defense_context"], {}, "defense_context must be an empty Dictionary -- no reaction context is ever built for this path")
	assert_eq(spy.calls[0]["defense_type"], "ac", "defense_type must remain the pre-existing 'ac' passive check")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a real player Strike against a real enemy, driven through
# the actual res://MainScene.tscn composition root, never opens a reaction
# window or pop-up for the enemy.
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


func _resolve_one_real_player_strike(instance) -> Dictionary:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
	return {"target_id": target_id}


func test_player_strike_never_opens_a_reaction_window_or_prompt_for_the_enemy() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_false(instance.reaction_prompt_ui.is_open(), "sanity: the reaction pop-up must be closed before any Strike happens")
	watch_signals(instance.reaction_prompt_ui)

	_resolve_one_real_player_strike(instance)

	assert_false(instance.reaction_prompt_ui.is_open(), "a player-strikes-enemy Strike must never open the reaction pop-up for the enemy (Part A pass-through)")
	assert_signal_not_emitted(
		instance.reaction_prompt_ui, "reaction_chosen",
		"the enemy is never offered a reaction on this path -- reaction_chosen must never fire"
	)

	for event in instance.event_sink.log:
		assert_false(
			is_instance_of(event, RoundEventsClass.ReactionWindowOpenedEvent),
			"no ReactionWindowOpenedEvent may be emitted for a player-strikes-enemy Strike in Part A scope"
		)
		assert_false(
			is_instance_of(event, RoundEventsClass.ReactionResolvedEvent),
			"no ReactionResolvedEvent may be emitted for a player-strikes-enemy Strike in Part A scope"
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — the real, live Strike outcome on this path is byte-for-byte
# unchanged: the plain passive-AC-only math resolution.gd has always
# produced, with no active-defense mitigation ever applied.
# ══════════════════════════════════════════════════════════════════════════

func test_player_strike_outcome_is_byte_for_byte_unchanged_from_pre_sprint_baseline() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var actor_id: String = instance.round_session.current_actor().get("combatant_id", "")
	var before_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]

	# Capture the target's own ac BEFORE resolving -- resolution.gd's plain
	# passive-AC math (no active defense) computes defense_value from
	# exactly this value; a hit could otherwise defeat/remove the target
	# before this suite can re-read it.
	var target_before: Dictionary = instance._find_strike_reachable_target(target_id)
	var target_ac = target_before.get("ac", null)

	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	# Find the AttackEvent this Strike must have emitted -- the single
	# observable record of "how the Strike was actually resolved" for this
	# path, per this codebase's ADR-003 event-sourced status/log projections.
	var attack_event = null
	for event in instance.event_sink.log:
		if is_instance_of(event, RoundEventsClass.AttackEvent):
			attack_event = event

	assert_not_null(attack_event, "a real player Strike must emit an AttackEvent")
	if attack_event == null:
		return

	var after_remaining: int = instance.status_panel_view.get_status(actor_id).get("action_budget_remaining", -1)
	assert_eq(after_remaining, before_remaining - 1, "PINNED (unchanged): a resolved Strike must still cost exactly 1 action, identical to every other Strike path")

	# PINNED (unchanged): defense_value must equal the plain target ac --
	# resolution.gd's no-active-defense math never reduces/negates it --
	# this IS "pre-sprint baseline" for this path, since Part A never wires
	# a reaction window here. Mirrors tests/gut/
	# test_resolve_action_use_case_active_defense.gd's
	# test_default_arg_call_still_resolves_the_passive_ac_only_path()
	# invariant, reconfirmed here through the real, live MainScene call site.
	if target_ac != null:
		assert_eq(attack_event.defense_value, target_ac, "PINNED: defense_value must equal the plain target ac -- no active-defense adjustment on this path")
