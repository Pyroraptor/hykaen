extends Node
## MainScene.gd — project composition root (ADR-006 / US-004 / FEAT-005)
##
## This is the SINGLE place Infrastructure adapters are wired to Application
## ports for the whole game (manual DI via the scene tree — no DI framework,
## per ADR-002). project.godot's run/main_scene points at MainScene.tscn
## (which attaches this script), so launching the project boots directly
## into the prologue encounter (US-004) — the steel thread's entry_point.
##
## Wiring performed in _ready():
##   1. ResourceEncounterRepository (infrastructure/resource_encounter_repository.gd)
##      loads data/encounters/prologue_encounter.tres and builds the domain
##      hex-positioned Combatant list (US-001) — the repository adapter.
##   2. GodotRandomAdapter (core/combat/godot_random_adapter.gd) is
##      constructed, seeded from the encounter resource's seed field for
##      determinism (NFR-002/006) — the RandomPort adapter. It is exposed on
##      this node (random_port) as the production RandomNumberPort instance
##      later Application-layer callers (e.g. a future TurnController/UI
##      layer, US-011) can retrieve from the composition root without
##      re-wiring their own adapter.
##   3. ConsoleEventSinkAdapter (defined below) implements EventSinkPort by
##      mirroring every round event to stdout — the event-sink adapter and
##      this iteration's textual observability extension point.
##   4. The existing Encounter composition root (core/combat/encounter.gd,
##      itself already the established ADR-006 wiring for RunRoundUseCase /
##      ResolveActionUseCase / DetermineOutcomeUseCase) drives the prologue
##      party (reused from titus.tres via prologue_encounter.tres, per
##      US-004) against the prologue enemy to a terminal outcome, republishing
##      every round event through the event-sink adapter above.
##
## No new ports or use cases are introduced here (ADR-002 / CR-001 guardrail)
## — this file only constructs adapters around the pre-existing ports/use
## cases and the pre-existing Encounter composition root.

const ResourceEncounterRepositoryClass = preload("res://infrastructure/resource_encounter_repository.gd")
const GodotRandomAdapterClass          = preload("res://core/combat/godot_random_adapter.gd")
const EncounterClass                   = preload("res://core/combat/encounter.gd")
const RNGClass                         = preload("res://core/rules/rng.gd")
const AttributesClass                  = preload("res://core/rules/attributes.gd")
const WeaponResourceClass              = preload("res://core/model/weapon_resource.gd")
const ArmorResourceClass               = preload("res://core/model/armor_resource.gd")

## The steel-thread's entry_point: the one encounter this composition root boots into.
const PROLOGUE_ENCOUNTER_PATH: String = "res://data/encounters/prologue_encounter.tres"

## EnemyResource carries no AC field in the v0 schema; 12 mirrors the
## production convention already established for enemies built from
## EnemyResource data (core/sim/simulator.gd / tests/integration/test_steel_thread_e2e.gd).
const DEFAULT_ENEMY_AC: int = 12

## Safety cap on run_round() calls — guards this composition root against an
## unexpected non-terminating scenario hanging the running game at boot.
const MAX_ROUNDS_GUARD: int = 100


## ConsoleEventSinkAdapter — concrete EventSinkPort adapter (ADR-006):
## mirrors every emitted round event to stdout via print(), giving a textual
## trace of the encounter without introducing a new port (the observability
## extension point called out for this iteration).
class ConsoleEventSinkAdapter:
	extends "res://core/application/event_sink_port.gd"

	var log: Array = []

	func emit(event) -> void:
		log.append(event)
		if event.has_method("to_dict"):
			print("INFO: round event ", event.to_dict())
		else:
			print("INFO: round event ", event)


## encounter_repository — the repository adapter instantiated at the
## composition root (ADR-006).
var encounter_repository

## random_port — the production RandomPort adapter instantiated at the
## composition root (ADR-006), seeded for determinism (NFR-002/006).
var random_port

## event_sink — the EventSinkPort adapter instantiated at the composition
## root (ADR-006); every round event from the booted encounter passes through it.
var event_sink

## encounter — the running Encounter (core/combat/encounter.gd) for the
## booted prologue fight.
var encounter

## outcome / round_count / event_count — exposed for verification (manual
## smoke test and automated GUT coverage) that the prologue encounter
## actually ran to a terminal state.
var outcome: String = ""
var round_count: int = 0
var event_count: int = 0


