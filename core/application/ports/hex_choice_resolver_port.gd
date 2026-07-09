## core/application/ports/hex_choice_resolver_port.gd — HexChoiceResolverPort
## (FEAT-001 / US-004, ADR-002)
##
## Application layer (Clean Architecture): the contract a future Dodge-Step
## hex-selection window (US-005/US-006/US-007) will depend on to ask "which
## hex do you want to step to?", without knowing whether the answer comes
## from a human (a live hex click on the battlefield), an AI policy, or a
## scripted test double. Mirrors core/application/ports/
## reaction_chooser_port.gd's EXISTING injection pattern exactly: a
## documented abstract base class concrete adapters extend directly
## (`extends "res://core/application/ports/hex_choice_resolver_port.gd"`),
## wired ONLY at the MainScene.gd composition root (ADR-002/G2 — "ports are
## injected ONLY at the MainScene composition root; no test may self-wire
## the seam under test"). See tests/application/test_hex_choice_resolver_seam.gd
## for the seam-level proof that a scripted hex choice flows through REAL
## MainScene wiring rather than a test-constructed resolver invoked in
## isolation.
##
## Contract:
##   resolve(legal_hexes: Array) -> HexCoord | null
##     Returns exactly one member of `legal_hexes`, chosen by whatever
##     concrete adapter this base is extended by (a human's live click, an
##     AI policy, a scripted test double). Returns null ONLY when
##     `legal_hexes` is empty (US-007's future "no legal adjacent hex" edge
##     case) — a NON-empty `legal_hexes` must NEVER resolve to null; that
##     would be indistinguishable from the legitimate "nothing to choose
##     from" case and would let a caller silently skip a Step it should have
##     prompted for (the forbidden G3 trace-only punt this feature's
##     error_handling design note calls out).
##
## Error handling / anti-punt discipline (G3): an unscripted resolver in
## production MUST require/await real human/UI input for a non-empty
## `legal_hexes` — it may NEVER fabricate/guess an answer on its own (see
## MainScene.gd's `_UIHexChoiceResolver`, the production default this port's
## contract is written for). This base class's own abstract resolve()
## documents that contract and fails LOUD (push_error) rather than ever
## guessing a hex, so a bare HexChoiceResolverPort handed to a caller by
## mistake can never silently misbehave. It still always honors the one
## universal invariant every conforming implementation — including this
## base — must uphold: an empty `legal_hexes` always yields null, never an
## error, since there is nothing to choose from and therefore nothing to
## guess either.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance.
##
## Usage example:
##   var resolver: HexChoiceResolverPort = ScriptedHexChoiceResolver.new(HexCoord.new(1, 0))
##   var chosen = resolver.resolve([HexCoord.new(1, 0), HexCoord.new(0, 1)])
##   # chosen -> HexCoord(q=1, r=0)  (the scripted choice)
##
##   var empty_resolver: HexChoiceResolverPort = ScriptedHexChoiceResolver.new(null)
##   var none = empty_resolver.resolve([])
##   # none -> null (the ONLY legal case for a null return)

class_name HexChoiceResolverPort
extends RefCounted


## resolve(legal_hexes) -> HexCoord | null — abstract; concrete adapters
## MUST override. The base implementation exists only to document the
## contract and to fail LOUD (push_error), never to guess/fabricate a hex.
## Still honors the one universal invariant every conforming implementation
## must uphold: an empty legal_hexes always yields null immediately, never
## an error/await — there is nothing to choose from, so there is nothing to
## guess either.
func resolve(legal_hexes: Array):
	if legal_hexes.is_empty():
		return null
	push_error("HexChoiceResolverPort.resolve() is abstract — override in a concrete adapter")
	return null


## choose_step_hex(defender_id, legal_hexes) -> HexCoord | null — FEAT-001
## (US-001, Dodge-Step steel-thread extension; ADR-001/ADR-002 "no
## duplicate seam"): the Dodge-Step-flavored entry point onto this EXACT
## SAME seam (this steel thread's api_contracts:
## IHexChoicePort.choose_step_hex(defender_id, legal_hexes) -> HexCoord),
## added so a future ResolveDodgeStepUseCase can ask "which legal Step hex
## did `defender_id` pick?" using the vocabulary this steel thread's design
## standardizes on, WITHOUT introducing a second, parallel hex-choice
## resolution algorithm: it is a pure, zero-logic delegation to resolve()
## above — the ONE production implementation every concrete adapter (the
## real MainScene.gd `_UIHexChoiceResolver`, and every scripted test
## double) already provides by inheriting from this base class. Every
## invariant resolve() already documents (null ONLY for an empty
## legal_hexes; a non-empty legal_hexes must never resolve to null) holds
## here unchanged, since this method performs no logic of its own.
##
## `defender_id` is accepted, per the design's IHexChoicePort contract
## shape, but is NOT consulted by this base delegation — resolve()'s own
## legal_hexes-membership contract already fully determines the answer
## regardless of which defender is asking. A future concrete adapter MAY
## override this method to make use of `defender_id` (e.g. a multi-actor
## UI), but doing so can never bypass resolve()'s single authoritative
## resolution path without also overriding resolve() itself.
##
## tests/regression/test_single_hex_choice_seam.gd statically enforces
## that core/application/ports/hex_choice_resolver_port.gd remains the
## ONLY hex-choice seam implementation referenced from the MainScene.gd
## composition root — this method must never grow its own independent
## resolution logic.
func choose_step_hex(_defender_id: String, legal_hexes: Array):
	return resolve(legal_hexes)
