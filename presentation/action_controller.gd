extends RefCounted

## ActionController — abstract base for the composition root's verb-bar action
## controllers (the Command pattern, FEAT-004 / US-004). Each concrete verb
## extends this and implements the three-method verb contract below:
## availability() / enter_selection() / execute(selection). Today's verbs are
## Strike / Step / Stride / End Turn; a future SpellActionController (Cast a
## Spell) or CombineActionController (combinations) extends this the SAME way and
## needs zero changes here.
##
## Composition-root de-bloat (2026-07-10): the machinery every verb shares — live
## session access through the stable RoundSessionHolder, and the current-actor /
## current-action-economy reads each verb's availability gate uses — lives here
## once, so the concrete controllers stay small and modular. MainScene keeps thin
## _verb_bar_<verb>_<method> shims that delegate to the concrete controller, so
## the VerbBarRegistry Callable(self, …) registrations and the direct-call tests
## are unchanged. Referenced (per subclass) via preload consts, not class_name,
## keeping standalone --check-only parses working and honoring the "wired only by
## MainScene" discipline the inner adapters follow.

## Constructed with a single `deps: Dictionary` (composition-root data-driven verb
## table, 2026-07-11): MainScene owns ONE memoized `_verb_deps()` dict keyed by
## documented collaborator names and instantiates every verb via
## `VERB_TABLE[verb_id].new(_verb_deps())`, so a future Combine controller can
## resolve any sub-action controller through the single `_controller(verb_id)`
## lookup, and adding a verb is one VERB_TABLE entry (no per-verb positional
## constructor). Each subclass reads only the keys it needs from `deps`; the base
## needs `deps["session_holder"]` (the stable RoundSessionHolder). No test
## constructs these positionally, so widening `_init` to a dict is safe.
var _session_holder


func _init(deps: Dictionary) -> void:
	if not deps.has("session_holder"):
		push_error("ActionController: deps missing required key \"session_holder\"")
	_session_holder = deps.get("session_holder", null)


## _session() — the live RoundSession for the current round (null before the
## first round begins), reached through the stable holder so it is never a stale
## per-round reference.
func _session():
	return _session_holder.get_current()


## current_actor() -> Dictionary — the session's current actor, or {} when there
## is no live session.
func current_actor() -> Dictionary:
	var session = _session()
	return session.current_actor() if session != null else {}


## current_actor_entity() -> Combatant or null — the LIVE current-actor instance
## (never a to_dict() copy), for verbs whose execute() feeds the actor into a
## MUTATING seam (resolve()/ResolveStrideUseCase), where the entity must travel
## by reference so take_damage()/move_to() land on the container's instance.
## Null when there is no live session (mirrors current_actor()'s empty sentinel).
func current_actor_entity():
	var session = _session()
	return session.current_actor_entity() if session != null else null


## current_action_economy() — the current actor's live ActionEconomy (the SAME
## instance round_session.current_action_economy() exposes), or null when there
## is no live session. Every verb's availability gate reads this.
func current_action_economy():
	var session = _session()
	return session.current_action_economy() if session != null else null


# ── Verb contract — concrete subclasses OVERRIDE these three. The base defaults
# are deliberately inert (unavailable / empty / not-ok) so an un-overridden verb
# fails safe rather than crashing. ─────────────────────────────────────────────

func availability() -> bool:
	return false


func enter_selection() -> Dictionary:
	return {}


## SelectionShape — FEAT-009 (US-009, design notes API contract #5): the three
## shapes execute()'s `selection` argument may now take, additively:
##   SCALAR       — the existing, unchanged shape (a target_id String, a
##                   HexCoord, or null) every pre-existing verb (Strike/Step/
##                   Stride/End Turn) already passes.
##   OPTION_TARGET — a Layer-2a option paired with a Layer-2b target (a
##                   Dictionary carrying both an "option" and a "target" key —
##                   the same pairing core/application/resolved_selection.gd's
##                   ResolvedSelection.option_then_target() produces).
##   TARGET_SET    — an AREA-resolved list of targets/hexes (a plain Array —
##                   mirrors ResolvedSelection.area_set()'s target_set).
## Strike/Step/Stride/End Turn each override execute() ENTIRELY (never call
## super.execute()), so none of this machinery is reachable from them at
## all — purely additive groundwork for a future verb that instead overrides
## only expected_shape() + the shape-specific _execute_*() handler below.
enum SelectionShape {
	SCALAR,
	OPTION_TARGET,
	TARGET_SET,
}

