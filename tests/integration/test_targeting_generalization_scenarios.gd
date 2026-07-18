extends GutTest
## tests/integration/test_targeting_generalization_scenarios.gd — FEAT-245
## (US-014).
##
## Consolidated coverage for this iteration's targeting-generalization work
## (FEAT-010's Layer-2a candidate_options step, FEAT-011/FEAT-242's Layer-2b
## AREA_SET origin-pick/preview/confirm step, FEAT-013's post-resolution
## lock groundwork): a SINGLE suite exercising all three of
## candidate_options/OPTION_TARGET, AREA/TARGET_SET, and the pre-existing
## single-target SCALAR verb (Strike) side by side, through the REAL,
## shipped presentation/selection_overlay.gd SelectionOverlay AND the REAL
## presentation/action_controller.gd base-class execute() shape dispatch —
## proving the additive extension is genuinely additive (Strike is
## unaffected) rather than merely asserting each shape in isolation the way
## tests/integration/test_selection_overlay_option_list.gd /
## tests/integration/test_selection_overlay_area_targeting.gd already do
## (those two suites drive SelectionOverlay against a FakeVerbRegistry whose
## execute() is a bare recorder — never a genuine ActionController
## instance).
##
## "Not mocked doubles" (test_criteria #4), concretely:
##   - CAST/BLAST scenarios (Criteria 1-2): a REAL
##     infrastructure/verb_bar_registry_adapter.gd VerbBarRegistryAdapter —
##     the SAME class MainScene.gd's own _build_verb_registry() constructs —
##     registers two REAL presentation/action_controller.gd SUBCLASSES
##     (CastSpellActionController / BlastAreaActionController, mirroring
##     tests/unit/test_action_controller_execute_shapes.gd's established
##     "opt into the base dispatch by overriding expected_shape() + the
##     matching _execute_*() handler, never execute() itself" convention),
##     wired to a REAL presentation/verb_bar_view.tscn VerbBarView and a REAL
##     presentation/hex_grid_view.tscn HexGridView (loaded with a REAL
##     core/domain/combatant.gd Combatant) via the EXACT composition-root
##     wiring MainScene.gd itself establishes
##     (verb_bar_view.verb_selection_entered -> selection_overlay.activate(),
##     see MainScene.gd's _on_verb_bar_selection_entered()). Every
##     execute_calls entry recorded below is written by the REAL base-class
##     execute() -> _classify_selection() -> _execute_option_target()/
##     _execute_target_set() dispatch (action_controller.gd), never by a
##     hand-rolled registry stub.
##   - Strike scenario (Criterion 3): the REAL res://MainScene.tscn
##     composition root, booted exactly as
##     tests/regression/test_strike_end_to_end_unchanged.gd /
##     tests/integration/test_mainscene_player_strike_enemy_reaction.gd
##     already establish — the REAL StrikeActionController, the REAL
##     SelectionOverlay, the REAL VerbBarView/HexGridView.
##
## test_criteria covered:
##   1. test_cast_candidate_options_presents_list_pick_advances_to_targeting_and_executes_option_and_target
##      — candidate_options descriptor presents a Layer-2a list, choosing an
##      option advances to Layer-2b targeting, and a target click resolves
##      through the REAL execute(option, target) dispatch.
##   2. test_blast_area_descriptor_highlights_computed_affected_set_and_resolves_full_set_into_execute
##      — an AREA_SET descriptor highlights the core/geometry-computed
##      affected set on an origin pick and resolves the FULL computed set
##      into the REAL execute() dispatch on confirmation.
##   3. test_strike_single_target_verb_remains_unchanged_end_to_end_in_the_same_suite
##      — Strike (a SCALAR-shaped, execute()-overriding verb) resolves
##      end-to-end through the real UI, completely unaffected by the
##      candidate_options/AREA machinery exercised by Criteria 1-2 above, in
##      the SAME suite.
##   4. every scenario above is driven through the real
##      selection_overlay/action_controller path — see the "not mocked
##      doubles" note.

