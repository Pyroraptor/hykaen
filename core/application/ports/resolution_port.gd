## core/application/ports/resolution_port.gd — ResolutionPort (FEAT-009 /
## US-009; FR-008)
##
## Application layer (Clean Architecture, ADR-001): documents the contract
## core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase
## depends on to resolve a single spell-attack roll against ONE target —
## mirrors this project's established Protocol-style port pattern
## (core/application/ports/targeting_port.gd's TargetingPort,
## core/application/ports/round_energy_pool_port.gd's RoundEnergyPoolPort):
## a base class documenting the abstract contract; a concrete adapter
## either `extends` it or simply duck-types it. Exactly like
## RoundEnergyPoolPort's SessionEnergyPoolAdapter, the ONE concrete adapter
## this feature needs is nested inside this same file (below) rather than a
## separate adapter file — this feature's file list is deliberately
## scoped to just this port + the use case that drives it.
##
## DESIGN CHOICE — domain-object-in, AttackResult-out (design notes'
## architecture section: "ResolutionPort — resolve_spell_attack(attacker,
## target, spell, defense_type) -> AttackResult (implemented by existing
## core/rules/resolution.gd; NOT modified, only depended-upon)"):
## ResolveCastUseCase calls this port's resolve_spell_attack() with the
## SAME domain objects/values it was itself handed — `caster`/`target`
## (core/domain/combatant.gd Combatant instances), `spell`
## (core/domain/spell.gd Spell instance), and `spell.defense` (the raw
## Spell.Defense enum int) — UNMODIFIED, per this feature's own doc: "...
## calling resolve_spell_attack(caster, target, spell, spell.defense)
## unmodified per target". Bridging those domain types down to
## core/rules/resolution.gd's Dictionary/String-keyed
## resolve_spell_attack(attacker: Dictionary, target: Dictionary, spell:
## Dictionary, defense_type: String) contract is entirely this port's
## concrete adapter's job (ResolutionRulesAdapter below) — resolution.gd
## itself is NEVER modified (design notes' explicit constraint: "NOT
## modified, only depended-upon").
##
## Contract:
##   resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary
##     attacker/target — core/domain/combatant.gd Combatant instances.
##     spell            — core/domain/spell.gd Spell instance.
##     defense_type     — a Spell.Defense enum int (the caller hands in
##                         `spell.defense` verbatim).
##     Returns the AttackResult Dictionary core/rules/resolution.gd's
##     Resolution.resolve_spell_attack() produces verbatim: {"hit", "crit",
##     "roll_total", "damage_raw", "active_defense_applied", "damage_final"}
##     (plus "error" only when the resolved defense_type is invalid, e.g.
##     Spell.Defense.NONE — a non-attack spell like Channel should never be
##     routed through this port at all; see resolve_spell_controller.gd's
##     own gate).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var port: ResolutionPort = ResolutionPort.ResolutionRulesAdapter.new(SeededRandomAdapter.new(42))
##   var attack_result := port.resolve_spell_attack(marigold, skeleton, fire_bolt, fire_bolt.defense)
##   attack_result["hit"]  # true/false, deterministic for seed 42

class_name ResolutionPort
extends RefCounted

const SpellClass = preload("res://core/domain/spell.gd")
const ResolutionClass = preload("res://core/rules/resolution.gd")


## resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary
## — abstract; concrete adapters MUST override. The base implementation
## exists only to document the contract and to fail LOUD (push_error),
## mirroring TargetingPort's / RoundEnergyPoolPort's identical "abstract
## base, push_error default" convention — never to guess/fabricate an
## AttackResult.
func resolve_spell_attack(_attacker, _target, _spell, _defense_type):
	push_error("ResolutionPort.resolve_spell_attack() is abstract — override in a concrete adapter")
	return {
		"hit": false,
		"crit": false,
		"roll_total": 0,
		"damage_raw": 0,
		"active_defense_applied": "none",
		"damage_final": 0,
		"error": "ResolutionPort.resolve_spell_attack() is abstract — override in a concrete adapter",
	}


## _PortRNGAdapter — internal adapter wrapping an injected RandomNumberPort
## (the dice_spec-shaped `roll(dice_spec)` contract — core/rules/
## random_port.gd) so it can be handed to core/rules/resolution.gd's
## Resolution constructor, which duck-types its injected `_rng` against the
## RNG-shaped `d20()` / `roll(die_size, count)` contract (core/rules/
## rng.gd). Verbatim mirror of core/application/resolve_to_hit_uc.gd's /
## core/application/resolve_action_use_case.gd's identically-named,
## identically-shaped inner class — kept as an independent copy here
## (rather than imported) for the same reason those files each keep their
## own copy: GDScript inner classes are not importable across files without
## a full script preload/instantiate indirection, and this adapter carries
## zero state/behavior worth centralizing beyond this one-line forward.
class _PortRNGAdapter:
	extends RefCounted
	var _port

	func _init(port) -> void:
		_port = port

	## d20() -> int — forwards to the injected port's own d20().
	func d20() -> int:
		return _port.d20()

	## roll(die_size, count) -> int — forwards to the injected port's
	## dice_spec-shaped roll().
	func roll(die_size: int, count: int) -> int:
		return _port.roll({"die": die_size, "count": count})


