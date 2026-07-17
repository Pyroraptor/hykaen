extends GutTest
## tests/characterization/test_strike_characterization.gd
##
## GUT characterization suite for FEAT-008 (US-008 / FR-009, NFR-001,
## ADR-013): "Consolidate live Strike resolution into resolution.gd".
##
## PURPOSE (characterization testing, per CR-001): this suite was written
## and made to pass FIRST, against the OLD core/application/
## resolve_action_use_case.gd's _resolve_strike() -- a hand-rolled,
## passive-AC-only re-implementation of core/rules/resolution.gd's
## resolve_weapon_attack() math (Off-Guard +2 defense reduction,
## crit-by-10-or-more). It pins that exact numeric behavior BEFORE the
## duplicate math is deleted and _resolve_strike() is rewired to delegate
## to Resolution.resolve_weapon_attack(attacker, target, weapon,
## defense_type, active_defense, defense_context) directly, so a
## regression during consolidation would flip one of these assertions
## rather than surface later.
##
## After consolidation this whole suite MUST still pass byte-for-byte
## identically -- that is the point of a characterization test: it does
## not care HOW the result was computed, only that the observable output
## (hit/crit/damage_final/defense_value) never moves.
##
## Sections:
##   A. Off-Guard +2 characterization (blanket defense-value reduction)
##   B. Crit-by-10-or-more threshold characterization (exact boundary)
##   C. Delegation static check (_resolve_strike routes through
##      resolution.gd's resolve_weapon_attack())
##   D. No-duplicate-resolution-math static check (CR-001: the hand-rolled
##      AC-only formulas must not exist anywhere outside resolution.gd)
##   E. Unified seeded RNG determinism across both former call paths (the
##      live ResolveActionUseCase path and the direct Resolution+RNG path
##      historically used by core/combat/encounter.gd / core/sim/
##      simulator.gd) -- same seed must produce identical outcomes.

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const ResolutionClass           = preload("res://core/rules/resolution.gd")
const RNGClass                  = preload("res://core/rules/rng.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const FlankingClass             = preload("res://core/rules/flanking.gd")
const SeededRandomAdapterClass  = preload("res://core/combat/seeded_random_adapter.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")

const RESOLVE_ACTION_USE_CASE_PATH: String = "res://core/application/resolve_action_use_case.gd"
const RESOLUTION_PATH: String = "res://core/rules/resolution.gd"


# ── Local test doubles (mirrors tests/test_resolve_action_use_case.gd's
#    conventions -- each suite in this project owns its own doubles) ────────

class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var calls: Array = []

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		calls.append(dice_spec)
		var v = _values[_index]
		_index += 1
		return v


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


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port    = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


func _fresh_ae():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


# ══════════════════════════════════════════════════════════════════════════
# Section A: Off-Guard +2 characterization
#
# attacker: strength=0, weapon prof_bonus=0, damage_die=6 -> attack modifier
# is +0, so roll_total == the raw scripted d20 value exactly.
# target: ac=12.
#
# Scripted raw roll = 10 -> roll_total = 10.
#   baseline (no Off-Guard): defense_value=12 -> 10 < 12 -> MISS.
#   Off-Guard (-2):          defense_value=10 -> 10 >= 10 -> HIT (boundary
#                             flip caused ENTIRELY by the +2 bonus).
# ══════════════════════════════════════════════════════════════════════════

func _off_guard_attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	})


func _off_guard_target(conditions: Array = []):
	return CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 12, "conditions": conditions})


func test_pin_baseline_defense_value_equals_plain_ac() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		_off_guard_attacker(), _fresh_ae(), _off_guard_target([]), "Strike", 1, 0
	)
	assert_true(result.get("ok", false), "baseline Strike must resolve")
	assert_eq(result["event"].defense_value, 12, "PINNED: baseline defense_value must equal the target's plain ac (12)")
	assert_false(result["event"].hit, "PINNED: roll_total(10) < ac(12) -> miss")


func test_pin_off_guard_reduces_defense_value_by_exactly_two() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		_off_guard_attacker(), _fresh_ae(), _off_guard_target([FlankingClass.OFF_GUARD_CONDITION]), "Strike", 1, 0
	)
	assert_true(result.get("ok", false), "Off-Guard Strike must resolve")
	assert_eq(result["event"].defense_value, 10, "PINNED: Off-Guard defense_value must be ac(12) - 2 = 10")


func test_pin_off_guard_flips_boundary_miss_into_hit() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		_off_guard_attacker(), _fresh_ae(), _off_guard_target([FlankingClass.OFF_GUARD_CONDITION]), "Strike", 1, 0
	)
	assert_true(result["event"].hit, "PINNED: roll_total(10) >= off-guard defense_value(10) -> hit")
	assert_eq(result.get("damage_final", -1), 4, "PINNED: damage_final = damage_roll(4) + strength_mod(0) = 4")