const HexGridViewScene: PackedScene         = preload("res://presentation/hex_grid_view.tscn")
const VerbBarViewScene: PackedScene         = preload("res://presentation/verb_bar_view.tscn")
const SelectionOverlayClass                 = preload("res://presentation/selection_overlay.gd")
const SelectionDescriptorClass              = preload("res://core/application/selection_descriptor.gd")
const HexCoordClass                         = preload("res://core/geometry/hex_coord.gd")
const CombatantClass                        = preload("res://core/domain/combatant.gd")
const VerbBarRegistryAdapterClass           = preload("res://infrastructure/verb_bar_registry_adapter.gd")
const RoundSessionHolderClass               = preload("res://infrastructure/round_session_holder.gd")

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"

## PROLOGUE_SEED -- this project's established known-good fixture seed
## (mirrors tests/regression/test_strike_end_to_end_unchanged.gd's/
## tests/integration/test_mainscene_player_strike_enemy_reaction.gd's
## identically-valued constant): Titus acts first and the sole enemy
## (Skeleton) starts adjacent to him, so Strike's Layer 2 has at least one
## in-reach target at boot with zero setup needed.
const PROLOGUE_SEED: int = 42


# ── Real ActionController subclasses -- mirror tests/unit/
# test_action_controller_execute_shapes.gd's established convention:
# opt INTO the REAL base class's execute() shape-dispatch machinery by
# overriding ONLY expected_shape() + the matching _execute_*() handler,
# never execute() itself. This is the ONLY way to reach that dispatch code
# genuinely, so a call recorded in execute_calls below proves the REAL
# action_controller.gd pipeline ran, not a test-local stand-in. ───────────

## CastSpellActionController -- an OPTION_TARGET verb (candidate_options,
## FEAT-010/US-010): presents two spell options ahead of a single in-reach
## target, mirroring core/application/selection_descriptor.gd's own
## `cast_descriptor` usage example.
class CastSpellActionController:
	extends "res://presentation/action_controller.gd"

	## [option, target] per REAL _execute_option_target() dispatch.
	var execute_calls: Array = []

	func availability() -> bool:
		return true

	func enter_selection() -> Dictionary:
		return {
			"candidate_targets": ["enemy_0"],
			"candidate_hexes": [],
			"candidate_options": [
				{"id": "fireball", "label": "Fireball"},
				{"id": "ice_bolt", "label": "Ice Bolt"},
			],
		}

	func expected_shape() -> int:
		return SelectionShape.OPTION_TARGET

	func _execute_option_target(option, target) -> Dictionary:
		execute_calls.append([option, target])
		return {"ok": true, "resolved": true, "shape": "OPTION_TARGET", "option": option, "target": target}


## BlastAreaActionController -- a TARGET_SET verb (AREA_SET, FEAT-011/
## FEAT-242/US-011): a single candidate origin hex resolving to a radius-1
## affected-hex set, mirroring core/application/selection_descriptor.gd's
## own `blast_descriptor` usage example.
class BlastAreaActionController:
	extends "res://presentation/action_controller.gd"

	## the resolved target_set Array per REAL _execute_target_set() dispatch.
	var execute_calls: Array = []

	func availability() -> bool:
		return true

	func enter_selection() -> Dictionary:
		return {
			"candidate_hexes": [HexCoordClass.new(0, 0)],
			"candidate_targets": [],
			"resolution_mode": SelectionDescriptorClass.ResolutionMode.AREA_SET,
			"geometry_rule": {"radius": 1},
		}

	func expected_shape() -> int:
		return SelectionShape.TARGET_SET

	func _execute_target_set(targets: Array) -> Dictionary:
		execute_calls.append(targets)
		return {"ok": true, "resolved": true, "shape": "TARGET_SET", "targets": targets}


var _hex_grid_view = null
var _verb_bar_view = null
var _selection_overlay = null
var _registry = null
var _cast_controller: CastSpellActionController = null
var _blast_controller: BlastAreaActionController = null


func _verb_deps() -> Dictionary:
	return {"session_holder": RoundSessionHolderClass.new()}


