extends GutTest
## tests/ui/test_exploration_hud_rest_button.gd — FEAT-007 (US-006; FR-008;
## iteration AB-0, rest mechanics steel thread).
##
## GUT test suite for presentation/exploration_hud.gd's ExplorationHUD — the
## user-facing entry point of the rest-mechanics steel thread. Mirrors
## tests/gut/test_verb_bar_view.gd's "real scene, fake collaborators"
## convention: the REAL res://presentation/exploration_hud.tscn is
## instantiated and driven through its public surface; the party fed to it
## is a small set of duck-typed fake Combatant/ItemResource doubles (mirrors
## tests/unit/test_long_rest_use_case.gd's FakeItem convention) rather than
## real domain objects, since ExplorationHUD's "needs rest" scan is
## explicitly duck-typed (design notes: reads hp_current/hp_max/stamina/
## stamina_max/equipped_items via plain field access, matching every other
## use case's `_duck_get()` convention in this codebase).
##
## Covers all five test_criteria from the feature spec:
##   1. Rest Button is visible in EXPLORATION, hidden in COMBAT.
##   2. Rest Button is disabled when every party member is fully rested (HP==max,
##      stamina==max, no discharged Mage item).
##   3. Rest Button is enabled when at least one party member needs rest.
##   4. Pressing the Rest Button while enabled emits the open-Rest-Panel signal.
##   5. The needs-rest scan performs no mutation of any Combatant field (pure
##      read-only query).

const ExplorationHudScene: PackedScene = preload("res://presentation/exploration_hud.tscn")
const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")

## FakeCombatant — a tiny duck-typed double exposing exactly the fields
## ExplorationHUD's needs-rest scan reads (hp_current/hp_max/stamina/
## stamina_max/equipped_items), mirroring tests/unit/test_long_rest_use_case.gd's
## FakeItem "small real fake" philosophy.
class FakeCombatant:
	var hp_current: int
	var hp_max: int
	var stamina: int
	var stamina_max: int
	var equipped_items: Array

	func _init(p_hp_current: int, p_hp_max: int, p_stamina: int, p_stamina_max: int, p_equipped_items: Array = []) -> void:
		hp_current = p_hp_current
		hp_max = p_hp_max
		stamina = p_stamina
		stamina_max = p_stamina_max
		equipped_items = p_equipped_items


## FakeItem — a tiny duck-typed double exposing is_charged/energy_cost,
## mirroring tests/unit/test_long_rest_use_case.gd's FakeItem exactly.
class FakeItem:
	var is_charged: bool
	var energy_cost: int

	func _init(p_is_charged: bool, p_energy_cost: int) -> void:
		is_charged = p_is_charged
		energy_cost = p_energy_cost


func _fully_rested_party() -> Array:
	return [
		FakeCombatant.new(10, 10, 5, 5, [FakeItem.new(true, 1)]),
		FakeCombatant.new(20, 20, 3, 3, []),
	]


var _hud = null


func before_each() -> void:
	_hud = ExplorationHudScene.instantiate()
	add_child_autofree(_hud)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: visible in EXPLORATION, hidden in COMBAT.
# ══════════════════════════════════════════════════════════════════════════

func test_rest_button_visible_in_exploration_mode() -> void:
	_hud.set_game_mode(GameModeReaderClass.EXPLORATION)

	assert_true(_hud.get_rest_button().visible, "Rest Button must be visible in EXPLORATION mode")


func test_rest_button_hidden_in_combat_mode() -> void:
	_hud.set_game_mode(GameModeReaderClass.COMBAT)

	assert_false(_hud.get_rest_button().visible, "Rest Button must be hidden in COMBAT mode")


func test_rest_button_toggles_visibility_across_mode_transitions() -> void:
	_hud.set_game_mode(GameModeReaderClass.COMBAT)
	assert_false(_hud.get_rest_button().visible)

	_hud.set_game_mode(GameModeReaderClass.EXPLORATION)
	assert_true(_hud.get_rest_button().visible, "re-entering EXPLORATION must re-show the Rest Button")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: disabled when every party member is fully rested.
