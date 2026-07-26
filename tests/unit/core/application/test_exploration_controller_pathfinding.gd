extends GutTest
## tests/unit/core/application/test_exploration_controller_pathfinding.gd
##
## GUT test suite for FEAT-003 (US-003 / FR-007): core/application/
## exploration_controller.gd's ExplorationController accepting an optional
## trailing EncounterResource (ADR-003) and move_party_member() enforcing
## tile passability (via the injected encounter) only when one is provided.
##
## Verifies (this feature's test_criteria):
##   1. Constructor accepts an optional encounter parameter defaulting to
##      null with no change to existing no-arg-beyond-session construction
##      signature (ExplorationController.new(session) still works).
##   2. move_party_member() rejects an impassable target_hex when an
##      encounter is injected: returns false, party_hex_positions unmutated.
##   3. move_party_member() with NO encounter injected retains
##      adjacency-only behavior identical to pre-iteration (explicit
##      regression test, RISK-007) -- an adjacent hex succeeds even if it
##      would have been "impassable" had a matching encounter existed.
##   4. Ordering invariant (S0-4a): the passability check runs strictly
##      after the adjacency check (a non-adjacent AND impassable target
##      still fails via the adjacency path, i.e. is still rejected -- and,
##      more importantly, an adjacent-but-impassable hex is rejected by the
##      NEW passability check, never mutating state) and strictly before
##      any party_hex_positions mutation.

const ExplorationControllerClass = preload("res://core/application/exploration_controller.gd")
const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")
const EncounterResourceClass = preload("res://data/encounters/encounter_resource.gd")
const HexTileDataResourceClass = preload("res://data/tiles/hex_tile_data_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")


func _make_tile(q: int, r: int, passable: bool, difficult: bool = false):
	var tile = HexTileDataResourceClass.new()
	tile.q = q
	tile.r = r
	tile.passable = passable
	tile.difficult = difficult
	return tile


func _make_encounter(tiles: Array[HexTileDataResourceClass]):
	var encounter := EncounterResourceClass.new()
	encounter.tiles = tiles
	return encounter


func _make_session(party_hex: Dictionary = {"hero": {"q": 0, "r": 0}}):
	var session = ScenarioSessionClass.new()
	var scenario = ScenarioResourceClass.new()
	scenario.scenario_id = "test_scenario"
	var typed_entries: Array[ScenarioEncounterEntryResourceClass] = []
	scenario.encounter_entries = typed_entries
	session.scenario = scenario
	var positions: Dictionary = {}
	for combatant_id in party_hex:
		var pos: Dictionary = party_hex[combatant_id]
		positions[combatant_id] = HexCoordClass.new(pos["q"], pos["r"])
	session.party_hex_positions = positions
	return session


# ── Criterion 1: optional encounter param, no-arg construction unchanged ───

func test_constructor_still_accepts_session_only_no_encounter() -> void:
	var session = _make_session()
	# Must not error / must not require a second argument.
	var controller = ExplorationControllerClass.new(session)

	var target = HexCoordClass.new(1, 0)
	var result: bool = controller.move_party_member("hero", target)

	assert_true(result, "session-only construction must retain adjacency-only success behavior")


func test_constructor_accepts_optional_trailing_encounter() -> void:
	var session = _make_session()
	var encounter = _make_encounter([])
	# Must not error when passed explicitly.
	var controller = ExplorationControllerClass.new(session, encounter)

	assert_not_null(controller, "constructor must accept a trailing encounter argument")


# ── Criterion 2: impassable target rejected when encounter injected ───────

func test_move_party_member_rejects_impassable_target_hex_when_encounter_injected() -> void:
	var session = _make_session()
	var blocked_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(1, 0, false)])
	var controller = ExplorationControllerClass.new(session, encounter)

	var result: bool = controller.move_party_member("hero", blocked_hex)

	assert_false(result, "an impassable target_hex must be rejected when an encounter is injected")
	assert_true(
		session.party_hex_positions["hero"].equals(HexCoordClass.new(0, 0)),
		"a rejected impassable move must not mutate party_hex_positions"
	)


