extends RefCounted

## presentation/verbs/resolve_spell_controller.gd — ResolveSpellController
## (FEAT-008 / US-008; FR-007, ADR-007)
##
## Adapter/presentation layer (Clean Architecture, ADR-001): the composition-
## root-facing driver of the "cast reaches resolution" step of the Cast-a-
## Spell steel thread (design notes' architecture section: "ResolveSpellController
## ... adapter that drives ResolveCastUseCase, wiring TargetingPort UI,
## ResolutionPort, EffectsApplierPort, CombatLogPort"). NOT a VerbController
## (does not extend presentation/action_controller.gd) — this controller is
## never registered in MainScene.VERB_TABLE directly; it is invoked FROM
## presentation/verbs/spell_action_controller.gd's SpellActionController once
## a Begin/ContinueCastUseCase call drives casting_state.remaining_actions to
## 0 (see that file's `_maybe_resolve_cast()`).
##
## SCOPE (FEAT-008): this feature implements ONLY the strict
## remaining_actions==0 gate + the TargetingPort integration (target
## SELECTION, range-filtered) — test_criteria:
##   1. TargetingPort is invoked ONLY when casting_state.remaining_actions
##      reaches 0.
##   2. out-of-range targets are excluded from the selectable set for Fire
##      Bolt (50ft).
##   3. a cancelled/interrupted casting_state never triggers targeting.
## The REMAINING half of design notes' ResolveCastUseCase (ResolutionPort's
## attack roll, EffectsApplierPort's DAMAGE/ADD_ENERGY application,
## CombatLogPort's CAST_RESOLVE emission, and clearing casting_state
## afterward) is explicitly OUT of this feature's scope — a later feature
## extends execute() below to drive those remaining steps once a target has
## been chosen. Until then, casting_state is left untouched by this
## controller (SpellActionController's own ExecuteResult contract — see
## tests/boot/test_continue_cast_firebolt.gd — still shows
## remaining_actions == 0 with casting_state still SET after this
## controller runs).
##
## Gate (api_contracts #2's precondition, ADR-007): TargetingPort is reached
## ONLY when `actor` is non-null, `actor.is_casting()` is true, AND
## core/domain/casting_state.gd's CastingState.remaining_actions == 0.
## A cancelled/interrupted cast (core/domain/combatant.gd's
## Combatant.cancel_cast() clears casting_state back to {}, so
## actor.is_casting() becomes false) therefore structurally can never reach
## targeting, regardless of what remaining_actions held immediately before
## cancellation — there is no separate "was this cancelled?" flag to check;
## an empty casting_state IS the cancelled/interrupted signal (mirrors
## core/domain/combatant.gd's own is_casting()/cancel_cast() doc: "Reserved
## for the Cast-a-Spell multi-turn casting state machine. Empty when not
## casting").
##
## Range enforcement (test_criteria #2; design notes' api_contracts #2:
## "ranged-only, out-of-range targets excluded from the pick set (never
## surfaced as selectable)"): candidates are filtered via
## core/geometry/hex_math.gd HexMath.hex_distance() against
## spell.range_ft converted to hexes at FEET_PER_HEX (1 hex = 5 ft, the
## project-wide convention — see core/model/weapon_resource.gd's own
## range_hexes doc and docs/hollow-world-v0-spec.org's "1 hex = 5 ft")
## BEFORE the filtered Array is ever handed to TargetingPort — see
## core/application/ports/targeting_port.gd's own "legal-set-in,
## single-pick-out" design-choice doc for why the PORT itself never sees an
## out-of-range candidate at all (mirrors
## presentation/strike_action_controller.gd's `_reachable_targets()` /
## core/application/ports/hex_choice_resolver_port.gd's identical
## established division of responsibility).
##
## A spell with range_ft <= 0 (self/no-target, e.g. Channel) never opens
## targeting at all — design notes' architecture section: "Channel, no
## targeting needed — target = self" — TargetingPort.request_single_target()
## is simply never called for such a spell.
##
## SCOPE (FEAT-277, this feature; US-012, FR-013): a self/no-target spell
## (range_ft <= 0) is no longer a dead end — `_maybe_resolve_self_cast()`
## now hands it to the SAME core/application/use_cases/resolve_cast_use_case.gd
## ResolveCastUseCase every attack-defense spell already drives (design
## notes: "Routes Channel through the identical SpellActionController/
## ResolveSpellController/ResolveCastUseCase path (no bespoke verb)"),
## ONLY when `spell.effect_type` is core/domain/effects/effect_kind.gd
## EffectKind.ADD_ENERGY — ResolutionPort is never reached for this branch
## (no attack roll exists for Channel), but ResolveCastUseCase still runs
## its CLEANUP + LOG steps and applies the ADD_ENERGY effect to the
## caster's own round energy pool via the newly-injected `energy_pool_fn`
## dep below.
##
## Every collaborator is injected via a `deps: Dictionary` (mirrors
## presentation/verbs/spell_action_controller.gd's own `deps` convention):
##   "spell_catalog_port"  — SpellCatalogPort (core/application/ports/
##                           spell_catalog_port.gd); defaults to a fresh
##                           ResourceSpellCatalogAdapter (the real,
##                           production adapter), mirroring
##                           SpellActionController's identical default.
##   "targeting_port"      — TargetingPort (core/application/ports/
##                           targeting_port.gd); defaults to null (no live
##                           UI/AI adapter wired yet at this feature's
##                           composition-root state — MainScene.gd is NOT
##                           modified by this feature) — degrades safely
##                           (see execute()'s own doc) rather than crashing,
##                           mirroring this codebase's established
##                           "unwired collaborator -> safe fallback"
##                           convention (e.g. SpellActionController's own
##                           `_round_energy_pool_port()` null-session
##                           degrade).
##   "candidates_fn"       — Callable () -> Array[Combatant]; the candidate
##                           target pool BEFORE range filtering (e.g. living
##                           enemies). Defaults to an invalid Callable, which
##                           degrades to an empty candidate Array — again,
##                           no live composition-root wiring exists for this
##                           yet (a future feature threads a real candidate
##                           source through, the same way
##                           presentation/strike_action_controller.gd's
##                           `living_enemies_fn` is threaded in by
##                           MainScene.gd's `_verb_deps()`).
##   "resolution_port"     — FEAT-009 (US-009; FR-008): ResolutionPort
##                           (core/application/ports/resolution_port.gd);
##                           defaults to null (a caller/test that never
##                           supplies one still degrades safely). When
##                           wired, drives ResolveCastUseCase (core/
##                           application/use_cases/resolve_cast_use_case.gd)
##                           once a target has been chosen — see execute()'s
##                           own doc for the exact gate. FEAT-283 (resolves
##                           PR-001): MainScene.gd's `_verb_deps()` now
##                           supplies its own real `spell_resolution_port`
##                           (a ResolutionRulesAdapter wrapping the
##                           composition root's shared RandomPort) under
##                           this key, forwarded here by
##                           spell_action_controller.gd's SpellActionController
##                           -- a REAL booted MainScene needs no test-only
##                           override to resolve this port anymore.
##   "combat_log_port"     — FEAT-276 (US-011; FR-010): CombatLogPort
##                           (core/application/ports/combat_log_port.gd);
##                           defaults to null, mirroring "resolution_port"'s
##                           identical "unwired collaborator -> safe
##                           fallback" convention. Forwarded UNMODIFIED to
##                           ResolveCastUseCase.execute() (see that use
##                           case's own FEAT-276 doc for the CLEANUP/LOG
##                           steps it drives once wired). FEAT-283: same
##                           real-wiring precedent as "resolution_port"
##                           above — MainScene.gd's `_verb_deps()` now
##                           supplies its real `spell_combat_log_port`
##                           (a CombatLogPanelAdapter) under this key.
##   "energy_pool_fn"      — FEAT-277 (US-012; FR-013): Callable(caster) ->
##                           EnergyPool (core/domain/energy_pool.gd); defaults
##                           to an invalid Callable(), mirroring
##                           "candidates_fn"'s identical "unwired collaborator
##                           -> safe fallback" convention. Forwarded
##                           UNMODIFIED to ResolveCastUseCase.execute() --
##                           consulted ONLY for a self-cast ADD_ENERGY spell
##                           (e.g. Channel), see `_maybe_resolve_self_cast()`'s
##                           own doc. FEAT-283: same real-wiring precedent as
##                           "resolution_port"/"combat_log_port" above —
##                           MainScene.gd's `_verb_deps()` now supplies a
##                           real Callable bound to its own
##                           `_energy_pool_for()`, reading the LIVE
##                           RoundSession's energy pool for the given caster.
##
## FEAT-009 (US-008; FR-011, ADR-005): after ANY successful resolve above
## (self-cast, pre-chosen-target, or live-TargetingPort), `_maybe_discharge_item()`
## discharges the equipped item that PREPARED the resolved spell (if any) —
## see that method's own doc for the exact "energy_cost > 0 AND
## resolve_cast_result.success" gate and its no-throw-on-no-match
## contract. This is the exit-point half of the item-implement steel
## thread AA-3-2 (BeginCastUseCase's FEAT-007 charge-state guard is the
## entry-point half): `orb_gram.is_charged` flips true -> false the
## instant Frost Breath resolves, so a subsequent `castable_spell_ids()`
## call no longer offers "frost_breath" (mitigates RISK-001).
##
## Usage:
##   var controller := ResolveSpellController.new({
##       "spell_catalog_port": catalog, "targeting_port": targeting,
##       "candidates_fn": func(): return [skeleton, goblin],
##       "resolution_port": resolution_port,
##   })
##   var result := controller.execute(marigold)  # {"success", "target_id", "error", "resolve_cast_result"?}

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")
const CastingStateClass = preload("res://core/domain/casting_state.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const HexMathClass = preload("res://core/geometry/hex_math.gd")
const SpellClass = preload("res://core/domain/spell.gd")
const ResolveCastUseCaseClass = preload("res://core/application/use_cases/resolve_cast_use_case.gd")
const SelectionResolutionUseCaseClass = preload("res://core/application/selection_resolution_use_case.gd")

## 1 hex == 5 ft — the project-wide convention (docs/hollow-world-v0-spec.org,
## core/model/weapon_resource.gd's range_hexes doc). Spell range is authored
## in feet (core/domain/spell.gd's Spell.range_ft); this is the SOLE place
## that conversion happens for spell targeting, mirroring
## presentation/strike_action_controller.gd's own weapon range_hexes usage
## (weapons are already authored directly in hexes, so no such conversion
## exists there — spells are the first range_ft-authored source this
## codebase range-gates by hex distance).
const FEET_PER_HEX: int = 5

var _spell_catalog_port
var _targeting_port
var _candidates_fn: Callable
var _resolution_port
var _combat_log_port
var _energy_pool_fn: Callable
var _combatant_roster_fn: Callable
var _resolve_cast_use_case := ResolveCastUseCaseClass.new()
var _selection_resolution_use_case := SelectionResolutionUseCaseClass.new()


func _init(deps: Dictionary = {}) -> void:
	_spell_catalog_port = deps.get("spell_catalog_port", ResourceSpellCatalogAdapterClass.new())
	_targeting_port = deps.get("targeting_port", null)
	_candidates_fn = deps.get("candidates_fn", Callable())
	_resolution_port = deps.get("resolution_port", null)
	_combat_log_port = deps.get("combat_log_port", null)
	_energy_pool_fn = deps.get("energy_pool_fn", Callable())
	# FEAT-006 (US-005; FR-004, ADR-004): the FULL live combatant roster (every
	# combatant in the encounter -- caster, allies, AND enemies; unlike
	# "candidates_fn" above, which is scoped to the enemy-only pool the
	# SCALAR/single-target flow range-filters), consulted ONLY by the AoE
	# branch below (`_maybe_resolve_aoe_cast()`). Defaults to an invalid
	# Callable, mirroring every other "unwired collaborator -> safe fallback"
	# dep on this class -- no live composition-root wiring exists for this yet
	# (a future feature threads MainScene.gd's real `_party + _enemies` roster
	# through, the same way `candidates_fn` is threaded in today).
	_combatant_roster_fn = deps.get("combatant_roster_fn", Callable())


## execute(actor) -> Dictionary{success, target_id, target, error,
## resolve_cast_result?} — api_contracts #2's TARGETING step (see
## file-level SCOPE doc for what remains out of scope), PLUS FEAT-009's
## (US-009; FR-008) RESOLUTION step layered on top: once a non-null
## `target` has been chosen AND `spell.defense` is an actual attack defense
## (i.e. not Spell.Defense.NONE — a self/no-attack spell like Channel never
## reaches this step, see `_maybe_resolve_attack()`'s own doc) AND a
## ResolutionPort is wired (`deps["resolution_port"]`), this method drives
## core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase
## against that single target, attaching its Dictionary result under the
## ADDITIVE "resolve_cast_result" key — every pre-existing key (success/
## target_id/target/error) is byte-for-byte unchanged, so no FEAT-008
## caller/test regresses. Every "not yet time to resolve" case (null actor,
## not casting, remaining_actions != 0) returns `_skip_result()` WITHOUT
## ever invoking TargetingPort OR ResolutionPort — the gate test_criteria
## #1/#3 assert against.
func execute(actor, round_number: int = 0, pre_chosen_target_id: String = "", aoe_origin_hex = null) -> Dictionary:
	if not _should_resolve(actor):
		return _skip_result()

	var state = CastingStateClass.from_dict(actor.casting_state)
	var spell = _spell_catalog_port.get_spell(state.spell_id) if _spell_catalog_port != null else null
	if spell == null:
		# Defensive/should-be-unreachable (a known_spell_ids entry that no
		# longer resolves through the catalog) — mirrors
		# ContinueCastUseCase's own ERR_INVALID_STATE fail-safe convention.
		return _fail(ErrorCodeClass.ERR_INVALID_STATE)

	if (spell.is_area_effect() or spell.is_cone()) and aoe_origin_hex != null:
		# FEAT-006 (US-005; FR-004, ADR-004): the AoE branch -- see
		# `_maybe_resolve_aoe_cast()`'s own doc. Gated on BOTH
		# is_area_effect() (never reached by a single-target spell like Fire
		# Bolt, even if a caller mistakenly supplies `aoe_origin_hex` --
		# test_criteria #5's regression guard) AND a non-null
		# `aoe_origin_hex` (an area-effect spell invoked the pre-FEAT-006 way,
		# with no origin yet resolved, falls through to the unchanged
		# single-target flow below rather than crashing).
		return _maybe_resolve_aoe_cast(actor, spell, aoe_origin_hex, round_number)

	if spell.range_ft <= 0:
		# Self/no-target spell (e.g. Channel) — never opens targeting at all
		# (file-level doc). `target_id` is the caster's own id.
		var self_cast_result := {"success": true, "target_id": actor.display_id(), "target": actor, "error": ErrorCodeClass.NONE}
		var resolve_cast_result = _maybe_resolve_self_cast(actor, spell, round_number)
		if resolve_cast_result != null:
			self_cast_result["resolve_cast_result"] = resolve_cast_result
		_maybe_discharge_item(actor, spell, resolve_cast_result)
		return self_cast_result

	var legal_targets: Array = _in_range_candidates(actor, spell.range_ft)

	# When a target was pre-chosen via the overlay (enter_selection() returned
	# candidate_targets, player clicked an enemy), look it up in legal_targets
	# and resolve without calling the targeting port (synchronous path).
	if pre_chosen_target_id != "":
		var pre_target = null
		for t in legal_targets:
			if t.display_id() == pre_chosen_target_id:
				pre_target = t
				break
		if pre_target == null and not legal_targets.is_empty():
			pre_target = legal_targets[0]
		if pre_target != null:
			var pre_result := {"success": true, "target_id": pre_target.display_id(), "target": pre_target, "error": ErrorCodeClass.NONE}
			var resolve_cast_result = _maybe_resolve_attack(actor, spell, pre_target, round_number)
			if resolve_cast_result != null:
				pre_result["resolve_cast_result"] = resolve_cast_result
			_maybe_discharge_item(actor, spell, resolve_cast_result)
			return pre_result
		return {"success": false, "target_id": null, "target": null, "error": ErrorCodeClass.ERR_NO_VALID_TARGET}

	if _targeting_port == null:
		# No live TargetingPort adapter wired yet at this feature's
		# composition-root state (file-level doc) — degrade safely rather
		# than crash; never fabricate a target of our own.
		return {"success": false, "target_id": null, "target": null, "error": ErrorCodeClass.ERR_NO_VALID_TARGET}

	var target = await _targeting_port.request_single_target(legal_targets)
	if target == null:
		# api_contracts #2: "the cast still resolves as a wasted action" —
		# nothing to resolve against, so ResolutionPort is never invoked
		# either (mirrors the "not yet time to resolve" gate above).
		return {"success": true, "target_id": null, "target": null, "error": ErrorCodeClass.ERR_NO_VALID_TARGET}

	var result: Dictionary = {"success": true, "target_id": target.display_id(), "target": target, "error": ErrorCodeClass.NONE}
	var resolve_cast_result = _maybe_resolve_attack(actor, spell, target, round_number)
	if resolve_cast_result != null:
		result["resolve_cast_result"] = resolve_cast_result
	_maybe_discharge_item(actor, spell, resolve_cast_result)
	return result


## _should_resolve(actor) -> bool — the ADR-007 gate (file-level doc): true
## ONLY when `actor` is non-null, mid-cast, AND its CastingState's
## remaining_actions has reached exactly 0. A cancelled/interrupted cast
## (casting_state == {}, so is_casting() == false) and a still-in-progress
## cast (remaining_actions > 0) both fail this gate identically — neither
## ever reaches TargetingPort.
func _should_resolve(actor) -> bool:
	if actor == null:
		return false
	if not actor.is_casting():
		return false
	var state = CastingStateClass.from_dict(actor.casting_state)
	return state.remaining_actions == 0


## _maybe_resolve_attack(actor, spell, target) -> Dictionary | null —
## FEAT-009 (US-009; FR-008): drives ResolveCastUseCase against a SINGLE
## already-chosen, non-null `target`, returning its Dictionary result, or
## null when there is nothing to resolve — either `spell.defense` is
## Spell.Defense.NONE (a self/no-attack spell, e.g. Channel's ADD_ENERGY —
## there is no defense to roll against, so resolve_spell_attack() must
## never be invoked at all) or no ResolutionPort is wired yet (mirrors
## `_targeting_port == null`'s identical "unwired collaborator -> safe
## fallback" convention above — no live composition-root wiring exists for
## this yet, MainScene.gd is NOT modified by this feature).
##
## `spell.defense`/`actor`/`target` are handed to ResolveCastUseCase.
## execute() UNMODIFIED (this feature's own scope doc: "calling
## resolve_spell_attack(caster, target, spell, spell.defense) unmodified
## per target") — this method performs no conversion itself; that is
## entirely ResolveCastUseCase's/ResolutionPort's job. `_combat_log_port`
## (FEAT-276, possibly null) is forwarded alongside it unmodified —
## ResolveCastUseCase.execute() itself degrades safely (no emit() call at
## all) when it is null.
## _maybe_resolve_self_cast(actor, spell) -> Dictionary | null — FEAT-277
## (US-012; FR-013): drives ResolveCastUseCase for a self/no-target spell
## (range_ft <= 0, e.g. Channel), returning its Dictionary result, or null
## when there is nothing to resolve — ONLY `spell.effect_type ==
## EffectKind.ADD_ENERGY` reaches ResolveCastUseCase here; any OTHER
## self-targeted effect type is explicitly out of this feature's scope and
## is left untouched (mirrors `_maybe_resolve_attack()`'s own "return null
## when there is nothing to resolve" convention). `targets` is handed to
## ResolveCastUseCase as an empty Array — the ADD_ENERGY branch never
## consults it (see that use case's own FEAT-277 doc), it operates on
## `actor` directly. `_resolution_port` is forwarded unmodified even though
## it is never invoked for this branch (mirrors `_maybe_resolve_attack()`'s
## identical "hand the collaborator through, let the use case decide"
## discipline); `_energy_pool_fn` (this feature's own new dep) is what
## actually drives the caster's round energy pool mutation.
func _maybe_resolve_self_cast(actor, spell, round_number: int = 0):
	if spell.effect_type != SpellClass.EffectKindClass.ADD_ENERGY:
		return null
	return _resolve_cast_use_case.execute(actor, spell, [], _resolution_port, _combat_log_port, _energy_pool_fn, round_number)


func _maybe_resolve_attack(actor, spell, target, round_number: int = 0):
	if spell.defense == SpellClass.Defense.NONE:
		return null
	if _resolution_port == null:
		return null
	return _resolve_cast_use_case.execute(actor, spell, [target], _resolution_port, _combat_log_port, Callable(), round_number)


## _maybe_resolve_aoe_cast(actor, spell, origin_hex, round_number) ->
## Dictionary — FEAT-006 (US-005; FR-004, ADR-004): the AoE-target-collection
## + resolution wiring step connecting FEAT-005's AREA_SET origin pick to
## FEAT-003's multi-target ResolveCastUseCase. Extracts the affected hex set
## from `origin_hex` via
## core/application/selection_resolution_use_case.gd's
## SelectionResolutionUseCase.affected_set() (parametrized by
## `spell.area_hex_radius()`, domain-owned — no radius math happens here),
## filters `_combatant_roster_fn`'s live combatant list down to those whose
## `hex_coord` falls inside that set (`_combatants_in_hexes()` below), and
## hands the resulting Combatant[] straight to ResolveCastUseCase.execute()
## — NO friendly-fire filter is applied (ADR-004): a combatant occupying the
## origin hex, including the caster itself, is collected exactly like any
## other in-area combatant. An empty targets Array (no combatant anywhere in
## the affected set) is not an error — it is handed to ResolveCastUseCase
## exactly as-is, which resolves it via its own documented empty-targets
## success path (test_criteria #4).
##
## Mirrors `_maybe_resolve_attack()`'s "no ResolutionPort wired -> nothing to
## resolve" convention: an unwired `_resolution_port` skips
## ResolveCastUseCase entirely (`resolve_cast_result` stays null on the
## returned Dictionary) rather than crashing or fabricating a result.
## `_maybe_discharge_item()` is still invoked afterward, mirroring every
## other resolve path in this file (its own null-`resolve_cast_result`
## no-op guard makes this safe even when ResolutionPort was never reached).
func _maybe_resolve_aoe_cast(actor, spell, origin_hex, round_number: int = 0) -> Dictionary:
	var result := {"success": true, "target_id": null, "target": null, "error": ErrorCodeClass.NONE}

	var geometry_rule: Dictionary
	if spell.is_cone():
		geometry_rule = {"shape": "cone", "length": spell.cone_hex_length(), "caster_hex": actor.hex_coord}
	else:
		geometry_rule = {"radius": spell.area_hex_radius()}
	var affected_hexes: Array = _selection_resolution_use_case.affected_set(origin_hex, geometry_rule)
	var targets: Array = _combatants_in_hexes(affected_hexes)

	var resolve_cast_result = null
	if _resolution_port != null:
		resolve_cast_result = _resolve_cast_use_case.execute(actor, spell, targets, _resolution_port, _combat_log_port, Callable(), round_number)
		result["resolve_cast_result"] = resolve_cast_result

	_maybe_discharge_item(actor, spell, resolve_cast_result)
	return result


## _combatants_in_hexes(hexes) -> Array — every combatant from
## `_combatant_roster_fn` (defaulting to an empty Array when unwired/invalid,
## mirroring `_in_range_candidates()`'s identical degrade) whose `hex_coord`
## equals (HexCoord.equals()) one of `hexes`. A null combatant/`hex_coord` is
## skipped rather than crashing (mirrors `_in_range_candidates()`'s own
## null-guard convention).
func _combatants_in_hexes(hexes: Array) -> Array:
	var roster: Array = _combatant_roster_fn.call() if _combatant_roster_fn.is_valid() else []
	var in_area: Array = []
	for combatant in roster:
		if combatant == null:
			continue
		var combatant_hex = combatant.hex_coord
		if combatant_hex == null:
			continue
		for hex_coord in hexes:
			if combatant_hex.equals(hex_coord):
				in_area.append(combatant)
				break
	return in_area


## _in_range_candidates(actor, range_ft) -> Array — every candidate from
## `_candidates_fn` (defaulting to an empty Array when unwired/invalid) whose
## hex_coord is within `range_ft` converted to hexes (FEET_PER_HEX) of
## `actor`'s own hex_coord, via the SAME HexMath.hex_distance() primitive
## presentation/strike_action_controller.gd already uses for weapon range —
## test_criteria #2's enforcement point. A null actor/candidate hex_coord is
## skipped rather than crashing (mirrors StrikeActionController's identical
## null-guard convention).
func _in_range_candidates(actor, range_ft: int) -> Array:
	var candidates: Array = _candidates_fn.call() if _candidates_fn.is_valid() else []
	var actor_hex = actor.hex_coord
	if actor_hex == null:
		return []

	var range_hexes: int = int(range_ft / FEET_PER_HEX)
	var in_range: Array = []
	for candidate in candidates:
		if candidate == null:
			continue
		var candidate_hex = candidate.hex_coord
		if candidate_hex != null and HexMathClass.hex_distance(actor_hex, candidate_hex) <= range_hexes:
			in_range.append(candidate)
	return in_range


func _skip_result() -> Dictionary:
	return {"success": false, "target_id": null, "target": null, "error": ErrorCodeClass.NONE}


func _fail(error_code: int) -> Dictionary:
	return {"success": false, "target_id": null, "target": null, "error": error_code}


## _maybe_discharge_item(actor, spell, resolve_cast_result) -> void —
## FEAT-009 (US-008; FR-011, ADR-005): the discharge-on-cast exit-point
## requirement. Called from EVERY resolve path above (self-cast,
## pre-chosen-target, and live TargetingPort) immediately after
## `resolve_cast_result` has been computed. A no-op (never throws) unless
## ALL of the following hold:
##   1. `resolve_cast_result` is non-null AND its `success` key is true —
##      an unresolved/failed cast (e.g. no ResolutionPort wired, per
##      `_maybe_resolve_attack()`'s own "return null when there is nothing
##      to resolve" doc) never discharges anything.
##   2. `spell.energy_cost > 0` — a 0-cost spell (e.g. fire_bolt/Channel)
##      never discharges an equipped item, even if one happens to prepare
##      that spell_id (test_criteria #2).
## When both hold, this scans `actor`'s equipped items (the SAME
## `_duck_get(actor, "equipped_items", [])` duck-typed read
## core/application/use_cases/begin_cast_use_case.gd's BeginCastUseCase
## already established — no static ItemResource/Combatant.equipped_items
## type dependency, ADR-004) for the FIRST item whose `prepared_spell_id`
## matches the resolved `spell.spell_id`, and sets `item.is_charged =
## false` — a presentation-layer mutation on the live Resource reference
## already held via the combatant dict (ADR-005's documented exception,
## design notes' architecture section), NOT a new use case.
## No matching item (should not happen given BeginCastUseCase's FEAT-007
## charge-state guard, but must never throw per the design notes' own
## error_handling doc) is a silent no-op — the equipped_items walk simply
## finds nothing to mutate.
func _maybe_discharge_item(actor, spell, resolve_cast_result) -> void:
	if resolve_cast_result == null or not resolve_cast_result.get("success", false):
		return
	if spell.energy_cost <= 0:
		return

	var equipped_items: Array = _duck_get(actor, "equipped_items", [])
	for item in equipped_items:
		if item == null:
			continue
		var prepared_spell_id: String = String(_duck_get(item, "prepared_spell_id", ""))
		if prepared_spell_id != "" and prepared_spell_id == spell.spell_id:
			item.is_charged = false
			return


## _duck_get(obj, key, default) -> Variant — mirrors
## core/application/use_cases/begin_cast_use_case.gd's BeginCastUseCase._duck_get()
## verbatim (NFR-003 defensive duck-typing): tolerates `obj` being a
## Dictionary, an Object exposing `key` as a real property, or null/an
## Object with no such property (falls back to `default`, never raises).
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
