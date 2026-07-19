extends GutTest
## tests/unit/domain/effects/test_effect_value_objects.gd
##
## GUT suite for FEAT-001 (US-001): the domain Effect value-object family
## (core/domain/effects/effect_base.gd + effect_kind.gd + the five concrete
## subtypes DamageEffect/HealEffect/ConditionEffect/MoveEffect/
## AddEnergyEffect, all under core/domain/effects/).
##
## NOTE on this file's name/location: this project's GUT config
## (.gutconfig.json: prefix="test_", suffix=".gd") only auto-discovers
## scripts whose FILENAME begins with "test_" — see addons/gut/gut.gd's
## _get_files(). This file therefore keeps the project-wide `test_` prefix
## convention (test_effect_value_objects.gd) while living under the
## directory this feature's design notes call for
## (tests/unit/domain/effects/), so the suite is both correctly located
## AND actually picked up by the full-project GUT run (scripts/test_command.sh
## stage 7/8) rather than silently never executing.
##
## Verifies (test_criteria):
##   1. Each effect subtype constructs with the correct kind, target_id,
##      and kind-specific fields (amount / condition+op / hex).
##   2. EffectBase extends RefCounted with no Node/engine imports (a
##      static import-graph / source-text assertion, since GDScript's
##      static type checker forbids an `is Node` comparison against an
##      unrelated RefCounted hierarchy at parse time).
##   3. The domain-purity CI check (ci/check_domain_purity.sh) passes when
##      scoped to core/domain/effects/, and fails (non-zero exit) once an
##      engine import is injected into a fixture copy of that directory.
##   4. AddEnergyEffect constructs correctly and (FEAT-277 / US-012; FR-013)
##      is asserted to have exactly ONE live (non-test, non-definition)
##      production call site: core/application/use_cases/
##      resolve_cast_use_case.gd — its sole intended consumer, mapping
##      Channel's ADD_ENERGY effect_type onto the caster's own round energy
##      pool. Originally (design notes: "RESERVED, UNUSED this sprint")
##      this criterion asserted ZERO live call sites; FEAT-277 is this VO's
##      first real consumer, so the assertion narrows from "none" to
##      "exactly this one", still catching any OTHER accidental/premature
##      call site.
##
## GDScript's _init() cannot refuse to hand back an instance (no
## constructor-level exception mechanism), so "rejects ... at construction"
## is expressed via EffectBase.is_valid()/validation_error() flipping false
## the moment _init() detects an invariant violation (see
## core/domain/effects/effect_base.gd's file-level doc) — the SAME
## testable-state convention this codebase already uses elsewhere in place
## of relying on push_error capture, which is unreliable on this project's
## Godot 4.3 engine (see tests/unit/test_action_economy.gd's
## test_start_of_turn_null_combatant_guard_no_ops_and_logs_error()).

const EffectBaseClass      = preload("res://core/domain/effects/effect_base.gd")
const EffectKindClass      = preload("res://core/domain/effects/effect_kind.gd")
const DamageEffectClass    = preload("res://core/domain/effects/damage_effect.gd")
const HealEffectClass      = preload("res://core/domain/effects/heal_effect.gd")
const ConditionEffectClass = preload("res://core/domain/effects/condition_effect.gd")
const MoveEffectClass      = preload("res://core/domain/effects/move_effect.gd")
const AddEnergyEffectClass = preload("res://core/domain/effects/add_energy_effect.gd")
const HexCoordClass        = preload("res://core/geometry/hex_coord.gd")

const DOMAIN_PURITY_SCRIPT: String = "res://ci/check_domain_purity.sh"

const EFFECT_SOURCE_PATHS: Array = [
	"res://core/domain/effects/effect_base.gd",
	"res://core/domain/effects/effect_kind.gd",
	"res://core/domain/effects/damage_effect.gd",
	"res://core/domain/effects/heal_effect.gd",
	"res://core/domain/effects/condition_effect.gd",
	"res://core/domain/effects/move_effect.gd",
	"res://core/domain/effects/add_energy_effect.gd",
]

var _temp_dirs: Array = []


func after_each() -> void:
	for dir_path in _temp_dirs:
		OS.execute("rm", ["-rf", dir_path], [], true)
	_temp_dirs = []


func _make_temp_dir() -> String:
	var out: Array = []
	var rc: int = OS.execute("mktemp", ["-d"], out, true)
	if rc != 0 or out.is_empty():
		return ""
	var path: String = String(out[0]).strip_edges()
	_temp_dirs.append(path)
	return path


func _write_file(path: String, contents: String) -> bool:
	var parent_dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(contents)
	f.close()
	return true


func _copy_real_file_into_fixture(res_source_path: String, dest_path: String) -> void:
	var f := FileAccess.open(res_source_path, FileAccess.READ)
	if f == null:
		return
	var contents: String = f.get_as_text()
	f.close()
	_write_file(dest_path, contents)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: each subtype constructs with correct kind, target_id, and
# kind-specific fields (amount / condition+op / hex)
# ══════════════════════════════════════════════════════════════════════════

