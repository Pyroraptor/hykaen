## presentation/exploration_hud.gd — ExplorationHUD (FEAT-007 / US-006;
## FR-008; iteration AB-0, rest mechanics steel thread).
##
## Presentation layer (Clean Architecture): the user-facing entry point of
## the rest-mechanics steel thread. Renders a single Rest Button as a
## sibling of the existing Layer 1 action/verb bar (presentation/
## verb_bar_view.gd), mirroring that file's "real Control node, driven
## through a small public surface, no framework logic leaking into
## application/domain" convention.
##
## Visibility (design notes' component diagram, RISK-007 mitigation):
## set_game_mode() reads the current game mode through the SAME shared
## core/api/game_mode_reader.gd GameModeReader helper core/api/
## rest_action_guard.gd's RestActionGuard already uses for its own
## out-of-combat execution check — a single shared function so the Rest
## button's VISIBILITY check and the guard's EXECUTION check can never
## structurally diverge on what "current game mode" means. The Rest Button
## is visible whenever the resolved mode is anything other than
## GameModeReader.COMBAT (i.e. EXPLORATION), and hidden in COMBAT.
##
## Enablement: disabled unless needs_rest() — a PURE, READ-ONLY scan over
## the injected party (set_party()) — reports true. needs_rest() is
## deliberately NOT a use case (design notes' api_contracts #5): it performs
## no domain mutation whatsoever, only duck-typed field reads, mirroring the
## SAME `_duck_get()` convention already established by core/application/
## use_cases/long_rest_use_case.gd / short_rest_mage_recharge_use_case.gd —
## so this file can be driven by plain duck-typed test doubles exactly like
## those use cases' own test suites, with no dependency on a concrete
## core/domain/combatant.gd Combatant type. A party member "needs rest" when
## ANY of the following holds:
##   - hp_current < hp_max
##   - stamina < stamina_max
##   - any equipped item has is_charged == false AND energy_cost > 0
##     (a discharged Mage-paradigm item)
##
## Wiring to the Rest Panel: pressing the Rest Button while enabled emits
## `rest_panel_requested` — this file never constructs or reaches into a
## RestPanelController itself (a later feature); the composition root
## (MainScene.gd, out of this feature's scope) is expected to connect that
## signal once the panel exists, mirroring presentation/verb_bar_view.gd's
## own signal-forwarding convention (verb_selection_entered/verb_executed)
## rather than an injected Callable.
class_name ExplorationHUD
extends Control

const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")

## rest_panel_requested() — emitted after press() (or a real Rest Button
## click) succeeds while the button is enabled. No payload: the receiving
## composition root already owns whatever context (party, current
## combatant) the Rest Panel needs.
signal rest_panel_requested

## The live party this HUD scans for "needs rest" — duck-typed entries
## (real core/domain/combatant.gd Combatant instances in production; plain
## test doubles in tests). Never mutated by this file (see needs_rest()).
var _party: Array = []

var _game_mode_reader = GameModeReaderClass.new()

@onready var _rest_button: Button = $RestButton


func _ready() -> void:
	if _rest_button != null:
		_rest_button.pressed.connect(_on_rest_button_pressed)
		_rest_button.disabled = not needs_rest()


## set_game_mode(mode) -> void — resolves `mode` through the shared
## GameModeReader (accepts a plain int, a Dictionary/Object exposing
## `game_mode`, or null — see that file's header) and shows/hides the Rest
## Button: visible whenever the resolved mode != GameModeReader.COMBAT,
## hidden exactly in COMBAT.
func set_game_mode(mode) -> void:
	var resolved_mode: int = _game_mode_reader.read(mode)
	if _rest_button != null:
		_rest_button.visible = resolved_mode != GameModeReaderClass.COMBAT


## set_party(party) -> void — injects the CURRENT party roster and
## refreshes the Rest Button's disabled state from a fresh needs_rest()
## scan. Safe to call repeatedly (e.g. once per exploration-mode frame/turn
## boundary), mirroring presentation/verb_bar_view.gd's
## refresh_availability() re-query convention.
func set_party(party: Array) -> void:
	_party = party
	if _rest_button != null:
		_rest_button.disabled = not needs_rest()


## needs_rest() -> bool — PURE, READ-ONLY scan over the injected party (see
## file header for the exact OR-condition). Performs no mutation of any
## party member or equipped item field — every value below is only ever
## READ via _duck_get(), never written.
func needs_rest() -> bool:
	for combatant in _party:
		if combatant == null:
			continue

		var hp_current: int = int(_duck_get(combatant, "hp_current", 0))
		var hp_max: int = int(_duck_get(combatant, "hp_max", 0))
		if hp_current < hp_max:
			return true

		var stamina: int = int(_duck_get(combatant, "stamina", 0))
		var stamina_max: int = int(_duck_get(combatant, "stamina_max", 0))
		if stamina < stamina_max:
			return true

		var equipped_items: Array = _duck_get(combatant, "equipped_items", [])
		for item in equipped_items:
			if item == null:
				continue
			var is_charged: bool = bool(_duck_get(item, "is_charged", true))
			var energy_cost: int = int(_duck_get(item, "energy_cost", 0))
			if not is_charged and energy_cost > 0:
				return true

	return false


## get_rest_button() -> Button — the rendered Rest Button, for direct test
## inspection/press simulation (mirrors presentation/verb_bar_view.gd's
## get_button() convention).
func get_rest_button() -> Button:
	return _rest_button


## press_rest() -> bool — programmatic equivalent of a real Rest Button
## click (mirrors presentation/verb_bar_view.gd's press() convention).
## Returns whether the Rest Panel request was actually emitted (false when
## the button is missing/disabled).
func press_rest() -> bool:
	if _rest_button == null or _rest_button.disabled:
		return false
	rest_panel_requested.emit()
	return true


func _on_rest_button_pressed() -> void:
	press_rest()


# ── Internal helpers ─────────────────────────────────────────────────────

## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established by BeginCastUseCase._duck_get() / LongRestUseCase
## ._duck_get() / ShortRestMageRechargeUseCase._duck_get(): tolerates `obj`
## being a Dictionary (`.get(key, default)`), an Object exposing `key` as a
## real property (`Object.get(key)`, itself null-safe for an undeclared
## property), or null (falls back to `default`) — never raises.
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
