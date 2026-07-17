extends GutTest
## tests/gut/test_resolve_action_use_case_active_defense.gd
##
## GUT suite for FEAT-001 (US-001 / FR-001 / NFR-001, ADR-001): threading
## active_defense/defense_context trailing parameters through
## core/application/resolve_action_use_case.gd's resolve() (public entry
## point) and its internal _resolve_strike() helper, replacing the
## previously-hardcoded "none", {} passed into
## core/rules/resolution.gd's resolve_weapon_attack().
##
## This is the data/domain-boundary foundation the rest of the reactive-
## defense steel thread depends on (round_session.gd's future reaction
## window wiring, US-002+) -- resolve()/_resolve_strike() themselves gain
## NO new branching logic; they are a pure, verbatim pass-through.
##
## Validates (test_criteria):
##   1. tests/characterization/test_strike_characterization.gd continues to
##      pass byte-for-byte -- exercised by the project's normal full-suite
##      run, not duplicated here.
##   2. active_defense/defense_context are forwarded UNCHANGED from
##      resolve() through _resolve_strike() into resolve_weapon_attack().
##   3. Default-arg calls (no active_defense/defense_context supplied)
##      produce output identical to explicitly passing the pre-existing
##      "none"/{} defaults -- the backward-compat default-safety contract.
##   4. An audit of every existing production call site into resolve()
##      confirms none of them pass active_defense/defense_context yet
##      (default-only invocation) -- opting into reactive mode is reserved
##      for a later feature in this steel thread.
##
##      UPDATE (FEAT-004, US-003 / FR-003, ADR-004): that later feature has
##      now landed -- core/application/round_session.gd's enemy-Strikes-
##      player call site (inside advance_ai_turn()) legitimately threads a
##      resolved active_defense/defense_context into resolve(). Criterion 4's
##      audit below is updated (not removed) to reflect this: exactly ONE
##      production call site (round_session.gd's reactive Strike branch) may
##      now exceed the 7-argument default-only shape, capped at 9 args
##      (active_combatant_id + active_defense + defense_context). Every OTHER
##      production call site -- MainScene.gd's player-Strike path, and
##      round_session.gd's OWN separate autonomous-path call site inside
##      run_autonomous_to_completion(), which never offers a reaction --
##      must remain default-only, so this audit still catches an
##      undocumented/accidental new reactive call site anywhere else.
##
##      UPDATE (iteration K FEAT-004, US-004, ADR-004): MainScene.gd's
##      player-Strike path no longer calls resolve() at all -- it now calls
##      the SEPARATE resolve_reactive() entry point (core/application/
##      resolve_action_use_case.gd) so the enemy target genuinely reacts via
##      infrastructure/ai_reaction_policy.gd's AIReactionPolicy,
##      synchronously (no pop-up). resolve()'s own signature/behavior is
##      completely untouched by this -- resolve_reactive() is a deliberately
##      separate public method precisely so this criterion's audit (and
##      every other resolve()-call-site pin in this file) needed no further
##      changes beyond MainScene.gd now contributing zero sites to it (see
##      test_audit_finds_the_two_known_live_call_sites() below).

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")


# ── Local test doubles (each suite in this project owns its own, per
#    tests/characterization/test_strike_characterization.gd's convention) ───

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


## SpyResolution -- a duck-typed double standing in for core/rules/
## resolution.gd's Resolution instance. It never computes real Strike math;
## it only RECORDS the exact arguments it was called with, so the pass-
## through contract (criterion #2) can be asserted precisely without
## depending on resolution.gd's internal math. resolve_action_use_case.gd
## stores its Resolution instance in the plain (non-enforced-private)
## `_resolution` script variable, which this suite substitutes after
## construction -- the standard seam this codebase uses for this kind of
## collaborator swap (mirrors _PortRNGAdapter injection at _init() time).
class SpyResolution:
	var calls: Array = []

	func resolve_weapon_attack(
		attacker,
		target,
		weapon: Dictionary,
		defense_type: String,
		active_defense: String = "none",
		defense_context: Dictionary = {}
	) -> Dictionary:
		calls.append({
			"attacker": attacker,
			"target": target,
			"weapon": weapon,
			"defense_type": defense_type,
			"active_defense": active_defense,
			"defense_context": defense_context,
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


# ── Shared fixtures ──────────────────────────────────────────────────────────

func _attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	})


func _target():
	return CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 12})


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


