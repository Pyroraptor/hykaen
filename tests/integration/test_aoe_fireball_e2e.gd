extends GutTest
## tests/integration/test_aoe_fireball_e2e.gd — FEAT-008 (US-007; FR-007)
##
## THE steel-thread acceptance/E2E test for the AoE-Fireball feature
## (design notes' api_contracts section: "All four contracts are exercised
## end-to-end by tests/integration/test_aoe_fireball_e2e.gd (US-007), which
## plays the role of the steel thread's acceptance/E2E test analogous to a
## black-box API test in a networked system").
##
## Entry point: the player selects Gram Marx's Fireball and targets an
## origin hex via presentation/verbs/spell_action_controller.gd's
## SpellActionController.enter_selection() — driven here through the REAL,
## wired no-arg verb-table entry point (not merely the directly-callable
## build_area_set_selection() helper), exactly as tests/unit/presentation/
## test_spell_action_controller_aoe.gd's own
## test_enter_selection_real_entry_point_returns_area_set_for_in_progress_fireball_cast()
## proves in isolation — this suite is the first to drive that SAME real
## entry point all the way through to resolution.
##
## Exit point: presentation/verbs/resolve_spell_controller.gd's
## ResolveSpellController.execute() drives core/application/use_cases/
## resolve_cast_use_case.gd's ResolveCastUseCase.execute(), which applies
## INDEPENDENT per-target damage (one attack roll / one DamageEffect
## application per in-area combatant) and emits one
## core/domain/combat_log_entry.gd CombatLogEntry per target — visible here
## via both Combatant.hp_current and the injected CombatLogPanelAdapter.
##
## Every application-layer USE CASE and presentation-layer CONTROLLER driven
## below is the real, unmodified production class (BeginCastUseCase,
## ContinueCastUseCase, SpellActionController, ResolveSpellController,
## core/application/selection_resolution_use_case.gd's
## SelectionResolutionUseCase, ResolveCastUseCase) — nothing under
## core/application/ or presentation/verbs/ is mocked or subclassed by this
## suite. Only the two PORT-boundary collaborators this codebase's own
## established convention already treats as legitimately injectable doubles
## (mirrors tests/integration/test_resolve_spell_controller_aoe_targets.gd's
## SpyResolutionPort and every boot-real Cast-a-Spell suite's
## FakeRoundEnergyPoolPort/FakeActionEconomy) are test-local:
##   - a scripted, always-hit ResolutionPort (RNG/dice-roll adapter — the
##     genuinely external, non-deterministic collaborator every real
##     ResolutionPort-driven suite in this codebase already substitutes a
##     double for when a suite needs a deterministic, hit-guaranteed
##     outcome rather than branching on a seeded roll)
##   - a generous FakeRoundEnergyPoolPort / no-op FakeActionEconomy (so this
##     suite's assertions stay scoped to the AoE targeting/damage/log steel
##     thread, unaffected by round-energy-income mechanics that are a wholly
##     separate feature's concern)
## Gram Marx and every enemy combatant are built through the REAL production
## construction pipeline (infrastructure/combatant_factory.gd's
## CombatantFactory, exactly as MainScene.gd builds every combatant) against
## the REAL data/characters/gram_marx.tres and data/enemies/skeleton.tres
## fixtures — no synthetic/hand-rolled Combatant fixture stands in for
## either.
##
## Encounter geometry (hex-grid, 1 hex == 5 ft; Fireball's
## area_effect_radius_ft==20 -> area_hex_radius()==4, per
## data/spells/fireball.tres):
##   Gram Marx  @ (0, 0)   — well outside the eventual 4-hex blast (no
##                            friendly-fire concern for THIS suite's own
##                            assertions; ADR-004 itself applies no
##                            friendly-fire filter regardless).
##   enemy_a    @ (10, 0)  — the chosen blast ORIGIN itself (hex_distance 0
##                            from origin) -- inside the 4-hex radius.
##   enemy_b    @ (13, 0)  — hex_distance 3 from origin -- inside the 4-hex
##                            radius.
##   enemy_c    @ (20, 0)  — hex_distance 10 from origin -- OUTSIDE the
##                            4-hex radius; must be fully spared.
##
## "Selection overlay confirm" step: presentation/selection_overlay.gd's
## SelectionOverlay (pre-existing, unmodified per this feature's own design
## notes) previews/highlights the AREA_SET candidate_hexes returned by
## enter_selection(), and resolves a click on the chosen origin hex into the
## SAME (origin HexCoord) value ResolveSpellController.execute()'s
## `aoe_origin_hex` parameter consumes -- see
## tests/integration/test_selection_overlay_area_targeting.gd's own
## real-SelectionOverlay proof of that exact preview/confirm/resolve
## mechanics (driven purely against a UI-facing hex_grid_view double, no
## application-layer collaborator). This suite picks `enemy_a`'s hex
## directly out of the REAL enter_selection() descriptor's own
## candidate_hexes (the origin a player click on the overlay would have
## confirmed) and hands it straight to ResolveSpellController.execute() —
## the SAME wiring step tests/integration/
## test_resolve_spell_controller_aoe_targets.gd already establishes as the
## direct, UI-independent way to drive ResolveSpellController's AoE branch
## with an already-confirmed origin.
##
## "No GDScript panics/errors logged" (test_criteria): this project's
## established Godot-4.3 push_error-capture-unavailable proxy convention
## (mirrors tests/e2e/test_steel_thread_strike_full_flow.gd Section A) —
## every use-case Dictionary result asserted below carries
## `error == ErrorCode.NONE` and `success == true`; a genuine internal
## push_error()/fail-fast path (e.g. ERR_INVALID_STATE, ERR_NOT_CASTABLE,
## a null spell/catalog resolution) would surface as one of those
## assertions failing, since none of this suite's real production
## collaborators ever swallow an error silently.

