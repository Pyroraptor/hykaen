## core/application/ports/targeting_port.gd — TargetingPort (FEAT-008 /
## US-008; FR-007, ADR-007)
##
## Application layer (Clean Architecture): documents the contract
## presentation/verbs/resolve_spell_controller.gd's ResolveSpellController
## depends on to ask "which of these already-legal targets is chosen?" once
## a cast reaches resolution (casting_state.remaining_actions == 0) —
## mirrors this project's established Protocol-style port pattern
## (core/application/ports/hex_choice_resolver_port.gd's
## HexChoiceResolverPort, core/application/ports/selection_port.gd's
## SelectionPort): a base class documenting the abstract contract; a
## concrete adapter either `extends` it or simply duck-types it.
##
## DESIGN CHOICE — legal-set-in, single-pick-out (mirrors
## HexChoiceResolverPort exactly, NOT a caster/range_ft/defense-consuming
## signature): design notes' architecture section describes this port's
## shape as "request_single_target(caster, range_ft, defense) -> target",
## but api_contracts #2 clarifies WHERE the range enforcement actually
## happens: "ranged-only, out-of-range targets excluded from the pick set
## (never surfaced as selectable)" — the FILTERING is ResolveSpellController's
## job (using core/geometry/hex_math.gd HexMath.hex_distance(), the SAME
## primitive presentation/strike_action_controller.gd's own
## _reachable_targets() already uses for weapon range_hexes), exactly
## mirroring HexChoiceResolverPort's own established "the caller computes
## legal_hexes; the port only ever picks FROM an already-legal set" division
## of responsibility. This port therefore receives the PRE-FILTERED
## candidate list directly — an out-of-range target can structurally never
## reach a concrete adapter's UI/AI selection logic, closing the same class
## of "a compromised/buggy presentation adapter mutating domain state
## illegitimately" gap design notes' security section calls out for
## SelectionPort/TargetingPort generally.
##
## Contract:
##   request_single_target(legal_targets: Array) -> Combatant | null
##     Returns exactly one member of `legal_targets` (a caster/AI/human
##     picks among them; HOW is entirely the concrete adapter's business —
##     a blocking UI modal, a scripted test double, an AI heuristic).
##     Returns null ONLY when `legal_targets` is empty (api_contracts #2's
##     ERR_NO_VALID_TARGET case — "no in-range target at resolution") — a
##     NON-empty `legal_targets` must NEVER resolve to null, mirroring
##     HexChoiceResolverPort's identical "never silently punt on a
##     non-empty legal set" invariant.
##   request_aoe_targets(legal_targets: Array) -> Array
##     Extension point (design notes' architecture section: "AoE
##     multi-target spells beyond Fire Bolt: TargetingPort.
##     request_aoe_targets is already a distinct method from single-target,
##     ready for area spell data") — not exercised by this feature (Fire
##     Bolt is single-target); declared here only so a later AoE spell
##     feature does not need a breaking port change.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var resolver: TargetingPort = ScriptedTargetingPort.new(skeleton)
##   var chosen = resolver.request_single_target([skeleton, goblin])
##   # chosen -> skeleton (the scripted choice)
##
##   var empty_resolver: TargetingPort = ScriptedTargetingPort.new(null)
##   var none = empty_resolver.request_single_target([])
##   # none -> null (the ONLY legal case for a null return)

class_name TargetingPort
extends RefCounted


## request_single_target(legal_targets) -> Combatant | null — abstract;
## concrete adapters MUST override. The base implementation exists only to
## document the contract and to fail LOUD (push_error), never to
## guess/fabricate a target. Still honors the one universal invariant every
## conforming implementation must uphold: an empty legal_targets always
## yields null immediately — there is nothing to choose from, so there is
## nothing to guess either.
func request_single_target(legal_targets: Array):
	if legal_targets.is_empty():
		return null
	push_error("TargetingPort.request_single_target() is abstract — override in a concrete adapter")
	return null


## request_aoe_targets(legal_targets) -> Array — abstract extension point;
## concrete adapters MAY override once an AoE spell exists (see file-level
## doc). Defaults to returning every legal target unfiltered when
## non-empty (a single-target-only adapter never needs to override this),
## and an empty Array when there is nothing to choose from.
func request_aoe_targets(legal_targets: Array) -> Array:
	return legal_targets.duplicate()
