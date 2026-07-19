## core/domain/energy_pool.gd — EnergyPool domain value object (FEAT-003 /
## US-003; FR-012, FR-015)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no Resource/ResourceLoader concerns,
## no engine I/O. Extends RefCounted only, matching the existing
## value-object convention (core/domain/spell.gd, core/geometry/hex_coord.gd).
##
## Represents ONE caster's per-round Channeling energy pool
## (core/application/round_session.gd's RoundSession holds a
## Dictionary[caster_id -> EnergyPool], one per caster who has cast this
## round). `capacity` is resolved ONCE, at pool-creation time, from the
## caster's Combatant.spellcasting_attribute_score (core/domain/combatant.gd)
## — never re-derived or duplicated elsewhere (design notes' data_model:
## "capacity = spellcasting_attribute_score, re-derived at pool creation,
## not copied ahead of time").
##
## Clamp-on-add semantics: add(amount) always leaves `current` within
## [0, capacity] — a caller can never push `current` above `capacity` (an
## over-cap ADD_ENERGY effect application is simply truncated, not an
## error) nor below 0 (a negative `amount` is likewise clamped, never
## producing a negative balance).
##
## empty() resets `current` to 0 — the operation
## core/application/round_session.gd's end-of-round hook (finish()) invokes
## on EVERY caster's EnergyPool once a round concludes, per this feature's
## scope. EnergyPool itself is NOT the caster's `committed_energy` (that
## lives on Combatant.casting_state, a separate field entirely) — emptying
## a pool never touches already-committed energy, since EnergyPool has no
## reference to that field at all.
##
## Usage:
##   var pool := EnergyPool.new(3)   # capacity = spellcasting_attribute_score
##   pool.add(2)                     # current == 2
##   pool.add(5)                     # current == 3 (clamped at capacity)
##   pool.empty()                    # current == 0

class_name EnergyPool
extends RefCounted

## Maximum energy this pool can ever hold, resolved once at construction
## from the caster's spellcasting_attribute_score. Never mutated after
## _init().
var capacity: int = 0

## Current banked energy, always within [0, capacity].
var current: int = 0


func _init(p_capacity: int = 0, p_current: int = 0) -> void:
	capacity = maxi(0, p_capacity)
	current = clampi(p_current, 0, capacity)


## add(amount) -> int — adds `amount` (may be negative) to `current`,
## clamped to [0, capacity]. Returns the resulting `current` value.
func add(amount: int) -> int:
	current = clampi(current + amount, 0, capacity)
	return current


## empty() -> void — resets `current` to 0. Does NOT touch `capacity` (a
## fresh round starts from the SAME resolved capacity) and never touches
## any other object — in particular, never a caster's committed_energy
## (Combatant.casting_state), which is a wholly separate field this class
## has no reference to.
func empty() -> void:
	current = 0
