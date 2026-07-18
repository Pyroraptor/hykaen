extends GutTest
## tests/unit/test_event_emission_seam.gd — FEAT-006 (US-006, design notes'
## api_contracts #6 / architecture section).
##
## GUT suite proving the "generalize event emission seam" retrofit:
## core/application/event_sink_port.gd's EventSinkPort.emit(event) dispatch
## — and core/application/resolve_action_use_case.gd's new internal
## _emit_event() seam it is routed through — accepts ANY typed event object,
## not just AttackEvent-shaped ones, WITHOUT any type-branching, and WITHOUT
## altering the live AttackEvent code path's observable behavior.
##
## This is deliberately a documentation-and-tripwire feature (design notes:
## "a deliberate extension point, not a live change this sprint") — no new
## event type is actually emitted anywhere in the live codebase as of this
## feature. This suite pins that fact explicitly, so a future feature that
## starts emitting a second event type live does so as a conscious, visible
## spec change rather than silent scope creep.
##
## Sections (test_criteria):
##   A. AttackEvent emission for Strike remains byte-identical to baseline.
##      Mirrors tests/integration/test_strike_effects_applier_retrofit.gd's
##      Section C pinned scenario EXACTLY (same scripted rolls, same
##      attacker/target fixtures, same round/cycle_index) — the FEAT-004
##      baseline this generalization must not disturb.
##   B. Zero new event types are emitted live this sprint — both the
##      non-lethal and lethal Strike paths only ever emit
##      RoundEvents.AttackBroadcast / RoundEvents.CombatantDefeatedEvent
##      (the pre-existing FEAT-099 set), plus a static check that
##      resolve_action_use_case.gd's _emit_event() seam has exactly the two
##      expected call sites.
##   C. EventSinkPort.emit()'s dispatch mechanism accepts an arbitrary typed
##      event object with NO branching inside the AttackEvent code path —
##      proven both behaviorally (an unrelated RefCounted value object
##      passed straight through a concrete adapter) and statically (no
##      `if event is`/`match event` type-inspection anywhere in
##      event_sink_port.gd or resolve_action_use_case.gd's _emit_event()).

const ResolveActionUseCaseClass = preload("res://core/application/resolve_action_use_case.gd")
const RoundEventsClass          = preload("res://core/rules/round_events.gd")
const ActionEconomyClass        = preload("res://core/rules/action_economy.gd")
const CombatantClass            = preload("res://core/domain/combatant.gd")

const RESOLVE_ACTION_USE_CASE_PATH: String = "res://core/application/resolve_action_use_case.gd"
const EVENT_SINK_PORT_PATH: String = "res://core/application/event_sink_port.gd"


# ── Local test doubles (mirrors tests/integration/
#    test_strike_effects_applier_retrofit.gd's established conventions —
#    each suite in this project owns its own doubles) ──────────────────────

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


class ScriptedRandomNumberPort:
	extends "res://core/rules/random_port.gd"

	var _values: Array
	var _index: int = 0
	var calls: Array = []

	func _init(values: Array) -> void:
		_values = values

	func roll(dice_spec: Dictionary) -> int:
		calls.append(dice_spec)
		var v = _values[_index]
		_index += 1
		return v


## ArbitraryProbeEvent — a value object with ZERO relationship to
## RoundEvents.AttackBroadcast/CombatantDefeatedEvent or any other
## event type this codebase currently constructs. Used ONLY to prove the
## emit() dispatch mechanism does not special-case AttackEvent's shape.
class ArbitraryProbeEvent:
	extends RefCounted

	var probe_field: String
	var probe_amount: int

	func _init(p_probe_field: String = "", p_probe_amount: int = 0) -> void:
		probe_field = p_probe_field
		probe_amount = p_probe_amount


func _make_use_case(scripted_values: Array) -> Dictionary:
	var rng_port    = ScriptedRandomNumberPort.new(scripted_values)
	var event_sink  = FakeEventSinkPort.new()
	var history     = FakeRoundHistoryPort.new()
	var use_case    = ResolveActionUseCaseClass.new(rng_port, event_sink, history)
	return {"use_case": use_case, "rng_port": rng_port, "event_sink": event_sink, "history": history}


func _fresh_ae():
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	return ae