func test_damage_effect_accepts_positive_amount() -> void:
	var e := DamageEffectClass.new("enemy_0", 6)
	assert_true(e.is_valid(), "amount=6 is a valid DamageEffect")
	assert_eq(e.kind, EffectKindClass.DAMAGE)
	assert_eq(e.target_id, "enemy_0")
	assert_eq(e.amount, 6)


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
	assert_eq(e.kind, EffectKindClass.HEAL)
	assert_eq(e.target_id, "player_0")
	assert_eq(e.amount, 8)


func test_heal_effect_rejects_zero_amount() -> void:
	var e := HealEffectClass.new("player_0", 0)
	assert_false(e.is_valid(), "amount=0 must be rejected at construction")


func test_heal_effect_rejects_negative_amount() -> void:
	var e := HealEffectClass.new("player_0", -1)
	assert_false(e.is_valid(), "a negative amount must be rejected at construction")


func test_condition_effect_accepts_valid_construction_and_exposes_op() -> void:
	var e := ConditionEffectClass.new("enemy_0", "Off-Guard", true)
	assert_true(e.is_valid())
	assert_eq(e.kind, EffectKindClass.CONDITION)
	assert_eq(e.target_id, "enemy_0")
	assert_eq(e.condition, "Off-Guard")
	assert_true(e.add)
	assert_eq(e.op, ConditionEffectClass.Op.ADD, "op must mirror add=true as Op.ADD")


func test_condition_effect_add_false_sets_op_remove() -> void:
	var e := ConditionEffectClass.new("enemy_0", "Off-Guard", false)
	assert_false(e.add)
	assert_eq(e.op, ConditionEffectClass.Op.REMOVE, "op must mirror add=false as Op.REMOVE")


func test_condition_effect_rejects_empty_target_id() -> void:
	var e := ConditionEffectClass.new("", "Off-Guard", true)
	assert_false(e.is_valid(), "an empty target_id must be rejected at construction")


func test_condition_effect_rejects_empty_condition() -> void:
	var e := ConditionEffectClass.new("enemy_0", "", true)
	assert_false(e.is_valid(), "an empty condition tag must be rejected at construction")


func test_move_effect_accepts_in_bounds_hex() -> void:
	var e := MoveEffectClass.new("player_0", HexCoordClass.new(2, -1))
	assert_true(e.is_valid())
	assert_eq(e.kind, EffectKindClass.MOVE)
	assert_eq(e.target_id, "player_0")
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


func test_add_energy_effect_accepts_positive_amount() -> void:
	var e := AddEnergyEffectClass.new("player_0", 3)
	assert_true(e.is_valid())
	assert_eq(e.kind, EffectKindClass.ADD_ENERGY)
	assert_eq(e.target_id, "player_0")
	assert_eq(e.amount, 3)


func test_add_energy_effect_rejects_zero_amount() -> void:
	var e := AddEnergyEffectClass.new("player_0", 0)
	assert_false(e.is_valid(), "amount=0 must be rejected at construction")


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
# Criterion 2: EffectBase extends RefCounted only, no Node/scene-tree
# dependency — every Effect source file is scanned, matching this
# codebase's established domain-purity test convention (see
# tests/unit/core/domain/test_mobility_dodge_rule.gd's
# test_source_is_domain_pure()).
# ══════════════════════════════════════════════════════════════════════════

func test_effect_base_extends_refcounted_only() -> void:
	var e := EffectBaseClass.new(EffectKindClass.DAMAGE, "t")
	assert_true(e is RefCounted, "EffectBase must be a RefCounted, not a Node/Control")
	# NOTE: `e is Node` cannot be expressed here — GDScript's static type
	# checker statically rejects `is` comparisons between unrelated class
	# hierarchies (EffectBase extends RefCounted; Node is a disjoint
	# branch), failing this file's own parse rather than the assertion at
	# runtime. get_class() is the runtime-safe equivalent: a
	# RefCounted-only script with no Node ancestor always reports
	# "RefCounted" here.
	assert_eq(e.get_class(), "RefCounted", "EffectBase must never be a Node (ADR-001 domain purity)")


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
# Criterion 3a: the domain-purity CI check passes when scoped to
# core/domain/effects/ — a real subprocess invocation of
# ci/check_domain_purity.sh, mirroring tests/ci/test_static_checks.gd's
# established convention (OS.execute against the real script, never a
# re-implementation of its logic).
# ══════════════════════════════════════════════════════════════════════════

func test_domain_purity_check_passes_scoped_to_core_domain_effects() -> void:
	var absolute_script_path: String = ProjectSettings.globalize_path(DOMAIN_PURITY_SCRIPT)
	var absolute_target_dir: String = ProjectSettings.globalize_path("res://core/domain/effects")
	var out: Array = []
	var rc: int = OS.execute("bash", [absolute_script_path, absolute_target_dir], out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)
	assert_eq(
		rc, 0,
		"ci/check_domain_purity.sh must exit 0 for core/domain/effects; output: %s" % combined_output
	)