## before_each() -- builds the CAST/BLAST harness with the EXACT
## composition-root wiring MainScene.gd itself establishes for
## VerbBarView/SelectionOverlay (see MainScene.gd's
## _on_verb_bar_selection_entered()), backed by a REAL
## VerbBarRegistryAdapter, REAL ActionController subclasses, and a REAL
## HexGridView carrying one REAL Combatant token. The Strike scenario boots
## its own separate, full res://MainScene.tscn instance (see
## _boot_main_scene() below) rather than reusing this harness, mirroring
## this project's established "boot-real" convention for Strike.
func before_each() -> void:
	_hex_grid_view = HexGridViewScene.instantiate()
	add_child_autofree(_hex_grid_view)
	_hex_grid_view.load_combatants([
		CombatantClass.new("enemy_0", "Ice Wraith", "Enemy", HexCoordClass.new(2, 0)),
	])

	_cast_controller = CastSpellActionController.new(_verb_deps())
	_blast_controller = BlastAreaActionController.new(_verb_deps())

	_registry = VerbBarRegistryAdapterClass.new()
	_registry.register(
		"CAST",
		Callable(_cast_controller, "availability"),
		Callable(_cast_controller, "enter_selection"),
		Callable(_cast_controller, "execute"),
	)
	_registry.register(
		"BLAST",
		Callable(_blast_controller, "availability"),
		Callable(_blast_controller, "enter_selection"),
		Callable(_blast_controller, "execute"),
	)

	_verb_bar_view = VerbBarViewScene.instantiate()
	add_child_autofree(_verb_bar_view)
	_verb_bar_view.configure(_registry)

	_selection_overlay = SelectionOverlayClass.new()
	_selection_overlay.configure(_registry, _hex_grid_view)

	# The EXACT composition-root wiring MainScene.gd establishes (see
	# MainScene.gd's _on_verb_bar_selection_entered()).
	_verb_bar_view.verb_selection_entered.connect(
		func(verb_id, selection): _selection_overlay.activate(verb_id, selection)
	)


func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	return instance


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — candidate_options descriptor presents a Layer-2a list, an
# option pick advances to Layer-2b targeting, and execute(option, target) is
# invoked correctly through the REAL action_controller.gd dispatch.
# ══════════════════════════════════════════════════════════════════════════