## _attacker()/_target() — deliberately IDENTICAL fixtures to
## tests/integration/test_strike_effects_applier_retrofit.gd's own
## _attacker()/_target(), so Section A below reproduces that suite's pinned
## FEAT-004 baseline scenario exactly (same weapon math, same names).
func _attacker():
	return CombatantClass.from_dict({
		"name":     "Attacker",
		"strength": 0,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": 0,
			"damage_die": 6
		}
	})


func _target(hp_current: int = 50, ac: int = 5):
	return CombatantClass.from_dict({"name": "Target", "hp_current": hp_current, "ac": ac})


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


## _extract_function_body(content, func_signature_prefix) -> String — mirrors
## tests/integration/test_strike_effects_applier_retrofit.gd's helper of the
## same name: pulls one function's text (up to, but not including, the next
## top-level `\nfunc `) out of a whole-file source string.
func _extract_function_body(content: String, func_signature_prefix: String) -> String:
	var start: int = content.find(func_signature_prefix)
	assert_true(start >= 0, "expected to find '%s' in the source file" % func_signature_prefix)
	if start < 0:
		return ""
	var next_func: int = content.find("\nfunc ", start + func_signature_prefix.length())
	if next_func < 0:
		return content.substr(start)
	return content.substr(start, next_func - start)


## Strips full-line `##`/`#` doc-comment lines out of a source snippet
## before scanning for a call/branching pattern — mirrors
## ci/check_no_duplicate_seams.sh's convention: a comment merely NAMING a
## pattern (this file's own doc, or the production file's doc-comments)
## must never be mistaken for live code.
func _strip_comment_lines(body: String) -> String:
	var kept: Array = []
	for line in body.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ══════════════════════════════════════════════════════════════════════════
# Section A (test_criteria #1) — AttackEvent emission for Strike remains
# byte-identical to baseline after generalization.
# ══════════════════════════════════════════════════════════════════════════

func test_attack_event_emission_for_strike_remains_byte_identical_to_baseline() -> void:
	# Identical scripted scenario to tests/integration/
	# test_strike_effects_applier_retrofit.gd's Section C pin: rolls
	# [10, 4] (attack roll=10, damage roll=4), attacker "Attacker"
	# (strength=0), target "Target" (hp=50, ac=5), round=3, cycle_index=1.
	var rig: Dictionary = _make_use_case([10, 4])
	var use_case = rig["use_case"]
	var target = _target(50, 5)

	var result: Dictionary = use_case.resolve(_attacker(), _fresh_ae(), target, "Strike", 3, 1)
	assert_true(result.get("ok", false), "the scripted Strike must resolve")

	var event = result["event"]
	assert_true(event is RoundEventsClass.AttackBroadcast, "BASELINE: the emitted event must be a RoundEvents.AttackBroadcast")
	assert_eq(event.round, 3, "BASELINE: round field unchanged by the generalized emit seam")
	assert_eq(event.attacker_name, "Attacker", "BASELINE: attacker_name field unchanged")
	assert_eq(event.target_name, "Target", "BASELINE: target_name field unchanged")
	assert_eq(event.roll, 10, "BASELINE: roll field unchanged")
	assert_eq(event.defense_type, "ac", "BASELINE: defense_type field unchanged")
	assert_eq(event.defense_value, 5, "BASELINE: defense_value field unchanged")
	assert_true(event.hit, "BASELINE: hit field unchanged (roll_total(10) >= ac(5))")
	assert_false(event.crit, "BASELINE: crit field unchanged (excess < 10)")
	assert_eq(event.damage_final, 4, "BASELINE: damage_final field unchanged (damage roll(4) + strength_mod(0))")
	assert_not_null(event.actor_updated_action_budget, "BASELINE: actor_updated_action_budget must still be populated")
	assert_true(event.actor_updated_action_budget.has("remaining"), "BASELINE: actor_updated_action_budget must still carry 'remaining'")
	assert_true(event.actor_updated_action_budget.has("spent"), "BASELINE: actor_updated_action_budget must still carry 'spent'")

	# Exactly one event (attack only, non-lethal) — the generalized seam
	# must not add, drop, or duplicate any emission for the Strike path.
	assert_eq(rig["event_sink"].events.size(), 1, "BASELINE: exactly one event (attack) emitted for a non-lethal scripted Strike")
	assert_eq(rig["event_sink"].events[0], event, "BASELINE: the sole emitted event must be the SAME AttackBroadcast instance returned in result['event']")