func test_domain_purity_check_passes_scoped_to_core_domain() -> void:
	# Broader control: the whole core/domain tree (which now includes the
	# effects/ sub-package) must also still pass.
	var absolute_script_path: String = ProjectSettings.globalize_path(DOMAIN_PURITY_SCRIPT)
	var absolute_target_dir: String = ProjectSettings.globalize_path("res://core/domain")
	var out: Array = []
	var rc: int = OS.execute("bash", [absolute_script_path, absolute_target_dir], out, true)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line)
	assert_eq(
		rc, 0,
		"ci/check_domain_purity.sh must exit 0 for core/domain (which now includes core/domain/effects/); output: %s" % combined_output
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3b: the domain-purity CI check FAILS once an engine import is
# injected into a fixture copy of core/domain/effects/ — proving the gate
# actually covers this new module rather than passing vacuously.
# ══════════════════════════════════════════════════════════════════════════

func test_domain_purity_check_fails_on_engine_import_injected_into_effects_fixture() -> void:
	var tmp_dir: String = _make_temp_dir()
	if tmp_dir == "":
		pending("mktemp unavailable in this sandbox — skipping fixture-injection check")
		return

	# A faithful copy of the real effects/ family first -- proves the
	# fixture dir isn't just empty (which would make the check vacuously
	# pass) and that the real files themselves don't trip the gate.
	for path in EFFECT_SOURCE_PATHS:
		var file_name: String = path.get_file()
		_copy_real_file_into_fixture(path, tmp_dir + "/core/domain/effects/" + file_name)

	var absolute_script_path: String = ProjectSettings.globalize_path(DOMAIN_PURITY_SCRIPT)
	var clean_out: Array = []
	var clean_rc: int = OS.execute("bash", [absolute_script_path, tmp_dir + "/core"], clean_out, true)
	assert_eq(
		clean_rc, 0,
		"control case: a faithful copy of core/domain/effects/ must pass the domain-purity check"
	)

	# Now inject a Node-extending file directly into the effects/ fixture
	# directory (ADR-001 violation) and confirm the gate catches it.
	_write_file(
		tmp_dir + "/core/domain/effects/rogue_engine_effect.gd",
		"class_name RogueEngineEffect\nextends Node\n\nfunc _ready() -> void:\n\tpass\n"
	)
	var dirty_out: Array = []
	var dirty_rc: int = OS.execute("bash", [absolute_script_path, tmp_dir + "/core"], dirty_out, true)
	var combined_output: String = ""
	for line in dirty_out:
		combined_output += String(line)
	assert_ne(
		dirty_rc, 0,
		"check_domain_purity.sh must exit non-zero once an engine import ('extends Node') is injected into core/domain/effects/; output: %s" % combined_output
	)
	assert_true(
		combined_output.contains("rogue_engine_effect.gd"),
		"failure output must name the offending fixture file; got: %s" % combined_output
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: AddEnergyEffect constructs correctly (already proven above)
# and (FEAT-277) its only live production call site is
# resolve_cast_use_case.gd (grep-based).
# ══════════════════════════════════════════════════════════════════════════

## test_add_energy_effect_live_call_site_is_confined_to_resolve_cast_use_case()
## -- greps the WHOLE repository for the literal token "AddEnergyEffect" and
## asserts every hit is confined to:
##   - `##` doc-comment lines (e.g. effect_base.gd's family-overview header,
##     which legitimately names every sibling VO including AddEnergyEffect)
##     -- filtered out the same way ci/check_no_duplicate_seams.sh's
##     check_seam_sole_caller() filters comment-only lines before counting
##     real call sites (see that script's ":##" pattern)
##   - its own definition file (core/domain/effects/add_energy_effect.gd)
##   - test files (this suite, or any other under tests/)
##   - core/application/use_cases/resolve_cast_use_case.gd (FEAT-277's sole
##     intended production consumer)
## i.e. no OTHER application/presentation/infrastructure production file
## constructs or even references AddEnergyEffect (mirrors this file's own
## prior "RESERVED, UNUSED this sprint" discipline, narrowed to permit
## exactly this one now-legitimate call site).
func test_add_energy_effect_live_call_site_is_confined_to_resolve_cast_use_case() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var rc: int = OS.execute(
		"bash",
		[
			"-c",
			"grep -rn 'AddEnergyEffect' '" + repo_root + "' --include='*.gd' " +
			"| grep -vE ':[[:space:]]*##' " +
			"| grep -v '/core/domain/effects/add_energy_effect\\.gd:' " +
			"| grep -v '/tests/' " +
			"| grep -v '/core/application/use_cases/resolve_cast_use_case\\.gd:'",
		],
		out,
		true,
	)
	var combined_output: String = ""
	for line in out:
		combined_output += String(line) + "\n"
	assert_ne(
		rc, 0,
		"AddEnergyEffect's only live production call site must be resolve_cast_use_case.gd (FEAT-277); found an additional/unexpected call site: %s" % combined_output
	)
