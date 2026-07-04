## presentation/cancel_controller.gd — CancelController (FEAT-176 / US-012 /
## FR-007; ADR-005).
##
## Presentation layer (Clean Architecture): the ONE cancel/back affordance for
## EVERY Layer 2 (target/destination selection) mode a Layer 1 verb
## (VerbBarView, FEAT-004) may enter — Strike, Step, Stride, and any future
## verb registered the same generic way (mirrors presentation/
## selection_overlay.gd's own verb-agnostic discipline: this file contains NO
## "if verb_id == ..." branching of its own).
##
## THIS FEATURE'S CORE GUARANTEE (US-012 / FR-007, ADR-005): cancelling a
## Layer 2 selection is a PURE no-op path with respect to game state. This
## controller holds NO reference to `_verb_registry`, ActionResolverPort,
## MovementPort, TurnPort, or any Application-layer use case whatsoever — the
## ONLY collaborator it is ever configured with is the already-instantiated
## presentation/selection_overlay.gd SelectionOverlay, and the ONLY method it
## ever calls on it is SelectionOverlay.cancel() (added by this feature — see
## that file's own doc), which itself never touches the registry either (it
## only clears local Layer 2 state and blanks HexGridView's highlight). This
## is what makes "CancelController never invokes ActionResolverPort/
## MovementPort/TurnPort methods" true BY CONSTRUCTION, not merely by
## discipline — there is no port reference anywhere in this file for a future
## edit to accidentally wire up.
##
## Three affordances, ALL routed through the SAME cancel() entry point (design
## notes: "Esc/right-click/Cancel button"):
##   1. Esc key — detected in _unhandled_input() (InputEventKey, KEY_ESCAPE).
##   2. Right-click — detected in _unhandled_input() (InputEventMouseButton,
##      MOUSE_BUTTON_RIGHT), anywhere on screen (mirrors presentation/
##      hex_grid_view.gd's own _unhandled_input() left-click-anywhere
##      convention — this controller does not require the cancelling click to
##      land on any particular hex).
##   3. Cancel button — press_cancel_button() is the method a future Cancel
##      Button Control's `pressed` signal binds to (no companion .tscn is
##      introduced by this feature; see cancel()'s doc for why any UI trigger,
##      present or future, funnels through the identical code path).
##
## A plain presentation adapter (mirrors presentation/movement_input_
## controller.gd's / presentation/selection_overlay.gd's "no companion .tscn,
## instantiated directly by the composition root, plain RefCounted, never
## added to the scene tree" precedent — see tests/infrastructure/
## test_presentation_stack_wiring.gd's exact-child-set invariant, which this
## file must not grow). Since a RefCounted never receives engine
## _unhandled_input() callbacks, MainScene.gd (which IS already a live
## SceneTree Node) overrides _unhandled_input() itself and forwards every
## event straight to this controller's handle_input() below — mirroring how
## HexGridView's own _unhandled_input() is the ONE place a raw InputEvent is
## translated into a Presentation-level call in this codebase; this file adds
## a second such translation point without adding a second scene Node.

class_name CancelController
extends RefCounted

## selection_cancelled(verb_id) — emitted immediately after a successful
## cancel (i.e. a Layer 2 selection WAS active and has now been cleared),
## carrying the verb_id that was cancelled. Mirrors presentation/
## selection_overlay.gd's own selection_resolved/selection_rejected
## observability convention. Never emitted when there was nothing to cancel
## (Layer 1 already active) — see cancel()'s doc.
signal selection_cancelled(verb_id: String)

## The injected presentation/selection_overlay.gd SelectionOverlay — the ONLY
## collaborator this controller is ever configured with (see file-level doc
## for why no registry/port reference exists anywhere in this file).
var _selection_overlay = null


## configure(selection_overlay) -> void — injects the SelectionOverlay this
## controller cancels. Safe to call again (e.g. a future encounter reload)
## with no leaked state — this controller holds no other collaborator to
## reconfigure.
func configure(selection_overlay) -> void:
	_selection_overlay = selection_overlay


## cancel() -> bool — the SINGLE entry point every affordance (Esc, right-
## click, Cancel button) funnels through. Delegates directly to
## SelectionOverlay.cancel() — no registry, no use case, no port call is ever
## reachable from this method. Returns true iff a Layer 2 selection was
## actually active and has now been cancelled (Layer 1 resumed); returns
## false (a true no-op) when Layer 1 was already active or no overlay is
## configured, so pressing Esc/right-click/Cancel outside of any Layer 2
## selection never does anything at all.
func cancel() -> bool:
	if _selection_overlay == null:
		return false
	var verb_id: String = _selection_overlay.get_active_verb_id()
	var cancelled: bool = _selection_overlay.cancel()
	if cancelled:
		selection_cancelled.emit(verb_id)
		print("INFO: selection_cancelled verb_id=" + verb_id)
	return cancelled


## press_cancel_button() -> bool — alias for cancel(), named for the "Cancel
## button" affordance (design notes: "Esc/right-click/Cancel button"). A
## future Cancel Button Control's `pressed` signal should connect to this
## method (or to cancel() directly — they are identical); no new Control node
## is introduced by this feature (see file-level doc).
func press_cancel_button() -> bool:
	return cancel()


## handle_input(event) -> bool — translates Esc-key-pressed and
## right-click-pressed input events into cancel() calls. Purely an
## input-translation concern (ADR-001: no Layer 2 rule is evaluated here) —
## mirrors presentation/hex_grid_view.gd's own _unhandled_input() convention
## exactly, except this controller has no _unhandled_input() of its own to
## override (it is a RefCounted, never added to the scene tree — see
## file-level doc); MainScene.gd's own _unhandled_input() calls this method
## for every event it receives. Returns true (the event was consumed) only
## when the event names Esc/right-click AND a cancel actually happened, so an
## Esc/right-click with no active Layer 2 selection is left unconsumed for
## any other listener to handle.
func handle_input(event: InputEvent) -> bool:
	var is_escape_pressed: bool = (
		event is InputEventKey and event.pressed and not event.echo
		and event.keycode == KEY_ESCAPE
	)
	var is_right_click_pressed: bool = (
		event is InputEventMouseButton and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	)

	if not (is_escape_pressed or is_right_click_pressed):
		return false

	return cancel()
