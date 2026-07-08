## core/application/ports/reaction_window_port.gd — ReactionWindowPort
## (FEAT-009 / US-009 / FR-005, ADR-014)
##
## Application layer (Clean Architecture): the contract
## core/application/reaction_window.gd's ReactionWindow implements —
## documented here as a Protocol-style base so callers/tests can depend on
## the abstract contract rather than the concrete class, matching this
## project's established port pattern (core/application/ai_decision_port.gd,
## core/application/event_sink_port.gd).
##
## Modeled on core/application/round_session.gd's RoundSession stepwise/
## resumable pattern (ADR-007): rather than resolving a reaction
## synchronously inside one call, open()/resume() split the decision into
## two steps so a caller can yield to an injected ReactionChooserPort
## (which may itself be waiting on a blocking UI modal in Presentation)
## BETWEEN them, without this port itself ever blocking the engine thread —
## open() returns immediately with the legal choices, and resume() is
## invoked later (whenever the chooser produces an answer) to apply the
## decision and close the window.
##
## Contract:
##   open(trigger: Dictionary) -> Dictionary
##     Computes the reactor's legal_reactions for `trigger` (see
##     reaction_window.gd's file-level doc for `trigger`'s shape) and opens
##     a pausable window, emitting a RoundEvents.ReactionWindowOpenedEvent
##     via the injected EventSinkPort. Returns:
##       {window_id: String, legal_reactions: Array, opened: bool}
##     `opened` is false (window_id "", legal_reactions []) when the
##     reactor's ActionEconomy is already Spent — ALREADY_SPENT — the
##     window never opens and no event is emitted; the reaction implicitly
##     resolves to no-reaction.
##
##   resume(window_id: String, choice: String, resolved_by: String) -> Dictionary
##     Applies `choice` (one of the open()-returned legal_reactions, or
##     ReactionChooserPort.PASS) to the still-open window identified by
##     `window_id`, spends the reactor's reaction
##     (ActionEconomy.spend_reaction() — NEVER spend_action()) when
##     choice != PASS, emits a RoundEvents.ReactionResolvedEvent, and closes
##     the window. Returns:
##       {ok: true, window_id: String, choice: String}
##         — choice may differ from the requested one ONLY when the
##           reactor's budget was exhausted by a race between open() and
##           resume() (ALREADY_SPENT); it then falls back to PASS rather
##           than erroring, per this feature's "never hang/crash" error
##           handling policy.
##       {ok: false, error: "STALE_WINDOW"}
##         — window_id doesn't match the currently open window (or no
##           window is open); resume() has no effect.
##       {ok: false, error: "ILLEGAL_CHOICE"}
##         — choice is neither PASS nor a member of the open window's
##           legal_reactions; resume() has no effect, caller must
##           re-submit a legal choice.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance.

class_name ReactionWindowPort
extends RefCounted

## Error codes returned in resume()'s "error" key — see contract doc above.
const ERR_STALE_WINDOW: String = "STALE_WINDOW"
const ERR_ILLEGAL_CHOICE: String = "ILLEGAL_CHOICE"


## open(trigger) -> Dictionary — abstract; concrete implementations
## (reaction_window.gd's ReactionWindow) MUST override.
func open(_trigger: Dictionary) -> Dictionary:
	push_error("ReactionWindowPort.open() is abstract — override in a concrete implementation")
	return {"window_id": "", "legal_reactions": [], "opened": false}


## resume(window_id, choice, resolved_by) -> Dictionary — abstract; concrete
## implementations MUST override.
func resume(_window_id: String, _choice: String, _resolved_by: String = "unknown") -> Dictionary:
	push_error("ReactionWindowPort.resume() is abstract — override in a concrete implementation")
	return {"ok": false, "error": ERR_STALE_WINDOW}