func test_lethal_strike_still_emits_attack_then_defeated_events_in_order_after_generalization() -> void:
	# Same scripted attack/damage rolls, but a target with hp low enough
	# that this Strike is lethal — pins that the generalized _emit_event()
	# seam preserves BOTH the emission COUNT and ORDER (attack, then
	# defeated) the pre-generalization code produced.
	var rig: Dictionary = _make_use_case([10, 4])
	var use_case = rig["use_case"]
	var target = _target(3, 5)

	var result: Dictionary = use_case.resolve(_attacker(), _fresh_ae(), target, "Strike", 3, 1)
	assert_true(result.get("ok", false), "the scripted Strike must resolve")
	assert_true(result.get("target_defeated", false), "BASELINE: hp(3) - damage(4) <= 0 -> target_defeated must be true")

	var events: Array = rig["event_sink"].events
	assert_eq(events.size(), 2, "BASELINE: exactly two events (attack, defeated) for a lethal Strike")
	assert_true(events[0] is RoundEventsClass.AttackBroadcast, "BASELINE: first emitted event must be the AttackBroadcast")
	assert_true(events[1] is RoundEventsClass.CombatantDefeatedEvent, "BASELINE: second emitted event must be the CombatantDefeatedEvent")


# ══════════════════════════════════════════════════════════════════════════
# Section B (test_criteria #2) — zero new event types are emitted live this
# sprint.
# ══════════════════════════════════════════════════════════════════════════

func test_zero_new_event_types_emitted_live_for_non_lethal_strike() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var use_case = rig["use_case"]

	use_case.resolve(_attacker(), _fresh_ae(), _target(50, 5), "Strike", 1, 0)

	for event in rig["event_sink"].events:
		assert_true(
			event is RoundEventsClass.AttackBroadcast or event is RoundEventsClass.CombatantDefeatedEvent,
			"SCOPE-CREEP TRIPWIRE: only the pre-existing FEAT-099 event types (AttackBroadcast/CombatantDefeatedEvent) may be emitted live this sprint; got %s" % event
		)


func test_zero_new_event_types_emitted_live_for_lethal_strike() -> void:
	var rig: Dictionary = _make_use_case([10, 4])
	var use_case = rig["use_case"]

	use_case.resolve(_attacker(), _fresh_ae(), _target(3, 5), "Strike", 1, 0)

	assert_true(rig["event_sink"].events.size() > 0, "sanity: at least one event must have been emitted")
	for event in rig["event_sink"].events:
		assert_true(
			event is RoundEventsClass.AttackBroadcast or event is RoundEventsClass.CombatantDefeatedEvent,
			"SCOPE-CREEP TRIPWIRE: only the pre-existing FEAT-099 event types (AttackBroadcast/CombatantDefeatedEvent) may be emitted live this sprint; got %s" % event
		)


func test_emit_event_seam_has_exactly_the_two_expected_call_sites() -> void:
	# Static check: resolve_action_use_case.gd's _finalize_strike_result()
	# must call the generalized _emit_event() seam EXACTLY twice — once for
	# attack_event, once for defeated_event — never for a third,
	# unforeseen event variable. A new live event type would add a THIRD
	# `_emit_event(` call site here, which is exactly the scope creep this
	# tripwire catches.
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")
	var live_code: String = _strip_comment_lines(body)

	var call_count: int = live_code.count("_emit_event(")
	assert_eq(
		call_count, 2,
		"SCOPE-CREEP TRIPWIRE: _finalize_strike_result() must call _emit_event() exactly twice (attack_event, defeated_event); found %d -- a live third event type has been introduced" % call_count
	)
	assert_true(live_code.contains("_emit_event(attack_event)"), "expected the AttackEvent call site to be unchanged")
	assert_true(live_code.contains("_emit_event(defeated_event)"), "expected the CombatantDefeatedEvent call site to be unchanged")


# ══════════════════════════════════════════════════════════════════════════
# Section C (test_criteria #3) — EventSinkPort.emit()'s dispatch mechanism
# accepts arbitrary typed event objects with NO branching inside the
# AttackEvent code path.
# ══════════════════════════════════════════════════════════════════════════

