extends "res://presentation/action_controller.gd"

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")
const SubActionQueueEntryClass = preload("res://core/rules/sub_action_queue_entry.gd")

## CombineActionController — FEAT-001 (US-001; FR-003; ADR-001), Iteration N
## (Combinations) kickoff.
##
## Scaffolds the COMBINE meta-verb's entry point: this class registers the
## infrastructure seam (MainScene.VERB_TABLE["COMBINE"] -> this class) that
## lets Combine be resolved the SAME data-driven way every other verb is —
## via `_controller("COMBINE")` — without this file ever hard-referencing its
## eventual sub-action controllers. Combine is a META-verb that will
## orchestrate other verbs' own controllers (e.g. Charge = Stride + Strike),
## and it MUST reach them exclusively through the shared
## `_controller(verb_id)` table lookup (i.e. `_controller("STRIDE")` /
## `_controller("STRIKE")`, resolved lazily at the point of use by whatever
## composition root constructs this controller) — never a `preload`/
## `class_name` reference to StrideActionController/StrikeActionController
## in this file. That is what keeps the dependency arrow inward-compatible
## despite Combine sitting one layer "above" the verbs it fuses (see
## docs/iterations/iteration-N-combinations.org).
##
## Scope of the FEAT-001 kickoff: entry-point plumbing. The three-method verb
## contract below was an INERT stub — fail-closed availability(), an empty
## enter_selection(), a no-op/not-ok execute() — mirroring
## presentation/action_controller.gd's own "fails safe rather than crashing"
## base defaults. Real gating (Stamina >= 1, not Dazed, >= 2 combinable
## actions this turn, via core/rules/action_economy.gd's existing
## combine_actions() validation) and the N-length sub-action queue
## orchestration are later Iteration N features, built ON TOP of this seam
## without changing it.
##
## FEAT-002 (US-002; FR-001) layers the FIRST of those on top: execute() now
## wires a REAL, live Stamina decrement (Combatant.spend_stamina()) — see
## execute()'s own doc below. availability()/enter_selection() remain
## unchanged stubs; real Dazed/Repeat/Stamina>=1 validation is still a later
## feature.
##
## FEAT-003 (US-003; FR-002; ADR-004) layers the Stamina>=1 REJECTION gate on
## top of FEAT-002's spend: execute() now routes through the EXISTING
## core/rules/action_economy.gd ActionEconomy.combine_actions() Stamina check
## BEFORE calling Combatant.spend_stamina(), so an actor with insufficient
## Stamina is rejected (ExecutionResult {ok:false, reason:"VALIDATION_FAILED"})
## with ZERO mutation — no parallel/duplicate ad-hoc stamina comparison is
## authored here; combine_actions() is the SOLE Stamina-check code path (see
## execute()'s own doc below). The Repeat check combine_actions() also
## performs is exercised against placeholder Repeat-tagged actions for THIS
## feature's scope only — real Repeat-trait/sub-action-pair selection and the
## real N-length sub-action queue are later Iteration N features layered on
## top, without changing this seam.
##
## FEAT-004 (US-004; FR-004) extracts this Stamina/Dazed check into the
## shared `_validate_combine()` private helper below, reused by BOTH
## availability() and execute() — so real, live Dazed gating (via
## ActionEconomy.set_dazed()) now applies uniformly to both entry points,
## with `action_economy.combine_actions()` remaining the file's SOLE
## Stamina/Dazed-comparison call site (see `_validate_combine()`'s own doc).
##
## FEAT-005 (US-005; ADR-005/FR-010) layers the GENERALIZED N-length
## sub-action queue structure on top: `build_charge_queue()` authors the v0
## 2-entry Charge queue (Stride then Strike) on
## core/rules/sub_action_queue_entry.gd's SubActionQueueEntry value object,
## and `resolve_sub_action_queue()` is the single generic resolution loop
## that walks ANY N-length queue in order_index order, calling a supplied
## resolver once per entry. Neither method is wired into execute() yet —
## the actual sub-controller lookup/no-self-spend invocation (via the verb
## registry) is a later Iteration N feature layered on top of this seam,
## without changing it; this feature's scope is the queue structure and its
## resolution loop only (see this file's own tests plus
## tests/unit/test_sub_action_queue_resolution.gd).
##
## FEAT-007 (US-007; the steel thread's exit point) finally WIRES
## resolve_sub_action_queue() into execute(): a valid, validated Combine now
## actually resolves its sub-action queue (v0: STRIDE then STRIKE) IN ORDER,
## each sub-action reached through its OWN controller looked up via
## `_controller(verb_id)` -- the SAME data-driven-registry seam
## MainScene.gd's own `_controller(verb_id)` resolves every top-level verb
## through (ADR-001) -- never a hard preload/class_name reference to
## StrideActionController/StrikeActionController (see this file's own
## FEAT-001 doc + tests/unit/test_combine_action_controller_registration.gd's
## static-scan criterion, which still holds).
##
## `_controller(verb_id)` here is a thin wrapper around `_controller_for_fn`
## -- a Callable(verb_id) -> ActionController-like collaborator injected via
## `deps["controller_for"]`. The REAL composition root (MainScene.gd) wires
## this to `Callable(self, "_controller")`, so a real, booted Combine
## resolves its STRIDE/STRIKE sub-controllers to the EXACT SAME memoized
## instances every other verb reaches through MainScene's own
## `_controller(verb_id)` table lookup -- one registry, one resolution path,
## reused rather than duplicated. Because each sub-action is resolved AND
## EXECUTED in queue order (order_index, via
## SubActionQueueEntryClass.sorted(), already enforced by
## resolve_sub_action_queue()), a queued STRIKE's own reach/target-validity
## check (StrikeActionController._reachable_targets(), which always reads
## the actor's LIVE, current hex_coord) naturally observes the actor's
## POST-Stride position -- Stride's own execute() call has already mutated
## that live Combatant instance in place by the time Strike's execute() call
## begins. No positional snapshot/threading is authored here; this falls out
## of "resolve strictly in order, through live references" for free.
##
## When no `controller_for` resolver is wired (every PRE-FEAT-007 unit test
## in this suite -- tests/unit/test_combine_stamina_decrement.gd /
## test_combine_stamina_rejection.gd -- constructs a CombineActionController
## with only `{"session_holder": ...}`), execute() degrades to the exact
## FEAT-002/FEAT-003 contract those tests already pin: validate, then spend
## exactly one Stamina, report {ok: true} -- no sub-action queue is built or
## resolved. This is not a second/parallel code path so much as it is the
## PRE-existing path, preserved verbatim for callers that never opt into
## sub-action orchestration by supplying a resolver.
##
## Sub-controller execute() calls are `await`-ed (StrideActionController's
## own execute() itself awaits ResolveStrideUseCase's Opportunistic-Strike
## resolution), so `resolve_sub_action_queue()` now also awaits each
## resolver call -- `await` on an already-resolved (non-coroutine) value is
## a documented no-op in GDScript, so every PRE-FEAT-007 synchronous
## resolver (tests/unit/test_sub_action_queue_resolution.gd,
## tests/unit/test_combine_enter_selection.gd) is unaffected.
##
## FEAT-010 (US-010; FR-009; ADR-006) closes the abort-safety gap FEAT-008's
## charge-first rework left open: FEAT-008 committed the Combine's own
## action/Stamina charge BEFORE resolving the sub-action queue, so an
## illegal/aborting sub-action (e.g. an illegal Stride destination) could
## previously leave an ORPHANED spend -- a committed charge with zero
## corresponding effect. `execute()` now runs a non-mutating
## `_preflight_charge_check()` (replicating ActionEconomy.spend_action()'s
## own precondition order via its existing public queries) BEFORE resolving
## the queue -- so an already-exhausted action economy still aborts before
## any sub-action runs, exactly as before -- but only COMMITS the real
## charge once the queue reaches a committed (not aborted) terminal state.
## `_sub_action_resolver()` also now classifies a failing STRIDE entry as a
## hard {ok: false, reason: "ILLEGAL_SUB_TARGET"} abort (no effect ever
## applied, so the whole Combine aborts with zero charge), and a STRIKE
## entry whose target has been invalidated as a graceful
## {ok: true, skipped: true, reason: "TARGET_INVALIDATED"} skip (the queue
## still reaches a defined {ok: true} terminal state, and the ONE charge is
## still committed, since an earlier entry's effect -- e.g. the queued
## STRIDE's move -- already genuinely applied). See
## tests/unit/test_combine_abort_illegal_stride.gd /
## tests/unit/test_combine_target_invalidated_strike.gd.

