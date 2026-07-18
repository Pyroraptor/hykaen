## core/rules/round_events.gd — Round/event value objects (FEAT-004 / ADR-004)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/SceneTree
## inheritance, no engine I/O. Every class declared in this file extends
## RefCounted only (ADR-004) and carries ZERO business logic; each is a
## simple, inspectable value object used to make the encounter's
## observability surface (AC-4 round interleaving, AC-5 budget audit
## trail) typed instead of free-form Dictionaries.
##
## Declares five value objects, all nested under the RoundEvents
## namespace class so a single preload exposes the whole group:
##
##   RoundEvents.AttackBroadcast
##     round, attacker_name, target_name, roll, defense_type,
##     defense_value, hit, crit, damage_final, actor_updated_action_budget
##     — emitted once per resolved Strike (mirrors the 'attack' entries
##       already produced by core/combat/encounter.gd's _round_events).
##       actor_updated_action_budget (FEAT-009 / US-009 / FR-014, ADR-003) is
##       an additive, backward-compatible field: a Dictionary
##       {remaining: int, spent: bool} snapshot of the ACTING combatant's
##       ActionBudget (core/rules/action_economy.gd) taken immediately after
##       this Strike's spend_action() call, or null when the caller did not
##       supply one (every pre-FEAT-009 construction site). Presentation
##       (presentation/status_panel_view.gd) projects this value read-only —
##       it never recomputes the budget itself.
##
##   RoundEvents.CombatantDefeatedEvent
##     round, name, defeated_by
##     — emitted when a combatant's HP transitions to <= 0.
##
##   RoundEvents.EncounterResultEvent
##     round, outcome
##     — emitted exactly once, when the encounter's outcome is decided.
##
##   RoundEvents.RoundHistoryEntry
##     round_number, cycle_index, combatant_id, action_type, budget_remaining
##     — one entry per resolved action/reaction (US-005); cycle_index
##       records which AC-4 interleave cycle the entry occurred in.
##
##   RoundEvents.TurnAdvancedEvent (FEAT-110 / US-010, ADR-007)
##     round, active_combatant_name, active_combatant_id
##     — emitted by core/application/round_session.gd's RoundSession every
##       time the turn cursor moves to a new living, un-Spent combatant
##       (end_current_turn() / advance_ai_turn()), so InitiativeView's
##       active-combatant highlight can advance through the SAME
##       EventSinkPort pipeline every other round event already uses
##       (ADR-003). active_combatant_id may be "" when the underlying
##       combatant Dictionary carries no stable combatant_id at this layer
##       (InitiativeView falls back to resolving by active_combatant_name).
##
##   RoundEvents.ReactionWindowOpenedEvent (FEAT-009 / US-009 / FR-005, ADR-014)
##     round, window_id, trigger_type, reactor_name, legal_reactions
##     — emitted by core/application/reaction_window.gd's ReactionWindow.open()
##       every time a pausable reaction window opens for a reactor,
##       reusing this SAME EventSinkPort/RoundEvents surface rather than a
##       new port (ADR-reuse).
##
##   RoundEvents.ReactionResolvedBroadcast (FEAT-009 / US-009 / FR-005, ADR-014)
##     round, window_id, choice, resolved_by
##     — emitted by ReactionWindow.resume() once a reaction window's choice
##       has been applied and the window closed. resolved_by is one of
##       "player" | "ai_policy" | "auto" | "unknown" (the caller-supplied
##       hint — see reaction_window.gd's resume() doc).
##
## All five classes expose their fields directly (for property-style
## inspection/equality in tests) AND a to_dict() method (for Dictionary-
## style assertions and easy serialization/logging).
##
## Usage example:
##   const RoundEventsClass = preload("res://core/rules/round_events.gd")
##   var ev := RoundEventsClass.AttackBroadcast.new(1, "Titus", "Goblin", 17,
##       "ac", 14, true, false, 6)
##   ev.to_dict() # → {round: 1, attacker_name: "Titus", ...}

class_name RoundEvents


## AttackBroadcast — value object describing one resolved Strike.
class AttackBroadcast:
	extends RefCounted

	var round: int
	var attacker_name: String
	var target_name: String
	var roll: int
	var defense_type: String
	var defense_value: int
	var hit: bool
	var crit: bool
	var damage_final: int
	## actor_updated_action_budget — FEAT-009/US-009: {remaining, spent}
	## snapshot of the acting combatant's ActionBudget post-resolution, or
	## null when not supplied (see file-level doc above).
	var actor_updated_action_budget = null

	func _init(
		p_round: int = 0,
		p_attacker_name: String = "",
		p_target_name: String = "",
		p_roll: int = 0,
		p_defense_type: String = "",
		p_defense_value: int = 0,
		p_hit: bool = false,
		p_crit: bool = false,
		p_damage_final: int = 0,
		p_actor_updated_action_budget = null
	) -> void:
		round         = p_round
		attacker_name = p_attacker_name
		target_name   = p_target_name
		roll          = p_roll
		defense_type  = p_defense_type
		defense_value = p_defense_value
		hit           = p_hit
		crit          = p_crit
		damage_final  = p_damage_final
		actor_updated_action_budget = p_actor_updated_action_budget

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":         round,
			"attacker_name": attacker_name,
			"target_name":   target_name,
			"roll":          roll,
			"defense_type":  defense_type,
			"defense_value": defense_value,
			"hit":           hit,
			"crit":          crit,
			"actor_updated_action_budget": actor_updated_action_budget,
			"damage_final":  damage_final,
		}


