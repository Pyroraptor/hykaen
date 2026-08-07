## presentation/verb_dispatch_controller.gd — VerbDispatchController
## (FEAT-007/FEAT-010; US-005/US-009; FR-006/FR-009; ADR-002).
##
## Presentation layer (Clean Architecture, ADR-001): a primary/driving
## controller extracted VERBATIM (same algorithm/behavior) from MainScene.gd's
## former `_build_verb_registry()` / `_verb_bar_current_action_economy()` /
## `_verb_bar_<verb>_availability()` / `_verb_bar_<verb>_enter_selection()` /
## `_verb_bar_<verb>_execute()` methods (one triple per VERB_TABLE entry) and
## the `_on_verb_bar_selection_entered()` / `_on_selection_overlay_resolved()`
## Layer-1/Layer-2 signal handlers — this file is now the SOLE owner of
## verb-bar dispatch and VerbBarRegistry construction (US-009's composition-
## root line-count budget, ADR-001 fitness functions).
##
## MainScene.gd `.new()`s this controller once and hands it its dependencies
## via `setup(main_scene)` — a direct reference to the composition root
## itself (mirrors presentation/combine_queue_build_session.gd's
## `_WeakOptionTarget` doc: a RefCounted holding a reference to a Node is
## never a collection-blocking cycle, since Node lifetime is scene-tree/
## manual-free driven, not refcount driven — only RefCounted<->RefCounted
## cycles need the weakref indirection that class uses). Every collaborator
## this controller reads (`_controller(verb_id)`, `round_session`, `_party`,
## `_enemies`, `combine_queue_build_session`, `combine_targeting_session`,
## `selection_overlay`, `_spell_picker`, `verb_bar_view`, `status_panel_view`)
## is read FRESH off the injected `main_scene` reference on every call — never
## a snapshot — exactly mirroring the pre-extraction methods' own "reads fresh
## off `self`" discipline (see e.g. `_current_party()`'s doc on MainScene.gd).
##
## `_controller(verb_id)` / `_verb_deps()` / `_controllers` deliberately
## remain on MainScene.gd, UNCHANGED (see tests/boot/
## test_cast_spell_verb_deps_composition_root_wiring.gd's own FEAT-007 doc) —
## this controller reaches them through `main_scene._controller(verb_id)`, the
## EXACT SAME lookup every other verb (and Combine's own sub-action
## resolution, `core/controllers/combine_action_controller.gd`'s
## `controller_for` seam) already resolves through. No second/forked
## controller-resolution path is introduced (ADR-002).
##
## API contract (ADR-005's signal-based/Dictionary-return error vocabulary —
## GDScript has no exceptions):
##   setup(main_scene) -> void
##     Wires this controller's sole collaborator. Must be called exactly
##     once, before build_verb_registry()/any `_verb_bar_*` method.
##
##   build_verb_registry(verb_table: Dictionary) -> VerbBarRegistryAdapter
##     Loops `verb_table` (MainScene's own VERB_TABLE constant, injected here
##     rather than duplicated — VERB_TABLE remains "the sole place a verb is
##     enumerated", MainScene.gd's own doc) and registers each verb's
##     availability()/enter_selection()/execute() as a Callable bound to
##     THIS controller (`Callable(self, ...)`) — adding a verb is still ~one
##     VERB_TABLE entry + its controller file + three thin `_verb_bar_<verb>_*`
##     methods here, mirroring the pre-extraction convention exactly.
##
##   `_verb_bar_<verb>_availability()` / `_verb_bar_<verb>_enter_selection()`
##   / `_verb_bar_<verb>_execute(selection)` — one triple per VERB_TABLE verb
##     (STRIKE/STEP/STRIDE/END_TURN/CAST_SPELL/COMBINE). Every triple except
##     COMBINE's own `enter_selection()` is a thin delegate to
##     `main_scene._controller(verb_id)`; COMBINE's `enter_selection()`
##     starts `main_scene.combine_queue_build_session`'s interactive
##     queue-build pick loop directly (unchanged behavior).
##
##   _on_verb_bar_selection_entered(verb_id, selection) -> void /
##   _on_selection_overlay_resolved(verb_id, result) -> void
##     The Layer-1 -> Layer-2 and Layer-2-resolved signal handlers
##     (VerbBarView.verb_selection_entered / SelectionOverlay.selection_resolved),
##     connected to THIS controller's methods directly by MainScene's
##     `_ready()` (`verb_bar_view.verb_selection_entered.connect(verb_dispatch_controller._on_verb_bar_selection_entered)`).
##
## Depends only on: infrastructure/verb_bar_registry_adapter.gd (the adapter
## constructed and returned by build_verb_registry()) plus whatever the
## injected `main_scene` reference exposes. Zero direct SQL/HTTP/domain-rule
## concerns of its own — every actual verb execution is delegated straight
## through `main_scene._controller(verb_id)` to the real, already-tested
## ActionController subclasses (StrikeActionController, StepActionController,
## ...), exactly as MainScene's own pre-extraction shims did.

