## presentation/player_reaction_chooser.gd — PlayerReactionChooser
## (FEAT-207 / US-013 / FR-015)
##
## Presentation layer (Clean Architecture): the human-facing implementation
## of core/application/ports/reaction_chooser_port.gd's ReactionChooserPort
## contract — the "PlayerReactionChooser -> ReactionChooserPort" arrow this
## feature's design notes describe. Wraps an injected reaction-prompt UI
## (scenes/ui/reaction_prompt_ui.gd's ReactionPromptUI, duck-typed here —
## this file never preloads that script, it only calls open_prompt() and
## awaits reaction_chosen, so any test double exposing that same two-member
## contract may be substituted) and drives it to a decision, suspending the
## CALLING COROUTINE (never the engine thread — Godot's `await`/Signal
## mechanism only suspends the awaiting function; rendering and every other
## node keep ticking) until the player actually presses an option.
##
## core/application/reaction_window.gd's own file-level doc already
## documents this exact division of responsibility: its convenience
## open_and_resolve()/open_and_resolve_attack() methods call
## `chooser.choose(...)` SYNCHRONOUSLY (no `await`) and are therefore only
## safe for headless/AI choosers (infrastructure/auto_reaction_chooser.gd)
## whose choose() returns immediately with no suspension. A real, blocking
## PlayerReactionChooser — this class — must instead be driven via the
## SAME ReactionWindow's split open()/resume() calls, with the caller
## itself `await`ing choose() directly (see
## presentation/turn_controller.gd's resolve_reaction(), FEAT-207's live
## integration point, and reaction_window.gd's own "Usage example
## (player-facing, split across two calls)" doc).
##
## No auto-timeout (this feature's test_criteria): choose()'s `await` below
## never resolves on its own — it only completes once the injected prompt
## UI emits reaction_chosen, exactly mirroring that UI's own "no Timer, no
## fallback" contract (see scenes/ui/reaction_prompt_ui.gd's doc).
##
## Domain purity boundary (ADR-001): this file lives in presentation/ (the
## one layer allowed to depend on a Control/Node-backed UI) — the
## ReactionChooserPort contract itself is never violated: choose() still
## returns a String naming one of legal_reactions or PASS, only
## asynchronously instead of synchronously.
##
## Usage example (mirrors core/application/reaction_window.gd's own
## "player-facing, split across two calls" doc):
##   var chooser := PlayerReactionChooser.new(reaction_prompt_ui)
##   var opened := reaction_window.open(trigger)
##   var choice: String = await chooser.choose(opened["legal_reactions"], trigger.get("attack_context", {}))
##   var result := reaction_window.resume(opened["window_id"], choice, "player")

class_name PlayerReactionChooser
extends "res://core/application/ports/reaction_chooser_port.gd"

## The injected reaction-prompt UI (scenes/ui/reaction_prompt_ui.gd's
## ReactionPromptUI). Duck-typed — see file-level doc.
var _prompt_ui


## _init(prompt_ui) — stores the injected prompt UI. Never constructed
## here (ADR-002 injection, mirrors every other adapter in this codebase).
func _init(prompt_ui) -> void:
	_prompt_ui = prompt_ui


## choose(legal_reactions, context) -> String — opens the modal reaction
## prompt (filtered to legal_reactions + PASS — see ReactionPromptUI's own
## doc) and suspends THIS COROUTINE until the player picks an option, i.e.
## until `_prompt_ui` emits its reaction_chosen(choice) signal. Callers MUST
## `await` this method (see file-level doc) — it is a genuine coroutine.
func choose(legal_reactions: Array, context: Dictionary) -> String:
	_prompt_ui.open_prompt(legal_reactions, context)
	var choice = await _prompt_ui.reaction_chosen
	return choice
