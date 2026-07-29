extends GutTest
## tests/unit/test_exploration_mode_controller_selection.gd — FEAT-002
## (US-003 / FR-005, ADR-002, mitigates RISK-003).
##
## GUT suite for presentation/exploration_mode_controller.gd's new
## `_select_party_member(id)` helper — the single authorized write path for
## selection state (design notes: "SelectPartyMemberUseCase.execute(id):
## sets SelectionState, calls SelectionRenderPort.set_selected_combatant(id)
## ... This is the single mutation path for selection (US-003) — all other
## call sites are refactored to route through it.").
##
## test_criteria covered:
##   1. _select_party_member(id) sets selected_party_member_id to id.
##   2. _select_party_member(id) calls hex_grid_view.set_selected_combatant(id)
##      and get_selected_combatant() reflects id afterward.
##   3. boot-time auto-select routes through _select_party_member() rather
##      than assigning selected_party_member_id directly — proven via a
##      call-count spy subclass overriding _select_party_member() (this
##      codebase's established "extends <real script path>, override, call
##      super." spy convention — see tests/unit/test_dodge_reaction.gd's own
##      SpyActionEconomy).
##   4. _select_party_member("") clears both selected_party_member_id and
##      hex_grid_view.get_selected_combatant().

const ExplorationModeControllerClass = preload("res://presentation/exploration_mode_controller.gd")
const NewGameFactoryClass = preload("res://core/application/new_game_factory.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

## _FakeHexGridView — a hand-written fake exposing the `hex_clicked`/
## `hex_hovered` signals boot() connects to (mirrors tests/gut/
## test_exploration_mode_controller.gd's own _FakeHexGridView convention),
## PLUS a real, stateful set_selected_combatant()/get_selected_combatant()
## round-trip so this suite can assert the SelectionRenderPort contract
## (FEAT-001) directly rather than merely recording a call count.
## set_tile_terrain() is intentionally absent: the authored prologue
## scenario's boot encounter has an empty `tiles` array, so boot()'s own
## "paint terrain" loop never iterates and never calls it (see
## ExplorationModeController.boot()'s own doc for this precedent).
class _FakeHexGridView:
	extends RefCounted
	signal hex_clicked(hex_coord)
	signal hex_hovered(hex_coord)

	var _selected_combatant_id: String = ""
	var set_selected_combatant_calls: Array = []

	func set_path_overlay(_path: Array, _color: Color) -> void:
		pass

	func clear_overlays() -> void:
		pass

	func set_selected_combatant(id: String) -> void:
		set_selected_combatant_calls.append(id)
		_selected_combatant_id = id

	func get_selected_combatant() -> String:
		return _selected_combatant_id


## _FakeHexCombatant — minimal duck-typed stand-in for boot()'s
## `hex_combatants` entries (`combatant_id`/`hex_coord`), mirrors tests/gut/
## test_exploration_mode_controller.gd's own _FakeHexCombatant.
class _FakeHexCombatant:
	extends RefCounted
	var combatant_id: String
	var hex_coord

	func _init(p_combatant_id: String, p_hex_coord) -> void:
		combatant_id = p_combatant_id
		hex_coord = p_hex_coord


## _SelectPartyMemberSpy — a REAL ExplorationModeController that records
## every _select_party_member() invocation (this codebase's established
## "extends <real script path>, override, call super." spy convention — see
## tests/unit/test_dodge_reaction.gd's own SpyActionEconomy wrapping
## core/rules/action_economy.gd's spend_action()). Because boot() itself
## calls `_select_party_member(...)` as a plain (unqualified) method call,
## GDScript's normal virtual dispatch resolves that call against THIS
## subclass's override, not the base script's own definition — so a call
## count here proves boot()'s auto-select genuinely routes through the
## helper rather than merely happening to produce the same end state via a
## direct field assignment.
class _SelectPartyMemberSpy:
	extends "res://presentation/exploration_mode_controller.gd"

	var select_party_member_call_count: int = 0
	var select_party_member_call_ids: Array = []

	func _select_party_member(id: String) -> void:
		select_party_member_call_count += 1
		select_party_member_call_ids.append(id)
		super._select_party_member(id)


func _make_controller(hex_grid_view) -> ExplorationModeControllerClass:
	var controller := ExplorationModeControllerClass.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})
	return controller


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — _select_party_member(id) sets selected_party_member_id.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_sets_selected_party_member_id() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"_select_party_member(id) must set selected_party_member_id to id"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — _select_party_member(id) calls hex_grid_view.
# set_selected_combatant(id); get_selected_combatant() reflects id after.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_calls_hex_grid_view_set_selected_combatant() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)

	controller._select_party_member("hero_a")

	assert_eq(
		hex_grid_view.set_selected_combatant_calls, ["hero_a"],
		"_select_party_member(id) must call hex_grid_view.set_selected_combatant(id) exactly once, with id"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"hex_grid_view.get_selected_combatant() must reflect id immediately after _select_party_member(id)"
	)