class_name VerbDispatchController
extends RefCounted

const VerbBarRegistryAdapterClass = preload("res://infrastructure/verb_bar_registry_adapter.gd")

var _controller_fn: Callable
var _round_session_fn: Callable
var _combine_queue_build_session = null
var _combine_targeting_session = null
var _selection_overlay = null
var _spell_picker = null
var _verb_bar_view = null
var _status_panel_view = null
var _party_fn: Callable
var _enemies_fn: Callable
var _turn_presentation_fn: Callable


## setup(deps) -> void — injects all collaborators. Must be called exactly
## once, before build_verb_registry()/any `_verb_bar_*` method below.
func setup(deps: Dictionary) -> void:
	_controller_fn = deps["controller_fn"]
	_round_session_fn = deps["round_session_fn"]
	_combine_queue_build_session = deps["combine_queue_build_session"]
	_combine_targeting_session = deps["combine_targeting_session"]
	_selection_overlay = deps["selection_overlay"]
	_spell_picker = deps["spell_picker"]
	_verb_bar_view = deps.get("verb_bar_view")
	_status_panel_view = deps.get("status_panel_view")
	_party_fn = deps["party_fn"]
	_enemies_fn = deps["enemies_fn"]
	_turn_presentation_fn = deps["turn_presentation_fn"]


## build_verb_registry(verb_table) -> VerbBarRegistryAdapterClass — loops
## `verb_table` (MainScene's own VERB_TABLE) and registers each verb's three
## thin `_verb_bar_<verb>_*` methods on THIS controller. See file-level doc.
func build_verb_registry(verb_table: Dictionary) -> VerbBarRegistryAdapterClass:
	var registry := VerbBarRegistryAdapterClass.new()

	for verb_id in verb_table:
		var suffix: String = verb_id.to_lower()
		registry.register(
			verb_id,
			Callable(self, "_verb_bar_%s_availability" % suffix),
			Callable(self, "_verb_bar_%s_enter_selection" % suffix),
			Callable(self, "_verb_bar_%s_execute" % suffix),
		)

	return registry


## _verb_bar_current_action_economy() -> ActionEconomy or null — the SAME
## live ActionEconomy `round_session.current_action_economy()` already
## exposes, read here only for its get_remaining() count.
func _verb_bar_current_action_economy():
	var round_session = _round_session_fn.call()
	if round_session == null:
		return null
	return round_session.current_action_economy()


func _verb_bar_strike_availability() -> bool:
	return _controller_fn.call("STRIKE").availability()


func _verb_bar_strike_enter_selection() -> Dictionary:
	return _controller_fn.call("STRIKE").enter_selection()


func _verb_bar_strike_execute(selection) -> Dictionary:
	return await _controller_fn.call("STRIKE").execute(selection)


func _verb_bar_step_availability() -> bool:
	return _controller_fn.call("STEP").availability()


func _verb_bar_step_enter_selection() -> Dictionary:
	return _controller_fn.call("STEP").enter_selection()


func _verb_bar_step_execute(selection) -> Dictionary:
	# FEAT-006: StepActionController.execute() now `await`s an optional
	# hex_grid_view.animate_token_to() call before returning, mirroring
	# STRIDE/CAST_SPELL/COMBINE's own `await`ed dispatch below -- required
	# so a future hex_grid_view composition-root wiring for STEP does not
	# silently truncate this coroutine into a GDScriptFunctionState.
	return await _controller_fn.call("STEP").execute(selection)


func _verb_bar_stride_availability() -> bool:
	return _controller_fn.call("STRIDE").availability()


func _verb_bar_stride_enter_selection() -> Dictionary:
	return _controller_fn.call("STRIDE").enter_selection()


func _verb_bar_stride_execute(selection) -> Dictionary:
	return await _controller_fn.call("STRIDE").execute(selection)


func _verb_bar_end_turn_availability() -> bool:
	return _controller_fn.call("END_TURN").availability()


func _verb_bar_end_turn_enter_selection() -> Dictionary:
	return _controller_fn.call("END_TURN").enter_selection()