## _make_spied_use_case() -> Dictionary -- a use case whose internal
## `_resolution` collaborator has been swapped for a SpyResolution double,
## so every _resolve_strike()/resolve_weapon_attack() call is recorded
## verbatim.
func _make_spied_use_case() -> Dictionary:
	var rig: Dictionary = _make_use_case()
	var spy := SpyResolution.new()
	rig["use_case"]._resolution = spy
	rig["spy"] = spy
	return rig


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: active_defense/defense_context forwarded UNCHANGED from
# resolve() through _resolve_strike() into resolve_weapon_attack().
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_forwards_active_defense_and_defense_context_verbatim() -> void:
	var rig: Dictionary = _make_spied_use_case()
	var defense_context: Dictionary = {
		"open_space_available": false,
		"blocking_weapon": {"block_value": 3, "damage_die": 6},
		"action_economy": _fresh_action_economy(),
	}

	rig["use_case"].resolve(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0, "", "block", defense_context
	)

	assert_eq(rig["spy"].calls.size(), 1, "resolve() must delegate exactly one Strike to resolve_weapon_attack()")
	var call: Dictionary = rig["spy"].calls[0]
	assert_eq(call["active_defense"], "block", "active_defense must reach resolve_weapon_attack() unchanged")
	assert_eq(call["defense_type"], "ac", "defense_type passed alongside active_defense must remain 'ac'")
	assert_same(
		call["defense_context"], defense_context,
		"defense_context must be forwarded as the SAME Dictionary reference (verbatim pass-through, no copy/rebuild)"
	)
	assert_eq(
		call["defense_context"].get("open_space_available"), false,
		"defense_context contents must arrive unmodified"
	)
	assert_eq(
		call["defense_context"].get("blocking_weapon"), {"block_value": 3, "damage_die": 6},
		"defense_context contents must arrive unmodified"
	)


func test_resolve_strike_forwards_active_defense_and_defense_context_verbatim() -> void:
	# Exercises _resolve_strike() directly (not only via resolve()), per the
	# feature spec's explicit "resolve() through _resolve_strike() into
	# resolve_weapon_attack()" wording.
	var rig: Dictionary = _make_spied_use_case()
	var defense_context: Dictionary = {"parrying_weapon": {"parry_bonus": 2}}

	rig["use_case"]._resolve_strike(_attacker(), _target(), _attacker()["weapon"], "parry", defense_context)

	assert_eq(rig["spy"].calls.size(), 1)
	var call: Dictionary = rig["spy"].calls[0]
	assert_eq(call["active_defense"], "parry", "_resolve_strike() must forward active_defense unchanged")
	assert_same(
		call["defense_context"], defense_context,
		"_resolve_strike() must forward defense_context as the SAME Dictionary reference"
	)


func test_resolve_forwards_default_none_and_empty_dict_when_not_supplied() -> void:
	# When a caller does not opt in, resolve() must still forward the exact
	# "none"/{} pair resolve_weapon_attack() has always received historically
	# (no silent substitution of some other sentinel).
	var rig: Dictionary = _make_spied_use_case()

	rig["use_case"].resolve(_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0)

	assert_eq(rig["spy"].calls.size(), 1)
	var call: Dictionary = rig["spy"].calls[0]
	assert_eq(call["active_defense"], "none", "default-arg calls must forward active_defense='none'")
	assert_eq(call["defense_context"], {}, "default-arg calls must forward an empty defense_context")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: default-arg calls produce output identical to explicitly
# passing the pre-existing "none"/{} defaults (backward-compat
# default-safety contract).
# ══════════════════════════════════════════════════════════════════════════

func test_default_args_produce_identical_output_to_explicit_none_and_empty_context() -> void:
	var rig_default: Dictionary = _make_use_case([10, 4])
	var result_default: Dictionary = rig_default["use_case"].resolve(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0
	)

	var rig_explicit: Dictionary = _make_use_case([10, 4])
	var result_explicit: Dictionary = rig_explicit["use_case"].resolve(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0, "", "none", {}
	)

	assert_true(result_default.get("ok", false))
	assert_true(result_explicit.get("ok", false))
	assert_eq(
		result_default.get("damage_final"), result_explicit.get("damage_final"),
		"omitting active_defense/defense_context must be identical to explicitly passing 'none'/{}"
	)
	assert_eq(result_default["event"].hit, result_explicit["event"].hit)
	assert_eq(result_default["event"].crit, result_explicit["event"].crit)
	assert_eq(result_default["event"].defense_value, result_explicit["event"].defense_value)
	assert_eq(result_default["event"].roll, result_explicit["event"].roll)