## _controller_for_fn — FEAT-007: the data-driven sub-action-controller
## resolver, `deps["controller_for"]` (a Callable(verb_id: String) ->
## ActionController-like instance). Defaults to an invalid/empty Callable()
## when not supplied, in which case `_controller(verb_id)` returns null and
## execute() falls back to its pre-FEAT-007 stamina-only contract (see the
## file-level doc above). The REAL composition root wires this to
## `Callable(MainScene, "_controller")`.
var _controller_for_fn: Callable


func _init(deps: Dictionary) -> void:
	super(deps)
	_controller_for_fn = deps.get("controller_for", Callable())


## _validate_combine(actor) -> Dictionary — the SOLE Stamina/Dazed-check code
## path shared by availability() and execute() (FEAT-004 layered on top of
## FEAT-003's ADR-004 invariant): both callers route through this single
## private helper rather than each re-deriving their own comparison, so
## action_economy.combine_actions() remains the ONLY place a Stamina/Dazed
## comparison is ever authored in this file (see
## tests/unit/test_combine_stamina_rejection.gd's
## test_no_parallel_ad_hoc_stamina_comparison_exists /
## test_combine_actions_is_the_sole_stamina_check_call_site, which assert
## exactly this). Placeholder Repeat-tagged actions are used for THIS
## feature's scope only -- real Repeat-trait/sub-action-pair selection is a
## later Iteration N feature layered on top, without changing this seam.
func _validate_combine(actor) -> Dictionary:
	return _run_combine_validation(
		actor,
		{"name": "combine_a", "traits": ["Repeat"]},
		{"name": "combine_b", "traits": ["Repeat"]}
	)


