## scenes/ui/reaction_prompt_ui.gd — ReactionPromptUI (FEAT-207 / US-013 /
## FR-015)
##
## Presentation layer (Clean Architecture): the player-facing BLOCKING
## reaction pop-up — the steel thread's on-screen entry point for reactions
## (design notes' trace: "... yields to the injected ReactionChooserPort ->
## PlayerReactionChooser [presentation] shows blocking pop-up ... choice
## resumes resolution.gd"). Renders exactly one Button per entry of the
## `legal_reactions` Array handed to open_prompt(), PLUS one Pass button —
## never any other option (test_criteria: "modal pop-up filters displayed
## options to only legal_reactions plus Pass for the current
## trigger/reactor state") — reusing the SAME generic "one control per
## registry-style entry, zero per-option branching" idiom
## presentation/verb_bar_view.gd already established for the Layer 1 verb
## bar (this feature's design notes: "reusing existing verb->target UX
## registry idioms").
##
## Ownership of the "blocking" contract (test_criteria: "resolution
## progression is blocked until the player selects an option (no
## auto-timeout)"): this Control NEVER resolves a choice on its own — there
## is no Timer, no frame-count limit, no fallback of any kind. It stays
## open (visible, `_is_open == true`) until press_option()/a real Button
## press fires, at which point it emits reaction_chosen(choice) exactly
## once and immediately closes. presentation/player_reaction_chooser.gd's
## PlayerReactionChooser is the ReactionChooserPort adapter that `await`s
## this signal (see that file's doc for the full hand-off) — THIS file
## deliberately never imports/preloads
## core/application/ports/reaction_chooser_port.gd itself (PASS_CHOICE
## below is a duplicated plain String constant, not a shared import),
## keeping the presentation -> application dependency direction exactly
## one-way (PlayerReactionChooser depends on this file, never the reverse).
##
## MOUSE_FILTER discipline (regression-tested against the Iteration E
## click-eating pitfall documented by
## tests/gut/test_verb_ui_input_regression.gd's
## test_display_panels_are_mouse_transparent): unlike the READ-ONLY
## status/log/initiative panels (which must be MOUSE_FILTER_IGNORE so they
## never swallow a click meant for the hex grid beneath them), THIS Control
## is deliberately MODAL while open — its Backdrop child is
## MOUSE_FILTER_STOP so a click landing outside the prompt panel while open
## can never reach the hex grid/verb bar beneath it (this is what makes
## "resolution blocks until the player chooses" true at the input level
## too, not merely the resolution-flow level). The failure mode this
## feature's test_criteria explicitly regression-tests is the INVERSE one:
## an overlapping backdrop/panel silently swallowing clicks meant for the
## prompt's OWN option buttons. This is avoided by strict child order in
## reaction_prompt_ui.tscn — Backdrop is the FIRST child (bottom of the
## paint/input order) and PromptPanel (which owns the actual option
## buttons) is the LAST child, so a button's own click is always delivered
## to the button — which, as a Control, consumes it — before the backdrop
## underneath it would ever see it.
##
## FEAT-002 (US-002 / FR-001, Iteration J Part B): core/application/
## reaction_window.gd's new "PreHitAvoidance" trigger_type (Dodge/Steel only,
## opened BEFORE the attack roll) requires NO changes to this file — its
## legal_reactions Array (e.g. ["dodge","steel"]) is rendered by the SAME
## generic "one Button per entry, capitalize() for the label" loop in
## _rebuild_buttons() below that already renders every other trigger_type's
## offered reactions (Dodge/Parry/Block/Steel/WeaponAttack alike). This file
## never branches on trigger_type or reaction identity — see
## presentation/turn_controller.gd's resolve_reaction() for where a
## PreHitAvoidance trigger would eventually be opened/awaited.
##
## Single UI input stack (test_criteria: "no parallel input stack is
## forked"): this file declares NO _input()/_unhandled_input()/_gui_input()
## override of its own — every interaction flows through standard Control
## Button.pressed signals exactly like presentation/verb_bar_view.gd /
## presentation/end_turn_control.gd, so no second/forked input-handling
## path is introduced anywhere in the project (verified directly by a
## source-inspection regression test,
## tests/integration/test_reaction_prompt_ui.gd).

class_name ReactionPromptUI
extends Control

