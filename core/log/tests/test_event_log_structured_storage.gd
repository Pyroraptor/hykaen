extends GutTest
## core/log/tests/test_event_log_structured_storage.gd
##
## GUT suite for FEAT-007 (US-007 / FR-008): persisting structured
## AttackEvent + ReactionResolvedEvent pairs in event_log_view.gd's storage,
## on top of core/log/attack_event.gd + core/log/reaction_resolved_event.gd's
## new domain value objects.
##
## Verifies (test_criteria):
##   1. record_attack(attack_event) stores a structured AttackEvent
##      retrievable via an accessor.
##   2. record_reaction(reaction_event, correlated_attack_id) correctly
##      pairs a ReactionResolvedEvent to its AttackEvent by
##      attack_event_id+window_id.
##   3. Duplicate window firing for the same attack_event_id+window_id is
##      rejected (the budget rule expressed at storage level).
##   4. Entries lacking a structured pairing still render via the
##      pre-existing formatted-string path unchanged.
##
## Plus a section proving core/application/round_session.gd's new,
## optional, byte-for-byte-default-safe EventLogPort-style seam
## (set_event_log_record_attack_fn()) forwards a correctly-shaped
## core/log/attack_event.gd AttackEvent once a Strike resolves, mirroring
## every other Dependency-Inversion seam already established in that file.

const AttackEventClass           = preload("res://core/log/attack_event.gd")
const ReactionResolvedEventClass = preload("res://core/log/reaction_resolved_event.gd")

## EventLogViewClass — the plain SCRIPT (never the .tscn scene): core/ (ADR-001
## domain purity, tests/static/test_no_godot_types_in_core.py) must never
## preload a Godot .tscn scene resource, even from a test file. Instantiating
## via EventLogViewClass.new() (rather than the scene's $RowsContainer child)
## is safe for every assertion this suite makes — record_attack()/
## record_reaction()/on_attack_event()'s formatted-string path all guard
## `_rows_container` being null (see event_log_view.gd's own null-guards).
const EventLogViewClass = preload("res://presentation/event_log_view.gd")

const RunRoundUseCaseClass         = preload("res://core/application/run_round_use_case.gd")
const ResolveActionUseCaseClass    = preload("res://core/application/resolve_action_use_case.gd")
const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")
const SeededRandomAdapterClass     = preload("res://core/combat/seeded_random_adapter.gd")
const AIClass                      = preload("res://core/combat/ai.gd")


# ── Fake/double port implementations (mirrors tests/unit/core/application/
#    test_round_session_ai_turn.gd's established rig) ──────────────────────

class FakeTurnOrderPort:
	extends "res://core/application/turn_order_port.gd"

	var _entries: Array

	func _init(entries: Array) -> void:
		_entries = entries

	func get_turn_order() -> Array:
		return _entries


class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


class FakeRoundHistoryPort:
	extends "res://core/application/round_history_port.gd"

	var entries: Array = []

	func append(entry: Dictionary) -> void:
		entries.append(entry)

	func get_history() -> Array:
		return entries


const CombatantClass = preload("res://core/domain/combatant.gd")

func _durable_combatant(p_name: String, p_is_enemy: bool, p_combatant_id: String = ""):
	return CombatantClass.from_dict({
		"name":         p_name,
		"combatant_id": p_combatant_id,
		"hp_current":   2000,
		"ac":           10,
		"strength":     3,
		"dexterity":    2,
		"intuition":    2,
		"_is_enemy":    p_is_enemy,
		"weapon": {
			"weapon_id": "test_sword",
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 2,
			"damage_die": 6,
		},
	})


func _entry(combatant) -> Dictionary:
	return {"combatant": combatant, "action_economy": ActionEconomyClass.new()}


