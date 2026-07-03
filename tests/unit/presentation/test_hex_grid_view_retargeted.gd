extends GutTest
## tests/unit/presentation/test_hex_grid_view_retargeted.gd — FEAT-004
## (US-004 / FR-013, iteration D "UI Consolidation + Movement UX").
##
## Retargets tests/gut/test_hex_battlefield.gd (FEAT-005), whose subject --
## the duplicate scenes/battlefield/HexBattlefield.gd + CombatantReadout.gd
## widget -- was removed from MainScene's composition root (FEAT-001/P0-2).
## presentation/hex_grid_view.gd is the ONE kept hex-rendering surface; this
## file closes the coverage gaps that suite's deletion would otherwise have
## left open, rather than re-testing what already has an equivalent home:
##
##   old criterion                                    | equivalent coverage
##   --------------------------------------------------+---------------------------------------------------------
##   1. rendered hex position matches domain HexPosition| tests/unit/presentation/test_hex_grid_view_mapping.gd
##      (per combatant)                                 (test_each_token_is_positioned_at_its_combatants_mapped_...)
##      -- re-affirmed directly below for 1:1 traceability
##   2. one CombatantReadout instantiated per combatant  | HexGridView's equivalent (one CombatantTokenView per
##                                                        combatant) is ALSO already covered by
##                                                        test_hex_grid_view_mapping.gd
##                                                        (test_load_combatants_instantiates_one_token_per_combatant)
##   3. code-review guardrail: no reach/damage/hit       | NOT previously covered for hex_grid_view.gd -- added below
##      computation of its own (ADR-001)                 (test_source_contains_no_combat_computation_keywords)
##   round-event forwarding (readout HP updates)          | superseded by presentation/status_panel_view.gd, which
##                                                        already owns HP projection in the kept stack (see
##                                                        tests/unit/presentation/test_status_panel_view_retargeted.gd)
##   unknown combatant id yields empty/no position        | NOT previously covered for hex_grid_view.gd -- added below
##                                                        (test_unknown_combatant_id_get_token_returns_null)
##
## FEAT-157's out-of-radius bounds-validation guard (push_warning() +
## skip-reposition/skip-readout) was specific to scenes/battlefield/
## HexBattlefield.gd's own implementation quirk (FIND-150) and is NOT ported
## here: HexGridView never crashes on an out-of-radius hex_coord (it simply
## renders the token off the drawn background grid), so there is no
## equivalent defect to guard against in the kept stack -- a "test with no
## coverage-equivalence need" per this feature's own test_criteria.

const HexGridViewClass: GDScript = preload("res://presentation/hex_grid_view.gd")
const HexGridViewScene: PackedScene = preload("res://presentation/hex_grid_view.tscn")
const ResourceEncounterRepositoryClass: GDScript = preload("res://infrastructure/resource_encounter_repository.gd")
const HexCoordClass: GDScript = preload("res://core/geometry/hex_coord.gd")

const HEX_GRID_VIEW_SOURCE_PATH: String = "res://presentation/hex_grid_view.gd"
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

const EPSILON: float = 0.01

var _combatants: Array = []
var _hex_grid_view = null


func before_each() -> void:
	var repo = ResourceEncounterRepositoryClass.new()
	_combatants = repo.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)


# ══════════════════════════════════════════════════════════════════════════
# Retarget of Criterion 1 (test_hex_battlefield.gd): rendered hex/screen
# position matches the domain HexPosition (q, r) for every combatant --
# re-affirmed directly against HexGridView for 1:1 traceability, even though
# test_hex_grid_view_mapping.gd already independently proves this.
# ══════════════════════════════════════════════════════════════════════════

func test_rendered_token_position_matches_domain_hex_position_for_every_combatant() -> void:
	assert_true(_combatants.size() > 0, "prologue_encounter.tres must yield at least one combatant")
	_hex_grid_view.load_combatants(_combatants)

	for combatant in _combatants:
		var token = _hex_grid_view.get_token(combatant.combatant_id)
		assert_not_null(token, "get_token() must return the instantiated token for %s" % combatant.combatant_id)
		if token == null:
			continue
		var expected_position: Vector2 = HexGridViewClass.axial_to_pixel(combatant.hex_coord)
		assert_almost_eq(
			token.position, expected_position, Vector2(EPSILON, EPSILON),
			"token for %s must be rendered at axial_to_pixel(hex_coord), matching its domain HexPosition" % combatant.combatant_id
		)


# ══════════════════════════════════════════════════════════════════════════
# New coverage: unknown combatant id yields no rendered position (retargets
# test_hex_battlefield.gd's "unknown combatant id yields empty hex position"
# onto HexGridView's equivalent get_token()/move_token() surface).
# ══════════════════════════════════════════════════════════════════════════

func test_unknown_combatant_id_get_token_returns_null() -> void:
	_hex_grid_view.load_combatants(_combatants)
	assert_null(_hex_grid_view.get_token("does_not_exist"))


func test_move_token_on_unknown_combatant_id_leaves_token_count_unchanged() -> void:
	_hex_grid_view.load_combatants(_combatants)
	var before_count: int = _hex_grid_view.get_token_count()

	_hex_grid_view.move_token("does_not_exist", HexCoordClass.new(2, 2))

	assert_eq(
		_hex_grid_view.get_token_count(), before_count,
		"move_token() for an unknown combatant_id must be a safe no-op, never creating/removing a token"
	)


# ══════════════════════════════════════════════════════════════════════════
# New coverage (code-review guardrail): hex_grid_view.gd contains no reach/
# damage/hit computation of its own -- read-and-render only (ADR-001).
# Retargets test_hex_battlefield.gd's identically-purposed guardrail.
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
	var source: String = _read_source(HEX_GRID_VIEW_SOURCE_PATH).to_lower()
	var forbidden_keywords: Array = [
		"roll_attack", "damage_die", "is_adjacent", "compute_ac", "compute_hp",
		"hit_chance", "randi(", "randf(",
	]
	for keyword in forbidden_keywords:
		assert_eq(
			source.find(keyword), -1,
			"presentation/hex_grid_view.gd must contain no combat computation ('%s' found) -- read-and-render only (ADR-001)" % keyword
		)
