## infrastructure/resource_encounter_repository.gd — ResourceEncounterRepository
## (FEAT-001 / US-001 / ADR-005)
##
## Infrastructure/Adapter layer (Clean Architecture): loads a Resource-file
## encounter definition (data/encounters/*.tres, backed by
## data/encounters/encounter_resource.gd's EncounterResource) and builds
## domain Combatant instances (core/domain/combatant.gd) from it,
## initializing each combatant's hex_coord (core/geometry/hex_coord.gd) from
## the authored party_hex_positions / enemy_hex_positions arrays.
##
## This is the ONE place ResourceLoader / Resource-file concerns meet the
## domain Combatant/HexCoord value types (ADR-005) — it performs no combat
## rules logic and depends only on the domain layer (core/domain,
## core/geometry) plus the Godot ResourceLoader API, matching the
## Infrastructure→Domain dependency direction (never the reverse).
##
## Usage:
##   var repo := ResourceEncounterRepository.new()
##   var combatants: Array = repo.load_combatants("res://data/encounters/prologue_encounter.tres")
##   combatants[0].hex_coord.q   # authored q value from the .tres file

class_name ResourceEncounterRepository
extends RefCounted

const CombatantClass = preload("res://core/domain/combatant.gd")
const HexCoordClass  = preload("res://core/geometry/hex_coord.gd")

## Team tag applied to combatants built from party_resource_paths.
const TEAM_PLAYER: String = "Player"

## Team tag applied to combatants built from enemy_resource_paths.
const TEAM_ENEMY: String = "Enemy"


## load_combatants(path) → Array[Combatant]
##
## Loads the EncounterResource at `path` and returns an Array of domain
## Combatant instances: party members (team=Player) followed by enemies
## (team=Enemy), each hex_coord initialized from the resource's
## party_hex_positions / enemy_hex_positions arrays (parallel to
## party_resource_paths / enemy_resource_paths by index). A combatant whose
## index has no corresponding authored position defaults to HexCoord(0, 0).
##
## Returns an empty Array if the encounter resource fails to load.
func load_combatants(path: String) -> Array:
	var encounter_resource = ResourceLoader.load(path)
	if encounter_resource == null:
		push_error("ResourceEncounterRepository: failed to load encounter resource at %s" % path)
		return []

	var combatants: Array = []
	_append_team_combatants(
		combatants,
		encounter_resource.party_resource_paths,
		encounter_resource.party_hex_positions,
		TEAM_PLAYER
	)
	_append_team_combatants(
		combatants,
		encounter_resource.enemy_resource_paths,
		encounter_resource.enemy_hex_positions,
		TEAM_ENEMY
	)
	return combatants


## _append_team_combatants — builds one Combatant per entry in
## `resource_paths`, appending them to `combatants` in order. Each
## combatant's display name is read from the referenced member resource's
## `name` field (CharacterResource / EnemyResource both expose one); its
## hex_coord is read from `hex_positions[index]` when present, else
## HexCoord(0, 0).
func _append_team_combatants(
	combatants: Array,
	resource_paths: Array,
	hex_positions: Array,
	team: String
) -> void:
	for i in range(resource_paths.size()):
		var member_path: String = resource_paths[i]
		var member_resource = ResourceLoader.load(member_path)
		var display_name: String = member_resource.name if member_resource != null else member_path

		var hex_coord: HexCoordClass = HexCoordClass.new(0, 0)
		if i < hex_positions.size():
			var position: Dictionary = hex_positions[i]
			hex_coord = HexCoordClass.new(position.get("q", 0), position.get("r", 0))

		combatants.append(CombatantClass.new(
			"%s_%d" % [team.to_lower(), i],
			display_name,
			team,
			hex_coord
		))