## _run_combine_validation(actor, action_a, action_b) -> Dictionary — FEAT-006
## (US-006; FR-005): the SOLE call site of
## action_economy.combine_actions() within this file, shared by
## _validate_combine() (availability()/execute()'s placeholder Repeat-tagged
## check) AND enter_selection() (the REAL, player-chosen pair). Extracting
## this keeps the file's existing "combine_actions() called exactly once"
## invariant intact (see
## tests/unit/test_combine_stamina_rejection.gd's
## test_combine_actions_is_the_sole_stamina_check_call_site) even though two
## different call SITES within the source now need to reach it -- both route
## through this one private helper instead of each calling
## economy.combine_actions() directly.
func _run_combine_validation(actor, action_a: Dictionary, action_b: Dictionary) -> Dictionary:
	var economy := ActionEconomyClass.new()
	economy.set_dazed(actor.has_condition("Dazed"))
	return economy.combine_actions(action_a, action_b, actor.stamina)


## availability() -> bool — FEAT-004 (US-004; FR-004): gate the COMBINE verb
## on its three preconditions (the steel thread's entry-point precondition:
## "offered only when availability() gating passes"):
##   1. actor.stamina >= 1 — can afford the Stamina cost.
##   2. actor is NOT Dazed — Dazed forbids combining per spec.
##   3. actor.combinable_actions_available() >= 2 — the live per-turn
##      combinable-action-slot count (core/domain/combatant.gd's
##      `actions_this_turn`, e.g. a fresh turn's Movement + Primary slots),
##      the entity-sourced predicate design notes call for alongside the
##      live ActionEconomy.can_take_action() check below.
## Also consults the live ActionEconomy.can_take_action() gate (FEAT-008),
## mirroring Strike/Stride's own availability(). Invalid PAIRINGS (e.g. two
## identical non-Repeat verbs) are still caught at execute() →
## combine_actions() instead -- that remains the authoritative pairing-
## validation site per the spec ("REUSE that validation; the new controller
## enforces it, then executes").
## Fails closed (false) with no live actor.
func availability() -> bool:
	var actor = current_actor_entity()
	if actor == null:
		return false
	var ae = current_action_economy()
	if ae != null and not ae.can_take_action():
		return false
	if actor.combinable_actions_available() < 2:
		return false
	return _validate_combine(actor).get("ok", false)


## _default_charge_pair() -> Array[Dictionary] — v0's fixed Charge sub-action
## pair (Stride, Strike): two DIFFERENT verbs, so the different-verb branch
## of action_economy.combine_actions()'s rule accepts them with no Repeat
## trait required. This is enter_selection()'s default `pair` argument when
## a caller doesn't supply its own (FEAT-006; US-006).
static func _default_charge_pair() -> Array:
	return [
		{"verb_id": "STRIDE", "traits": []},
		{"verb_id": "STRIKE", "traits": []},
	]


