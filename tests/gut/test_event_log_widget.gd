extends GutTest
## tests/gut/test_event_log_widget.gd — FEAT-004 (US-004 / FR-006)
##
## Event log widget fed by typed round events.
##
## Realizes US-004's steel-thread "event log" surface: a presentation-layer
## widget subscribed to the EXISTING core/application/event_sink_port.gd
## (no new/parallel event bus, per ADR-005) that renders AttackEvent /
## CombatantDefeatedEvent / EncounterResultEvent entries in arrival order.
##
## That widget already exists in this codebase as
## presentation/event_log_view.gd (+ presentation/event_log_view.tscn),
## wired into the composition root at MainScene.gd's
## _presentation_event_subscribers() (see MainScene.gd step 6) — this file
## adds the FEAT-004-scoped coverage requested by this feature's
## test_criteria, exercising that SAME production widget/wiring rather than
## introducing a second, duplicate implementation (which would itself
## violate ADR-005's "no parallel event bus/consumer" constraint).
##
## Verifies (test_criteria):
##   1. The widget renders one entry per AttackEvent/CombatantDefeatedEvent/
##      EncounterResultEvent received via event_sink_port, in emission order.
##   2. No signal bus other than the existing event_sink_port is subscribed
##      to (source-inspection: neither the widget nor MainScene's wiring of
##      it uses Godot's `.connect()` signal machinery — it is driven purely
##      by direct on_round_event() calls forwarded from the one
##      EventSinkPort adapter, ADR-003/ADR-005).
##   3. The widget correctly subscribes when MainScene wires it during
##      composition-root setup (a real Strike through the real MainScene
##      composition root produces a real log entry).

const EventLogViewScene: PackedScene = preload("res://presentation/event_log_view.tscn")
const EVENT_LOG_VIEW_PATH: String = "res://presentation/event_log_view.gd"
const MAIN_SCENE_GD_PATH: String = "res://MainScene.gd"
const MAIN_SCENE_TSCN_PATH: String = "res://MainScene.tscn"

const RoundEventsClass = preload("res://core/rules/round_events.gd")


func _read_source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: one entry per AttackEvent/CombatantDefeatedEvent/
# EncounterResultEvent received via event_sink_port, in emission order.
# ══════════════════════════════════════════════════════════════════════════

func test_widget_renders_one_entry_per_event_type_in_emission_order() -> void:
	var widget = EventLogViewScene.instantiate()
	add_child_autofree(widget)

	# Simulate the EXACT sequence event_sink_port.gd's contract dispatches
	# through a concrete adapter's forward_to loop (MainScene.gd step 3):
	# one on_round_event() call per emitted event, in emission order.
	var attack_event = RoundEventsClass.AttackBroadcast.new(1, "Titus", "Skeleton", 17, "ac", 14, true, false, 6)
	var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(1, "Skeleton", "Titus")
	var result_event = RoundEventsClass.EncounterResultEvent.new(1, "won")

	widget.on_round_event(attack_event)
	widget.on_round_event(defeated_event)
	widget.on_round_event(result_event)

	assert_eq(
		widget.get_entry_count(), 3,
		"exactly one rendered entry must be produced per AttackEvent/CombatantDefeatedEvent/EncounterResultEvent received"
	)

	var texts: Array = [
		widget.get_entry_text(0),
		widget.get_entry_text(1),
		widget.get_entry_text(2),
	]
	assert_string_contains(texts[0], "Titus", "entry 0 (first emitted) must be the AttackEvent")
	assert_string_contains(texts[0], "Skeleton", "entry 0 (first emitted) must be the AttackEvent")
	assert_string_contains(texts[1], "Skeleton", "entry 1 (second emitted) must be the CombatantDefeatedEvent")
	assert_string_contains(texts[1], "defeated", "entry 1 (second emitted) must be the CombatantDefeatedEvent")
	assert_string_contains(texts[2], "won", "entry 2 (third emitted) must be the EncounterResultEvent")

	# Arrival order, not domain `round` order: sequence_numbers must be
	# strictly increasing in the order on_round_event() was actually called.
	var sequence_numbers: Array = widget.get_sequence_numbers()
	assert_eq(sequence_numbers.size(), 3)
	assert_true(sequence_numbers[0] < sequence_numbers[1])
	assert_true(sequence_numbers[1] < sequence_numbers[2])