const CombatantFactoryClass            = preload("res://infrastructure/combatant_factory.gd")
const CombatantClass                   = preload("res://core/domain/combatant.gd")
const HexCoordClass                    = preload("res://core/geometry/hex_coord.gd")
const ResourceSpellCatalogAdapterClass = preload("res://core/adapters/resource_spell_catalog_adapter.gd")
const BeginCastUseCaseClass            = preload("res://core/application/use_cases/begin_cast_use_case.gd")
const ContinueCastUseCaseClass         = preload("res://core/application/use_cases/continue_cast_use_case.gd")
const SpellActionControllerClass       = preload("res://presentation/verbs/spell_action_controller.gd")
const ResolveSpellControllerClass      = preload("res://presentation/verbs/resolve_spell_controller.gd")
const ResolutionPortClass              = preload("res://core/application/ports/resolution_port.gd")
const CombatLogPanelAdapterClass       = preload("res://presentation/ui/combat_log_panel_adapter.gd")
const CombatLogEntryClass              = preload("res://core/domain/combat_log_entry.gd")
const ErrorCodeClass                   = preload("res://core/application/ports/errors.gd")
const SelectionDescriptorClass         = preload("res://core/application/selection_descriptor.gd")
const RoundSessionHolderClass          = preload("res://infrastructure/round_session_holder.gd")
const HexMathClass                     = preload("res://core/geometry/hex_math.gd")

const GRAM_MARX_PATH: String = "res://data/characters/gram_marx.tres"
const SKELETON_PATH: String  = "res://data/enemies/skeleton.tres"

## AREA_HEX_RADIUS -- Fireball's area_effect_radius_ft (20) / FEET_PER_HEX
## (5) == 4, per data/spells/fireball.tres (asserted directly against the
## real, loaded catalog entry below -- never hardcoded past that one
## assertion).
const AREA_HEX_RADIUS: int = 4


# ══════════════════════════════════════════════════════════════════════════
# Test doubles — PORT boundary only (never a controller/use case; see
# file-level doc for why these two are the established exception).
# ══════════════════════════════════════════════════════════════════════════

## ScriptedHitResolutionPort -- always resolves to the SAME deterministic
## hit, mirroring tests/integration/test_resolve_spell_controller_aoe_targets.gd's
## SpyResolutionPort exactly (a real ResolutionPort subclass, records every
## `target` argument in call order so this suite can independently verify
## exactly which combatants ResolveCastUseCase drove an attack roll
## against -- i.e. the targets array ResolveSpellController/
## SelectionResolutionUseCase actually assembled from the live encounter).
class ScriptedHitResolutionPort:
	extends ResolutionPortClass
	var calls: Array = []
	var scripted_result: Dictionary = {"hit": true, "crit": false, "roll_total": 15, "damage_raw": 6, "active_defense_applied": "none", "damage_final": 6}

	func resolve_spell_attack(_attacker, target, _spell, _defense_type) -> Dictionary:
		calls.append(target)
		return scripted_result