func test_pin_unrelated_condition_does_not_reduce_defense_value() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var result: Dictionary = rig["use_case"].resolve(
		_off_guard_attacker(), _fresh_ae(), _off_guard_target(["Dazed"]), "Strike", 1, 0
	)
	assert_eq(result["event"].defense_value, 12, "PINNED: a non-Off-Guard condition must not reduce defense_value")


# ══════════════════════════════════════════════════════════════════════════
# Section B: Crit-by-10-or-more threshold characterization
#
# attacker: strength=3, weapon prof_bonus=2, damage_die=6.
# raw=20 -> roll_total = 20 + 3 + 2 = 25.
#
#   target ac=15 -> excess = 25-15 = 10 -> PINNED: crit=true (boundary
#                   value, exactly 10).
#   target ac=16 -> excess = 25-16 = 9  -> PINNED: crit=false (one below
#                   the boundary; still a hit, never a crit).
# ══════════════════════════════════════════════════════════════════════════

func _crit_attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6
		}
	})


func test_pin_crit_fires_at_exactly_ten_over_defense_value() -> void:
	# raw=20 -> roll_total=25 vs ac=15 -> excess=10 -> crit.
	# Crit damage: roll(6,2) scripted as a single summed value (9) + strength_mod(3)*2 = 15.
	var rig: Dictionary = _make_use_case([20, 9])
	var result: Dictionary = rig["use_case"].resolve(
		_crit_attacker(), _fresh_ae(), CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 15}), "Strike", 1, 0
	)
	assert_true(result["event"].hit, "PINNED: roll_total(25) >= ac(15) -> hit")
	assert_true(result["event"].crit, "PINNED: excess(25-15=10) >= 10 -> crit at the exact boundary")
	assert_eq(result.get("damage_final", -1), 15, "PINNED: crit damage_final = roll(9) + strength_mod(3)*2 = 15")
	assert_eq(rig["rng_port"].calls[1], {"die": 6, "count": 2}, "PINNED: a crit must roll 2 damage dice")


func test_pin_no_crit_one_below_the_boundary() -> void:
	# raw=20 -> roll_total=25 vs ac=16 -> excess=9 -> hit but NOT crit.
	var rig: Dictionary = _make_use_case([20, 5])
	var result: Dictionary = rig["use_case"].resolve(
		_crit_attacker(), _fresh_ae(), CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 16}), "Strike", 1, 0
	)
	assert_true(result["event"].hit, "PINNED: roll_total(25) >= ac(16) -> hit")
	assert_false(result["event"].crit, "PINNED: excess(25-16=9) < 10 -> must not crit, one below the boundary")
	assert_eq(result.get("damage_final", -1), 8, "PINNED: non-crit damage_final = roll(5) + strength_mod(3) = 8")
	assert_eq(rig["rng_port"].calls[1], {"die": 6, "count": 1}, "PINNED: a non-crit must roll exactly 1 damage die")


# ══════════════════════════════════════════════════════════════════════════
# Section C: Delegation static check (test_criteria #2) -- _resolve_strike()
# must delegate to resolution.gd's resolve_weapon_attack(), passing
# defense_type/active_defense/defense_context, rather than re-implementing
# the math inline.
# ══════════════════════════════════════════════════════════════════════════

func test_resolve_action_use_case_preloads_resolution_gd() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	assert_true(
		content.contains("res://core/rules/resolution.gd"),
		"core/application/resolve_action_use_case.gd must preload/reference core/rules/resolution.gd (delegation, CR-001)"
	)