## Human-readable labels for SelectionShape, used only to build the
## shape-mismatch diagnostic message below (Dictionary, not
## SelectionShape.keys(), so the message stays stable even if enum member
## order ever changes).
const _SHAPE_NAMES: Dictionary = {
	SelectionShape.SCALAR: "SCALAR",
	SelectionShape.OPTION_TARGET: "OPTION_TARGET",
	SelectionShape.TARGET_SET: "TARGET_SET",
}


## _classify_selection(selection) -> SelectionShape — inspects the RUNTIME
## shape of `selection` and returns which of the three additive shapes it
## matches. A Dictionary carrying both "option" and "target" keys is
## OPTION_TARGET; any other Array is TARGET_SET; everything else (String,
## HexCoord, null, int, ...) is SCALAR — the existing shape every verb
## registered before this feature already hands execute().
func _classify_selection(selection) -> int:
	if selection is Dictionary and selection.has("option") and selection.has("target"):
		return SelectionShape.OPTION_TARGET
	if selection is Array:
		return SelectionShape.TARGET_SET
	return SelectionShape.SCALAR


## expected_shape() -> SelectionShape — which shape THIS verb's execute()
## `selection` argument is contracted to receive. Defaults to SCALAR, so
## every verb registered before this feature (Strike/Step/Stride/End Turn)
## — none of which override this — keeps the legacy scalar contract
## unchanged. A future OPTION_TARGET/TARGET_SET verb overrides this
## alongside its matching _execute_*() handler below.
func expected_shape() -> int:
	return SelectionShape.SCALAR


## execute(selection) -> Dictionary — FEAT-009 (US-009): the additive shape
## dispatch. Classifies `selection`'s runtime shape and, when it matches this
## verb's expected_shape(), routes to the matching _execute_*() handler
## below. A verb that instead overrides execute() directly (every verb
## registered before this feature) never reaches this method at all, so
## nothing here can regress an existing single-scalar caller like Strike —
## the widened contract is additive machinery for callers that opt in by
## NOT overriding execute().
##
## Shape mismatch (e.g. a SCALAR-only verb handed a TARGET_SET) is a wiring
## bug, not a runtime/user error: fail-fast in dev/test via assert() (which
## the engine compiles out of release exports), fail-soft with a logged
## no-op Dictionary in a shipped build (design notes' error_handling policy
## #5) — mirrors core/domain/effects_applier.gd's identical
## assert()+push_error()+fail-soft-return convention for its own contract
## violations.
func execute(selection = null) -> Dictionary:
	var shape: int = _classify_selection(selection)
	var expected: int = expected_shape()

	if shape != expected:
		var message: String = (
			"ActionController: selection shape mismatch -- expected %s but received %s"
			% [_SHAPE_NAMES.get(expected, str(expected)), _SHAPE_NAMES.get(shape, str(shape))]
		)
		assert(false, message)
		push_error(message)
		return {"ok": false, "error": "ERR_SHAPE_MISMATCH"}

	match shape:
		SelectionShape.OPTION_TARGET:
			return _execute_option_target(selection.get("option"), selection.get("target"))
		SelectionShape.TARGET_SET:
			return _execute_target_set(selection)
		_:
			return _execute_scalar(selection)


## _execute_scalar(selection) -> Dictionary — SCALAR-shape handler. Override
## in a subclass that opts into the base execute() dispatch above instead of
## overriding execute() directly. Deliberately inert default (mirrors the
## pre-existing execute() default), so an un-overridden verb fails safe.
func _execute_scalar(_selection) -> Dictionary:
	return {"ok": false}


## _execute_option_target(option, target) -> Dictionary — OPTION_TARGET-shape
## handler. Deliberately inert default.
func _execute_option_target(_option, _target) -> Dictionary:
	return {"ok": false}


## _execute_target_set(targets) -> Dictionary — TARGET_SET-shape handler.
## Deliberately inert default.
func _execute_target_set(_targets: Array) -> Dictionary:
	return {"ok": false}