## _make_event_log() -> EventLogView — builds a bare EventLogView from its
## SCRIPT (never the .tscn scene, see EventLogViewClass's own doc above).
## Deliberately does NOT construct a "RowsContainer" child: tests/static/
## test_no_godot_types_in_core.py's ADR-001 domain-purity scan forbids ANY
## core/*.gd file (including its own tests/) from instantiating/referencing a
## Node/Control-descendant type at all -- not just Control itself, but every
## concrete widget (VBoxContainer/Label/etc). event_log_view.gd's own
## `@onready var _rows_container` therefore resolves to null here (exactly
## the SAME "instantiated outside its .tscn" shape its null-guards already
## document), which is harmless for every assertion this suite makes.
func _make_event_log():
	var log = EventLogViewClass.new()
	add_child_autofree(log)
	return log


func _make_session(entries: Array, party: Array, enemies: Array, event_sink_port, random_number_port):
	var turn_order_port    = FakeTurnOrderPort.new(entries)
	var round_history_port = FakeRoundHistoryPort.new()
	var resolve_action_use_case = ResolveActionUseCaseClass.new(
		random_number_port, event_sink_port, round_history_port
	)
	var determine_outcome_use_case = DetermineOutcomeUseCaseClass.new()
	var run_round_use_case = RunRoundUseCaseClass.new(
		turn_order_port, event_sink_port, round_history_port, AIClass.new(),
		resolve_action_use_case, determine_outcome_use_case
	)
	return run_round_use_case.begin_round(1, party, enemies)


# ══════════════════════════════════════════════════════════════════════════
# Sanity: the two new domain value objects (core/log/attack_event.gd,
# core/log/reaction_resolved_event.gd) construct and round-trip via to_dict().
# ══════════════════════════════════════════════════════════════════════════

func test_attack_event_value_object_stores_and_snapshots_all_fields() -> void:
	var attack_event := AttackEventClass.new(
		"AE-1", 1, "goblin", "titus", "test_sword", 17, true, false, 6, 6, false, false, 100
	)

	assert_eq(attack_event.id, "AE-1")
	assert_eq(attack_event.attacker_id, "goblin")
	assert_eq(attack_event.target_id, "titus")
	assert_true(attack_event.is_hit)
	assert_false(attack_event.is_crit)
	assert_eq(attack_event.damage_final, 6)

	var snapshot: Dictionary = attack_event.to_dict()
	assert_eq(snapshot.get("id"), "AE-1")
	assert_eq(snapshot.get("weapon_id"), "test_sword")
	assert_eq(snapshot.get("damage_raw"), 6)