## ResolutionRulesAdapter — the ONE concrete adapter this feature needs,
## wrapping a fresh core/rules/resolution.gd Resolution instance (built
## from an injected RandomNumberPort, exactly mirroring
## core/application/resolve_to_hit_uc.gd's own construction convention) and
## bridging this port's domain-object-shaped contract down to that
## unmodified file's Dictionary/String-keyed
## resolve_spell_attack(attacker, target, spell, defense_type) signature.
##
## `random_number_port` is injected — never constructed here — mirroring
## every other RandomNumberPort-consuming use case in this codebase
## (NFR-003: no global RNG). A caller wanting deterministic, replayable
## resolution (e.g. a pinned-seed boot-real test) injects a
## core/combat/seeded_random_adapter.gd SeededRandomAdapter; production
## composition-root wiring (deferred — MainScene.gd is NOT modified by
## this feature) would inject core/combat/godot_random_adapter.gd's
## GodotRandomAdapter instead.
class ResolutionRulesAdapter:
	extends RefCounted

	var _resolution  ## core/rules/resolution.gd Resolution — unmodified.

	func _init(random_number_port) -> void:
		_resolution = ResolutionClass.new(_PortRNGAdapter.new(random_number_port))

	## resolve_spell_attack(attacker, target, spell, defense_type) ->
	## Dictionary — this port's contract, implemented by bridging
	## Combatant/Spell/enum-int down to core/rules/resolution.gd's
	## Dictionary/String contract and delegating to it UNMODIFIED (see
	## file-level doc). Never inspects/transforms the returned AttackResult
	## Dictionary — it is handed back verbatim.
	func resolve_spell_attack(attacker, target, spell, defense_type) -> Dictionary:
		return _resolution.resolve_spell_attack(
			_attacker_dict(attacker),
			target.to_dict(),
			_spell_dict(spell),
			_defense_type_string(defense_type)
		)

	## _attacker_dict(attacker) -> Dictionary — Combatant.to_dict() already
	## carries "spellcasting_attribute_score" (the numeric score
	## resolve_spell_attack's modifier math needs); core/rules/
	## resolution.gd's own contract reads that score indirectly via
	## `attacker.get(attacker["spellcasting_attribute"], 0)` (a
	## String-keyed indirection, so ANY numeric attacker field can serve as
	## the casting modifier) — pointing "spellcasting_attribute" at the
	## literal String "spellcasting_attribute_score" reuses that
	## already-present field with no separate attribute-name lookup needed.
	## "spell_attack_bonus" defaults to 0 — no such field is modeled on
	## Combatant/Spell yet in this iteration (an extension point for a
	## later feature, mirrors this file's own "unmodified" constraint: this
	## adapter fabricates no bonus resolution.gd wasn't handed).
	func _attacker_dict(attacker) -> Dictionary:
		var d: Dictionary = attacker.to_dict()
		d["spellcasting_attribute"] = "spellcasting_attribute_score"
		d["spell_attack_bonus"] = 0
		return d

	## _spell_dict(spell) -> Dictionary — core/rules/resolution.gd's spell
	## contract needs only "damage_die" (an int); core/domain/spell.gd's
	## Spell instead carries `damage_formula` (a dice-expression String,
	## e.g. "2d8+ATTR" — see that file's own doc). `_parse_damage_die()`
	## extracts the die size from that formula so resolution.gd's damage
	## roll draws the SAME die Fire Bolt's authored data specifies.
	func _spell_dict(spell) -> Dictionary:
		return {"damage_die": _parse_damage_die(spell.damage_formula)}

	## _parse_damage_die(formula) -> int — extracts the die-size capture
	## group from an "NdM[+...]" formula (e.g. "2d8+ATTR" -> 8). Returns 0
	## for an unparseable/empty formula (e.g. Channel's "") — matching
	## resolution.gd's own "roll(0, count) -> 0" safe degrade, since a
	## non-damage spell should never reach this adapter's damage-die path
	## in the first place (resolve_spell_controller.gd's own defense-gated
	## invocation, see that file's doc).
	func _parse_damage_die(formula: String) -> int:
		var regex := RegEx.new()
		regex.compile("\\d+d(\\d+)")
		var result := regex.search(formula)
		return int(result.get_string(1)) if result != null else 0

	## _defense_type_string(defense_type) -> String — maps a
	## core/domain/spell.gd Spell.Defense enum int onto
	## core/rules/resolution.gd's VALID_DEFENSE_TYPES String vocabulary
	## ("ac"/"reflex"/"fortitude"/"will"). Spell.Defense.NONE (and any other
	## unmapped value) yields "" — deliberately NOT a member of
	## VALID_DEFENSE_TYPES, so resolution.gd's own guard rejects it with its
	## existing "Invalid defense type" error Dictionary rather than this
	## adapter fabricating a fallback defense to roll against.
	func _defense_type_string(defense_type: int) -> String:
		match defense_type:
			SpellClass.Defense.AC:
				return "ac"
			SpellClass.Defense.REFLEX:
				return "reflex"
			SpellClass.Defense.FORTITUDE:
				return "fortitude"
			SpellClass.Defense.WILL:
				return "will"
		return ""
