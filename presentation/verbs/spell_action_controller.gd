extends "res://presentation/action_controller.gd"

## presentation/verbs/spell_action_controller.gd — SpellActionController
## (FEAT-004 / US-004, FEAT-005 / US-005; FR-003, FR-004)
##
## Concrete ActionController subclass (presentation/action_controller.gd) —
## the CAST_SPELL verb's composition-root wiring point, registered into
## MainScene.VERB_TABLE by FEAT-004 (the data-driven verb-table convention
## every prior verb, e.g. presentation/stride_action_controller.gd, already
## follows: "adding a verb is ~one entry [in VERB_TABLE] + its controller
## file + the three thin _verb_bar_<verb>_* shims").
##
## FEAT-004 landed ONLY the registration + a skeleton three-step verb
## contract (deliberately inert, matching action_controller.gd's own
## "un-overridden defaults fail safe rather than crash" convention).
##
## FEAT-005 wired the FIRST-CAST half of the real pipeline:
## core/application/use_cases/begin_cast_use_case.gd's BeginCastUseCase, run
## against core/application/ports/round_energy_pool_port.gd's
## RoundEnergyPoolPort (a SessionEnergyPoolAdapter this controller builds
## itself from the live RoundSession -- see `_round_energy_pool_port()`
## below, since MainScene.gd's `_verb_deps()` composition-root dict is NOT
## modified by this feature) and core/application/ports/spell_catalog_port.gd's
## SpellCatalogPort (defaulting to the ALREADY-EXISTING core/adapters/
## resource_spell_catalog_adapter.gd ResourceSpellCatalogAdapter, unless a
## caller injects `deps["spell_catalog_port"]`, e.g. a test double).
##
## FEAT-006 (US-006, FR-005) wires the SUBSEQUENT-ACTION half:
## an already-mid-cast actor's execute() call now delegates to
## core/application/use_cases/continue_cast_use_case.gd's
## ContinueCastUseCase instead of falling through to the FEAT-004 inert
## stub -- no re-selection (enter_selection() already returns {} for this
## branch, unchanged since FEAT-005), no re-payment of energy (no
## RoundEnergyPoolPort/SpellCatalogPort collaborator is even constructed on
## this path), just decrement casting_state.remaining_actions and spend the
## turn's action. ResolveCastUseCase/CancelCastUseCase (resolving/cancelling
## a cast once remaining_actions hits 0, or a lethal Opportunistic Strike)
## remain OUT of FEAT-006's scope -- ContinueCastUseCase only ever
## decrements and stops.
##
## FEAT-008 (this feature; US-008, FR-007, ADR-007) wires the RESOLUTION
## TRIGGER: after EITHER the first-cast (BeginCastUseCase) OR the
## continuing-cast (ContinueCastUseCase) branch below runs,
## `_maybe_resolve_cast()` checks whether that call just drove
## `actor.casting_state.remaining_actions` to exactly 0 -- a 1-action spell
## (e.g. Channel) can reach 0 on the FIRST cast, not just a later
## continuation -- and, ONLY then, hands `actor` to
## presentation/verbs/resolve_spell_controller.gd's ResolveSpellController
## (this feature's other new file), which drives the TargetingPort
## integration (target selection, range-filtered) under its own strict
## remaining_actions==0 gate. See that file's own doc for the full contract
## and for what remains OUT of this feature's scope (the rest of
## ResolveCastUseCase -- attack resolution, effect application, combat log,
## casting_state cleanup). The resolve outcome is attached to this
## controller's own ExecuteResult under the additive "resolve_spell_result"
## key -- every pre-existing key (success/casting_state/error) is
## byte-for-byte unchanged, so no FEAT-005/FEAT-006 caller/test regresses.
##
## Fail-safe degrade (mirrors this project's established "unwired
## collaborator -> safe fallback" convention, e.g. core/application/
## round_session.gd's Callable seams): whenever the live session does not
## (yet) expose `get_energy_pool()` -- e.g. tests/unit/
## test_spell_action_controller_skeleton.gd's minimal FakeSession double,
## which predates this feature and exercises the controller in isolation --
## availability()/execute() degrade to their FEAT-004 skeleton behavior
## rather than crashing on a missing method.

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")
const BeginCastUseCaseClass = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const ContinueCastUseCaseClass = preload("res://core/application/use_cases/continue_cast_use_case.gd")
const RoundEnergyPoolPortClass = preload("res://core/application/ports/round_energy_pool_port.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const CastingStateClass = preload("res://core/domain/casting_state.gd")

## _spell_catalog_port — FEAT-005: the SpellCatalogPort collaborator every
## availability()/execute() call resolves a spell_id through. Reads
## `deps["spell_catalog_port"]` (a test double may inject a fake here);
## defaults to a fresh ResourceSpellCatalogAdapter (the real, production
## adapter, loading res://data/spells/*.tres) when the key is absent --
## so a REAL, booted MainScene needs no additional composition-root wiring
## for this feature to work end-to-end (MainScene.gd's `_verb_deps()` dict
## itself is not modified by this feature).
var _spell_catalog_port

## _resolve_spell_controller — FEAT-008: the ResolveSpellController this
## controller hands `actor` to once a cast reaches remaining_actions == 0
## (see file-level doc). Built from `deps["resolve_spell_controller"]` when
## a caller/test injects one (e.g. a spy verifying the wiring itself);
## otherwise a fresh one is constructed here from
## `deps["targeting_port"]`/`deps["targeting_candidates_fn"]` (both default
## to ResolveSpellController's own safe-degrade defaults -- no live
## TargetingPort/candidate-source composition-root wiring exists yet at
## this feature's state, MainScene.gd is NOT modified by this feature) and
## this same `_spell_catalog_port`, mirroring `_round_energy_pool_port()`'s
## identical "build the real collaborator here, degrade safely when unwired"
## convention.
var _resolve_spell_controller

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
	_spell_catalog_port = deps.get("spell_catalog_port", ResourceSpellCatalogAdapterClass.new())
	_resolve_spell_controller = deps.get("resolve_spell_controller", ResolveSpellControllerClass.new({
		"spell_catalog_port": _spell_catalog_port,
		"targeting_port": deps.get("targeting_port", null),
		"candidates_fn": deps.get("targeting_candidates_fn", Callable()),
	}))


## _round_energy_pool_port(actor) -> RoundEnergyPoolPort or null — FEAT-005:
## builds a fresh SessionEnergyPoolAdapter bound to the LIVE session +
## `actor`, or null when the live session does not (yet) expose
## get_energy_pool() -- see file-level "fail-safe degrade" doc. Built fresh
## per call (cheap, stateless wrapper) rather than cached, since the live
## session itself may change across a controller's lifetime (mirrors
## action_controller.gd's own `_session()` re-fetching every call).
func _round_energy_pool_port(actor):
	var session = _session()
	if session == null or not session.has_method("get_energy_pool"):
		return null
	return RoundEnergyPoolPortClass.SessionEnergyPoolAdapter.new(session, actor)


## availability() -> bool — US-004 contract #1, completed by FEAT-005:
## delegates to BeginCastUseCase.availability() -- true when the live actor
## is already mid-cast (is_casting(), the "continue casting" path) OR knows
## at least one spell AFFORDABLE against the round energy pool's current
## balance. Degrades to the FEAT-004 skeleton predicate (known_spell_ids
## non-empty) when the live session cannot yet supply a RoundEnergyPoolPort
## (see file-level doc) -- every pre-existing test/caller that never wires a
## real session-backed pool keeps its FEAT-004 behavior unchanged. No live
## session/actor (current_actor_entity() == null) still fails safe to false.
func availability() -> bool:
	var actor = current_actor_entity()
	if actor == null:
		return false
	if actor.is_casting():
		return true
	if actor.known_spell_ids.is_empty():
		return false

	var pool_port = _round_energy_pool_port(actor)
	if pool_port == null:
		return true

	return BeginCastUseCaseClass.new().availability(actor, _spell_catalog_port, pool_port)


## enter_selection() -> Dictionary — US-004 contract #2 (skeleton half):
## returns an empty Dictionary (the base class's own "no selection" shape,
## action_controller.gd's default) when the actor is already mid-cast — the
## real contract's "If actor.is_casting(): returns null (skip selection,
## US-006)" — else a verb_id-tagged candidate-set Dictionary matching every
## other verb's enter_selection() shape (candidate_hexes/candidate_targets).
##
## FEAT-278 (US-013; FR-014): candidate_targets is now populated with the
## ENERGY-GATED pick list -- BeginCastUseCase.castable_spell_ids(), i.e.
## `actor`'s known_spell_ids filtered to those whose Spell.energy_cost is
## affordable against the round energy pool's current balance (e.g. an L1
## caster who knows Fireball, energy_cost=2, never sees "fireball" offered
## while the pool balance is < 2 -- see data/spells/fireball.tres). Degrades
## to the FEAT-004 skeleton behavior (candidate_targets == []) when the live
## session cannot yet supply a RoundEnergyPoolPort (see file-level "fail-safe
## degrade" doc) -- every pre-existing test/caller that never wires a real
## session-backed pool keeps its FEAT-004 behavior unchanged.
func enter_selection() -> Dictionary:
	var actor = current_actor_entity()
	if actor != null and actor.is_casting():
		return {}

	var candidate_targets: Array = []
	if actor != null:
		var pool_port = _round_energy_pool_port(actor)
		if pool_port != null:
			candidate_targets = BeginCastUseCaseClass.new().castable_spell_ids(actor, _spell_catalog_port, pool_port)

	return {"verb_id": "CAST_SPELL", "candidate_hexes": [], "candidate_targets": candidate_targets}


## execute(selection) -> Dictionary — US-004 contract #3, completed by
## FEAT-005 for the FIRST-CAST branch and FEAT-006 for the CONTINUING-CAST
## branch:
##   - actor already mid-cast (actor.is_casting()): delegates to
##     ContinueCastUseCase.execute() -- no re-selection, no re-payment of
##     energy, just decrement casting_state.remaining_actions and spend the
##     turn's action (US-006). `selection` is ignored on this branch --
##     enter_selection() already returned {} for it, so no caller should be
##     handing one in, but a stray value must not change this branch's
##     behavior either.
##   - actor NOT already mid-cast: delegates to BeginCastUseCase.execute()
##     -- reserving `selection`'s spell's energy up front via
##     RoundEnergyPoolPort, then initializing casting_state and spending
##     the turn action (see that use case's own doc for the full
##     ExecuteResult contract, including ERR_INSUFFICIENT_ENERGY /
##     ERR_NOT_CASTABLE).
##
## `selection` (first-cast branch only) is the ALREADY-PICKED spell_id (a
## String, mirroring every other verb's `selection` == the Layer-2-resolved
## pick, e.g. Strike's target_id) or a Dictionary carrying one under the
## "spell_id" key.
##
## Every "cannot yet determine a real answer" fallback (no live actor,
## no/empty selection on the first-cast branch, no session-backed
## RoundEnergyPoolPort available -- see file-level "fail-safe degrade" doc)
## returns the SAME FEAT-004 inert stub shape byte-for-byte --
## ResolveCastUseCase/CancelCastUseCase remain a separate, later feature's
## scope.
func execute(selection = null) -> Dictionary:
	var actor = current_actor_entity()
	if actor == null:
		return _inert_result()

	if actor.is_casting():
		var continue_result: Dictionary = ContinueCastUseCaseClass.new().execute(actor, current_action_economy())
		return _maybe_resolve_cast(actor, continue_result)

	var spell_id: String = _extract_spell_id(selection)
	if spell_id == "":
		return _inert_result()

	var pool_port = _round_energy_pool_port(actor)
	if pool_port == null:
		return _inert_result()

	var begin_result: Dictionary = BeginCastUseCaseClass.new().execute(
		actor, spell_id, _spell_catalog_port, pool_port, current_action_economy()
	)
	return _maybe_resolve_cast(actor, begin_result)


## _maybe_resolve_cast(actor, result) -> Dictionary — FEAT-008 (US-008;
## FR-007, ADR-007): the strict remaining_actions==0 gate. `result` (the
## Begin/ContinueCastUseCase ExecuteResult, UNCHANGED) is returned as-is
## except for an additive "resolve_spell_result" key, present ONLY when
## `actor` is still mid-cast (is_casting()) AND its CastingState's
## remaining_actions has reached exactly 0 -- a 1-action spell (e.g.
## Channel) can satisfy this gate on the FIRST cast, not only a later
## continuation, so this check runs after BOTH execute() branches above,
## never just the continuing-cast one. A cancelled/interrupted cast (empty
## casting_state, is_casting() == false -- e.g. a failed energy reservation,
## or a future lethal-Opportunistic-Strike CancelCastUseCase call) and a
## still-in-progress cast (remaining_actions > 0) both fail this gate
## identically, so ResolveSpellController.execute() -- and therefore
## TargetingPort -- is never reached for either case.
func _maybe_resolve_cast(actor, result: Dictionary) -> Dictionary:
	if actor != null and actor.is_casting():
		var state = CastingStateClass.from_dict(actor.casting_state)
		if state.remaining_actions == 0:
			result["resolve_spell_result"] = _resolve_spell_controller.execute(actor)
	return result


## _extract_spell_id(selection) -> String — accepts either the plain scalar
## shape (a spell_id String, mirroring every pre-existing verb's `selection`
## argument) or a Dictionary carrying one under "spell_id" (forward
## compatible with a future SelectionPort-driven OPTION_TARGET-style pick).
## Anything else (null, an unrelated type) yields "" -- treated by execute()
## exactly like "no selection at all".
func _extract_spell_id(selection) -> String:
	if selection is String:
		return selection
	if selection is Dictionary:
		return String(selection.get("spell_id", ""))
	return ""


## _inert_result() -> Dictionary — the FEAT-004 skeleton's deliberately-inert
## ExecuteResult shape (see that feature's own doc for why `error` is
## ErrorCode.NONE rather than a fabricated real failure code).
func _inert_result() -> Dictionary:
	return {"success": false, "casting_state": null, "error": ErrorCodeClass.NONE}