## FakeRoundEnergyPoolPort -- duck-typed RoundEnergyPoolPort double, mirrors
## tests/integration/test_frost_breath_cast_discharge_dazed_cold_log.gd's
## identically-shaped fake: a generous in-memory balance so Fireball's
## energy_cost (2) is never gated by round-energy availability, keeping
## this suite's assertions scoped to the AoE targeting/damage/log steel
## thread it exists to prove end-to-end.
class FakeRoundEnergyPoolPort:
	extends RefCounted
	var _balance: int

	func _init(starting_balance: int = 99) -> void:
		_balance = starting_balance

	func reserve(_caster_id: String, amount: int) -> bool:
		if _balance < amount:
			return false
		_balance -= amount
		return true

	func balance(_caster_id: String) -> int:
		return _balance


## FakeActionEconomy -- duck-typed action-economy double, mirrors
## tests/integration/test_frost_breath_cast_discharge_dazed_cold_log.gd's
## own fake.
class FakeActionEconomy:
	extends RefCounted
	var spend_calls: Array = []

	func spend_action(action_metadata: Dictionary) -> Dictionary:
		spend_calls.append(action_metadata)
		return {"success": true, "ok": true}


## _FakeSession -- a tiny, real (not all-mocked) double satisfying the SAME
## current_actor()/current_actor_entity()/current_action_economy() contract
## presentation/action_controller.gd's ActionController reads through
## `_session()`, mirroring tests/unit/presentation/test_spell_action_controller_aoe.gd's
## own identically-named/shaped fixture -- the SpellActionController driven
## below is otherwise entirely real/unmocked.
class _FakeSession:
	var _actor

	func _init(actor) -> void:
		_actor = actor

	func current_actor() -> Dictionary:
		return {} if _actor == null else {"combatant_id": _actor.combatant_id}

	func current_actor_entity():
		return _actor

	func current_action_economy():
		return null


# ══════════════════════════════════════════════════════════════════════════
# Fixture construction — REAL production CombatantFactory, REAL .tres data.
# ══════════════════════════════════════════════════════════════════════════

func _build_gram_marx(hex_coord):
	var factory := CombatantFactoryClass.new()
	var spec: Dictionary = factory.build_party_combatant(GRAM_MARX_PATH, hex_coord, "gram_marx_1")
	assert_false(spec.has("error"), "fixture assumption: gram_marx.tres must build a valid combatant with no error")
	return CombatantClass.from_dict(spec)


func _build_enemy(id: String, hex_coord):
	var factory := CombatantFactoryClass.new()
	var spec: Dictionary = factory.build_enemy_combatant(SKELETON_PATH, hex_coord, id)
	assert_false(spec.has("error"), "fixture assumption: the Skeleton enemy resource must build a valid combatant with no error")
	var enemy := CombatantClass.from_dict(spec)
	assert_true(enemy.is_conscious(), "fixture assumption: every enemy combatant must start LIVING before this steel thread casts against it")
	return enemy


# ══════════════════════════════════════════════════════════════════════════
# The steel thread
# ══════════════════════════════════════════════════════════════════════════

