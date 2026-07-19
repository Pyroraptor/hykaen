## core/application/use_cases/resolve_cast_use_case.gd — ResolveCastUseCase
## (FEAT-009 / US-009; FR-008)
##
## Application layer (Clean Architecture, ADR-001): depends ONLY on domain
## (core/domain/combatant.gd Combatant, core/domain/spell.gd Spell) and its
## own sibling application-layer port (ResolutionPort,
## core/application/ports/resolution_port.gd) — never an
## adapter/infrastructure/presentation type, and never the engine scene
## tree. `resolution_port` is injected duck-typed (no static port type
## annotation on the parameter, mirroring core/application/use_cases/
## begin_cast_use_case.gd's / continue_cast_use_case.gd's own convention),
## so a caller/test may substitute a fake without needing a concrete
## adapter.
##
## SCOPE (FEAT-009): implements ONLY the RESOLUTION step of design notes'
## full ResolveCastUseCase contract — "calls ResolutionPort per target".
## Everything else that contract also describes (requesting target(s) via
## TargetingPort — already presentation/verbs/resolve_spell_controller.gd's
## FEAT-008 job; mapping AttackResult -> Effect(s) and applying them via
## EffectsApplierPort; clearing CastingState; emitting a CombatLogPort
## entry) is explicitly OUT of this feature's scope — a later feature
## extends/composes those steps alongside this one. This use case therefore
## neither mutates `caster`/`target` nor reads/clears CastingState at all;
## it is a pure fan-out over an already-resolved target list.
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
## Dictionary} entries, one per non-null target, in the SAME order as
## `targets` — `attack_result` is whatever ResolutionPort.
## resolve_spell_attack() returned, never inspected/transformed here
## either.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name ResolveCastUseCase
extends RefCounted

const ErrorCodeClass = preload("res://core/application/ports/errors.gd")


## execute(caster, spell, targets, resolution_port) -> Dictionary — this
## feature's own scope only (see file-level doc). Fails safe to
## ERR_INVALID_STATE, with NO ResolutionPort call at all, when `caster`,
## `spell`, or `resolution_port` is null — a caller reaching this use case
## in that state has a wiring bug (mirrors continue_cast_use_case.gd's own
## "no partial/inconsistent state" discipline). An empty (or null)
## `targets` Array is NOT an error — it simply yields an empty `results`
## Array (e.g. a wasted-action resolve with no valid target, per design
## notes' error_handling: "the cast still resolves ... still completes").
## A null entry within `targets` is skipped rather than crashing (mirrors
## resolve_spell_controller.gd's own null-guard convention).
func execute(caster, spell, targets: Array, resolution_port) -> Dictionary:
	if caster == null or spell == null or resolution_port == null:
		return {"success": false, "results": [], "error": ErrorCodeClass.ERR_INVALID_STATE}

	var results: Array = []
	for target in targets:
		if target == null:
			continue
		var attack_result: Dictionary = resolution_port.resolve_spell_attack(caster, target, spell, spell.defense)
		results.append({"target_id": target.display_id(), "attack_result": attack_result})

	return {"success": true, "results": results, "error": ErrorCodeClass.NONE}