## PASS_CHOICE — mirrors core/application/ports/reaction_chooser_port.gd's
## ReactionChooserPort.PASS ("none") exactly, duplicated here as a plain
## String constant (never preloaded — see file-level doc) so this
## presentation-layer file carries no import-time dependency on the
## application layer's port; only presentation/player_reaction_chooser.gd
## (which DOES import the port) bridges the two.
const PASS_CHOICE: String = "none"
const PASS_LABEL: String = "Pass"

## reaction_chosen(choice) — emitted exactly once, the instant a real
## option (a legal reaction, or Pass) is chosen.
## presentation/player_reaction_chooser.gd's PlayerReactionChooser `await`s
## this signal to fulfil its ReactionChooserPort.choose() contract.
signal reaction_chosen(choice: String)

## True from open_prompt() until a choice is made — see file-level "no
## auto-timeout" doc above; nothing in this file ever flips this back to
## false on its own initiative.
var _is_open: bool = false

## The exact legal_reactions Array (never including Pass) this prompt is
## CURRENTLY displaying — exposed for test/observability inspection.
var _legal_reactions: Array = []

## reaction_id (String) -> Button, one per currently rendered option
## (including the always-present Pass button), mirroring
## presentation/verb_bar_view.gd's `_buttons` Dictionary convention.
var _buttons: Dictionary = {}

## Dynamically created Label showing attacker/reactor names and roll data.
## Inserted as the first child of _buttons_container in _rebuild_buttons().
## Null when no context is available.
var _context_label: Label = null

@onready var _backdrop: Control = $Backdrop
@onready var _buttons_container: VBoxContainer = $PromptPanel/ButtonsContainer


func _ready() -> void:
	visible = false
	if _backdrop != null:
		# Deliberately MODAL while open (see file-level MOUSE_FILTER doc) —
		# set here (not in the .tscn) to mirror this project's established
		# convention of assigning mouse_filter programmatically in _ready()
		# (presentation/status_panel_view.gd / event_log_view.gd /
		# initiative_view.gd all do the same for their own, opposite,
		# MOUSE_FILTER_IGNORE case).
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP


## open_prompt(legal_reactions, context) -> void — the ONLY way this prompt
## becomes visible. Rebuilds exactly one Button per legal_reactions entry
## PLUS one Pass button, discarding any previously-rendered set, then shows
## the modal. `context` is accepted (mirrors
## core/application/ports/reaction_chooser_port.gd's choose() contract
## exactly) but not rendered anywhere on this minimal pop-up yet — reserved
## for a future richer prompt (e.g. "Goblin attacks Titus for up to 7
## damage") without needing to change this method's signature.
func open_prompt(legal_reactions: Array, context: Dictionary = {}) -> void:
	_legal_reactions = legal_reactions.duplicate()
	_rebuild_buttons(context)
	visible = true
	_is_open = true


## is_open() -> bool — true from open_prompt() until a choice is made.
func is_open() -> bool:
	return _is_open


## get_displayed_options() -> Array — the exact option set currently
## rendered: legal_reactions, in order, followed by Pass — for direct
## test/observability inspection (mirrors
## presentation/verb_bar_view.gd's get_verb_ids()).
func get_displayed_options() -> Array:
	var options: Array = _legal_reactions.duplicate()
	options.append(PASS_CHOICE)
	return options


## get_button(reaction_id) -> Button or null — the rendered Button for a
## given reaction_id (or PASS_CHOICE for the Pass button), for direct test
## inspection/press simulation (mirrors
## presentation/verb_bar_view.gd's get_button()).
func get_button(reaction_id: String) -> Button:
	return _buttons.get(reaction_id, null)


## get_button_count() -> int — number of option buttons currently rendered
## (mirrors presentation/verb_bar_view.gd's get_button_count()).
func get_button_count() -> int:
	return _buttons.size()


## press_option(reaction_id) -> void — drives the SAME choice-resolution
## path a real Button press does (see _on_option_pressed() below).
## Production code never needs to call this directly — real presses arrive
## via each rendered Button's own `pressed` signal (wired in
## _rebuild_buttons()) — this is exposed so tests can drive a choice
## without reaching into Button internals.
func press_option(reaction_id: String) -> void:
	_on_option_pressed(reaction_id)


# ── Internal helpers ─────────────────────────────────────────────────────