func test_default_arg_call_still_resolves_the_passive_ac_only_path() -> void:
	# A minimal end-to-end sanity check (real resolution.gd, no spy) that a
	# plain, pre-existing-shape resolve() call is completely unaffected by
	# the new trailing parameters simply existing on the signature.
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		_attacker(), _fresh_action_economy(), _target(), "Strike", 1, 0
	)
	assert_true(result.get("ok", false), "a default-arg Strike must still resolve successfully")
	assert_false(result["event"].hit, "PINNED (unchanged): roll_total(10) < ac(12) -> miss")
	assert_eq(result["event"].defense_value, 12, "PINNED (unchanged): defense_value must equal plain ac with no active defense")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: audit every existing production call site into resolve() --
# none of them may pass active_defense/defense_context yet (default-only
# invocation is the backward-compat contract this feature guarantees).
# ══════════════════════════════════════════════════════════════════════════

## Production source directories/files that are allowed to hold a LIVE call
## site into ResolveActionUseCase.resolve() -- mirrors tests/characterization/
## test_strike_characterization.gd's _PRODUCTION_SCAN_DIRS convention, plus
## the composition root (MainScene.gd lives at the project root, not under
## core/presentation/infrastructure).
const _PRODUCTION_SCAN_DIRS: Array = ["res://core", "res://presentation", "res://infrastructure"]
const _PRODUCTION_SCAN_FILES: Array = ["res://MainScene.gd"]

## The exact needle shared by every known call-site variable-naming
## convention in this codebase ("resolve_action_use_case.resolve(" and
## "_resolve_action_use_case.resolve(" both contain this substring).
const _CALL_NEEDLE: String = "_action_use_case.resolve("

## Maximum positional argument count resolve() accepts WITHOUT opting into
## active_defense/defense_context (combatant, action_economy, target,
## action_name, round_number, cycle_index, active_combatant_id).
const _MAX_DEFAULT_ONLY_ARG_COUNT: int = 7

## Maximum positional argument count resolve() accepts for the ONE
## documented reactive call site (FEAT-004): the 7 default-only args above
## PLUS active_defense + defense_context.
const _REACTIVE_CALL_SITE_MAX_ARG_COUNT: int = 9

