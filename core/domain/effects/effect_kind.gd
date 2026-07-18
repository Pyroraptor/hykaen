## core/domain/effects/effect_kind.gd — EffectKind (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O. Extends RefCounted only, matching the existing value-object
## convention (core/geometry/hex_coord.gd, core/rules/round_events.gd).
##
## A single global enum acting as the Effect family's tagged-union
## discriminator (design notes' data_model: "kind: EffectKind enum
## {DAMAGE, CONDITION, MOVE, HEAL, ADD_ENERGY} — this IS the discriminator,
## avoiding a single wide nullable-field table: each concrete subtype only
## carries the fields it needs, eliminating nulls"). Every concrete Effect
## subtype (core/domain/effects/damage_effect.gd et al.) sets its own `kind`
## field from this enum via EffectBase's _init(), never re-declaring the
## discriminant itself.
##
## Lives under core/domain/effects/ (the dedicated Effect value-object
## family directory this feature establishes), not bare core/domain/ —
## keeping the whole discriminated-subtype family colocated in one
## sub-package as the domain grows additional value-object families
## alongside it.
##
## Declared as a bare (unnamed) enum so each member is exposed directly as
## an EffectKind.<NAME> integer constant — no extra `.Kind.` nesting level
## for every call site (a future EffectsApplier's kind-dispatch switch) to
## spell out.
##
## Usage:
##   effect.kind == EffectKind.DAMAGE

class_name EffectKind
extends RefCounted

enum {
	DAMAGE,
	CONDITION,
	MOVE,
	HEAL,
	ADD_ENERGY,
}
