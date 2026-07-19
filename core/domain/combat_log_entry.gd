## core/domain/combat_log_entry.gd — CombatLogEntry (FEAT-276 / US-011;
## FR-010)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine I/O. Extends RefCounted
## only, matching the existing value-object convention (core/domain/spell.gd,
## core/domain/casting_state.gd, core/log/attack_event.gd).
##
## The runtime value object presentation/verbs/resolve_spell_controller.gd's
## ResolveSpellController / core/application/use_cases/resolve_cast_use_case.gd's
## ResolveCastUseCase constructs once a cast reaches resolution and hands to
## core/application/ports/combat_log_port.gd's CombatLogPort.emit() —
## design notes' data_model CombatLogEntry entity: an append-only event
## record referenced by id everywhere else (spell_id -> SpellResource,
## actor_id/target_ids -> combatant_id), never a duplicated copy of the
## spell/combatant data itself (3NF-equivalent, mirrors this file's own
## sibling value objects' "referenced by id, never embedded" convention).
##
## Fields (design notes' data_model, this feature's CAST_RESOLVE-only
## scope — CAST_BEGIN/CAST_CONTINUE/CAST_CANCELLED are declared in
## `EventType` below as the closed vocabulary design notes specify, but are
## not yet constructed by any caller in this iteration; a later feature
## may emit them without a breaking change to this class):
##   event_type     — EventType enum member (CAST_BEGIN / CAST_CONTINUE /
##                     CAST_RESOLVE / CAST_CANCELLED).
##   actor_id       — the caster's combatant_id (Combatant.display_id()).
##   spell_id       — FK -> SpellResource / core/domain/spell.gd Spell.
##   target_ids     — Array of target combatant_id Strings; empty for a
##                     no-valid-target resolve or a target-less spell
##                     (e.g. Channel's ADD_ENERGY).
##   hit            — bool | null. null when no attack roll was made for
##                     this entry (e.g. no valid target, or a non-attack
##                     spell).
##   damage_amount  — int | null. null when no damage was applied (a miss,
##                     a non-damage spell, or no valid target).
##   energy_delta   — int | null. Reserved for a future ADD_ENERGY-mapped
##                     entry (e.g. Channel); null when not applicable —
##                     never populated by this feature's CAST_RESOLVE/DAMAGE
##                     path.
##   round_number   — the round this entry was recorded in. Defaults to 0
##                     when the caller has no round context to supply (this
##                     feature's ResolveCastUseCase does not receive one —
##                     an extension point for a later feature, per data_model's
##                     "(round_number, turn_index, sequence) composite" key,
##                     not this feature's own scope).
##
## Immutable after construction — every field is set exactly once in
## _init() and never mutated again (mirrors core/domain/spell.gd's Spell /
## core/domain/casting_state.gd's CastingState).
##
## Usage:
##   var entry := CombatLogEntry.new(
##       CombatLogEntry.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt",
##       ["skeleton"], true, 9, null
##   )
##   entry.to_dict()  # {"event_type": ..., "actor_id": "marigold_1", ...}

class_name CombatLogEntry
extends RefCounted

## The closed CAST_* event-type vocabulary (design notes' data_model). This
## feature (FEAT-276) constructs only CAST_RESOLVE entries; the remaining
## members are declared so a later feature can emit CAST_BEGIN/CAST_CONTINUE/
## CAST_CANCELLED without a breaking enum change.
enum EventType {
	CAST_BEGIN,
	CAST_CONTINUE,
	CAST_RESOLVE,
	CAST_CANCELLED,
}

var event_type: int = EventType.CAST_RESOLVE
var actor_id: String = ""
var spell_id: String = ""
var target_ids: Array = []
var hit = null            ## bool | null
var damage_amount = null  ## int | null
var energy_delta = null   ## int | null
var roll_total = null     ## int | null — attack roll total; null for non-attack spells
var round_number: int = 0


func _init(
	p_event_type: int = EventType.CAST_RESOLVE,
	p_actor_id: String = "",
	p_spell_id: String = "",
	p_target_ids: Array = [],
	p_hit = null,
	p_damage_amount = null,
	p_energy_delta = null,
	p_round_number: int = 0,
	p_roll_total = null
) -> void:
	event_type = p_event_type
	actor_id = p_actor_id
	spell_id = p_spell_id
	target_ids = p_target_ids.duplicate()
	hit = p_hit
	damage_amount = p_damage_amount
	energy_delta = p_energy_delta
	roll_total = p_roll_total
	round_number = p_round_number


## to_dict() -> Dictionary — snapshot of every field, for assertions/logging,
## mirroring core/log/attack_event.gd's AttackEvent's identical to_dict()
## convention.
func to_dict() -> Dictionary:
	return {
		"event_type": event_type,
		"actor_id": actor_id,
		"spell_id": spell_id,
		"target_ids": target_ids.duplicate(),
		"hit": hit,
		"damage_amount": damage_amount,
		"energy_delta": energy_delta,
		"roll_total": roll_total,
		"round_number": round_number,
	}
