class_name CombatantFactory
extends RefCounted

## CombatantFactory — builds the runtime combatant Dictionary shape that
## core/application/resolve_action_use_case.gd expects, from authored
## CharacterResource / EnemyResource data on disk.
##
## Extracted verbatim from MainScene.gd (composition-root de-bloat, 2026-07-10):
## the party/enemy construction + FEAT-227 fail-fast validation lived inline in
## the 2,788-line MainScene god-object, forcing every review of this concern to
## trace the whole file. It is a resource-loading construction boundary (it calls
## ResourceLoader.load and maps Resources → the app-layer combatant dict), so it
## sits in infrastructure/ alongside ResourceEncounterRepository. MainScene now
## delegates _build_party_combatant()/_build_enemy_combatant() here unchanged;
## this move is behavior-preserving (no logic changes).

const RNGClass            = preload("res://core/rules/rng.gd")
const AttributesClass     = preload("res://core/rules/attributes.gd")
const WeaponResourceClass = preload("res://core/model/weapon_resource.gd")
const ArmorResourceClass  = preload("res://core/model/armor_resource.gd")
const CombatantClass      = preload("res://core/domain/combatant.gd")

## FEAT-227 (US-001 / FR-001, resolves FIND-223): typed fail-fast error codes.
## Mirrors this project's established ERR_ constant idiom. A caller MUST check
## result.has("error") before treating a build_enemy_combatant() return value as
## a playable combatant.
const ERR_ENEMY_RESOURCE_LOAD_FAILED: String = "ERR_ENEMY_RESOURCE_LOAD_FAILED"
const ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE: String = "ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE"
const ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD: String = "ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD"


