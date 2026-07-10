## infrastructure/ai_hex_choice_resolver.gd — AIHexChoiceResolver
## (FEAT-005 / US-005, ADR-004)
##
## Infrastructure/adapter layer (Clean Architecture): a deterministic,
## synchronous implementation of core/application/ports/
## hex_choice_resolver_port.gd's HexChoiceResolverPort contract — the enemy
## AI's Dodge-Step hex-SELECTION "brain" (contrast with
## infrastructure/ai_reaction_policy.gd's AIReactionPolicy, the enemy's
## reaction-CHOICE brain — these are two distinct, independent ports/
## adapters). This is a NEW, INDEPENDENT HexChoiceResolverPort
## implementation, distinct from MainScene.gd's `_UIHexChoiceResolver`
## (which BLOCKS on a live `hex_grid_view.hex_clicked` signal for the
## PLAYER's own Dodge-Step, highlighting the legal destinations first) — the
## two are parallel, swappable adapters behind the SAME port, selected at
## the composition root (MainScene.gd), never confused with one another,
## exactly mirroring AIReactionPolicy's/PlayerReactionChooser's own
## established "one port, multiple concrete adapters" precedent for
## core/application/ports/reaction_chooser_port.gd.
##
## Heuristic (per this feature's design notes' governing constant "Enemy
## Dodge-Step hex choice: prefer the legal adjacent hex that preserves melee
## reach on the original attacker; else the first legal hex; else no Step"):
##   1. Prefer the entry of `legal_hexes` that is ALSO one of the
##      `attacker_hex` constructor argument's 6 flat-top axial neighbors
##      (core/geometry/hex_math.gd HexMath.hex_neighbors()) — i.e. the
##      Skeleton's Dodge-Step never dodges itself out of its own melee reach
##      on the attacker who just struck it, in whatever order `legal_hexes`
##      was handed in (never a re-ordered/re-ranked choice of its own).
##   2. Else the FIRST entry of `legal_hexes`, verbatim (the same
##      "else the first legal hex" fallback this steel thread's design notes
##      require).
## No RNG, no engine I/O — this file owns ZERO adjacency/occupancy
## computation of its own (that remains
## presentation/movement_input_controller.gd's/core/rules/movement.gd's
## job, ADR-001 "no new adjacency rule"): `legal_hexes` is handed in
## verbatim by the caller (MainScene.gd's `_resolve_enemy_dodge_step()`),
## already filtered to legal/unoccupied destinations.
##
## resolve() NEVER awaits/blocks/prompts and NEVER touches
## hex_grid_view.set_selectable_hexes() (it does not even hold a reference
## to a HexGridView) — it is a plain, synchronous function, so the caller
## can NEVER open a pop-up or a hex-grid highlight for the enemy's own
## Dodge-Step (this feature's "no pop-up/highlight" test criterion).
##
## Domain purity boundary (ADR-001, mirrored here even though this is an
## Infrastructure adapter): extends RefCounted only (via
## HexChoiceResolverPort) — no Node/Control/SceneTree inheritance. Lives in
## infrastructure/ (an adapter) since it implements the HexChoiceResolverPort
## seam and is bound to it only at the composition root (MainScene), per
## ADR-002 injection — never imported by core/ itself.
##
## Usage example:
##   var resolver := AIHexChoiceResolver.new(attacker_hex)
##   var chosen = resolver.resolve(legal_hexes)
##   # chosen -> the legal hex that keeps `attacker_hex` in melee reach, if
##   #           one exists among legal_hexes; otherwise legal_hexes[0];
##   #           null only when legal_hexes is empty.

class_name AIHexChoiceResolver
extends "res://core/application/ports/hex_choice_resolver_port.gd"

const HexMathClass = preload("res://core/geometry/hex_math.gd")

## The original attacker's hex_coord (a core/geometry/hex_coord.gd HexCoord),
## captured at construction time — OPTIONAL. When null (no attacker position
## known/handed in), this resolver degrades safely straight to the "first
## legal hex" fallback below — never a crash, never a fabricated attacker
## position of its own.
var _attacker_hex


func _init(attacker_hex = null) -> void:
	_attacker_hex = attacker_hex


## resolve(legal_hexes) -> HexCoord | null — see class-level doc for the
## full priority-ordered heuristic. An empty legal_hexes always yields null
## immediately (the ONE universal invariant every HexChoiceResolverPort
## implementation must uphold, per that port's own contract) — there is
## nothing to choose from.
func resolve(legal_hexes: Array):
	if legal_hexes.is_empty():
		return null

	if _attacker_hex != null:
		var attacker_neighbors: Array = HexMathClass.hex_neighbors(_attacker_hex)
		for candidate in legal_hexes:
			for neighbor in attacker_neighbors:
				if neighbor.equals(candidate):
					return candidate

	return legal_hexes[0]
