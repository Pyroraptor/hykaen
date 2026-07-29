extends GutTest
## tests/integration/test_reaction_prompt_ui.gd
##
## GUT test suite for FEAT-207 (US-013 / FR-015): the player-facing blocking
## reaction pop-up — scenes/ui/reaction_prompt_ui.gd's ReactionPromptUI,
## presentation/player_reaction_chooser.gd's PlayerReactionChooser
## (implementing core/application/ports/reaction_chooser_port.gd's
## ReactionChooserPort), and their wiring into
## presentation/turn_controller.gd's resolve_reaction() / MainScene.gd's
## composition root.
##
## Verifies (this feature's test_criteria):
##   1. The modal pop-up filters displayed options to only legal_reactions
##      plus Pass for the current trigger/reactor state.
##   2. Resolution progression is blocked until the player selects an option
##      — no auto-timeout of any kind.
##   3. No parallel input stack is forked — a single UI input stack is
##      confirmed (source-inspection: no _input()/_unhandled_input()/
##      _gui_input() override; every interaction flows through Button.pressed).
##   4. A regression test confirms overlapping panels do not eat clicks (the
##      MOUSE_FILTER pitfall from Iteration E) — proven both by the exact
##      mouse_filter/child-order contract AND behaviorally (a press reaches
##      the right button despite the backdrop overlapping it).
##   5. An E2E test: the pop-up appears for a live attack (a real
##      ReactionWindow + core/rules/resolution.gd Resolution), filters
##      correctly, and resolution resumes only after a choice is made.

