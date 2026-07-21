extends GutTest
## tests/acceptance/combine/test_us001_descriptor_acceptance.gd — FEAT-303
## (Iteration O "Combine Selection UX"; CHECKLIST-3).
##
## Scripted acceptance-test evidence for US-001 ("As a player, when I press
## a combinable verb, the system returns a real SelectionDescriptor -- not a
## bare {ok, queue}-only Dictionary -- so I can see legal next picks").
##
## This file asserts ONLY the acceptance behavior named by US-001 -- it
## exercises the REAL, already-shipped
## core/domain/combine/selection_descriptor.gd SelectionDescriptor value
## object and the REAL
## core/controllers/combine_action_controller.gd CombineActionController's
## enter_selection() (the concrete VerbControllerPort seam FEAT-001/FEAT-002
## fixed), never a hand-rolled substitute. Deeper unit coverage of these
## same classes already lives in
## tests/unit/domain/combine/test_selection_descriptor.gd and
## tests/unit/application/combine/test_build_verb_queue_use_case.gd -- this
## suite exists to give the deployment-readiness checklist an explicit,
## individually-named, CI-verifiable trace back to US-001's own acceptance
## behavior, not to re-derive that coverage.
##
## Acceptance behavior verified:
##   1. SelectionDescriptor is a genuine value object carrying ALL SIX
##      design-notes fields (ok, candidate_options, candidate_hexes,
##      candidate_targets, order_index, meta) -- not a bare {ok, queue}
##      Dictionary.
##   2. CombineActionController.enter_selection() -- the real
##      VerbControllerPort seam a player's verb press drives -- returns
##      exactly this SelectionDescriptor shape, with legal next-pick verbs
##      surfaced in candidate_options.

const SelectionDescriptorScript = preload("res://core/domain/combine/selection_descriptor.gd")
const CombineActionControllerClass = preload("res://core/controllers/combine_action_controller.gd")
const CombineQueueClass = preload("res://core/domain/combine/combine_queue.gd")

const STRIDE_RESOURCE_PATH: String = "res://data/verbs/stride.tres"
const STRIKE_RESOURCE_PATH: String = "res://data/verbs/strike.tres"


class FakeVerbRegistryPort:
	extends "res://core/application/combine/verb_registry_port.gd"

	var _pool: Array

	func _init(pool: Array) -> void:
		_pool = pool

	func get_available_verbs(_actor, _context) -> Array:
		return _pool


func _option_ids(candidate_options: Array) -> Array:
	var ids: Array = []
	for option in candidate_options:
		ids.append(option.get("id"))
	return ids


# ══════════════════════════════════════════════════════════════════════════
# US-001, criterion 1 -- SelectionDescriptor carries all six design-notes
# fields as a genuine value object (construction acceptance).
# ══════════════════════════════════════════════════════════════════════════

func test_us001_selection_descriptor_construction_carries_all_six_fields() -> void:
	var descriptor = SelectionDescriptorScript.new(
		true, [{"id": "STRIDE", "label": "Stride", "kind": "VERB"}],
		["hex_a"], ["target_a"], 2, {"note": "acceptance"}
	)

	assert_true(descriptor.ok, "US-001: ok must be settable/readable")
	assert_eq(descriptor.candidate_options.size(), 1, "US-001: candidate_options must be a real field")
	assert_eq(descriptor.candidate_hexes, ["hex_a"], "US-001: candidate_hexes must be a real field")
	assert_eq(descriptor.candidate_targets, ["target_a"], "US-001: candidate_targets must be a real field")
	assert_eq(descriptor.order_index, 2, "US-001: order_index must be a real field")
	assert_eq(descriptor.meta, {"note": "acceptance"}, "US-001: meta must be a real field")


func test_us001_selection_descriptor_failure_state_is_explicit_not_silently_empty() -> void:
	var failure = SelectionDescriptorScript.new(false)

	assert_false(failure.ok, "US-001: a failed request must report ok=false explicitly")
	assert_eq(failure.candidate_options, [], "US-001: a failed request's candidate_options must be an explicit empty array, not a masked success")


# ══════════════════════════════════════════════════════════════════════════
# US-001, criterion 2 -- CombineActionController.enter_selection() (the real
# VerbControllerPort seam a verb press drives) returns a genuine
# SelectionDescriptor, not the pre-fix bare {ok, queue} Dictionary.
# ══════════════════════════════════════════════════════════════════════════

func test_us001_combine_action_controller_enter_selection_returns_real_selection_descriptor() -> void:
	var port := FakeVerbRegistryPort.new([
		ResourceLoader.load(STRIDE_RESOURCE_PATH),
		ResourceLoader.load(STRIKE_RESOURCE_PATH),
	])
	var controller := CombineActionControllerClass.new({"verb_registry_port": port})

	var descriptor = controller.enter_selection({
		"actor_id": {"combatant_id": "player_0"},
		"mode": "BUILD_QUEUE",
		"combine_context": CombineQueueClass.Context.TURN,
		"queue": [],
	})

	assert_true(descriptor.ok, "US-001: a live actor + registry must yield ok=true")
	assert_true(descriptor.candidate_options is Array, "US-001: returned object must expose candidate_options (a real SelectionDescriptor field, not an ad-hoc Dictionary)")
	var ids: Array = _option_ids(descriptor.candidate_options)
	assert_true(ids.has("STRIDE"), "US-001: legal next-pick verbs must be surfaced in candidate_options")
	assert_true(ids.has("STRIKE"), "US-001: legal next-pick verbs must be surfaced in candidate_options")
	assert_eq(descriptor.order_index, 0, "US-001: order_index must be present on the returned descriptor")
	assert_true(descriptor.meta is Dictionary, "US-001: meta must be present (a Dictionary) on the returned descriptor")
	# The pre-fix bug returned a bare {ok, queue}-only Dictionary -- proving
	# candidate_hexes/candidate_targets are ALSO present (even if empty for
	# this verb-pick step) rules that regression out.
	assert_true(descriptor.candidate_hexes is Array, "US-001: candidate_hexes must be present, proving this is not the old {ok, queue}-only shape")
	assert_true(descriptor.candidate_targets is Array, "US-001: candidate_targets must be present, proving this is not the old {ok, queue}-only shape")
