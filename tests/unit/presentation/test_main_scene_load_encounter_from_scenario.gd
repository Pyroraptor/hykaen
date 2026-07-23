extends GutTest
## tests/unit/presentation/test_main_scene_load_encounter_from_scenario.gd
##
## GUT test suite for FEAT-010 (US-009 / FR-008, NFR-001):
## MainScene.gd's new load_encounter_from_scenario(scenario, encounter_id)
## public method -- the additive boot hook that drives
## LoadScenarioEncounterUseCase (FEAT-008/FEAT-009) and, on success, feeds
## the result into this composition root's EXISTING `_party`/`_enemies`
## assignment path and EncounterClass.new()/initialize() call (reused
## verbatim, ADR-006) -- WITHOUT touching the existing _ready()/
## PROLOGUE_ENCOUNTER_PATH hardcoded boot path at all (ADR-005/RISK-004:
## this file's diff is strictly additive).
##
## Test criteria covered:
##   1. (Pre-check / regression guard) The existing _ready()/
##      PROLOGUE_ENCOUNTER_PATH boot-path regression suites
##      (tests/unit/test_main_scene_entry_point.gd,
##      tests/unit/test_main_scene_interactive_wiring.gd) are a BLOCKING
##      pre-check for this feature -- run separately by the same GUT
##      invocation this file participates in; this file does not
##      duplicate their coverage.
##   2. load_encounter_from_scenario(prologue_scenario.tres, 'prologue')
##      returns true; `_party` contains live Marigold+Titus Combatant
##      instances; `_enemies` contains one live Skeleton Combatant
##      instance; EncounterClass.initialize() has run (encounter is a real,
##      non-null EncounterClass instance with a rolled turn order).
##   3. Calling load_encounter_from_scenario() with an unknown encounter_id
##      returns false, no crash, and pre-call `_party`/`_enemies` scene
##      state is left completely unmodified. (push_error() itself is
##      exercised -- see the source -- but not asserted via GUT's
##      assert_push_error, which relies on OS.add_logger, a documented
##      Godot 4.4+-only no-op on this project's Godot 4.3 engine; see
##      tests/unit/test_action_economy.gd's identical precedent/note.)

const MainSceneScript = preload("res://MainScene.gd")
const CombatantClass = preload("res://core/domain/combatant.gd")
const EncounterClass = preload("res://core/combat/encounter.gd")
const ScenarioResourceClass = preload("res://data/scenarios/scenario_resource.gd")

const PROLOGUE_SCENARIO_PATH := "res://data/scenarios/prologue_scenario.tres"
const PROLOGUE_ENCOUNTER_ID := "prologue"


func _build_main_scene():
	var instance = MainSceneScript.new()
	return instance


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: happy path -- returns true, live party/enemy Combatants, encounter initialized
# ══════════════════════════════════════════════════════════════════════════════

func test_load_encounter_from_scenario_happy_path_populates_live_combatants() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load")

	var instance = _build_main_scene()
	autofree(instance)

	var ok: bool = instance.load_encounter_from_scenario(scenario, PROLOGUE_ENCOUNTER_ID)

	assert_true(ok, "load_encounter_from_scenario() must return true for the real prologue_scenario.tres fixture")

	assert_eq(instance._party.size(), 2, "_party must contain exactly 2 live combatants (Titus + Marigold)")
	var party_names: Array = []
	for combatant in instance._party:
		assert_is(combatant, CombatantClass, "every _party entry must be a live Combatant instance")
		party_names.append(combatant.name)
	assert_true(party_names.has("Titus"), "_party must contain a live Titus Combatant")
	assert_true(party_names.has("Marigold"), "_party must contain a live Marigold Combatant")

	assert_eq(instance._enemies.size(), 1, "_enemies must contain exactly 1 live combatant (Skeleton)")
	if instance._enemies.size() == 1:
		assert_is(instance._enemies[0], CombatantClass, "the _enemies entry must be a live Combatant instance")
		assert_eq(instance._enemies[0].name, "Skeleton", "_enemies must contain a live Skeleton Combatant")

	assert_is(instance.encounter, EncounterClass, "encounter must be a real EncounterClass instance")
	assert_true(
		instance.encounter._turn_order.size() > 0,
		"EncounterClass.initialize() must have run (a non-empty turn order was rolled)"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: unknown encounter_id -- returns false, push_error, no mutation
# ══════════════════════════════════════════════════════════════════════════════

func test_load_encounter_from_scenario_unknown_encounter_id_returns_false_without_mutation() -> void:
	var scenario = ResourceLoader.load(PROLOGUE_SCENARIO_PATH)
	assert_not_null(scenario, "fixture assumption: prologue_scenario.tres must load")

	var instance = _build_main_scene()
	autofree(instance)

	# Snapshot pre-call state -- both fields default to empty arrays before
	# any boot path has run against this freshly-`.new()`'d instance.
	var party_before: Array = instance._party.duplicate()
	var enemies_before: Array = instance._enemies.duplicate()
	var encounter_before = instance.encounter

	var ok: bool = instance.load_encounter_from_scenario(scenario, "no-such-encounter-id")

	assert_false(ok, "load_encounter_from_scenario() must return false for an unknown encounter_id")

	assert_eq(instance._party, party_before, "_party must be left completely unmodified on failure")
	assert_eq(instance._enemies, enemies_before, "_enemies must be left completely unmodified on failure")
	assert_eq(instance.encounter, encounter_before, "encounter must be left completely unmodified on failure")


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1 (static complement): load_encounter_from_scenario is additive --
# it must not appear inside _ready()'s own body, i.e. it is never called from
# the existing hardcoded boot path (ADR-005/RISK-004: strictly additive diff).
# ══════════════════════════════════════════════════════════════════════════════

func test_ready_source_does_not_invoke_load_encounter_from_scenario() -> void:
	var file := FileAccess.open("res://MainScene.gd", FileAccess.READ)
	assert_not_null(file, "MainScene.gd must be readable")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	var ready_start: int = content.find("func _ready() -> void:")
	assert_true(ready_start >= 0, "MainScene.gd must still declare _ready()")
	var next_func_start: int = content.find("\nfunc ", ready_start + 1)
	assert_true(next_func_start > ready_start, "must be able to locate the end of _ready()'s body")

	# The raw substring from "func _ready() -> void:" up to the next "\nfunc "
	# also swallows any doc-comment block sitting directly ABOVE that next
	# function (e.g. this very feature's own load_encounter_from_scenario()
	# doc header, which necessarily mentions its own name many times) --
	# strip every comment line (trimmed text starting with '#') before
	# searching, so this check only sees _ready()'s actual executable body.
	var ready_body_raw: String = content.substr(ready_start, next_func_start - ready_start)
	var code_lines: Array = []
	for line in ready_body_raw.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	var ready_body_code_only: String = "\n".join(code_lines)

	assert_false(
		ready_body_code_only.contains("load_encounter_from_scenario"),
		"_ready() must not call load_encounter_from_scenario() -- the existing hardcoded boot path is left untouched (RISK-004)"
	)
