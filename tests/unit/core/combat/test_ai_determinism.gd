extends GutTest
## tests/unit/core/combat/test_ai_determinism.gd
##
## GUT unit test suite for FEAT-007 (US-007 / FR-011, ADR-005): the stable
## lowest-(q,r) lexicographic tie-break rule core/combat/ai.gd's
## _select_target() (nearest-target selection) and _stride_toward_target()
## (destination selection) already apply — FEAT-004's groundwork
## (tests/unit/core/combat/test_ai_target_selection.gd's own file-level doc
## explicitly cites "US-007" for this exact rule) — must hold with ZERO RNG
## calls anywhere in the tie-break path, so decide_action() produces
## BYTE-IDENTICAL AIDecision output across repeated invocations against an
## identical battlefield_state, regardless of HYKAEN_SEED/seed_override.
##
## This suite does NOT re-test FEAT-003/FEAT-004/FEAT-005/FEAT-006's reach/
## Stride-closing/Stride-then-Strike/action-budget criteria — those remain
## covered by tests/unit/core/combat/test_ai_reach_strike.gd,
## test_ai_target_selection.gd, test_ai_stride_then_strike.gd, and
## test_ai_action_budget.gd. It focuses exclusively on the TIE-BREAK
## determinism guarantee itself.
##
## Test criteria (feature spec):
##   1. Repeated decide_action() invocations against an identical
##      battlefield_state under HYKAEN_SEED/seed_override yield
##      byte-identical AIDecision output.
##   2. No RNG call sites exist in ai.gd's tie-break logic.
##   3. Full existing determinism suite from prior iterations still passes
##      (no regression) — verified by this project's full test_command run;
##      this suite additionally re-affirms the pre-existing
##      test_ai_gd_does_not_extend_node_or_control-style static purity guard.

const AIClass              = preload("res://core/combat/ai.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")
const HexMathClass         = preload("res://core/geometry/hex_math.gd")
const MovementClass        = preload("res://core/rules/movement.gd")
const ActionEconomyClass   = preload("res://core/rules/action_economy.gd")
const SeedPolicyClass      = preload("res://infrastructure/seed_policy.gd")

## REPEAT_COUNT — number of repeated decide_action() invocations exercised
## against a freshly-rebuilt but STRUCTURALLY IDENTICAL battlefield_state
## each time; a non-deterministic tie-break (e.g. one accidentally seeded by
## RNG) would be overwhelmingly likely to diverge across this many samples.
const REPEAT_COUNT: int = 25

## A handful of arbitrary, mutually distinct seed values used only to prove
## the AIDecision output is completely INSENSITIVE to whichever seed is
## active via HYKAEN_SEED -- i.e. the tie-break path consults no RNG/seed
## state at all.
const PROBE_SEEDS: Array = [1, 42, 4242, 999983, -7]


# ══════════════════════════════════════════════════════════════════════════
# Real-environment isolation for HYKAEN_SEED -- mirrors
# tests/regression/test_seed_determinism.gd's before_each()/after_each()
# convention so no test state leaks to any other GUT script sharing this
# headless run.
# ══════════════════════════════════════════════════════════════════════════

var _had_env_var_before: bool = false
var _original_env_value: String = ""


func before_each() -> void:
	_had_env_var_before = OS.has_environment(SeedPolicyClass.ENV_VAR_NAME)
	if _had_env_var_before:
		_original_env_value = OS.get_environment(SeedPolicyClass.ENV_VAR_NAME)


func after_each() -> void:
	if _had_env_var_before:
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, _original_env_value)
	else:
		OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)


# ── Fixture helpers ─────────────────────────────────────────────────────────

func _melee_combatant(hex_coord) -> Dictionary:
	return {
		"name":        "Skeleton",
		"hp_current":  8,
		"ac":          12,
		"strength":    2,
		"hex_coord":   hex_coord,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 1,
			"damage_die": 6
		}
	}


func _target(name: String, hex_coord, hp: int = 18) -> Dictionary:
	return {"name": name, "hp_current": hp, "ac": 14, "strength": 5, "hex_coord": hex_coord}


## Builds two living targets that are EXACTLY equidistant (hex_distance == 1
## -- both are adjacent flat-top axial neighbors of a combatant standing at
## (0,0), so decide_action() Strikes immediately regardless of which is
## chosen -- letting this test observe _select_target()'s tie-break choice
## directly in the returned AIDecision's "target" field), with distinct
## (q, r) so a non-deterministic/order-dependent tie-break would be
## observable:
##   Titus  @ (1, 0) -- hex_distance((0,0),(1,0)) == 1
##   Varro  @ (0, 1) -- hex_distance((0,0),(0,1)) == 1
## Lexicographically, (0,1) < (1,0) on q alone, so Varro is the ONE
## deterministically-correct nearest-target choice under the stable
## lowest-(q,r) rule, regardless of which order the two are supplied in.
func _equidistant_targets() -> Dictionary:
	var titus: Dictionary = _target("Titus", HexCoordClass.new(1, 0))
	var varro: Dictionary = _target("Varro", HexCoordClass.new(0, 1))
	return {"titus": titus, "varro": varro}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1a -- nearest-TARGET tie-break: byte-identical, order-independent