## enter_selection(pair) -> Dictionary — FEAT-006 (US-006; FR-005): the
## player-facing entry point for choosing the ordered pair of sub-actions to
## fuse. `pair` is an Array of exactly two Dictionaries shaped
## {"verb_id": String, "traits": Array[String]} -- v0 defaults to
## _default_charge_pair() (STRIDE, STRIKE -- different verbs, so no Repeat
## trait is required), but a caller (present or future selection UI) may
## instead supply an identical-verb pair (e.g. two STRIKEs), which is legal
## ONLY when both entries carry the "Repeat" trait.
##
## Routes the different-verb-OR-same-verb-with-Repeat rule through the SAME
## action_economy.combine_actions() validation call _validate_combine()
## (shared by availability()/execute()) already uses -- this is not a
## second/parallel rule implementation; only the two actions handed to
## combine_actions() differ (the REAL chosen pair, not _validate_combine()'s
## placeholder Repeat-tagged stand-ins).
##
## Returns:
##   {ok: true, queue: Array[SubActionQueueEntry]}  -- the FEAT-005 queue
##       structure (order_index 0..N-1, in pair order, targeting_payload
##       still null -- populated by each sub-action's own targeting pass, a
##       later feature), built via the SAME SubActionQueueEntry value object
##       build_charge_queue() constructs from, so the default pair's queue
##       matches build_charge_queue()'s output exactly.
##   {ok: false, reason: "IDENTICAL_NON_REPEAT_VERBS" | "DAZED" |
##       "INSUFFICIENT_STAMINA"} -- surfaced to the player as a rejected
##       selection, never a crash (mirrors availability()/execute()'s
##       fail-closed contract). reason is whatever
##       action_economy.combine_actions() reports.
## Fails closed (ok=false, no reason) with no live actor or a malformed
## (non-2-entry) pair.
func enter_selection(pair: Array = _default_charge_pair()) -> Dictionary:
	var actor = current_actor_entity()
	if actor == null or pair.size() != 2:
		return {"ok": false}

	var action_a := {"name": pair[0].get("verb_id", ""), "traits": pair[0].get("traits", [])}
	var action_b := {"name": pair[1].get("verb_id", ""), "traits": pair[1].get("traits", [])}

	var validation: Dictionary = _run_combine_validation(actor, action_a, action_b)

	if not validation.get("ok", false):
		return {"ok": false, "reason": validation.get("reason")}

	var queue: Array = [
		SubActionQueueEntryClass.new(0, pair[0].get("verb_id", "")),
		SubActionQueueEntryClass.new(1, pair[1].get("verb_id", "")),
	]
	return {"ok": true, "queue": queue}


