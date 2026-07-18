extends GutTest
## tests/unit/test_effect_value_objects.gd
##
## GUT suite for FEAT-001 (US-001): the domain Effect value-object family
## (core/domain/effect.gd + effect_kind.gd + the five concrete subtypes
## DamageEffect/HealEffect/ConditionEffect/MoveEffect/AddEnergyEffect).
##
## Verifies (test_criteria):
##   1. DamageEffect/HealEffect construction rejects amount<=0 at _init time.
##   2. ConditionEffect/MoveEffect reject empty target_id / out-of-bounds hex
##      at construction.
##   3. Each Effect subtype exposes the correct EffectKind discriminator.
##   4. The domain-purity CI check (ci/check_domain_purity.sh) passes for
##      core/domain/effect*.gd — no engine/UI imports detected.
##   5. Effect base class extends RefCounted only, no Node/scene-tree
##      dependency.
##
## GDScript's _init() cannot refuse to hand back an instance (no
## constructor-level exception mechanism), so "rejects ... at construction"
## is expressed via Effect.is_valid()/validation_error() flipping false the
## moment _init() detects an invariant violation (see core/domain/effect.gd's
## file-level doc) — the SAME testable-state convention this codebase
## already uses elsewhere in place of relying on push_error capture, which
## is unreliable on this project's Godot 4.3 engine (see
## tests/unit/test_action_economy.gd's
## test_start_of_turn_null_combatant_guard_no_ops_and_logs_error()).

const EffectClass          = preload("res://core/domain/effect.gd")
const EffectKindClass      = preload("res://core/domain/effect_kind.gd")
const DamageEffectClass    = preload("res://core/domain/damage_effect.gd")
const HealEffectClass      = preload("res://core/domain/heal_effect.gd")
const ConditionEffectClass = preload("res://core/domain/condition_effect.gd")
const MoveEffectClass      = preload("res://core/domain/move_effect.gd")
const AddEnergyEffectClass = preload("res://core/domain/add_energy_effect.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")

const DOMAIN_PURITY_SCRIPT: String = "res://ci/check_domain_purity.sh"

const EFFECT_SOURCE_PATHS: Array = [
	"res://core/domain/effect.gd",
	"res://core/domain/effect_kind.gd",
	"res://core/domain/damage_effect.gd",
	"res://core/domain/heal_effect.gd",
	"res://core/domain/condition_effect.gd",
	"res://core/domain/move_effect.gd",
	"res://core/domain/add_energy_effect.gd",
]


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: DamageEffect/HealEffect reject amount<=0 at construction
# ══════════════════════════════════════════════════════════════════════════

func test_damage_effect_accepts_positive_amount() -> void:
	var e := DamageEffectClass.new("enemy_0", 6)
	assert_true(e.is_valid(), "amount=6 is a valid DamageEffect")
	assert_eq(e.amount, 6)
	assert_eq(e.target_id, "enemy_0")


func test_damage_effect_rejects_zero_amount() -> void:
	var e := DamageEffectClass.new("enemy_0", 0)
	assert_false(e.is_valid(), "amount=0 must be rejected at construction")
	assert_ne(e.validation_error(), "", "a rejected DamageEffect must record a reason")


func test_damage_effect_rejects_negative_amount() -> void:
	var e := DamageEffectClass.new("enemy_0", -3)
	assert_false(e.is_valid(), "a negative amount must be rejected at construction")


func test_heal_effect_accepts_positive_amount() -> void:
	var e := HealEffectClass.new("player_0", 8)
	assert_true(e.is_valid(), "amount=8 is a valid HealEffect")
	assert_eq(e.amount, 8)


func test_heal_effect_rejects_zero_amount() -> void:
	var e := HealEffectClass.new("player_0", 0)
	assert_false(e.is_valid(), "amount=0 must be rejected at construction")


func test_heal_effect_rejects_negative_amount() -> void:
	var e := HealEffectClass.new("player_0", -1)
	assert_false(e.is_valid(), "a negative amount must be rejected at construction")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: ConditionEffect/MoveEffect reject empty target_id /
# out-of-bounds hex at construction
# ══════════════════════════════════════════════════════════════════════════

func test_condition_effect_accepts_valid_construction() -> void:
	var e := ConditionEffectClass.new("enemy_0", "Off-Guard", true)
	assert_true(e.is_valid())
	assert_eq(e.condition, "Off-Guard")
	assert_true(e.add)


func test_condition_effect_rejects_empty_target_id() -> void:
	var e := ConditionEffectClass.new("", "Off-Guard", true)
	assert_false(e.is_valid(), "an empty target_id must be rejected at construction")


func test_condition_effect_rejects_empty_condition() -> void:
	var e := ConditionEffectClass.new("enemy_0", "", true)
	assert_false(e.is_valid(), "an empty condition tag must be rejected at construction")


func test_move_effect_accepts_in_bounds_hex() -> void:
	var e := MoveEffectClass.new("player_0", HexCoordClass.new(2, -1))
	assert_true(e.is_valid())
	assert_eq(e.hex.q, 2)
	assert_eq(e.hex.r, -1)


func test_move_effect_rejects_empty_target_id() -> void:
	var e := MoveEffectClass.new("", HexCoordClass.new(0, 0))
	assert_false(e.is_valid(), "an empty target_id must be rejected at construction")


func test_move_effect_rejects_out_of_bounds_hex() -> void:
	var e := MoveEffectClass.new("player_0", HexCoordClass.new(99, 99))
	assert_false(e.is_valid(), "a hex far outside the board radius must be rejected at construction")


func test_move_effect_rejects_null_hex() -> void:
	var e := MoveEffectClass.new("player_0", null)
	assert_false(e.is_valid(), "a null hex must be rejected at construction")