## CombatantDefeatedEvent — value object emitted when a combatant's HP
## transitions to <= 0.
class CombatantDefeatedEvent:
	extends RefCounted

	var round: int
	var name: String
	var defeated_by: String

	func _init(p_round: int = 0, p_name: String = "", p_defeated_by: String = "") -> void:
		round       = p_round
		name        = p_name
		defeated_by = p_defeated_by

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":       round,
			"name":        name,
			"defeated_by": defeated_by,
		}


## EncounterResultEvent — terminal value object emitted exactly once per
## encounter, when win/loss/draw is decided.
class EncounterResultEvent:
	extends RefCounted

	var round: int
	var outcome: String

	func _init(p_round: int = 0, p_outcome: String = "") -> void:
		round   = p_round
		outcome = p_outcome

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":   round,
			"outcome": outcome,
		}


## RoundHistoryEntry — one entry per resolved action/reaction (US-005),
## carrying the post-spend budget_remaining and the AC-4 cycle_index the
## action occurred in (supports interleaving-order verification).
class RoundHistoryEntry:
	extends RefCounted

	var round_number: int
	var cycle_index: int
	var combatant_id: String
	var action_type: String
	var budget_remaining: int

	func _init(
		p_round_number: int = 0,
		p_cycle_index: int = 0,
		p_combatant_id: String = "",
		p_action_type: String = "",
		p_budget_remaining: int = 0
	) -> void:
		round_number     = p_round_number
		cycle_index      = p_cycle_index
		combatant_id     = p_combatant_id
		action_type      = p_action_type
		budget_remaining = p_budget_remaining

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round_number":     round_number,
			"cycle_index":      cycle_index,
			"combatant_id":     combatant_id,
			"action_type":      action_type,
			"budget_remaining": budget_remaining,
		}


## TurnAdvancedEvent — value object emitted when the active-turn cursor moves
## to a new living, un-Spent combatant (FEAT-110 / US-010, ADR-007). See
## file-level doc above for the active_combatant_id fallback contract.
class TurnAdvancedEvent:
	extends RefCounted

	var round: int
	var active_combatant_name: String
	var active_combatant_id: String

	func _init(p_round: int = 0, p_active_combatant_name: String = "", p_active_combatant_id: String = "") -> void:
		round                 = p_round
		active_combatant_name = p_active_combatant_name
		active_combatant_id   = p_active_combatant_id

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":                  round,
			"active_combatant_name":  active_combatant_name,
			"active_combatant_id":    active_combatant_id,
		}


## ReactionWindowOpenedEvent — FEAT-009 (US-009 / FR-005, ADR-014): value
## object emitted by core/application/reaction_window.gd's ReactionWindow.
## open() every time a pausable reaction window opens for a reactor.
class ReactionWindowOpenedEvent:
	extends RefCounted

	var round: int
	var window_id: String
	var trigger_type: String
	var reactor_name: String
	var legal_reactions: Array

	func _init(
		p_round: int = 0,
		p_window_id: String = "",
		p_trigger_type: String = "",
		p_reactor_name: String = "",
		p_legal_reactions: Array = []
	) -> void:
		round           = p_round
		window_id       = p_window_id
		trigger_type    = p_trigger_type
		reactor_name    = p_reactor_name
		legal_reactions = p_legal_reactions

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":           round,
			"window_id":       window_id,
			"trigger_type":    trigger_type,
			"reactor_name":    reactor_name,
			"legal_reactions": legal_reactions,
		}


## ReactionResolvedBroadcast — FEAT-009 (US-009 / FR-005, ADR-014): value object
## emitted by core/application/reaction_window.gd's ReactionWindow.resume()
## once a reaction window's choice has been applied and the window closed.
class ReactionResolvedBroadcast:
	extends RefCounted

	var round: int
	var window_id: String
	var choice: String
	var resolved_by: String

	func _init(
		p_round: int = 0,
		p_window_id: String = "",
		p_choice: String = "",
		p_resolved_by: String = "unknown"
	) -> void:
		round       = p_round
		window_id   = p_window_id
		choice      = p_choice
		resolved_by = p_resolved_by

	## to_dict() → Dictionary — snapshot of all fields, for assertions/logging.
	func to_dict() -> Dictionary:
		return {
			"round":       round,
			"window_id":   window_id,
			"choice":      choice,
			"resolved_by": resolved_by,
		}
