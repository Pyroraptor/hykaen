## core/application/use_cases/resolve_cast_use_case.gd — ResolveCastUseCase
## (FEAT-009 / US-009, FEAT-010 / US-010; FR-008, FR-009)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd Combatant, core/domain/spell.gd Spell,
## core/domain/effects_applier.gd EffectsApplier, core/domain/effects/
## damage_effect.gd DamageEffect) and its own sibling application-layer
## port (ResolutionPort, core/application/ports/resolution_port.gd) —
## never an adapter/infrastructure/presentation type, and never the engine
## scene tree. `resolution_port` is injected duck-typed (no static port
## type annotation on the parameter, mirroring core/application/use_cases/
## begin_cast_use_case.gd's / continue_cast_use_case.gd's own convention),
## so a caller/test may substitute a fake without needing a concrete
## adapter.
##
## SCOPE (FEAT-009): implements the RESOLUTION step of design notes' full
## ResolveCastUseCase contract — "calls ResolutionPort per target".
##
## SCOPE (FEAT-010, this feature): layers the EFFECT step on top — "maps
## AttackResult -> Effect(s) (DAMAGE ...), applies via EffectsApplierPort".
## On a hit, the returned AttackResult's `damage_final` (already computed
## by ResolutionPort/core/rules/resolution.gd from the spell's own
## damage_formula + the caster's spellcasting attribute, e.g. Fire Bolt's
## "2d8+ATTR" fire damage — see resolution_port.gd's own doc; this use
## case performs no dice math of its own) is wrapped in a
## core/domain/effects/damage_effect.gd DamageEffect targeted at that same
## target, then dispatched through the SAME single domain EffectsApplier
## seam (core/domain/effects_applier.gd) every other combat-state mutation
## in this codebase is required to funnel through (ci/
## check_no_duplicate_seams.sh's seam-4 check) — mutating the live target
## Combatant instance BY REFERENCE (never a copy, never re-fetched from a
## Dictionary round-trip). A miss (`attack_result["hit"] == false`) never
## builds/applies a DAMAGE effect at all — the target's hp is left
## untouched.
##
## SCOPE (FEAT-277, this feature): layers the ADD_ENERGY effect-type case on
## top — design notes' architecture section: "Channel ... resolves through
## the identical SpellActionController/ResolveSpellController/
## ResolveCastUseCase path (no bespoke verb)". A spell whose
## `spell.effect_type` is core/domain/effects/effect_kind.gd EffectKind.
## ADD_ENERGY (e.g. Channel) NEVER reaches ResolutionPort at all — there is
## no attack roll, no target, no DAMAGE effect — it is dispatched instead to
## `_execute_add_energy()` below, which builds a core/domain/effects/
## add_energy_effect.gd AddEnergyEffect from `spell.effect_params["amount"]`
## (defaulting to 1) and applies it directly to the CASTER's own
## round-scoped core/domain/energy_pool.gd EnergyPool (design notes:
## "applying +1 energy to the caster's own round pool on resolution") —
## obtained via the injected `energy_pool_fn` Callable(caster) -> EnergyPool,
## mirroring resolve_spell_controller.gd's own `_candidates_fn` "duck-typed
## Callable collaborator, degrades safely when unwired/invalid" convention
## (no core/application/ports/round_energy_pool_port.gd change is needed —
## that port's reserve()/balance() contract is for the up-front,
## non-refundable BeginCastUseCase payment, ADR-003, a wholly separate
## concern from resolution-time energy gain). The SAME CLEANUP + LOG steps
## below still run for this path (casting_state cleared, a CAST_RESOLVE
## entry emitted with `energy_delta` set and `target_ids`/`hit`/
## `damage_amount` left empty/null — design notes' data_model: "empty for
## ADD_ENERGY-only spells like Channel").
##
## SCOPE (FEAT-276, this feature): layers the CLEANUP + LOG steps on top —
## design notes' api_contracts #2: "CLEANUP: actor.casting_state = null
## unconditionally on completion of this call" and "LOG step:
## CombatLogPort.emit(CombatLogEntry{...}) — always emitted, hit or miss."
## Once the RESOLUTION/EFFECT steps above have run for every target (or been
## skipped entirely for an empty `targets` Array — see execute()'s own doc),
## this use case:
##   1. Builds ONE core/domain/combat_log_entry.gd CombatLogEntry
##      (EventType.CAST_RESOLVE) from `caster`/`spell`/the FIRST entry in
##      `results` (Fire Bolt is single-target this iteration; `hit`/
##      `damage_amount` are null when `results` is empty, e.g. a wasted
##      action with no valid target — see CombatLogEntry's own doc) and
##      hands it to the injected `combat_log_port` (core/application/ports/
##      combat_log_port.gd CombatLogPort) via emit() — skipped entirely
##      when no port is injected (mirrors this use case's existing
##      "injected duck-typed, no static port type annotation" convention;
##      a caller/test not yet wiring a CombatLogPort keeps its pre-FEAT-276
##      behavior unchanged).
##   2. Calls `caster.cancel_cast()` (core/domain/combatant.gd's existing
##      sole `casting_state = {}` mutator — no new Combatant method is
##      introduced by this feature) UNCONDITIONALLY — regardless of
##      hit/miss, and regardless of whether a CombatLogPort was injected —
##      so `caster.is_casting()` is false and `caster.casting_state` is
##      empty the instant this call returns.
##
## Still explicitly OUT of this feature's scope (a later feature composes
## these remaining steps alongside this one): requesting target(s) via
## TargetingPort (already presentation/verbs/resolve_spell_controller.gd's
## FEAT-008 job) — this use case never requests/filters targets itself,
## only resolves+applies+logs+clears against whatever `targets` its caller
## already chose.
##
## execute(caster, spell, targets, resolution_port) -> Dictionary{success,
## results, error}: for every non-null `target` in `targets` (in order),
## calls `resolution_port.resolve_spell_attack(caster, target, spell,
## spell.defense)` UNMODIFIED — the exact caster/target/spell instances
## this use case was itself handed, and the spell's own `defense` field (a
## core/domain/spell.gd Spell.Defense enum int) — verbatim, with no
## transformation at this layer (adapting those values down to
## core/rules/resolution.gd's Dictionary/String contract is entirely
## ResolutionPort's concrete adapter's job, never this use case's — see
## resolution_port.gd's own file-level doc).
##
## `results` is an Array of {"target_id": String, "attack_result":
## Dictionary, "damage_applied": int} entries, one per non-null target, in
## the SAME order as `targets` — `attack_result` is whatever ResolutionPort.
## resolve_spell_attack() returned, never inspected/transformed here beyond
## the hit-gated DAMAGE-effect mapping described above; `damage_applied` is
## 0 on a miss (or when `damage_final` is not a positive int on a hit — a
## defensive degrade, never a crash) and the applied amount on a hit.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ResolveCastUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")
const EffectsApplierClass = preload("res://core/domain/effects_applier.gd")
const DamageEffectClass = preload("res://core/domain/effects/damage_effect.gd")
const AddEnergyEffectClass = preload("res://core/domain/effects/add_energy_effect.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")
const CombatLogEntryClass = preload("res://core/domain/combat_log_entry.gd")

