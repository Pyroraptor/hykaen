## core/application/use_cases/provoke_reaction_on_cast_use_case.gd —
## ProvokeReactionOnCastUseCase (FEAT-279 / US-014; FR-016, ADR-005)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (implicitly, through the `actor`/`candidate_reactors` shapes every other
## reaction seam already uses) and its own sibling application-layer use
## case, core/application/use_cases/resolve_stride_use_case.gd's
## ResolveStrideUseCase — never an adapter/infrastructure/presentation type,
## and never the engine scene tree.
##
## Design notes' architecture section: "ProvokeReactionOnCastUseCase(actor)
## — wraps Begin/ContinueCastUseCase to fire ReactionWindowPort for the
## Concentrate trait, exactly reusing the Stride trigger path." ADR-005
## ("no new reaction infrastructure") is satisfied literally: this use case
## introduces NO new eligibility rule, NO new port, and NO new
## OpportunisticStrike-resolution mechanism of its own — it simply calls
## ResolveStrideUseCase.execute() (the SAME "trigger used by Stride" the
## feature description names) with `actor` standing in as the "mover" and
## `actor`'s OWN current hex_coord standing in as BOTH the mover and the
## mover_start_hex.
##
## Casting a spell (a Concentrate-trait action, per this feature's own
## design notes) never relocates the caster the way a Stride does — so
## "the mover's start hex" is simply wherever the caster already stands.
## Reusing ResolveStrideUseCase unmodified with a STATIONARY mover means
## core/domain/opportunistic_strike_eligibility.gd's existing adjacent/
## hostile/not-Spent/melee-reach predicate is evaluated against the SAME
## live position a Stride's own opening position would use, and every
## downstream collaborator (reactor_spent_fn, reactor_resolver_fn,
## strike_use_case, reactor_action_economy_fn) is threaded through
## byte-for-byte identically to presentation/stride_action_controller.gd's
## own call shape — the composition root (SpellActionController) wires the
## SAME shared ReactionController seams Stride already uses, never a
## bespoke CAST_SPELL-only reaction path.
##
## execute(actor, candidate_reactors, reactor_spent_fn, reactor_resolver_fn,
##         strike_use_case, reactor_action_economy_fn, round_number,
##         cycle_index) -> Dictionary — returns
## ResolveStrideUseCase.execute()'s own Dictionary shape verbatim
## ({"reactions": Array, "mover_downed": bool, "stride_should_commit": bool}
## — the field names are inherited unchanged from the reused use case; a
## caller reading "mover_downed"/"stride_should_commit" for a cast simply
## interprets them as "was the caster downed by the provoked reaction" /
## "is it safe for the cast to proceed" — CancelCastUseCase, the use case
## that would actually ACT on a lethal outcome here, is an explicitly
## deferred extension point and OUT of this feature's scope).
##
## A null `actor`, or an `actor` carrying no hex_coord at all (e.g. a
## fixture/test double that never populates positional data), degrades
## safely to an empty, no-op outcome — mirroring this project's established
## "unwired/incomplete collaborator degrades safely" convention (see
## resolve_stride_use_case.gd's own file-level doc) — rather than crashing.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ProvokeReactionOnCastUseCase
extends RefCounted

const ResolveStrideUseCaseClass = preload("res://core/application/use_cases/resolve_stride_use_case.gd")


## execute(...) -> Dictionary — see file-level doc for the full contract.
## `candidate_reactors`/`reactor_spent_fn`/`reactor_resolver_fn`/
## `strike_use_case`/`reactor_action_economy_fn`/`round_number`/
## `cycle_index` are forwarded verbatim to ResolveStrideUseCase.execute() —
## this method adds NO new parameter shape of its own beyond resolving
## `actor`'s own hex_coord as the stationary mover/mover_start_hex pair.
func execute(
	actor,
	candidate_reactors: Array,
	reactor_spent_fn: Callable = Callable(),
	reactor_resolver_fn: Callable = Callable(),
	strike_use_case = null,
	reactor_action_economy_fn: Callable = Callable(),
	round_number: int = 0,
	cycle_index: int = 0
) -> Dictionary:
	var caster_hex = _hex_coord_of(actor)
	if actor == null or caster_hex == null:
		return {"reactions": [], "mover_downed": false, "stride_should_commit": true}

	var use_case := ResolveStrideUseCaseClass.new()
	return await use_case.execute(
		actor, caster_hex, candidate_reactors,
		reactor_spent_fn, reactor_resolver_fn,
		strike_use_case, reactor_action_economy_fn,
		round_number, cycle_index
	)


## _hex_coord_of(actor) -> HexCoord or null — mirrors core/domain/
## opportunistic_strike_eligibility.gd's/core/combat/ai.gd's own established
## "Combatant entity vs plain Dictionary" dual-shape read convention, so this
## use case works identically whether handed a real, live
## core/domain/combatant.gd Combatant (every production call site) or a
## plain Dictionary fixture (this feature's own unit tests, mirroring
## tests/unit/core/application/use_cases/test_resolve_stride_use_case.gd's
## established Dictionary-mover fixture style).
func _hex_coord_of(actor):
	if actor == null:
		return null
	return actor.get("hex_coord", null) if actor is Dictionary else actor.hex_coord
