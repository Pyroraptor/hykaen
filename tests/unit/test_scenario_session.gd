extends GutTest
## tests/unit/test_scenario_session.gd
##
## GUT test suite for FEAT-003 (US-002 / FR-001): core/application/
## scenario_session.gd's ScenarioSession runtime application state.
##
## Verifies (this feature's test_criteria):
##   1. is_encounter_complete('unknown_id') == false (fail-open).
##   2. mark_encounter_complete('x') then is_encounter_complete('x') == true
##      — 'x' is a real entry within the session's loaded scenario.
##   3. mark_encounter_complete('unknown_id') is a safe no-op when
##      'unknown_id' matches no real entry — no crash, and
##      completed_encounter_ids is left unaffected by the dangling id (both
##      when a scenario IS loaded and when none is loaded at all).
##   4. get_active_encounter_entries() excludes any entry whose
##      encounter_id is in completed_encounter_ids.
##   5. get_active_encounter_entries() on an empty/unset scenario returns
##      an empty array without error.
##   6. Static source-inspection check: scenario_session.gd contains no
##      'extends Node' / presentation-layer imports (ADR-001/RISK-002).

const ScenarioSessionClass = preload("res://core/application/scenario_session.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")
const ScenarioEncounterEntryResourceClass = preload("res://data/scenarios/scenario_encounter_entry_resource.gd")

const SCENARIO_SESSION_PATH: String = "res://core/application/scenario_session.gd"


func _make_entry(encounter_id: String):
	var entry = ScenarioEncounterEntryResourceClass.new()
	entry.encounter_id = encounter_id
	return entry


func _make_scenario(encounter_ids: Array):
	var scenario = ScenarioResourceClass.new()
	scenario.scenario_id = "test_scenario"
	var entries: Array[ScenarioEncounterEntryResource] = []
	for id in encounter_ids:
		entries.append(_make_entry(id))
	scenario.encounter_entries = entries
	return scenario


# ── Criterion 1: fail-open on an unknown id ─────────────────────────────────

func test_is_encounter_complete_unknown_id_returns_false() -> void:
	var session = ScenarioSessionClass.new()
	assert_false(
		session.is_encounter_complete("unknown_id"),
		"is_encounter_complete() must fail-open (false) for an id never marked complete"
	)


func test_is_encounter_complete_unknown_id_returns_false_with_scenario_loaded() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["x", "y"])
	assert_false(
		session.is_encounter_complete("unknown_id"),
		"is_encounter_complete() must fail-open (false) for an id never marked complete, even with a scenario loaded"
	)


# ── Criterion 2: mark then check ────────────────────────────────────────────

func test_mark_encounter_complete_then_is_encounter_complete_true() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["x"])

	session.mark_encounter_complete("x")

	assert_true(
		session.is_encounter_complete("x"),
		"mark_encounter_complete('x') must make is_encounter_complete('x') return true"
	)


func test_mark_encounter_complete_is_idempotent_no_duplicate() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["x"])

	session.mark_encounter_complete("x")
	session.mark_encounter_complete("x")

	assert_eq(
		session.completed_encounter_ids.count("x"), 1,
		"marking the same encounter_id complete twice must not append a duplicate"
	)


# ── Criterion 3: safe no-op on a dangling/unknown id ────────────────────────

func test_mark_encounter_complete_unknown_id_no_scenario_is_safe_no_op() -> void:
	var session = ScenarioSessionClass.new()

	session.mark_encounter_complete("unknown_id")

	assert_eq(
		session.completed_encounter_ids.size(), 0,
		"mark_encounter_complete() with no scenario loaded must not mutate completed_encounter_ids"
	)
	assert_eq(
		session.get_active_encounter_entries().size(), 0,
		"an unrelated/dangling id marked complete must not fabricate any active entries"
	)


func test_mark_encounter_complete_unknown_id_with_scenario_is_safe_no_op() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["real_entry"])

	session.mark_encounter_complete("unknown_id")

	assert_eq(
		session.completed_encounter_ids.size(), 0,
		"a dangling id (matching no real entry) must not be added to completed_encounter_ids"
	)
	assert_eq(
		session.get_active_encounter_entries().size(), 1,
		"the real entry must remain active — an unrelated dangling id must not exclude it"
	)


# ── Criterion 4: active entries exclude completed ones ──────────────────────

func test_get_active_encounter_entries_excludes_completed() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["a", "b", "c"])

	session.mark_encounter_complete("b")

	var active: Array = session.get_active_encounter_entries()
	var active_ids: Array = []
	for entry in active:
		active_ids.append(entry.encounter_id)

	assert_eq(active.size(), 2, "exactly 2 of 3 entries must remain active")
	assert_true(active_ids.has("a"), "entry 'a' must remain active")
	assert_true(active_ids.has("c"), "entry 'c' must remain active")
	assert_false(active_ids.has("b"), "entry 'b' must be excluded once marked complete")


func test_get_active_encounter_entries_returns_all_when_none_completed() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario(["a", "b"])

	assert_eq(
		session.get_active_encounter_entries().size(), 2,
		"with nothing marked complete, every authored entry must be active"
	)


# ── Criterion 5: empty/unset scenario returns empty array, no error ────────

func test_get_active_encounter_entries_on_unset_scenario_returns_empty_array() -> void:
	var session = ScenarioSessionClass.new()
	assert_eq(
		session.get_active_encounter_entries().size(), 0,
		"get_active_encounter_entries() with no scenario loaded must return an empty array, not error"
	)


func test_get_active_encounter_entries_on_scenario_with_no_entries_returns_empty_array() -> void:
	var session = ScenarioSessionClass.new()
	session.scenario = _make_scenario([])
	assert_eq(
		session.get_active_encounter_entries().size(), 0,
		"get_active_encounter_entries() on a scenario with no entries must return an empty array"
	)


# ── Criterion 6: static check — domain/application purity (RISK-002) ───────

func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable to run the RISK-002 static check" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


func test_source_has_no_node_or_control_inheritance() -> void:
	var content: String = _read_source(SCENARIO_SESSION_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("extends Node"), "scenario_session.gd must not extend Node (ADR-001/RISK-002)")
	assert_false(content.contains("extends Control"), "scenario_session.gd must not extend Control (ADR-001/RISK-002)")
	assert_false(content.contains("extends CanvasItem"), "scenario_session.gd must not extend CanvasItem (ADR-001/RISK-002)")
	assert_true(content.contains("extends RefCounted"), "scenario_session.gd must extend RefCounted (ADR-001/RISK-002)")


func test_source_has_no_presentation_layer_imports() -> void:
	var content: String = _read_source(SCENARIO_SESSION_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("res://presentation/"), "scenario_session.gd must not import presentation/ (RISK-002)")
	assert_false(content.contains("preload(\"res://MainScene"), "scenario_session.gd must not import MainScene (RISK-002)")
	assert_false(content.contains("HexGridView"), "scenario_session.gd must not reference HexGridView (RISK-002)")


func test_source_has_no_engine_lifecycle_callbacks() -> void:
	var content: String = _read_source(SCENARIO_SESSION_PATH)
	if content.is_empty():
		return
	assert_false(content.contains("func _ready("), "scenario_session.gd must not define _ready() (ADR-001)")
	assert_false(content.contains("func _process("), "scenario_session.gd must not define _process() (ADR-001)")
	assert_false(
		content.contains("func _physics_process("),
		"scenario_session.gd must not define _physics_process() (ADR-001)"
	)