## The single domain EffectsApplier instance this use case dispatches every
## resolved hit's DAMAGE effect through (see file-level FEAT-010 doc).
## Injectable for tests (a spy can observe apply() calls without needing a
## live Combatant); defaults to a real EffectsApplier, mirroring
## core/application/resolve_action_use_case.gd's/core/application/
## apply_on_hit_defense_uc.gd's identical "own an EffectsApplier, allow
## injection" convention.
var _effects_applier


func _init(p_effects_applier = null) -> void:
	_effects_applier = p_effects_applier if p_effects_applier != null else EffectsApplierClass.new()


## get_effects_applier() -> EffectsApplier — exposes the single domain
## EffectsApplier instance this use case dispatches DAMAGE effects
## through, mirroring resolve_action_use_case.gd's/apply_on_hit_defense_uc.gd's
## identically-named getter (used by tests/integration's shared-instance
## proofs and available here for the same purpose once a composition root
## wires ResolveCastUseCase alongside those other use cases).
func get_effects_applier():
	return _effects_applier


## execute(caster, spell, targets, resolution_port, combat_log_port,
## energy_pool_fn) -> Dictionary — this feature's own scope only (see
## file-level doc). Fails safe to ERR_INVALID_STATE, with NO CLEANUP/LOG
## step, when `caster` or `spell` is null — a caller reaching this use case
## in that state has a wiring bug (mirrors continue_cast_use_case.gd's own
## "no partial/inconsistent state" discipline); `caster.casting_state` is
## left completely untouched on this defensive path.
##
## FEAT-277: when `spell.effect_type` is EffectKind.ADD_ENERGY (e.g.
## Channel), this call is dispatched ENTIRELY to `_execute_add_energy()`
## below (see file-level FEAT-277 doc) — `resolution_port`/`targets` are
## never consulted at all for this branch (no attack roll, no target — a
## null/unwired `resolution_port` is therefore NOT an error for an
## ADD_ENERGY spell, unlike the attack-defense branch below).
##
## For every OTHER spell (the attack-defense/DAMAGE branch, unchanged from
## FEAT-009/FEAT-010): a null `resolution_port` IS an ERR_INVALID_STATE
## failure. An empty (or null) `targets` Array is NOT an error — it simply
## yields an empty `results` Array (e.g. a wasted-action resolve with no
## valid target, per design notes' error_handling: "the cast still
## resolves ... still completes") — CLEANUP/LOG still run in that case (see
## file-level FEAT-276 doc). A null entry within `targets` is skipped
## rather than crashing (mirrors resolve_spell_controller.gd's own
## null-guard convention).
##
## `combat_log_port` (FEAT-276) defaults to null — a caller/test not yet
## wiring a CombatLogPort (core/application/ports/combat_log_port.gd) never
## has emit() invoked at all (mirrors this file's own established
## "unwired collaborator -> safe fallback" convention). `energy_pool_fn`
## (FEAT-277) defaults to an invalid Callable() — consulted ONLY by the
## ADD_ENERGY branch (see `_apply_add_energy()`'s own doc).
func execute(caster, spell, targets: Array, resolution_port, combat_log_port = null, energy_pool_fn = Callable(), round_number: int = 0) -> Dictionary:
	if caster == null or spell == null:
		return {"success": false, "results": [], "error": ErrorCodeClass.ERR_INVALID_STATE}

	if spell.effect_type == EffectKindClass.ADD_ENERGY:
		return _execute_add_energy(caster, spell, combat_log_port, energy_pool_fn, round_number)

	if resolution_port == null:
		return {"success": false, "results": [], "error": ErrorCodeClass.ERR_INVALID_STATE}

	var results: Array = []
	for target in targets:
		if target == null:
			continue
		var attack_result: Dictionary = resolution_port.resolve_spell_attack(caster, target, spell, spell.defense)
		var damage_applied: int = _apply_damage_on_hit(target, attack_result)
		results.append({
			"target_id": target.display_id(),
			"attack_result": attack_result,
			"damage_applied": damage_applied,
		})

	_emit_combat_log_entry(caster, spell, results, combat_log_port, round_number)

	# CLEANUP (FEAT-276; api_contracts #2): unconditional, regardless of
	# hit/miss/no-valid-target -- the SOLE existing Combatant mutator that
	# empties casting_state (core/domain/combatant.gd's cancel_cast(), no
	# new method introduced by this feature).
	caster.cancel_cast()

	return {"success": true, "results": results, "error": ErrorCodeClass.NONE}


