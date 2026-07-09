## core/application/render_combat_log_use_case.gd — RenderCombatLogUseCase
## (FEAT-008 / US-008 / FR-007, Iteration J-R2 Part D)
##
## Application layer (Clean Architecture): completes the design's internal
## AttackEvent-paired-with-ReactionResolvedEvent event contract (the "api"
## layer US-008 calls out — there is no external HTTP surface in this steel
## thread, see design notes' api_contracts §5) by deriving the single
## active-defense outcome (core/log/reaction_resolved_event.gd's
## ReactionResolvedEvent.outcome vocabulary — "none" | "dodge_succeeded" |
## "dodge_failed" | "parry_succeeded" | "parry_failed" | "block_reduced_by_n")
## from facts core/rules/resolution.gd (via resolve_to_hit_uc.gd /
## apply_on_hit_defense_uc.gd) ALREADY computed, then pushing the resulting
## ReactionResolvedEvent through an injected record_reaction Callable
## (presentation/event_log_view.gd's ICombatLogPort-equivalent
## record_reaction(reaction_event, correlated_attack_id) -> bool contract) so
## that view's render_attack_entry()/get_active_defense_outcome_string()
## renders the CORRECT 'Defense: <outcome>' segment.
##
## Before this use case existed, NOTHING in production code ever called
## event_log_view.gd's record_reaction() — FEAT-005/006/007 wired
## record_attack()/render_attack_entry()/overwrite_entry_as_rich() into both
## live Strike call sites (MainScene.gd's `_verb_bar_strike_execute()` and
## core/application/round_session.gd's `advance_ai_turn()`), but the paired
## reaction half of the storage-level relation was left entirely unwired, so
## every rich row's Defense segment silently fell back to
## get_active_defense_outcome_string()'s "no reaction recorded" default
## ("none") regardless of what a defender actually chose. This use case (and
## the two live call sites that now invoke it — see this file's own doc on
## each, plus core/application/round_session.gd's advance_ai_turn() and
## MainScene.gd's _verb_bar_strike_execute()) closes that gap.
##
## This use case performs NO dice rolling, NO damage math, and never touches
## core/rules/resolution.gd directly — it only reformats already-resolved
## choice/success/reduced_by facts (computed by the SAME call sites that
## already drive record_attack()/render_attack_entry()) into the
## storage-shaped core/log/reaction_resolved_event.gd value object. Depends
## ONLY on that domain-adjacent value object plus an injected, duck-typed
## Callable (ADR-002's Dependency-Inversion seam, mirroring
## core/application/round_session.gd's `_event_log_record_attack_fn` /
## `_event_log_render_attack_entry_fn` Callables) — never a concrete
## Presentation/Infrastructure reference. Domain purity boundary (ADR-001):
## extends RefCounted only — no Node/Control/SceneTree inheritance, no
## engine I/O.
class_name RenderCombatLogUseCase
extends RefCounted

const ReactionResolvedEventClass = preload("res://core/log/reaction_resolved_event.gd")

## Window ids — mirrors core/application/reaction_window.gd's / core/
## application/round_session.gd's already-established "PreHitAvoidance"
## (Dodge/Steel, asked BEFORE the attack roll) and "OnHitMitigation"
## (Parry/Block, asked AFTER the hit result is known) trigger_type vocabulary
## — never a third, invented window name.
const WINDOW_PRE_HIT_AVOIDANCE: String = "PreHitAvoidance"
const WINDOW_ON_HIT_MITIGATION: String = "OnHitMitigation"

## _OUTCOME_PREFIX_FOR_CHOICE — maps an active-defense choice ("dodge" /
## "steel" / "parry") to the outcome-string prefix _derive_outcome() appends
## "_succeeded"/"_failed" to below. Mirrors presentation/event_log_view.gd's
## own _OUTCOME_DISPLAY vocabulary: only "dodge"/"parry" have a distinct
## display mapping there — "steel" reuses "dodge"'s prefix since the design's
## data_model ReactionOutcome enum has no separate STEEL member (and no
## story in this iteration exercises it), but a Steel choice is still
## recorded faithfully rather than silently dropped. "block" is deliberately
## absent here — Block's outcome is never a succeeded/failed binary (see
## _derive_outcome()'s doc).
const _OUTCOME_PREFIX_FOR_CHOICE: Dictionary = {
	"dodge": "dodge",
	"steel": "dodge",
	"parry": "parry",
}


