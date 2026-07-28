extends GutTest
## tests/unit/core/combat/test_ai.gd
##
## GUT unit test suite for FEAT-004 (US-004 / FR-004, NFR-001/NFR-003,
## ADR-003 — "AI Stride pathfinder seam in ai.gd"): core/combat/ai.gd's
## _stride_toward_target() gains an OPTIONAL, injected `_stride_pathfinder_fn`
## Callable seam (set via set_stride_pathfinder_fn()), mirroring the SAME
## Callable Dependency-Inversion convention `_stride_reaction_resolver_fn`
## already established (FEAT-006). Once a legal Stride destination is chosen,
## _stride_toward_target() computes a `stride_path` via this seam (falling
## back to the direct two-hex [origin, destination] path when the seam is
## unwired or reports an invalid/short result), forwards it as the 4th
## positional argument to `_stride_reaction_resolver_fn` WHENEVER the
## pathfinder seam is itself wired (reflection over the resolver's OWN
## declared arity — ADR-003 — so every pre-existing 3-argument resolver
## Callable/test double keeps working completely unchanged), and includes it
## under the additive "path" key of the returned AI decision Dictionary.
##
## This suite deliberately does NOT re-test FEAT-003/FEAT-006/FEAT-007/FEAT-008's
## reach/target-selection/Stride-closing/opportunistic-strike-cancellation
## criteria beyond what is needed to exercise the new seam — those remain
## covered by tests/unit/core/combat/test_ai_reach_strike.gd,
## test_ai_target_selection.gd, test_ai_stride_then_strike.gd, and
## test_ai_action_budget.gd.
##
## Verifies (test_criteria):
##   1. set_stride_pathfinder_fn(fn) wires the seam and _stride_toward_target()
##      calls it with (origin, best_destination).
##   2. _stride_reaction_resolver_fn is invoked with stride_path as its 4th
##      argument when the pathfinder is wired.
##   3. Legacy 3-arg resolver Callables continue to work unchanged when the
##      pathfinder is wired too (i.e. they are never handed a 4th argument at
##      all — ADR-003 reflection dispatch).
##   4. Fallback to the direct [origin, best_destination] path when
##      _stride_pathfinder_fn is UNWIRED. When wired but returns size < 2
##      (no route found), the Stride is ABORTED (no action taken) — falling
##      back to a straight-line path that bypasses blocking hexes would
##      produce a visual pass-through of opponent tokens.
##   5. The returned AI decision Dictionary always includes a "path" key
##      (the real path, or the 2-element fallback) whenever a Stride branch
##      outcome is produced.

const AIClass            = preload("res://core/combat/ai.gd")
const HexCoordClass      = preload("res://core/geometry/hex_coord.gd")
const HexMathClass       = preload("res://core/geometry/hex_math.gd")
const ActionEconomyClass = preload("res://core/rules/action_economy.gd")


# ── Shared fixture helpers (mirrors test_ai_stride_then_strike.gd) ─────────

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


## _hex_pairs(hexes) -> Array — converts an Array of HexCoord into an Array of
## [q, r] pairs so assert_eq() can compare by VALUE — GDScript's Array `==`
## compares HexCoord elements by reference/identity, never by (q, r) value.
func _hex_pairs(hexes: Array) -> Array:
	var pairs: Array = []
	for h in hexes:
		pairs.append([h.q, h.r])
	return pairs


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: set_stride_pathfinder_fn(fn) wires the seam and
# _stride_toward_target() calls it with (origin, best_destination).
# ══════════════════════════════════════════════════════════════════════════

var _pathfinder_calls: Array = []

func _spy_pathfinder(origin, destination) -> Array:
	_pathfinder_calls.append([origin, destination])
	# A distinctly-recognizable 3-hex "real" path (never equal to the
	# 2-element fallback), so later assertions can tell the seam's own
	# result was genuinely used rather than the fallback.
	return [origin, HexCoordClass.new(999, 999), destination]