## _execute_add_energy(caster, spell, combat_log_port, energy_pool_fn) ->
## Dictionary — FEAT-277 (US-012; FR-013): the ADD_ENERGY-effect-type branch
## of execute() (see this method's own doc + file-level FEAT-277 doc).
## Builds ONE core/domain/effects/add_energy_effect.gd AddEnergyEffect
## targeted at the CASTER (`caster.display_id()`) from
## `spell.effect_params["amount"]` (defaulting to 1 — Channel's own
## authored SpellResource value, data/spells/channel.tres), applies it to
## the caster's own round energy pool via `_apply_add_energy()`, emits the
## SAME CAST_RESOLVE CombatLogEntry shape FEAT-276 established (with
## `target_ids=[]`, `hit=null`, `damage_amount=null`, `energy_delta` set to
## the amount actually applied — design notes' data_model: "empty for
## ADD_ENERGY-only spells like Channel"), then runs the SAME unconditional
## CLEANUP step (`caster.cancel_cast()`) every other branch of this use
## case runs.
func _execute_add_energy(caster, spell, combat_log_port, energy_pool_fn, round_number: int = 0) -> Dictionary:
	var amount: int = int(spell.effect_params.get("amount", 1))
	var effect := AddEnergyEffectClass.new(caster.display_id(), amount)
	var applied: int = _apply_add_energy(caster, effect, energy_pool_fn)

	if combat_log_port != null:
		var entry := CombatLogEntryClass.new(
			CombatLogEntryClass.EventType.CAST_RESOLVE,
			caster.display_id(),
			spell.spell_id,
			[],
			null,
			null,
			applied,
			round_number
		)
		combat_log_port.emit(entry)

	# CLEANUP (FEAT-276 convention, reused unconditionally here too).
	caster.cancel_cast()

	return {
		"success": true,
		"results": [{"target_id": caster.display_id(), "energy_delta": applied}],
		"error": ErrorCodeClass.NONE,
	}


