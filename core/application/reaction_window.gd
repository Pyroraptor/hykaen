## core/application/reaction_window.gd — ReactionWindow (FEAT-009 / US-009 /
## FR-005, ADR-014)
##
## Application layer (Clean Architecture): the pausable, resumable
## reaction-window abstraction that connects live Strike resolution
## (core/rules/resolution.gd) to the eventual reaction pop-up, modeled on
## core/application/round_session.gd's RoundSession stepwise/resumable
## pattern (ADR-007) — a first-class object a caller can drive one step at
## a time (open() then, later, resume()) instead of blocking the engine
## thread waiting for a decision inline.
##
## Depends ONLY on core/rules/resolution.gd's Resolution class (its new,
## pure, static eligibility predicates — is_dodge_eligible()/
## is_steel_eligible()/is_parry_eligible()/is_block_eligible(), see that
## file's FEAT-009 additions — so this class never re-derives/duplicates
## those rules) and on the injected EventSinkPort (ADR-003's existing
## observability surface, reused rather than a new port). Never imports an
## adapter/infrastructure/presentation type.
##
## `trigger` (the Dictionary passed to open()) shape:
##   "trigger_type"            — String, one of Resolution's active-defense
##                                family: "Dodge" | "Parry" | "Block" |
##                                "Steel" | "OpportunisticStrike".
##   "reactor"                 — Dictionary: the combatant offered the
##                                reaction (needs "conditions"/"skills"/
##                                "conscious" for Dodge/Steel eligibility).
##   "reactor_action_economy"  — the reactor's ActionEconomy instance
##                                (core/rules/action_economy.gd). OPTIONAL —
##                                when omitted, the reactor is treated as
##                                never Spent and resume() never spends a
##                                reaction (useful for pure legal_reactions
##                                inspection in tests).
##   "weapon"                  — Dictionary: the reactor's OWN weapon, used
##                                by the Parry/Block eligibility predicates
##                                (parry_bonus/block_value).
##   "defense_type"            — String: "ac" | "reflex" | "fortitude" |
##                                "will" — the passive defense this attack
##                                is being resolved against; drives Dodge's
##                                and Steel's trigger predicates.
##   "attack_context"          — Dictionary: forwarded verbatim to the
##                                ReactionChooserPort as `context`, and also
##                                consulted directly for
##                                "open_space_available" (Dodge) and
##                                "melee_reach" (OpportunisticStrike).
##   "round_number"            — int, OPTIONAL (default 0): stamped on the
##                                emitted events.
##
## `legal_reactions` returned by open() is EITHER [trigger_type's lowercase
## reaction name] (when that specific trigger's eligibility predicate
## passes) or [] (when it does not) — the reaction window offers exactly
## the ONE reaction type named by `trigger`, mirroring ReactionTrigger's
## own trigger_type field (see this feature's data_model). ReactionChooserPort.PASS
## ("none") is ALWAYS an additional implicit choice, never listed inside
## legal_reactions itself (mirrors this feature's api_contracts: "choice ∈
## legal_reactions ∪ {Pass}").
##
## Only ONE window may be open at a time (this steel thread's documented
## "no nested/parallel windows" constraint) — calling open() while a
## window is already open closes/discards the stale one first (last writer
## wins; callers are expected to resume() or let a window resolve before
## opening the next one).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example (player-facing, split across two calls):
##   var window := ReactionWindow.new(event_sink_port)
##   var opened := window.open(trigger)
##   # ... later, once the (possibly UI-driven) chooser has an answer ...
##   var result := window.resume(opened["window_id"], "dodge", "player")
##
## Usage example (headless, single call — no UI present, FEAT-009 test_criteria):
##   var window := ReactionWindow.new(event_sink_port)
##   var result := window.open_and_resolve(trigger, AutoReactionChooserClass.new("pass"))

class_name ReactionWindow
extends "res://core/application/ports/reaction_window_port.gd"

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const RoundEventsClass   = preload("res://core/rules/round_events.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")

## Lowercase reaction names — a legal_reactions entry, and the exact String
## forwarded as resolve_weapon_attack()'s active_defense argument (its
## VALID_ACTIVE_DEFENSES contract).
const REACTION_DODGE: String = "dodge"
const REACTION_PARRY: String = "parry"
const REACTION_BLOCK: String = "block"
const REACTION_STEEL: String = "steel"
const REACTION_OPPORTUNISTIC_STRIKE: String = "opportunistic_strike"

var _event_sink_port  ## EventSinkPort — injected

var _window_counter: int = 0

## _open_window_id — "" when no window is currently open (the pausable
## state this class holds BETWEEN open() and resume(), see file-level doc).
var _open_window_id: String = ""
var _open_trigger: Dictionary = {}
var _open_legal_reactions: Array = []


## _init(event_sink_port) — stores the injected EventSinkPort. Duck-typed
## (no static port type on the parameter) so any object implementing
## EventSinkPort's documented emit() contract may be substituted (test
## doubles in particular), matching this project's existing port-injection
## convention.
func _init(event_sink_port) -> void:
	_event_sink_port = event_sink_port