## execute(selection) -> Dictionary — FEAT-002 (US-002; FR-001) + FEAT-003
## (US-003; FR-002; ADR-004) + FEAT-007 (US-007; the steel thread's exit
## point) + FEAT-010 (US-010; FR-009; ADR-006, abort-safe execution):
## validates via core/rules/action_economy.gd ActionEconomy.combine_actions()
## BEFORE spending any Stamina, THEN (FEAT-007) queues and resolves the
## chosen sub-actions IN ORDER, each through its own controller looked up via
## `_controller(verb_id)` (see this file's own FEAT-005/FEAT-007 doc above):
##   - combine_actions() is the SOLE Stamina-check code path (FR-002 /
##     ADR-004): on failure (stamina_pool < 1), execute() short-circuits
##     BEFORE any mutation and returns {ok: false, reason: "VALIDATION_FAILED"}
##     (design notes' api_contracts #3 failure-mode list), never decrementing
##     actor.stamina.
##   - `selection` (optional) is a Dictionary that may carry:
##       "queue"    — an Array[SubActionQueueEntry] to resolve, defaulting to
##                    build_charge_queue() (v0's STRIDE-then-STRIKE Charge)
##                    when omitted.
##       <verb_id>  — the targeting payload to hand that queue entry's own
##                    controller.execute() (e.g. selection["STRIDE"] is a
##                    HexCoord, selection["STRIKE"] is a target_id String) —
##                    falling back to the queue entry's own
##                    targeting_payload when the key is absent.
##   - FEAT-010 (US-010): the Combine-level action/Stamina charge is now
##     committed ONLY AFTER the sub-action queue reaches a committed (not
##     aborted) terminal state — never before, so an illegal/aborting
##     sub-action can never leave an "orphaned spend" (a committed charge
##     with no corresponding effect). A non-mutating `_preflight_charge_check()`
##     (below) still runs BEFORE the queue resolves, replicating
##     ActionEconomy.spend_action()'s own precondition order (ALREADY_SPENT /
##     ACTION_ALREADY_USED / MOVEMENT_ALREADY_USED) purely by reading its
##     existing public queries (is_spent()/can_take_action()/
##     can_take_movement_action()) — so a Combine whose action economy is
##     already exhausted STILL fails before any sub-action resolves, exactly
##     preserving FEAT-008's original charge-first guarantee
##     (tests/unit/test_combine_single_charge.gd's
##     test_combine_execute_fails_before_effects_when_action_already_used)
##     without ever committing a charge that resolution might subsequently
##     abort. "Movement" trait is tagged when the queue contains a STRIDE, so
##     the movement lockout trips exactly once at the Combine level — the
##     SAME gate every standalone Stride trips — rather than being bypassed
##     or double-tripped (FEAT-009).
##   - Each entry resolves via resolve_sub_action_queue() (FEAT-005's
##     existing generic, order_index-ordered loop -- no second/duplicate
##     resolution loop is authored here), whose resolver (`_sub_action_resolver()`
##     below) looks the entry's controller up via `_controller(entry.verb_id)`
##     and awaits its execute(payload) call. Because the loop resolves
##     strictly in order, a queued STRIKE always observes the actor's
##     POST-move position when a STRIDE precedes it in the queue (see
##     file-level doc).
##       - A failing STRIDE entry (e.g. an illegal/no-longer-selectable
##         destination) is classified {ok: false, reason: "ILLEGAL_SUB_TARGET"}
##         by `_sub_action_resolver()` — this ABORTS the whole Combine (no
##         sub-action past it is ever reached, no charge is ever committed,
##         since Stride's own effect never applied): execute() reports
##         {ok: false, reason: "ILLEGAL_SUB_TARGET", resolved_verb_ids: <ids
##         resolved before it>} (FEAT-010; US-010).
##       - A failing STRIKE entry whose target is no longer selectable (e.g.
##         it died/left reach between the queued STRIDE committing and
##         STRIKE's own resolution step) is classified as a GRACEFUL SKIP —
##         {ok: true, skipped: true, reason: "TARGET_INVALIDATED"} — rather
##         than aborting: the queue resolution loop continues/completes, so a
##         Combine whose STRIDE already committed still reaches a defined
##         {ok: true} terminal ExecutionResult (never a partial-effect abort)
##         and its ONE charge is still committed below, since an effect (the
##         Stride move) genuinely applied (FEAT-010; US-010).
##   - Any other sub-action failure still aborts the whole Combine (no
##     charge, no further sub-actions): execute() reports {ok: false, reason:
##     <the failing entry's own reason>, resolved_verb_ids: <ids resolved
##     before it failed>}.
##   - On a committed terminal state, Combine drains exactly one Stamina
##     through Combatant.spend_stamina(), the SAME single mutator every
##     earlier validation feature reads/writes through, so there is exactly
##     one Stamina-consuming code path for a Combine execute() call, never a
##     second/duplicate one.
##   - When no `controller_for` resolver was injected (deps lacks
##     "controller_for"), execute() degrades to the pre-FEAT-007
##     validate-then-spend-only contract (see file-level doc) -- no queue is
##     built or resolved, preserving tests/unit/test_combine_stamina_decrement.gd
##     / tests/unit/test_combine_stamina_rejection.gd's existing pin exactly.
## Fails safe (ok=false, no mutation) when there is no live actor, mirroring
## the FEAT-001 stub's no-crash contract.
func execute(selection = null) -> Dictionary:
	var actor = current_actor_entity()
	if actor == null:
		return {"ok": false}

	var validation: Dictionary = _validate_combine(actor)
	if not validation.get("ok", false):
		return {"ok": false, "reason": "VALIDATION_FAILED"}

	if not _controller_for_fn.is_valid():
		# No sub-action controller resolver wired -- degrade to the
		# pre-FEAT-007 validate-then-spend-only contract (see file-level doc).
		actor.spend_stamina()
		return {"ok": true}

	var sel: Dictionary = selection if selection is Dictionary else {}
	var queue: Array = sel.get("queue", build_charge_queue())
	var has_stride: bool = _queue_has_stride(queue)

	# FEAT-010 (US-010; FR-009; ADR-006) — a non-mutating precondition peek,
	# BEFORE any sub-action resolves, so an already-exhausted action economy
	# still aborts a Combine with zero mutation (preserving FEAT-008's
	# original charge-first guarantee) WITHOUT committing a charge this
	# call might otherwise need to roll back if the queue subsequently
	# aborts (see this method's own doc above).
	var economy = current_action_economy()
	if economy != null:
		var preflight: Dictionary = _preflight_charge_check(economy, has_stride)
		if not preflight.get("ok", false):
			return {"ok": false, "reason": preflight.get("reason", "ACTION_UNAVAILABLE")}

	# Resolve sub-actions under full suppression — each sub-controller's own
	# spend_action() becomes a no-op (the Combine's own charge, committed
	# below only once this loop reaches a committed terminal state, is the
	# ONE real action-economy mutation), but its own game effect (the move,
	# the attack) still applies normally.
	var resolution: Dictionary = await resolve_sub_action_queue(queue, _sub_action_resolver(sel))
	if not resolution.get("ok", false):
		return {
			"ok": false,
			"reason": resolution.get("reason", "SUB_ACTION_FAILED"),
			"resolved_verb_ids": resolution.get("resolved_verb_ids", []),
		}

	# FEAT-010: the queue reached a committed (not aborted) terminal state —
	# NOW, and only now, commit the Combine's own single action-economy
	# charge, tagged "Movement" once when the queue contained a STRIDE
	# (FEAT-009). Defense in depth: this should be unreachable given the
	# preflight check above (nothing else can mutate `economy` while
	# sub-actions run under no-self-spend suppression), but on the
	# (unreachable in practice) chance it still fails, report failure with
	# zero further mutation rather than spending Stamina for a Combine whose
	# own action charge itself failed.
	if economy != null:
		var combine_traits: Array = ["Movement"] if has_stride else []
		var charge: Dictionary = economy.spend_action({"name": "COMBINE", "traits": combine_traits})
		if not charge.get("success", false):
			return {"ok": false, "reason": charge.get("reason", "ACTION_UNAVAILABLE")}

	actor.spend_stamina()
	return {
		"ok": true,
		"resolved_verb_ids": resolution.get("resolved_verb_ids", []),
		"skipped_verb_ids": resolution.get("skipped_verb_ids", []),
	}