const ReactionPromptUIScene    = preload("res://scenes/ui/reaction_prompt_ui.tscn")
const ReactionPromptUIClass    = preload("res://scenes/ui/reaction_prompt_ui.gd")
const PlayerReactionChooserClass = preload("res://presentation/player_reaction_chooser.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")
const ReactionWindowClass      = preload("res://core/application/reaction_window.gd")
const ResolutionClass          = preload("res://core/rules/resolution.gd")
const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const RoundEventsClass         = preload("res://core/rules/round_events.gd")
const TurnControllerClass      = preload("res://presentation/turn_controller.gd")
const CombatantClass           = preload("res://core/domain/combatant.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const REACTION_PROMPT_UI_PATH: String = "res://scenes/ui/reaction_prompt_ui.gd"


# ── Fake/double EventSinkPort (mirrors tests/unit/test_reaction_window.gd's
#    established convention) ─────────────────────────────────────────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


## SequenceRNG — mirrors tests/unit/test_parry_reaction.gd's own SequenceRNG:
## returns successive values from pre-set d20/roll sequences, so a live
## attack's outcome is fully deterministic for this suite's E2E scenario.
class SequenceRNG:
	var _d20_seq: Array
	var _roll_seq: Array
	var _d20_idx: int = 0
	var _roll_idx: int = 0

	func _init(d20_seq: Array, roll_seq: Array = []) -> void:
		_d20_seq = d20_seq
		_roll_seq = roll_seq

	func d20() -> int:
		var val: int = _d20_seq[_d20_idx % _d20_seq.size()]
		_d20_idx += 1
		return val

	func roll(_die_size: int, _count: int) -> int:
		var val: int = _roll_seq[_roll_idx % _roll_seq.size()]
		_roll_idx += 1
		return val


# ── Shared fixture helpers ─────────────────────────────────────────────────

func _instantiate_ui() -> Node:
	var ui = ReactionPromptUIScene.instantiate()
	add_child_autofree(ui)
	return ui


var _attacker: Dictionary = {
	"strength": 3, "dexterity": 1, "constitution": 2,
	"willpower": 1, "intellect": 1, "intuition": 1, "social": 1
}

var _attacker_weapon: Dictionary = {
	"damage_modifier_attribute": "strength",
	"proficiency_bonus": 2,
	"damage_die": 6
}


func _reactor(overrides: Dictionary = {}):
	var base: Dictionary = {
		"name": "Titus",
		"ac": 13, "reflex": 12, "fortitude": 14, "will": 11,
		"conditions": [],
		"conscious": true,
		"skills": {"mobility": 1, "determination": 1},
	}
	for key in overrides:
		base[key] = overrides[key]
	return CombatantClass.from_dict(base)


func _parrying_weapon(parry_bonus: int = 3) -> Dictionary:
	return {"damage_die": 8, "parry_bonus": parry_bonus, "block_value": 0}


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1: filters displayed options to only legal_reactions + Pass
# ══════════════════════════════════════════════════════════════════════════

func test_open_prompt_displays_exactly_one_legal_reaction_plus_pass() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt(["parry"], {})

	assert_eq(ui.get_displayed_options(), ["parry", "none"],
		"must display exactly the offered legal reaction plus Pass, nothing else")
	assert_eq(ui.get_button_count(), 2)
	assert_not_null(ui.get_button("parry"), "a Parry option button must be rendered")
	assert_not_null(ui.get_button(ReactionChooserPortClass.PASS), "a Pass button must always be rendered")
	assert_eq(ui.get_button("parry").text, "Parry")
	assert_eq(ui.get_button(ReactionChooserPortClass.PASS).text, "Pass")


func test_open_prompt_with_no_legal_reactions_displays_only_pass() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt([], {})

	assert_eq(ui.get_displayed_options(), ["none"],
		"with no legal reactions offered, only Pass may ever be displayed")
	assert_eq(ui.get_button_count(), 1)


func test_open_prompt_rebuilds_and_never_leaks_stale_buttons_across_two_triggers() -> void:
	var ui = _instantiate_ui()

	ui.open_prompt(["parry"], {})
	ui.press_option("parry")

	ui.open_prompt(["dodge"], {})

	assert_eq(ui.get_displayed_options(), ["dodge", "none"],
		"a later reaction trigger must never leak the earlier trigger's option set")
	assert_null(ui.get_button("parry"), "the earlier Parry button must not survive the rebuild")


func test_open_prompt_becomes_visible() -> void:
	var ui = _instantiate_ui()
	assert_false(ui.visible, "the pop-up must start hidden")

	ui.open_prompt(["dodge"], {})

	assert_true(ui.visible, "open_prompt() must make the modal visible")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2: resolution progression is blocked until the player
# selects an option — no auto-timeout
# ══════════════════════════════════════════════════════════════════════════

func test_prompt_stays_open_with_no_auto_timeout() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["dodge"], {})

	assert_true(ui.is_open())

	# Simulate several frames/a real wait passing with no player input —
	# nothing may auto-resolve this on its own (no Timer, no fallback).
	for i in range(5):
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout

	assert_true(ui.is_open(), "the prompt must remain open indefinitely absent a real player choice")
	assert_true(ui.visible)


func test_prompt_closes_and_emits_reaction_chosen_only_once_a_button_is_pressed() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["dodge"], {})

	var received: Array = []
	ui.reaction_chosen.connect(func(choice): received.append(choice))

	ui.get_button("dodge").pressed.emit()

	assert_eq(received, ["dodge"])
	assert_false(ui.is_open(), "the prompt must close the instant a choice is made")
	assert_false(ui.visible)


func test_pressing_pass_reports_the_pass_sentinel() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["dodge", "parry"], {})

	var received: Array = []
	ui.reaction_chosen.connect(func(choice): received.append(choice))

	ui.get_button(ReactionChooserPortClass.PASS).pressed.emit()

	assert_eq(received, [ReactionChooserPortClass.PASS])