## open(trigger) -> Dictionary — see class-level doc / ReactionWindowPort's
## contract doc for the full behavior. Non-blocking: computes
## legal_reactions and returns immediately — it never itself asks a
## chooser for a decision (that is resume()'s caller's job, e.g.
## open_and_resolve() below, or a UI event handler holding onto
## window_id across frames).
func open(trigger: Dictionary) -> Dictionary:
	var reactor: Dictionary = trigger.get("reactor", {})
	var reactor_action_economy = trigger.get("reactor_action_economy", null)

	if reactor_action_economy != null and reactor_action_economy.is_spent():
		# ALREADY_SPENT (per this feature's api_contracts / security notes):
		# the window never opens and no event is emitted — the reaction
		# implicitly resolves to no-reaction.
		return {"window_id": "", "legal_reactions": [], "opened": false, "reason": "ALREADY_SPENT"}

	var legal_reactions: Array = _compute_legal_reactions(trigger)

	_window_counter += 1
	var window_id: String = "rwin-%d" % _window_counter
	_open_window_id       = window_id
	_open_trigger         = trigger
	_open_legal_reactions = legal_reactions

	_event_sink_port.emit(RoundEventsClass.ReactionWindowOpenedEvent.new(
		trigger.get("round_number", 0),
		window_id,
		trigger.get("trigger_type", ""),
		reactor.get("name", ""),
		legal_reactions
	))

	return {"window_id": window_id, "legal_reactions": legal_reactions, "opened": true}


## resume(window_id, choice, resolved_by) -> Dictionary — see class-level
## doc / ReactionWindowPort's contract doc. Applies `choice` and closes the
## window in a single, synchronous, non-blocking call — no loop/wait of any
## kind, so the engine thread is never blocked by this method.
func resume(window_id: String, choice: String, resolved_by: String = "unknown") -> Dictionary:
	if window_id == "" or window_id != _open_window_id:
		return {"ok": false, "error": ERR_STALE_WINDOW}

	if choice != ReactionChooserPortClass.PASS and not _open_legal_reactions.has(choice):
		return {"ok": false, "error": ERR_ILLEGAL_CHOICE}

	var trigger: Dictionary = _open_trigger
	var reactor_action_economy = trigger.get("reactor_action_economy", null)
	var applied_choice: String = choice

	if applied_choice != ReactionChooserPortClass.PASS and reactor_action_economy != null:
		var spend_result: Dictionary = reactor_action_economy.spend_reaction()
		if not spend_result.get("success", false):
			# Race guard (open()..resume() straddling another spend): fall
			# back to PASS rather than erroring — "never hang/crash".
			applied_choice = ReactionChooserPortClass.PASS

	_event_sink_port.emit(RoundEventsClass.ReactionResolvedEvent.new(
		trigger.get("round_number", 0),
		window_id,
		applied_choice,
		resolved_by
	))

	# Close the window — resume() is a one-shot operation per window_id.
	_open_window_id       = ""
	_open_trigger         = {}
	_open_legal_reactions = []

	return {"ok": true, "window_id": window_id, "choice": applied_choice}


## open_and_resolve(trigger, chooser, resolved_by) -> Dictionary — FEAT-009
## convenience orchestration: open()s the window, hands its legal_reactions
## (plus trigger["attack_context"]) to the injected ReactionChooserPort,
## then resume()s with whatever it returns — the "yield-to-chooser" flow
## the file-level doc describes, in one call. This is what lets a headless
## AutoReactionChooser (infrastructure/auto_reaction_chooser.gd) drive
## resolution to completion with NO UI present (test_criteria #3): for an
## Auto/AI chooser, choose() answers synchronously so this whole call
## returns immediately; a future blocking PlayerReactionChooser would
## instead be driven via the split open()/resume() calls directly (e.g.
## from a UI signal handler), never through this convenience method.
##
## When open() reports the reactor was already Spent (never opened), this
## method skips resume() entirely and reports the implicit PASS outcome
## directly — resume()'s STALE_WINDOW guard would otherwise reject a
## resume() call against a window_id that was never opened.
func open_and_resolve(trigger: Dictionary, chooser, resolved_by: String = "auto") -> Dictionary:
	var opened: Dictionary = open(trigger)
	if not opened.get("opened", false):
		return {
			"ok": true,
			"window_id": "",
			"choice": ReactionChooserPortClass.PASS,
			"opened": false,
			"reason": opened.get("reason", ""),
		}

	var legal_reactions: Array = opened.get("legal_reactions", [])
	var context: Dictionary = trigger.get("attack_context", {})
	var choice: String = chooser.choose(legal_reactions, context)

	var result: Dictionary = resume(opened["window_id"], choice, resolved_by)
	result["opened"] = true
	return result


## _compute_legal_reactions(trigger) -> Array — evaluates the
## trigger-type-specific eligibility predicate (test_criteria #1) via
## core/rules/resolution.gd's FEAT-009 static predicates, never
## re-implementing the rule itself. Returns [] for an unrecognized
## trigger_type (defensive — never raises).
func _compute_legal_reactions(trigger: Dictionary) -> Array:
	var trigger_type: String = trigger.get("trigger_type", "")
	var reactor: Dictionary = trigger.get("reactor", {})
	var weapon: Dictionary = trigger.get("weapon", {})
	var defense_type: String = trigger.get("defense_type", "")
	var attack_context: Dictionary = trigger.get("attack_context", {})

	match trigger_type:
		"Dodge":
			if ResolutionClass.is_dodge_eligible(defense_type, reactor, attack_context):
				return [REACTION_DODGE]
			return []
		"Parry":
			if ResolutionClass.is_parry_eligible(weapon):
				return [REACTION_PARRY]
			return []
		"Block":
			if ResolutionClass.is_block_eligible(weapon):
				return [REACTION_BLOCK]
			return []
		"Steel":
			if ResolutionClass.is_steel_eligible(defense_type, reactor):
				return [REACTION_STEEL]
			return []
		"OpportunisticStrike":
			# Melee-reach predicate (relaxable per this feature's
			# extension_points — future talents may add predicates here
			# without rewriting the trigger pipeline).
			if attack_context.get("melee_reach", false):
				return [REACTION_OPPORTUNISTIC_STRIKE]
			return []
		_:
			return []