## _queue_has_stride(queue) -> bool — true iff `queue` contains a STRIDE
## entry. Shared by execute()'s preflight check and its post-resolution
## charge tagging (FEAT-009/FEAT-010) so both consult the SAME single
## derivation of "does this Combine's queue contain a Movement-trait
## sub-action" rather than two independently-authored scans.
func _queue_has_stride(queue: Array) -> bool:
	for entry in queue:
		if entry.verb_id == "STRIDE":
			return true
	return false


## _preflight_charge_check(economy, has_stride) -> Dictionary — FEAT-010
## (US-010; FR-009; ADR-006): a PURE, non-mutating read of the SAME
## precondition order core/rules/action_economy.gd's ActionEconomy.spend_action()
## itself enforces (ALREADY_SPENT -> ACTION_ALREADY_USED ->
## MOVEMENT_ALREADY_USED), using only its existing public queries
## (is_spent()/can_take_action()/can_take_movement_action()). This lets
## execute() fail BEFORE any sub-action resolves when the actor's action
## economy is already exhausted — matching the real spend_action() call's
## own rejection exactly — without actually committing a charge (economy is
## left completely untouched either way): the REAL commit happens only once
## the sub-action queue below reaches a committed terminal state (see
## execute()'s own doc). Returns {ok: true} when a real spend_action() call
## with these same traits would be expected to succeed.
func _preflight_charge_check(economy, has_stride: bool) -> Dictionary:
	if economy.is_spent():
		return {"ok": false, "reason": "ALREADY_SPENT"}
	if not economy.can_take_action():
		return {"ok": false, "reason": "ACTION_ALREADY_USED"}
	if has_stride and not economy.can_take_movement_action():
		return {"ok": false, "reason": "MOVEMENT_ALREADY_USED"}
	return {"ok": true}


## _controller(verb_id) -> ActionController or null — FEAT-007: the SAME
## data-driven table-lookup seam every other verb (and now Combine's own
## sub-actions) is resolved through, delegating entirely to the injected
## `_controller_for_fn` Callable (see this file's own field-level doc above)
## rather than ever preloading/hard-referencing a concrete controller class.
## Returns null when no resolver was ever injected -- callers (execute()'s
## resolver below) must treat that as "sub-action controller unavailable",
## never crash.
func _controller(verb_id: String):
	if not _controller_for_fn.is_valid():
		return null
	return _controller_for_fn.call(verb_id)


