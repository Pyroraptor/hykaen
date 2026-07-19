extends "res://presentation/action_controller.gd"

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

func _init(deps: Dictionary) -> void:
	super(deps)


## availability() -> bool — stub, fail-closed. Real gating (Stamina >= 1, not
## Dazed, >= 2 combinable actions this turn) is wired in a later feature.
func availability() -> bool:
	return false


## enter_selection() -> Dictionary — stub, empty selection. The real
## sub-action queue selection UI (choosing the ordered pair/N-tuple of verbs
## to fuse) is wired in a later feature.
func enter_selection() -> Dictionary:
	return {}


## execute(selection) -> Dictionary — FEAT-002 (US-002; FR-001): wires the
## live Stamina decrement. This is still a STUBBED execute() -- no
## Dazed/Repeat/Stamina>=1 validation and no sub-action queue orchestration
## yet (those are later Iteration N features layered on top, without
## changing this seam) -- but the Stamina spend itself is real: on a live
## actor, Combine drains exactly one Stamina through
## Combatant.spend_stamina(), the SAME single mutator every later
## validation feature reads/writes through, so there is exactly one
## Stamina-consuming code path for a Combine execute() call, never a
## second/duplicate one. Fails safe (ok=false, no mutation) when there is
## no live actor, mirroring the FEAT-001 stub's no-crash contract.
func execute(_selection = null) -> Dictionary:
	var actor = current_actor_entity()
	if actor == null:
		return {"ok": false}
	actor.spend_stamina()
	return {"ok": true}
