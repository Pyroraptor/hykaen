## core/application/use_cases/resolve_stride_use_case.gd — ResolveStrideUseCase
## (iteration K FEAT-006 / US-006; effect resolution added by FEAT-007 / US-007,
## ADR-005 — see that feature's own dedicated doc section below)
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
## Returns {"reactions": Array[Dictionary], "mover_downed": bool,
##          "stride_should_commit": bool}:
##   "reactions"    — one entry per reactor a window was ACTUALLY opened for:
##                     {"reactor": Dictionary, "choice": String,
##                     "strike_result": Dictionary (OPTIONAL, see below)}. A
##                     reactor filtered out by
##                     OpportunisticStrikeEligibility.eligible() (or skipped
##                     because `reactor_resolver_fn` was never wired) never
##                     appears here.
##   "mover_downed" — bool, iteration K FEAT-007 (US-007, ADR-005): true iff
##                     ANY resolved Opportunistic Strike defeated `mover`
##                     (mover.hp_current transitioned to <= 0) — see this
##                     feature's own doc below for the full contract. Always
##                     false when `strike_use_case` is never wired (every
##                     pre-FEAT-007 caller/test).
##   "stride_should_commit" — bool, iteration K FEAT-008 (US-008): the
##                     EXPLICIT inverse of "mover_downed" (`not mover_downed`)
##                     — see this feature's own "Ordering / multi-reactor
##                     semantics" doc below for the full commit/cancel
##                     contract. Always true when "mover_downed" is false,
##                     including every pre-FEAT-008 caller/test.
##
## Once execute() returns, every eligible reactor's reaction has been fully
## resolved (chosen and, if applicable, spent AND its effect applied — see
## this feature's own FEAT-007 doc below) — the caller may now safely commit
## the mover's position change (UNLESS "mover_downed" is true, in which case
## the caller MUST cancel the Stride instead — see this feature's own
## error_handling design note: "MoverDownedByOpportunisticStrikeError"),
## per this feature's contract: "opens a resolved reaction window before
## position changes".
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## ── iteration K FEAT-007 (US-007 / FR-005, ADR-005) — EFFECT RESOLUTION ────
##
## FEAT-006 (above) only ever RECORDED an eligible reactor's `choice` — it
## never resolved what an "opportunistic_strike" choice actually DOES,
## leaving the exact "reaction_window.resume() records the choice + spends,
## applies nothing" gap this project's design notes call out. This feature
## closes it: whenever a reactor's resolved `choice` is
## REACTION_OPPORTUNISTIC_STRIKE, execute() now ALSO resolves a real melee
## Strike from that reactor against `mover` — through the SAME consolidated
## resolve_action_use_case/resolve_weapon_attack path (ADR-005) an ordinary
## Strike takes, so damage math/event emission/round-history bookkeeping are
## never re-implemented here a second time — landing BEFORE this method
## returns, i.e. strictly BEFORE the caller's own subsequent Movement.stride()/
## movement_input_controller.stride_to() call ever mutates `mover`'s
## hex_coord (both live call sites — core/combat/ai.gd's
## `_stride_reaction_resolver_fn` seam and MainScene.gd's
## _verb_bar_stride_execute() — already `await` this method to completion
## before their own Stride-commit line runs; this feature does not change
## that ordering, only what now genuinely happens during the await).
##
## strike_use_case — OPTIONAL (default null): a duck-typed
## core/application/resolve_action_use_case.gd ResolveActionUseCase instance
## (or anything exposing an identically-shaped `resolve(combatant,
## action_economy, target, action_name, round_number, cycle_index)` method).
## Left null — the default, and the value every pre-FEAT-007 caller/test
## passes implicitly by omission — an "opportunistic_strike" choice is still
## recorded in `reactions` exactly as FEAT-006 left it (no "strike_result"
## key, no damage, `mover_downed` stays false): a genuinely unwired seam
## degrades safely rather than crashing, matching this project's established
## convention (see `reactor_resolver_fn`'s own doc above).
##
## reactor_action_economy_fn — OPTIONAL (default an invalid Callable):
## Callable(reactor: Dictionary) -> ActionEconomy (or null), resolving a
## reactor Dictionary to ITS OWN live core/rules/action_economy.gd
## ActionEconomy instance (e.g. MainScene.gd's `_action_economy_for()`).
## Required (alongside `strike_use_case`) for the Strike to actually be
## paid for and resolved — when either is missing/unwired, or the Callable
## answers null for a given reactor, that reactor's "opportunistic_strike"
## choice is recorded WITHOUT a strike_result, exactly like the
## strike_use_case-unwired case above (never a crash).
##
## Pay via spend_reaction, NEVER spend_action: the reactor's REAL
## ActionEconomy (resolved via `reactor_action_economy_fn`) is wrapped in
## core/application/ports/action_economy_port.gd's ReactionPaidActionEconomy
## adapter before being handed to `strike_use_case.resolve()` — that adapter
## redirects resolve()'s internal spend_action() call to the wrapped
## instance's OWN spend_reaction(), so the reactor's shared per-round budget
## is genuinely debited via spend_reaction() (verifiable via a spy on the
## real ActionEconomy instance), never spend_action() — see that file's own
## doc for the full mechanism. core/application/reaction_window.gd's
## resume() (iteration K FEAT-007) is a COOPERATING change: it now
## deliberately withholds its own spend_reaction() call for an
## "OpportunisticStrike" trigger specifically so THIS call is the reactor's
## ONE spend for the Strike, never a double-spend.
##
## round_number / cycle_index — OPTIONAL (default 0 each): forwarded
## verbatim to `strike_use_case.resolve()`'s identically-named parameters,
## stamped onto the emitted AttackEvent/RoundHistoryEntry exactly like any
## other Strike.
##
## Ordering / multi-reactor semantics (design notes' "Ordering / interrupt
## semantics", Guy-approved): `candidate_reactors` is resolved strictly in
## the order supplied (initiative order, unchanged from FEAT-006 — see that
## feature's own doc). The FIRST resolved Opportunistic Strike that leaves
## `mover.hp_current <= 0` sets `mover_downed` true and STOPS this method
## from offering the window to any further candidate reactors — a downed
## mover has nothing left to Stride, and a further Strike against it would
## be rejected by resolve_action_use_case.gd's own ERR_TARGET_INVALID
## precondition anyway (defeated targets are invalid), so stopping here
## avoids that wasted/no-op call entirely.
##
## ── iteration K FEAT-008 (US-008) — CALLER-SIDE COMMIT/CANCEL CONTRACT ─────
##
## FEAT-006/FEAT-007 (above) built and returned `mover_downed`, but NEITHER
## of this use case's two live call sites (core/combat/ai.gd's
## `_stride_reaction_resolver_fn` seam -> MainScene.gd's
## `_resolve_enemy_stride_opportunistic_window()`, and MainScene.gd's own
## `_verb_bar_stride_execute()`) ever wired `strike_use_case`/
## `reactor_action_economy_fn` through to this method, NOR did either call
## site ever consult the returned Dictionary at all — the Stride's own
## Movement.stride()/movement_input_controller.stride_to() commit ran
## UNCONDITIONALLY immediately afterward, regardless of what execute()
## reported. This is exactly the "records the choice, resolves no effect"
## (and, once FEAT-007 added effect resolution, "resolves the effect but
## the caller never acts on the result") gap this project's guardrails call
## out (G1/G2/G3): a lethal Opportunistic Strike would correctly deal
## damage and correctly report `mover_downed: true`, yet the mover's Stride
## would STILL commit, moving a defeated combatant's token and leaving the
## game in a state a human real-play session would immediately see as
## broken.
##
## This feature closes that gap at BOTH call sites: `_stride_toward_target()`
## (core/combat/ai.gd) now reads the Dictionary `_stride_reaction_resolver_fn`
## returns (MainScene.gd's `_resolve_enemy_stride_opportunistic_window()` was
## changed from `-> void` to `-> Dictionary` to carry it) and skips its own
## `MovementClass.stride()` call — returning the SAME "no action taken"
## sentinel `{"action_type": "", ...}` decide_action() already returns for
## "no legal Stride destination" — whenever `"mover_downed"` comes back
## true; `_verb_bar_stride_execute()` (MainScene.gd) performs the identical
## check before ever calling `movement_input_controller.stride_to()`. Both
## call sites also now wire `strike_use_case`/`reactor_action_economy_fn`
## for the first time, so an "opportunistic_strike" choice genuinely
## resolves a Strike in live play, not merely in this use case's own unit
## tests. This use case ITSELF still never mutates `mover.hex_coord` or
## calls Movement.stride() — the commit/cancel decision remains entirely
## the caller's responsibility, exactly as this file's own header doc has
## always stated; FEAT-008 only ensures BOTH real callers actually honor
## the Dictionary this method already promised.