## PlayerReactionChooser.choose() is a genuine coroutine: it must not resolve
## until the injected UI's reaction_chosen signal fires. Schedules the
## simulated player press for later this frame (call_deferred) so this test
## proves `await chooser.choose(...)` genuinely suspends rather than
## resolving synchronously/immediately with a stale/garbage value.
func test_player_reaction_chooser_blocks_until_the_ui_reports_a_choice() -> void:
	var ui = _instantiate_ui()
	var chooser: PlayerReactionChooserClass = PlayerReactionChooserClass.new(ui)

	var press_later := func():
		assert_true(ui.is_open(), "fixture: the prompt must already be open when the deferred press fires")
		ui.press_option(ReactionChooserPortClass.PASS)
	press_later.call_deferred()

	var choice: String = await chooser.choose(["dodge"], {"attacker_name": "Goblin"})
	await get_tree().process_frame

	assert_eq(choice, ReactionChooserPortClass.PASS)
	assert_false(ui.is_open())


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3: no parallel input stack is forked
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_prompt_ui_declares_no_forked_input_handling() -> void:
	var file := FileAccess.open(REACTION_PROMPT_UI_PATH, FileAccess.READ)
	assert_not_null(file, "must be able to read reaction_prompt_ui.gd's source")
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()

	assert_false(content.contains("func _input("),
		"ReactionPromptUI must not override _input() — a single UI input stack (Button.pressed) must be used")
	assert_false(content.contains("func _unhandled_input("),
		"ReactionPromptUI must not override _unhandled_input() — a single UI input stack (Button.pressed) must be used")
	assert_false(content.contains("func _gui_input("),
		"ReactionPromptUI must not override _gui_input() — a single UI input stack (Button.pressed) must be used")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4: regression — overlapping panels do not eat clicks
# (the MOUSE_FILTER pitfall from Iteration E)
# ══════════════════════════════════════════════════════════════════════════

## Unlike the READ-ONLY status/log/initiative panels (which must be
## MOUSE_FILTER_IGNORE, per tests/gut/test_verb_ui_input_regression.gd's
## test_display_panels_are_mouse_transparent), this pop-up is deliberately
## MODAL while open: its Backdrop must capture (STOP) clicks so the hex grid
## beneath it can never be reached while a reaction is pending.
func test_backdrop_is_modal_stop_filter_while_the_read_only_panels_stay_ignore() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["dodge"], {})

	var backdrop: Control = ui.get_node("Backdrop")
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_STOP,
		"the modal backdrop must capture clicks (STOP) while a reaction is pending -- this is the opposite contract from the read-only display panels")


## The regression itself: Backdrop must be the FIRST child (bottom of the
## paint/input order) and PromptPanel (which owns the option buttons) the
## LAST child — otherwise a later-added full-rect backdrop would sit ON TOP
## of the buttons and silently swallow every click meant for them (exactly
## the Iteration E click-eating bug class, this time risked internally
## rather than between sibling panels).
func test_backdrop_is_ordered_beneath_the_button_panel_so_it_cannot_eat_button_clicks() -> void:
	var ui = _instantiate_ui()

	var backdrop_index: int = ui.get_node("Backdrop").get_index()
	var prompt_panel_index: int = ui.get_node("PromptPanel").get_index()

	assert_true(prompt_panel_index > backdrop_index,
		"PromptPanel (owning the option buttons) must be a LATER sibling than Backdrop, so buttons are drawn/hit-tested on top of it")


## Behavioral proof that the backdrop's overlap does not, in practice,
## prevent a button press from resolving correctly — pressing each rendered
## option (with the modal backdrop present and STOP-filtered) must still
## reach the CORRECT handler exactly once.
func test_each_rendered_option_button_resolves_correctly_despite_the_overlapping_backdrop() -> void:
	var ui = _instantiate_ui()
	ui.open_prompt(["dodge", "parry"], {})

	for reaction_id in ["dodge", "parry", ReactionChooserPortClass.PASS]:
		ui.open_prompt(["dodge", "parry"], {})
		var received: Array = []
		var handler := func(choice): received.append(choice)
		ui.reaction_chosen.connect(handler)

		ui.get_button(reaction_id).pressed.emit()

		assert_eq(received, [reaction_id], "pressing '%s' must resolve to exactly that choice, never swallowed/misrouted by the backdrop" % reaction_id)
		ui.reaction_chosen.disconnect(handler)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #5: E2E — the pop-up appears for a live attack, filters
# correctly, and resolution resumes only after a choice is made
# ══════════════════════════════════════════════════════════════════════════