func _ready() -> void:
	encounter_repository = ResourceEncounterRepositoryClass.new()
	var hex_combatants: Array = encounter_repository.load_combatants(PROLOGUE_ENCOUNTER_PATH)

	var encounter_resource = ResourceLoader.load(PROLOGUE_ENCOUNTER_PATH)
	if encounter_resource == null:
		push_error("MainScene: failed to load " + PROLOGUE_ENCOUNTER_PATH)
		return

	random_port = GodotRandomAdapterClass.new(encounter_resource.seed)
	event_sink = ConsoleEventSinkAdapter.new()

	var party: Array = []
	for i in range(encounter_resource.party_resource_paths.size()):
		var party_hex = hex_combatants[i].hex_coord if i < hex_combatants.size() else null
		party.append(_build_party_combatant(encounter_resource.party_resource_paths[i], party_hex))

	var party_count: int = encounter_resource.party_resource_paths.size()
	var enemies: Array = []
	for j in range(encounter_resource.enemy_resource_paths.size()):
		var idx: int = party_count + j
		var enemy_hex = hex_combatants[idx].hex_coord if idx < hex_combatants.size() else null
		enemies.append(_build_enemy_combatant(encounter_resource.enemy_resource_paths[j], enemy_hex))

	var rng := RNGClass.new(encounter_resource.seed)
	encounter = EncounterClass.new(party, enemies, rng)
	encounter.initialize()

	var rounds_run: int = 0
	while encounter.get_outcome() == "" and rounds_run < MAX_ROUNDS_GUARD:
		encounter.run_round()
		for event in encounter.get_round_events():
			event_sink.emit(event)
		rounds_run += 1

	outcome = encounter.get_outcome()
	round_count = encounter.get_round_count()
	event_count = event_sink.log.size()

	print(
		"INFO: Hykaen MainScene booted into prologue encounter -- outcome=" + outcome
		+ " rounds=" + str(round_count) + " events=" + str(event_count)
	)


## _build_party_combatant(character_path, hex_coord) -> Dictionary
##
## Builds the Dictionary shape core/combat/encounter.gd expects (US-004
## reuses the existing party pipeline) from a CharacterResource, its
## class_ref, and the first WeaponResource / ArmorResource found among its
## starting_equipment. hex_coord (a core/geometry/hex_coord.gd HexCoord, or
## null) is attached so melee reach-gating (US-003) applies when present.
func _build_party_combatant(character_path: String, hex_coord) -> Dictionary:
	var character = ResourceLoader.load(character_path)
	var class_data = character.class_ref

	var weapon_res = null
	var armor_res = null
	for equip_path in character.starting_equipment:
		var equip = ResourceLoader.load(equip_path)
		if equip is WeaponResourceClass:
			weapon_res = equip
		elif equip is ArmorResourceClass:
			armor_res = equip

	var attrs := AttributesClass.new(RNGClass.new(0))
	var hp: int = attrs.compute_hp(character.attributes, class_data)
	var ac: int = attrs.compute_ac(character.attributes, armor_res.ac_base, armor_res.category)

	var combatant: Dictionary = {
		"name":       character.name,
		"hp_current": hp,
		"ac":         ac,
		"strength":   character.attributes.get("strength",  0),
		"dexterity":  character.attributes.get("dexterity", 0),
		"intuition":  character.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
			"proficiency_bonus":         weapon_res.proficiency_bonus,
			"damage_die":                weapon_res.damage_die
		}
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	return combatant


## _build_enemy_combatant(enemy_path, hex_coord) -> Dictionary
##
## Builds the Dictionary shape core/combat/encounter.gd expects from an
## EnemyResource. hex_coord (a core/geometry/hex_coord.gd HexCoord, or null)
## is attached so melee reach-gating (US-003) applies when present.
func _build_enemy_combatant(enemy_path: String, hex_coord) -> Dictionary:
	var enemy = ResourceLoader.load(enemy_path)

	var attribute_map: Dictionary = {"str": "strength", "dex": "dexterity"}
	var raw_attribute: String = enemy.weapon.get("attribute", "strength")
	var weapon_attribute: String = attribute_map.get(raw_attribute, raw_attribute)

	var combatant: Dictionary = {
		"name":       enemy.name,
		"hp_current": enemy.hp,
		"ac":         DEFAULT_ENEMY_AC,
		"strength":   enemy.str,
		"dexterity":  enemy.dex,
		"intuition":  0,
		"weapon": {
			"damage_modifier_attribute": weapon_attribute,
			"proficiency_bonus":         enemy.weapon.get("proficiency_bonus", 1),
			"damage_die":                enemy.weapon.get("die", 6)
		}
	}
	if hex_coord != null:
		combatant["hex_coord"] = hex_coord
	return combatant