class_name ResolveStrideUseCase
extends RefCounted

const OpportunisticStrikeEligibilityClass = preload("res://core/domain/opportunistic_strike_eligibility.gd")

## iteration K FEAT-007 (US-007, ADR-005): the Application-layer collaborator
## _resolve_opportunistic_strike_effect() (below) uses to pay an
## Opportunistic Strike's cost via spend_reaction rather than spend_action —
## see core/application/ports/action_economy_port.gd's own file-level doc
## for the full mechanism.
const ActionEconomyPortClass = preload("res://core/application/ports/action_economy_port.gd")

## REACTION_OPPORTUNISTIC_STRIKE — iteration K FEAT-007: mirrors
## core/application/open_reaction_window_use_case.gd's / core/application/
## reaction_window.gd's own identically-valued constant exactly (both files
## independently define this constant since this one must stay free of
## either import — matching this project's established "each file
## independently defines matching constants" convention, see
## open_reaction_window_use_case.gd's own REACTION_OPPORTUNISTIC_STRIKE doc).
const REACTION_OPPORTUNISTIC_STRIKE: String = "opportunistic_strike"


func execute(
	mover,
	mover_start_hex,
	candidate_reactors: Array,
	reactor_spent_fn: Callable = Callable(),
	reactor_resolver_fn: Callable = Callable(),
	strike_use_case = null,
	reactor_action_economy_fn: Callable = Callable(),
	round_number: int = 0,
	cycle_index: int = 0
) -> Dictionary:
	var reactions: Array = []
	var mover_downed: bool = false

	for reactor in candidate_reactors:
		var reactor_spent: bool = false
		if reactor_spent_fn.is_valid():
			reactor_spent = bool(reactor_spent_fn.call(reactor))

		# Melee-only eligibility (OpportunisticStrikeEligibility's own
		# adjacent/hostile/not-Spent/melee-reach predicate) is enforced HERE,
		# BEFORE reactor_resolver_fn is ever consulted and therefore BEFORE
		# any resolution (choice-asking OR effect-resolution) can possibly
		# proceed for this candidate — a ranged reactor (or any other
		# ineligible candidate) never reaches either step below.
		if not OpportunisticStrikeEligibilityClass.eligible(reactor, mover, mover_start_hex, reactor_spent):
			continue

		if not reactor_resolver_fn.is_valid():
			continue

		var context: Dictionary = {"melee_reach": true}
		var result: Dictionary = await reactor_resolver_fn.call(reactor, context)
		var choice: String = result.get("choice", "none")
		var reaction_entry: Dictionary = {"reactor": reactor, "choice": choice}

		if choice == REACTION_OPPORTUNISTIC_STRIKE:
			var strike_result: Dictionary = _resolve_opportunistic_strike_effect(
				reactor, mover, strike_use_case, reactor_action_economy_fn, round_number, cycle_index
			)
			if not strike_result.is_empty():
				reaction_entry["strike_result"] = strike_result
				if strike_result.get("target_defeated", false):
					mover_downed = true

		reactions.append(reaction_entry)

		if mover_downed:
			break

	# iteration K FEAT-008 (US-008): "stride_should_commit" is the EXPLICIT,
	# self-documenting inverse of `mover_downed` -- added so BOTH live call
	# sites (core/combat/ai.gd's enemy-mover path via MainScene.gd's
	# `_stride_reaction_resolver_fn` seam, and MainScene.gd's own
	# player-mover `_verb_bar_stride_execute()`) consult ONE shared, named
	# field for "may the caller now commit the Stride's hex_coord mutation?"
	# rather than each independently inverting `mover_downed` at its own
	# call site (ADR-002: single source of truth for the commit/cancel
	# decision this use case's own contract already establishes -- see this
	# method's file-level doc, "Once execute() returns ... the caller may
	# now safely commit the mover's position change (UNLESS mover_downed is
	# true...)"). Always true when `mover_downed` is false -- including
	# every pre-FEAT-008 caller/test that never resolves a strike_use_case
	# at all (the field is additive; no existing consumer of "mover_downed"
	# is affected).
	return {
		"reactions": reactions,
		"mover_downed": mover_downed,
		"stride_should_commit": not mover_downed,
	}


