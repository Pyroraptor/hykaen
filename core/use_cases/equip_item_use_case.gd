## core/use_cases/equip_item_use_case.gd — EquipItemUseCase (FEAT-004 / US-004; FR-004)
##
## Application layer (Clean Architecture, ADR-001/ADR-002): depends ONLY on
## the Domain layer (core/model/character_resource.gd's CharacterResource,
## core/model/equipment_slot.gd's EquipmentSlot, core/resources/item_resource.gd's
## ItemResource) — never an adapter/infrastructure/presentation type, and
## never the engine scene tree. GDScript has no first-class Protocol/
## interface construct, so this class itself acts as both the port (its
## execute() signature is the contract callers program against) and its
## own sole implementation — no repository port is introduced, since no new
## persistence behavior is required this iteration (see ADR-005): the
## caller is responsible for supplying an already-loaded CharacterResource/
## ItemResource pair (via the project's existing character-loading adapter)
## and, on success, for persisting any resulting mutation if that is
## desired.
##
## execute(character, item) -> Dictionary — ADR-002 Result-shaped Dictionary
## convention: {ok:true} on success, {ok:false, error:String} on failure.
## Never raises. Validation rules are checked IN ORDER, first failure wins
## (design notes' api_contracts #5):
##   1. invalid slot           — item is null, or item.slot outside [0, 14]
##   2. slot occupied          — character.get_item_in_slot(item.slot) != null
##   3. OFF_HAND blocked        — character.is_slot_blocked(item.slot) == true
##      by two-handed item        (i.e. item.slot == OFF_HAND and the equipped
##                                 MAIN_HAND item has two_handed == true —
##                                 RISK-006's asymmetric blocking rule, see
##                                 CharacterResource.is_slot_blocked())
##   4. two-handed item requires — item.two_handed == true and OFF_HAND is
##      empty OFF_HAND              already occupied by another item
##
## On success, `item` is appended to character.equipped_items (the sole
## mutation this use case performs) and {ok:true} is returned.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name EquipItemUseCase
extends RefCounted

const _EquipmentSlot = preload("res://core/model/equipment_slot.gd")


## execute(character, item) -> Dictionary — see file-level doc for the full
## contract. A null `character` fails safe to {ok:false, error:'invalid slot'}
## (there is no valid character to equip onto).
func execute(character, item) -> Dictionary:
	if character == null or item == null:
		return {"ok": false, "error": "invalid slot"}

	if item.slot < 0 or item.slot > 14:
		return {"ok": false, "error": "invalid slot"}

	if character.get_item_in_slot(item.slot) != null:
		return {"ok": false, "error": "slot occupied"}

	if character.is_slot_blocked(item.slot):
		return {"ok": false, "error": "OFF_HAND blocked by two-handed item"}

	if item.two_handed and character.get_item_in_slot(_EquipmentSlot.OFF_HAND) != null:
		return {"ok": false, "error": "two-handed item requires empty OFF_HAND"}

	character.equipped_items.append(item)
	return {"ok": true}
