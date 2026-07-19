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
## Scope of THIS feature only: entry-point plumbing. The three-method verb
## contract below is deliberately an INERT stub — fail-closed availability(),
## an empty enter_selection(), a no-op/not-ok execute() — mirroring
## presentation/action_controller.gd's own "fails safe rather than crashing"
## base defaults. Real gating (Stamina >= 1, not Dazed, >= 2 combinable
## actions this turn, via core/rules/action_economy.gd's existing
## combine_actions() validation) and the N-length sub-action queue
## orchestration are later Iteration N features, built ON TOP of this seam
## without changing it.

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


## execute(selection) -> Dictionary — stub, always reports failure with zero
## side effects. The real validate-then-orchestrate execution (queueing
## sub-actions resolved via `_controller(sub_id)`, charging exactly one
## action + one Stamina at the Combine level) is wired in a later feature.
func execute(_selection = null) -> Dictionary:
	return {"ok": false}