func test_reaction_resolved_event_value_object_stores_and_snapshots_all_fields() -> void:
	var reaction_event := ReactionResolvedEventClass.new(
		"RE-1", "AE-1", "PreHitAvoidance", "dodge", "ai", "dodge_succeeded", null
	)

	assert_eq(reaction_event.attack_event_id, "AE-1")
	assert_eq(reaction_event.window_id, "PreHitAvoidance")
	assert_eq(reaction_event.choice, "dodge")

	var snapshot: Dictionary = reaction_event.to_dict()
	assert_eq(snapshot.get("outcome"), "dodge_succeeded")
	assert_null(snapshot.get("reduced_by"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: record_attack(attack_event) stores a structured AttackEvent
# retrievable via an accessor.
# ══════════════════════════════════════════════════════════════════════════

func test_record_attack_stores_structured_attack_event_retrievable_via_accessor() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new(
		"AE-1", 1, "goblin", "titus", "test_sword", 17, true, false, 6, 6, false, false
	)
	log.record_attack(attack_event)

	var stored = log.get_structured_attack("AE-1")
	assert_not_null(stored, "a recorded AttackEvent must be retrievable by its id")
	assert_eq(stored.id, "AE-1")
	assert_eq(stored.attacker_id, "goblin")
	assert_eq(stored.target_id, "titus")
	assert_eq(stored.damage_final, 6)


func test_get_structured_attack_returns_null_for_unknown_id() -> void:
	var log = _make_event_log()

	assert_null(log.get_structured_attack("does-not-exist"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: record_reaction(reaction_event, correlated_attack_id)
# correctly pairs a ReactionResolvedEvent to its AttackEvent by
# attack_event_id+window_id.
# ══════════════════════════════════════════════════════════════════════════

func test_record_reaction_pairs_to_its_attack_event_by_id_and_window() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new(
		"AE-1", 1, "goblin", "titus", "test_sword", 17, true, false, 6, 6, false, false
	)
	log.record_attack(attack_event)

	var prehit_reaction := ReactionResolvedEventClass.new(
		"RE-1", null, "PreHitAvoidance", "dodge", "ai", "dodge_failed"
	)
	var accepted: bool = log.record_reaction(prehit_reaction, "AE-1")
	assert_true(accepted, "pairing a reaction to an existing AttackEvent must succeed")

	var paired = log.get_paired_reaction("AE-1", "PreHitAvoidance")
	assert_not_null(paired, "the ReactionResolvedEvent must be retrievable by attack_event_id+window_id")
	assert_eq(paired.choice, "dodge")
	assert_eq(paired.outcome, "dodge_failed")

	# A DIFFERENT window on the SAME attack is a distinct pairing slot.
	assert_null(log.get_paired_reaction("AE-1", "OnHitMitigation"))


func test_record_reaction_supports_both_windows_paired_to_the_same_attack_event() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new("AE-2", 1, "goblin", "titus", "test_sword", 10, true, false, 6, 4)
	log.record_attack(attack_event)

	var prehit := ReactionResolvedEventClass.new("RE-1", null, "PreHitAvoidance", "none", "ai", "none")
	var onhit  := ReactionResolvedEventClass.new("RE-2", null, "OnHitMitigation", "block", "ai", "block_reduced_by_n", 2)

	assert_true(log.record_reaction(prehit, "AE-2"))
	assert_true(log.record_reaction(onhit, "AE-2"))

	assert_eq(log.get_paired_reaction("AE-2", "PreHitAvoidance").choice, "none")
	assert_eq(log.get_paired_reaction("AE-2", "OnHitMitigation").choice, "block")


func test_record_reaction_rejects_pairing_to_an_unknown_attack_event() -> void:
	var log = _make_event_log()

	var reaction_event := ReactionResolvedEventClass.new("RE-1", null, "PreHitAvoidance", "dodge", "ai", "dodge_succeeded")
	var accepted: bool = log.record_reaction(reaction_event, "no-such-attack")

	assert_false(accepted, "pairing to a non-existent AttackEvent must be rejected")
	assert_null(log.get_paired_reaction("no-such-attack", "PreHitAvoidance"))


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: duplicate window firing for the same attack_event_id+window_id
# is rejected — the budget rule expressed at storage level.
# ══════════════════════════════════════════════════════════════════════════

func test_duplicate_window_firing_for_the_same_attack_and_window_is_rejected() -> void:
	var log = _make_event_log()

	var attack_event := AttackEventClass.new("AE-3", 1, "goblin", "titus", "test_sword", 15, true, false, 6, 6)
	log.record_attack(attack_event)

	var first_reaction  := ReactionResolvedEventClass.new("RE-1", null, "OnHitMitigation", "block", "ai", "block_reduced_by_n", 2)
	var second_reaction := ReactionResolvedEventClass.new("RE-2", null, "OnHitMitigation", "parry", "ai", "parry_succeeded")

	assert_true(log.record_reaction(first_reaction, "AE-3"), "the first window firing must be accepted")
	var second_accepted: bool = log.record_reaction(second_reaction, "AE-3")
	assert_false(second_accepted, "a SECOND firing of the SAME window for the SAME attack_event_id must be rejected")

	# The original pairing must be left completely untouched by the rejected
	# duplicate — never silently overwritten.
	var paired = log.get_paired_reaction("AE-3", "OnHitMitigation")
	assert_eq(paired.choice, "block", "a rejected duplicate must never overwrite the original paired reaction")

	assert_eq(
		log.get_rejected_duplicate_reactions().size(), 1,
		"the rejected duplicate must be observable (this project's Godot 4.3 engine cannot capture assert()/push_error() output from GUT)"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: entries lacking a structured pairing still render via the
# pre-existing formatted-string path unchanged.
# ══════════════════════════════════════════════════════════════════════════

func test_preexisting_formatted_string_path_is_unaffected_by_structured_recording() -> void:
	var log = _make_event_log()

	# The OLD path: a plain Dictionary dispatched via on_attack_event(), with
	# no structured AttackEvent ever recorded for it.
	log.on_attack_event({
		"round": 1,
		"attacker_name": "Titus",
		"target_name": "Skeleton",
		"hit": true,
		"crit": false,
		"damage_final": 6,
	})

	assert_eq(log.get_entry_count(), 1, "the pre-existing formatted-string entry path must be unaffected")
	var text: String = log.get_entry_text(0)
	assert_string_contains(text, "Titus")
	assert_string_contains(text, "Skeleton")
	assert_string_contains(text, "Hit")

	# Recording a structured AttackEvent afterwards must not retroactively
	# alter (or remove) the pre-existing formatted-string entry.
	var attack_event := AttackEventClass.new("AE-4", 1, "goblin", "titus", "test_sword", 12, true, false, 5, 5)
	log.record_attack(attack_event)

	assert_eq(log.get_entry_count(), 1, "recording structured data must never mutate the pre-existing entries array")
	assert_eq(log.get_entry_text(0), text, "the pre-existing formatted-string entry must render byte-for-byte unchanged")

	# The structured accessor for an attack_event_id that was never recorded
	# (the OLD Dictionary-dispatched entry above has no id) returns null —
	# an "unpaired" lookup, never an error.
	assert_null(log.get_structured_attack("unpaired-id"))


# ══════════════════════════════════════════════════════════════════════════
# RoundSession integration: the new, optional, byte-for-byte-default-safe
# record_attack seam forwards a correctly-shaped core/log/attack_event.gd
# AttackEvent once a Strike resolves; never injecting it changes nothing
# (NFR-004).
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_forwards_structured_attack_event_when_seam_is_injected() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(42)
	var session = _make_session(entries, [titus], [goblin], event_sink_port, random_number_port)

	var recorded_attacks: Array = []
	session.set_event_log_record_attack_fn(func(attack_event): recorded_attacks.append(attack_event))

	var result: Dictionary = await session.advance_ai_turn()
	assert_true(result.get("ok", false))

	assert_eq(recorded_attacks.size(), 1, "advance_ai_turn() must forward exactly one structured AttackEvent per resolved Strike")
	var forwarded = recorded_attacks[0]
	assert_eq(forwarded.attacker_id, "goblin")
	assert_eq(forwarded.target_id, "titus")
	assert_eq(forwarded.weapon_id, "test_sword")
	assert_true(forwarded.id != null and str(forwarded.id) != "", "a generated attack_event_id must always be non-empty")


func test_round_session_never_forwards_when_seam_is_not_injected() -> void:
	var goblin = _durable_combatant("Goblin", true, "goblin")
	var titus  = _durable_combatant("Titus", false, "titus")
	var entries: Array = [_entry(goblin), _entry(titus)]

	var event_sink_port    = FakeEventSinkPort.new()
	var random_number_port = SeededRandomAdapterClass.new(42)
	var session = _make_session(entries, [titus], [goblin], event_sink_port, random_number_port)

	# No set_event_log_record_attack_fn() call — every pre-existing caller's
	# behavior (NFR-004).
	var result: Dictionary = await session.advance_ai_turn()
	assert_true(result.get("ok", false), "advance_ai_turn() must resolve exactly as before when no EventLogPort seam is injected")