## _apply_add_energy(caster, effect, energy_pool_fn) -> int — FEAT-277:
## applies `effect` (an AddEnergyEffect) to the EnergyPool
## `energy_pool_fn.call(caster)` returns, mirroring `_apply_damage_on_hit()`'s
## own "return the amount ACTUALLY applied" convention. An invalid `effect`
## (AddEnergyEffect.is_valid() == false — amount <= 0, see that class' own
## doc) or an unwired/invalid `energy_pool_fn` Callable (this codebase's
## established "unwired collaborator -> safe fallback" convention, mirrors
## resolve_spell_controller.gd's own `_candidates_fn` degrade) both skip the
## pool mutation entirely and return 0 — never a fabricated non-zero delta.
func _apply_add_energy(caster, effect, energy_pool_fn) -> int:
	if not effect.is_valid():
		push_error("ResolveCastUseCase: invalid AddEnergyEffect -- skipping: %s" % effect.validation_error())
		return 0

	if not (energy_pool_fn is Callable) or not energy_pool_fn.is_valid():
		return 0

	var pool = energy_pool_fn.call(caster)
	if pool == null:
		return 0

	var before: int = pool.current
	pool.add(effect.amount)
	return pool.current - before


## _emit_combat_log_entry(caster, spell, results, combat_log_port) -> void
## — FEAT-276 (US-011; FR-010, api_contracts #2's LOG step): builds ONE
## core/domain/combat_log_entry.gd CombatLogEntry (EventType.CAST_RESOLVE)
## from `caster.display_id()`/`spell.spell_id`/every `results` entry's
## `target_id`, and the FIRST result's hit/damage_applied (Fire Bolt is
## single-target this iteration — `hit`/`damage_amount` are left null when
## `results` is empty, e.g. a wasted action with no valid target), then
## hands it to `combat_log_port.emit()` -- skipped entirely (no
## CombatLogEntry constructed at all) when `combat_log_port` is null (see
## execute()'s own doc).
func _emit_combat_log_entry(caster, spell, results: Array, combat_log_port, round_number: int = 0) -> void:
	if combat_log_port == null:
		return

	var target_ids: Array = []
	for result in results:
		target_ids.append(result.get("target_id"))

	var hit = null
	var damage_amount = null
	var roll_total = null
	if not results.is_empty():
		var first_result: Dictionary = results[0]
		var attack_result: Dictionary = first_result.get("attack_result", {})
		hit = attack_result.get("hit", false)
		damage_amount = int(first_result.get("damage_applied", 0))
		if attack_result.has("roll_total"):
			roll_total = int(attack_result["roll_total"])

	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE,
		caster.display_id(),
		spell.spell_id,
		target_ids,
		hit,
		damage_amount,
		null,
		round_number,
		roll_total
	)
	combat_log_port.emit(entry)


## _apply_damage_on_hit(target, attack_result) -> int — FEAT-010 (US-010;
## FR-009): on a hit (`attack_result["hit"] == true`) with a positive
## `damage_final`, builds a DamageEffect(target.display_id(), damage_final)
## and dispatches it through `_effects_applier.apply()` against `{target_id:
## target}` — mutating the SAME live `target` instance by reference (never
## a copy). Returns the amount actually applied (0 on a miss, or when
## `damage_final` is not a positive int — DamageEffect rejects amount<=0 at
## construction, so this guard avoids ever constructing an invalid effect).
func _apply_damage_on_hit(target, attack_result: Dictionary) -> int:
	if not attack_result.get("hit", false):
		return 0

	var damage: int = int(attack_result.get("damage_final", 0))
	if damage <= 0:
		return 0

	var target_id: String = target.display_id()
	var damage_effect = DamageEffectClass.new(target_id, damage)
	_effects_applier.apply([damage_effect], {target_id: target})
	return damage