## build_party_combatant(character_path, hex_coord, combatant_id) -> Dictionary
##
## Builds the Dictionary shape core/application/resolve_action_use_case.gd
## expects (US-004 reuses the existing party pipeline) from a
## CharacterResource, its class_ref, and the first WeaponResource /
## ArmorResource found among its starting_equipment. hex_coord (a
## core/geometry/hex_coord.gd HexCoord, or null) is attached so melee
## reach-gating (US-003) applies when present. combatant_id (the domain
## Combatant's stable id from ResourceEncounterRepository, or "") is
## attached so Presentation controls (StrikeActionControl/StatusPanelView)
## can identify this combatant consistently with HexGridView's tokens.
func build_party_combatant(character_path: String, hex_coord, combatant_id: String = "") -> Dictionary:
	var character = ResourceLoader.load(character_path)
	var class_data = character.class_ref

	# FEAT-005 (US-005 / FR-003, RISK-002 mitigation): walk starting_equipment
	# and collect an ORDERED weapon_res_list of every WeaponResource found,
	# instead of resolving a single `weapon_res` variable. Order is
	# semantically significant (data_model): index 0 = primary, index 1 =
	# off-hand. weapon_res (below) stays the primary weapon for every
	# existing downstream read in this function -- this is purely additive.
	var weapon_res_list: Array = []
	var armor_res = null
	for equip_path in character.starting_equipment:
		var equip = ResourceLoader.load(equip_path)
		if equip is WeaponResourceClass:
			weapon_res_list.append(equip)
		elif equip is ArmorResourceClass:
			armor_res = equip
	var weapon_res = weapon_res_list[0] if not weapon_res_list.is_empty() else null

	var attrs := AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(character.attributes, class_data)
	var ac: int = attrs.compute_ac(character.attributes, armor_res.ac_base, armor_res.category)
	var stamina: int = attrs.compute_stamina(character.attributes, class_data)

	# FEAT-001 (US-001; iteration AB-0, rest mechanics steel thread):
	# stamina_max is the SAME derived value as `stamina` above (both come
	# from Attributes.compute_stamina()) -- a freshly-built combatant starts
	# at full stamina, and stamina_max is the ceiling LongRestUseCase (a
	# later feature) restores `stamina` to.
	var stamina_max: int = stamina

	# intellect: a plain authored attribute, resolved the SAME way
	# strength/dexterity/intuition already are below -- 0 for a character
	# with no authored "intellect" key.
	var intellect: int = character.attributes.get("intellect", 0)

	# mage_recharge_budget_remaining: intellect-derived daily budget for a
	# Mage-paradigm combatant (any equipped item with energy_cost > 0);
	# else 0. Uses the SAME _duck_get()-style equipped-items walk
	# BeginCastUseCase (core/application/use_cases/begin_cast_use_case.gd)
	# already established, so no rigid ItemResource type dependency is
	# introduced here.
	var mage_recharge_budget_remaining: int = compute_mage_recharge_budget_remaining(intellect, character.equipped_items)

	# FEAT-002 (Iteration M P0-0, US-001/FR-001/FR-002): resolve this
	# character's spellcasting_attribute_score through the EXISTING
	# construction path — no bespoke caster path. The governing attribute
	# name lives on class_data (core/model/class_resource.gd's
	# spellcasting_attribute, e.g. "willpower" for a Divine Warrior); "" for a
	# non-caster class (e.g. Fighter) resolves to a score of 0, matching
	# every other non-caster combatant built here today. known_spell_ids is
	# carried straight from the authored CharacterResource (duplicated to
	# avoid aliasing its mutable Array), mirroring the "skills" Dictionary
	# carry-through above.
	var spellcasting_attribute_name: String = class_data.spellcasting_attribute
	var spellcasting_attribute_score: int = 0
	if spellcasting_attribute_name != "":
		spellcasting_attribute_score = character.attributes.get(spellcasting_attribute_name, 0)

	var combatant: Dictionary = {
		"name":       character.name,
		"hp_current": hp,
		"hp_max":     hp,
		"stamina":    stamina,
		"stamina_max": stamina_max,
		"ac":         ac,
		"strength":   character.attributes.get("strength",  0),
		"dexterity":  character.attributes.get("dexterity", 0),
		"intuition":  character.attributes.get("intuition", 0),
		"intellect":  intellect,
		"mage_recharge_budget_remaining": mage_recharge_budget_remaining,
		# FEAT-236 (US-001/US-002, resolves DEF-001): carry the REAL
		# CharacterResource.skills Dictionary (mobility/determination) onto
		# the combatant dict, mirroring build_enemy_combatant()'s identical
		# fix below. Without this, core/application/_build_defense_context.gd's
		# build_prehit_context() reads target.get("skills", {}).get("mobility", 0)
		# against a MISSING "skills" key and silently defaults to 0, so
		# ai_reaction_policy.gd's MobilityDodgeRule.dodge_worthwhile()
		# (10+mobility > targeted_defense_value) evaluates against a phantom
		# zero mobility in live play even though every mocked-dict unit test
		# (which hand-populates "skills" itself) stays green. .duplicate()
		# avoids aliasing the CharacterResource's own mutable Dictionary
		# into the combatant (mirrors this codebase's existing convention of
		# never handing a Resource's own mutable container out by reference).
		"skills":     character.skills.duplicate(),
		# FEAT-002 (Iteration M P0-0): resolved caster fields (see comment
		# above) — 0 / [] for a non-caster character, threaded through the
		# SAME construction path every party combatant uses.
		"spellcasting_attribute_score": spellcasting_attribute_score,
		"known_spell_ids": character.known_spell_ids.duplicate(),
		# FEAT-004 (US-004 / FR-002): carry the WeaponResource's display
		# name onto the combatant weapon dict, so reaction-prompt/UI
		# labels (a later feature) can render "Parry (Mace +1)" instead
		# of a bare reaction id. Combatant.from_dict()/to_dict() deep-
		# duplicate arbitrary weapon-dict keys (weapon.duplicate(true)),
		# so this round-trips with zero domain-layer change.
		#
		# FEAT-005 (US-005 / FR-003): `weapon` is built from
		# weapon_res_list[0] (the primary) via the shared
		# _weapon_dict_from_resource() helper -- SAME shape as before,
		# unchanged. `weapons` is the new ordered per-slot list: [primary]
		# for a single-weapon combatant, or [primary, off_hand] for a
		# shield-bearer like Patience. weapons[0] is always structurally
		# identical to `weapon` (invariant pinned by regression tests).
		"weapon": _weapon_dict_from_resource(weapon_res),
		"weapons": _weapon_dicts_from_resources(weapon_res_list)
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	if combatant_id != "":
		combatant["combatant_id"] = combatant_id
	# Combatant migration Phase B (docs/refactors/combatant-entity-migration.org):
	# route the factory's success output THROUGH the Combatant entity so the
	# entity is now the single construction source. Still returns a Dictionary
	# (via to_dict()), so callers/pipeline are unchanged until Phase C flips the
	# resolution signatures to consume the instance directly. The FEAT-227
	# fail-fast error path above is deliberately NOT routed through the entity —
	# it keeps returning the {"error": ...} Dictionary the call-site guard checks.
	var result: Dictionary = CombatantClass.from_dict(combatant).to_dict()
	# FEAT-005 (US-004 / FR-007, ADR-004): expose equipped_items on the
	# combatant dict. Combatant.to_dict()/from_dict() round-trip a FIXED,
	# named field set (see core/domain/combatant.gd) and does not carry
	# arbitrary keys through, so this is set on the Dictionary AFTER the
	# entity round-trip rather than inside the `combatant` literal above
	# (which would be silently dropped). .duplicate() is a SHALLOW copy —
	# a new Array container per build, but the SAME live ItemResource
	# instances character.equipped_items holds — so a mutation to a field
	# on one of those Resources (e.g. is_charged, set by
	# ResolveSpellController's post-resolve discharge hook) stays visible
	# everywhere else holding this combatant dict, and via
	# character.equipped_items directly, since both arrays alias the same
	# underlying Resource objects. This is the infrastructure seam that
	# lets the application layer duck-type-read equipped_items without any
	# core/resources/.tres import of its own.
	result["equipped_items"] = character.equipped_items.duplicate()
	return result


## _fail_enemy_resource_load(error_code, message, enemy_path) -> Dictionary
##
## FEAT-227 (US-001 / FR-001, resolves FIND-223): the single shared
## fail-fast exit point build_enemy_combatant() routes every load/sanity
## validation failure through. Logs via push_error() (this project's
## established non-aborting diagnostic call — see e.g.
## core/application/resolve_action_use_case.gd's identical push_error()-
## then-continue convention) and returns the typed error Dictionary shape
## ({"error": error_code, "enemy_path": enemy_path}) in place of a valid
## combatant, so a caller/test can observe the failure directly.
##
## NOTE: deliberately does NOT use a real GDScript assert() here (unlike
## core/application/reaction_window.gd's assert_reaction_budget_delta()).
## Empirically, under this project's headless Godot 4.3 CLI test run (no
## debugger attached), a failing assert() does not merely log and
## continue as documented elsewhere in this codebase -- it unwinds the
## CURRENT function immediately, so the push_error()/return lines below it
## never execute and the caller instead observes the function's bare
## default return value ({} for a Dictionary), silently defeating the very
## typed-error contract this function exists to provide. push_error()
## alone is both sufficient (it is this project's genuinely non-aborting
## logging call) and correct here.
func _fail_enemy_resource_load(error_code: String, message: String, enemy_path: String) -> Dictionary:
	var full_message: String = "CombatantFactory.build_enemy_combatant(%s): %s" % [enemy_path, message]
	push_error(full_message)
	return {"error": error_code, "enemy_path": enemy_path}


## build_enemy_combatant(enemy_path, hex_coord, combatant_id) -> Dictionary
##
## Builds the Dictionary shape core/application/resolve_action_use_case.gd
## expects from an EnemyResource. hex_coord (a core/geometry/hex_coord.gd
## HexCoord, or null) is attached so melee reach-gating (US-003) applies
## when present. combatant_id (see build_party_combatant() above) is
## attached so Presentation controls can identify this combatant
## consistently with HexGridView's tokens.
##
## FEAT-008 (US-008 / FR-008, ADR-106): ac/fortitude/reflex/will are read
## DIRECTLY from the loaded EnemyResource's own authored fields (data/
## enemies/enemy_resource.gd, populated e.g. by data/enemies/skeleton.tres —
## ac=14, fortitude=13, reflex=12, will=12) — never a hard-coded fallback
## constant. A Strike against an EnemyResource-built target rolls against that
## resource's OWN authored AC (14 for the Skeleton). core/sim/simulator.gd's
## own combatant-construction path reads these same four fields from the same
## EnemyResource source, so the sim and the live game can never silently
## diverge on enemy defenses.
##
## FEAT-227 (US-001 / FR-001, resolves FIND-223): fail-fast-at-load
## validation. Previously ResourceLoader.load(enemy_path) was never null
## checked (a missing/unresolvable path crashed reaching into a null
## Resource's fields) and the weapon fields it threads through
## (damage_die/proficiency_bonus/parry_bonus/block_value/block_die) were
## read with no range/sanity validation at all, so malformed authored data
## (e.g. a never-authored empty weapon Dictionary, or a negative die size)
## silently produced a "dead on arrival" combatant instead of failing
## loudly. This function returns a typed error Dictionary
## ({"error": <ERR_ code>, "enemy_path": enemy_path}) in place of a valid
## combatant shape whenever the resource fails to load or its weapon data
## is malformed. A caller MUST check result.has("error") before treating
## the return value as a playable combatant.
##
## FEAT-002 (US-002, ADR-001/ADR-002): the weapon source of truth moved
## from EnemyResource's own inline `weapon: Dictionary` +
## parry_bonus/block_value/block_die fields to `weapon_paths: Array` — an
## ordered list of res:// paths to normalized WeaponResource files
## (data/weapons/*.tres). Index 0 is resolved via ResourceLoader and its
## OWN fields (damage_die/proficiency_bonus/damage_modifier_attribute/
## parry_bonus/block_value/block_die) now feed the combatant weapon dict
## below -- same validation checks, same error codes, same resulting
## Dictionary shape, only the read source changed. damage_modifier_attribute
## is already the canonical long-form name on WeaponResource (e.g.
## "strength"), so the old str/dex -> strength/dexterity attribute_map
## translation is no longer needed.
##
## FEAT-006 (US-005, ADR-005/ADR-006): `weapon_path_override` (4th arg, ""
## by default) lets a caller (the encounter spawn-slot orchestration --
## api/orchestration, a later feature) pin a SPECIFIC weapon path for this
## spawn, overriding the enemy's own default. Resolution precedence (must
## match api_contracts exactly):
##   1. weapon_path_override, when non-empty -- highest precedence.
##   2. enemy.weapon_paths[0] -- fallback.
##   3. neither present -- ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE.
## Everything downstream of path resolution (load + field validation) is
## UNCHANGED regardless of which branch supplied the path.
##
## FEAT-006 (US-006, EWA2-2-1): `off_hand_path_override` (5th arg, "" by
## default) resolves an OPTIONAL off-hand weapon for this enemy, mirroring
## build_party_combatant()'s FEAT-005 off-hand collection. Resolution
## precedence (must match api_contracts exactly):
##   1. off_hand_path_override, when non-empty -- highest precedence.
##   2. enemy.weapon_paths[1], when present -- fallback.
##   3. neither present -- no off-hand; combatant['weapons'] stays a single-
##      element Array (regression: skeleton.tres and every other existing
##      single-weapon enemy fixture is unaffected).
## Off-hand resolution runs strictly AFTER the primary weapon has already
## loaded and passed field validation, so a malformed off-hand can never
## mask (or be masked by) a primary-weapon failure. A resolved off-hand path
## that fails to load returns ERR_ENEMY_RESOURCE_LOAD_FAILED; a loaded
## off-hand WeaponResource with a negative damage_die/parry_bonus/
## block_value/block_die returns ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD --
## the SAME error codes/shape the primary weapon path already uses.
func build_enemy_combatant(enemy_path: String, hex_coord, combatant_id: String = "", weapon_path_override: String = "", off_hand_path_override: String = "") -> Dictionary:
	var enemy = ResourceLoader.load(enemy_path)
	if enemy == null:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_LOAD_FAILED,
			"ResourceLoader.load() returned null -- the EnemyResource path is missing or failed to load",
			enemy_path
		)

	var weapon_path: String = ""
	if weapon_path_override != "":
		weapon_path = weapon_path_override
	elif not enemy.weapon_paths.is_empty():
		weapon_path = enemy.weapon_paths[0]
	else:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_WEAPON_UNRESOLVABLE,
			"weapon_paths is empty -- no weapon configured for this enemy, refusing to default to a phantom weapon",
			enemy_path
		)

	var weapon_res = ResourceLoader.load(weapon_path)
	if weapon_res == null:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_LOAD_FAILED,
			"weapon WeaponResource failed to load from '%s'" % weapon_path,
			enemy_path
		)

	var damage_die: int = weapon_res.damage_die
	if damage_die < 0:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
			"damage_die must be non-negative; got %d" % damage_die,
			enemy_path
		)

	var proficiency_bonus: int = weapon_res.proficiency_bonus
	if proficiency_bonus < 0:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
			"proficiency_bonus must be non-negative; got %d" % proficiency_bonus,
			enemy_path
		)

	if weapon_res.parry_bonus < 0:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
			"parry_bonus must be non-negative; got %d" % weapon_res.parry_bonus,
			enemy_path
		)

	if weapon_res.block_value < 0:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
			"block_value must be non-negative; got %d" % weapon_res.block_value,
			enemy_path
		)

	if weapon_res.block_die < 0:
		return _fail_enemy_resource_load(
			ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
			"block_die must be non-negative; got %d" % weapon_res.block_die,
			enemy_path
		)

	var weapon_attribute: String = weapon_res.damage_modifier_attribute

	# FEAT-006 (US-006, EWA2-2-1): resolve an optional off-hand weapon --
	# see the build_enemy_combatant() doc above for the full precedence and
	# error-code contract. off_hand_res stays null when no off-hand path
	# resolves at all (empty override AND enemy.weapon_paths.size() < 2).
	var off_hand_path: String = ""
	if off_hand_path_override != "":
		off_hand_path = off_hand_path_override
	elif enemy.weapon_paths.size() >= 2:
		off_hand_path = enemy.weapon_paths[1]

	var off_hand_res = null
	if off_hand_path != "":
		off_hand_res = ResourceLoader.load(off_hand_path)
		if off_hand_res == null:
			return _fail_enemy_resource_load(
				ERR_ENEMY_RESOURCE_LOAD_FAILED,
				"off-hand weapon WeaponResource failed to load from '%s'" % off_hand_path,
				enemy_path
			)

		if off_hand_res.damage_die < 0:
			return _fail_enemy_resource_load(
				ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
				"off-hand damage_die must be non-negative; got %d" % off_hand_res.damage_die,
				enemy_path
			)

		if off_hand_res.parry_bonus < 0:
			return _fail_enemy_resource_load(
				ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
				"off-hand parry_bonus must be non-negative; got %d" % off_hand_res.parry_bonus,
				enemy_path
			)

		if off_hand_res.block_value < 0:
			return _fail_enemy_resource_load(
				ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
				"off-hand block_value must be non-negative; got %d" % off_hand_res.block_value,
				enemy_path
			)

		if off_hand_res.block_die < 0:
			return _fail_enemy_resource_load(
				ERR_ENEMY_RESOURCE_INVALID_WEAPON_FIELD,
				"off-hand block_die must be non-negative; got %d" % off_hand_res.block_die,
				enemy_path
			)

	# FEAT-006: `primary_weapon_dict` is the SAME shape build_enemy_combatant()
	# has always built inline as combatant["weapon"] -- extracted to a local
	# so it can ALSO seed weapons_list[0], guaranteeing the weapons[0] ==
	# weapon invariant (data_model) by construction, matching
	# build_party_combatant()'s identical guarantee (FEAT-005).
	var primary_weapon_dict: Dictionary = {
		"name":                      weapon_res.name,
		"damage_modifier_attribute": weapon_attribute,
		"proficiency_bonus":         proficiency_bonus,
		"damage_die":                damage_die,
		"parry_bonus":               weapon_res.parry_bonus,
		"block_value":               weapon_res.block_value,
		"block_die":                 weapon_res.block_die
	}
	var weapons_list: Array = [primary_weapon_dict]
	if off_hand_res != null:
		weapons_list.append(_weapon_dict_from_resource(off_hand_res))

	# FEAT-007 (US-007 / FR-006 / FR-008): stamina/stamina_max are now READ
	# from the EnemyResource's own authored stamina_max field (data/enemies/
	# enemy_resource.gd, FEAT-002) rather than hardcoded to 0. A freshly-built
	# enemy combatant starts at full stamina (stamina == stamina_max), mirroring
	# build_party_combatant()'s identical stamina/stamina_max-from-source
	# convention above. skeleton.tres authors stamina_max = 0, so this is a
	# byte-for-byte regression-safe no-op for every enemy that has not yet
	# authored a non-zero stamina_max.
	var enemy_stamina_max: int = enemy.stamina_max

	var combatant: Dictionary = {
		"name":       enemy.name,
		"hp_current": enemy.hp,
		"hp_max":     enemy.hp,
		"stamina":    enemy_stamina_max,
		"stamina_max": enemy_stamina_max,
		"ac":         enemy.ac,
		"fortitude":  enemy.fortitude,
		"reflex":     enemy.reflex,
		"will":       enemy.will,
		"strength":   enemy.str,
		"dexterity":  enemy.dex,
		"intuition":  enemy.intuition,
		"intellect":  0,
		"mage_recharge_budget_remaining": 0,
		# FEAT-236 (US-001/US-002, resolves DEF-001): carry the REAL
		# EnemyResource.skills Dictionary (mobility/determination) onto the
		# combatant dict, mirroring build_party_combatant()'s identical fix
		# above with NO field-name drift (both use the SAME "skills" key
		# holding the SAME "mobility"/"determination" sub-keys). Previously
		# this key was never set at all, so core/application/
		# _build_defense_context.gd's build_prehit_context() silently read a
		# missing "skills" key as {} and defaulted mobility to 0 for every
		# real enemy in live play -- ai_reaction_policy.gd's
		# MobilityDodgeRule.dodge_worthwhile() (10+mobility >
		# targeted_defense_value) was therefore ALWAYS evaluated against
		# mobility=0 regardless of the authored EnemyResource data (e.g.
		# skeleton.tres's skills.mobility=1), even though existing unit tests
		# passed green (they hand-populate combatant["skills"] on a mocked
		# Dictionary directly, never exercising this factory function at
		# all). .duplicate() avoids aliasing the EnemyResource's own mutable
		# Dictionary into the combatant.
		"skills":     enemy.skills.duplicate(),
		# FEAT-004 (US-004 / FR-002): mirrors build_party_combatant()'s
		# identical addition above -- carry the WeaponResource's display
		# name onto the enemy combatant's weapon dict too. FEAT-001
		# (iteration K): carry the DEFENSIVE reaction fields too (mirrors
		# build_party_combatant()'s identical FEAT-006 fix above) so
		# is_parry_eligible()/is_block_eligible() read non-zero values for
		# enemy defenders too — without these, an enemy's weapon dict always
		# read 0 and the reaction window could never offer the enemy a
		# Parry/Block choice.
		#
		# FEAT-006 (US-006, EWA2-2-1): `weapon` is `primary_weapon_dict`
		# (built above) -- SAME shape as before, unchanged. `weapons` is
		# [primary_weapon_dict] for a single-weapon enemy (regression:
		# skeleton.tres), or [primary_weapon_dict, off_hand_dict] when an
		# off-hand resolved via override or enemy.weapon_paths[1].
		# weapons[0] is always structurally identical to `weapon` by
		# construction (same primary_weapon_dict instance).
		"weapon":  primary_weapon_dict,
		"weapons": weapons_list
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	if combatant_id != "":
		combatant["combatant_id"] = combatant_id
	# Combatant migration Phase B (docs/refactors/combatant-entity-migration.org):
	# route the factory's success output THROUGH the Combatant entity so the
	# entity is now the single construction source. Still returns a Dictionary
	# (via to_dict()), so callers/pipeline are unchanged until Phase C flips the
	# resolution signatures to consume the instance directly. The FEAT-227
	# fail-fast error path above is deliberately NOT routed through the entity —
	# it keeps returning the {"error": ...} Dictionary the call-site guard checks.
	var result: Dictionary = CombatantClass.from_dict(combatant).to_dict()
	# FEAT-007 (US-007 / FR-006 / FR-008): 'ai_tier' is set on the returned
	# Dictionary AFTER the Combatant entity round-trip, mirroring
	# build_party_combatant()'s identical post-round-trip 'equipped_items'
	# attachment above. core/domain/combatant.gd's from_dict()/to_dict() only
	# round-trip a FIXED, named field set (see that file's header note) and do
	# NOT carry arbitrary keys through -- 'stamina'/'stamina_max' already
	# survive the round-trip because they are among those fixed fields, but
	# 'ai_tier' is not, so it would be silently dropped if attached to the
	# `combatant` literal above instead. This keeps core/domain/combatant.gd
	# itself untouched (no ai_tier field added to the frozen entity schema).
	result["ai_tier"] = enemy.ai_tier
	return result


## _weapon_dict_from_resource(weapon_res) -> Dictionary
##
## FEAT-005 (US-005 / FR-003): the single shared mapping from a loaded
## WeaponResource to the combatant weapon-dict shape (name,
## damage_modifier_attribute, proficiency_bonus, damage_die, parry_bonus,
## block_value, block_die). Extracted so build_party_combatant()'s
## `weapon` (primary) and `weapons` (ordered list) fields are built from
## the EXACT same mapping -- this is what guarantees the weapons[0] ==
## weapon invariant (data_model) by construction, not by a separate
## equality check.
func _weapon_dict_from_resource(weapon_res) -> Dictionary:
	return {
		"name":                      weapon_res.name,
		"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
		"proficiency_bonus":         weapon_res.proficiency_bonus,
		"damage_die":                weapon_res.damage_die,
		"parry_bonus":               weapon_res.parry_bonus,
		"block_value":               weapon_res.block_value,
		"block_die":                 weapon_res.block_die
	}


## _weapon_dicts_from_resources(weapon_res_list) -> Array
##
## FEAT-005 (US-005 / FR-003): maps an ORDERED Array of loaded
## WeaponResources (as collected by build_party_combatant()'s
## starting_equipment walk) to an Array of weapon dicts via
## _weapon_dict_from_resource(), preserving order (index 0 = primary,
## index 1 = off-hand). Returns [] for an empty list -- the pre-existing
## nil-check/error path for a missing primary weapon is unchanged; this
## helper never raises.
func _weapon_dicts_from_resources(weapon_res_list: Array) -> Array:
	var result: Array = []
	for weapon_res in weapon_res_list:
		result.append(_weapon_dict_from_resource(weapon_res))
	return result


## compute_mage_recharge_budget_remaining(intellect, equipped_items) -> int
##
## FEAT-001 (US-001; iteration AB-0, rest mechanics steel thread): a
## Mage-paradigm combatant's starting daily recharge budget is `intellect`
## when ANY equipped item is dischargeable (energy_cost > 0); otherwise 0
## (Channeler/Sorcerer paradigms, or a non-caster, never carry a
## dischargeable item so this always resolves 0 for them). Walks
## `equipped_items` via `_duck_get()` (below) rather than depending on a
## concrete ItemResource type -- mirrors the SAME defensive, duck-typed
## equipped-items walk BeginCastUseCase (core/application/use_cases/
## begin_cast_use_case.gd) already established for castable_spell_ids()/
## _find_item_preparing(). A null entry in `equipped_items` is skipped, not
## a crash (NFR-003).
##
## Exposed as a public method (not `_`-prefixed) so it is directly unit
## testable against synthetic Dictionary-shaped items, independent of
## whether any currently-authored ItemResource .tres fixture authors
## energy_cost yet.
func compute_mage_recharge_budget_remaining(intellect: int, equipped_items: Array) -> int:
	for item in equipped_items:
		if item == null:
			continue
		var energy_cost: int = int(_duck_get(item, "energy_cost", 0))
		if energy_cost > 0:
			return intellect
	return 0


## _duck_get(obj, key, default) -> Variant — the SAME defensive duck-typed
## field read established by BeginCastUseCase._duck_get() (see that file's
## own doc for the full three-shape contract: Dictionary, Object exposing
## `key` as a real property, or null/absent -- falls back to `default` in
## every case, never raises).
func _duck_get(obj, key: String, default = null):
	if obj == null:
		return default
	if obj is Dictionary:
		return obj.get(key, default)
	var value = obj.get(key)
	return value if value != null else default
