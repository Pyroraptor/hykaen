extends "res://presentation/action_controller.gd"

const ActionEconomyClass = preload("res://core/rules/action_economy.gd")

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

func _init(deps: Dictionary) -> void:
	super(deps)


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
	var economy := ActionEconomyClass.new()
	economy.set_dazed(actor.has_condition("Dazed"))
	return economy.combine_actions(
		{"name": "combine_a", "traits": ["Repeat"]},
		{"name": "combine_b", "traits": ["Repeat"]},
		actor.stamina
	)


## availability() -> bool — FEAT-004 (US-004; FR-004): gate the COMBINE verb
## on the two static preconditions derivable without per-turn wiring:
##   1. actor.stamina >= 1 — can afford the Stamina cost.
##   2. actor is NOT Dazed — Dazed forbids combining per spec.
## The ">=2 combinable actions available" predicate is intentionally omitted
## here: it requires per-turn verb-availability state that has no producer
## yet. Invalid pairings are caught at execute() → combine_actions() instead,
## which is the authoritative validation site per the spec ("REUSE that
## validation; the new controller enforces it, then executes").
## Fails closed (false) with no live actor.
func availability() -> bool:
	var actor = current_actor_entity()
	if actor == null:
		return false
	return _validate_combine(actor).get("ok", false)


## enter_selection() -> Dictionary — stub, empty selection. The real
## sub-action queue selection UI (choosing the ordered pair/N-tuple of verbs
## to fuse) is wired in a later feature.
func enter_selection() -> Dictionary:
	return {}


## execute(selection) -> Dictionary — FEAT-002 (US-002; FR-001) + FEAT-003
## (US-003; FR-002; ADR-004): validates via
## core/rules/action_economy.gd ActionEconomy.combine_actions() BEFORE
## spending any Stamina. This is still a PARTIALLY-stubbed execute() -- no
## real Repeat-trait selection and no sub-action queue orchestration yet
## (those are later Iteration N features layered on top, without changing
## this seam; see the file-level FEAT-003/FEAT-004 doc above for why
## combine_actions() is called with placeholder Repeat-tagged actions) -- but
## the Stamina>=1 REJECTION gate, the real live Dazed gate (FEAT-004), and
## the Stamina spend itself are all real:
##   - combine_actions() is the SOLE Stamina-check code path (FR-002 /
##     ADR-004): on failure (stamina_pool < 1), execute() short-circuits
##     BEFORE any mutation and returns {ok: false, reason: "VALIDATION_FAILED"}
##     (design notes' api_contracts #3 failure-mode list), never decrementing
##     actor.stamina.
##   - On success, Combine drains exactly one Stamina through
##     Combatant.spend_stamina(), the SAME single mutator every later
##     validation feature reads/writes through, so there is exactly one
##     Stamina-consuming code path for a Combine execute() call, never a
##     second/duplicate one.
## Fails safe (ok=false, no mutation) when there is no live actor, mirroring
## the FEAT-001 stub's no-crash contract.
func execute(_selection = null) -> Dictionary:
	var actor = current_actor_entity()
	if actor == null:
		return {"ok": false}

	var validation: Dictionary = _validate_combine(actor)
	if not validation.get("ok", false):
		return {"ok": false, "reason": "VALIDATION_FAILED"}

	actor.spend_stamina()
	return {"ok": true}
