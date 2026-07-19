## core/domain/casting_state.gd — CastingState (FEAT-005 / US-005; FR-004)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine I/O. Extends RefCounted
## only, matching the existing value-object convention (core/domain/spell.gd,
## core/domain/energy_pool.gd).
##
## The runtime value object BeginCastUseCase (core/application/use_cases/
## begin_cast_use_case.gd) builds once a first-cast reservation succeeds —
## design notes' data_model CastingState entity: {spell_id,
## remaining_actions, committed_energy, caster_id}. Embedded 1:0..1 on
## core/domain/combatant.gd's Combatant (a combatant has at most one
## in-progress cast) — NOT a separate collection, avoiding an orphan-
## reference anomaly.
##
## IMPORTANT compatibility note: Combatant.casting_state itself remains a
## plain Dictionary field (established by FEAT-002/Iteration M P0-0, ahead
## of this feature — see combatant.gd's own doc), not a CastingState
## instance — every pre-existing caller/test (e.g.
## tests/unit/core/domain/test_combatant_combat_state.gd's
## test_casting_hooks_default_and_cancel(), which assigns a raw Dictionary
## directly to `casting_state`) already depends on that Dictionary shape.
## This class is therefore a CONSTRUCTION HELPER: Combatant.begin_cast()
## builds one, then stores its to_dict() projection on the Dictionary field
## — the same "domain value object with dict interop" pattern
## core/domain/combatant.gd itself already establishes for its own
## to_dict()/from_dict() bridge.
##
## Immutable after construction — every field is set exactly once in
## _init() and never mutated again (mirrors core/domain/spell.gd's Spell).
##
## Usage:
##   var state := CastingState.new("fire_bolt", 1, 0, "marigold_1")
##   state.spell_id             # "fire_bolt"
##   state.remaining_actions    # 1
##   state.to_dict()            # {"spell_id": "fire_bolt", ...}
##   CastingState.from_dict(state.to_dict()).spell_id  # "fire_bolt"

class_name CastingState
extends RefCounted

## The spell being cast (FK -> SpellResource / core/domain/spell.gd Spell,
## by spell_id).
var spell_id: String = ""

## Actions still required to finish this cast. Set to `actions_cost - 1` at
## begin-cast time (the first action is spent immediately — design notes'
## api_contracts #1: "spends the turn action, remaining_actions -= 1").
var remaining_actions: int = 0

## Channeling-pool energy committed up front, non-refundable (ADR-003).
var committed_energy: int = 0

## The caster's own combatant_id (display_id()) — carried for CombatLogPort/
## debugging convenience, mirrored redundantly per design notes' data_model
## note ("redundant-but-denormalized-for-log-convenience").
var caster_id: String = ""


func _init(
	p_spell_id: String = "",
	p_remaining_actions: int = 0,
	p_committed_energy: int = 0,
	p_caster_id: String = ""
) -> void:
	spell_id = p_spell_id
	remaining_actions = p_remaining_actions
	committed_energy = p_committed_energy
	caster_id = p_caster_id


## is_complete() -> bool — true once no further actions are required to
## finish this cast (remaining_actions has reached 0 or below). Consulted by
## a future ContinueCastUseCase/ResolveCastUseCase (out of this feature's
## scope) to decide whether resolution should trigger.
func is_complete() -> bool:
	return remaining_actions <= 0


## to_dict() -> Dictionary — the plain-Dictionary projection stored on
## Combatant.casting_state (see file-level compatibility note above).
func to_dict() -> Dictionary:
	return {
		"spell_id": spell_id,
		"remaining_actions": remaining_actions,
		"committed_energy": committed_energy,
		"caster_id": caster_id,
	}


## from_dict(spec) -> CastingState — the inverse bridge, tolerant of missing
## keys (mirrors core/domain/combatant.gd's own from_dict() tolerance
## convention). NOTE: constructed via `load(<this file's own path>).new(...)`
## rather than a bare `CastingState.new(...)` self-reference (and left
## untyped, not `-> CastingState`) — a bare global class_name (either as a
## static type annotation OR as a callee) needs Godot's global script-class
## cache to already know this brand-new script, which is not guaranteed
## headless/CI (mirrors core/domain/combatant.gd's own documented
## HexCoordClass-over-bare-HexCoord convention; `load()` with an explicit
## path sidesteps the global class-name lookup entirely).
static func from_dict(spec: Dictionary):
	return load("res://core/domain/casting_state.gd").new(
		String(spec.get("spell_id", "")),
		int(spec.get("remaining_actions", 0)),
		int(spec.get("committed_energy", 0)),
		String(spec.get("caster_id", ""))
	)