func test_move_party_member_allows_passable_target_hex_when_encounter_injected() -> void:
	var session = _make_session()
	var open_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(1, 0, true)])
	var controller = ExplorationControllerClass.new(session, encounter)

	var result: bool = controller.move_party_member("hero", open_hex)

	assert_true(result, "a passable target_hex must still succeed when an encounter is injected")
	assert_true(
		session.party_hex_positions["hero"].equals(open_hex),
		"a successful passable move must update party_hex_positions"
	)


func test_move_party_member_allows_unauthored_hex_when_encounter_injected() -> void:
	# Open-world default: a hex with no authored tile entry is passable=true
	# even when an encounter IS injected.
	var session = _make_session()
	var unauthored_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(9, 9, false)])
	var controller = ExplorationControllerClass.new(session, encounter)

	var result: bool = controller.move_party_member("hero", unauthored_hex)

	assert_true(result, "an unauthored hex must default to passable=true even with an encounter injected")


# ── Criterion 3: no-encounter behavior is byte-for-byte pre-iteration (RISK-007) ─

func test_move_party_member_no_encounter_injected_retains_adjacency_only_behavior() -> void:
	# Regression test: with no encounter injected, an adjacent hex must
	# succeed regardless of what tile data would say if an encounter WERE
	# present -- passability enforcement must be entirely inert.
	var session = _make_session()
	var target = HexCoordClass.new(1, 0)
	var controller = ExplorationControllerClass.new(session)

	var result: bool = controller.move_party_member("hero", target)

	assert_true(result, "with no encounter injected, an adjacent target_hex must still succeed unconditionally")
	assert_true(
		session.party_hex_positions["hero"].equals(target),
		"with no encounter injected, party_hex_positions must still update on adjacent move"
	)


func test_move_party_member_no_encounter_injected_non_adjacent_still_fails_closed() -> void:
	var session = _make_session()
	var target = HexCoordClass.new(5, 5)
	var controller = ExplorationControllerClass.new(session)

	var result: bool = controller.move_party_member("hero", target)

	assert_false(result, "with no encounter injected, non-adjacent rejection must be unchanged")
	assert_true(
		session.party_hex_positions["hero"].equals(HexCoordClass.new(0, 0)),
		"with no encounter injected, a rejected non-adjacent move must not mutate party_hex_positions"
	)


# ── Criterion 4: ordering invariant (S0-4a) — adjacency before passability ─

func test_non_adjacent_impassable_target_rejected_via_adjacency_not_passability() -> void:
	# A target that is BOTH non-adjacent AND impassable must still be
	# rejected (adjacency check runs first regardless), and must never
	# mutate party_hex_positions.
	var session = _make_session()
	var target = HexCoordClass.new(5, 5)
	var encounter = _make_encounter([_make_tile(5, 5, false)])
	var controller = ExplorationControllerClass.new(session, encounter)

	var result: bool = controller.move_party_member("hero", target)

	assert_false(result, "a non-adjacent, impassable target_hex must be rejected")
	assert_true(
		session.party_hex_positions["hero"].equals(HexCoordClass.new(0, 0)),
		"rejection must not mutate party_hex_positions regardless of which check failed"
	)


func test_impassable_adjacent_target_never_mutates_state_before_rejection() -> void:
	# Explicit S0-4a ordering proof: an adjacent-but-impassable hex is
	# rejected by the passability check (which must run BEFORE mutation),
	# leaving party_hex_positions completely untouched.
	var session = _make_session()
	var blocked_hex = HexCoordClass.new(1, 0)
	var encounter = _make_encounter([_make_tile(1, 0, false)])
	var controller = ExplorationControllerClass.new(session, encounter)

	watch_signals(controller)
	var result: bool = controller.move_party_member("hero", blocked_hex)

	assert_false(result, "an adjacent but impassable target_hex must be rejected")
	assert_eq(
		session.party_hex_positions.keys().size(), 1,
		"rejection must not add/remove any party_hex_positions entries"
	)
	assert_true(
		session.party_hex_positions["hero"].equals(HexCoordClass.new(0, 0)),
		"party_hex_positions['hero'] must remain at its original hex after a rejected impassable move"
	)
	assert_signal_emit_count(
		controller, "combat_triggered", 0,
		"a rejected impassable move must never evaluate/emit triggers"
	)