# ══════════════════════════════════════════════════════════════════════════

func test_rest_button_disabled_when_party_fully_rested() -> void:
	_hud.set_party(_fully_rested_party())

	assert_true(_hud.get_rest_button().disabled, "Rest Button must be disabled when no party member needs rest")


func test_rest_button_disabled_before_any_party_configured() -> void:
	assert_true(_hud.get_rest_button().disabled, "Rest Button must be disabled before set_party() is ever called")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: enabled when at least one party member needs rest.
# ══════════════════════════════════════════════════════════════════════════

func test_rest_button_enabled_when_a_party_member_has_hp_below_max() -> void:
	var party := _fully_rested_party()
	party[0].hp_current = 5
	_hud.set_party(party)

	assert_false(_hud.get_rest_button().disabled, "Rest Button must be enabled when a party member has HP < max")


func test_rest_button_enabled_when_a_party_member_has_stamina_below_max() -> void:
	var party := _fully_rested_party()
	party[1].stamina = 0
	_hud.set_party(party)

	assert_false(_hud.get_rest_button().disabled, "Rest Button must be enabled when a party member has stamina < max")


func test_rest_button_enabled_when_a_party_member_has_a_discharged_mage_item() -> void:
	var party := _fully_rested_party()
	party[0].equipped_items = [FakeItem.new(false, 1)]
	_hud.set_party(party)

	assert_false(_hud.get_rest_button().disabled, "Rest Button must be enabled when any equipped item is discharged (is_charged==false, energy_cost>0)")


func test_rest_button_stays_disabled_for_a_discharged_but_never_dischargeable_item() -> void:
	var party := _fully_rested_party()
	party[0].equipped_items = [FakeItem.new(false, 0)]
	_hud.set_party(party)

	assert_true(_hud.get_rest_button().disabled, "an item with energy_cost==0 never discharges, so it must not enable the Rest Button")


func test_rest_button_ignores_null_entries_in_party() -> void:
	var party := _fully_rested_party()
	party.append(null)
	_hud.set_party(party)

	assert_true(_hud.get_rest_button().disabled, "a null party entry must be skipped, not crash or force-enable")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: pressing the Rest Button while enabled opens the Rest Panel.
# ══════════════════════════════════════════════════════════════════════════

func test_pressing_enabled_rest_button_emits_rest_panel_requested() -> void:
	var party := _fully_rested_party()
	party[0].hp_current = 1
	_hud.set_party(party)

	watch_signals(_hud)
	_hud.get_rest_button().pressed.emit()

	assert_signal_emitted(_hud, "rest_panel_requested")


func test_pressing_disabled_rest_button_does_not_emit_rest_panel_requested() -> void:
	_hud.set_party(_fully_rested_party())

	watch_signals(_hud)
	_hud.get_rest_button().pressed.emit()

	assert_signal_not_emitted(_hud, "rest_panel_requested")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: the needs-rest scan is pure read-only — no Combatant mutation.
# ══════════════════════════════════════════════════════════════════════════

func test_needs_rest_scan_does_not_mutate_any_combatant_field() -> void:
	var party := _fully_rested_party()
	party[0].hp_current = 3
	party[0].equipped_items = [FakeItem.new(false, 2)]

	var before_hp: int = party[0].hp_current
	var before_stamina: int = party[0].stamina
	var before_item_charged: bool = party[0].equipped_items[0].is_charged
	var before_item_cost: int = party[0].equipped_items[0].energy_cost

	_hud.set_party(party)
	_hud.needs_rest()
	_hud.needs_rest()

	assert_eq(party[0].hp_current, before_hp, "needs_rest() must never mutate hp_current")
	assert_eq(party[0].stamina, before_stamina, "needs_rest() must never mutate stamina")
	assert_eq(party[0].equipped_items[0].is_charged, before_item_charged, "needs_rest() must never mutate an item's is_charged")
	assert_eq(party[0].equipped_items[0].energy_cost, before_item_cost, "needs_rest() must never mutate an item's energy_cost")
