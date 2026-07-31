## core/use_cases/prepare_spell_use_case.gd — PrepareSpellUseCase (FEAT-006 / US-006; FR-006)
##
## Application layer (Clean Architecture, ADR-001/ADR-002): depends ONLY on
## the Domain layer (core/model/character_resource.gd's CharacterResource,
## core/resources/item_resource.gd's ItemResource) — never an adapter/
## infrastructure/presentation type, and never the engine scene tree.
## Mirrors EquipItemUseCase/UnequipItemUseCase (core/use_cases/
## equip_item_use_case.gd, core/use_cases/unequip_item_use_case.gd): GDScript
## has no first-class Protocol/interface construct, so this class itself
## acts as both the port (its execute() signature is the contract callers
## program against) and its own sole implementation — no repository port is
## introduced, since no new persistence behavior is required this iteration
## (see ADR-005): the caller is responsible for supplying an already-loaded
## CharacterResource (via the project's existing character-loading adapter)
## and, on success, for persisting any resulting mutation if that is
## desired.
##
## execute(character, slot, spell_id) -> Dictionary — ADR-002 Result-shaped
## Dictionary convention: {ok:true} on success, {ok:false, error:String} on
## failure. Never raises. Validation rules are checked IN ORDER, first
## failure wins (design notes' api_contracts #7):
##   1. no item in slot — character.get_item_in_slot(slot) == null
##   2. (clearing)      — spell_id == "" always succeeds: sets the target
##                         item's prepared_spell_id to "" and is_charged to
##                         false, bypassing the level cap entirely (freeing a
##                         slot can never itself violate the cap).
##   3. prepared spell   — per ADR-006, the number of items ACROSS THIS
##      count exceeds        character's equipped_items that would hold a
##      level                non-empty prepared_spell_id AFTER this
##                            operation must not exceed character.level. If
##                            it would, {ok:false, error:'prepared spell
##                            count (N) exceeds level (L)'} is returned
##                            (N = the resulting count, L = character.level)
##                            and no mutation occurs.
##
## On success (set or clear), the target item's prepared_spell_id/is_charged
## fields are updated and {ok:true} is returned.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name PrepareSpellUseCase
extends RefCounted


## execute(character, slot, spell_id) -> Dictionary — see file-level doc for
## the full contract. A null `character` fails safe to {ok:false, error:'no
## item in slot'} (there is no item to target).
func execute(character, slot: int, spell_id: String) -> Dictionary:
	if character == null:
		return {"ok": false, "error": "no item in slot"}

	var item = character.get_item_in_slot(slot)
	if item == null:
		return {"ok": false, "error": "no item in slot"}

	if spell_id == "":
		item.prepared_spell_id = ""
		item.is_charged = false
		return {"ok": true}

	var prepared_count := 1
	for equipped in character.equipped_items:
		if equipped == item or equipped == null:
			continue
		if equipped.prepared_spell_id != "":
			prepared_count += 1

	if prepared_count > character.level:
		return {
			"ok": false,
			"error": "prepared spell count (%d) exceeds level (%d)" % [prepared_count, character.level],
		}

	item.prepared_spell_id = spell_id
	item.is_charged = true
	return {"ok": true}
