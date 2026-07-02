## scenes/battlefield/CombatantReadout.gd — CombatantReadout (FEAT-005 / US-005)
##
## Presentation layer (Clean Architecture): a single combatant's read-only,
## event-driven readout — name/HP/Stamina/action budget/Spent/conditions —
## the per-combatant half of the hex battlefield renderer feature
## (scenes/battlefield/HexBattlefield.gd instantiates one of these per
## combatant, mirroring the existing precedent set by
## presentation/hex_grid_view.gd + presentation/combatant_token_view.gd for
## the earlier hex-rendering feature, and presentation/status_panel_view.gd
## for the earlier per-combatant status projection).
##
## CombatantReadout is populated in exactly two ways, both read-only with
## respect to domain state:
##   1. initialize(view_model) — an initial SNAPSHOT load, mirroring
##      presentation/status_panel_view.gd's load_combatants() contract. The
##      view_model Dictionary carries combatant_id/name/hp_current/hp_max/
##      stamina_current/stamina_max/action_budget_remaining/spent/conditions.
##   2. on_round_event(event) — incremental updates driven EXCLUSIVELY by the
##      typed round events declared in core/rules/round_events.gd (ADR-003:
##      Presentation subscribes to EventSinkPort broadcasts, never polls
##      domain state). Recognizes an AttackEvent-shaped payload targeting
##      this readout's combatant (by name) and a CombatantDefeatedEvent-
##      shaped payload naming this combatant. Any other event, or one for a
##      different combatant, is a silent no-op.
##
## CombatantReadout performs NO melee-range/damage/hit computation of any
## kind — it only ever reads fields already present on an event
## (damage_final, target_hp_after) and reflects them; it never rolls dice,
## computes AC/HP, or evaluates tile-to-tile adjacency (ADR-001, verified by
## tests/gut/test_combatant_readout.gd's source-inspection guardrail and by
## code review). It declares no per-frame update callback of its own --
## every state change happens synchronously inside on_round_event(), so
## readouts update purely in response to events, never by polling.

class_name CombatantReadout
extends Node2D

## Row keys copied verbatim into get_status()'s return shape from the view
## model passed to initialize() (mirrors presentation/status_panel_view.gd's
## _ROW_FIELDS convention).
const _FIELDS: Array = [
	"combatant_id", "name", "hp_current", "hp_max",
	"stamina_current", "stamina_max",
	"action_budget_remaining", "spent", "conditions",
]

var combatant_id: String = ""
var display_name: String = ""
var hp_current: int = 0
var hp_max: int = 0
var stamina_current: int = 0
var stamina_max: int = 0
var action_budget_remaining: int = 0
var spent: bool = false
var conditions: Array = []

## The Label this readout draws its text on -- created directly in _init()
## (rather than via an @onready reference into a companion .tscn) so
## CombatantReadout can be instantiated standalone with `.new()`, exactly
## like presentation/combatant_token_view.gd's sibling relationship to
## presentation/hex_grid_view.gd, but without requiring its own scene file.
var _label: Label


func _init() -> void:
	_label = Label.new()
	_label.name = "ReadoutLabel"
	add_child(_label)


## initialize(view_model) → void — (re)populates this readout from an
## initial snapshot Dictionary. Any field absent from `view_model` falls
## back to a sensible empty default (mirrors
## presentation/status_panel_view.gd's _default_for_field()).
func initialize(view_model: Dictionary) -> void:
	combatant_id             = view_model.get("combatant_id", "")
	display_name             = view_model.get("name", "")
	hp_current                = view_model.get("hp_current", 0)
	hp_max                     = view_model.get("hp_max", 0)
	stamina_current            = view_model.get("stamina_current", 0)
	stamina_max                = view_model.get("stamina_max", 0)
	action_budget_remaining   = view_model.get("action_budget_remaining", 0)
	spent                      = view_model.get("spent", false)
	conditions                 = Array(view_model.get("conditions", []))
	_refresh_label()


## get_status() → Dictionary — a snapshot Dictionary with keys combatant_id/
## name/hp_current/hp_max/stamina_current/stamina_max/
## action_budget_remaining/spent/conditions, for test/inspection assertions.
func get_status() -> Dictionary:
	return {
		"combatant_id":            combatant_id,
		"name":                    display_name,
		"hp_current":              hp_current,
		"hp_max":                  hp_max,
		"stamina_current":         stamina_current,
		"stamina_max":             stamina_max,
		"action_budget_remaining": action_budget_remaining,
		"spent":                   spent,
		"conditions":              conditions.duplicate(),
	}


## get_display_text() → String — the exact text rendered on this readout's
## Label, for display-level assertions.
func get_display_text() -> String:
	return _label.text if _label != null else ""


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes:
##   - an AttackEvent-shaped payload (`target_name` plus `damage_final` or
##     `target_hp_after`) naming THIS readout's combatant.
##   - a CombatantDefeatedEvent-shaped payload (`name` plus `defeated_by`)
##     naming THIS readout's combatant.
## Any other event, or one naming a different combatant, is a silent no-op.
func on_round_event(event) -> void:
	if event == null or display_name == "":
		return

	if _event_get(event, "target_name", "") == display_name and (
		_event_has(event, "damage_final") or _event_has(event, "target_hp_after")
	):
		_apply_attack_event(event)
	elif _event_get(event, "name", "") == display_name and _event_has(event, "defeated_by"):
		_apply_defeated_event(event)


# ── Internal helpers ─────────────────────────────────────────────────────

func _apply_attack_event(event) -> void:
	if _event_has(event, "target_hp_after"):
		hp_current = _event_get(event, "target_hp_after", hp_current)
	elif _event_has(event, "damage_final"):
		hp_current = maxi(hp_current - _event_get(event, "damage_final", 0), 0)
	_refresh_label()


func _apply_defeated_event(_event) -> void:
	hp_current = 0
	if not conditions.has("Defeated"):
		conditions.append("Defeated")
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var conditions_text: String = ", ".join(conditions) if conditions.size() > 0 else "None"
	_label.text = "%s — HP %d/%d | Stamina %d/%d | Actions %d | Spent: %s | Conditions: %s" % [
		display_name, hp_current, hp_max, stamina_current, stamina_max,
		action_budget_remaining, "Yes" if spent else "No", conditions_text,
	]


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## CombatantReadout never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default