func test_widget_preserves_arrival_order_even_when_round_numbers_are_out_of_order() -> void:
	var widget = EventLogViewScene.instantiate()
	add_child_autofree(widget)

	# Deliberately emitted with `round` fields out of numeric order (5, 1, 3)
	# -- the widget must preserve ARRIVAL (event_sink_port dispatch) order,
	# never re-sort by the domain round field an event happens to carry.
	var first = RoundEventsClass.EncounterResultEvent.new(5, "won")
	var second = RoundEventsClass.AttackBroadcast.new(1, "A", "B", 10, "ac", 12, true, false, 3)
	var third = RoundEventsClass.CombatantDefeatedEvent.new(3, "B", "A")

	widget.on_round_event(first)
	widget.on_round_event(second)
	widget.on_round_event(third)

	assert_eq(widget.get_entry_count(), 3)
	assert_string_contains(widget.get_entry_text(0), "won", "entry 0 must be the first-arrived EncounterResultEvent")
	assert_string_contains(widget.get_entry_text(1), "A", "entry 1 must be the second-arrived AttackEvent")
	assert_string_contains(widget.get_entry_text(2), "defeated", "entry 2 must be the third-arrived CombatantDefeatedEvent")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: no signal bus other than the existing event_sink_port is
# subscribed to.
# ══════════════════════════════════════════════════════════════════════════

func test_widget_source_uses_no_signal_connect_calls() -> void:
	# The widget must be driven purely by direct on_round_event()/
	# on_attack_event()/on_combatant_defeated_event()/on_encounter_result_event()
	# calls forwarded from the one EventSinkPort adapter (ADR-003) -- never by
	# subscribing itself to a Godot Signal/signal bus of its own or anyone
	# else's (which would be a second, parallel event bus, forbidden by
	# ADR-005).
	var source: String = _read_source(EVENT_LOG_VIEW_PATH)
	assert_eq(
		source.find(".connect("), -1,
		"presentation/event_log_view.gd must not use Godot's signal .connect() machinery -- it must be driven only by direct calls forwarded from event_sink_port"
	)
	assert_eq(
		source.find("signal "), -1,
		"presentation/event_log_view.gd must not declare any Signal of its own -- it is a pure sink, not a second event bus"
	)


func test_widget_is_wired_in_main_scene_only_via_event_sink_forwarding_not_a_signal_connection() -> void:
	# MainScene.gd (the composition root) must wire event_log_view into the
	# pipeline exclusively through the ConsoleEventSinkAdapter's forward_to
	# list -- i.e. event_log_view never appears as the target of a
	# `.connect(` call anywhere in the composition root, which would indicate
	# a second, parallel subscription path outside event_sink_port.
	var source: String = _read_source(MAIN_SCENE_GD_PATH)

	assert_true(
		source.contains("event_log_view"),
		"MainScene.gd must reference event_log_view to wire it into the composition root"
	)

	var search_from: int = 0
	while true:
		var idx: int = source.find("event_log_view", search_from)
		if idx == -1:
			break
		var line_end: int = source.find("\n", idx)
		if line_end == -1:
			line_end = source.length()
		var line: String = source.substr(idx, line_end - idx)
		assert_false(
			line.contains(".connect("),
			"no line referencing event_log_view in MainScene.gd may use .connect() -- it must be wired solely through the event_sink_port forwarding list, e.g.: " + line
		)
		search_from = idx + 1


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: the widget correctly subscribes when MainScene wires it
# during composition-root setup.
# ══════════════════════════════════════════════════════════════════════════

func test_main_scene_wires_event_log_view_into_the_real_event_sink_subscribers() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_TSCN_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)

	assert_not_null(instance.event_log_view, "MainScene must expose a non-null event_log_view after composition")
	assert_true(
		instance.event_sink.forward_to.has(instance.event_log_view),
		"MainScene's composition root must register event_log_view as a subscriber of the real event_sink_port adapter"
	)


func test_widget_receives_a_real_attack_event_through_the_live_composition_root() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_TSCN_PATH)
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)

	assert_eq(
		instance.event_log_view.get_entry_count(), 0,
		"fixture assumption: no events logged yet before any Strike"
	)

	# FEAT-188 (DEF-001): FEAT-006 (US-006) removed the legacy
	# immediate-resolve-on-click Strike control this test originally drove
	# directly -- Strike is now driven SOLELY through the Layer 1 verb bar
	# ($VerbBarView, presentation/verb_bar_view.gd) -> `_verb_registry`'s
	# STRIKE entry, entered via the real `verb_bar_view.press("STRIKE")` and
	# resolved via the real `_verb_registry.execute("STRIKE", ...)`, mirroring
	# the retargeting already applied to sibling suites in FEAT-181/182.
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: the prologue's first actor has at least one in-reach target")

	var result: Dictionary = instance._verb_registry.execute("STRIKE", target_ids[0])
	assert_true(result.get("resolved", false), "the real resolve_action_use_case must resolve the Strike")

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"the widget must have rendered at least one entry once the real composition root emitted an AttackEvent through event_sink_port"
	)
