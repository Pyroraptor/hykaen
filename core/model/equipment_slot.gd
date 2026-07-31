## core/model/equipment_slot.gd — EquipmentSlot value object (FEAT-001 / US-001)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O, and no
## `extends` at all — a stateless namespace of int constants + one static
## lookup function, matching the existing pure-value-object/pure-function
## convention established by core/geometry/hex_math.gd (class_name only,
## no extends) and core/rules/attributes.gd's constant tables.
##
## Defines the 15-slot equipment taxonomy for a CharacterResource's
## `equipped_items` (see core/model/character_resource.gd, FEAT-002+):
## MAIN_HAND, OFF_HAND, HEAD, NECK, SHOULDERS, CHEST, BACK, HANDS, WAIST,
## LEGS, FEET, RING_1, RING_2, ACCESSORY_1, ACCESSORY_2.
##
## ALL_SLOTS is the canonical ordering used by EquipmentPanelUI (a future
## Presentation-layer consumer) to render one row per slot, and by
## use cases/tests that need to iterate every defined slot.
##
## slot_name(slot: int) -> String returns the human-readable label for a
## given slot constant (e.g. slot_name(MAIN_HAND) == "Main Hand"). Per the
## API contract (design notes, contract #1), an out-of-range slot value
## returns a non-crashing fallback string rather than raising an error.
##
## Usage:
##   for slot in EquipmentSlot.ALL_SLOTS:
##       var label := EquipmentSlot.slot_name(slot)

class_name EquipmentSlot

## Individual slot constants — slot_value INT PK in [0, 14] (see design
## notes' data model). Values are the slot's fixed position in ALL_SLOTS;
## do not renumber without updating any persisted .tres data that stores a
## raw int (none exist yet as of this feature).
const MAIN_HAND: int = 0
const OFF_HAND: int = 1
const HEAD: int = 2
const NECK: int = 3
const SHOULDERS: int = 4
const CHEST: int = 5
const BACK: int = 6
const HANDS: int = 7
const WAIST: int = 8
const LEGS: int = 9
const FEET: int = 10
const RING_1: int = 11
const RING_2: int = 12
const ACCESSORY_1: int = 13
const ACCESSORY_2: int = 14

## Canonical ordering of all 15 defined slots — no duplicates. This is the
## order EquipmentPanelUI iterates to render one row per slot.
const ALL_SLOTS: Array = [
	MAIN_HAND,
	OFF_HAND,
	HEAD,
	NECK,
	SHOULDERS,
	CHEST,
	BACK,
	HANDS,
	WAIST,
	LEGS,
	FEET,
	RING_1,
	RING_2,
	ACCESSORY_1,
	ACCESSORY_2,
]

## Human-readable label per slot constant, functionally dependent only on
## slot_value (3NF — see design notes' data model).
const _SLOT_NAMES: Dictionary = {
	MAIN_HAND: "Main Hand",
	OFF_HAND: "Off Hand",
	HEAD: "Head",
	NECK: "Neck",
	SHOULDERS: "Shoulders",
	CHEST: "Chest",
	BACK: "Back",
	HANDS: "Hands",
	WAIST: "Waist",
	LEGS: "Legs",
	FEET: "Feet",
	RING_1: "Ring 1",
	RING_2: "Ring 2",
	ACCESSORY_1: "Accessory 1",
	ACCESSORY_2: "Accessory 2",
}


## slot_name(slot: int) -> String
##
## Returns the human-readable label for `slot`. Never raises — an
## out-of-range/undefined slot value returns a non-empty fallback string
## instead of crashing (API contract #1, design notes).
static func slot_name(slot: int) -> String:
	return _SLOT_NAMES.get(slot, "Unknown Slot")
