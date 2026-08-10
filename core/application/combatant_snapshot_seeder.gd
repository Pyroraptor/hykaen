## core/application/combatant_snapshot_seeder.gd — CombatantSnapshotSeeder
##
## Application layer: static helpers for restoring persisted combatant state
## (hex positions and HP/stamina/conditions) from saved game-state data into
## live combatant arrays at boot.  Extracted from MainScene._ready() (the
## former _seed_party_hex_positions_from_current_game_state(),
## _seed_combatant_snapshots_from_current_game_state(), and
## _combatant_snapshot_entry_is_well_formed() methods) to keep the
## composition root free of implementation detail.
##
## seed_hex_positions(hex_combatants, party, positions) -> void
##   Applies saved party_hex_positions entries to both hex_combatants and
##   party arrays.  Unknown combatant_ids are warned and skipped.
##
## seed_snapshots(hex_combatants, party, enemies, snapshots) -> void
##   Applies saved combatant_snapshots (hp_current / stamina / conditions)
##   to any combatant whose display_id matches an entry.  Malformed entries
##   are warned and skipped without mutating any combatant.

class_name CombatantSnapshotSeeder
extends RefCounted

const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


static func seed_hex_positions(hex_combatants: Array, party: Array, positions: Array) -> void:
	if positions.is_empty():
		return
	for entry in positions:
		var id: String = String(entry.get("combatant_id", ""))
		var hex       := HexCoordClass.new(int(entry.get("q", 0)), int(entry.get("r", 0)))
		var found     := false
		for c in hex_combatants:
			if c.combatant_id == id:
				c.move_to(hex)
				found = true
				break
		if not found:
			push_warning("CombatantSnapshotSeeder: party_hex_positions entry references combatant_id '%s' not present in the live encounter -- skipped" % id)
			continue
		for c in party:
			if c.display_id() == id:
				c.move_to(hex)
				break


static func seed_snapshots(hex_combatants: Array, party: Array, enemies: Array, snapshots: Array) -> void:
	if snapshots.is_empty():
		return
	var all_combatants: Array = hex_combatants + party + enemies
	for entry in snapshots:
		var id: String     = String(entry.get("combatant_id", ""))
		var matches: Array = []
		for c in all_combatants:
			if c.display_id() == id:
				matches.append(c)
		if matches.is_empty():
			push_warning("CombatantSnapshotSeeder: combatant_snapshots entry references combatant_id '%s' not present in the live encounter -- skipped" % id)
			continue
		if not _entry_is_well_formed(entry, id):
			continue
		for c in matches:
			if entry.has("hp_current"):
				c.hp_current = int(entry["hp_current"])
			if entry.has("stamina"):
				c.stamina = int(entry["stamina"])
			if entry.has("conditions"):
				c.conditions = (entry["conditions"] as Array).duplicate()


static func _entry_is_well_formed(entry: Dictionary, combatant_id: String) -> bool:
	if entry.has("hp_current") and not (entry["hp_current"] is int or entry["hp_current"] is float):
		push_warning("CombatantSnapshotSeeder: combatant_snapshots entry for combatant_id '%s' has malformed hp_current (expected a number) -- entry rejected" % combatant_id)
		return false
	if entry.has("stamina") and not (entry["stamina"] is int or entry["stamina"] is float):
		push_warning("CombatantSnapshotSeeder: combatant_snapshots entry for combatant_id '%s' has malformed stamina (expected a number) -- entry rejected" % combatant_id)
		return false
	if entry.has("conditions") and not (entry["conditions"] is Array):
		push_warning("CombatantSnapshotSeeder: combatant_snapshots entry for combatant_id '%s' has malformed conditions (expected an Array) -- entry rejected" % combatant_id)
		return false
	return true
