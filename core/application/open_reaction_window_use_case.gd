## core/application/open_reaction_window_use_case.gd — OpenReactionWindowUseCase
## (iteration K FEAT-004 / US-004, ADR-004)
##
## Application layer (Clean Architecture): a GENERALIZED reaction-window opener
## usable for any of the three window types this steel thread's design notes
## define (PreHitAvoidance, OnHitMitigation, OpportunisticStrike — only the
## first two are ever driven by this feature; OpportunisticStrike is a future
## Stride-triggered feature's concern). Depends ONLY on the injected
## ReactionChooserPort (an Application-layer port — core/application/ports/
## reaction_chooser_port.gd) and core/rules/action_economy.gd's
## RESERVE/MAX_BUDGET constants (this project's established precedent for
## "domain-safe" core/rules/ references — see infrastructure/
## ai_reaction_policy.gd's own identical import). Never imports an
## adapter/infrastructure/presentation type, and never touches the engine
## scene tree — synchronous, no `await`, no coroutine, so a caller (e.g.
## core/application/resolve_action_use_case.gd's resolve_reactive()) can
## invoke it inline without ever suspending — this is what guarantees NO
## pop-up/UI can ever open on this call path (this feature's test_criteria
## "no pop-up UI opens during the enemy's reaction window").
##
## open(window_type, legal_reactions, context, chooser_port) -> String
##   window_type     — String, one of "PreHitAvoidance" | "OnHitMitigation" |
##                      "OpportunisticStrike" (per this feature's design
##                      notes' ReactionContext.window_type). Consumed ONLY for
##                      observability (an eventual structured combat-log
##                      entry's own "window_type" field, per this feature's
##                      design notes) — this method never branches on it: the
##                      caller is responsible for computing `legal_reactions`
##                      appropriately for the window it is opening (mirrors
##                      core/application/reaction_window.gd's own
##                      trigger_type-agnostic resume()/open_and_resolve()
##                      contract).
##   legal_reactions — Array of String reaction names (e.g. ["dodge"],
##                      ["parry", "block"]) the caller has ALREADY computed
##                      via the appropriate eligibility predicate(s)
##                      (core/rules/resolution.gd's is_dodge_eligible()/
##                      is_steel_eligible()/is_parry_eligible()/
##                      is_block_eligible(), or a use case's own wrapper —
##                      see core/application/resolve_to_hit_uc.gd's
##                      legal_prehit_reactions() / core/application/
##                      apply_on_hit_defense_uc.gd's legal_onhit_reactions(),
##                      this feature's own additions). This use case NEVER
##                      re-derives eligibility itself.
##   context         — Dictionary; forwarded VERBATIM to chooser_port.choose()
##                      as its own `context` argument (e.g. built by
##                      core/application/_build_defense_context.gd's
##                      build_prehit_context()/build_onhit_context()). Also
##                      consulted directly for "action_current" — see the
##                      RESERVE gate below.
##   chooser_port    — a ReactionChooserPort implementation (e.g.
##                      infrastructure/ai_reaction_policy.gd's AIReactionPolicy
##                      for a synchronous, no-pop-up AI reactor).
##
## Returns exactly one of `legal_reactions`' own entries, or
## ReactionChooserPort.PASS ("none") — NEVER throws/hangs (per this feature's
## error_handling design note: "Pass, regardless of the above, if reacting
## would leave action_current-1 < 1").
##
## Guard order (each short-circuits to PASS WITHOUT ever invoking
## chooser_port.choose() — mirrors this feature's api_contracts
## "NoLegalReactionsError -> returns 'pass'" / "ReactionBudgetExhaustedError
## ... forces 'pass' deterministically, logged for observability"):
##   1. legal_reactions is empty — nothing to offer.
##   2. the RESERVE gate (action_current - 1 < ActionEconomy.RESERVE) — a
##      DEFENSE-IN-DEPTH re-check of the SAME gate infrastructure/
##      ai_reaction_policy.gd's own choose() already applies internally, so a
##      misbehaving/future ReactionChooserPort implementation that skips its
##      own gate can never break the reserve invariant from THIS seam.
##   3. chooser_port is null — a defensive no-op path (never crashes on an
##      unwired seam).
## A chosen reaction not present in legal_reactions (a misbehaving chooser) is
## a safety-net degrade to PASS, logged via push_error() — mirrors
## core/application/reaction_window.gd's resume()/open_and_resolve() family's
## identical ERR_ILLEGAL_CHOICE-style safety net.
##
## Determinism (this feature's test_criteria): open() consumes ZERO RNG of its
## own — every input is read verbatim from `context`/`legal_reactions`, so two
## calls with identical arguments always return the identical choice.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var use_case := OpenReactionWindowUseCase.new()
##   var choice: String = use_case.open(
##       OpenReactionWindowUseCase.WINDOW_PRE_HIT_AVOIDANCE,
##       ["dodge"], {"mobility": 1, "targeted_defense_value": 10, "action_current": 7},
##       AIReactionPolicyClass.new()
##   )
##   # choice -> "dodge"

class_name OpenReactionWindowUseCase
extends RefCounted

const ActionEconomyClass       = preload("res://core/rules/action_economy.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")

## Window-type String constants — see this feature's design notes'
## ReactionContext.window_type enum (PreHitAvoidance | OnHitMitigation |
## OpportunisticStrike). Exposed so callers never hand-roll these literals.
const WINDOW_PRE_HIT_AVOIDANCE: String = "PreHitAvoidance"
const WINDOW_ON_HIT_MITIGATION: String = "OnHitMitigation"
const WINDOW_OPPORTUNISTIC_STRIKE: String = "OpportunisticStrike"


## open(window_type, legal_reactions, context, chooser_port) -> String — see
## class-level doc for the full contract.
func open(window_type: String, legal_reactions: Array, context: Dictionary, chooser_port) -> String:
	if legal_reactions.is_empty():
		return ReactionChooserPortClass.PASS

	var action_current: int = context.get("action_current", ActionEconomyClass.MAX_BUDGET)
	if action_current - 1 < ActionEconomyClass.RESERVE:
		push_error(
			"OpenReactionWindowUseCase.open: RESERVE gate forced Pass for window_type='%s' (action_current=%d)"
			% [window_type, action_current]
		)
		return ReactionChooserPortClass.PASS

	if chooser_port == null:
		return ReactionChooserPortClass.PASS

	var requested_choice: String = chooser_port.choose(legal_reactions, context)
	if requested_choice == ReactionChooserPortClass.PASS or legal_reactions.has(requested_choice):
		return requested_choice

	push_error(
		"OpenReactionWindowUseCase.open: chooser_port returned an illegal choice '%s' not in legal_reactions %s for window_type='%s' -- coercing to Pass"
		% [requested_choice, str(legal_reactions), window_type]
	)
	return ReactionChooserPortClass.PASS
