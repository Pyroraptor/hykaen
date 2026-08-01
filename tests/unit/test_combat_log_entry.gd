extends GutTest
## tests/unit/core/domain/test_combat_log_entry.gd — FEAT-276 (US-011;
## FR-010)
##
## GUT suite for core/domain/combat_log_entry.gd's CombatLogEntry: a pure
## domain value object, constructed once per resolved cast and handed to
## core/application/ports/combat_log_port.gd's CombatLogPort.emit() by
## core/application/use_cases/resolve_cast_use_case.gd's ResolveCastUseCase.
##
## test_criteria covered (this file's own scope, ahead of the boot-real
## e2e proof in tests/boot/test_fire_bolt_full_cast_e2e_log.gd):
##   1. Every constructor argument round-trips onto the matching field.
##   2. to_dict() snapshots every field.
##   3. Immutability-by-convention: fields are set once in _init() and
##      Array arguments are duplicated, not aliased.
##   4. Domain purity: extends RefCounted only, no engine imports.

const CombatLogEntryClass = preload("res://core/domain/combat_log_entry.gd")


func test_defaults_are_a_cast_resolve_entry_with_no_targets_and_null_outcome_fields() -> void:
	var entry := CombatLogEntryClass.new()

	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "")
	assert_eq(entry.spell_id, "")
	assert_eq(entry.target_ids, [])
	assert_null(entry.hit)
	assert_null(entry.damage_amount)
	assert_null(entry.energy_delta)
	assert_eq(entry.round_number, 0)


func test_constructor_arguments_round_trip_onto_matching_fields_for_a_hit() -> void:
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt",
		["skeleton"], true, 9, null, 1
	)

	assert_eq(entry.event_type, CombatLogEntryClass.EventType.CAST_RESOLVE)
	assert_eq(entry.actor_id, "marigold_1")
	assert_eq(entry.spell_id, "fire_bolt")
	assert_eq(entry.target_ids, ["skeleton"])
	assert_true(entry.hit)
	assert_eq(entry.damage_amount, 9)
	assert_null(entry.energy_delta)
	assert_eq(entry.round_number, 1)


func test_constructor_arguments_round_trip_onto_matching_fields_for_a_miss() -> void:
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt",
		["skeleton"], false, 0, null, 1
	)

	assert_false(entry.hit)
	assert_eq(entry.damage_amount, 0)


func test_to_dict_snapshots_every_field() -> void:
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt",
		["skeleton"], true, 9, null, 2
	)

	assert_eq(entry.to_dict(), {
		"event_type": CombatLogEntryClass.EventType.CAST_RESOLVE,
		"actor_id": "marigold_1",
		"spell_id": "fire_bolt",
		"target_ids": ["skeleton"],
		"hit": true,
		"damage_amount": 9,
		"energy_delta": null,
		"round_number": 2,
		"roll_total": null,
		"damage_type": "",
	})


func test_target_ids_array_is_duplicated_not_aliased() -> void:
	var source_targets: Array = ["skeleton"]
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt", source_targets
	)

	source_targets.append("goblin")

	assert_eq(entry.target_ids, ["skeleton"], "mutating the caller's Array after construction must never leak into the entry")


func test_to_dict_target_ids_is_a_copy_not_the_live_field() -> void:
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt", ["skeleton"]
	)

	var snapshot: Dictionary = entry.to_dict()
	snapshot["target_ids"].append("goblin")

	assert_eq(entry.target_ids, ["skeleton"], "mutating a to_dict() snapshot must never leak back into the entry's own field")


func test_event_type_enum_declares_the_full_closed_cast_vocabulary() -> void:
	assert_eq(CombatLogEntryClass.EventType.CAST_BEGIN, 0)
	assert_eq(CombatLogEntryClass.EventType.CAST_CONTINUE, 1)
	assert_eq(CombatLogEntryClass.EventType.CAST_RESOLVE, 2)
	assert_eq(CombatLogEntryClass.EventType.CAST_CANCELLED, 3)


## ══════════════════════════════════════════════════════════════════════════
## FEAT-001 (US-001; FR-001, FR-002): damage_type field
## ══════════════════════════════════════════════════════════════════════════

func test_damage_type_defaults_to_empty_string_with_no_argument() -> void:
	var entry := CombatLogEntryClass.new()

	assert_eq(entry.damage_type, "")
	assert_eq(entry.to_dict().get("damage_type"), "")


func test_damage_type_defaults_to_empty_string_for_legacy_positional_construction() -> void:
	# Mirrors the exact pre-existing 9-positional-argument call shape used by
	# core/application/use_cases/resolve_cast_use_case.gd before this feature
	# (roll_total as the last argument, no damage_type) -- NFR-001 backward
	# compatibility.
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt",
		["skeleton"], true, 9, null, 1, 18
	)

	assert_eq(entry.roll_total, 18)
	assert_eq(entry.damage_type, "", "a pre-existing caller predating this feature must default damage_type to '' (NFR-001)")
	assert_eq(entry.to_dict().get("damage_type"), "")


func test_damage_type_param_is_stored_and_serialized() -> void:
	var entry := CombatLogEntryClass.new(
		CombatLogEntryClass.EventType.CAST_RESOLVE, "marigold_1", "frost_breath",
		["skeleton"], true, 9, null, 1, 18, "cold"
	)

	assert_eq(entry.damage_type, "cold")
	assert_eq(entry.to_dict().get("damage_type"), "cold")


func test_domain_purity_extends_refcounted_only() -> void:
	# NOTE: `entry is Node` cannot be expressed here — GDScript's static type
	# checker forbids an `is Node` comparison against an unrelated RefCounted
	# hierarchy at parse time (mirrors tests/unit/domain/effects/
	# test_effect_value_objects.gd's identical constraint) — so purity is
	# instead proven by source-text inspection (no "extends Node"/"extends
	# Control" clause) below, matching that file's established convention.
	var entry := CombatLogEntryClass.new()
	assert_true(entry is RefCounted)

	var source: String = FileAccess.get_file_as_string("res://core/domain/combat_log_entry.gd")
	assert_false(source.contains("extends Node"), "CombatLogEntry must never extend Node (ADR-001 domain purity)")
	assert_false(source.contains("extends Control"), "CombatLogEntry must never extend Control (ADR-001 domain purity)")