func test_event_sink_emit_accepts_an_arbitrary_typed_event_object() -> void:
	# ArbitraryProbeEvent shares NOTHING with RoundEvents.AttackBroadcast --
	# no common base beyond RefCounted, no shared fields. If emit() (or any
	# concrete adapter) special-cased/branched on AttackEvent's shape, this
	# would fail to append cleanly / would need a to_dict()-shaped Dictionary
	# instead.
	var sink := FakeEventSinkPort.new()
	var probe := ArbitraryProbeEvent.new("heal", 8)

	sink.emit(probe)

	assert_eq(sink.events.size(), 1, "the arbitrary typed event must have been accepted and appended")
	assert_true(sink.events[0] is ArbitraryProbeEvent, "the dispatched event must be the SAME arbitrary type, unmodified")
	assert_eq(sink.events[0].probe_field, "heal", "the arbitrary event's own fields must pass through untouched")
	assert_eq(sink.events[0].probe_amount, 8, "the arbitrary event's own fields must pass through untouched")


func test_console_event_sink_adapter_accepts_an_arbitrary_typed_event_object() -> void:
	# Same proof against the REAL concrete adapter this composition root
	# wires up in production (infrastructure/console_event_sink_adapter.gd),
	# not just this suite's own Fake -- confirming the generalized contract
	# holds for the adapter actually used at runtime, too.
	var ConsoleEventSinkAdapterClass = preload("res://infrastructure/console_event_sink_adapter.gd")
	var adapter = ConsoleEventSinkAdapterClass.new()
	var probe := ArbitraryProbeEvent.new("condition", 1)

	adapter.emit(probe)

	assert_eq(adapter.log.size(), 1, "the real console adapter must accept and log the arbitrary typed event")
	assert_true(adapter.log[0] is ArbitraryProbeEvent, "the logged event must be the SAME arbitrary type, unmodified")


func test_event_sink_port_emit_signature_and_body_contain_no_type_branching() -> void:
	var content: String = _read_file(EVENT_SINK_PORT_PATH)

	# The parameter must remain untyped -- no static type hint restricting
	# emit() to a Dictionary or a specific event class.
	assert_true(
		content.contains("func emit(event) -> void:"),
		"EventSinkPort.emit()'s parameter must remain untyped (no ': Dictionary'/event-class type hint) so any typed event object is a legal argument"
	)

	var body: String = _extract_function_body(content, "func emit(event) -> void:")
	var live_code: String = _strip_comment_lines(body)
	assert_false(live_code.contains("if event is"), "EventSinkPort.emit()'s base implementation must not branch on event's type")
	assert_false(live_code.contains("match event"), "EventSinkPort.emit()'s base implementation must not branch on event's type")


func test_emit_event_seam_body_contains_no_type_branching() -> void:
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _emit_event(event) -> void:")
	var live_code: String = _strip_comment_lines(body)

	assert_false(live_code.contains("if event is"), "_emit_event() must be a pure, undifferentiated forward -- no branching on event's type")
	assert_false(live_code.contains("match event"), "_emit_event() must be a pure, undifferentiated forward -- no branching on event's type")
	assert_true(
		live_code.contains("_event_sink_port.emit(event)"),
		"_emit_event() must forward verbatim to the injected EventSinkPort's emit(event)"
	)


func test_attack_event_construction_code_path_is_untouched_by_the_generalization() -> void:
	# The AttackEvent construction block itself (constructing
	# RoundEvents.AttackBroadcast from strike_result/combatant/target) must
	# contain no new conditional dispatch introduced by this feature --
	# only the trailing hand-off call was refactored to go through
	# _emit_event() (see this file's Section A/B above proving that hand-off
	# is behaviorally identical).
	var content: String = _read_file(RESOLVE_ACTION_USE_CASE_PATH)
	var body: String = _extract_function_body(content, "func _finalize_strike_result(")

	var construction_start: int = body.find("var attack_event = RoundEventsClass.AttackBroadcast.new(")
	assert_true(construction_start >= 0, "expected to find the AttackBroadcast construction call")
	var emit_call_start: int = body.find("_emit_event(attack_event)", construction_start)
	assert_true(emit_call_start >= 0, "expected _emit_event(attack_event) to immediately follow AttackBroadcast construction")

	var construction_block: String = _strip_comment_lines(body.substr(construction_start, emit_call_start - construction_start))
	assert_false(construction_block.contains("if "), "the AttackBroadcast construction block must contain no new conditional branching")