func test_set_stride_pathfinder_fn_wires_seam_and_is_called_with_origin_and_best_destination() -> void:
	_pathfinder_calls = []
	var ai = AIClass.new()
	ai.set_stride_pathfinder_fn(Callable(self, "_spy_pathfinder"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)  # out of melee reach initially -- forces a Stride
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "fixture assumption: the out-of-reach target must force a Stride")
	assert_eq(_pathfinder_calls.size(), 1, "the injected pathfinder seam must be called exactly once")
	assert_eq(_pathfinder_calls[0][0].q, origin_hex.q, "the pathfinder must be called with the mover's origin hex (q)")
	assert_eq(_pathfinder_calls[0][0].r, origin_hex.r, "the pathfinder must be called with the mover's origin hex (r)")
	var destination = result.get("destination", null)
	assert_not_null(destination, "fixture assumption: a Stride decision must carry a non-null destination")
	assert_eq(_pathfinder_calls[0][1].q, destination.q, "the pathfinder must be called with the CHOSEN best_destination hex (q)")
	assert_eq(_pathfinder_calls[0][1].r, destination.r, "the pathfinder must be called with the CHOSEN best_destination hex (r)")

	# The seam's own (non-degenerate) result must be the one reported -- not
	# the [origin, destination] fallback.
	assert_eq(
		_hex_pairs(result.get("path", [])), [[origin_hex.q, origin_hex.r], [999, 999], [destination.q, destination.r]],
		"decide_action() must report the REAL pathfinder result, not the direct fallback, when the seam returns a valid (size >= 2) path"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: _stride_reaction_resolver_fn is invoked with stride_path as
# its 4th argument when the pathfinder is wired.
# ══════════════════════════════════════════════════════════════════════════

var _resolver_4arg_calls: Array = []

func _resolver_4arg(mover, mover_start_hex, candidate_reactors: Array, stride_path: Array) -> Dictionary:
	_resolver_4arg_calls.append(stride_path)
	return {}


func test_stride_reaction_resolver_receives_stride_path_as_fourth_argument_when_pathfinder_wired() -> void:
	_resolver_4arg_calls = []
	var ai = AIClass.new()
	ai.set_stride_pathfinder_fn(Callable(self, "_spy_pathfinder"))
	ai.set_stride_reaction_resolver_fn(Callable(self, "_resolver_4arg"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride")
	assert_eq(_resolver_4arg_calls.size(), 1, "the 4-argument resolver must be invoked exactly once")
	assert_eq(
		_hex_pairs(_resolver_4arg_calls[0]), _hex_pairs(result.get("path", [])),
		"the resolver's 4th argument must be the SAME stride_path reported under the decision's own 'path' key"
	)
	assert_eq(_hex_pairs(_resolver_4arg_calls[0])[1], [999, 999], "fixture assumption: the resolver must receive the REAL (non-fallback) pathfinder result")


func test_stride_reaction_resolver_receives_only_three_arguments_when_pathfinder_unwired() -> void:
	# US-004: with NO pathfinder seam wired (the current production
	# MainScene.gd composition root's own state), a resolver that DOES
	# declare a 4th (stride_path) parameter -- e.g. the REAL
	# reaction_controller.gd resolver already wired in production -- must
	# still be invoked with exactly 3 positional arguments, so that no
	# pre-existing caller's per-transit-hex OpportunisticStrike evaluation is
	# silently activated before a real pathfinder is deliberately wired too.
	_resolver_4arg_calls = []
	var received_arg_counts: Array = []
	var ai = AIClass.new()
	ai.set_stride_reaction_resolver_fn(Callable(self, "_resolver_4arg_optional").bind(received_arg_counts))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride")
	assert_eq(received_arg_counts.size(), 1, "the resolver must be invoked exactly once")
	assert_eq(received_arg_counts[0], 3, "an unwired pathfinder seam must never cause the 4th (stride_path) argument to be forwarded, even to a resolver that declares it")


func _resolver_4arg_optional(mover, mover_start_hex, candidate_reactors: Array, received_arg_counts: Array, stride_path: Array = []) -> Dictionary:
	# `stride_path` defaults to [] -- mirrors reaction_controller.gd's real
	# production resolver shape, which also treats a 3-argument call as
	# legal (the 4th parameter has a default).
	received_arg_counts.append(3 if stride_path.is_empty() else 4)
	return {}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: legacy 3-arg resolver Callables continue to work unchanged --
# never handed a 4th argument (ADR-003 reflection dispatch), even when the
# pathfinder seam is wired.
# ══════════════════════════════════════════════════════════════════════════

var _resolver_3arg_call_count: int = 0

func _resolver_3arg(mover, mover_start_hex, candidate_reactors: Array) -> Dictionary:
	_resolver_3arg_call_count += 1
	return {}


func test_legacy_three_argument_resolver_continues_to_work_unchanged_with_pathfinder_wired() -> void:
	_resolver_3arg_call_count = 0
	var ai = AIClass.new()
	ai.set_stride_pathfinder_fn(Callable(self, "_spy_pathfinder"))
	ai.set_stride_reaction_resolver_fn(Callable(self, "_resolver_3arg"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	# Must complete without a runtime "too many arguments" error -- the
	# resolver's OWN declared arity (3) governs how many arguments it is
	# actually called with.
	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride", "the Stride must still commit -- an unwired-for-4-args resolver is not a failure")
	assert_eq(_resolver_3arg_call_count, 1, "the legacy 3-argument resolver must still be invoked exactly once")
	assert_true(
		combatant["hex_coord"].equals(result.get("destination", null)),
		"the combatant must actually be repositioned -- the Stride proceeds exactly as before this feature for a legacy resolver"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: fallback to the direct [origin, best_destination] path when
# _stride_pathfinder_fn is unwired or returns a size < 2 Array.
# ══════════════════════════════════════════════════════════════════════════

func test_fallback_path_when_pathfinder_seam_is_unwired() -> void:
	var ai = AIClass.new()
	# _stride_pathfinder_fn deliberately left unwired.

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "Stride")
	var destination = result.get("destination", null)
	assert_eq(
		_hex_pairs(result.get("path", [])), [[origin_hex.q, origin_hex.r], [destination.q, destination.r]],
		"an unwired pathfinder seam must fall back to the direct [origin, best_destination] path"
	)


func _empty_pathfinder(_origin, _destination) -> Array:
	return []


func _single_hex_pathfinder(origin, _destination) -> Array:
	return [origin]


func test_wired_pathfinder_returning_empty_array_aborts_stride() -> void:
	var ai = AIClass.new()
	ai.set_stride_pathfinder_fn(Callable(self, "_empty_pathfinder"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(
		result.get("action_type", ""), "",
		"a wired pathfinder reporting an empty (unreachable) result must ABORT the stride, not fall back to a straight-line path that bypasses blocking hexes"
	)
	assert_null(
		result.get("destination", null),
		"no destination must be committed when the wired pathfinder returns no route"
	)
	assert_true(
		combatant["hex_coord"].equals(origin_hex),
		"the combatant must NOT be repositioned when the pathfinder aborts the stride"
	)


func test_wired_pathfinder_returning_single_element_array_aborts_stride() -> void:
	var ai = AIClass.new()
	ai.set_stride_pathfinder_fn(Callable(self, "_single_hex_pathfinder"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(
		result.get("action_type", ""), "",
		"a wired pathfinder reporting a size-1 (trivial/degenerate) result must ABORT the stride, not use a straight-line fallback"
	)
	assert_null(
		result.get("destination", null),
		"no destination must be committed when the wired pathfinder returns a degenerate path"
	)
	assert_true(
		combatant["hex_coord"].equals(origin_hex),
		"the combatant must NOT be repositioned when the degenerate pathfinder aborts the stride"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: the returned AI decision Dictionary always includes a "path"
# key (the real path, or the 2-element fallback) for a Stride branch outcome
# -- including a Stride CANCELLED by a lethal Opportunistic Strike.
# ══════════════════════════════════════════════════════════════════════════

func _mover_downed_resolver(_mover, _mover_start_hex, _candidate_reactors: Array) -> Dictionary:
	return {"mover_downed": true}


func test_returned_decision_always_includes_path_key_for_a_committed_stride() -> void:
	var ai = AIClass.new()
	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_true(result.has("path"), "a committed Stride decision must include the 'path' key")
	assert_true(result.get("path", []).size() >= 2, "the reported path must be a genuine, non-degenerate hex sequence")


func test_returned_decision_includes_path_key_even_when_stride_is_cancelled_by_lethal_opportunistic_strike() -> void:
	var ai = AIClass.new()
	ai.set_stride_reaction_resolver_fn(Callable(self, "_mover_downed_resolver"))

	var origin_hex = HexCoordClass.new(0, 0)
	var combatant: Dictionary = _melee_combatant(origin_hex)
	var target_hex = HexCoordClass.new(4, 0)
	var target: Dictionary = _target("Titus", target_hex)
	var action_economy = ActionEconomyClass.new()
	action_economy.start_of_turn()

	var result: Dictionary = await ai.decide_action(combatant, [target], action_economy, [])

	assert_eq(result.get("action_type", ""), "", "a lethal Opportunistic Strike must cancel the Stride -- the no-action sentinel is reported")
	assert_true(
		combatant["hex_coord"].equals(origin_hex),
		"the mover must remain at its origin hex -- Movement.stride() must never be called once mover_downed is reported"
	)
	assert_true(result.has("path"), "even a cancelled Stride decision must include the 'path' key -- it was already computed before the reaction window resolved")
	var cancelled_path: Array = result.get("path", [])
	assert_eq(cancelled_path.size(), 2, "the cancelled decision's 'path' must be the direct 2-element fallback (no pathfinder seam wired in this test)")
	assert_true(cancelled_path[0].equals(origin_hex), "the fallback path's first hex must be the mover's origin")
	assert_eq(
		HexMathClass.hex_distance(cancelled_path[1], target_hex), 1,
		"fixture assumption: the chosen best_destination (the fallback path's second hex) must land adjacent to the target"
	)
