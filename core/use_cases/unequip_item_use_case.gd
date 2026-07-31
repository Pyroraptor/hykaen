## core/use_cases/unequip_item_use_case.gd — UnequipItemUseCase (FEAT-005 / US-005; FR-005)
##
## Application layer (Clean Architecture, ADR-001/ADR-002): depends ONLY on
## the Domain layer (core/model/character_resource.gd's CharacterResource) —
## never an adapter/infrastructure/presentation type, and never the engine
## scene tree. Mirrors EquipItemUseCase (core/use_cases/equip_item_use_case.gd,
## FEAT-004): GDScript has no first-class Protocol/interface construct, so
## this class itself acts as both the port (its execute() signature is the
## contract callers program against) and its own sole implementation — no
## repository port is introduced, since no new persistence behavior is
## required this iteration (see ADR-005): the caller is responsible for
## supplying an already-loaded CharacterResource and, on success, for
## persisting any resulting mutation if that is desired.
##
## execute(character, slot) -> Dictionary — ADR-002 Result-shaped Dictionary
## convention: {ok:true, item:ItemResource} on success, {ok:false,
## error:String} on failure. Never raises (design notes' api_contracts #6):
##   - slot occupied -> the ItemResource is removed from
##     character.equipped_items and returned as {ok:true, item:<ItemResource>}
##   - slot empty    -> {ok:false, error:'slot empty'}
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name UnequipItemUseCase
extends RefCounted


## execute(character, slot) -> Dictionary — see file-level doc for the full
## contract. A null `character` or a slot with nothing equipped both fail
## safe to {ok:false, error:'slot empty'} (there is no item to remove).
func execute(character, slot: int) -> Dictionary:
	if character == null:
		return {"ok": false, "error": "slot empty"}

	var item = character.get_item_in_slot(slot)
	if item == null:
		return {"ok": false, "error": "slot empty"}

	character.equipped_items.erase(item)
	return {"ok": true, "item": item}
