## core/rules/round_events.gd — Round/event value objects (FEAT-004 / ADR-004)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/SceneTree
## inheritance, no engine I/O. Every class declared in this file extends
## RefCounted only (ADR-004) and carries ZERO business logic; each is a
## simple, inspectable value object used to make the encounter's
## observability surface (AC-4 round interleaving, AC-5 budget audit
## trail) typed instead of free-form Dictionaries.
##
## Declares four value objects, all nested under the RoundEvents
## namespace class so a single preload exposes the whole group:
##
##   RoundEvents.AttackEvent
##     round, attacker_name, target_name, roll, defense_type,
##     defense_value, hit, crit, damage_final
##     — emitted once per resolved Strike (mirrors the 'attack' entries
##       already produced by core/combat/encounter.gd's _round_events).
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
## All four classes expose their fields directly (for property-style
## inspection/equality in tests) AND a to_dict() method (for Dictionary-
## style assertions and easy serialization/logging).
##
## Usage example:
##   const RoundEventsClass = preload("res://core/rules/round_events.gd")
##   var ev := RoundEventsClass.AttackEvent.new(1, "Titus", "Goblin", 17,
##       "ac", 14, true, false, 6)
##   ev.to_dict() # → {round: 1, attacker_name: "Titus", ...}

class_name RoundEvents


## AttackEvent — value object describing one resolved Strike.
class AttackEvent:
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

	func _init(
		p_round: int = 0,
		p_attacker_name: String = "",
		p_target_name: String = "",
		p_roll: int = 0,
		p_defense_type: String = "",
		p_defense_value: int = 0,
		p_hit: bool = false,
		p_crit: bool = false,
		p_damage_final: int = 0
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