## _resolve_opportunistic_strike_effect(reactor, mover, strike_use_case,
## reactor_action_economy_fn, round_number, cycle_index) -> Dictionary —
## iteration K FEAT-007: the effect-resolution helper execute() above
## delegates to once a reactor's choice comes back
## REACTION_OPPORTUNISTIC_STRIKE. Returns {} (empty — no strike_result key
## added to the reaction entry) when either collaborator is unwired/answers
## null, exactly matching this method's own doc's "degrades safely" contract
## — never a crash. Otherwise returns `strike_use_case.resolve()`'s own
## result Dictionary verbatim (resolved/ok/event/target_defeated/damage_final/...
## — see core/application/resolve_action_use_case.gd's resolve() doc).
func _resolve_opportunistic_strike_effect(
	reactor,
	mover,
	strike_use_case,
	reactor_action_economy_fn: Callable,
	round_number: int,
	cycle_index: int
) -> Dictionary:
	if strike_use_case == null or not reactor_action_economy_fn.is_valid():
		push_error("OS_DEBUG: early exit - strike_use_case=%s fn_valid=%s" % [str(strike_use_case), str(reactor_action_economy_fn.is_valid())])
		return {}

	var reactor_action_economy = reactor_action_economy_fn.call(reactor)
	if reactor_action_economy == null:
		push_error("OS_DEBUG: reactor_action_economy is null for reactor=%s" % str(reactor.display_id() if reactor != null else "null"))
		return {}

	var paid_economy = ActionEconomyPortClass.ReactionPaidActionEconomy.new(reactor_action_economy)
	var result: Dictionary = strike_use_case.resolve(reactor, paid_economy, mover, "Strike", round_number, cycle_index)
	push_error("OS_DEBUG: strike resolved ok=%s error=%s target_defeated=%s" % [str(result.get("ok", "?")), str(result.get("error", "none")), str(result.get("target_defeated", false))])
	return result