## record_reaction_outcome(attack_event_id, window_id, choice, resolved_by,
##                          success, reduced_by, record_reaction_fn) ->
##                          ReactionResolvedEvent — builds a
## core/log/reaction_resolved_event.gd ReactionResolvedEvent from
## already-resolved facts and pushes it through `record_reaction_fn`
## (presentation/event_log_view.gd's record_reaction(), when injected) so it
## is paired to `attack_event_id`/`window_id` for
## get_active_defense_outcome_string()/render_attack_entry() to read back.
## Always returns the constructed ReactionResolvedEvent (even when
## `record_reaction_fn` is left unbound), so a caller/test may inspect the
## derived outcome directly without needing a wired event_log_view.
##
## attack_event_id    — the correlated AttackEvent's id (record_attack()'s
##                       own key — see core/log/attack_event.gd).
## window_id           — "PreHitAvoidance" | "OnHitMitigation" (which window
##                       this reaction was resolved through).
## choice              — "none" | "dodge" | "steel" | "parry" | "block" —
##                       the reactor's ACTUAL choice, already resolved by the
##                       caller (never re-derived here).
## resolved_by         — "human" | "ai" | "auto" (who made the choice).
## success             — bool, consulted ONLY for "dodge"/"steel"/"parry":
##                       true iff the reaction FULLY prevented damage (the
##                       attack missed after Dodge/Steel — core/rules/
##                       resolution.gd's resolve_to_hit() `not hit` result —
##                       or Parry's opposed roll strictly exceeded the
##                       attacker's — apply_on_hit_defense()'s
##                       `on_hit_suppressed`). Ignored for "none"/"block"
##                       (Block's outcome is never success/fail — see
##                       _derive_outcome()'s doc).
## reduced_by          — int, consulted ONLY for "block": the actual
##                       damage-reduction amount (damage_raw - damage_final,
##                       already computed by core/rules/resolution.gd's
##                       apply_on_hit_defense() — never re-derived here).
## record_reaction_fn  — OPTIONAL Callable satisfying
##                       presentation/event_log_view.gd's
##                       record_reaction(reaction_event, correlated_attack_id)
##                       -> bool contract. A no-op (the built event is still
##                       returned, just never recorded) when left unbound —
##                       every pre-existing caller/test double that never
##                       wires one (NFR-004 default-safety, mirrors every
##                       other Callable seam this codebase already
##                       established).
func record_reaction_outcome(
	attack_event_id,
	window_id: String,
	choice: String,
	resolved_by: String,
	success: bool,
	reduced_by: int,
	record_reaction_fn: Callable = Callable()
):
	var outcome: String = _derive_outcome(choice, success)
	var reaction_event_id: String = "%s-%s" % [str(attack_event_id), window_id]

	var reaction_event = ReactionResolvedEventClass.new(
		reaction_event_id,
		attack_event_id,
		window_id,
		choice,
		resolved_by,
		outcome,
		reduced_by if outcome == "block_reduced_by_n" else null
	)

	if record_reaction_fn.is_valid():
		record_reaction_fn.call(reaction_event, attack_event_id)

	return reaction_event


## _derive_outcome(choice, success) -> String — the SOLE place this feature
## maps a resolved choice + already-computed success flag onto
## core/log/reaction_resolved_event.gd's outcome vocabulary. Pure,
## side-effect-free, never rolls dice/mutates anything:
##   "none"            -> "none"
##   "block"           -> "block_reduced_by_n" (Block always reduces SOME
##                        amount, possibly 0 — it is never a binary
##                        succeeded/failed outcome, per core/rules/
##                        resolution.gd's apply_on_hit_defense() Block branch,
##                        which unconditionally sets active_defense_applied
##                        once attempted).
##   "dodge" / "steel" -> "dodge_succeeded" | "dodge_failed"
##   "parry"           -> "parry_succeeded" | "parry_failed"
##   anything else     -> "none" (defensive — an unrecognized choice is
##                        never fabricated into a bogus outcome string).
func _derive_outcome(choice: String, success: bool) -> String:
	if choice == "block":
		return "block_reduced_by_n"
	if _OUTCOME_PREFIX_FOR_CHOICE.has(choice):
		var prefix: String = _OUTCOME_PREFIX_FOR_CHOICE[choice]
		return "%s_succeeded" % prefix if success else "%s_failed" % prefix
	return "none"
