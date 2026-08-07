extends GutTest
## tests/unit/domain/test_spell_area_effect.gd
##
## GUT suite for FEAT-001 (US-001/FR-001, ADR-005 domain purity): the
## domain core/domain/spell.gd Spell value object gains an
## area_effect_radius_ft field plus two pure helper functions —
## is_area_effect() and area_hex_radius() — that the presentation-layer
## SpellActionController (a later feature) will use to branch between
## SCALAR and AREA_SET resolution modes without any AoE-radius math
## leaking out of the domain layer.
##
## Test criteria (FEAT-001):
##   1. area_hex_radius() boundary table (mitigates RISK-003):
##        0ft  -> 0 hex (is_area_effect() == false)
##        15ft -> 3 hex
##        20ft -> 4 hex
##        30ft -> 6 hex
##   2. is_area_effect() returns false when radius==0, true when radius>0.
##   3. Every pre-existing positional-construction call site (i.e. a Spell
##      built WITHOUT passing area_effect_radius_ft) still compiles and
##      defaults the new field to 0 without altering any other field.
##   4. area_effect_radius_ft defaults to 0 for the zero-arg constructor
##      too.

const SpellClass = preload("res://core/domain/spell.gd")
const EffectKindClass = preload("res://core/domain/effects/effect_kind.gd")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: field defaults to 0
# ══════════════════════════════════════════════════════════════════════════

func test_area_effect_radius_ft_defaults_to_zero_with_no_arguments() -> void:
	var spell := SpellClass.new()
	assert_eq(spell.area_effect_radius_ft, 0, "area_effect_radius_ft must default to 0")
	assert_false(spell.is_area_effect(), "a spell with radius 0 must not be an area effect")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: pre-existing legacy positional construction is unaffected
# ══════════════════════════════════════════════════════════════════════════

func test_legacy_positional_construction_without_area_effect_radius_ft_defaults_to_zero() -> void:
	# Mirrors the exact positional-argument shape used by pre-existing
	# callers (e.g. tests/unit/test_resolve_cast_combat_log.gd's
	# _fire_bolt()) that predate this feature and never pass
	# area_effect_radius_ft -- NFR-001 backward compatibility.
	var spell := SpellClass.new(
		"fire_bolt", "Fire Bolt", 2, 0, SpellClass.Defense.REFLEX, 50, "2d8+ATTR", "fire", []
	)
	assert_eq(spell.area_effect_radius_ft, 0, "a spell fixture predating this feature must default area_effect_radius_ft to 0 (NFR-001)")
	assert_false(spell.is_area_effect())
	# Other fields must be entirely unaffected by the new trailing field.
	assert_eq(spell.spell_id, "fire_bolt")
	assert_eq(spell.damage_type, "fire")


func test_area_effect_radius_ft_param_is_stored() -> void:
	var spell := SpellClass.new(
		"fireball", "Fireball", 2, 2, SpellClass.Defense.REFLEX, 100,
		"3d6+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "3d6+ATTR", "type": "fire"}, "", 20
	)
	assert_eq(spell.area_effect_radius_ft, 20, "area_effect_radius_ft constructor argument must be stored")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: is_area_effect()
# ══════════════════════════════════════════════════════════════════════════

func test_is_area_effect_false_when_radius_is_zero() -> void:
	var spell := _make_spell_with_radius(0)
	assert_false(spell.is_area_effect(), "radius 0 must not be an area effect")


func test_is_area_effect_true_when_radius_is_positive() -> void:
	var spell := _make_spell_with_radius(5)
	assert_true(spell.is_area_effect(), "any radius > 0 must be an area effect")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: area_hex_radius() boundary table (RISK-003)
# ══════════════════════════════════════════════════════════════════════════

func test_area_hex_radius_boundary_table() -> void:
	var cases := [
		{"radius_ft": 0, "expected_hex": 0, "expected_is_area_effect": false},
		{"radius_ft": 15, "expected_hex": 3, "expected_is_area_effect": true},
		{"radius_ft": 20, "expected_hex": 4, "expected_is_area_effect": true},
		{"radius_ft": 30, "expected_hex": 6, "expected_is_area_effect": true},
	]
	for case in cases:
		var spell := _make_spell_with_radius(case["radius_ft"])
		assert_eq(
			spell.area_hex_radius(), case["expected_hex"],
			"area_hex_radius() for %dft must be %d hex" % [case["radius_ft"], case["expected_hex"]]
		)
		assert_eq(
			spell.is_area_effect(), case["expected_is_area_effect"],
			"is_area_effect() for %dft must be %s" % [case["radius_ft"], case["expected_is_area_effect"]]
		)


func _make_spell_with_radius(radius_ft: int) -> Object:
	return SpellClass.new(
		"fireball", "Fireball", 2, 2, SpellClass.Defense.REFLEX, 100,
		"3d6+ATTR", "fire", ["Concentrate"], EffectKindClass.DAMAGE,
		{"formula": "3d6+ATTR", "type": "fire"}, "", radius_ft
	)
