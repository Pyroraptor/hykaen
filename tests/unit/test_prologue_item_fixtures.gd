extends GutTest
## tests/unit/test_prologue_item_fixtures.gd
##
## GUT test suite for FEAT-007 (US-007; FR-007 data half; ADR-006
## observability item 2): fixture-loading regression test guarding the six
## data-driven ItemResource .tres fixtures that feed the equipment steel
## thread's exit-point assertions on gram_marx and titus:
##   data/items/staff_gram.tres
##   data/items/ring_channeling.tres
##   data/items/longsword_titus.tres
##   data/items/shield_titus.tres
##   data/items/shortsword_marigold.tres
##   data/items/axe_dwarf.tres
##
## Mirrors the established test_ranged_weapon_fixtures.gd /
## test_item_resource.gd conventions: every fixture is loaded via the
## existing generic Resource loading path (ResourceLoader.load()) — never
## constructed in-memory — so an authoring mistake in the committed .tres
## file itself (not just in the ItemResource script) is caught here.
##
## Test criteria (FEAT-007):
##   - Loading each of the six fixtures yields is_valid()==true and
##     validation_error()==''
##   - staff_gram: slot==MAIN_HAND, two_handed==true, is_implement==true,
##     prepared_spell_id=='fire_bolt', is_charged==true
##   - ring_channeling: slot==RIGHT_RING (EquipmentSlot.RING_1 — see
##     core/model/equipment_slot.gd; the FEAT-001 slot taxonomy names this
##     slot RING_1 rather than RIGHT_RING), is_implement==false,
##     prepared_spell_id=='channel', is_charged==true
##   - All six fixtures have a non-empty, human-readable display_name

const ItemResourceClass = preload("res://core/resources/item_resource.gd")
const EquipmentSlotClass = preload("res://core/model/equipment_slot.gd")

const FIXTURE_PATHS: Array = [
	"res://data/items/staff_gram.tres",
	"res://data/items/ring_channeling.tres",
	"res://data/items/longsword_titus.tres",
	"res://data/items/shield_titus.tres",
	"res://data/items/shortsword_marigold.tres",
	"res://data/items/axe_dwarf.tres",
]


# ── All six fixtures load, are ItemResource, and are valid ────────────────

func test_all_six_fixtures_load_as_valid_item_resources() -> void:
	for path in FIXTURE_PATHS:
		var item = ResourceLoader.load(path)
		assert_not_null(item, "ResourceLoader.load('%s') must return non-null" % path)
		if item == null:
			continue
		assert_is(item, ItemResourceClass, "%s must be an ItemResource" % path)
		assert_true(item.is_valid(), "%s must be valid: %s" % [path, item.validation_error()])
		assert_eq(item.validation_error(), "", "%s validation_error() must be empty" % path)


# ── All six fixtures have a non-empty, human-readable display_name ────────

func test_all_six_fixtures_have_non_empty_display_name() -> void:
	for path in FIXTURE_PATHS:
		var item = ResourceLoader.load(path)
		assert_not_null(item, "ResourceLoader.load('%s') must return non-null" % path)
		if item == null:
			continue
		assert_ne(item.display_name, "", "%s display_name must be non-empty" % path)
		assert_true(
			item.display_name.strip_edges().length() > 0,
			"%s display_name must be human-readable (non-whitespace)" % path
		)


# ── staff_gram ──────────────────────────────────────────────────────────

func test_staff_gram_fields() -> void:
	var item = ResourceLoader.load("res://data/items/staff_gram.tres")
	assert_not_null(item, "staff_gram.tres must load")
	if item == null:
		return
	assert_eq(item.slot, EquipmentSlotClass.MAIN_HAND, "staff_gram.slot must be MAIN_HAND")
	assert_true(item.two_handed, "staff_gram.two_handed must be true")
	assert_true(item.is_implement, "staff_gram.is_implement must be true")
	assert_eq(item.prepared_spell_id, "fire_bolt", "staff_gram.prepared_spell_id must be 'fire_bolt'")
	assert_true(item.is_charged, "staff_gram.is_charged must be true")


# ── ring_channeling ─────────────────────────────────────────────────────

func test_ring_channeling_fields() -> void:
	var item = ResourceLoader.load("res://data/items/ring_channeling.tres")
	assert_not_null(item, "ring_channeling.tres must load")
	if item == null:
		return
	# FEAT-001's EquipmentSlot taxonomy names the ring slots RING_1/RING_2
	# (no RIGHT_RING/LEFT_RING constants exist); RING_1 is the "right ring"
	# slot referenced by the FEAT-007 spec.
	assert_eq(item.slot, EquipmentSlotClass.RING_1, "ring_channeling.slot must be RING_1 (right ring)")
	assert_false(item.is_implement, "ring_channeling.is_implement must be false")
	assert_eq(item.prepared_spell_id, "channel", "ring_channeling.prepared_spell_id must be 'channel'")
	assert_true(item.is_charged, "ring_channeling.is_charged must be true")


# ── longsword_titus / shield_titus (not two-handed; OFF_HAND unblocked) ───

func test_longsword_titus_fields() -> void:
	var item = ResourceLoader.load("res://data/items/longsword_titus.tres")
	assert_not_null(item, "longsword_titus.tres must load")
	if item == null:
		return
	assert_eq(item.slot, EquipmentSlotClass.MAIN_HAND, "longsword_titus.slot must be MAIN_HAND")
	assert_false(item.two_handed, "longsword_titus.two_handed must be false")


func test_shield_titus_fields() -> void:
	var item = ResourceLoader.load("res://data/items/shield_titus.tres")
	assert_not_null(item, "shield_titus.tres must load")
	if item == null:
		return
	assert_eq(item.slot, EquipmentSlotClass.OFF_HAND, "shield_titus.slot must be OFF_HAND")
	assert_false(item.two_handed, "shield_titus.two_handed must be false")


# ── shortsword_marigold / axe_dwarf ────────────────────────────────────────

func test_shortsword_marigold_fields() -> void:
	var item = ResourceLoader.load("res://data/items/shortsword_marigold.tres")
	assert_not_null(item, "shortsword_marigold.tres must load")
	if item == null:
		return
	assert_eq(item.slot, EquipmentSlotClass.MAIN_HAND, "shortsword_marigold.slot must be MAIN_HAND")
	assert_false(item.two_handed, "shortsword_marigold.two_handed must be false")


func test_axe_dwarf_fields() -> void:
	var item = ResourceLoader.load("res://data/items/axe_dwarf.tres")
	assert_not_null(item, "axe_dwarf.tres must load")
	if item == null:
		return
	assert_eq(item.slot, EquipmentSlotClass.MAIN_HAND, "axe_dwarf.slot must be MAIN_HAND")
	assert_false(item.two_handed, "axe_dwarf.two_handed must be false")