func _verb_bar_end_turn_execute(_selection = null) -> Dictionary:
	return _controller_fn.call("END_TURN").execute(_selection)


func _verb_bar_cast_spell_availability() -> bool:
	return _controller_fn.call("CAST_SPELL").availability()


func _verb_bar_cast_spell_enter_selection() -> Dictionary:
	return _controller_fn.call("CAST_SPELL").enter_selection()


func _verb_bar_cast_spell_execute(selection = null) -> Dictionary:
	return await _controller_fn.call("CAST_SPELL").execute(selection)


func _verb_bar_combine_availability() -> bool:
	return _controller_fn.call("COMBINE").availability()


## _verb_bar_combine_enter_selection() -> Dictionary — the LIVE entry point
## VerbBarRegistry actually invokes for a real player's COMBINE press.
## Delegates to `combine_queue_build_session.start(actor)` -- the interactive
## BuildVerbQueueUseCase/ConfirmQueueUseCase-backed queue-builder loop -- which
## drives SelectionOverlay directly. No verb_id is ever hardcoded here -- the
## real, live candidate pool is asked for fresh on every pick.
func _verb_bar_combine_enter_selection() -> Dictionary:
	var round_session = _round_session_fn.call()
	var actor = round_session.current_actor() if round_session != null else null
	_combine_queue_build_session.start(actor)
	return {}  # combine_queue_build_session.start() drives SelectionOverlay directly


func _verb_bar_combine_execute(selection = null) -> Dictionary:
	return await _controller_fn.call("COMBINE").execute(selection)


## _on_verb_bar_selection_entered(verb_id, selection) -> void — forwards
## VerbBarView's own verb_selection_entered signal straight to
## selection_overlay.activate(), UNLESS a Combine build/targeting session is
## already driving SelectionOverlay directly.
func _on_verb_bar_selection_entered(verb_id: String, selection) -> void:
	if _combine_targeting_session.is_active() or _combine_queue_build_session.is_active():
		return  # combine_targeting_session.start()/combine_queue_build_session.start() already drove SelectionOverlay directly
	_selection_overlay.activate(verb_id, selection)
	if _selection_overlay.is_awaiting_option():
		_spell_picker.show(_selection_overlay.get_candidate_options(), Callable(_selection_overlay, "choose_option"))


## _on_selection_overlay_resolved(_verb_id, _result) -> void — fires once
## selection_overlay resolves a highlighted target/hex click through
## `_verb_registry.execute()`. Re-gates $VerbBarView, re-derives the Layer 1
## Step/Stride highlight, and pushes fresh action-budget/HP values.
func _on_selection_overlay_resolved(_verb_id: String, _result) -> void:
	# A resolved COMBINE pick while the interactive queue-BUILD loop is
	# active routes to `combine_queue_build_session.advance()` instead, never
	# touching `_verb_registry`/`verb_bar_view`/highlight state a standalone
	# verb resolution would.
	if _combine_queue_build_session.is_active() and _verb_id == "COMBINE":
		_combine_queue_build_session.advance()
		return
	if _combine_targeting_session.try_advance(_verb_id):
		return

	_spell_picker.hide()
	if _verb_bar_view != null:
		_verb_bar_view.refresh_availability()

	var round_session = _round_session_fn.call()
	if round_session != null:
		# highlight_legal_moves is instance-native (it configures the
		# mutating movement controller), so pass the LIVE actor instance.
		var actor = round_session.current_actor_entity()
		if actor != null:
			_turn_presentation_fn.call().highlight_legal_moves(actor, actor.display_id())
			# Push action budget to StatusPanelView. Strike already does this
			# via AttackEvent, but Cast Spell / Continue Cast spend actions
			# without emitting any event, so an explicit push is required
			# here (mirrors StrideActionController's pattern).
			var ae = round_session.current_action_economy()
			if ae != null and _status_panel_view != null:
				_status_panel_view.on_verb_action_budget_changed(
					actor.display_id(), ae.get_remaining(), ae.is_spent()
				)
		# Push fresh HP values for all combatants after any spell resolution.
		# Spell damage is applied via EffectsApplier (no AttackEvent emitted),
		# so on_attack_event() never fires -- an explicit HP push is required
		# (mirrors the action-budget push above for the same reason).
		if _status_panel_view != null:
			for combatant in _party_fn.call() + _enemies_fn.call():
				_status_panel_view.update_combatant_hp(combatant.display_id(), combatant.hp_current)
				_status_panel_view.update_conditions(combatant.display_id(), combatant.conditions)