func test_select_party_member_is_a_safe_no_op_state_update_without_a_hex_grid_view() -> void:
	# Defensive null-check contract (mirrors this file's established guard
	# convention): a controller with no hex_grid_view wired must still
	# update selected_party_member_id rather than crashing.
	var controller := ExplorationModeControllerClass.new()

	controller._select_party_member("hero_a")

	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"_select_party_member(id) must still update selected_party_member_id when _hex_grid_view is null"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — boot-time auto-select routes through _select_party_member(),
# not a direct assignment of selected_party_member_id.
# ══════════════════════════════════════════════════════════════════════════

func test_boot_time_auto_select_invokes_select_party_member_helper() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _SelectPartyMemberSpy.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})

	controller.boot([
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0)),
		_FakeHexCombatant.new("hero_b", HexCoordClass.new(1, 0)),
	])

	assert_eq(
		controller.select_party_member_call_count, 1,
		"boot()'s initial auto-select must invoke _select_party_member() exactly once (only for the first seeded party member)"
	)
	assert_eq(
		controller.select_party_member_call_ids, ["hero_a"],
		"boot()'s auto-select must call _select_party_member() with the FIRST seeded hex_combatants entry's id"
	)
	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"boot() must still default selected_party_member_id to the first seeded party member (end-state unchanged by this refactor)"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"boot()'s auto-select, routed through the helper, must also update the HexGridView selection-render cache"
	)


func test_boot_time_auto_select_never_calls_helper_when_already_selected() -> void:
	# Mirrors ExplorationModeController.boot()'s own "never overwrites an
	# already-assigned selection" contract: pre-assigning
	# selected_party_member_id before boot() must leave the helper entirely
	# uninvoked (0 calls), not just invoked with the pre-assigned value.
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _SelectPartyMemberSpy.new()
	controller.setup({
		"hex_grid_view": hex_grid_view,
		"scenario_path": NewGameFactoryClass.PROLOGUE_SCENARIO_PATH_CONST,
	})
	controller.selected_party_member_id = "hero_b"

	controller.boot([
		_FakeHexCombatant.new("hero_a", HexCoordClass.new(0, 0)),
		_FakeHexCombatant.new("hero_b", HexCoordClass.new(1, 0)),
	])

	assert_eq(
		controller.select_party_member_call_count, 0,
		"boot() must never invoke _select_party_member() when selected_party_member_id was already assigned"
	)
	assert_eq(
		controller.selected_party_member_id, "hero_b",
		"a pre-assigned selected_party_member_id must survive boot() untouched"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4 — _select_party_member("") clears both caches.
# ══════════════════════════════════════════════════════════════════════════

func test_select_party_member_empty_string_clears_selection() -> void:
	var hex_grid_view := _FakeHexGridView.new()
	var controller := _make_controller(hex_grid_view)
	controller._select_party_member("hero_a")
	assert_eq(
		controller.selected_party_member_id, "hero_a",
		"sanity check: a party member must be selected before it can be cleared"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "hero_a",
		"sanity check: the hex_grid_view selection cache must also be set before it can be cleared"
	)

	controller._select_party_member("")

	assert_eq(
		controller.selected_party_member_id, "",
		"_select_party_member(\"\") must clear selected_party_member_id"
	)
	assert_eq(
		hex_grid_view.get_selected_combatant(), "",
		"_select_party_member(\"\") must clear hex_grid_view's selection (via set_selected_combatant(\"\"))"
	)