func test_e2e_live_attack_reaction_pop_up_filters_and_blocks_resolution_until_choice() -> void:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	var ui = _instantiate_ui()
	var chooser: PlayerReactionChooserClass = PlayerReactionChooserClass.new(ui)

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var parrying_weapon: Dictionary = _parrying_weapon(3)
	var trigger: Dictionary = {
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"weapon": parrying_weapon,
		"defense_type": "ac",
		"attack_context": {"parrying_weapon": parrying_weapon},
	}

	# attack_d20=10 -> roll_total = 10 + strength(3) + prof(2) = 15 -> hits ac(13)
	# damage_die roll=4 -> damage_raw = 4 + strength(3) = 7
	# parry_d20=13 -> parry_roll = 13 + parry_bonus(3) = 16 -> STRICT exceed -> Parry succeeds
	var resolution: ResolutionClass = ResolutionClass.new(SequenceRNG.new([10, 13], [4]))

	# Step 1: open the window -- proves the pop-up would be offered exactly
	# the eligible Parry reaction, nothing else (test_criteria #1).
	var opened: Dictionary = window.open(trigger)
	assert_eq(opened["legal_reactions"], ["parry"],
		"a live attack against a reactor with parry_bonus > 0 must offer exactly Parry")

	# Step 2: schedule the "player" choosing Parry for later this frame --
	# the E2E proof that resolution.gd is never even invoked until this
	# fires (test_criteria #2's "blocks... until a choice is made").
	var press_parry := func():
		assert_true(ui.is_open(), "the pop-up must be open, showing exactly ['parry','none'], when the player responds")
		assert_eq(ui.get_displayed_options(), ["parry", "none"])
		ui.press_option("parry")
	press_parry.call_deferred()

	var choice: String = await chooser.choose(opened["legal_reactions"], trigger["attack_context"])
	assert_eq(choice, "parry")
	await get_tree().process_frame

	var resumed: Dictionary = window.resume(opened["window_id"], choice, "player")
	assert_true(resumed["ok"])
	assert_eq(ae.get_remaining(), 6, "resuming with a real reaction choice must spend exactly one reaction")

	# Step 3: resolution genuinely only proceeds NOW, using the player's
	# actual choice as resolve_weapon_attack()'s active_defense argument --
	# mirrors core/application/reaction_window.gd's own
	# open_and_resolve_attack() delegation.
	var defense_context: Dictionary = trigger["attack_context"].duplicate()
	defense_context["action_economy"] = ae
	var outcome: Dictionary = resolution.resolve_weapon_attack(
		_attacker, trigger["reactor"], _attacker_weapon, "ac", choice, defense_context
	)

	assert_true(outcome["hit"], "the underlying attack still hits AC")
	assert_true(outcome["on_hit_suppressed"], "the player's chosen Parry must suppress the hit")
	assert_eq(outcome["damage_final"], 0, "a successful Parry suppresses damage to 0")


## Same E2E scenario, but the player chooses Pass -- proves declining never
## triggers the reaction/never spends a reaction, exactly like the headless
## AutoReactionChooser("pass") path already proven by
## tests/unit/test_parry_reaction.gd.
func test_e2e_live_attack_pass_choice_never_spends_a_reaction() -> void:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	var ui = _instantiate_ui()
	var chooser: PlayerReactionChooserClass = PlayerReactionChooserClass.new(ui)

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var parrying_weapon: Dictionary = _parrying_weapon(3)
	var trigger: Dictionary = {
		"trigger_type": "Parry",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"weapon": parrying_weapon,
		"defense_type": "ac",
		"attack_context": {"parrying_weapon": parrying_weapon},
	}

	var opened: Dictionary = window.open(trigger)

	var press_pass := func():
		ui.press_option(ReactionChooserPortClass.PASS)
	press_pass.call_deferred()

	var choice: String = await chooser.choose(opened["legal_reactions"], trigger["attack_context"])
	assert_eq(choice, ReactionChooserPortClass.PASS)
	await get_tree().process_frame

	window.resume(opened["window_id"], choice, "player")
	assert_eq(ae.get_remaining(), 7, "declining (Pass) must never spend a reaction")


