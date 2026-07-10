## core/application/use_cases/resolve_stride_use_case.gd — ResolveStrideUseCase
## (iteration K FEAT-006 / US-006)
##
## Application layer (Clean Architecture): the second demoable slice this
## iteration's design notes describe — "a Stride opens a resolved reaction
## window before position changes". Depends ONLY on core/domain/
## opportunistic_strike_eligibility.gd's OpportunisticStrikeEligibility (the
## pure eligibility predicate) plus caller-injected Callables (ADR-002 —
## Dependency Inversion via duck-typed Callables, mirroring core/application/
## round_session.gd's established _reaction_resolver_fn/_token_reposition_fn
## seam convention). Never imports an adapter/infrastructure/presentation
## type, and never touches the engine scene tree directly.
##
## execute() is called by BOTH Stride paths this feature wires — the enemy
## mover path (core/combat/ai.gd, via its injected
## `_stride_reaction_resolver_fn` Callable seam) and the player mover path
## (MainScene._verb_bar_stride_execute) — BEFORE either path commits the
## Stride's hex_coord mutation via core/rules/movement.gd's Movement.stride().
## This use case itself never touches hex_coord/ActionEconomy/Movement at
## all — it only decides WHICH reactors get offered an OpportunisticStrike
## window and collects their resolved choices; committing (or cancelling) the
## Stride, and any future application of the strike itself
## (resolve_opportunistic_strike_use_case.gd, a later feature — NOT yet
## introduced by this one), remain entirely the caller's responsibility.
##
## execute(mover, mover_start_hex, candidate_reactors, reactor_spent_fn,
##         reactor_resolver_fn) -> Dictionary
##
## mover               — the Dictionary of the combatant about to Stride.
## mover_start_hex      — mover's hex_coord BEFORE the Stride (captured by the
##                        caller BEFORE it ever calls Movement.stride()) — a
##                        core/geometry/hex_coord.gd HexCoord.
## candidate_reactors   — Array of every OTHER combatant Dictionary who might
##                        react (both allies and hostiles of `mover` — the
##                        hostile filter lives entirely inside
##                        OpportunisticStrikeEligibility, this use case never
##                        pre-filters by faction itself). Expected to already
##                        be supplied in initiative order by the caller — this
##                        use case resolves reactors strictly in the order
##                        given, never re-sorting them itself.
## reactor_spent_fn      — OPTIONAL, duck-typed Callable(reactor: Dictionary)
##                        -> bool: "has this reactor's reaction already been
##                        spent?" (e.g. wrapping ActionEconomy.is_spent()).
##                        Left an invalid (unbound) Callable — the default —
##                        this method then treats every candidate as never
##                        Spent (a caller that cannot supply per-reactor
##                        budget data, e.g. a unit test, still gets a usable
##                        answer for the adjacency/hostility/melee-reach
##                        filters).
## reactor_resolver_fn   — Callable(reactor: Dictionary, context: Dictionary)
##                        -> Dictionary, AWAITED once per ELIGIBLE reactor
##                        (never for an ineligible one — no window is ever
##                        opened for those, so no chooser is ever consulted).
##                        Must return at least {"choice": String}. The CALLER
##                        decides HOW to route this per reactor — a real,
##                        blocking presentation/turn_controller.gd
##                        resolve_reaction() pop-up for a player reactor, or a
##                        synchronous core/application/
##                        open_reaction_window_use_case.gd OpenReactionWindowUseCase
##                        call (backed by infrastructure/ai_reaction_policy.gd's
##                        AIReactionPolicy) for an enemy reactor — this use
##                        case never constructs a ReactionChooserPort or any
##                        concrete adapter itself (ADR-002 injection). Left an
##                        invalid (unbound) Callable — the default — every
##                        eligible reactor is simply skipped (no window opened,
##                        matching this feature's error_handling design note:
##                        an unwired seam degrades safely rather than crashing
##                        or guessing an answer).
##
## Returns {"reactions": Array[Dictionary]} — one entry per reactor a window
## was ACTUALLY opened for: {"reactor": Dictionary, "choice": String}. A
## reactor filtered out by OpportunisticStrikeEligibility.eligible() (or
## skipped because `reactor_resolver_fn` was never wired) never appears here.
## Once execute() returns, every eligible reactor's reaction has been fully
## resolved (chosen and, if applicable, spent) — the caller may now safely
## commit the mover's position change, per this feature's contract: "opens a
## resolved reaction window before position changes".
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ResolveStrideUseCase
extends RefCounted

const OpportunisticStrikeEligibilityClass = preload("res://core/domain/opportunistic_strike_eligibility.gd")


func execute(
	mover: Dictionary,
	mover_start_hex,
	candidate_reactors: Array,
	reactor_spent_fn: Callable = Callable(),
	reactor_resolver_fn: Callable = Callable()
) -> Dictionary:
	var reactions: Array = []

	for reactor in candidate_reactors:
		var reactor_spent: bool = false
		if reactor_spent_fn.is_valid():
			reactor_spent = bool(reactor_spent_fn.call(reactor))

		if not OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover_start_hex, reactor_spent):
			continue

		if not reactor_resolver_fn.is_valid():
			continue

		var context: Dictionary = {"melee_reach": true}
		var result: Dictionary = await reactor_resolver_fn.call(reactor, context)
		reactions.append({"reactor": reactor, "choice": result.get("choice", "none")})

	return {"reactions": reactions}
