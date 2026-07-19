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
##
## FEAT-279 (US-014; FR-016, ADR-005) wires the REACTION-PROVOKING half of
## the CAST_SPELL execute() branch design notes' api_contracts #1 always
## promised ("fires ReactionWindowPort (Concentrate trait)") but FEAT-005/
## FEAT-006 never actually drove: once EITHER the first-cast
## (BeginCastUseCase) OR the continuing-cast (ContinueCastUseCase) branch
## below reports success, `_provoke_reaction_on_cast()` hands `actor` to
## core/application/use_cases/provoke_reaction_on_cast_use_case.gd's
## ProvokeReactionOnCastUseCase -- the SAME shared `reaction`
## ReactionController collaborator (presentation/reaction_controller.gd)
## presentation/stride_action_controller.gd's own execute() already reads
## out of this controller's identical `deps` dict (MainScene.gd's ONE
## memoized `_verb_deps()` Dictionary already carries every key this needs --
## "reaction"/"action_economy_for"/"current_round_number"/
## "resolve_action_use_case"/"living_enemy_reactors"/"current_turn_order" --
## so no composition-root change is required for this feature at all), so
## Cast-a-Spell opens the identical OpportunisticStrike window a Stride
## opens, with the caster's own current position standing in for a
## stationary "mover" (ADR-005: "no new reaction infrastructure" -- see that
## use case's own file-level doc). The provoked outcome is attached to this
## controller's own ExecuteResult under the additive "reaction_result" key --
## every pre-existing key (success/casting_state/error) is byte-for-byte
## unchanged, so no FEAT-005/FEAT-006/FEAT-008 caller/test regresses.
## FEAT-279 fired the window and reported what happened, but never ACTED on
## a lethal outcome — CancelCastUseCase remained a separate, later
## feature's scope.
##
## FEAT-280 (US-015; FR-017) closes that gap: `_maybe_cancel_cast()`
## (this feature's new helper) inspects the SAME `reaction_result`
## Dictionary `_provoke_reaction_on_cast()` already returns and, whenever it
## reports `stride_should_commit == false` (a lethal Opportunistic Strike
## fired mid-action — mirrors iteration K FEAT-238's lethal-OS-cancels-
## Stride "mover_downed" -> "stride_should_commit: false" contract,
## presentation/stride_action_controller.gd's own cancel branch), hands
## `actor` to core/application/use_cases/cancel_cast_use_case.gd's
## CancelCastUseCase -- clearing casting_state WITHOUT refunding
## committed_energy (ADR-003). This runs on BOTH the first-cast
## (BeginCastUseCase) and continuing-cast (ContinueCastUseCase) branches
## below, immediately after `_provoke_reaction_on_cast()` returns and
## BEFORE `_maybe_resolve_cast()` is ever consulted -- so a cancelled cast
## (actor.is_casting() == false) always fails `_maybe_resolve_cast()`'s own
## `actor.is_casting()` gate identically to any other already-cleared
## casting_state, guaranteeing ResolveSpellController/ResolveCastUseCase is
## NEVER reached for a cancelled cast (no spell resolves, no effect is ever
## applied) -- the mutual-exclusion invariant design notes' error_handling
## section requires ("a cast either resolves exactly once or is cancelled
## exactly once, never both").

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")
const BeginCastUseCaseClass = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const ContinueCastUseCaseClass = preload("res://core/application/use_cases/continue_cast_use_case.gd")
const RoundEnergyPoolPortClass = preload("res://core/application/ports/round_energy_pool_port.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const ResolveSpellControllerClass = preload("res://presentation/verbs/resolve_spell_controller.gd")
const ProvokeReactionOnCastUseCaseClass = preload("res://core/application/use_cases/provoke_reaction_on_cast_use_case.gd")
const CancelCastUseCaseClass = preload("res://core/application/use_cases/cancel_cast_use_case.gd")
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

## FEAT-279 (US-014): the shared reaction-provoking collaborators, read
## verbatim out of MainScene.gd's ONE memoized `_verb_deps()` Dictionary --
## mirrors presentation/stride_action_controller.gd's own `_init()`
## identically-keyed reads exactly (see that file's own doc), so no
## composition-root change is required to wire this feature.
var _reaction
var _action_economy_fn: Callable
var _round_number_fn: Callable
var _resolve_action_use_case
var _living_enemy_reactors_fn: Callable
var _turn_order_fn: Callable


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
	_reaction = deps.get("reaction", null)
	_action_economy_fn = deps.get("action_economy_for", Callable())
	_round_number_fn = deps.get("current_round_number", Callable())
	_resolve_action_use_case = deps.get("resolve_action_use_case", null)
	_living_enemy_reactors_fn = deps.get("living_enemy_reactors", Callable())
	_turn_order_fn = deps.get("current_turn_order", Callable())
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
		if continue_result.get("success", false):
			var continue_reaction_result: Dictionary = await _provoke_reaction_on_cast(actor)
			continue_result["reaction_result"] = continue_reaction_result
			continue_result = _maybe_cancel_cast(actor, continue_result, continue_reaction_result)
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
	if begin_result.get("success", false):
		var begin_reaction_result: Dictionary = await _provoke_reaction_on_cast(actor)
		begin_result["reaction_result"] = begin_reaction_result
		begin_result = _maybe_cancel_cast(actor, begin_result, begin_reaction_result)
	return _maybe_resolve_cast(actor, begin_result)


## _provoke_reaction_on_cast(actor) -> Dictionary — FEAT-279 (US-014; FR-016,
## ADR-005): fires the SAME OpportunisticStrike reaction window a player
## Stride opens (presentation/stride_action_controller.gd's own execute(),
## byte-for-byte-mirrored Callable wiring below) for `actor`'s Cast-a-Spell
## action -- a Concentrate-trait action, per this feature's design notes --
## via core/application/use_cases/provoke_reaction_on_cast_use_case.gd's
## ProvokeReactionOnCastUseCase. `actor` never relocates while casting, so
## the candidate reactor pool is every living enemy (mirrors
## StrideActionController's own player-mover `_living_enemy_reactors_fn`
## convention exactly -- only party members cast spells in this codebase's
## current scope), ordered by initiative and reaction-asserted the SAME way.
## Degrades safely to a no-op outcome (see the use case's own file-level
## doc) whenever `_reaction` is unwired (e.g. tests/unit/
## test_spell_action_controller_skeleton.gd's minimal deps dict, which
## predates this feature) -- never a crash.
func _provoke_reaction_on_cast(actor) -> Dictionary:
	if _reaction == null:
		return {"reactions": [], "mover_downed": false, "stride_should_commit": true}

	var living_reactors: Array = _living_enemy_reactors_fn.call() if _living_enemy_reactors_fn.is_valid() else []
	var candidate_reactors: Array = _reaction.order_candidate_reactors_by_initiative(living_reactors)
	if _turn_order_fn.is_valid():
		var turn_order = _turn_order_fn.call()
		if turn_order != null:
			_reaction.assert_candidate_reactors_ordering(candidate_reactors, turn_order)

	var use_case := ProvokeReactionOnCastUseCaseClass.new()
	return await use_case.execute(
		actor, candidate_reactors,
		Callable(_reaction, "is_reactor_reaction_spent"),
		Callable(_reaction, "resolve_enemy_opportunistic_strike_reaction"),
		_resolve_action_use_case,
		_action_economy_fn,
		_round_number_fn.call() if _round_number_fn.is_valid() else 0,
		0
	)


## _maybe_cancel_cast(actor, result, reaction_result) -> Dictionary —
## FEAT-280 (US-015; FR-017): the lethal-Opportunistic-Strike-cancels-cast
## branch, mirroring presentation/stride_action_controller.gd's own
## `execute()` "stride_should_commit" check (iteration K FEAT-238's
## lethal-OS-cancels-Stride machinery). `reaction_result` is whatever
## `_provoke_reaction_on_cast()` just returned for THIS action
## (ProvokeReactionOnCastUseCase's own Dictionary shape, forwarding
## ResolveStrideUseCase's `mover_downed`/`stride_should_commit` fields
## verbatim).
##
## When `stride_should_commit` is true (the common case -- no reactor chose
## Opportunistic Strike, or none of the resolved strikes were lethal),
## `result` is returned UNCHANGED. Only when it is false AND `actor` is
## STILL mid-cast (defensive -- a lethal strike should always leave the
## actor mid-cast at this point, since the Begin/ContinueCastUseCase
## success branch immediately above always set casting_state) does this
## method delegate to core/application/use_cases/cancel_cast_use_case.gd's
## CancelCastUseCase.execute(actor) -- clearing casting_state WITHOUT
## refunding committed_energy (ADR-003) -- and overwrites `result`'s
## "casting_state"/"error" keys (ERR_CAST_CANCELLED) to reflect the
## cancellation. Every OTHER key `result` already carries (e.g. "success",
## still true -- the Begin/ContinueCastUseCase action itself DID succeed;
## only the cast that action started/continued was subsequently cancelled)
## is left byte-for-byte untouched.
##
## `_maybe_resolve_cast()` (called immediately after this method,
## unmodified) naturally never resolves the cast once `actor.is_casting()`
## is false, so no spell ever resolves and no effect is ever applied on
## this path -- the mutual-exclusion invariant design notes'
## error_handling section requires.
func _maybe_cancel_cast(actor, result: Dictionary, reaction_result: Dictionary) -> Dictionary:
	if reaction_result.get("stride_should_commit", true):
		return result
	if actor == null or not actor.is_casting():
		return result

	var cancel_result: Dictionary = CancelCastUseCaseClass.new().execute(actor)
	result["casting_state"] = cancel_result.get("casting_state", null)
	result["error"] = ErrorCodeClass.ERR_CAST_CANCELLED
	return result


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
