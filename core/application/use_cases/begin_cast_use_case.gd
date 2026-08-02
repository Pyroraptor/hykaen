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
	if spell_catalog_port == null or round_energy_pool_port == null:
		return false

	var caster_id: String = actor.display_id()
	var balance: int = round_energy_pool_port.balance(caster_id)
	for spell_id in actor.known_spell_ids:
		var spell = spell_catalog_port.get_spell(spell_id)
		if spell != null and spell.energy_cost <= balance:
			return true
	var _equipped = actor.get("equipped_items")
	for item in (_equipped if _equipped != null else []):
		if item == null or item.prepared_spell_id == "" or not item.is_charged:
			continue
		var spell = spell_catalog_port.get_spell(item.prepared_spell_id)
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

	var is_known: bool = actor.known_spell_ids.has(spell_id)
	var prepared_item = null if is_known else _find_item_preparing(actor, spell_id)
	if not is_known and prepared_item == null:
		return _fail(ErrorCodeClass.ERR_NOT_CASTABLE)

	# FEAT-007 (US-006; FR-009, ADR-006): secondary charge-state guard.
	# Checked AFTER the known_spell_ids/prepared_item resolution above but
	# BEFORE any energy reservation/state mutation -- an item-prepared spell
	# whose item.is_charged==false is rejected as ERR_INVALID_STATE, the
	# SAME "abort before any side effect" contract the existing
	# ERR_INSUFFICIENT_ENERGY branch below already honors (error_handling
	# design note). An innate known spell (`is_known == true`) never reaches
	# `prepared_item` at all, so it is completely unaffected by this guard.
	if not is_known and not bool(_duck_get(prepared_item, "is_charged", false)):
		return _fail(ErrorCodeClass.ERR_INVALID_STATE)

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
##
## FEAT-006 (US-005; FR-008, steel thread iteration AA-3-1): after the
## known_spell_ids pass above (untouched), this method ALSO walks
## `actor`'s equipped items -- read via `_duck_get(actor, "equipped_items",
## [])`, NEVER a static ItemResource/Combatant.equipped_items type
## dependency (ADR-004) -- and unions in each item's `prepared_spell_id`
## where ALL of the following hold:
##   1. `prepared_spell_id` is non-empty (an implement with nothing
##      prepared contributes nothing).
##   2. `is_charged == true` (an uncharged implement's spell is not
##      offered -- discharging/recharging is a later feature's concern).
##   3. the spell_id is not already present in `result` (dedupe -- a spell
##      known innately AND item-prepared, e.g. a future overlap, is listed
##      exactly once, in known_spell_ids' position).
##   4. `spell_catalog_port.get_spell(prepared_spell_id)` resolves
##      non-null AND its `energy_cost` is affordable against the SAME pool
##      `balance` read once above (the identical affordability rule the
##      known_spell_ids pass already applies) -- an unresolvable
##      prepared_spell_id is silently skipped (NFR-003 defensive
##      duck-typing), never a crash.
## `_duck_get()` (below) tolerates `actor`/an item being either a plain
## Dictionary (`.get(key, default)`) or an Object exposing the field as a
## property (Object.get(property), which itself safely returns null --
## never raises -- for an undeclared property, e.g. Marigold/Patience's
## Combatant instances, which carry no `equipped_items` field at all) --
## so a non-item-user actor's `known_spell_ids` list passes through this
## method completely unchanged, with no exception (steel thread's own
## AA-3-1 test criterion).
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

	var equipped_items: Array = _duck_get(actor, "equipped_items", [])
	for item in equipped_items:
		if item == null:
			continue
		var prepared_spell_id: String = String(_duck_get(item, "prepared_spell_id", ""))
		if prepared_spell_id == "" or not bool(_duck_get(item, "is_charged", false)):
			continue
		if result.has(prepared_spell_id):
			continue
		var prepared_spell = spell_catalog_port.get_spell(prepared_spell_id)
		if prepared_spell != null and prepared_spell.energy_cost <= balance:
			result.append(prepared_spell_id)

	return result


## _duck_get(obj, key, default) -> Variant — FEAT-006: a single defensive
## duck-typed field read shared by castable_spell_ids()'s equipped-items
## walk (above), tolerating THREE shapes without ever raising:
##   - `obj` is a Dictionary: `obj.get(key, default)` (the established
##     dict-key-read idiom used throughout this codebase's Application
##     layer).
##   - `obj` is an Object exposing `key` as a real property (e.g. a
##     duck-typed item double, or an ItemResource handed in through an
##     adapter/presentation caller): `Object.get(key)`, which itself
##     returns null (never raises/pushes an error) for a property that
##     genuinely doesn't exist on that Object -- verified against this
##     project's Godot 4.3 runtime.
##   - `obj` is null, or an Object with no such property: falls back to
##     `default` -- e.g. Marigold/Patience's plain Combatant instances,
##     which declare no `equipped_items` field at all, degrade to `[]`
##     rather than crashing castable_spell_ids() for the whole party
##     (NFR-003).
## _find_item_preparing(actor, spell_id) -> Variant — FEAT-007 (US-006;
## FR-009, ADR-006): walks `actor`'s equipped items (the SAME
## `_duck_get(actor, "equipped_items", [])` read castable_spell_ids() above
## already uses) looking for the first item whose `prepared_spell_id`
## matches `spell_id`, REGARDLESS of that item's `is_charged` state -- this
## is deliberately charge-state-agnostic so execute()'s caller (above) can
## distinguish "no item prepares this spell at all" (ERR_NOT_CASTABLE, the
## existing contract) from "an item prepares it but it's uncharged"
## (ERR_INVALID_STATE, this feature's new guard). Returns null when no
## equipped item's `prepared_spell_id` matches -- never raises, mirroring
## `_duck_get()`'s own defensive-duck-typing contract (NFR-003).
func _find_item_preparing(actor, spell_id: String):
	var equipped_items: Array = _duck_get(actor, "equipped_items", [])
	for item in equipped_items:
		if item == null:
			continue
		var prepared_spell_id: String = String(_duck_get(item, "prepared_spell_id", ""))
		if prepared_spell_id != "" and prepared_spell_id == spell_id:
			return item
	return null


func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
