extends "res://presentation/action_controller.gd"

## presentation/verbs/spell_action_controller.gd — SpellActionController
## (FEAT-004 / US-004; FR-003)
##
## Concrete ActionController subclass (presentation/action_controller.gd) —
## the CAST_SPELL verb's composition-root wiring point, registered into
## MainScene.VERB_TABLE by this same feature (the data-driven verb-table
## convention every prior verb, e.g. presentation/stride_action_controller.gd,
## already follows: "adding a verb is ~one entry [in VERB_TABLE] + its
## controller file + the three thin _verb_bar_<verb>_* shims").
##
## SCOPE (FEAT-004): this feature lands ONLY the registration + a skeleton
## three-step verb contract (availability()/enter_selection()/execute()) —
## deliberately inert, matching action_controller.gd's own "un-overridden
## defaults fail safe rather than crash" convention. The REAL casting
## pipeline (BeginCastUseCase/ContinueCastUseCase/ResolveCastUseCase/
## CancelCastUseCase, and the SelectionPort/RoundEnergyPoolPort/
## SpellCatalogPort/ReactionWindowPort ports they run against — see design
## notes' architecture section) lands with later features in this
## iteration; none of those use cases or ports exist as concrete
## collaborators yet, so this controller never calls into one.
##
## availability()/enter_selection() DO read the SAME live actor accessor
## every other verb controller reads (ActionController.current_actor_entity()),
## so the skeleton already reflects the real, booted Combatant's
## is_casting()/known_spell_ids state (FEAT-001/FEAT-002 groundwork) rather
## than an always-false placeholder — but neither checks the round energy
## pool balance half of design notes' API contract #1
## ("... AND round energy pool balance >= that spell's energy_cost"), since
## RoundEnergyPoolPort has no concrete adapter yet. Purely additive: CAST_SPELL
## is a brand-new verb_id no other code path depends on, so this cannot
## regress Strike/Step/Stride/End Turn.

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")

## _verb_deps() -> Array[String] — the closed list of application-layer PORTS
## (see design notes' architecture section: "declares `_verb_deps()`
## returning the ports it needs") this verb is contracted to eventually
## depend on, once BeginCastUseCase/ContinueCastUseCase land: SelectionPort
## (the spell/Layer-2 picker), RoundEnergyPoolPort (the up-front,
## non-refundable energy reservation, ADR-003), SpellCatalogPort (spell_id ->
## Spell lookup), and ReactionWindowPort (the Concentrate-trait reaction
## trigger, reusing the Stride Opportunistic Strike path). Declared `static`
## — this is a pure, instance-independent declaration of the contract (no
## `deps` dict is consulted), so a composition-root wiring check can call it
## without constructing a controller instance. Named/shaped to match
## action_controller.gd's `deps: Dictionary` constructor convention: each
## returned name documents which key this verb will eventually read out of
## that dict once the corresponding adapter exists.
static func _verb_deps() -> Array:
	return [
		"SelectionPort",
		"RoundEnergyPoolPort",
		"SpellCatalogPort",
		"ReactionWindowPort",
	]


func _init(deps: Dictionary) -> void:
	super(deps)


## availability() -> bool — US-004 contract #1 (skeleton half): true when the
## live actor is already mid-cast (is_casting(), the "continue casting" path)
## OR knows at least one spell (known_spell_ids is non-empty). Does NOT yet
## gate on round energy pool balance — see file-level doc. No live session/
## actor (current_actor_entity() == null) fails safe to false, exactly like
## every other verb's availability() when there is no current turn.
func availability() -> bool:
	var actor = current_actor_entity()
	if actor == null:
		return false
	if actor.is_casting():
		return true
	return actor.known_spell_ids.size() > 0


## enter_selection() -> Dictionary — US-004 contract #2 (skeleton half):
## returns an empty Dictionary (the base class's own "no selection" shape,
## action_controller.gd's default) when the actor is already mid-cast — the
## real contract's "If actor.is_casting(): returns null (skip selection,
## US-006)" — else a verb_id-tagged candidate-set Dictionary matching every
## other verb's enter_selection() shape (candidate_hexes/candidate_targets),
## here always empty since no SpellCatalogPort-backed spell list exists yet
## to populate candidate_targets with.
func enter_selection() -> Dictionary:
	var actor = current_actor_entity()
	if actor != null and actor.is_casting():
		return {}
	return {"verb_id": "CAST_SPELL", "candidate_hexes": [], "candidate_targets": []}


## execute(selection) -> Dictionary — US-004 contract #3 (skeleton half): the
## deliberately-inert stub. Matches the real contract's
## ExecuteResult{success, casting_state, error} shape so a caller can
## pattern-match on it exactly like the eventual BeginCastUseCase/
## ContinueCastUseCase-backed implementation will return, but never mutates
## casting_state, never spends the turn action, and never reserves energy —
## there is no use case wired in yet for it to delegate to. `error` is
## ErrorCode.NONE (not one of the closed enum's real failure codes): none of
## those codes describe "this verb is not implemented yet", and returning a
## real failure code here would be misleading (e.g. ERR_NOT_CASTABLE implies
## a genuine known-spell-list check ran, which it did not).
func execute(_selection = null) -> Dictionary:
	return {"success": false, "casting_state": null, "error": ErrorCodeClass.NONE}