# choice across many repeated invocations against a fresh-but-identical
# battlefield_state, regardless of active HYKAEN_SEED.
# ══════════════════════════════════════════════════════════════════════════

func test_equidistant_target_tie_break_is_byte_identical_across_repeated_invocations() -> void:
	var chosen_names: Array = []

	for i in range(REPEAT_COUNT):
		# A different HYKAEN_SEED value every iteration -- if tie-breaking
		# secretly consulted any RNG/seed source, this would perturb which
		# target gets chosen. Alternate presentation order (targets supplied
		# as [titus, varro] on even iterations, [varro, titus] on odd) to
		# also prove the choice is not an accident of array order.
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(PROBE_SEEDS[i % PROBE_SEEDS.size()]))

		var ai = AIClass.new()
		var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
		var pair: Dictionary = _equidistant_targets()
		var targets: Array = [pair["titus"], pair["varro"]] if i % 2 == 0 else [pair["varro"], pair["titus"]]

		var result: Dictionary = await ai.decide_action(combatant, targets)
		assert_eq(result.get("action_type", ""), "Strike", "iteration %d: fixture assumption: both equidistant targets are adjacent, so decide_action() must Strike immediately" % i)
		chosen_names.append(result.get("target", {}).get("name", ""))

	for i in range(chosen_names.size()):
		assert_eq(
			chosen_names[i], "Varro",
			"iteration %d: the stable lowest-(q,r) rule must deterministically choose Varro (0,1) over Titus (1,0) every single time, regardless of HYKAEN_SEED or array order" % i
		)

	# Sanity guard against a vacuously-true suite: confirm every sample
	# really is identical to the first (not merely all equal to a hardcoded
	# literal by coincidence of this assertion's own wording).
	for i in range(1, chosen_names.size()):
		assert_eq(chosen_names[i], chosen_names[0], "AIDecision.target.name must be byte-identical across repeated invocation %d vs invocation 0" % i)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1b -- destination tie-break: byte-identical choice across many
# repeated invocations, when multiple legal Stride destinations tie for the
# minimum hex_distance to the chosen target.
# ══════════════════════════════════════════════════════════════════════════

func test_equidistant_destination_tie_break_is_byte_identical_across_repeated_invocations() -> void:
	var origin_hex = HexCoordClass.new(0, 0)
	# (1, 4) is deliberately chosen (rather than an on-axis point like
	# (10, 0)) so that the Speed-4 Stride affordance has MULTIPLE legal
	# destinations tying for the minimum hex_distance to the target --
	# (0, 4) and (1, 3) both land exactly hex_distance 1 from (1, 4) -- so
	# this test genuinely exercises the tie-break rule rather than a
	# vacuous single-best-candidate case.
	var target_hex = HexCoordClass.new(1, 4)

	# Independently (never calling into ai.gd) compute the full legal
	# destination set and the expected winner under the SAME stable
	# lowest-(q,r) rule, so this assertion is not merely "whatever ai.gd
	# returns first" -- it is checked against an INDEPENDENTLY derived
	# expectation.
	var candidates: Array = MovementClass.get_stride_destinations({"hex_coord": origin_hex}, [])
	assert_false(candidates.is_empty(), "fixture assumption: at least one legal Stride destination must exist")

	var expected_destination = null
	var expected_distance: int = -1
	for candidate in candidates:
		var distance: int = HexMathClass.hex_distance(candidate, target_hex)
		var is_better: bool = expected_destination == null or distance < expected_distance
		var is_tie_and_lower: bool = (
			expected_destination != null and distance == expected_distance
			and _is_lower_coord(candidate, expected_destination)
		)
		if is_better or is_tie_and_lower:
			expected_destination = candidate
			expected_distance = distance

	assert_not_null(expected_destination, "fixture assumption: an expected winning destination must be derivable")

	# Confirm the fixture genuinely exercises a tie (>= 2 candidates share
	# expected_distance) -- otherwise this test would not actually be
	# proving anything about TIE-BREAKING.
	var tied_count: int = 0
	for candidate in candidates:
		if HexMathClass.hex_distance(candidate, target_hex) == expected_distance:
			tied_count += 1
	assert_true(tied_count >= 2, "fixture assumption: at least two legal destinations must tie for the minimum distance to the target, to genuinely exercise the tie-break rule")

	var chosen_destinations: Array = []

	for i in range(REPEAT_COUNT):
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(PROBE_SEEDS[i % PROBE_SEEDS.size()]))

		var ai = AIClass.new()
		var combatant: Dictionary = _melee_combatant(HexCoordClass.new(origin_hex.q, origin_hex.r))
		var target: Dictionary = _target("Titus", HexCoordClass.new(target_hex.q, target_hex.r))
		var action_economy = ActionEconomyClass.new()
		action_economy.start_of_turn()

		var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])
		assert_eq(result.get("action_type", ""), "Stride", "iteration %d: fixture assumption: the out-of-reach target must trigger a Stride" % i)

		var destination = result.get("destination", null)
		assert_not_null(destination, "iteration %d: a Stride decision must carry a non-null destination" % i)
		chosen_destinations.append(destination)

	for i in range(chosen_destinations.size()):
		assert_true(
			chosen_destinations[i].equals(expected_destination),
			"iteration %d: the chosen Stride destination (%s) must byte-identically match the independently-derived stable lowest-(q,r) winner (%s) every single time, regardless of HYKAEN_SEED" % [i, chosen_destinations[i], expected_destination]
		)

	for i in range(1, chosen_destinations.size()):
		assert_true(
			chosen_destinations[i].equals(chosen_destinations[0]),
			"AIDecision.destination must be byte-identical across repeated invocation %d vs invocation 0" % i
		)