func test_move_effect_accepts_hex_exactly_at_board_radius() -> void:
	var e := MoveEffectClass.new("player_0", HexCoordClass.new(MoveEffectClass.BOARD_RADIUS, 0))
	assert_true(e.is_valid(), "a hex exactly at BOARD_RADIUS must be in-bounds (inclusive)")


func test_move_effect_rejects_hex_one_past_board_radius() -> void:
	var e := MoveEffectClass.new("player_0", HexCoordClass.new(MoveEffectClass.BOARD_RADIUS + 1, 0))
	assert_false(e.is_valid(), "a hex one past BOARD_RADIUS must be out-of-bounds")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: each Effect subtype exposes the correct EffectKind
# discriminator
# ══════════════════════════════════════════════════════════════════════════

func test_damage_effect_kind_discriminator() -> void:
	assert_eq(DamageEffectClass.new("t", 1).kind, EffectKindClass.DAMAGE)


func test_heal_effect_kind_discriminator() -> void:
	assert_eq(HealEffectClass.new("t", 1).kind, EffectKindClass.HEAL)


func test_condition_effect_kind_discriminator() -> void:
	assert_eq(ConditionEffectClass.new("t", "Off-Guard", true).kind, EffectKindClass.CONDITION)


func test_move_effect_kind_discriminator() -> void:
	assert_eq(MoveEffectClass.new("t", HexCoordClass.new(0, 0)).kind, EffectKindClass.MOVE)


func test_add_energy_effect_kind_discriminator() -> void:
	assert_eq(AddEnergyEffectClass.new("t", 1).kind, EffectKindClass.ADD_ENERGY)


func test_effect_kinds_are_pairwise_distinct() -> void:
	var kinds: Array = [
		EffectKindClass.DAMAGE,
		EffectKindClass.CONDITION,
		EffectKindClass.MOVE,
		EffectKindClass.HEAL,
		EffectKindClass.ADD_ENERGY,
	]
	var seen := {}
	for k in kinds:
		assert_false(seen.has(k), "EffectKind values must be pairwise distinct")
		seen[k] = true


# ══════════════════════════════════════════════════════════════════════════
# AddEnergyEffect (reserved, unused this sprint) — same amount>0 invariant
# ══════════════════════════════════════════════════════════════════════════

func test_add_energy_effect_accepts_positive_amount() -> void:
	var e := AddEnergyEffectClass.new("player_0", 3)
	assert_true(e.is_valid())
	assert_eq(e.amount, 3)


func test_add_energy_effect_rejects_zero_amount() -> void:
	var e := AddEnergyEffectClass.new("player_0", 0)
	assert_false(e.is_valid(), "amount=0 must be rejected at construction")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5: Effect base class extends RefCounted only, no Node/scene-tree
# dependency — every Effect source file is scanned, matching this
# codebase's established domain-purity test convention (see
# tests/unit/core/domain/test_mobility_dodge_rule.gd's
# test_source_is_domain_pure()).
# ══════════════════════════════════════════════════════════════════════════

func test_effect_base_extends_refcounted_only() -> void:
	var e := EffectClass.new(EffectKindClass.DAMAGE, "t")
	assert_true(e is RefCounted, "Effect must be a RefCounted, not a Node/Control")
	# NOTE: `e is Node` cannot be expressed here — GDScript's static type
	# checker statically rejects `is` comparisons between unrelated class
	# hierarchies (Effect extends RefCounted; Node is a disjoint branch),
	# failing this file's own parse rather than the assertion at runtime.
	# get_class() is the runtime-safe equivalent: a RefCounted-only script
	# with no Node ancestor always reports "RefCounted" here.
	assert_eq(e.get_class(), "RefCounted", "Effect must never be a Node (ADR-001 domain purity)")


func test_all_effect_source_files_are_domain_pure() -> void:
	for path in EFFECT_SOURCE_PATHS:
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "%s must be readable" % path)
		if f == null:
			continue
		var content: String = f.get_as_text()
		f.close()

		assert_false(
			content.contains("extends Node"),
			"%s must not extend Node (ADR-001)" % path
		)
		assert_false(
			content.contains("extends Control"),
			"%s must not extend Control (ADR-001)" % path
		)
		assert_false(
			content.contains("extends CanvasItem"),
			"%s must not extend CanvasItem (ADR-001)" % path
		)
		assert_false(
			content.contains("preload(\"res://core/application") or content.contains("extends \"res://core/application"),
			"%s must not import from the application layer (ADR-001 inward-only dependency rule)" % path
		)
		assert_false(
			content.contains("preload(\"res://presentation") or content.contains("extends \"res://presentation"),
			"%s must not import from the presentation layer (ADR-001 inward-only dependency rule)" % path
		)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: the domain-purity CI check passes for core/domain/effect*.gd
# — a real subprocess invocation of ci/check_domain_purity.sh, mirroring
# tests/ci/test_static_checks.gd's established convention (OS.execute
# against the real script, never a re-implementation of its logic).
# ══════════════════════════════════════════════════════════════════════════

func test_domain_purity_check_passes_scoped_to_core_domain() -> void:
	var absolute_script_path: String = ProjectSettings.globalize_path(DOMAIN_PURITY_SCRIPT)
	var absolute_target_dir: String = ProjectSettings.globalize_path("res://core/domain")
	var out: Array = []
	var rc: int = OS.execute("bash", [absolute_script_path, absolute_target_dir], out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)
	assert_eq(
		rc, 0,
		"ci/check_domain_purity.sh must exit 0 for core/domain (which now includes effect*.gd); output: %s" % combined_output
	)
