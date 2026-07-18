## core/domain/effects/move_effect.gd — MoveEffect (FEAT-001 / US-001)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript, zero engine
## I/O. Concrete EffectBase value object (core/domain/effects/effect_base.gd)
## carrying a destination HexCoord targeted at one combatant. The domain
## EffectsApplier (core/domain/effects_applier.gd, FEAT-002/US-002)
## dispatches this to Combatant.move_to() (core/domain/combatant.gd) —
## this feature defines the pure data shape only.
##
## Extends the base script BY PATH
## (`extends "res://core/domain/effects/effect_base.gd"`), matching
## core/domain/effects/damage_effect.gd's convention (see its file doc for
## the preload-typing rationale). Depends only on core/geometry/hex_coord.gd
## and core/geometry/hex_math.gd — both existing, pure domain modules
## (design notes: "core/geometry: existing pure module reused (not
## modified)") — so this stays a domain-to-domain dependency, never
## reaching outward.
##
## Invariants (data_model / error_handling policy #1: "invalid hex ->
## rejected ... before reaching the use case"): target_id must be
## non-empty (enforced by EffectBase, every subtype inherits it), `hex`
## must be a non-null HexCoord, and `hex` must be within the board's
## bounds. This project has no other domain-level board-bounds constant
## today (the only existing radius, presentation/hex_grid_view.gd's
## GRID_RADIUS = 5, is a rendering constant the domain layer must never
## import — ADR-001), so BOARD_RADIUS below pins the SAME value
## independently at the domain layer, matching the currently rendered
## board. A hex is in-bounds when its cube-coordinate distance from the
## origin (0,0) is <= BOARD_RADIUS (identical to hex_grid_view.gd's own
## `absi(s) <= GRID_RADIUS` rendering-bounds check, expressed via the
## shared HexMath.hex_distance() utility instead of re-deriving it).
##
## Usage:
##   var e := MoveEffect.new("player_0", HexCoord.new(2, -1))
##   e.kind == EffectKind.MOVE   # true
##   e.hex.q                    # 2
##   e.is_valid()                # true
##   var bad := MoveEffect.new("player_0", HexCoord.new(99, 99))
##   bad.is_valid()               # false — out of bounds

class_name MoveEffect
extends "res://core/domain/effects/effect_base.gd"

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")
const HexCoordClass   = preload("res://core/geometry/hex_coord.gd")
const HexMathClass    = preload("res://core/geometry/hex_math.gd")

## The board's radius (in hex_distance from the origin) beyond which a hex
## is considered out of bounds. See file-level doc for why this domain
## constant independently pins the same value as
## presentation/hex_grid_view.gd's GRID_RADIUS rather than importing it.
const BOARD_RADIUS: int = 5

## The destination HexCoord (core/geometry/hex_coord.gd). Must be non-null
## and within BOARD_RADIUS of the origin (see file doc).
var hex: HexCoordClass = null


func _init(p_target_id: String = "", p_hex: HexCoordClass = null) -> void:
	super(EffectKindClass.MOVE, p_target_id)
	hex = p_hex
	if hex == null:
		_reject("hex must not be null")
	elif HexMathClass.hex_distance(HexCoordClass.new(0, 0), hex) > BOARD_RADIUS:
		_reject("hex (q=%d, r=%d) is out of bounds (BOARD_RADIUS=%d)" % [hex.q, hex.r, BOARD_RADIUS])
