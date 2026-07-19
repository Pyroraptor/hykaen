## core/application/use_cases/begin_cast_use_case.gd — BeginCastUseCase
## (FEAT-005 / US-005; FR-004)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant, core/domain/spell.gd's Spell) and
## its own sibling application-layer ports (SpellCatalogPort,
## RoundEnergyPoolPort) — never an adapter/infrastructure/presentation type,
## and never the engine scene tree. Every collaborator is injected
## (duck-typed — no static port type annotation on parameters, mirroring
## core/application/use_cases/resolve_stride_use_case.gd's own
## `strike_use_case`/`reactor_action_economy_fn` convention), so a caller may
## substitute a fake in a unit test without needing a concrete adapter.
##
## Implements the FIRST-CAST half of the Cast-a-Spell steel thread (design
## notes' architecture section) — the "spell pick, up-front energy payment,
## casting_state init" sequence for a caster who is NOT already mid-cast:
##   1. availability() — US-004 contract #1's full predicate (the skeleton,
##      presentation/verbs/spell_action_controller.gd's SpellActionController
##      FEAT-004, only checked known_spell_ids non-empty OR is_casting();
##      this method ALSO checks round energy pool balance >= at least one
##      known spell's energy_cost, per api_contracts #1).
##   2. execute() — api_contracts #1's execute() first-cast branch:
##        a. validate spell_id is known + resolvable (ERR_NOT_CASTABLE)
##        b. reserve committed_energy via RoundEnergyPoolPort.reserve()
##           BEFORE any state mutation (ERR_INSUFFICIENT_ENERGY on failure —
##           error_handling design note: "aborts BeginCastUseCase BEFORE any
##           casting_state is set and BEFORE the turn action is spent")
##        c. initialize casting_state via Combatant.begin_cast() (domain
##           method, core/domain/combatant.gd — builds a
##           core/domain/casting_state.gd CastingState value object and
##           projects it onto the entity's Dictionary field)
##        d. spend the actor's current turn action
##
## ContinueCastUseCase/ResolveCastUseCase/CancelCastUseCase (design notes'
## architecture section) are explicitly OUT of this feature's scope — an
## actor already mid-cast never reaches this use case at all (see
## SpellActionController's own execute() branch).
##
## FEAT-278 (US-013; FR-014) adds castable_spell_ids() -- the energy-gated
## PICK LIST counterpart to availability()'s boolean predicate above (see
## that method's own doc for the full contract).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name BeginCastUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## availability(actor, spell_catalog_port, round_energy_pool_port) -> bool —
## api_contracts #1's full predicate: true when `actor` is already mid-cast
## (the "continue casting" path, handled elsewhere), OR `actor` knows at
## least one spell whose energy_cost is affordable against its round energy
## pool's CURRENT balance (read-only — RoundEnergyPoolPort.balance(), never
## reserve()). A null `actor` fails safe to false.
func availability(actor, spell_catalog_port, round_energy_pool_port) -> bool:
	if actor == null:
		return false
	if actor.is_casting():
		return true
	if actor.known_spell_ids.is_empty():
		return false
	if spell_catalog_port == null or round_energy_pool_port == null:
		return false

	var caster_id: String = actor.display_id()
	var balance: int = round_energy_pool_port.balance(caster_id)
	for spell_id in actor.known_spell_ids:
		var spell = spell_catalog_port.get_spell(spell_id)
		if spell != null and spell.energy_cost <= balance:
			return true
	return false


## execute(actor, spell_id, spell_catalog_port, round_energy_pool_port,
##         action_economy) -> Dictionary{success, casting_state, error} —
## api_contracts #1's execute() first-cast branch. `action_economy` is
## OPTIONAL (default null, duck-typed — expects spend_action(metadata) ->
## Dictionary, mirroring core/rules/action_economy.gd's ActionEconomy): when
## null, the turn-action spend step is simply skipped (a caller/test that
## does not care about action-economy bookkeeping still gets a usable
## answer, matching this codebase's established "unwired collaborator
## degrades safely" convention).
func execute(actor, spell_id: String, spell_catalog_port, round_energy_pool_port, action_economy = null) -> Dictionary:
	if actor == null:
		return _fail(ErrorCodeClass.ERR_NOT_CASTABLE)

	if not actor.known_spell_ids.has(spell_id):
		return _fail(ErrorCodeClass.ERR_NOT_CASTABLE)

	var spell = spell_catalog_port.get_spell(spell_id) if spell_catalog_port != null else null
	if spell == null:
		return _fail(ErrorCodeClass.ERR_NOT_CASTABLE)

	var caster_id: String = actor.display_id()
	var reserved: bool = round_energy_pool_port.reserve(caster_id, spell.energy_cost) if round_energy_pool_port != null else false
	if not reserved:
		return _fail(ErrorCodeClass.ERR_INSUFFICIENT_ENERGY)

	# Energy is committed -- ONLY now do we mutate casting_state / spend the
	# action (error_handling design note: reservation failure must leave
	# NO partial/inconsistent state; this is the sole point of no return).
	actor.begin_cast(spell.spell_id, spell.actions_cost, spell.energy_cost)

	if action_economy != null:
		action_economy.spend_action({"name": "Cast a Spell", "traits": spell.traits})

	return {
		"success": true,
		"casting_state": (actor.casting_state as Dictionary).duplicate(true),
		"error": ErrorCodeClass.NONE,
	}


func _fail(error_code: int) -> Dictionary:
	return {"success": false, "casting_state": null, "error": error_code}


## castable_spell_ids(actor, spell_catalog_port, round_energy_pool_port) ->
## Array — FEAT-278 (US-013; FR-014): the energy-gated spell PICK LIST
## api_contracts #1's enter_selection() populates its SelectionRequest with
## ("known_spell_ids filtered by pool balance per US-013") -- every spell_id
## in `actor.known_spell_ids` whose resolved Spell.energy_cost is affordable
## against the round energy pool's CURRENT balance (read-only --
## RoundEnergyPoolPort.balance(), never reserve(), mirroring availability()'s
## own read-only balance check above). This is the SAME affordability rule
## availability() already applies to decide "is at least one spell
## castable?" -- this method is its list-producing counterpart, so a caster
## who knows Fireball (energy_cost=2, FEAT-278) at a pool balance < 2 never
## sees "fireball" in the returned list, even though Fire Bolt/Channel
## (energy_cost=0) remain offered.
##
## An unresolvable spell_id (SpellCatalogPort.get_spell() returns null --
## malformed/missing authored data) is silently excluded rather than
## crashing the pick list, matching ResourceSpellCatalogAdapter's own
## "malformed data is treated as unknown" convention. A null actor/
## spell_catalog_port/round_energy_pool_port fails safe to an empty Array.
func castable_spell_ids(actor, spell_catalog_port, round_energy_pool_port) -> Array:
	if actor == null or spell_catalog_port == null or round_energy_pool_port == null:
		return []

	var caster_id: String = actor.display_id()
	var balance: int = round_energy_pool_port.balance(caster_id)

	var result: Array = []
	for spell_id in actor.known_spell_ids:
		var spell = spell_catalog_port.get_spell(spell_id)
		if spell != null and spell.energy_cost <= balance:
			result.append(spell_id)
	return result