func test_resolve_action_use_case_calls_resolve_weapon_attack() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	assert_true(
		content.contains(".resolve_weapon_attack("),
		"core/application/resolve_action_use_case.gd must call resolve_weapon_attack() on a Resolution instance (CR-001 delegation)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section D: No-duplicate-resolution-math static check (test_criteria #4) --
# the hand-rolled Off-Guard reduction / crit-threshold formulas that used to
# live in resolve_action_use_case.gd must not exist anywhere outside
# resolution.gd, repo-wide.
# ══════════════════════════════════════════════════════════════════════════

func _scan_dir_for_pattern(dir_path: String, pattern: String, out_files: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_scan_dir_for_pattern(dir_path + "/" + entry, pattern, out_files)
		elif entry.ends_with(".gd"):
			var full_path: String = dir_path + "/" + entry
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var content: String = f.get_as_text()
				f.close()
				if content.contains(pattern):
					out_files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Source-of-truth production directories only (mirrors ci/check_no_duplicate_seams.sh's
## SCAN_DIRS convention) -- never tests/ or addons/, which legitimately
## declare their own local doubles/fixtures.
const _PRODUCTION_SCAN_DIRS: Array = ["res://core", "res://presentation", "res://infrastructure"]


func test_off_guard_reduction_math_exists_only_in_resolution_gd() -> void:
	var matches: Array = []
	for dir_path in _PRODUCTION_SCAN_DIRS:
		_scan_dir_for_pattern(dir_path, "func _off_guard_defense_reduction", matches)
	assert_eq(
		matches, [RESOLUTION_PATH],
		"CR-001: exactly one func _off_guard_defense_reduction() may exist repo-wide (resolution.gd); found: %s" % str(matches)
	)


func test_crit_threshold_formula_exists_only_in_resolution_gd() -> void:
	var matches: Array = []
	for dir_path in _PRODUCTION_SCAN_DIRS:
		_scan_dir_for_pattern(dir_path, "roll_total - defense_value) >= 10", matches)
	for match_path in matches:
		assert_eq(
			match_path, RESOLUTION_PATH,
			"CR-001: the crit-threshold formula 'roll_total - defense_value) >= 10' must not be duplicated outside resolution.gd; found in: %s" % match_path
		)
	assert_true(
		matches.size() >= 1,
		"sanity: resolution.gd itself must still contain the crit-threshold formula (it was not accidentally deleted)"
	)


func test_resolve_action_use_case_no_longer_references_proficiency_bonus_directly() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	assert_false(
		content.contains("proficiency_bonus"),
		"CR-001: resolve_action_use_case.gd must not reference weapon['proficiency_bonus'] directly any more -- that math now lives solely in resolution.gd"
	)


func test_resolve_action_use_case_no_longer_defines_off_guard_reduction_helper() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	assert_false(
		content.contains("_off_guard_defense_reduction"),
		"CR-001: resolve_action_use_case.gd must not define/call its own _off_guard_defense_reduction() -- resolution.gd owns that logic exclusively"
	)


# ══════════════════════════════════════════════════════════════════════════
# Section E: Unified seeded RNG determinism across both former call paths
# (test_criteria #5) -- the live ResolveActionUseCase path (driven by an
# injected RandomNumberPort) and the direct Resolution+RNG path historically
# used by core/combat/encounter.gd / core/sim/simulator.gd must produce
# byte-identical outcomes when seeded identically, proving they now share
# ONE underlying seeded RNG source rather than two independent ones.
# ══════════════════════════════════════════════════════════════════════════

func _shared_attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 3,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 8
		}
	})


func test_unified_rng_produces_identical_results_across_both_former_call_paths() -> void:
	var seed_value: int = 4242

	# Path A: direct Resolution + RNG -- the pre-existing call path used by
	# core/combat/encounter.gd / core/sim/simulator.gd (never modified by
	# this feature).
	var direct_rng = RNGClass.new(seed_value)
	var direct_resolution = ResolutionClass.new(direct_rng)
	var direct_target: Dictionary = {"ac": 13}
	var direct_result: Dictionary = direct_resolution.resolve_weapon_attack(
		_shared_attacker(), direct_target, _shared_attacker()["weapon"], "ac", "none", {}
	)

	# Path B: the live ResolveActionUseCase path, now delegating to
	# resolution.gd internally, driven by a SeededRandomAdapter constructed
	# with the SAME seed.
	var seeded_port = SeededRandomAdapterClass.new(seed_value)
	var use_case = ResolveActionUseCaseClass.new(seeded_port, FakeEventSinkPort.new(), FakeRoundHistoryPort.new())
	var live_target = CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 13})
	var live_result: Dictionary = use_case.resolve(
		_shared_attacker(), _fresh_ae(), live_target, "Strike", 1, 0
	)

	assert_eq(
		live_result["event"].hit, direct_result["hit"],
		"unified RNG: identical seed must produce an identical hit/miss outcome across both former call paths"
	)
	assert_eq(
		live_result["event"].crit, direct_result["crit"],
		"unified RNG: identical seed must produce an identical crit outcome across both former call paths"
	)
	assert_eq(
		live_result.get("damage_final", -1), direct_result["damage_final"],
		"unified RNG: identical seed must produce identical damage_final across both former call paths"
	)
	assert_eq(
		live_result["event"].roll, direct_result["roll_total"],
		"unified RNG: identical seed must produce an identical roll_total across both former call paths"
	)


func test_unified_rng_is_reproducible_across_two_independent_live_path_runs() -> void:
	var seed_value: int = 777

	var port_a = SeededRandomAdapterClass.new(seed_value)
	var use_case_a = ResolveActionUseCaseClass.new(port_a, FakeEventSinkPort.new(), FakeRoundHistoryPort.new())
	var result_a: Dictionary = use_case_a.resolve(
		_shared_attacker(), _fresh_ae(), CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 13}), "Strike", 1, 0
	)

	var port_b = SeededRandomAdapterClass.new(seed_value)
	var use_case_b = ResolveActionUseCaseClass.new(port_b, FakeEventSinkPort.new(), FakeRoundHistoryPort.new())
	var result_b: Dictionary = use_case_b.resolve(
		_shared_attacker(), _fresh_ae(), CombatantClass.from_dict({"name": "Target", "hp_current": 50, "ac": 13}), "Strike", 1, 0
	)

	assert_eq(result_a["event"].hit, result_b["event"].hit, "same seed, live path: hit must be reproducible")
	assert_eq(result_a["event"].crit, result_b["event"].crit, "same seed, live path: crit must be reproducible")
	assert_eq(result_a.get("damage_final", -1), result_b.get("damage_final", -1), "same seed, live path: damage_final must be reproducible")