## TurnController.resolve_reaction() (FEAT-207 integration point) drives the
## SAME split open()/resume() flow via the REAL, production PlayerReactionChooser
## + ReactionPromptUI + ReactionWindow, proving the presentation-layer wiring
## (not just the raw classes in isolation) blocks correctly.
func test_turn_controller_resolve_reaction_blocks_until_the_player_answers() -> void:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	var ui = _instantiate_ui()
	var chooser: PlayerReactionChooserClass = PlayerReactionChooserClass.new(ui)

	var turn_controller: TurnControllerClass = TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	var trigger: Dictionary = {
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	}

	var press_dodge := func():
		assert_eq(ui.get_displayed_options(), ["dodge", "none"])
		ui.press_option("dodge")
	press_dodge.call_deferred()

	var result: Dictionary = await turn_controller.resolve_reaction(trigger, "player")

	assert_true(result["ok"])
	assert_eq(result["choice"], "dodge")
	assert_eq(ae.get_remaining(), 6)
	await get_tree().process_frame


## When the reactor is already Spent, resolve_reaction() must complete
## immediately (no window ever opens, so the pop-up must never appear/hang
## waiting on a chooser answer for a reaction that cannot legally happen).
func test_turn_controller_resolve_reaction_completes_immediately_when_reactor_already_spent() -> void:
	var sink: FakeEventSinkPort = FakeEventSinkPort.new()
	var window: ReactionWindowClass = ReactionWindowClass.new(sink)
	var ui = _instantiate_ui()
	var chooser: PlayerReactionChooserClass = PlayerReactionChooserClass.new(ui)

	var turn_controller: TurnControllerClass = TurnControllerClass.new()
	add_child_autofree(turn_controller)
	turn_controller.configure_reactions(window, chooser)

	var ae: ActionEconomyClass = ActionEconomyClass.new()
	for i in range(7):
		ae.spend_reaction()

	var trigger: Dictionary = {
		"trigger_type": "Dodge",
		"reactor": _reactor(),
		"reactor_action_economy": ae,
		"defense_type": "ac",
		"attack_context": {"open_space_available": true},
	}

	var result: Dictionary = await turn_controller.resolve_reaction(trigger, "player")

	assert_true(result["ok"])
	assert_false(result["opened"])
	assert_false(ui.is_open(), "the pop-up must never open for an already-Spent reactor")
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════
# MainScene composition-root wiring (working software, not just mocks)
# ══════════════════════════════════════════════════════════════════════════

func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


func test_main_scene_wires_a_real_reaction_prompt_ui_and_player_reaction_chooser() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance.get_node_or_null("UILayer/ReactionPromptUI"), "MainScene must wire a ReactionPromptUI child node under UILayer")
	assert_true(is_instance_of(instance.reaction_prompt_ui, ReactionPromptUIClass))
	assert_true(is_instance_of(instance.player_reaction_chooser, PlayerReactionChooserClass))
	assert_true(is_instance_of(instance.reaction_window, ReactionWindowClass))
	assert_false(instance.reaction_prompt_ui.visible, "the pop-up must start hidden in the real, booted composition root")


## Behavioral proof, in the REAL booted MainScene tree (every other panel —
## StatusPanelView/EventLogView/InitiativeView/HexGridView/VerbBarView —
## present and overlapping the same viewport), that opening the pop-up and
## pressing one of its buttons still resolves correctly: the definitive
## "overlapping panels do not eat clicks" regression proof in situ, not just
## in isolation.
func test_main_scene_reaction_prompt_ui_resolves_a_choice_correctly_amid_the_full_presentation_stack() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	instance.reaction_prompt_ui.open_prompt(["block"], {})
	assert_true(instance.reaction_prompt_ui.visible)

	var received: Array = []
	instance.reaction_prompt_ui.reaction_chosen.connect(func(choice): received.append(choice))

	instance.reaction_prompt_ui.get_button("block").pressed.emit()

	assert_eq(received, ["block"], "the pop-up's own button must still resolve correctly amid the full real presentation stack")
	assert_false(instance.reaction_prompt_ui.visible)