## _sub_action_resolver(sel) -> Callable — FEAT-007 + FEAT-008 (US-008;
## FR-007; ADR-003). Builds the Callable(entry: SubActionQueueEntry) ->
## Dictionary resolve_sub_action_queue() expects, closing over `sel`
## (execute()'s own selection Dictionary). For each queue entry: resolves
## its controller via `_controller(entry.verb_id)` (never a direct class
## reference), then awaits that controller's OWN execute(payload,
## no_self_spend_execution=true) call -- `payload` is `sel[entry.verb_id]`
## when the caller supplied one, else the entry's own (possibly still-null)
## targeting_payload. Reports {ok: false, reason: "ERR_CONTROLLER_NOT_FOUND"}
## for an entry whose verb_id has no resolvable controller, rather than
## crashing.
##
## `no_self_spend_execution=true` is THE single-charge invariant (US-008):
## every real sub-controller (StrideActionController/StrikeActionController,
## unmodified apart from accepting this additive flag) still applies its OWN
## game effect (the Stride move, the Strike attack) exactly as it would
## standalone, but its own action-economy self-charge becomes a no-op for
## the duration of that call (core/rules/action_economy.gd's
## begin_self_spend_suppression()/end_self_spend_suppression(), which each
## sub-controller's own execute() now brackets its self-charge point with --
## see their own FEAT-008 doc). So a queue's SECOND-or-later sub-action is
## never rejected with ACTION_ALREADY_USED, and the shared per-round budget
## is never touched by any sub-action at all -- execute() above charges the
## ONE real action (+ one Stamina) exactly once, at the Combine level, once
## the whole queue has resolved. This replaces the earlier FEAT-007 stopgap
## (`_allow_next_sub_action_spend()`, which cleared the per-turn gate between
## sub-actions and let EACH one genuinely drain the shared budget) with the
## real no-self-spend mode the design always intended.
##
## FEAT-010 (US-010; FR-009; ADR-006) — abort-safe execution: a sub-action's
## own targeting/legality check runs at exactly this point, immediately
## before its own effect would apply (Stride/Strike's own execute()
## contract, unchanged by this feature). A failing entry's result is
## reclassified here, by verb, into exactly one of two outcomes:
##   - A failing STRIDE entry (destination no longer/never a legal Stride
##     destination -- StrideActionController's own execute() rejects it,
##     via its movement collaborator, BEFORE any positional mutation) is
##     reported {ok: false, reason: "ILLEGAL_SUB_TARGET"}, propagating a
##     genuine failure up to resolve_sub_action_queue()'s existing
##     stop-at-first-failure contract -- the whole Combine aborts, no charge
##     is ever committed (execute() above only reaches its charge point once
##     resolution succeeds), and no effect has applied for the aborted
##     entry, so there is no orphaned spend.
##   - A failing STRIKE entry whose target is no longer selectable (dead,
##     out of reach, or otherwise invalidated between the queued STRIDE
##     committing and this entry's own resolution step --
##     StrikeActionController's own execute() reports
##     "ERR_TARGET_NOT_SELECTABLE") is reported {ok: true, skipped: true,
##     verb_id: "STRIKE", reason: "TARGET_INVALIDATED"} instead of a
##     failure -- a GRACEFUL skip: resolve_sub_action_queue() treats this as
##     a successfully-resolved entry (no abort), so the Combine still
##     reaches a defined {ok: true} terminal ExecutionResult reflecting
##     whatever DID commit (e.g. the queued STRIDE's own move) rather than
##     discarding it. execute() above still commits its ONE charge in this
##     case, since an effect (the earlier STRIDE) genuinely applied -- the
##     no-orphaned-spend invariant is about spend WITHOUT effect, not about
##     every sub-action necessarily completing.
##   - Any other sub-action failure (an unresolved controller lookup, or a
##     verb-specific rejection this feature does not special-case) is
##     returned verbatim, preserving pre-FEAT-010 behaviour.
func _sub_action_resolver(sel: Dictionary) -> Callable:
	return func(entry):
		var controller = _controller(entry.verb_id)
		if controller == null:
			return {"ok": false, "reason": "ERR_CONTROLLER_NOT_FOUND"}
		var payload = sel.get(entry.verb_id, entry.targeting_payload)
		var result: Dictionary = await controller.execute(payload, true)
		if result.get("ok", false):
			return result

		if entry.verb_id == "STRIDE":
			return {
				"ok": false,
				"reason": "ILLEGAL_SUB_TARGET",
				"sub_error": result.get("error", result.get("reason", null)),
			}

		if entry.verb_id == "STRIKE" and result.get("error", "") == "ERR_TARGET_NOT_SELECTABLE":
			return {"ok": true, "skipped": true, "verb_id": entry.verb_id, "reason": "TARGET_INVALIDATED"}

		return result


