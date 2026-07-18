## core/domain/effects_applier.gd — EffectsApplier (FEAT-002 / US-002)
##
## Domain layer (Clean Architecture, ADR-001): pure GDScript — no
## Node/Control/CanvasItem inheritance, no engine lifecycle callbacks, no
## engine I/O. Extends RefCounted only, matching the existing value-object
## convention (core/domain/effects/effect_base.gd, core/domain/combatant.gd).
##
## EffectsApplier is a pure DOMAIN SERVICE, not an application use case —
## it has no ports and no I/O, depending only on Effect value objects
## (core/domain/effects/*.gd) and Combatant instances (core/domain/
## combatant.gd). This is the SINGLE reusable seam the steel thread routes
## all combat-state mutation through (design notes' architecture section):
## no code path outside this class is permitted to call
## Combatant.take_damage()/heal()/add_condition()/move_to() directly —
## enforced statically by ci/check_no_duplicate_seams.sh's EffectsApplier
## seam check (this feature also extends that gate).
##
## apply(effects, combatants) -> void — api_contracts #1:
##   Pre:  every effect.target_id SHOULD exist as a key in `combatants`
##         (the live combatant set, e.g. a future
##         CombatantSetPort.get_live_combatants() snapshot).
##   Post: each effect applied exactly once, by reference, in list order —
##         mutating the SAME Combatant instance passed in via `combatants`
##         (never a copy, never a Dictionary round-trip; see
##         core/domain/combatant.gd's take_damage()/heal()/add_condition()/
##         move_to() mutators, which this class dispatches to directly).
##
## Dispatch: effect.kind (EffectKind, core/domain/effects/effect_kind.gd)
## determines which Combatant mutator this class calls —
##   DAMAGE     -> target.take_damage(amount)
##   HEAL       -> target.heal(amount)              (capped at hp_max)
##   CONDITION  -> target.add_condition(condition) when add=true,
##                 target.remove_condition(condition) when add=false
##   MOVE       -> target.move_to(hex)
##   ADD_ENERGY -> reserved (Iteration M); no Combatant mutator exists yet,
##                 so this kind push_error()s and is skipped rather than
##                 crashing on a missing method.
##
## Error handling (design notes' error_handling policy #1/#2, matching this
## codebase's established assert(false, message); push_error(message)
## convention — see core/application/reaction_window.gd's
## assert_reaction_budget_delta() and presentation/reaction_controller.gd):
##   - A null effect, or an effect that failed its own construction-time
##     validation (Effect.is_valid() == false — see core/domain/effects/effect_base.gd),
##     is skipped: push_error() + continue to the next effect. An invalid
##     effect must never reach a Combatant mutator.
##   - A missing target_id (not a key in `combatants`) triggers a REAL
##     GDScript assert() — Godot only compiles assert() into debug/test
##     builds, so this is a genuine assert-fail signal in dev/CI and a
##     silent no-op in an exported release build — immediately followed by
##     push_error() as defense-in-depth (this project's Godot 4.3 engine
##     cannot reliably capture push_error() output from GUT), then the
##     offending effect is skipped.
##   - Skipping one effect NEVER aborts the batch: apply() always continues
##     to every remaining effect in `effects`, matching api_contracts #1's
##     "never a silent full-batch abort".
##
## Usage:
##   var applier := EffectsApplier.new()
##   var combatants := {"enemy_0": some_combatant}
##   applier.apply([DamageEffect.new("enemy_0", 6)], combatants)
##   combatants["enemy_0"].hp_current  # reduced by 6, same instance

class_name EffectsApplier
extends RefCounted

const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")


## apply(effects, combatants) -> void — dispatches every Effect in
## `effects` (an Array of Effect-family value objects, core/domain/
## effect*.gd) against `combatants` (a Dictionary keyed by combatant_id ->
## Combatant instance, core/domain/combatant.gd), in list order. See the
## file-level doc for the full pre/post/error contract.
func apply(effects: Array, combatants: Dictionary) -> void:
	for effect in effects:
		_apply_one(effect, combatants)


## _apply_one(effect, combatants) -> void — applies exactly one Effect, by
## reference, against the live `combatants` set. Never raises/throws
## (GDScript has no exceptions) — every failure mode logs and returns,
## letting apply()'s loop continue to the next effect (no partial-batch
## abort).
func _apply_one(effect, combatants: Dictionary) -> void:
	if effect == null:
		push_error("EffectsApplier: null effect in batch -- skipping")
		return

	if not effect.is_valid():
		push_error(
			"EffectsApplier: invalid effect (kind=%s, target_id='%s') -- skipping: %s"
			% [effect.kind, effect.target_id, effect.validation_error()]
		)
		return

	if not combatants.has(effect.target_id):
		var message: String = (
			"EffectsApplier: missing target_id '%s' in combatants -- skipping effect (kind=%s)"
			% [effect.target_id, effect.kind]
		)
		# Fail-soft skip in a release build (assert() compiles out); a real
		# assert-fail signal in dev/test builds (design notes'
		# error_handling policy #2). push_error() is defense-in-depth since
		# this project's Godot 4.3 engine cannot reliably capture
		# push_error() output from GUT directly.
		assert(false, message)
		push_error(message)
		return

	var target = combatants[effect.target_id]

	match effect.kind:
		EffectKindClass.DAMAGE:
			target.take_damage(effect.amount)
		EffectKindClass.HEAL:
			target.heal(effect.amount)
		EffectKindClass.CONDITION:
			if effect.add:
				target.add_condition(effect.condition)
			else:
				target.remove_condition(effect.condition)
		EffectKindClass.MOVE:
			target.move_to(effect.hex)
		EffectKindClass.ADD_ENERGY:
			# Reserved for Iteration M (design notes' data_model) -- no
			# Combatant mutator exists yet for this kind.
			push_error("EffectsApplier: ADD_ENERGY dispatch not implemented (reserved for Iteration M) -- skipping")
		_:
			push_error("EffectsApplier: unknown EffectKind %s -- skipping" % effect.kind)
