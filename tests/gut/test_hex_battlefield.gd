extends GutTest
## tests/gut/test_hex_battlefield.gd — FEAT-005 (US-005 / FR-004, NFR-001)
##
## GUT test suite for scenes/battlefield/HexBattlefield.gd — the flat-top hex
## battlefield renderer. Reuses the EXISTING domain hex/position data
## (core/geometry/hex_coord.gd, core/domain/combatant.gd) loaded via the
## already-tested infrastructure/resource_encounter_repository.gd adapter,
## exactly like tests/unit/presentation/test_hex_grid_view_mapping.gd already
## does for the prior hex-rendering feature — no new fixture/data path is
## introduced here.
##
## Verifies (test_criteria):
##   1. Each combatant's rendered hex coordinate matches its domain
##      HexPosition (q, r).
##   2. HexBattlefield instantiates one CombatantReadout per combatant (the
##      per-combatant readout half of this feature).
##   3. Code-review guardrail (source-inspection, defense-in-depth alongside
##      the human code-review checklist item): HexBattlefield.gd contains no
##      reach/damage/hit computation — it is read-and-render only (ADR-001).

const HexBattlefieldScene: PackedScene = preload("res://scenes/battlefield/HexBattlefield.tscn")
const HexBattlefieldClass: GDScript = preload("res://scenes/battlefield/HexBattlefield.gd")
const CombatantReadoutClass: GDScript = preload("res://scenes/battlefield/CombatantReadout.gd")
const ResourceEncounterRepositoryClass: GDScript = preload("res://infrastructure/resource_encounter_repository.gd")

const HEX_BATTLEFIELD_SOURCE_PATH: String = "res://scenes/battlefield/HexBattlefield.gd"
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

var _combatants: Array = []
var _battlefield = null


func before_each() -> void:
	var repo = ResourceEncounterRepositoryClass.new()
	_combatants = repo.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	_battlefield = HexBattlefieldScene.instantiate()
	add_child_autofree(_battlefield)


func test_prologue_encounter_yields_at_least_one_combatant() -> void:
	assert_true(_combatants.size() > 0, "prologue_encounter.tres must yield at least one combatant")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: rendered hex coordinate matches domain HexPosition (q, r).
# ══════════════════════════════════════════════════════════════════════════

func test_rendered_hex_position_matches_domain_hex_position_for_every_combatant() -> void:
	_battlefield.load_combatants(_combatants)
	for combatant in _combatants:
		var rendered: Dictionary = _battlefield.get_hex_position(combatant.combatant_id)
		assert_eq(
			rendered.get("q", null), combatant.hex_coord.q,
			"rendered q must match domain HexPosition.q for %s" % combatant.combatant_id
		)
		assert_eq(
			rendered.get("r", null), combatant.hex_coord.r,
			"rendered r must match domain HexPosition.r for %s" % combatant.combatant_id
		)


func test_unknown_combatant_id_yields_empty_hex_position() -> void:
	_battlefield.load_combatants(_combatants)
	assert_eq(_battlefield.get_hex_position("does_not_exist"), {})


func test_reload_does_not_leak_stale_hex_positions() -> void:
	_battlefield.load_combatants(_combatants)
	_battlefield.load_combatants(_combatants)
	assert_eq(
		_battlefield.get_combatant_count(), _combatants.size(),
		"a second load_combatants() call must not leak duplicate entries"
	)


func test_token_screen_position_matches_axial_to_pixel_mapping() -> void:
	_battlefield.load_combatants(_combatants)
	for combatant in _combatants:
		var readout = _battlefield.get_readout(combatant.combatant_id)
		assert_not_null(readout, "get_readout() must return a CombatantReadout for %s" % combatant.combatant_id)
		if readout == null:
			continue
		var expected: Vector2 = HexBattlefieldClass.axial_to_pixel(combatant.hex_coord)
		assert_almost_eq(readout.position, expected, Vector2(0.01, 0.01))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: one CombatantReadout instantiated per combatant.
# ══════════════════════════════════════════════════════════════════════════

func test_load_combatants_instantiates_one_readout_per_combatant() -> void:
	_battlefield.load_combatants(_combatants)
	assert_eq(_battlefield.get_combatant_count(), _combatants.size())

	var readout_children: int = 0
	for child in _battlefield.get_children():
		if child is CombatantReadoutClass:
			readout_children += 1
	assert_eq(readout_children, _combatants.size())


func test_readout_carries_over_combatant_name() -> void:
	_battlefield.load_combatants(_combatants)
	for combatant in _combatants:
		var readout = _battlefield.get_readout(combatant.combatant_id)
		if readout == null:
			fail_test("missing readout for %s" % combatant.combatant_id)
			continue
		assert_eq(readout.get_status().get("name"), combatant.name)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: round-event forwarding — the battlefield is the aggregation
# point that forwards event_sink_port broadcasts down to every readout
# (ADR-003), without itself computing anything about the event.
# ══════════════════════════════════════════════════════════════════════════

func test_on_round_event_forwards_to_the_matching_readout() -> void:
	const RoundEventsClass = preload("res://core/rules/round_events.gd")
	_battlefield.load_combatants(_combatants, _view_models_for(_combatants))

	var target = _combatants[_combatants.size() - 1]
	var attack_event = RoundEventsClass.AttackEvent.new(1, "Attacker", target.name, 17, "ac", 14, true, false, 4)
	_battlefield.on_round_event(attack_event)

	var readout = _battlefield.get_readout(target.combatant_id)
	assert_eq(readout.get_status().get("hp_current"), 6, "forwarded AttackEvent must reduce the matching readout's HP")


func _view_models_for(combatants: Array) -> Array:
	var view_models: Array = []
	for combatant in combatants:
		view_models.append({
			"combatant_id": combatant.combatant_id,
			"name": combatant.name,
			"hp_current": 10,
			"hp_max": 10,
			"stamina_current": 4,
			"stamina_max": 4,
			"action_budget_remaining": 7,
			"spent": false,
			"conditions": [],
		})
	return view_models


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 (code review guardrail): no reach/damage/hit computation.
# ══════════════════════════════════════════════════════════════════════════

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_contains_no_combat_computation_keywords() -> void:
	var source: String = _read_source(HEX_BATTLEFIELD_SOURCE_PATH).to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "is_adjacent", "compute_ac", "compute_hp",
		"reach", "hit_chance", "randi", "randf", "rng",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"scenes/battlefield/HexBattlefield.gd must contain no combat computation ('%s' found) -- read-and-render only (ADR-001)" % keyword
		)