## build_charge_queue() -> Array[SubActionQueueEntry] — FEAT-005 (US-005;
## ADR-005/FR-010): the v0 Charge sub-action queue (Stride then Strike),
## authored on the generalized SubActionQueueEntry structure rather than as
## a bespoke fixed-pair shape. Delegates entirely to
## SubActionQueueEntry.build_charge_queue() -- this file introduces no
## second/parallel way to construct a Charge queue.
func build_charge_queue() -> Array:
	return SubActionQueueEntryClass.build_charge_queue()


## FEAT-006 (US-006; FR-005) layers the REAL enter_selection() player-facing
## sub-action pair selection on top of FEAT-005's queue structure: the
## default (no-argument) call offers v0 Charge's [STRIDE, STRIKE] pair --
## two DIFFERENT verbs, so no Repeat trait is required -- but a caller may
## instead supply its own two-entry `pair` (e.g. an identical-verb pair),
## which is legal ONLY when both entries carry the "Repeat" trait. The
## different-verb-OR-same-verb-with-Repeat rule is enforced through the
## SAME action_economy.combine_actions() validation call every other Combine
## entry point already shares (see enter_selection()'s own doc below) --
## no second/parallel rule implementation is authored here.
##
## resolve_sub_action_queue(queue, resolver) -> Dictionary — FEAT-005
## (US-005; ADR-005/FR-010): the GENERIC N-length sub-action queue
## resolution loop. Sorts `queue` by order_index (via
## SubActionQueueEntry.sorted() — order_index, never insertion/array
## position, is authoritative) and calls `resolver` once per entry, in
## that order. Never assumes a fixed length: the SAME loop drives the v0
## 2-entry Charge queue (build_charge_queue() above) and any synthetic
## N-length queue a caller supplies, with zero special-casing on queue
## length (see tests/unit/test_sub_action_queue_resolution.gd's N=3 case).
##
## `resolver` — a Callable(entry: SubActionQueueEntry) -> Dictionary,
## returning a Result-style {ok: bool, ...} Dictionary for that single
## entry's resolution. The actual sub-controller lookup/execute call (via
## the verb registry, with a no-self-spend execution mode) is a later
## Iteration N feature layered on top of this seam; this loop is
## resolver-agnostic and performs no verb-table lookups of its own.
##
## Stops at the first entry whose resolver call reports ok=false — no
## further entries are resolved beyond that point — and returns
## {ok: false, resolved_verb_ids: <ids resolved before the failure>,
## reason: <the failing entry's own reason, if any>}. When every entry
## resolves, returns {ok: true, resolved_verb_ids: <all verb_ids, in
## resolution order>, skipped_verb_ids: <the subset of resolved_verb_ids
## whose own resolver result carried "skipped": true>}.
##
## FEAT-010 (US-010; FR-009; ADR-006) adds `skipped_verb_ids` purely
## additively -- a resolver may report {ok: true, skipped: true, ...} for an
## entry that gracefully degraded rather than genuinely applying its effect
## (e.g. presentation/combine_action_controller.gd's own `_sub_action_resolver()`
## for a Strike whose target was invalidated -- see that method's own doc).
## Such an entry still counts as "resolved" (ok=true, no abort) but is ALSO
## surfaced in `skipped_verb_ids` so a caller (execute()) can distinguish "every
## sub-action's effect genuinely applied" from "the queue reached a defined
## terminal state, but not every entry's effect applied" without either loop
## or caller re-deriving that distinction from resolver internals.
func resolve_sub_action_queue(queue: Array, resolver: Callable) -> Dictionary:
	var resolved_verb_ids: Array = []
	var skipped_verb_ids: Array = []
	var ordered: Array = SubActionQueueEntryClass.sorted(queue)
	for entry in ordered:
		# FEAT-007: awaited so an async resolver (e.g. one that calls a real
		# ActionController.execute(), which may itself await) is driven to
		# completion before this loop reads its result. `await` on an
		# already-resolved (non-coroutine) value is a documented GDScript
		# no-op, so every pre-existing synchronous resolver (this file's own
		# earlier tests) is unaffected.
		var result: Dictionary = await resolver.call(entry)
		if not result.get("ok", false):
			return {
				"ok": false,
				"resolved_verb_ids": resolved_verb_ids,
				"reason": result.get("reason", null),
			}
		resolved_verb_ids.append(entry.verb_id)
		if result.get("skipped", false):
			skipped_verb_ids.append(entry.verb_id)
	return {"ok": true, "resolved_verb_ids": resolved_verb_ids, "skipped_verb_ids": skipped_verb_ids}