## The ONE production file permitted to hold a reactive (>7-argument) call
## site (FEAT-004, US-003 / FR-003, ADR-004) -- round_session.gd's
## enemy-Strikes-player Strike branch inside advance_ai_turn().
const _REACTIVE_CALL_SITE_FILE: String = "res://core/application/round_session.gd"


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _collect_gd_files(dir_path: String, out_files: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_collect_gd_files(dir_path + "/" + entry, out_files)
		elif entry.ends_with(".gd"):
			out_files.append(dir_path + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()


## _count_top_level_args(args_text) -> int -- counts comma-separated
## arguments at paren/bracket/brace depth 0 only, so a Dictionary literal
## argument like `{"a": 1, "b": 2}` counts as ONE argument, not two.
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
## locates every non-comment occurrence of _CALL_NEEDLE in `content` and
## extracts the full, paren-depth-matched argument-list text that follows
## it (correctly handling calls that span multiple source lines).
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

		var paren_start: int = idx + _CALL_NEEDLE.length() - 1  # index of the '('
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
		var line_number: int = content.substr(0, idx).count("\n") + 1
		sites.append({"args_text": args_text, "line": line_number})
	return sites


func test_no_production_call_site_passes_active_defense_or_defense_context() -> void:
	# UPDATED by FEAT-004 (see this file's file-level "UPDATE" doc above):
	# round_session.gd's reactive enemy-Strikes-player call site is now the
	# ONE documented exception permitted to exceed the 7-argument
	# default-only shape (capped at 9 args). Every other call site --
	# anywhere else in the scanned production tree, INCLUDING
	# round_session.gd's own separate autonomous-path call site -- must
	# still be default-only, so an undocumented/accidental new reactive call
	# site is still caught here.
	var files: Array = []
	for dir_path in _PRODUCTION_SCAN_DIRS:
		_collect_gd_files(dir_path, files)
	for file_path in _PRODUCTION_SCAN_FILES:
		files.append(file_path)

	var total_sites_found: int = 0
	var reactive_sites_found: int = 0
	for file_path in files:
		var content: String = _read_file(file_path)
		var sites: Array = _find_call_sites(content)
		for site in sites:
			total_sites_found += 1
			var arg_count: int = _count_top_level_args(site["args_text"])
			if arg_count <= _MAX_DEFAULT_ONLY_ARG_COUNT:
				continue

			reactive_sites_found += 1
			assert_eq(
				file_path, _REACTIVE_CALL_SITE_FILE,
				"%s:%d calls resolve() with %d arguments -- only %s's reactive Strike call site (FEAT-004) may exceed the %d-argument default-only contract" % [
					file_path, site["line"], arg_count, _REACTIVE_CALL_SITE_FILE, _MAX_DEFAULT_ONLY_ARG_COUNT
				]
			)
			assert_true(
				arg_count <= _REACTIVE_CALL_SITE_MAX_ARG_COUNT,
				"%s:%d calls resolve() with %d arguments -- exceeds the %d-argument reactive-call-site ceiling (active_combatant_id + active_defense + defense_context)" % [
					file_path, site["line"], arg_count, _REACTIVE_CALL_SITE_MAX_ARG_COUNT
				]
			)

	assert_eq(
		reactive_sites_found, 1,
		"exactly one production call site (round_session.gd's reactive enemy-Strikes-player Strike branch, FEAT-004) may pass active_defense/defense_context"
	)
	assert_true(
		total_sites_found > 0,
		"sanity: the audit must find at least one production call site into resolve() " +
		"(core/application/round_session.gd and MainScene.gd are both expected to have one) -- " +
		"zero found means the scan itself is broken, not that the contract holds"
	)


func test_audit_finds_the_two_known_live_call_sites() -> void:
	# Pins the CURRENT set of production call sites (ADR-005's documented
	# "two parallel live call sites": round_session.gd's enemy-strikes-player
	# path (two loop bodies) and MainScene.gd's player-strikes-enemy path) --
	# so a future feature that adds/removes a call site does so consciously,
	# by updating this assertion, rather than silently.
	#
	# UPDATED by FEAT-004: round_session.gd's two call sites are no longer
	# both 6-argument default-only -- the interactive, reaction-enabled
	# enemy-Strikes-player Strike branch (advance_ai_turn()) now passes 9
	# args, while the autonomous/sim call site
	# (run_autonomous_to_completion(), which never offers a reaction) still
	# passes the original 6.
	var round_session_content: String = _read_file("res://core/application/round_session.gd")
	var round_session_sites: Array = _find_call_sites(round_session_content)
	assert_eq(
		round_session_sites.size(), 2,
		"core/application/round_session.gd is expected to have exactly 2 live resolve() call sites"
	)
	var round_session_arg_counts: Array = []
	for site in round_session_sites:
		round_session_arg_counts.append(_count_top_level_args(site["args_text"]))
	round_session_arg_counts.sort()
	assert_eq(
		round_session_arg_counts, [6, 9],
		"round_session.gd is expected to have exactly one 6-arg (autonomous) and one 9-arg (reactive interactive) call site"
	)

	# UPDATED by iteration K FEAT-004 (US-004, ADR-004): MainScene.gd's
	# player-strikes-enemy call site no longer calls resolve() at all -- it
	# now calls the SEPARATE resolve_reactive() entry point (see
	# core/application/resolve_action_use_case.gd's own doc) so the enemy
	# target can genuinely react (Dodge/Parry/Block) via
	# infrastructure/ai_reaction_policy.gd's AIReactionPolicy, synchronously
	# (no pop-up). resolve_reactive()'s name does not match this audit's
	# `_action_use_case.resolve(` needle (it requires the literal substring
	# to be followed immediately by "(", never "_reactive(") -- by design,
	# this is a SEPARATE method precisely so every pre-existing resolve()
	# call site/pinned audit above (round_session.gd's own two sites) stays
	# byte-for-byte untouched. MainScene.gd therefore now contributes ZERO
	# sites to this particular audit.
	var main_scene_content: String = _read_file("res://MainScene.gd")
	var main_scene_sites: Array = _find_call_sites(main_scene_content)
	assert_eq(
		main_scene_sites.size(), 0,
		"MainScene.gd is expected to have zero '_action_use_case.resolve(' call sites -- it now calls resolve_reactive() instead (iteration K FEAT-004)"
	)