func test_fireball_aoe_damages_in_radius_enemies_and_spares_out_of_radius_enemy_steel_thread() -> void:
	# ── Encounter setup: Gram Marx + enemy_a & enemy_b inside the blast
	# radius, enemy_c outside it (file-level geometry doc). ─────────────────
	var gram_marx := _build_gram_marx(HexCoordClass.new(0, 0))
	var origin := HexCoordClass.new(10, 0)
	var enemy_a := _build_enemy("enemy_a", origin)                    # distance 0 from origin
	var enemy_b := _build_enemy("enemy_b", HexCoordClass.new(13, 0))  # distance 3 from origin
	var enemy_c := _build_enemy("enemy_c", HexCoordClass.new(20, 0))  # distance 10 from origin

	var enemy_a_hp_max: int = enemy_a.hp_max
	var enemy_b_hp_max: int = enemy_b.hp_max
	var enemy_c_hp_max: int = enemy_c.hp_max
	assert_gt(enemy_a_hp_max, 0, "fixture assumption: the Skeleton must have positive hp_max")

	var catalog := ResourceSpellCatalogAdapterClass.new()
	var fireball := catalog.get_spell("fireball")
	assert_not_null(fireball, "fixture assumption: data/spells/fireball.tres must load as a valid Spell through the real catalog adapter")
	assert_eq(fireball.area_hex_radius(), AREA_HEX_RADIUS, "fixture assumption: Fireball's area_effect_radius_ft (20ft) must resolve to a 4-hex blast radius")
	assert_eq(HexMathClass.hex_distance(origin, enemy_a.hex_coord), 0)
	assert_eq(HexMathClass.hex_distance(origin, enemy_b.hex_coord), 3)
	assert_true(HexMathClass.hex_distance(origin, enemy_c.hex_coord) > AREA_HEX_RADIUS, "fixture assumption: enemy_c must sit strictly outside the 4-hex blast radius")

	var pool := FakeRoundEnergyPoolPort.new(99)
	var action_economy := FakeActionEconomy.new()

	# ── ENTRY POINT: Gram Marx knows Fireball innately
	# (data/characters/gram_marx.tres known_spell_ids == ["fireball"]). ────
	assert_true(gram_marx.known_spell_ids.has("fireball"), "fixture assumption: Gram Marx must know fireball innately")
	var castable_before: Array = BeginCastUseCaseClass.new().castable_spell_ids(gram_marx, catalog, pool)
	assert_true(castable_before.has("fireball"), "entry point: castable_spell_ids(gram_marx) must contain 'fireball' before casting")

	# ── Player selects Fireball: BeginCastUseCase pays the up-front energy
	# cost and starts casting_state (real, unmocked use case). ─────────────
	var begin_result: Dictionary = BeginCastUseCaseClass.new().execute(gram_marx, "fireball", catalog, pool, action_economy)
	assert_true(begin_result.get("success", false), "BeginCastUseCase.execute() must succeed for a known, affordable Fireball")
	assert_eq(begin_result.get("error"), ErrorCodeClass.NONE)
	assert_true(gram_marx.is_casting(), "a successful begin-cast must leave Gram Marx mid-cast")
	assert_eq(gram_marx.casting_state.get("remaining_actions"), 1, "Fireball's 2-action cost must leave 1 remaining action after begin_cast")

	# ── ENTRY POINT (this feature's own contract): the player targets an
	# origin hex via the REAL, wired SpellActionController.enter_selection()
	# no-arg verb-table entry point -- built from a minimal-but-real
	# session double (file-level doc), never a hand-rolled selection
	# descriptor. ────────────────────────────────────────────────────────────
	var holder := RoundSessionHolderClass.new()
	holder.set_current(_FakeSession.new(gram_marx))
	var spell_action_controller := SpellActionControllerClass.new({"session_holder": holder})

	var descriptor: Dictionary = spell_action_controller.enter_selection()
	assert_eq(descriptor.get("verb_id"), "CAST_SPELL")
	assert_eq(descriptor.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET, "a mid-cast, one-action-remaining Fireball must reach the AREA_SET branch through the real enter_selection() entry point")
	assert_eq(descriptor.get("geometry_rule"), {"radius": AREA_HEX_RADIUS})
	assert_eq(descriptor.get("candidate_targets"), [], "an AoE origin is chosen by hex, never by clicking a target token")

	var candidate_hexes: Array = descriptor.get("candidate_hexes", [])
	assert_true(candidate_hexes.size() > 0, "candidate_hexes must be non-empty for a valid Fireball cast")
	var found_chosen_origin := false
	for hex_coord in candidate_hexes:
		if hex_coord.equals(origin):
			found_chosen_origin = true
			break
	assert_true(found_chosen_origin, "the chosen blast origin must be among the REAL enter_selection()-computed candidate_hexes -- exactly what a player's overlay click would need to land on")

	# ── SELECTION OVERLAY CONFIRM (file-level doc): the player's click on
	# `origin` (a genuine member of candidate_hexes above) is what
	# presentation/selection_overlay.gd's SelectionOverlay would confirm and
	# hand onward as the resolved AREA_SET origin -- see
	# tests/integration/test_selection_overlay_area_targeting.gd for that
	# preview/confirm mechanics proven directly against the real overlay.
	# This suite carries that confirmed `origin` straight into
	# ResolveSpellController.execute()'s `aoe_origin_hex` parameter, the SAME
	# UI-independent wiring point tests/integration/
	# test_resolve_spell_controller_aoe_targets.gd already establishes. ─────

	# Drive the SAME cast to its last action (mirrors every other
	# steel-thread suite's begin -> continue -> resolve sequence).
	var continue_result: Dictionary = ContinueCastUseCaseClass.new().execute(gram_marx, action_economy)
	assert_true(continue_result.get("success", false), "ContinueCastUseCase.execute() must succeed to drive remaining_actions to 0")
	assert_eq(continue_result.get("error"), ErrorCodeClass.NONE)
	assert_eq(gram_marx.casting_state.get("remaining_actions"), 0, "the cast must now be ready to resolve")

	# ── EXIT POINT: the REAL, unmocked ResolveSpellController drives the
	# REAL, unmocked ResolveCastUseCase against the encounter's live
	# combatant roster, independently resolving EACH in-area target. ───────
	var resolution_port := ScriptedHitResolutionPort.new()
	var combat_log_panel := CombatLogPanelAdapterClass.new()
	var resolve_spell_controller := ResolveSpellControllerClass.new({
		"spell_catalog_port": catalog,
		"resolution_port": resolution_port,
		"combat_log_port": combat_log_panel,
		"combatant_roster_fn": func(): return [gram_marx, enemy_a, enemy_b, enemy_c],
	})

	var resolve_result: Dictionary = await resolve_spell_controller.execute(gram_marx, 1, "", origin)
	assert_true(resolve_result.get("success", false), "ResolveSpellController.execute() must succeed for a valid AoE resolution")
	assert_eq(resolve_result.get("error"), ErrorCodeClass.NONE)

	var resolve_cast_result: Dictionary = resolve_result.get("resolve_cast_result", {})
	assert_true(resolve_cast_result.get("success", false), "ResolveCastUseCase.execute() must itself report success")
	assert_eq(resolve_cast_result.get("error"), ErrorCodeClass.NONE)
	assert_eq(resolve_cast_result.get("results", []).size(), 2, "exactly the two in-area combatants (enemy_a + enemy_b) must have been independently resolved")

	# ── CLEANUP: casting_state cleared immediately after resolution. ───────
	assert_false(gram_marx.is_casting(), "casting_state must be cleared immediately after resolution")
	assert_true(gram_marx.casting_state.is_empty())

	# ── EXIT POINT ASSERTION 1: enemy_a and enemy_b took independent
	# damage; enemy_c is fully spared (outside the blast radius). ──────────
	var targeted_ids: Array = resolution_port.calls.map(func(t): return t.display_id())
	assert_true(targeted_ids.has("enemy_a"), "enemy_a (inside the 4-hex blast) must have been driven through ResolutionPort")
	assert_true(targeted_ids.has("enemy_b"), "enemy_b (inside the 4-hex blast) must have been driven through ResolutionPort")
	assert_false(targeted_ids.has("enemy_c"), "enemy_c (outside the 4-hex blast) must NEVER have been driven through ResolutionPort")
	assert_eq(resolution_port.calls.size(), 2, "exactly the two in-area combatants must have been targeted, no more/no less")

	assert_lt(enemy_a.hp_current, enemy_a_hp_max, "enemy_a must have taken damage from the AoE Fireball")
	assert_lt(enemy_b.hp_current, enemy_b_hp_max, "enemy_b must have taken damage from the AoE Fireball, INDEPENDENTLY of enemy_a")
	assert_eq(enemy_c.hp_current, enemy_c_hp_max, "enemy_c must be fully spared -- hp_current must equal hp_max, outside the blast radius")

	# ── EXIT POINT ASSERTION 2: the combat log carries EXACTLY one
	# CombatLogEntry per in-radius combatant (2 entries), and none for
	# enemy_c. ───────────────────────────────────────────────────────────────
	assert_eq(combat_log_panel.get_entry_count(), 2, "exactly one CombatLogEntry per in-radius combatant (enemy_a + enemy_b) must be emitted")

	var logged_target_ids: Array = []
	for i in range(combat_log_panel.get_entry_count()):
		var entry = combat_log_panel.get_entry(i)
		assert_true(entry is CombatLogEntryClass)
		assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
		assert_eq(entry.spell_id, "fireball")
		assert_eq(entry.actor_id, gram_marx.display_id())
		assert_eq(entry.target_ids.size(), 1, "each CombatLogEntry must carry exactly ONE target -- one row per combatant, never an aggregated multi-target row")
		assert_true(entry.hit, "the scripted ResolutionPort always hits -- every entry must record hit==true")
		assert_gt(entry.damage_amount, 0, "a hit must carry a positive damage_amount")
		logged_target_ids.append(entry.target_ids[0])

	assert_true(logged_target_ids.has(enemy_a.display_id()), "enemy_a must have its own independent CombatLogEntry")
	assert_true(logged_target_ids.has(enemy_b.display_id()), "enemy_b must have its own independent CombatLogEntry")
	assert_false(logged_target_ids.has(enemy_c.display_id()), "enemy_c must have NO CombatLogEntry at all")

	# ── "No GDScript panics/errors logged" proxy (file-level doc): every
	# use-case Dictionary result along this ENTIRE sequence reported
	# success==true / error==ErrorCode.NONE -- re-asserted here in one place
	# as this suite's own explicit closing statement of that criterion. ────
	assert_eq(begin_result.get("error"), ErrorCodeClass.NONE)
	assert_eq(continue_result.get("error"), ErrorCodeClass.NONE)
	assert_eq(resolve_result.get("error"), ErrorCodeClass.NONE)
	assert_eq(resolve_cast_result.get("error"), ErrorCodeClass.NONE)
