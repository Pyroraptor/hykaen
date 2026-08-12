## core/application/use_cases/long_rest_use_case.gd — LongRestUseCase
## (FEAT-003 / US-003; FR-004, NFR-001, NFR-005; iteration AB-0, rest
## mechanics steel thread).
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd's Combatant, via duck-typed field access — no
## static Combatant type dependency on the `party` elements themselves,
## mirroring core/application/use_cases/begin_cast_use_case.gd's
## `_duck_get()` convention) — never an adapter/infrastructure/presentation
## type, and never the engine scene tree. Extends RefCounted only: no
## Node/Control/SceneTree inheritance, no engine lifecycle coupling
## (ADR-001) — this is what lets tests/integration/test_rest_mechanics_e2e.gd
## (a later feature) boot a party with no MainScene dependency.
##
## api_contracts #2: execute(party) restores every combatant in `party` to a
## fully-rested state:
##   - hp_current -> hp_max
##   - stamina -> stamina_max
##   - mage_recharge_budget_remaining -> intellect
##   - every equipped item with is_charged==false AND energy_cost>0 ->
##     is_charged=true (a non-Mage combatant carries no such item, so this
##     step is a no-op for them; mage_recharge_budget_remaining==intellect==0
##     for a non-Mage combatant is likewise a no-op restore)
## Returns {success: true, restored_combatants: party.size()}. No error path
## is defined this iteration (rest-location safety is intentionally NOT
## enforced yet — ADR-004, a reserved future extension point) — execute()
## therefore always succeeds and performs no precondition validation of
## its own, matching Combatant's own "data entity, not the rule-enforcing
## layer" discipline.
##
## Idempotent by construction: every mutation below assigns a combatant's
## live field to its own ceiling/reset-source field (hp_max, stamina_max,
## intellect) or sets is_charged unconditionally true on a matched item —
## calling execute() twice in a row against the same party produces the
## identical fully-restored state both times, with no errors.

class_name LongRestUseCase
extends RefCounted


## execute(party: Array) -> Dictionary{success, restored_combatants} —
## api_contracts #2. `party` is an Array of duck-typed combatant-shaped
## objects (real core/domain/combatant.gd Combatant instances in
## production; a duck-typed double in tests) — accessed via direct field
## reads/writes (hp_current, hp_max, stamina, stamina_max, intellect,
## mage_recharge_budget_remaining, equipped_items), mirroring this
## codebase's established duck-typing convention for heterogeneous
## combatant/item collections (BeginCastUseCase._duck_get()).
func execute(party: Array) -> Dictionary:
	for combatant in party:
		if combatant == null:
			continue

		combatant.hp_current = combatant.hp_max
		combatant.stamina = combatant.stamina_max
		combatant.mage_recharge_budget_remaining = _compute_budget(combatant)

		var equipped_items: Array = _duck_get(combatant, "equipped_items", [])
		for item in equipped_items:
			if item == null:
				continue
			var is_charged: bool = bool(_duck_get(item, "is_charged", false))
			var energy_cost: int = int(_duck_get(item, "energy_cost", 0))
			if not is_charged and energy_cost > 0:
				item.is_charged = true

	return {"success": true, "restored_combatants": party.size()}


## _compute_budget(combatant) -> int — mirrors CombatantFactory.compute_mage_recharge_budget_remaining():
## returns intellect only when the combatant has at least one equipped item with energy_cost > 0,
## otherwise 0. Non-mages carry no such item, so they always restore to 0.
func _compute_budget(combatant) -> int:
	var equipped_items: Array = _duck_get(combatant, "equipped_items", [])
	for item in equipped_items:
		if item == null:
			continue
		if int(_duck_get(item, "energy_cost", 0)) > 0:
			return int(_duck_get(combatant, "intellect", 0))
	return 0


## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established by BeginCastUseCase._duck_get() (core/application/
## use_cases/begin_cast_use_case.gd): tolerates `obj` being a Dictionary
## (`.get(key, default)`), an Object exposing `key` as a real property
## (`Object.get(key)`, itself null-safe for an undeclared property), or
## null (falls back to `default`) — never raises.
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