func test_cast_candidate_options_presents_list_pick_advances_to_targeting_and_executes_option_and_target() -> void:
	var selection: Dictionary = _verb_bar_view.press("CAST")

	assert_true(
		selection.get("candidate_options", []).size() == 2,
		"CAST's REAL CastSpellActionController.enter_selection() must present exactly two candidate_options"
	)
	assert_true(_selection_overlay.is_active(), "pressing CAST must enter Layer 2")
	assert_true(_selection_overlay.is_awaiting_option(), "candidate_options must present Layer-2a BEFORE Layer-2b targeting begins")
	assert_eq(_selection_overlay.get_highlighted_target_ids(), [], "no target may be highlighted before an option is chosen")
	assert_eq(_cast_controller.execute_calls, [], "no execute() call may occur before an option AND a target are both chosen")

	var fireball := {"id": "fireball", "label": "Fireball"}
	_selection_overlay.choose_option(fireball)

	assert_false(_selection_overlay.is_awaiting_option(), "choosing an option must end Layer-2a's pending state")
	assert_true(_selection_overlay.is_active(), "Layer 2 (now Layer-2b targeting) must remain active after choosing an option")
	assert_eq(
		_selection_overlay.get_highlighted_target_ids(), ["enemy_0"],
		"Layer-2b must highlight the descriptor's candidate_targets once an option is chosen"
	)

	var target_token = _hex_grid_view.get_token("enemy_0")
	assert_not_null(target_token, "fixture assumption: enemy_0 has a rendered HexGridView token")

	watch_signals(_selection_overlay)
	_hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_signal_emitted(_selection_overlay, "selection_resolved", "clicking the highlighted target after choosing an option must resolve")
	assert_eq(
		_cast_controller.execute_calls, [[fireball, "enemy_0"]],
		"the REAL action_controller.gd base-class execute() -> _classify_selection() -> _execute_option_target() dispatch must have run with exactly the chosen option and the resolved target"
	)
	assert_false(_selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the option/target selection resolves")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — an AREA descriptor highlights the computed affected set on
# an origin pick and resolves the FULL computed set into execute() through
# the REAL action_controller.gd dispatch.
# ══════════════════════════════════════════════════════════════════════════

func test_blast_area_descriptor_highlights_computed_affected_set_and_resolves_full_set_into_execute() -> void:
	var selection: Dictionary = _verb_bar_view.press("BLAST")

	assert_eq(
		selection.get("resolution_mode"), SelectionDescriptorClass.ResolutionMode.AREA_SET,
		"BLAST's REAL BlastAreaActionController.enter_selection() must name resolution_mode AREA_SET"
	)
	assert_true(_selection_overlay.is_active(), "pressing BLAST must enter Layer 2")

	var origin := HexCoordClass.new(0, 0)
	watch_signals(_selection_overlay)
	_hex_grid_view.hex_clicked.emit(origin)

	assert_signal_not_emitted(_selection_overlay, "selection_resolved", "an origin pick must only preview -- it must never resolve by itself")
	assert_true(_selection_overlay.is_awaiting_area_confirm(), "picking the candidate origin hex must enter the AREA preview/awaiting-confirm state")

	var preview: Array = _selection_overlay.get_highlighted_hexes()
	assert_eq(preview.size(), 7, "the preview must be the full radius-1 affected set (origin + 6 neighbors), not just the clicked origin hex")
	assert_eq(_blast_controller.execute_calls, [], "no execute() call may occur until the preview is confirmed")

	# Confirmation: a second click landing within the previewed set (the
	# origin hex itself, always a member of its own affected set).
	_hex_grid_view.hex_clicked.emit(origin)

	assert_signal_emitted(_selection_overlay, "selection_resolved", "confirming the preview must resolve the AREA selection")
	assert_eq(_blast_controller.execute_calls.size(), 1, "exactly one REAL execute() call must occur on confirmation")

	var resolved_targets: Array = _blast_controller.execute_calls[0]
	assert_eq(
		resolved_targets.size(), 7,
		"the REAL action_controller.gd base-class execute() -> _classify_selection() -> _execute_target_set() dispatch must receive the FULL computed 7-hex target set, not just the clicked origin"
	)
	assert_false(_selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the AREA selection resolves")
	assert_false(_selection_overlay.is_awaiting_area_confirm(), "the AREA preview/awaiting-confirm state must be cleared once resolved")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 (regression, in the SAME suite) — Strike, a single-target
# SCALAR verb that overrides execute() entirely, remains unchanged end to
# end, unaffected by the candidate_options/AREA machinery Criteria 1-2 just
# exercised.
# ══════════════════════════════════════════════════════════════════════════

func test_strike_single_target_verb_remains_unchanged_end_to_end_in_the_same_suite() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var skeleton = _skeleton(instance)
	var skeleton_id: String = skeleton.combatant_id

	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	assert_eq(
		selection.get("candidate_options", []), [],
		"STRIKE must still present zero candidate_options -- the additive Layer-2a extension is opt-in per verb, never automatic"
	)
	assert_true(instance.selection_overlay.is_active(), "pressing STRIKE must enter Layer 2, exactly as before this feature")
	assert_false(
		instance.selection_overlay.is_awaiting_option(),
		"the additive candidate_options/Layer-2a extension must remain completely inert for STRIKE, even in a suite that also exercises CAST's Layer-2a"
	)
	assert_false(
		instance.selection_overlay.is_awaiting_area_confirm(),
		"the additive AREA_SET/Layer-2b extension must remain completely inert for STRIKE, even in a suite that also exercises BLAST's AREA preview"
	)

	var target_token = instance.hex_grid_view.get_token(skeleton_id)
	assert_not_null(target_token, "fixture assumption: the Skeleton has a rendered HexGridView token")

	watch_signals(instance.selection_overlay)
	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)

	assert_signal_emitted(instance.selection_overlay, "selection_resolved", "a click landing on the highlighted target's hex must resolve through the REAL SelectionOverlay, exactly as before this feature")
	var resolved_params: Array = get_signal_parameters(instance.selection_overlay, "selection_resolved")
	assert_eq(resolved_params[0], "STRIKE", "selection_resolved must carry the STRIKE verb_id")
	assert_true(resolved_params[1] is Dictionary, "selection_resolved's result must be the REAL StrikeActionController.execute() return Dictionary verbatim")
	assert_true(
		resolved_params[1].get("resolved", false),
		"STRIKE must still resolve normally end to end through the real selection_overlay/action_controller pipeline, unaffected by the additive OPTION_TARGET/TARGET_SET machinery exercised elsewhere in this suite"
	)
	assert_false(instance.selection_overlay.is_active(), "SelectionOverlay must return to Layer 1 once the real click resolves the Strike, exactly as before this feature")
