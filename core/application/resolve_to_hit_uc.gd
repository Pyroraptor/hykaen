## core/application/resolve_to_hit_uc.gd — ResolveToHitUseCase
## (FEAT-002 / US-001, ADR-001)
##
## Application layer (Clean Architecture): the APPLICATION-layer half of the
## ADR-001 two-phase Strike-resolution split. core/rules/resolution.gd
## already exposes the underlying domain-layer split (Resolution.resolve_to_hit()
## / Resolution.apply_on_hit_defense() — see that file's FEAT-001 doc); this
## use case is the Application-layer entry point Presentation/Infrastructure
## callers (and a future round_session.gd reaction-window integration) are
## meant to construct and drive, mirroring core/application/
## resolve_action_use_case.gd's own construction pattern (an injected
## RandomNumberPort wrapped in a _PortRNGAdapter and handed to a Resolution
## instance) rather than reaching into core/rules/resolution.gd directly.
##
## PHASE 1 responsibility ONLY: rolls the pre-hit Dodge/Steel check (if
## `pre_hit_defense` requests one and its trigger conditions hold), the
## attacker's attack roll, and — on a hit — the RAW damage roll. This class
## is STRUCTURALLY INCAPABLE of committing target.hp_current or emitting an
## AttackEvent/CombatantDefeatedEvent: it is never constructed with (and
## never references) an EventSinkPort at all, and it never writes to any
## Dictionary it is handed — see tests/application/test_resolve_to_hit_uc.gd
## for the pinned proof (test_criteria #1). Committing HP and emitting events
## is PHASE 2's exclusive job — see core/application/apply_on_hit_defense_uc.gd.
##
## RNG-sequence sharing (ADR-002): get_resolution() exposes the SAME
## Resolution instance this use case rolled the to-hit phase against, so a
## caller can hand it straight to ApplyOnHitDefenseUseCase's constructor —
## the on-hit mitigation phase (Block/Parry) MUST continue drawing from the
## IDENTICAL RNG sequence the to-hit phase already started, even across an
## awaited reaction window between the two phases. Never construct a second,
## independent Resolution instance for the apply phase of the SAME Strike.
##
## Wiring this use case into core/application/round_session.gd's live
## reaction-window coroutine (so an OnHitMitigation choice genuinely reduces
## an already-rolled Strike's damage before it commits) is explicitly OUT of
## this feature's file scope — round_session.gd's own FEAT-005 doc already
## flags this as "left to a follow-on feature"; this feature only establishes
## the two-phase use-case seam itself (mirrors this codebase's established
## "establishing this seam is this feature's entire scope" convention, e.g.
## round_session.gd's _reaction_resolver_fn original doc).
##
## Usage example:
##   var to_hit_uc := ResolveToHitUseCase.new(random_number_port)
##   var partial: Dictionary = to_hit_uc.resolve_to_hit(attacker, target, weapon, "ac")
##   # ... await an on-hit reaction window here, deciding on_hit_defense ...
##   var apply_uc := ApplyOnHitDefenseUseCase.new(to_hit_uc.get_resolution(), event_sink_port)
##   var result: Dictionary = apply_uc.apply(partial, attacker, target, on_hit_defense, ctx, round_number)

class_name ResolveToHitUseCase
extends RefCounted

const ResolutionClass = preload("res://core/rules/resolution.gd")


## _PortRNGAdapter — internal adapter wrapping an injected RandomNumberPort
## (the dice_spec-shaped `roll(dice_spec)` contract — core/rules/random_port.gd)
## so it can be handed to core/rules/resolution.gd's Resolution constructor,
## which duck-types its injected `_rng` against the RNG-shaped `d20()` /
## `roll(die_size, count)` contract (core/rules/rng.gd). Mirrors
## core/application/resolve_action_use_case.gd's own identically-named,
## identically-shaped inner class verbatim — kept as an independent copy
## here (rather than imported) because GDScript inner classes are not
## importable across files without a full script preload/instantiate
## indirection, and this adapter carries zero state/behavior worth
## centralizing beyond this one-line forward.
class _PortRNGAdapter:
	var _port

	func _init(port) -> void:
		_port = port

	## d20() -> int — forwards to the injected port's own d20().
	func d20() -> int:
		return _port.d20()

	## roll(die_size, count) -> int — forwards to the injected port's
	## dice_spec-shaped roll().
	func roll(die_size: int, count: int) -> int:
		return _port.roll({"die": die_size, "count": count})


var _resolution  ## Resolution (core/rules/resolution.gd) — constructed once
## here from the injected RandomNumberPort (FEAT-002); ALL to-hit math
## delegates to this single instance, never re-implemented here.


## _init(random_number_port) — stores the injected RandomNumberPort (NFR-003
## determinism — never an ambient/global RNG) and constructs the Resolution
## instance this use case's resolve_to_hit() delegates to.
func _init(random_number_port) -> void:
	_resolution = ResolutionClass.new(_PortRNGAdapter.new(random_number_port))


## get_resolution() -> Resolution — the SAME Resolution instance this use
## case rolled the to-hit phase against. Hand this to
## ApplyOnHitDefenseUseCase's constructor so the on-hit mitigation phase
## continues drawing from the IDENTICAL RNG sequence (see file-level doc
## above) — never construct a fresh Resolution for the apply phase of the
## SAME Strike.
func get_resolution():
	return _resolution


## resolve_to_hit(attacker, target, weapon, defense_type, pre_hit_defense,
##                ctx) -> Dictionary
##
## Delegates verbatim to Resolution.resolve_to_hit() — see
## core/rules/resolution.gd for the full parameter/return contract
## (roll_total, damage_raw, hit, crit, defender_stepped,
## active_defense_applied, next_check_bonus, defense_value, defense_type,
## weapon). Performs ZERO hp_current mutation and emits ZERO events — this
## use case has no EventSinkPort collaborator at all, so it is structurally
## incapable of emitting one (test_criteria #1).
func resolve_to_hit(
	attacker: Dictionary,
	target: Dictionary,
	weapon: Dictionary,
	defense_type: String = "ac",
	pre_hit_defense: String = "none",
	ctx: Dictionary = {}
) -> Dictionary:
	return _resolution.resolve_to_hit(attacker, target, weapon, defense_type, pre_hit_defense, ctx)
