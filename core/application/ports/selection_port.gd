## core/application/ports/selection_port.gd — SelectionPort (FEAT-005 /
## US-005; FR-004)
##
## Application layer (Clean Architecture): documents the "list-pick"
## contract design notes' architecture section names ("SelectionPort
## (list-pick) — pick_from(options) -> selection") — mirrors this project's
## established Protocol-style port pattern (core/application/ports/
## reaction_window_port.gd, core/application/ports/action_economy_port.gd):
## a base class documenting the abstract contract; a concrete adapter either
## `extends` it or simply duck-types it.
##
## SCOPE (FEAT-005): this feature establishes the seam only — mirrors this
## codebase's established convention of introducing a Dependency-Inversion
## port ahead of any concrete call site (e.g. core/application/
## round_session.gd's `_reaction_resolver_fn` was originally documented the
## same way: "no call site ... invokes it yet ... establishing this seam is
## this feature's entire scope"). presentation/verbs/spell_action_controller.gd's
## SpellActionController already picks its cast spell_id through the SAME
## Layer-2 selection flow every other verb (Strike/Step/Stride) uses —
## execute(selection)'s `selection` argument IS the already-resolved pick —
## so BeginCastUseCase (core/application/use_cases/begin_cast_use_case.gd)
## has no live call site for this port yet. A future Layer-2 UI surface that
## presents a genuine in-engine spell list (rather than requiring the
## `selection` argument to already carry a spell_id) is later, out-of-scope
## work — this port's contract is ready to receive it without a breaking
## change.
##
## Contract:
##   pick_from(options: Array) -> Variant
##     Presents `options` (a caller-defined list of pickable entries, e.g.
##     castable Spell/spell_id options) and returns whichever single entry
##     was chosen. Implementations decide HOW (a blocking UI modal, a
##     scripted test double, an AI heuristic) — this port carries only the
##     signature.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name SelectionPort
extends RefCounted


## pick_from(options) -> Variant — abstract; concrete implementations MUST
## override.
func pick_from(_options: Array):
	push_error("SelectionPort.pick_from() is abstract — override in a concrete implementation")
	return null