## _is_lower_coord(a, b) -> bool -- an INDEPENDENT re-implementation (not a
## call into ai.gd's private helper) of the stable (q, r) lexicographic
## tie-break rule, used only to derive this test's own expectations.
func _is_lower_coord(a, b) -> bool:
	if a.q != b.q:
		return a.q < b.q
	return a.r < b.r


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1c -- full AIDecision Dictionary (not just target/destination) is
# byte-identical across repeated invocations of the composite
# Stride-then-Strike path, against a fresh-but-structurally-identical
# battlefield_state each time.
# ══════════════════════════════════════════════════════════════════════════

func test_full_ai_decision_dictionary_is_byte_identical_across_repeated_invocations() -> void:
	var decisions: Array = []

	for i in range(REPEAT_COUNT):
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(PROBE_SEEDS[i % PROBE_SEEDS.size()]))

		var ai = AIClass.new()
		var combatant: Dictionary = _melee_combatant(HexCoordClass.new(0, 0))
		var target: Dictionary = _target("Titus", HexCoordClass.new(4, 0))
		var action_economy = ActionEconomyClass.new()
		action_economy.start_of_turn()

		var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])
		decisions.append({
			"action_type": result.get("action_type", ""),
			"target_name": result.get("target", {}).get("name", ""),
			"destination_q": result.get("destination").q if result.get("destination", null) != null else null,
			"destination_r": result.get("destination").r if result.get("destination", null) != null else null,
			"will_strike": result.get("will_strike", false),
		})

	for i in range(1, decisions.size()):
		assert_eq(
			decisions[i], decisions[0],
			"the full AIDecision projection must be byte-identical across repeated invocation %d vs invocation 0 against an identical battlefield_state, regardless of HYKAEN_SEED" % i
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 -- static check: no RNG call sites exist anywhere in ai.gd
# (the tie-break logic in particular consults no randomness source at all).
# Mirrors the established static-purity-guard convention (e.g.
# tests/unit/core/combat/test_ai_target_selection.gd's
# test_ai_gd_does_not_extend_node_or_control()).
# ══════════════════════════════════════════════════════════════════════════

func test_ai_gd_contains_no_rng_call_sites() -> void:
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var forbidden_tokens: Array = [
		"randi", "randf", "rand_range", "randomize", "RandomNumberGenerator",
		"seed(", "RandomNumberPort", "random_port", "RandomPort",
	]
	for token in forbidden_tokens:
		assert_false(
			content.contains(token),
			"core/combat/ai.gd must contain zero RNG call sites/collaborators (found forbidden token '%s') -- the tie-break path must be pure data-in/data-out (US-007, ADR-005)" % token
		)


func test_ai_gd_does_not_extend_node_or_control() -> void:
	var file := FileAccess.open("res://core/combat/ai.gd", FileAccess.READ)
	assert_not_null(file, "core/combat/ai.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	assert_false(content.contains("extends Node"), "ai.gd must not contain 'extends Node' -- domain purity (ADR-001)")
	assert_false(content.contains("extends Control"), "ai.gd must not contain 'extends Control' -- domain purity (ADR-001)")