## _rebuild_buttons(context) -> void — recomputes `_buttons` from `_legal_reactions`
## + the Pass option. Clears any previously-rendered buttons first, so a
## repeated open_prompt() call (e.g. a second reaction window opening later
## in the same encounter) never leaks duplicate buttons (mirrors
## presentation/verb_bar_view.gd's _rebuild_buttons()). Renders a context
## label (attacker/reactor names + roll data) above the buttons when the
## context dict contains attacker_name/reactor_name.
func _rebuild_buttons(context: Dictionary = {}) -> void:
	for button in _buttons.values():
		button.queue_free()
	_buttons.clear()

	if _context_label != null:
		_context_label.queue_free()
		_context_label = null

	if _buttons_container == null:
		return

	var context_text: String = _build_context_text(context)
	if context_text != "":
		_context_label = Label.new()
		_context_label.text = context_text
		_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_buttons_container.add_child(_context_label)

	for reaction_id in _legal_reactions:
		_add_option_button(String(reaction_id), _label_for_reaction(String(reaction_id), context))

	_add_option_button(PASS_CHOICE, PASS_LABEL)


func _build_context_text(context: Dictionary) -> String:
	var attacker_name: String = context.get("attacker_name", "")
	var reactor_name: String = context.get("reactor_name", "")
	var lines: PackedStringArray = PackedStringArray()
	if attacker_name != "" and reactor_name != "":
		lines.append("%s attacks %s" % [attacker_name, reactor_name])
	if context.has("attack_modifier"):
		var mod: int = context["attack_modifier"]
		lines.append("Attack modifier: %s%d" % ["+" if mod >= 0 else "", mod])
	if context.has("roll_total"):
		lines.append("Attack roll: %d" % context["roll_total"])
	if context.has("damage_raw"):
		lines.append("Damage: %d" % context["damage_raw"])
	return "\n".join(lines)


## _label_for_reaction(reaction_id, context) -> String — FEAT-010 (US-010 /
## FR-010): the presentation-layer exit point of the "Patience equips a
## shield" steel thread. Enriches the 'parry'/'block' button labels with the
## weapon name + stats sourced from the defense-context dict
## core/application/round_session.gd's _build_defense_context() produces
## (parry_weapon_name/parry_bonus/block_weapon_name/block_weapon_value/
## block_weapon_die/block_weapon_damage_die) — e.g. "Block (Small Shield
## 1d10+4)", "Parry (Mace +1)". Falls back to plain
## String(reaction_id).capitalize() for every other reaction id, AND for
## 'parry'/'block' themselves whenever the relevant weapon-derived context
## keys are absent/blank — this is the explicit backward-compatibility
## contract for every existing caller (including every pre-existing test in
## this suite) that omits weapon-derived context. Never mutates `context`;
## never called with the enriched label itself as `reaction_id` — the
## `_buttons` Dictionary this feeds is always keyed by the bare
## `reaction_id` (see _add_option_button() below), preserving the frozen
## `legal_reactions: Array[String]` contract end-to-end into the UI layer.
func _label_for_reaction(reaction_id: String, context: Dictionary) -> String:
	match reaction_id:
		"block":
			return _label_for_block_reaction(context)
		"parry":
			return _label_for_parry_reaction(context)
		_:
			return String(reaction_id).capitalize()


func _label_for_block_reaction(context: Dictionary) -> String:
	var weapon_name: String = String(context.get("block_weapon_name", ""))
	if weapon_name == "":
		return String("block").capitalize()
	var block_value: int = int(context.get("block_weapon_value", 0))
	var block_die: int = int(context.get("block_weapon_die", 0))
	if block_die <= 0:
		block_die = int(context.get("block_weapon_damage_die", 0))
	return "Block (%s 1d%d+%d)" % [weapon_name, block_die, block_value]


func _label_for_parry_reaction(context: Dictionary) -> String:
	var weapon_name: String = String(context.get("parry_weapon_name", ""))
	if weapon_name == "":
		return String("parry").capitalize()
	var parry_bonus: int = int(context.get("parry_bonus", 0))
	return "Parry (%s %s%d)" % [weapon_name, "+" if parry_bonus >= 0 else "", parry_bonus]


func _add_option_button(reaction_id: String, label: String) -> void:
	var button := Button.new()
	button.name = "Option_%s" % reaction_id
	button.text = label
	_buttons_container.add_child(button)
	button.pressed.connect(_on_option_pressed.bind(reaction_id))
	_buttons[reaction_id] = button


## _on_option_pressed(reaction_id) -> void — the ONE place a choice
## resolves: closes the modal (sticky — a second call after the prompt has
## already closed is a no-op, so a stray double-signal can never emit
## reaction_chosen twice for one open_prompt()) and emits reaction_chosen.
func _on_option_pressed(reaction_id: String) -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	reaction_chosen.emit(reaction_id)
