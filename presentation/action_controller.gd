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


func execute(_selection = null) -> Dictionary:
	return {"ok": false}
