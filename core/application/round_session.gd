## core/application/round_session.gd — RoundSession (FEAT-110 / US-010, ADR-007)
##
## Application layer (Clean Architecture): the resumable, stepwise cycle
## state for ONE round, returned by RunRoundUseCase.begin_round(). This is
## the declared ADR-007 amendment to RunRoundUseCase's surface: the AC-4
## interleaved-cycle state that used to live entirely as local variables
## inside execute()'s while-loop is now a first-class RefCounted object a
## human can drive one turn at a time (US-010/US-011), instead of the whole
## round resolving autonomously in a single call.
##
## Depends ONLY on the same collaborators RunRoundUseCase already depends on
## (ResolveActionUseCase, DetermineOutcomeUseCase, AIDecisionPort,
## EventSinkPort, RoundHistoryPort) plus the plain combatant/ActionEconomy
## Dictionaries pulled from TurnOrderPort — never on a concrete
## adapter/infrastructure class. No new port is introduced (ADR-002/ADR-007).
##
## Two independent ways this session's cycle can be driven, both funnelling
## every actual rule decision through the SAME resolve_action_use_case /
## determine_outcome_use_case instances (never a parallel rules path):
##
##   1. Interactive, one-turn-at-a-time (US-010/US-011 — the Presentation
##      turn-driver, presentation/turn_controller.gd, calls these):
##        current_actor() / current_action_economy() — who acts now.
##        advance_ai_turn()  — resolves the current Enemy actor's turn via
##          AIDecisionPort + resolve_action_use_case, then advances the
##          cursor. Defensive fallback: an AI decision that fails to resolve
##          still advances the cursor so the loop can never stall (US-011).
##        end_current_turn() — ends the current PLAYER actor's turn. ALWAYS
##          available regardless of whether/what action was spent (US-010);
##          the actor's own Strike (if any) was already resolved directly by
##          StrikeActionControl via resolve_action_use_case.resolve() (US-009,
##          unchanged) — this method owns only the post-action outcome check
##          + cursor advance, never the resolve() call itself.
##      Each cursor advance emits a RoundEvents.TurnAdvancedEvent via
##      EventSinkPort (ADR-003's one integration surface with Presentation).
##
##   2. Autonomous, whole-round-at-once (used ONLY by
##      RunRoundUseCase.execute(), the pre-existing headless N=1000 balance
##      sim entry point): run_autonomous_to_completion() replays the
##      byte-for-byte-identical AC-4 nested-cycle algorithm (incl. the
##      FEAT-097/CWE-835 no-progress backstop) that used to live inline in
##      execute() — auto-selecting a target for BOTH sides (AI for Enemy,
##      "first living target" for Player, matching execute()'s pre-FEAT-110
##      behavior exactly) rather than waiting on human input.
##
## finish() (used by both callers) mirrors execute()'s pre-FEAT-110 tail:
## end_of_round() on every combatant, then the round-scoped history slice.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
class_name RoundSession
extends RefCounted

const RoundEventsClass = preload("res://core/rules/round_events.gd")
const ActionsClass = preload("res://core/rules/actions.gd")
## ReactionWindowClass — FEAT-003 (US-003 / FR-002): preloaded ONLY for its
## static, side-effect-free helpers (is_on_hit_mitigation_eligible(),
## assert_reaction_budget_delta()) — RoundSession never instantiates a
## ReactionWindow itself (a resolver Callable, injected via
## set_reaction_resolver_fn()/set_prehit_avoidance_resolver_fn(), remains the
## sole seam to a real one — see those setters' own docs). Both files already
## live in the SAME application layer (ADR-002), so this is not a layering
## violation.
const ReactionWindowClass = preload("res://core/application/reaction_window.gd")

## AttackEventClass — FEAT-007 (US-007 / FR-008): preloaded ONLY to construct
## the STRUCTURED, storage-shaped AttackEvent record_attack() (event_log_view.gd,
## a same-layer-adjacent Presentation adapter) accepts — a different value
## object from RoundEventsClass.AttackEvent above (that one carries names for
## immediate rendering; this one carries ids for structured storage/pairing —
## see core/log/attack_event.gd's file-level doc). RoundSession never
## instantiates event_log_view.gd itself (ADR-001/ADR-002) — only this value
## object, handed to whatever Callable a composition root injects via
## set_event_log_record_attack_fn() below.
const AttackEventClass = preload("res://core/log/attack_event.gd")

## RenderCombatLogUseCaseClass — FEAT-008 (US-008 / FR-007): preloaded ONLY
## to derive/record the active-defense outcome ("Defense: <outcome>") for a
## just-resolved Strike's paired reaction — see that use case's own
## file-level doc. Both files live in the SAME application layer (ADR-002),
## so this is not a layering violation; RoundSession never imports/
## references presentation/event_log_view.gd itself (ADR-001/ADR-002) — only
## this use case, which in turn only invokes whichever Callable a
## composition root injects via set_event_log_record_reaction_fn() below.
const RenderCombatLogUseCaseClass = preload("res://core/application/render_combat_log_use_case.gd")

## ResolveDodgeStepUseCaseClass — FEAT-002 (US-002, Dodge-Step steel thread):
## preloaded ONLY to construct the use case that decides whether/how to
## prompt for a Dodge-Step destination hex once a Strike's to-hit phase has
## reported defender_stepped=true (see _resolve_dodge_step_prompt() below).
## Both files live in the SAME application layer (ADR-002), so this is not a
## layering violation — RoundSession never imports anything from
## presentation/ or infrastructure/ to do this (the use case itself depends
## only on plain data + a duck-typed Callable seam, mirroring every other
## use case this file already preloads).
const ResolveDodgeStepUseCaseClass = preload("res://core/application/resolve_dodge_step_use_case.gd")

var _entries: Array
var _party: Array
var _enemies: Array
var _round_number: int

var _resolve_action_use_case      ## ResolveActionUseCase — injected
var _determine_outcome_use_case   ## DetermineOutcomeUseCase — injected
var _ai_decision_port             ## AIDecisionPort — injected (duck-typed)
var _event_sink_port              ## EventSinkPort — injected
var _round_history_port           ## RoundHistoryPort — injected

## _cursor — index into _entries of the current actor; -1 once the round is
## over (no living, un-Spent actor remains, or the outcome was decided).
var _cursor: int = -1

## _token_reposition_fn — OPTIONAL (FEAT-008 / US-008 / FR-012, ADR-006): an
## injected, duck-typed Callable(combatant_id: String, new_hex_coord)
## advance_ai_turn() invokes immediately after an AI-issued Stride, so the
## enemy's on-screen token repositions through the EXACT SAME function
## presentation/movement_input_controller.gd's _resync_token_renderers()
## already calls for a player-driven Step/Stride — presentation/
## hex_grid_view.gd HexGridView.move_token() — never a second, parallel
## reposition implementation. RoundSession never imports/depends on
## HexGridView or any other Presentation type (ADR-001/ADR-002): it only
## calls whichever Callable the composition root (MainScene.gd) injects via
## set_token_reposition_fn(). Left as an invalid (unbound) Callable — the
## default — for every pre-existing caller/test double, including the
## autonomous run_autonomous_to_completion() path, which never sets one; a
## rendering-only concern is entirely optional and never required for the
## domain/application cycle logic to function correctly.
var _token_reposition_fn: Callable = Callable()

## _cycle_index — the AC-4 interleave cycle pass the CURRENT actor's action
## belongs to (0-based), stamped on resolve_action_use_case calls made via
## advance_ai_turn(). Incremented whenever the cursor wraps back around
## _entries (one full pass completed).
var _cycle_index: int = 0

## _turn_start_budget — FEAT-005 (US-003 / FR-003, ADR-011): the CURRENT
## actor's ActionEconomy.get_remaining() value snapshotted the moment the
## cursor landed on it (in _init() for the round's first actor, in
## _advance_cursor() for every actor after). _advance_cursor() compares this
## snapshot against the SAME ActionEconomy's remaining budget when that
## actor's turn ends (regardless of WHERE the spend happened — an AI-resolved
## Strike/Stride/WAIT via advance_ai_turn(), or a player Strike resolved
## directly by StrikeActionControl via resolve_action_use_case BEFORE
## end_current_turn() is called) to determine whether that turn made any
## progress at all, without RoundSession needing to intercept every possible
## call site that can spend an action.
var _turn_start_budget: int = 0

## _interactive_cycle_progress — FEAT-005: true once ANY actor's turn within
## the CURRENT interactive cycle pass has spent at least one action (budget
## decreased). Reset to false every time _advance_cursor() completes a full
## pass (mirrors run_autonomous_to_completion()'s local
## any_action_resolved_this_cycle, ported onto the interactive cursor path).
## Never consulted/mutated by the autonomous API — see
## run_autonomous_to_completion()'s own, separate local backstop tracking.
var _interactive_cycle_progress: bool = false

## _outcome — '' | 'won' | 'lost'; NEVER 'DRAW' (mirrors outcome()'s
## documented contract — a per-round DRAW is reported only via finish()'s
## Dictionary "outcome" key, see _forced_draw below).
var _outcome: String = ""

## _round_over — true once every living combatant is Spent, the outcome was
## decided, or the stalled-cycle backstop fired (autonomous path, AND —
## FEAT-005 / US-003 / FR-003, ADR-011 — the interactive cursor path).
var _round_over: bool = false

## _forced_draw — true once EITHER backstop fires: the autonomous
## run_autonomous_to_completion()'s CWE-835/FIND-095 backstop, OR (FEAT-005 /
## US-003 / FR-003, ADR-011) the interactive cursor path's own equivalent
## no-progress backstop in _advance_cursor() below — both mean "a full cycle
## pass resolved zero actions". Drives finish()'s per-round "outcome": "DRAW"
## vs "encounter_outcome": "" distinction, exactly matching
## RunRoundUseCase.execute()'s pre-FEAT-110 contract (and now also the
## interactive path's, per this steel thread's exit criterion: the 1000-turn
## guard in presentation/turn_controller.gd must never be what actually
## terminates a round — this backstop is the true last line of defense).
var _forced_draw: bool = false


## _init(entries, party, enemies, round_number, resolve_action_use_case,
##       determine_outcome_use_case, ai_decision_port, event_sink_port,
##       round_history_port) — stores the injected collaborators (all
## duck-typed, matching RunRoundUseCase's own constructor convention so test
## doubles may be substituted) and positions the cursor at the first living,
## un-Spent combatant in `entries` (or marks the round over immediately if
## none exists). Callers MUST have already granted each entry's
## ActionEconomy its start-of-round budget (RunRoundUseCase.begin_round()
## does this) — the constructor itself grants no budget.
##
## ADR-101/ADR-102/FEAT-004: this initial cursor assignment is one of the TWO
## call sites (the other being _advance_cursor() below) that together form
## the SINGLE authoritative seam for ActionEconomy.start_of_turn() — for
## BOTH player and AI actors alike. start_of_turn() is invoked exactly once
## here, immediately after the cursor is positioned on the first living,
## un-Spent combatant, so that combatant's per-turn flags
## (movement_used_this_turn/action_used_this_turn) are guaranteed clear
## before anything (Presentation's verb bar, an AI decision) ever inspects
## them. Closes the P0-1 movement-lockout defect for the very first actor of
## a round, which the pre-FEAT-004 code never cleared for a Player actor at
## all. start_of_turn() itself is documented as idempotent and
## budget/is_spent-neutral (ADR-102), so this call is always safe even
## though RunRoundUseCase.begin_round() already called start_of_round() on
## every entry moments earlier.
func _init(
	entries: Array,
	party: Array,
	enemies: Array,
	round_number: int,
	resolve_action_use_case,
	determine_outcome_use_case,
	ai_decision_port,
	event_sink_port,
	round_history_port
) -> void:
	_entries                    = entries
	_party                      = party
	_enemies                    = enemies
	_round_number                = round_number
	_resolve_action_use_case    = resolve_action_use_case
	_determine_outcome_use_case = determine_outcome_use_case
	_ai_decision_port           = ai_decision_port
	_event_sink_port            = event_sink_port
	_round_history_port         = round_history_port

	_cursor = _find_first_actionable_index()
	if _cursor == -1:
		_round_over = true
	else:
		_entries[_cursor]["action_economy"].start_of_turn()
		# FEAT-005 (US-003 / FR-003, ADR-011): snapshot the first actor's
		# starting budget so _advance_cursor() can detect whether its turn
		# made any progress — see _turn_start_budget's doc above.
		_turn_start_budget = _entries[_cursor]["action_economy"].get_remaining()


## set_token_reposition_fn(fn) -> void — FEAT-008 (US-008 / FR-012, ADR-006):
## injects the Callable advance_ai_turn() invokes to visually reposition an
## AI-Stride actor's on-screen token. `fn` is expected to accept
## (combatant_id: String, new_hex_coord) — the exact signature of
## presentation/hex_grid_view.gd HexGridView.move_token(), the SAME function
## the player Step/Stride path (presentation/movement_input_controller.gd)
## already calls. Intended to be called once by the composition root
## (MainScene.gd) right after obtaining this RoundSession from
## RunRoundUseCase.begin_round(), e.g.:
##   round_session.set_token_reposition_fn(Callable(hex_grid_view, "move_token"))
## Never calling this method (every pre-existing caller/test double) leaves
## advance_ai_turn()'s behavior completely unchanged — see
## _reposition_token_after_ai_stride()'s no-op guard below.
func set_token_reposition_fn(fn: Callable) -> void:
	_token_reposition_fn = fn


## _reaction_resolver_fn — OPTIONAL (FEAT-002 / US-002 / FR-002, ADR-002):
## an injected, duck-typed Callable satisfying the ReactionResolverPort
## contract — `async func(trigger: Dictionary) -> Dictionary`, returning at
## least {choice: String} — that a future enemy-strikes-player reaction
## window will `await` before a Strike resolves. This is a typed-Callable
## seam (ADR-002's Dependency Inversion mechanism in lieu of GDScript
## interfaces/generics), mirroring `_token_reposition_fn` above exactly:
## RoundSession depends on this Callable ONLY as a signature and NEVER
## imports/references presentation/turn_controller.gd or any other
## concrete Presentation/Infrastructure class by type (ADR-001/ADR-002).
## Establishing this seam is this feature's ENTIRE scope — no call site in
## advance_ai_turn() (or anywhere else) invokes it yet; wiring a real
## trigger/defense_context through it on the enemy-strikes-player path is a
## separate, later feature. Left as an invalid (unbound) Callable — the
## default — for every pre-existing caller/test double, including every
## headless/sim caller, which never sets one; see _resolve_reaction()'s
## default-safety fallback below.
var _reaction_resolver_fn: Callable = Callable()


## set_reaction_resolver_fn(fn) -> void — FEAT-002 (US-002 / FR-002,
## ADR-002): injects the ReactionResolverPort Callable described above.
## Intended to be called once by the composition root (MainScene.gd), the
## SAME way set_token_reposition_fn() already is, e.g.:
##   round_session.set_reaction_resolver_fn(Callable(turn_controller, "resolve_reaction"))
## Never calling this method (every pre-existing caller/test double,
## including every headless/sim caller) leaves RoundSession's behavior for
## those callers byte-for-byte unchanged — see _resolve_reaction()'s
## synchronous fallback below.
func set_reaction_resolver_fn(fn: Callable) -> void:
	_reaction_resolver_fn = fn


## _resolve_reaction(trigger) -> Dictionary — FEAT-002 (US-002 / FR-002,
## ADR-002): the internal seam a future reaction-window call site will
## `await` on an enemy-strikes-player Strike. When a resolver has been
## injected via set_reaction_resolver_fn(), awaits and returns its result
## verbatim — the ReactionResolverPort contract: `async func(trigger:
## Dictionary) -> Dictionary`. When NO resolver has been injected — every
## headless/sim caller, and every pre-existing test — this is a
## SYNCHRONOUS, zero-await fallback to {"choice": "none"} (equivalent to a
## PASS), preserving byte-for-byte pre-change behavior for those callers
## (NFR-004). Not yet called from advance_ai_turn() or anywhere else in
## this feature's scope — it exists solely to establish and characterize
## the port's default-safety contract ahead of the (separate) feature that
## threads a real trigger/defense_context through it.
func _resolve_reaction(trigger: Dictionary) -> Dictionary:
	if _reaction_resolver_fn.is_valid():
		return await _reaction_resolver_fn.call(trigger)
	return {"choice": "none"}


## _prehit_avoidance_resolver_fn — OPTIONAL (FEAT-002 / US-002 / FR-001,
## Iteration J Part B): an injected, duck-typed Callable satisfying the SAME
## ReactionResolverPort shape `_reaction_resolver_fn` above does — `async
## func(trigger: Dictionary) -> Dictionary`, returning at least {choice:
## String} — but `await`ed for a DIFFERENT, EARLIER reaction window:
## "PreHitAvoidance" (Dodge/Steel only), opened BEFORE the existing
## "WeaponAttack" window this session already awaits via `_resolve_reaction`
## above. This mirrors `_reaction_resolver_fn`'s own seam-establishment
## pattern exactly (a typed-Callable Dependency Inversion seam, ADR-002) and
## is deliberately a SEPARATE Callable rather than overloading the existing
## one, so a caller can inject a PreHitAvoidance resolver (e.g. one backed by
## core/application/reaction_window.gd's
## open_and_resolve_prehit_avoidance()) without disturbing the existing
## WeaponAttack resolver's contract or any of its pinned tests. Left as an
## invalid (unbound) Callable — the default — for every pre-existing
## caller/test double, including every headless/sim caller, which never sets
## one; see _resolve_prehit_avoidance()'s default-safety fallback below.
var _prehit_avoidance_resolver_fn: Callable = Callable()


## set_prehit_avoidance_resolver_fn(fn) -> void — FEAT-002: injects the
## PreHitAvoidance ReactionResolverPort Callable described above. Intended to
## be called once by the composition root, the SAME way
## set_reaction_resolver_fn() already is. Never calling this method (every
## pre-existing caller/test double) leaves RoundSession's behavior for those
## callers byte-for-byte unchanged — see _resolve_prehit_avoidance()'s
## synchronous fallback below.
func set_prehit_avoidance_resolver_fn(fn: Callable) -> void:
	_prehit_avoidance_resolver_fn = fn


## _resolve_prehit_avoidance(trigger) -> Dictionary — FEAT-002: the internal
## seam advance_ai_turn()'s Strike branch `await`s BEFORE the existing
## WeaponAttack window / before any call in the chain ever reaches
## core/rules/resolution.gd's resolve_to_hit() (test_criteria #5). When a
## resolver has been injected via set_prehit_avoidance_resolver_fn(), awaits
## and returns its result verbatim. When NO resolver has been injected —
## every headless/sim caller, and every pre-existing test — this is a
## SYNCHRONOUS, zero-await fallback to {"choice": "none"} (equivalent to a
## PASS), preserving byte-for-byte pre-change behavior for those callers
## (NFR-004), exactly mirroring _resolve_reaction()'s own contract.
func _resolve_prehit_avoidance(trigger: Dictionary) -> Dictionary:
	if _prehit_avoidance_resolver_fn.is_valid():
		return await _prehit_avoidance_resolver_fn.call(trigger)
	return {"choice": "none"}


## _onhit_mitigation_resolver_fn — OPTIONAL (FEAT-004 / US-004 / FR-003): an
## injected, duck-typed Callable satisfying the SAME ReactionResolverPort
## shape `_prehit_avoidance_resolver_fn` above does -- `async func(trigger:
## Dictionary) -> Dictionary`, returning at least {choice: String} -- but
## `await`ed for the NEW, POST-HIT sibling window: "OnHitMitigation"
## (Parry/Block only), opened AFTER a Strike's hit/miss result is already
## known (core/application/reaction_window.gd's
## open_and_resolve_onhit_mitigation(), built on this feature's two-phase
## resolve_to_hit()/apply_on_hit_defense() split). This mirrors
## `_prehit_avoidance_resolver_fn`'s own seam-establishment pattern exactly
## (a typed-Callable Dependency Inversion seam, ADR-002) and is deliberately
## a SEPARATE Callable rather than overloading either existing one, so a
## caller can inject an OnHitMitigation resolver without disturbing the
## existing PreHitAvoidance/WeaponAttack resolvers' contracts or any of
## their pinned tests. Left as an invalid (unbound) Callable -- the default
## -- for every pre-existing caller/test double, including every
## headless/sim caller, which never sets one; see
## _resolve_onhit_mitigation()'s default-safety fallback below.
##
## Establishing this seam (plus reaction_window.gd's new "OnHitMitigation"
## trigger_type/open_and_resolve_onhit_mitigation()) is this feature's
## ENTIRE scope for RoundSession -- no call site in advance_ai_turn() (or
## anywhere else) invokes it yet; replacing the existing pre-hit "WeaponAttack"
## on-hit offer with a genuinely POST-HIT OnHitMitigation window inside
## advance_ai_turn() is a separate, later feature (mirrors
## `_reaction_resolver_fn`'s own original establishment-only doc above).
var _onhit_mitigation_resolver_fn: Callable = Callable()


## set_onhit_mitigation_resolver_fn(fn) -> void — FEAT-004: injects the
## OnHitMitigation ReactionResolverPort Callable described above. Intended to
## be called once by the composition root, the SAME way
## set_prehit_avoidance_resolver_fn() already is. Never calling this method
## (every pre-existing caller/test double) leaves RoundSession's behavior for
## those callers byte-for-byte unchanged -- see
## _resolve_onhit_mitigation()'s synchronous fallback below.
func set_onhit_mitigation_resolver_fn(fn: Callable) -> void:
	_onhit_mitigation_resolver_fn = fn


## _resolve_onhit_mitigation(trigger) -> Dictionary — FEAT-004: the internal
## seam a future feature's advance_ai_turn() Strike branch will `await` AFTER
## resolve_to_hit()'s hit/miss result is known (never before -- Parry/Block
## are ON-HIT reactions, see reaction_window.gd's OnHitMitigation doc). When a
## resolver has been injected via set_onhit_mitigation_resolver_fn(), awaits
## and returns its result verbatim. When NO resolver has been injected --
## every headless/sim caller, and every pre-existing test -- this is a
## SYNCHRONOUS, zero-await fallback to {"choice": "none"} (equivalent to a
## PASS), preserving byte-for-byte pre-change behavior for those callers
## (NFR-004), exactly mirroring _resolve_reaction()'s/
## _resolve_prehit_avoidance()'s own contract.
func _resolve_onhit_mitigation(trigger: Dictionary) -> Dictionary:
	if _onhit_mitigation_resolver_fn.is_valid():
		return await _onhit_mitigation_resolver_fn.call(trigger)
	return {"choice": "none"}


## _hex_choice_resolver_fn — OPTIONAL (FEAT-001 / US-001, Dodge-Step steel
## thread; ADR-001/ADR-002/ADR-006 "no duplicate seam"): an injected,
## duck-typed Callable satisfying THIS SAME reused FEAT-001 hex-choice seam's
## contract -- `func(legal_hexes: Array) -> HexCoord | null`
## (core/application/ports/hex_choice_resolver_port.gd's `resolve`/
## `choose_step_hex` contract, already proven end-to-end against the REAL
## MainScene.gd composition root by
## tests/application/test_hex_choice_resolver_seam.gd and
## tests/gut/test_hex_choice_seam_dodge_step.gd) -- mirrors every other
## Dependency-Inversion Callable seam already established in this file
## (_token_reposition_fn / _reaction_resolver_fn / _prehit_avoidance_resolver_fn
## / _onhit_mitigation_resolver_fn) exactly: RoundSession depends on this
## Callable ONLY as a signature, never importing/referencing
## core/application/ports/hex_choice_resolver_port.gd's concrete adapters or
## MainScene.gd by type (ADR-001/ADR-002). Establishing this seam on
## RoundSession is this feature's (FEAT-001 / US-001) ENTIRE scope for this
## file -- no call site in advance_ai_turn() (or anywhere else) invokes it
## yet; threading a genuine Dodge-Step await through a future
## ResolveDodgeStepUseCase is separate, later work (mirrors this file's own
## established "establishing this seam is this feature's entire scope"
## convention, e.g. `_onhit_mitigation_resolver_fn`'s original doc). Left as
## an invalid (unbound) Callable -- the default -- for every existing
## caller/test double, which never sets one; see
## _resolve_step_hex_choice()'s no-op-safe fallback below.
var _hex_choice_resolver_fn: Callable = Callable()


## set_hex_choice_resolver_fn(fn) -> void -- FEAT-001: injects the
## hex-choice-resolver Callable described above. Intended to be called once
## by the composition root (MainScene.gd), the SAME way
## set_token_reposition_fn() already is, e.g.:
##   round_session.set_hex_choice_resolver_fn(Callable(main_scene, "resolve_hex_choice"))
## Never calling this method (every pre-existing caller/test double) leaves
## RoundSession's behavior byte-for-byte unchanged (NFR-004) -- see
## _resolve_step_hex_choice()'s fallback below.
func set_hex_choice_resolver_fn(fn: Callable) -> void:
	_hex_choice_resolver_fn = fn


## _resolve_step_hex_choice(legal_hexes) -> HexCoord | null -- FEAT-001: the
## internal seam a future ResolveDodgeStepUseCase will `await` to ask "which
## legal Step hex was picked?", reusing the EXACT SAME
## HexChoiceResolverPort contract rather than a second, parallel resolution
## path (ADR-001/ADR-002/ADR-006 "no duplicate seam"): an empty
## `legal_hexes` always returns null IMMEDIATELY, with NO await/prompt at
## all -- the G3/G4 "zero-legal-adjacent-hex" guard this steel thread's
## error_handling design note requires (damage is negated, but no
## Step-selection UI is ever invoked). A non-empty `legal_hexes` awaits the
## injected Callable (when one has been set via
## set_hex_choice_resolver_fn()) and returns its result verbatim -- the
## SAME resolve()/choose_step_hex() contract
## tests/application/test_hex_choice_resolver_seam.gd and
## tests/gut/test_hex_choice_seam_dodge_step.gd already pin against the REAL
## MainScene.gd composition root. When no resolver has been injected --
## every headless/sim caller, and every pre-existing test -- this degrades
## safely to null even for a non-empty legal_hexes (never a fabricated/
## guessed hex, mirroring HexChoiceResolverPort's own "never guess"
## contract), since no call site invokes this helper yet in this feature's
## scope; a future feature's guard-clause caller remains responsible for
## never awaiting this without first checking legal_hexes itself.
func _resolve_step_hex_choice(legal_hexes: Array):
	if legal_hexes.is_empty():
		return null
	if _hex_choice_resolver_fn.is_valid():
		return await _hex_choice_resolver_fn.call(legal_hexes)
	return null


## _step_hex_query_fn — OPTIONAL (FEAT-002 / US-002, Dodge-Step steel
## thread): an injected, duck-typed Callable satisfying the design's
## IStepHexQueryPort contract -- `func(combatant_id: String) -> Array` --
## reused, unmodified, from presentation/movement_input_controller.gd's
## get_selectable_step_hexes_for() (never a new adjacency rule, ADR-002 "no
## duplicate seam"). Mirrors `_hex_choice_resolver_fn`'s own seam-
## establishment pattern exactly: RoundSession depends on this Callable
## ONLY as a signature, never importing/referencing
## presentation/movement_input_controller.gd or MainScene.gd by type
## (ADR-001/ADR-002). Left as an invalid (unbound) Callable -- the default
## -- for every pre-existing caller/test double, which never sets one; see
## _resolve_dodge_step_prompt()'s no-op-safe fallback below.
var _step_hex_query_fn: Callable = Callable()


## set_step_hex_query_fn(fn) -> void -- FEAT-002: injects the
## IStepHexQueryPort Callable described above. Intended to be called once by
## the composition root (MainScene.gd), the SAME way
## set_hex_choice_resolver_fn() already is, e.g.:
##   round_session.set_step_hex_query_fn(Callable(main_scene, "_query_selectable_step_hexes"))
## Never calling this method (every pre-existing caller/test double) leaves
## RoundSession's behavior byte-for-byte unchanged (NFR-004) -- see
## _resolve_dodge_step_prompt()'s fallback below.
func set_step_hex_query_fn(fn: Callable) -> void:
	_step_hex_query_fn = fn


## _resolve_dodge_step_prompt(target, partial) -> void -- FEAT-002 (US-002,
## Dodge-Step steel thread): the seam that a to-hit-phase caller
## (core/application/resolve_to_hit_uc.gd's ResolveToHitUseCase.resolve_to_hit()
## / core/rules/resolution.gd's Resolution.resolve_to_hit()) reporting
## `partial["defender_stepped"] == true` for a JUST-resolved Strike against
## `target` -- i.e. exactly the moment "the defender rolls a successful
## Dodge" per this steel thread's requirement -- `await`s to trigger the
## Step-selection prompt. Fully wired at the REAL MainScene.gd composition
## root (rewire_session() calls both set_hex_choice_resolver_fn() and
## set_step_hex_query_fn() below with production adapters -- never a test
## double), and exercised directly by tests/gut/test_dodge_step_prompt.gd
## against a real booted MainScene (G2). Threading a call to this method
## through advance_ai_turn()'s live Strike-resolution coroutine is
## deliberately left to a later feature (mirrors this file's own established
## "establishing this seam is this feature's entire scope" convention, e.g.
## `_hex_choice_resolver_fn`'s own FEAT-001 doc above) -- the REAL
## `_UIHexChoiceResolver` this seam is wired to genuinely blocks on a live
## hex click, so wiring an unconditional live call site here would hang any
## caller that scripts a successful Dodge without also scripting a click
## (including pre-existing suites, e.g. tests/test_mainscene_combat_log_richness.gd).
## Delegates the ENTIRE whether/how-to-prompt decision to
## ResolveDodgeStepUseCase (ADR-001/ADR-002: no duplicate resolution logic
## here) -- this method's only job is assembling that use case's inputs from
## RoundSession's own seams:
##   - `defender_id`      -- target's "combatant_id" falling back to "name"
##                            (this file's established identity convention).
##   - `legal_hexes`       -- `_step_hex_query_fn.call(defender_id)` when a
##                            query Callable has been injected, else an empty
##                            Array (the G3/G4 "no query wired -> no prompt"
##                            default-safety fallback -- never a fabricated
##                            adjacency computation of RoundSession's own).
##   - `hex_choice_resolver_fn` -- `_hex_choice_resolver_fn` verbatim, the
##                            EXACT SAME FEAT-001 seam _resolve_step_hex_choice()
##                            already consumes (no second, parallel hex-choice
##                            resolution path).
## A no-op (no query call, no prompt, no await) whenever
## `partial["defender_stepped"]` is false -- the overwhelmingly common case
## for every pre-existing caller/test (NFR-004). Even when defender_stepped
## is true, this remains a complete no-op for every pre-existing caller/test
## double, since neither `_step_hex_query_fn` nor `_hex_choice_resolver_fn`
## is ever injected by them (both default to an invalid Callable) --
## ResolveDodgeStepUseCase.resolve()'s own guard clauses degrade that to
## `legal_hexes == []` / an invalid resolver, either of which short-circuits
## before any await (see that use case's own doc).
##
## FEAT-004 (US-004, Dodge-Step steel thread -- "Relocate defender to
## player-chosen hex via shared token-reposition seam"): this method now ALSO
## threads `_token_reposition_fn` (the EXACT SAME ITokenRepositionPort seam
## `_reposition_token_after_ai_stride()` already awaits for an AI-issued
## Stride, ADR-002 "no duplicate seam") and `target` itself through to
## ResolveDodgeStepUseCase.resolve()'s new trailing parameters -- see that use
## case's own FEAT-004 doc for the full "reposition the token, then update
## Combatant.hex_coord" sequence it now performs once a hex has actually been
## chosen. `target` is the SAME live Dictionary reference this session's own
## `_entries` holds (current_actor()'s own documented contract), so mutating
## `target["hex_coord"]` inside the use case is immediately observable by
## every other holder of that reference (GDScript Dictionaries are reference
## types) -- no second, stale copy of the defender's position is ever left
## behind. A complete no-op for every pre-existing caller/test double for the
## SAME reason documented above: neither `_token_reposition_fn` nor a
## non-empty `target` reach ResolveDodgeStepUseCase.resolve() unless a hex was
## actually chosen, which itself requires both `_step_hex_query_fn` and
## `_hex_choice_resolver_fn` to already be injected.
func _resolve_dodge_step_prompt(target: Dictionary, partial: Dictionary) -> void:
	if not partial.get("defender_stepped", false):
		return

	var defender_id: String = target.get("combatant_id", target.get("name", ""))
	var legal_hexes: Array = []
	if _step_hex_query_fn.is_valid():
		legal_hexes = _step_hex_query_fn.call(defender_id)

	var use_case := ResolveDodgeStepUseCaseClass.new()
	await use_case.resolve(
		defender_id, true, legal_hexes, _hex_choice_resolver_fn,
		_token_reposition_fn, target
	)


## _debug_trace_enabled — FEAT-007 (US-002/US-003/US-007, ADR-007): OFF by
## default (NFR-004/NFR-005 default-safety — no observable behavior change,
## not even an extra print() line, for any pre-existing caller/test). When
## enabled via set_debug_trace_enabled(true), advance_ai_turn()'s Strike/
## reaction path emits debug-gated trace lines at three points — trigger-built,
## awaiting-resolver-start, resolver-resolved — directly de-risking the
## await-propagation this steel thread introduced by making a hang/stall
## visible immediately (as a missing "resolver_resolved" trace line) instead
## of as a silent freeze (this feature's observability design note #2).
var _debug_trace_enabled: bool = false

## _debug_trace_log — every trace line _trace() has emitted while
## _debug_trace_enabled was true, in order. Exposed via get_debug_trace_log()
## purely so tests can assert on the trace trail directly (mirrors
## MainScene.gd's pre-existing `_last_highlight_debug_log` convention)
## without needing to capture stdout.
var _debug_trace_log: Array = []


## set_debug_trace_enabled(enabled) -> void — FEAT-007: toggles the
## debug-gated trace logging described above. Never called by any
## pre-existing caller/test double, so every one of them keeps
## _debug_trace_enabled at its false default (NFR-004/NFR-005).
func set_debug_trace_enabled(enabled: bool) -> void:
	_debug_trace_enabled = enabled


## get_debug_trace_log() -> Array — a read-only copy of every trace line
## emitted so far (see `_debug_trace_log` above).
func get_debug_trace_log() -> Array:
	return _debug_trace_log.duplicate()


## _reaction_budget_violations — FEAT-003 (US-003 / FR-002): every
## budget-delta violation ReactionWindowClass.assert_reaction_budget_delta()
## has flagged for a Strike this session resolved via advance_ai_turn()
## (mirrors `_debug_trace_log`'s established observability convention
## immediately above). Recorded here purely so a test can observe that the
## gate actually fired: this project's Godot 4.3 engine cannot capture
## GDScript's assert()/push_error() output from GUT (see
## core/rules/resolution.gd's apply_on_hit_defense() doc for this same
## documented limitation). ALWAYS empty for a Strike that respects the
## <=1-reaction-per-Strike invariant — i.e. always empty for every
## pre-existing caller/test (NFR-004).
var _reaction_budget_violations: Array = []


## get_reaction_budget_violations() -> Array — a read-only copy of every
## budget-delta violation recorded so far (see `_reaction_budget_violations`
## above).
func get_reaction_budget_violations() -> Array:
	return _reaction_budget_violations.duplicate()


## _attack_event_id_counter — FEAT-007 (US-007 / FR-008): monotonically
## incremented once per resolved Strike inside advance_ai_turn() (see
## _generate_attack_event_id() below) — the SOLE source of the
## attack_event_id core/log/attack_event.gd's AttackEvent carries. This is
## the id US-007's storage-level pairing invariant (composite
## attack_event_id + window_id, event_log_view.gd's record_reaction()) is
## built on. Never reset mid-round; a fresh RoundSession (one per round, per
## this file's own doc) starts a fresh sequence, so ids are unique within a
## round's own structured log but NOT guaranteed globally unique across
## rounds — acceptable for this steel thread's in-memory-only storage
## (design notes: "no persistence tier this iteration").
var _attack_event_id_counter: int = 0


## _generate_attack_event_id() -> String — FEAT-007: returns a fresh,
## round-scoped-unique id ("R<round_number>-A<n>").
func _generate_attack_event_id() -> String:
	_attack_event_id_counter += 1
	return "R%d-A%d" % [_round_number, _attack_event_id_counter]


## _event_log_record_attack_fn — FEAT-007 (US-007 / FR-008): an OPTIONAL,
## injected, duck-typed Callable satisfying the design's EventLogPort
## record_attack(attack_event) half — `func(attack_event) -> void` — mirroring
## every other Dependency-Inversion seam already established in this file
## (_token_reposition_fn / _reaction_resolver_fn / _prehit_avoidance_resolver_fn
## / _onhit_mitigation_resolver_fn): a typed-Callable seam, never a concrete
## Presentation/Infrastructure reference (ADR-001/ADR-002) — RoundSession
## never imports/references presentation/event_log_view.gd by type. Left as
## an invalid (unbound) Callable — the default — for every pre-existing
## caller/test double, which never sets one; see
## _record_structured_attack()'s no-op guard below. Wiring a REAL adapter
## (event_log_view.gd's record_attack()) into the composition root
## (MainScene.gd) is explicitly OUT of this feature's file scope — a
## follow-on feature's job (mirrors this file's own established convention
## of "establishing this seam is this feature's entire scope", e.g.
## _reaction_resolver_fn's original FEAT-002 doc).
var _event_log_record_attack_fn: Callable = Callable()


## set_event_log_record_attack_fn(fn) -> void — FEAT-007: injects the
## Callable described above. Intended to be called once by the composition
## root, the SAME way set_token_reposition_fn() already is. Never calling
## this method (every pre-existing caller/test double) leaves RoundSession's
## behavior byte-for-byte unchanged (NFR-004) — see
## _record_structured_attack()'s no-op guard.
func set_event_log_record_attack_fn(fn: Callable) -> void:
	_event_log_record_attack_fn = fn


## _event_log_entry_count_fn — FEAT-006 (US-006 / FR-006, Iteration J-R2 Part
## D): an OPTIONAL, injected, duck-typed Callable satisfying the design's
## ICombatLogPort query half — `func() -> int` — mirroring
## _event_log_record_attack_fn immediately above. Bound by the composition
## root (MainScene.gd's rewire_session()) to event_log_view.get_entry_count(),
## the SAME query MainScene.gd's `_verb_bar_strike_execute()` (FEAT-005,
## the player-strikes-enemy path) already calls directly, so advance_ai_turn()
## can capture the append-order index the plain-format on_attack_event() row
## is ABOUT to land at BEFORE resolving the enemy Strike — the SAME
## "capture-then-overwrite-in-place" convention that keeps a killing blow's
## own, separate defeat row chronologically AFTER the Strike's row (see
## overwrite_entry_as_rich()'s doc, presentation/event_log_view.gd). Left as
## an invalid (unbound) Callable — the default — for every pre-existing
## caller/test double, which never sets one (NFR-004).
var _event_log_entry_count_fn: Callable = Callable()

## set_event_log_entry_count_fn(fn) -> void — FEAT-006: injects the Callable
## described above.
func set_event_log_entry_count_fn(fn: Callable) -> void:
	_event_log_entry_count_fn = fn


## _event_log_render_attack_entry_fn — FEAT-006: an OPTIONAL, injected,
## duck-typed Callable satisfying the design's ICombatLogPort rich-render
## half — `func(attack_event_id) -> String` — mirroring
## _event_log_record_attack_fn. Bound by the composition root to
## event_log_view.render_attack_entry(), the SAME formatter FEAT-005's player
## path already calls directly. Left invalid (no-op guarded, NFR-004) for
## every pre-existing caller/test double.
var _event_log_render_attack_entry_fn: Callable = Callable()

## set_event_log_render_attack_entry_fn(fn) -> void — FEAT-006: injects the
## Callable described above.
func set_event_log_render_attack_entry_fn(fn: Callable) -> void:
	_event_log_render_attack_entry_fn = fn


## _event_log_overwrite_entry_fn — FEAT-006: an OPTIONAL, injected,
## duck-typed Callable satisfying the design's ICombatLogPort
## suppress-and-append-rich half — `func(index, text, attack_event_id) ->
## bool` — mirroring _event_log_record_attack_fn. Bound by the composition
## root to event_log_view.overwrite_entry_as_rich(), the SAME in-place
## overwrite FEAT-005's player path already calls directly, so exactly one
## rich row (never a basic+rich duplicate pair) is visible per resolved
## enemy Strike. Left invalid (no-op guarded, NFR-004) for every pre-existing
## caller/test double.
var _event_log_overwrite_entry_fn: Callable = Callable()

## set_event_log_overwrite_entry_fn(fn) -> void — FEAT-006: injects the
## Callable described above.
func set_event_log_overwrite_entry_fn(fn: Callable) -> void:
	_event_log_overwrite_entry_fn = fn


## _event_log_record_reaction_fn — FEAT-008 (US-008 / FR-007): an OPTIONAL,
## injected, duck-typed Callable satisfying the design's ICombatLogPort
## record_reaction() half — `func(reaction_event, correlated_attack_id) ->
## bool` — mirroring `_event_log_record_attack_fn` above. Bound by the
## composition root (MainScene.gd's rewire_session()) to
## presentation/event_log_view.gd's record_reaction(), so
## RenderCombatLogUseCase (see `_generate_attack_event_id()`'s sibling call
## site below, inside advance_ai_turn()) can pair this Strike's ACTUAL
## dodge/steel/parry/block outcome to its AttackEvent — closing the gap where
## nothing in production code ever called record_reaction(), leaving every
## rich row's Defense segment stuck on its "no reaction recorded" "none"
## default (see render_combat_log_use_case.gd's file-level doc). Left as an
## invalid (unbound) Callable — the default — for every pre-existing
## caller/test double, which never sets one (NFR-004): RenderCombatLogUseCase
## itself still returns the derived ReactionResolvedEvent in that case, it is
## simply never recorded anywhere observable.
var _event_log_record_reaction_fn: Callable = Callable()

## set_event_log_record_reaction_fn(fn) -> void — FEAT-008: injects the
## Callable described above.
func set_event_log_record_reaction_fn(fn: Callable) -> void:
	_event_log_record_reaction_fn = fn


## _trace(message) -> void — FEAT-007: appends "DEBUG: <message>" to
## `_debug_trace_log` AND prints it (mirroring MainScene.gd's existing
## debug-log convention), but ONLY when `_debug_trace_enabled` is true — a
## complete no-op (not even a String concatenation) otherwise, so this never
## becomes an always-on hot-path cost (observability design note #2:
## "behind an existing debug/verbose flag, not left in hot path
## unconditionally").
func _trace(message: String) -> void:
	if not _debug_trace_enabled:
		return
	var line: String = "DEBUG: " + message
	_debug_trace_log.append(line)
	print(line)


## _VALID_ACTIVE_DEFENSES — FEAT-003 (US-002 / FR-002, ADR-003): mirrors
## core/rules/resolution.gd's Resolution.VALID_ACTIVE_DEFENSES verbatim (that
## file remains the single source of truth for the rule; this local copy
## exists only so _reaction_choice_to_active_defense() below can validate a
## resolver's response WITHOUT round_session.gd depending on resolution.gd's
## constant directly, since resolve_action_use_case.gd already re-sanitizes
## any unrecognized value to "none" itself — this is a defense-in-depth
## check purely so a malformed adapter response is logged (push_error) at
## the seam it actually came from, rather than silently swallowed one layer
## further down).
const _VALID_ACTIVE_DEFENSES: Array = ["none", "dodge", "block", "parry", "steel"]


## _reaction_choice_to_active_defense(reaction_result) -> String — FEAT-003:
## validates the Dictionary returned by _resolve_reaction() (either the
## injected resolver's own answer, or the synchronous {"choice": "none"}
## default-safety fallback) against the ReactionResolverPort contract
## (api_contracts #2 error_handling): a missing "choice" key, or a choice
## naming something other than one of resolution.gd's recognized active
## defenses, is a malformed adapter response — logged via push_error() and
## coerced to "none" (fail-safe: this must never raise/hang the round loop
## over a misbehaving resolver). A well-formed response's "choice" is
## returned verbatim, ready to be threaded straight into
## ResolveActionUseCase.resolve()'s `active_defense` parameter.
func _reaction_choice_to_active_defense(reaction_result: Dictionary) -> String:
	if not reaction_result.has("choice"):
		push_error("RoundSession: reaction resolver returned a Dictionary missing 'choice'; falling back to 'none'")
		return "none"

	var choice: String = str(reaction_result.get("choice", "none"))
	if not (choice in _VALID_ACTIVE_DEFENSES):
		push_error("RoundSession: reaction resolver returned unrecognized choice '%s'; falling back to 'none'" % choice)
		return "none"

	return choice


## _build_reaction_trigger(attacker, target, target_action_economy) ->
## Dictionary — FEAT-003 (attacker_id/target_id/defense_type/attack_context/
## round_number), extended by FEAT-004 (US-003 / FR-003, ADR-004): the
## ReactionTrigger value object (this feature's data_model) built on an
## enemy-Strikes-player Strike, immediately before awaiting
## _resolve_reaction() below. FEAT-003 proved the await itself was safe with
## a deliberately minimal shape; this feature adds the fields a real resolver
## (e.g. presentation/turn_controller.gd's resolve_reaction(), driving a real
## core/application/reaction_window.gd ReactionWindow) needs to actually
## offer/resolve a reaction — "attacker"/"target" (the full combatant
## Dictionaries, so a resolver can read weapon/skills/conditions without a
## second lookup) and "reactor_action_economy" (the DEFENDER's own
## ActionEconomy instance — a live reference, not a value snapshot, since
## GDScript Dictionaries/objects are already reference types and this
## project's ActionEconomy is deliberately mutated in place by
## spend_reaction()). The pre-existing "attacker_id"/"target_id"/
## "defense_type"/"attack_context"/"round_number" keys are preserved
## byte-for-byte (pinned by tests/gut/test_async_reaction_propagation.gd's
## trigger-shape audit) — this is a strictly additive enrichment, never a
## breaking rename.
##
## FEAT-008 (steel-thread smoke test) regression fix: "trigger_type"/
## "reactor"/"weapon" are ADDITIONALLY populated here so a real
## core/application/reaction_window.gd ReactionWindow.open() call (the
## concrete resolver presentation/turn_controller.gd's resolve_reaction()
## drives, per this session's own _resolve_reaction() doc) computes a
## genuinely non-empty legal_reactions for this trigger instead of silently
## defaulting to trigger_type "" -> [] (reaction_window.gd's documented
## "unrecognized trigger_type" fallback) for EVERY enemy Strike, which would
## have made every Dodge/Block/Parry choice reachable through this seam
## always resolve as ERR_ILLEGAL_CHOICE -> "pass", no matter what a chooser
## answered — a real integration gap between FEAT-004 (this file) and
## FEAT-207 (the reaction pop-up/ReactionWindow) that the FEAT-008 end-to-end
## steel-thread smoke test caught. "trigger_type" is the composite
## "WeaponAttack" type (reaction_window.gd's own FEAT-008 doc) so the window
## offers the UNION of whichever of Dodge/Parry/Block the DEFENDER
## (`target`) is currently eligible for, rather than being pinned to one
## pre-selected reaction — "reactor" is `target` itself (the combatant
## OFFERED the reaction) and "weapon" is the DEFENDER's own weapon (used by
## reaction_window.gd's is_parry_eligible()/is_block_eligible() predicates),
## mirroring _build_defense_context()'s own "parrying_weapon"/
## "blocking_weapon" derivation below exactly.
##
## FEAT-008 regression fix, continued — "reactor_action_economy" is
## deliberately withheld (left unset/null) on THIS trigger, unlike the
## ReactionTrigger passed to _resolve_reaction()'s doc-described shape one
## might expect. Rationale: _build_defense_context() below is this session's
## OWN, single, canonical spend authority — its "action_economy" key is what
## actually reaches core/rules/resolution.gd's resolve_weapon_attack(),
## whose dodge/block/parry branches call ActionEconomy.spend_reaction()
## exactly once per resolved Strike (pinned by
## tests/gut/test_enemy_strike_reaction_window.gd's "spend_reaction() must
## fire on the DEFENDER" assertions). When the injected resolver is the LIVE
## presentation/turn_controller.gd resolve_reaction() adapter, it drives
## core/application/reaction_window.gd's OWN open()/resume() pair as an
## independent legality/pop-up mechanism — resume() ALSO calls
## spend_reaction() on whatever "reactor_action_economy" its trigger carries.
## Handing resume() the SAME live ActionEconomy _build_defense_context() will
## separately spend against would silently charge the defender a SECOND
## reaction for the ONE choice they made. Leaving it null here means
## reaction_window.open()'s ALREADY_SPENT gate cannot short-circuit an
## already-Spent reactor's pop-up (a documented, accepted minor UX gap for
## this iteration — resolution.gd's own _try_spend_reaction() still
## correctly degrades an exhausted budget to a no-op, so no math/budget
## corruption results), and resume() spends nothing — leaving
## _build_defense_context()'s "action_economy" the single, authoritative
## spend site for this call path, exactly as
## tests/gut/test_enemy_strike_reaction_window.gd already pins.
func _build_reaction_trigger(attacker: Dictionary, target: Dictionary, _target_action_economy = null) -> Dictionary:
	return {
		"attacker_id":            attacker.get("combatant_id", attacker.get("name", "")),
		"target_id":              target.get("combatant_id", target.get("name", "")),
		"defense_type":           "ac",
		"attack_context":         {"attacker_weapon": attacker.get("weapon", {})},
		"round_number":           _round_number,
		"attacker":               attacker,
		"target":                 target,
		"reactor_action_economy": null,
		"trigger_type":           "WeaponAttack",
		"reactor":                target,
		"weapon":                 target.get("weapon", {}),
	}


## _build_prehit_avoidance_trigger(attacker, target) -> Dictionary — FEAT-002
## (US-002 / FR-001, Iteration J Part B): the ReactionTrigger built for the
## NEW "PreHitAvoidance" window, `await`ed by advance_ai_turn() BEFORE the
## existing "WeaponAttack" trigger/window below (test_criteria #5). Shaped
## identically to _build_reaction_trigger()'s "WeaponAttack" trigger (same
## attacker/target/round_number/attack_context/weapon derivation — never a
## second, drifting convention), differing ONLY in "trigger_type":
## "PreHitAvoidance" so core/application/reaction_window.gd's
## _compute_legal_reactions() offers exactly Dodge/Steel (never Parry/Block —
## see that branch's own doc) for this earlier, ON-ATTACKED-only ask.
## "reactor_action_economy" is withheld (null) for the SAME reason
## _build_reaction_trigger() withholds it — this session's OWN
## _build_defense_context() remains the single, canonical spend authority
## once the resolved choice reaches resolve_action_use_case.resolve()/
## resolution.gd, so a resolver driving reaction_window.gd's own open()/
## resume() pair (rather than its open_and_resolve_prehit_avoidance()
## convenience method) never double-spends the same reaction.
func _build_prehit_avoidance_trigger(attacker: Dictionary, target: Dictionary) -> Dictionary:
	return {
		"attacker_id":            attacker.get("combatant_id", attacker.get("name", "")),
		"target_id":              target.get("combatant_id", target.get("name", "")),
		"defense_type":           "ac",
		"attack_context":         {"attacker_weapon": attacker.get("weapon", {})},
		"round_number":           _round_number,
		"attacker":               attacker,
		"target":                 target,
		"reactor_action_economy": null,
		"trigger_type":           "PreHitAvoidance",
		"reactor":                target,
		"weapon":                 target.get("weapon", {}),
	}


## _build_onhit_mitigation_trigger(attacker, target, attack_hit) -> Dictionary
## — FEAT-005 (US-005 / FR-005, Iteration J Part A): the ReactionTrigger built
## for the NEW, genuinely POST-HIT "OnHitMitigation" window, `await`ed by
## advance_ai_turn() AFTER resolve_action_use_case.resolve() has already
## determined this Strike's hit/miss result (test_criteria: firing order
## PreHitAvoidance then, conditionally, OnHitMitigation -- never before the
## roll). Shaped identically to _build_prehit_avoidance_trigger()'s trigger
## (same attacker/target/round_number/attack_context/weapon derivation --
## never a second, drifting convention), differing in:
##   "trigger_type"           -- "OnHitMitigation" so
##                                core/application/reaction_window.gd's
##                                _compute_legal_reactions() offers exactly
##                                Parry/Block (never Dodge/Steel -- those are
##                                ON-ATTACKED reactions already resolved by
##                                the PreHitAvoidance window above) once its
##                                own is_on_hit_mitigation_eligible() gate
##                                passes.
##   "attack_hit"              -- threaded through verbatim so the REAL
##                                reaction_window.gd's own "OnHitMitigation"
##                                eligibility gate (which this method's own
##                                caller already evaluated via
##                                ReactionWindowClass.is_on_hit_mitigation_eligible()
##                                before ever building this trigger) evaluates
##                                the SAME fact, never a second, drifting copy.
##   "reaction_already_spent"  -- always false here: this trigger is only ever
##                                built when advance_ai_turn() has already
##                                confirmed active_defense == "none" for this
##                                Strike (see this trigger's sole call site's
##                                own doc) -- i.e. no reaction has been spent
##                                yet.
## "reactor_action_economy" is withheld (null) for the SAME reason
## _build_reaction_trigger()/_build_prehit_avoidance_trigger() withhold it —
## this session never hands a live resolver's own ReactionWindow.resume() the
## authority to spend the reactor's reaction directly (see those methods' own
## FEAT-008 doc for the full double-spend rationale this mirrors).
func _build_onhit_mitigation_trigger(attacker: Dictionary, target: Dictionary, attack_hit: bool) -> Dictionary:
	return {
		"attacker_id":            attacker.get("combatant_id", attacker.get("name", "")),
		"target_id":              target.get("combatant_id", target.get("name", "")),
		"defense_type":           "ac",
		"attack_context":         {"attacker_weapon": attacker.get("weapon", {})},
		"round_number":           _round_number,
		"attacker":               attacker,
		"target":                 target,
		"reactor_action_economy": null,
		"trigger_type":           "OnHitMitigation",
		"reactor":                target,
		"weapon":                 target.get("weapon", {}),
		"attack_hit":             attack_hit,
		"reaction_already_spent": false,
	}


## _find_action_economy_for(combatant) -> ActionEconomy or null — FEAT-004:
## looks up the ActionEconomy instance this session already holds (in
## _entries) for `combatant`, so the reactor's OWN live budget (never a
## copy) can be threaded into the ReactionTrigger/DefenseContext. Matches by
## object identity first (the common case — `combatant` is literally the
## same Dictionary reference _entries already holds, since RoundSession's
## _party/_enemies and _entries are built from the SAME underlying
## Dictionaries — see RunRoundUseCase.begin_round()), falling back to the
## combatant_id/name identity convention used elsewhere in this codebase
## (e.g. resolve_action_use_case.gd's _combatant_identifier()) for doubles
## that rebuild an equal-but-distinct Dictionary. Returns null (a safe,
## documented sentinel — see _build_defense_context()'s handling) if no
## matching entry exists.
func _find_action_economy_for(combatant: Dictionary):
	for entry in _entries:
		if is_same(entry["combatant"], combatant):
			return entry["action_economy"]

	var combatant_id: String = combatant.get("combatant_id", combatant.get("name", ""))
	if combatant_id != "":
		for entry in _entries:
			var candidate: Dictionary = entry["combatant"]
			if candidate.get("combatant_id", candidate.get("name", "")) == combatant_id:
				return entry["action_economy"]

	return null


## _build_defense_context(target, target_action_economy) -> Dictionary —
## FEAT-004 (US-003 / FR-003, ADR-004): the DefenseContext value object (this
## feature's data_model) core/rules/resolution.gd's resolve_weapon_attack()
## expects as its trailing `defense_context` argument. Resolved ENTIRELY from
## the DEFENDER's (`target`'s) own data — this session never re-derives
## reaction eligibility/math itself (that remains resolution.gd's/
## reaction_window.gd's exclusive job):
##   "action_economy"       — the defender's live ActionEconomy (may be null
##                             — see _find_action_economy_for()'s doc; when
##                             null, resolution.gd's _try_spend_reaction()
##                             treats spending as untracked/always-allowed
##                             rather than crashing, its own documented
##                             contract). This is the SOLE site that actually
##                             spends the defender's reaction for a chosen
##                             Dodge/Block/Parry (pinned by
##                             tests/gut/test_enemy_strike_reaction_window.gd)
##                             — see _build_reaction_trigger()'s FEAT-008 doc
##                             above for why the ReactionTrigger handed to a
##                             LIVE presentation/turn_controller.gd
##                             resolve_reaction() resolver deliberately
##                             withholds its own "reactor_action_economy" so
##                             core/application/reaction_window.gd's resume()
##                             never ALSO spends the same reaction a second
##                             time.
##   "parrying_weapon"      — the defender's own weapon Dictionary (the only
##                             weapon slot this project's combatant model
##                             carries — see core/rules/resolution.gd's
##                             is_parry_eligible(), which no-ops when it
##                             lacks a positive parry_bonus).
##   "blocking_weapon"      — the SAME weapon Dictionary; is_block_eligible()
##                             similarly no-ops without a positive
##                             block_value. A single weapon safely serves
##                             both roles because resolution.gd never applies
##                             more than one active_defense per Strike.
##   "open_space_available" — true (default-safe; no hex-grid adjacency/
##                             occupancy query is wired into RoundSession
##                             this feature — see this feature's design
##                             note's data_model doc, "derived from a grid
##                             query, not stored" — a future feature may
##                             thread a real query in without changing this
##                             method's other keys).
func _build_defense_context(target: Dictionary, target_action_economy) -> Dictionary:
	var target_weapon: Dictionary = target.get("weapon", {})
	return {
		"action_economy":       target_action_economy,
		"parrying_weapon":      target_weapon,
		"blocking_weapon":      target_weapon,
		"open_space_available": true,
	}


# ── Interactive stepwise API (US-010/US-011) ───────────────────────────────

## current_actor() -> Dictionary — the combatant whose turn it is, or {}
## when the round is over.
func current_actor() -> Dictionary:
	if _round_over or _cursor == -1:
		return {}
	return _entries[_cursor]["combatant"]


## current_action_economy() -> ActionEconomy or null — the ActionEconomy
## paired with current_actor() (the TurnOrderEntry shape). Not itself part
## of the design's headline method list, but required so Presentation
## (turn_controller.gd) can hand the active player's budget to
## StrikeActionControl.configure() without reaching back into Infrastructure.
func current_action_economy():
	if _round_over or _cursor == -1:
		return null
	return _entries[_cursor]["action_economy"]


## action_budget_snapshot() -> Array — one read-only Dictionary per combatant
## this session holds: {combatant_id, remaining, spent}, read live off the
## SAME per-entry ActionEconomy instances advance_ai_turn()/end_current_turn()
## mutate (never a copy). Presentation (MainScene._refresh_all_action_budgets())
## uses this to re-push every combatant's Actions/Spent readout to
## StatusPanelView after a run of auto-driven Enemy turns — an Enemy Stride/WAIT
## spends from its budget but emits no AttackEvent (unlike a Strike), so without
## this the enemy row's count goes stale. Pure read; mutates nothing, and is
## valid whether or not the round is over.
func action_budget_snapshot() -> Array:
	var snapshot: Array = []
	for entry in _entries:
		var combatant: Dictionary = entry["combatant"]
		var action_economy = entry["action_economy"]
		snapshot.append({
			"combatant_id": combatant.get("combatant_id", combatant.get("name", "")),
			"remaining":    action_economy.get_remaining(),
			"spent":        action_economy.is_spent(),
		})
	return snapshot


## is_round_over() -> bool — true when every living combatant is Spent OR an
## EncounterResultEvent has been emitted (or, autonomous path only, the
## stalled-cycle backstop forced a DRAW).
func is_round_over() -> bool:
	return _round_over


## outcome() -> String — '' | 'won' | 'lost' (never 'DRAW' — see finish()
## for the per-round DRAW distinction).
func outcome() -> String:
	return _outcome


## advance_ai_turn() -> Dictionary — for a current actor whose team is
## Enemy: obtains the action from AIDecisionPort, resolves it via the SAME
## resolve_action_use_case.resolve() the player's own Strike goes through,
## consults DetermineOutcomeUseCase, and advances the cursor. Calling this
## after is_round_over(), or when the current actor is not on the Enemy
## team, is a no-op returning {"ok": false}.
##
## WAIT (US-001 / FR-001, ADR-010): when core/combat/ai.gd's decide_action()
## reports its null-action sentinel ({"action_type": "", "target": {}, ...}
## — no living target, or the nearest one is out of reach and cannot be
## closed this turn), this method resolves that sentinel as an explicit
## WAIT (core/rules/actions.gd Actions.resolve_wait()) rather than a bare,
## budget-neutral cursor advance. WAIT spends exactly one action from the
## SAME ActionEconomy budget every other resolvable action draws from, so a
## permanently idle/unreachable enemy still depletes to Spent within
## ActionEconomy.MAX_BUDGET (7) of its OWN turns — the steel-thread
## round-termination guarantee this feature exists for (e.g. a kiting 1v1
## where the enemy can never close the distance). Defensive fallback (US-011
## error_handling): on the rare occasion WAIT itself is rejected (e.g. a
## stale/misbehaving AIDecisionPort double already spent this turn's one
## action), that is logged via push_warning() and the cursor is STILL
## advanced, so the loop can never stall/deadlock.
##
## FEAT-007 (US-007 / FR-005, ADR-105): the AIDecision obtained via
## _decide_ai_action() below carries EXACTLY ONE action — "Strike" or
## "Stride", never both (core/combat/ai.gd's FEAT-005 composite
## "Stride-then-Strike" path, and its will_strike-driven handling here, are
## REMOVED). When action_type is "Stride", core/combat/ai.gd's
## decide_action() has already EXECUTED the Stride itself (repositioning
## `combatant` and spending its ActionEconomy's Movement-trait action
## directly through core/rules/movement.gd, the SAME domain path a
## player-driven Stride uses) as part of building that decision — ai.gd is
## the single mover for both paths (ADR-001), so this method never re-spends
## or re-resolves the Stride half, and never attempts a same-turn Strike
## after it (any Strike the Stride enabled is decided on the enemy's NEXT
## turn). When action_type is "Strike", this method resolves it via
## _resolve_action_use_case.resolve() — the IDENTICAL pipeline the player's
## own Strike already goes through. No new port or use-case is introduced
## (ADR-002): the decision flows through the existing
## AIDecisionPort/ResolveActionUseCase contracts. Together with
## core/combat/ai.gd's one-decision-per-call contract, this guarantees
## advance_ai_turn() triggers at most ONE ActionEconomy.spend_action() call
## per AI turn — the same one-action gate the player is bound to.
## FEAT-003 (US-002 / FR-002, ADR-003, NFR-004): advance_ai_turn() is now a
## genuine coroutine (GDScript's `await`-driven suspension) — on the
## "Strike" branch below it awaits _resolve_reaction() BEFORE resolving the
## Strike, so an injected reaction resolver genuinely gets to run the
## defender's reaction to completion (however long that takes — a blocking
## player pop-up, a delayed test double, ...) before
## resolve_action_use_case.resolve() ever executes. Every existing caller
## that never injects a resolver (set_reaction_resolver_fn() never called —
## every headless/sim caller, and every pre-existing test) still resolves
## `await _resolve_reaction(...)` against the SAME synchronous, zero-await
## {"choice": "none"} fallback documented on _resolve_reaction() above: in
## GDScript, `await`ing an expression that never actually suspends (no
## Signal wait occurs) returns its value immediately, so this coroutine
## NEVER actually yields control back to the caller for that fallback path
## — behavior for those callers is byte-for-byte unchanged (NFR-004).
## GDScript nonetheless statically requires every direct call site of a
## function containing `await` anywhere in its body to itself use `await`
## (a parse-time rule, not a runtime one) — every caller in this codebase
## has been updated accordingly as part of this feature's mandated
## "audit every caller in the await chain" scope; see
## tests/gut/test_async_reaction_propagation.gd's audit test for the
## enumerated list.
func advance_ai_turn() -> Dictionary:
	if _round_over or _cursor == -1:
		return {"ok": false}

	var entry: Dictionary = _entries[_cursor]
	var combatant: Dictionary = entry["combatant"]
	if not combatant.get("_is_enemy", false):
		return {"ok": false, "error": "ERR_NOT_ENEMY_TURN"}

	var action_economy = entry["action_economy"]
	# ADR-101/ADR-102/FEAT-004: start_of_turn() for this actor was already
	# invoked exactly once by whichever cursor-positioning call site (_init,
	# or the prior _advance_cursor()) made this actor the current_actor() —
	# see the file-level and _advance_cursor() doc comments. Calling it again
	# here would be a redundant second call site for the SAME turn boundary,
	# which is exactly the P0-1/duplication defect this feature closes; the
	# call is intentionally NOT repeated here.
	var ai_decision: Dictionary = _decide_ai_action(combatant, action_economy)
	var action_name: String = ai_decision.get("action_type", "")
	var target: Dictionary = ai_decision.get("target", {})

	var any_action_taken: bool = false

	if action_name == "Stride":
		# The Stride itself already happened inside decide_action() (see
		# file-level doc above) — nothing further to resolve for it here.
		# FEAT-007: never a composite — the Strike half (if any) is decided
		# on this combatant's next turn, never resolved in this same call.
		any_action_taken = true
		_reposition_token_after_ai_stride(combatant, ai_decision)
	elif action_name != "" and not target.is_empty():
		# FEAT-003 proved awaiting the injected ReactionResolverPort BEFORE
		# resolving an enemy-Strikes-player Strike is safe (no deadlock, no
		# double-advance). FEAT-004 (US-003 / FR-003, ADR-004) now ACTS on
		# the resolver's answer: the resolved `active_defense` and a freshly
		# built DefenseContext (see _build_defense_context()'s doc) are
		# threaded verbatim into resolve_action_use_case.resolve()'s
		# trailing parameters — the SAME pass-through
		# resolve()/_resolve_strike() have accepted since FEAT-001, and the
		# SAME core/rules/resolution.gd math every other reaction-enabled
		# call site (e.g. reaction_window.gd's open_and_resolve_attack())
		# already exercises; this method never re-implements Dodge/Block/
		# Parry/Steel math or re-derives eligibility itself. A malformed or
		# un-injected resolver still degrades safely to active_defense
		# "none" / defense_context {} (see
		# _reaction_choice_to_active_defense()'s doc), which resolves
		# byte-for-byte identically to the pre-FEAT-004 default-only call --
		# tests/characterization/test_strike_characterization.gd's pin, and
		# this feature's own "Pass reproduces the exact pre-sprint unreacted
		# outcome" test_criterion.
		var active_defense: String = "none"
		var defense_context: Dictionary = {}
		# FEAT-008 (US-008 / FR-007): populated by whichever reaction branch
		# below actually resolved a defense for this Strike (the PreHitAvoidance
		# Dodge/Steel branch, or the OnHitMitigation Parry/Block branch inside
		# the two_phase_commit_pending block) — consumed once, right after
		# record_attack() below, to call RenderCombatLogUseCase.
		## record_reaction_outcome() so the rich row's Defense segment reflects
		## the ACTUAL outcome rather than always defaulting to "none".
		## reaction_window_id_for_log stays "" (no recording call) whenever
		## neither branch below resolved a reaction-eligible window for this
		## Strike (e.g. the legacy single-window "WeaponAttack" fallback path,
		## which no real composition-root boot ever takes — see this method's
		## own doc on `_onhit_mitigation_resolver_fn.is_valid()`).
		var reaction_window_id_for_log: String = ""
		var reaction_choice_for_log: String = "none"
		var reaction_success_for_log: bool = false
		var reaction_reduced_by_for_log: int = 0
		# FEAT-003 (US-002 / FR-002, G3 remediation): true once this Strike has
		# opted into GENUINE two-phase commit -- see the `else` branch below
		# (immediately preceding the removed trace-only stub this feature
		# replaces). When true, the atomic call to _resolve_action_use_case's
		# resolve() method a few lines down is SKIPPED ENTIRELY in favor of the deferred
		# resolve_to_hit_uc -> await OnHitMitigation -> apply_on_hit_defense_uc
		# sequence inlined below (still literally inside advance_ai_turn()'s own
		# body -- see tests/gut's/core/application/tests' static source-shape
		# audit, which requires the SECOND await point to remain coded directly
		# in this function, never delegated to a helper it merely calls).
		var two_phase_commit_pending: bool = false
		# FEAT-003 (US-003 / FR-002): declared here (rather than inside the
		# nested "Strike" branch below) so the budget-delta gate after
		# resolve_action_use_case.resolve() below -- which needs
		# `target_action_economy` -- can see the SAME variable the Strike
		# branch populates. `action_name` is always "Strike" whenever this
		# elif is reached (see the file-level "EXACTLY ONE action -- Strike
		# or Stride, never both" doc above); left null/-1 for any other
		# action_name so the gate below is a no-op in that case.
		var target_action_economy = null
		var reaction_budget_before: int = -1
		if action_name == "Strike":
			target_action_economy = _find_action_economy_for(target)
			# FEAT-003 (US-003 / FR-002): snapshot the defender's
			# reaction-eligible budget BEFORE either reaction window
			# (PreHitAvoidance below, and -- when not suppressed -- the
			# existing on-hit WeaponAttack window) is ever awaited for this
			# Strike. The budget-delta gate below compares this snapshot
			# against the same ActionEconomy's remaining budget once the
			# ENTIRE Strike (both windows, plus
			# resolve_action_use_case.resolve()'s own reaction-spending
			# resolve_weapon_attack() call) has resolved, proving AT MOST ONE
			# reaction was spent across the whole Strike regardless of which
			# branch below actually ran -- the shared spend_reaction() gate's
			# budget-delta assertion this feature adds (design notes: "a
			# budget-delta assertion (<=1 spent per Strike) in the shared
			# reaction resolution path").
			if target_action_economy != null:
				reaction_budget_before = target_action_economy.get_remaining()

			# FEAT-002 (US-002 / FR-001, Iteration J Part B): the
			# PreHitAvoidance window (Dodge/Steel only) is awaited FIRST --
			# BEFORE the existing WeaponAttack trigger is even built, and
			# before any call in this chain ever reaches
			# core/rules/resolution.gd's resolve_to_hit() (test_criteria
			# #5). For every existing caller/test double (no
			# set_prehit_avoidance_resolver_fn() call -- see that seam's own
			# doc), _resolve_prehit_avoidance() resolves against its
			# synchronous {"choice": "none"} default-safety fallback, so
			# prehit_choice below is always "none" and this branch's
			# behavior is byte-for-byte unchanged (NFR-004).
			var prehit_trigger: Dictionary = _build_prehit_avoidance_trigger(combatant, target)
			var prehit_result: Dictionary = await _resolve_prehit_avoidance(prehit_trigger)
			var prehit_choice: String = _reaction_choice_to_active_defense(prehit_result)
			var prehit_on_hit_suppressed: bool = prehit_result.get("on_hit_suppressed", false)

			if prehit_choice == "dodge" or prehit_choice == "steel":
				# A pre-hit reaction was already decided by the
				# PreHitAvoidance window -- resolve_action_use_case.resolve()'s
				# own resolve_to_hit() call (FEAT-001) remains the SOLE place
				# the actual dodge/steel roll happens (this session never
				# re-derives it); this window only ever decided the CHOICE.
				# The existing WeaponAttack window is deliberately never
				# asked in this branch -- the <=1-reaction-per-Strike budget
				# invariant means a reactor who already chose Dodge/Steel
				# here must never ALSO be offered a second reaction for the
				# same Strike (dodge-fail's "on_hit_suppressed" contract,
				# test_criteria #3).
				active_defense = prehit_choice
				defense_context = _build_defense_context(target, target_action_economy)
			elif not prehit_on_hit_suppressed:
				# FEAT-005 (US-005 / FR-005, Iteration J Part A): two-phase mode is
				# opted into once a caller injects a DEDICATED OnHitMitigation
				# resolver (set_onhit_mitigation_resolver_fn() -- MainScene.gd wires
				# this for real play, this feature). In that mode the legacy
				# combined "WeaponAttack" ask below (Dodge+Parry+Block unioned
				# BEFORE the roll even happens) is retired in favor of asking
				# Block/Parry strictly AFTER the hit result is known -- see the
				# two-phase commit block below (the SECOND await point this
				# coroutine awaits). active_defense/defense_context are
				# deliberately left "none"/{} here -- when two_phase_commit_pending
				# is set, they are never even handed to
				# _resolve_action_use_case's atomic resolve() at all (that atomic call is
				# skipped entirely in favor of the deferred commit below).
				#
				# Every pre-existing caller/test double that never calls
				# set_onhit_mitigation_resolver_fn() (NFR-004 default-safety) takes
				# the unchanged legacy path in the `if` branch instead, so this
				# feature introduces zero behavior change for them.
				if not _onhit_mitigation_resolver_fn.is_valid():
					var trigger: Dictionary = _build_reaction_trigger(combatant, target, target_action_economy)
					# FEAT-007 (observability #2): trigger-built trace point.
					_trace(
						"reaction_trigger_built attacker_id=%s target_id=%s round=%d"
						% [trigger.get("attacker_id", ""), trigger.get("target_id", ""), _round_number]
					)
					# FEAT-007: awaiting-resolver-start trace point -- emitted
					# immediately BEFORE the await below, so a genuinely hung/
					# never-resolving resolver is visible as "this line printed, but
					# resolver_resolved never did" rather than a silent freeze.
					_trace(
						"awaiting_resolver_start attacker_id=%s target_id=%s round=%d"
						% [trigger.get("attacker_id", ""), trigger.get("target_id", ""), _round_number]
					)
					var reaction_result: Dictionary = await _resolve_reaction(trigger)
					# FEAT-007: resolver-resolved trace point.
					_trace(
						"resolver_resolved choice=%s round=%d"
						% [str(reaction_result.get("choice", "")), _round_number]
					)
					active_defense = _reaction_choice_to_active_defense(reaction_result)
					defense_context = _build_defense_context(target, target_action_economy)
				else:
					# FEAT-003 (US-002 / FR-002, G3 remediation): two-phase mode --
					# defer to the genuine deferred-commit block below instead of
					# the atomic resolve() call.
					two_phase_commit_pending = true
			# else: prehit_on_hit_suppressed with no explicit dodge/steel
			# choice (a defensive/malformed-resolver case) -- active_defense/
			# defense_context stay "none"/{}, matching Pass.

		# FEAT-006 (US-006 / FR-006, Iteration J-R2 Part D): capture the
		# append-order index the plain-format on_attack_event() row is ABOUT
		# to land at -- inside whichever resolve path below synchronously
		# emits this Strike's AttackEvent via EventSinkPort -- BEFORE
		# resolving, mirroring MainScene.gd's `_verb_bar_strike_execute()`
		# player-path convention (FEAT-005) exactly. -1 (a safe no-op sentinel
		# for the overwrite call below) when no entry-count Callable was
		# injected -- every pre-existing caller/test double (NFR-004).
		var pending_entry_index: int = (
			_event_log_entry_count_fn.call() if _event_log_entry_count_fn.is_valid() else -1
		)

		var resolve_result: Dictionary = {}
		# FEAT-219 (PR-002 remediation): the RAW (pre-mitigation) damage for
		# THIS Strike, captured directly from the to-hit phase's own partial
		# result (`partial.get("damage_raw", 0)`) inside the two_phase_commit_pending
		# branch below -- NEVER re-derived from resolution.gd a second way.
		# -1 is a "not captured this call" sentinel (the legacy atomic
		# `else` branch below never populates it -- resolve_action_use_case.gd
		# is out of this feature's scope; see the structured_attack_event
		# construction below, which falls back to its pre-existing
		# damage_final-duplicate behavior in that case, an unchanged NFR-004
		# default-safety path). Consumed below to fix core/log/attack_event.gd's
		# damage_raw field, which this call site previously populated with a
		# SECOND COPY of damage_final instead of the true raw damage --
		# silently making it impossible for any observer (rich log row,
		# get_structured_attack()) to ever see that Parry/Block genuinely
		# reduced damage relative to the raw roll (the exact gap DEF-001/
		# PR-002 flagged: mitigation could regress to a no-op without any
		# code-verifiable signal catching it).
		var strike_damage_raw_for_log: int = -1

		if two_phase_commit_pending:
			# FEAT-003 (US-002 / FR-002, G3 remediation): the GENUINE two-phase
			# Strike commit -- replaces the old trace-but-don't-apply stub this
			# feature exists to fix (see this file's FEAT-003 top-level doc; the
			# anti-pattern that caused DEF-001, previously at ~line 1141-1167).
			# Spends the action, rolls ONLY the to-hit phase via
			# _resolve_action_use_case.get_resolve_to_hit_use_case() (NO
			# hp_current mutation, NO event emitted -- ResolveToHitUseCase's own
			# documented contract), AWAITS the OnHitMitigation window -- the
			# SECOND await point this coroutine awaits, coded directly here so
			# it stays inside advance_ai_turn()'s own body -- ONLY when the roll
			# actually hit (ReactionWindowClass.is_on_hit_mitigation_eligible()'s
			# own gate, never re-derived a second way; reaction_already_spent is
			# always false at this call site -- prehit already proved it did not
			# suppress this Strike's one reaction), and ONLY THEN commits via
			# _resolve_action_use_case.get_apply_on_hit_defense_use_case().apply()
			# -- the SOLE hp_current mutation / AttackEvent emission for this
			# Strike. A resolved Parry/Block choice therefore genuinely reduces
			# the damage actually committed, rather than being asked about and
			# discarded (test_criteria: Parry/Block mitigation actually applies;
			# Pass reproduces the raw/unmitigated outcome byte-for-byte).
			#
			# Precondition checks deliberately mirror ONLY
			# _resolve_action_use_case's atomic resolve()'s action-economy spend
			# (ERR_NO_ACTION_REMAINING) -- the melee-reach precondition is
			# intentionally NOT re-derived here: this branch's sole caller
			# (advance_ai_turn()'s enemy-Strikes-player path) only ever reaches a
			# target core/combat/ai.gd's decide_action() already chose as
			# adjacent/in-range (ai.gd's own job -- see
			# tests/unit/core/combat/test_ai_reach_strike.gd); re-deriving the
			# same reach math here would be a second, drifting copy of a rule
			# resolve_action_use_case.gd already owns, not a genuine
			# defense-in-depth gain for this call path.
			var spend_result: Dictionary = action_economy.spend_action({"name": action_name, "traits": []})
			if not spend_result.get("success", false):
				resolve_result = {"resolved": false, "ok": false, "error": "ERR_NO_ACTION_REMAINING"}
			else:
				var weapon: Dictionary = combatant.get("weapon", {})
				var to_hit_uc = _resolve_action_use_case.get_resolve_to_hit_use_case()
				var partial: Dictionary = to_hit_uc.resolve_to_hit(combatant, target, weapon, "ac", "none", {})
				var attack_hit: bool = partial.get("hit", false)
				var on_hit_defense: String = "none"
				# FEAT-219 (PR-002 remediation): capture the true pre-mitigation
				# damage for this Strike straight off the to-hit phase's own
				# result -- the SAME `partial` dict apply_uc.apply() below is
				# handed, never a second/re-derived read.
				strike_damage_raw_for_log = partial.get("damage_raw", 0)

				if ReactionWindowClass.is_on_hit_mitigation_eligible(false, attack_hit):
					var onhit_trigger: Dictionary = _build_onhit_mitigation_trigger(combatant, target, attack_hit)
					_trace(
						"onhit_mitigation_trigger_built attacker_id=%s target_id=%s round=%d"
						% [onhit_trigger.get("attacker_id", ""), onhit_trigger.get("target_id", ""), _round_number]
					)
					var onhit_result: Dictionary = await _resolve_onhit_mitigation(onhit_trigger)
					on_hit_defense = _reaction_choice_to_active_defense(onhit_result)
					_trace(
						"onhit_mitigation_resolved choice=%s round=%d"
						% [on_hit_defense, _round_number]
					)

				var onhit_defense_context: Dictionary = _build_defense_context(target, target_action_economy)
				var actor_updated_action_budget: Dictionary = {
					"remaining": spend_result.get("remaining", -1),
					"spent":     action_economy.is_spent(),
				}

				var apply_uc = _resolve_action_use_case.get_apply_on_hit_defense_use_case()
				var apply_result: Dictionary = apply_uc.apply(
					partial, combatant, target, on_hit_defense, onhit_defense_context,
					_round_number, actor_updated_action_budget
				)

				# FEAT-008 (US-008 / FR-007): capture the OnHitMitigation
				# outcome for RenderCombatLogUseCase below -- reformats
				# apply_on_hit_defense()'s ALREADY-COMPUTED
				# active_defense_applied/on_hit_suppressed/damage_final fields
				# (never re-derived here). reduced_by is the actual
				# damage-reduction amount Block applied (0 for a non-Block
				# choice, or a Block that reduced nothing); success mirrors
				# on_hit_suppressed, meaningful only for a Parry (see
				# render_combat_log_use_case.gd's _derive_outcome() doc).
				reaction_window_id_for_log = RenderCombatLogUseCaseClass.WINDOW_ON_HIT_MITIGATION
				reaction_choice_for_log = apply_result.get("active_defense_applied", "none")
				reaction_success_for_log = apply_result.get("on_hit_suppressed", false)
				reaction_reduced_by_for_log = max(0, partial.get("damage_raw", 0) - apply_result.get("damage_final", 0))

				var history_entry = RoundEventsClass.RoundHistoryEntry.new(
					_round_number, _cycle_index, combatant.get("name", ""), action_name, spend_result.get("remaining", -1)
				)
				_round_history_port.append({
					"attacker":         combatant,
					"action":           action_name,
					"target":           target,
					"roll":             partial.get("roll_total", 0),
					"damage_final":     apply_result.get("damage_final", 0),
					"budget_remaining": spend_result.get("remaining", -1),
					"round":            _round_number,
					"cycle_index":      _cycle_index,
					"entry":            history_entry
				})

				resolve_result = {
					"resolved":        true,
					"ok":              true,
					"event":           apply_result.get("event", null),
					"target_defeated": apply_result.get("defender_defeated", false),
					"damage_final":    apply_result.get("damage_final", 0),
				}
		else:
			resolve_result = _resolve_action_use_case.resolve(
				combatant, action_economy, target, action_name, _round_number, _cycle_index,
				"", active_defense, defense_context
			)

			# FEAT-008 (US-008 / FR-007): capture the PreHitAvoidance outcome
			# for RenderCombatLogUseCase below -- only reachable when
			# active_defense is "dodge"/"steel" (a genuine pre-hit reaction was
			# chosen; see the branch above that set it). Dodge/Steel succeeded
			# iff the JUST-resolved Strike's own "event" reports the attack
			# missed (core/rules/resolution.gd's resolve_to_hit() `not hit`
			# result, mirrored onto RoundEvents.AttackEvent.hit here) -- never
			# re-derived, only read back from the SAME resolved event this
			# method already forwards to record_attack() below.
			if active_defense == "dodge" or active_defense == "steel":
				var resolved_event_for_reaction = resolve_result.get("event", null)
				if resolved_event_for_reaction != null:
					reaction_window_id_for_log = RenderCombatLogUseCaseClass.WINDOW_PRE_HIT_AVOIDANCE
					reaction_choice_for_log = active_defense
					reaction_success_for_log = not resolved_event_for_reaction.hit

		any_action_taken = resolve_result.get("resolved", false)

		# FEAT-007 (US-007 / FR-008) / FEAT-006 (US-006 / FR-006): forward a
		# STRUCTURED AttackEvent (core/log/attack_event.gd) for this
		# JUST-resolved Strike to whatever record_attack Callable the
		# composition root injected via set_event_log_record_attack_fn() --
		# a complete no-op for every pre-existing caller/test double
		# (NFR-004). Deliberately built from the SAME resolve_result["event"]
		# instance emitted via EventSinkPort above -- never a second,
		# re-derived roll/damage computation. FEAT-006 additionally renders
		# and overwrites the plain-format row in place (see the inline doc
		# immediately below) -- exactly one rich row per resolved enemy
		# Strike, mirroring MainScene.gd's player-path wiring (FEAT-005).
		if action_name == "Strike" and any_action_taken:
			var resolved_attack_event_for_log = resolve_result.get("event", null)
			if resolved_attack_event_for_log != null:
				var attack_event_id: String = _generate_attack_event_id()
				var log_weapon: Dictionary = combatant.get("weapon", {})
				# FEAT-219 (PR-002 remediation): the structured, storage-shaped
				# AttackEvent's damage_raw field must carry the ACTUAL
				# pre-mitigation damage (strike_damage_raw_for_log, captured
				# above straight off the to-hit phase) -- previously this call
				# site passed a SECOND COPY of damage_final into this slot,
				# making it impossible for any observer (get_structured_attack(),
				# the rendered rich log row) to ever see that a successful
				# Parry/Block genuinely reduced damage relative to the raw
				# roll. The -1 sentinel (legacy atomic path, out of this
				# feature's scope) preserves the pre-existing damage_final-
				# duplicate fallback byte-for-byte (NFR-004 default-safety).
				var log_damage_raw: int = (
					strike_damage_raw_for_log
					if strike_damage_raw_for_log >= 0
					else resolved_attack_event_for_log.damage_final
				)
				var structured_attack_event = AttackEventClass.new(
					attack_event_id,
					_round_number,
					combatant.get("combatant_id", combatant.get("name", "")),
					target.get("combatant_id", target.get("name", "")),
					log_weapon.get("weapon_id", log_weapon.get("name", "")),
					resolved_attack_event_for_log.roll,
					resolved_attack_event_for_log.hit,
					resolved_attack_event_for_log.crit,
					log_damage_raw,
					resolved_attack_event_for_log.damage_final,
					false,
					false
				)

				if _event_log_record_attack_fn.is_valid():
					_event_log_record_attack_fn.call(structured_attack_event)

				# FEAT-008 (US-008 / FR-007): pair this Strike's ACTUAL
				# dodge/steel/parry/block outcome (captured above by whichever
				# reaction branch this Strike actually took --
				# reaction_window_id_for_log/reaction_choice_for_log/
				# reaction_success_for_log/reaction_reduced_by_for_log) to the
				# JUST-recorded structured AttackEvent via
				# RenderCombatLogUseCase.record_reaction_outcome(), so
				# render_attack_entry() below renders the CORRECT
				# 'Defense: <outcome>' segment instead of always falling back
				# to "none". A no-op (no ReactionResolvedEvent recorded) when
				# neither reaction branch resolved a window for this Strike --
				# reaction_window_id_for_log stays "" in that case (see its own
				# doc above).
				if reaction_window_id_for_log != "":
					var render_combat_log_use_case := RenderCombatLogUseCaseClass.new()
					render_combat_log_use_case.record_reaction_outcome(
						attack_event_id, reaction_window_id_for_log, reaction_choice_for_log,
						"human", reaction_success_for_log, reaction_reduced_by_for_log,
						_event_log_record_reaction_fn
					)

				# FEAT-006 (US-006 / FR-006, Iteration J-R2 Part D): mirror
				# MainScene.gd's `_verb_bar_strike_execute()` player-path rich-log
				# rendering (FEAT-005) for this enemy-strikes-player call site.
				# render_attack_entry() formats the roll/raw/final-damage rich text
				# from the JUST-recorded structured AttackEvent above (never a
				# second, re-derived roll/damage computation), and
				# overwrite_entry_as_rich() overwrites the plain-format row
				# on_attack_event() appended (at pending_entry_index, captured
				# above BEFORE this Strike resolved) in place -- so exactly one,
				# rich-format row is visible for this Strike, never a basic+rich
				# duplicate pair. A complete no-op (the plain row is left as-is)
				# when either Callable was never injected, or no entry-count
				# Callable was injected (pending_entry_index stays -1) — every
				# pre-existing caller/test double (NFR-004).
				if (
					_event_log_render_attack_entry_fn.is_valid()
					and _event_log_overwrite_entry_fn.is_valid()
					and pending_entry_index != -1
				):
					var rich_text: String = _event_log_render_attack_entry_fn.call(attack_event_id)
					_event_log_overwrite_entry_fn.call(pending_entry_index, rich_text, attack_event_id)

		# FEAT-005 (US-005 / FR-005, Iteration J Part A) / FEAT-003 (G3
		# remediation): the SECOND await point this feature introduces into
		# advance_ai_turn's coroutine chain -- a genuinely POST-HIT
		# "OnHitMitigation" ask (Parry/Block only) -- now lives directly inside
		# the `two_phase_commit_pending` block above (still coded literally
		# inside advance_ai_turn()'s own body), fired strictly AFTER the to-hit
		# phase has already determined this Strike's hit/miss result, and ONLY
		# when: (a) this is a Strike, (b) two-phase mode was opted into (a
		# dedicated OnHitMitigation resolver was injected -- see the elif
		# branch above), and (c) no reaction has been spent yet this Strike (a
		# Dodge/Steel choice from the PreHitAvoidance window always sets
		# active_defense to something else, correctly skipping two-phase mode
		# entirely per the <=1-reaction-per-Strike budget rule). Firing order is
		# therefore always PreHitAvoidance (above) THEN, conditionally,
		# OnHitMitigation (in the two_phase_commit_pending block above) --
		# never reversed, never duplicated (fires at most once per Strike). The
		# resolved choice GENUINELY reduces the damage committed -- see the
		# two_phase_commit_pending block's own doc; this is the G3 remediation
		# fix (previously a trace-but-don't-apply stub lived here).

		# FEAT-003 (US-003 / FR-002): the shared budget-delta gate — proves
		# AT MOST ONE reaction was actually spent from the defender's
		# ActionEconomy across this ENTIRE Strike (the PreHitAvoidance
		# window, the existing on-hit WeaponAttack window, and
		# resolve_action_use_case.resolve()'s own resolve_weapon_attack()
		# call — whichever combination of branches above actually ran),
		# never re-deriving the <=1-reaction-per-Strike invariant a second,
		# drifting way. A no-op (delta always 0 or 1) for every correctly
		# behaving call path, including every pre-existing test — this is a
		# detective regression guard, not a behavior change (NFR-004).
		if target_action_economy != null:
			var reaction_budget_after: int = target_action_economy.get_remaining()
			var reaction_budget_delta: int = reaction_budget_before - reaction_budget_after
			var budget_gate_label: String = "round=%d attacker=%s target=%s" % [
				_round_number,
				combatant.get("combatant_id", combatant.get("name", "")),
				target.get("combatant_id", target.get("name", "")),
			]
			if not ReactionWindowClass.assert_reaction_budget_delta(reaction_budget_delta, budget_gate_label):
				_reaction_budget_violations.append({
					"round_number": _round_number,
					"attacker_id": combatant.get("combatant_id", combatant.get("name", "")),
					"target_id":   target.get("combatant_id", target.get("name", "")),
					"delta":       reaction_budget_delta,
				})
	else:
		# US-001 / FR-001 (ADR-010): the null-action AI sentinel — resolve it
		# as an explicit WAIT (see the doc block above) instead of a bare,
		# budget-neutral cursor advance, so this combatant's action budget
		# genuinely depletes turn over turn.
		var wait_result: Dictionary = ActionsClass.resolve_wait(action_economy)
		any_action_taken = wait_result.get("success", false)

	if not any_action_taken:
		push_warning(
			"RoundSession.advance_ai_turn: no action resolved for '%s'; advancing turn regardless (CWE-835 guard)"
			% combatant.get("name", "")
		)
		_advance_cursor()
		return {"ok": true, "resolved": false}

	return _after_action_resolved()


## _decide_ai_action(combatant, action_economy) -> Dictionary — FEAT-006
## (US-006 / FR-010, ADR-002): drives the injected AIDecisionPort's
## decide_action(). Every pre-existing 2-argument adapter/test-double
## (core/application/ai_decision_port.gd's documented contract:
## decide_action(combatant, targets) -> Dictionary — e.g. this suite's own
## FakeAIDecisionPort/BrokenAIDecisionPort doubles) is called EXACTLY as
## before. When the injected port is the REAL core/combat/ai.gd — whose
## decide_action() additionally accepts the FEAT-004/005 OPTIONAL
## (action_economy, other_combatants) parameters — the extended 4-argument
## call is used instead, so the Stride-closing / Stride-then-Strike decision
## flow can actually execute through this orchestration. Which shape to call
## is determined via Callable.get_argument_count() (reflection over the
## port's own declared method signature), never a new static port/use-case
## type — no new port or use-case class is introduced by this feature.
func _decide_ai_action(combatant: Dictionary, action_economy) -> Dictionary:
	var decide_callable := Callable(_ai_decision_port, "decide_action")
	if decide_callable.get_argument_count() < 4:
		return decide_callable.call(combatant, _party)

	var other_combatants: Array = []
	for enemy in _enemies:
		if not is_same(enemy, combatant):
			other_combatants.append(enemy)

	return decide_callable.call(combatant, _party, action_economy, other_combatants)


## _reposition_token_after_ai_stride(combatant, ai_decision) -> void —
## FEAT-008 (US-008 / FR-012, ADR-006): invokes the injected
## `_token_reposition_fn` (see set_token_reposition_fn()'s doc) with the
## acting combatant's id and the Stride's destination hex — the EXACT SAME
## call presentation/movement_input_controller.gd's _resync_token_renderers()
## already makes for a player-driven Stride
## (hex_grid_view.move_token(actor_id, destination_hex)): same function, same
## call shape, only the actor_id/destination differ. A no-op when no
## reposition fn was injected (every headless test/the autonomous
## run_autonomous_to_completion() path never calls
## set_token_reposition_fn()) or when the decision carries no destination
## (defensive — decide_action() always supplies one for action_type
## "Stride", but this guards regardless of caller shape).
func _reposition_token_after_ai_stride(combatant: Dictionary, ai_decision: Dictionary) -> void:
	if not _token_reposition_fn.is_valid():
		return
	var destination = ai_decision.get("destination", null)
	if destination == null:
		return
	var actor_id: String = combatant.get("combatant_id", combatant.get("name", ""))
	_token_reposition_fn.call(actor_id, destination)


## end_current_turn() -> Dictionary — ends the current (player) actor's
## turn: consults DetermineOutcomeUseCase (emitting EncounterResultEvent if
## the player's just-resolved Strike ended the encounter), then advances the
## cursor to the next living, un-Spent actor. ALWAYS available regardless of
## whether/what action was spent this turn (US-010) — this method never
## itself spends an action or calls resolve_action_use_case. A no-op
## ({"ok": false}) once is_round_over().
##
## FEAT-004 (US-002 / FR-002, ADR-010): this is the PLAYER's free-pass path —
## deliberately distinct from advance_ai_turn()'s handling of an Enemy's
## null-action AI sentinel, which resolves as an explicit WAIT
## (core/rules/actions.gd Actions.resolve_wait()) that DOES spend one action
## via ActionEconomy.spend_action(). A player who ends their turn having
## chosen no action at all is never routed through resolve_wait() or any
## other spend_action()/spend_reaction() call here — end_current_turn()
## forwards straight to the shared _after_action_resolved() tail below,
## leaving the free-passing combatant's ActionEconomy.budget_remaining and
## is_spent() completely untouched, so that combatant's full budget remains
## available for a later reaction (Dodge/Parry/Block) this same round. The
## enemy WAIT path exists to guarantee round termination for an idle/
## unreachable Enemy (US-001); the player free-pass path exists so choosing
## not to act never costs the player anything (US-002) — the two are
## intentionally asymmetric.
func end_current_turn() -> Dictionary:
	if _round_over or _cursor == -1:
		return {"ok": false}
	return _after_action_resolved()


## finish() -> Dictionary — ends the round and returns the RoundResult
## Dictionary shaped identically to RunRoundUseCase.execute()'s pre-FEAT-110
## return:
##   {round_number: int, outcome: String, history: Array, encounter_outcome: String}
##
## FEAT-006 (US-004/FR-004, ADR-012): ActionEconomy.end_of_round() — which
## resets budget_remaining back to MAX_BUDGET (7) and clears is_spent() for
## EVERY combatant this session holds — is now invoked ONLY when this
## round's own outcome is still undecided (_outcome == "", covering BOTH a
## natural full-budget exhaustion AND the no-progress backstop's forced
## per-round DRAW, neither of which is ever reported as 'won'/'lost' by
## outcome() — see that method's own doc). This is exactly the multi-round
## steel thread's continuation contract: MainScene.gd's _on_round_over()
## calls finish() once a round concludes, and — only on an undecided
## outcome — increments ROUND_NUMBER and calls rewire_session() to begin the
## next round, which itself grants a fresh per-round budget via
## RunRoundUseCase.begin_round()'s own start_of_round() calls (CR-001 AC-2);
## finish()'s reset here is the FIRST of those two (belt-and-braces) resets,
## observable immediately after finish() returns, before any continuation
## logic runs. A DECIDED ('won'/'lost') outcome, by contrast, is a terminal
## state — the encounter is over, no further round will ever be begun for
## these combatants, so there is no reason to reset their budgets at all.
func finish() -> Dictionary:
	if _outcome == "":
		for entry in _entries:
			entry["action_economy"].end_of_round()

	var this_round_history: Array = []
	for hist_entry in _round_history_port.get_history():
		if hist_entry.get("round", -1) == _round_number:
			this_round_history.append(hist_entry)

	var result_outcome: String = "DRAW" if _forced_draw else _outcome
	var encounter_outcome: String = "" if _forced_draw else _outcome

	return {
		"round_number":      _round_number,
		"outcome":           result_outcome,
		"history":           this_round_history,
		"encounter_outcome": encounter_outcome
	}


# ── Autonomous whole-round API (used only by RunRoundUseCase.execute()) ────

## run_autonomous_to_completion() -> void — replays the AC-4 interleaved
## cycle algorithm to completion in one call, auto-selecting a target for
## EVERY combatant (AI for Enemy via AIDecisionPort, "first living target"
## for Player — mirroring the pre-FEAT-110 execute() body byte-for-byte,
## including the FEAT-097/CWE-835/FIND-095 stalled-cycle backstop). Marks
## the round over unconditionally when it returns. NOT used by the
## interactive stepwise API above — the human-paced path never auto-selects
## a Player target.
func run_autonomous_to_completion() -> void:
	var decided_outcome: String = ""
	var cycle_index: int = 0
	var force_draw_no_progress: bool = false

	while decided_outcome == "" and _has_living_unspent(_entries):
		var any_action_resolved_this_cycle: bool = false

		for entry in _entries:
			if decided_outcome != "":
				break

			var combatant: Dictionary = entry["combatant"]
			var action_economy = entry["action_economy"]

			# Dead combatants are skipped — no cycle slot consumed (AC-4)
			if combatant.get("hp_current", 0) <= 0:
				continue

			# Spent combatants are skipped — no cycle slot consumed (AC-4)
			if action_economy.is_spent():
				continue

			action_economy.start_of_turn()

			var is_enemy: bool = combatant.get("_is_enemy", false)
			var target_pool: Array = _party if is_enemy else _enemies

			var target: Dictionary = {}
			var action_name: String = ""

			if is_enemy:
				var ai_decision: Dictionary = _ai_decision_port.decide_action(combatant, target_pool)
				action_name = ai_decision.get("action_type", "")
				target      = ai_decision.get("target", {})
			else:
				for t in target_pool:
					if t.get("hp_current", 0) > 0:
						target = t
						break
				if not target.is_empty():
					action_name = "Strike"

			# No living target found — skip this combatant for the cycle.
			if action_name == "" or target.is_empty():
				continue

			var resolve_result: Dictionary = _resolve_action_use_case.resolve(
				combatant, action_economy, target, action_name, _round_number, cycle_index
			)

			if not resolve_result.get("resolved", false):
				continue

			any_action_resolved_this_cycle = true

			var outcome_check: String = _determine_outcome_use_case.classify(_party, _enemies)
			if outcome_check == "won" or outcome_check == "lost":
				decided_outcome = outcome_check
				_event_sink_port.emit(_determine_outcome_use_case.build_event(_round_number, decided_outcome))
				break

		if decided_outcome == "" and not any_action_resolved_this_cycle:
			push_warning("run_round: a full cycle resolved zero actions; forcing a safe DRAW to prevent an unbounded loop")
			force_draw_no_progress = true
			break

		cycle_index += 1

	_outcome      = decided_outcome
	_forced_draw  = force_draw_no_progress
	_round_over   = true
	_cursor       = -1


# ── Internal helpers ────────────────────────────────────────────────────────

## _after_action_resolved() -> Dictionary — shared tail used by both
## advance_ai_turn() (after a resolved AI action) and end_current_turn()
## (regardless of whether an action was spent): consults
## DetermineOutcomeUseCase; if decided, emits EncounterResultEvent and ends
## the round; otherwise advances the cursor to the next living, un-Spent
## actor (emitting TurnAdvancedEvent).
func _after_action_resolved() -> Dictionary:
	var decided: String = _determine_outcome_use_case.classify(_party, _enemies)
	if decided == "won" or decided == "lost":
		_outcome    = decided
		_round_over = true
		_cursor     = -1
		_event_sink_port.emit(_determine_outcome_use_case.build_event(_round_number, decided))
		return {"ok": true, "round_over": true, "outcome": decided}

	_advance_cursor()
	return {"ok": true, "round_over": _round_over}


## _advance_cursor() -> void — moves the cursor forward to the next living,
## un-Spent entry (wrapping past the end of _entries increments
## _cycle_index, mirroring one AC-4 "cycle pass"). Emits a
## RoundEvents.TurnAdvancedEvent for the new current actor. When no living,
## un-Spent entry remains, marks the round over instead.
##
## FEAT-005 (US-003 / FR-003, ADR-011): before moving the cursor, records
## whether the JUST-ENDED actor's turn made any progress (its
## ActionEconomy.get_remaining() dropped below the _turn_start_budget
## snapshot taken when the cursor landed on it — see that field's doc). When
## the cursor is about to wrap back around to complete a full cycle pass
## AND no actor's turn in that just-completed pass made any progress, this
## is the SAME "a full cycle pass resolved zero actions" condition
## run_autonomous_to_completion() already guards against — ported onto this
## interactive path so a genuinely stalled interactive round (e.g. an
## all-free-passing turn order, WAIT never reached) resolves to a safe DRAW
## here too, rather than relying on presentation/turn_controller.gd's
## 1000-turn guard ever being what actually terminates the round (this
## steel thread's exit criterion: hitting that guard is a bug signal, never
## a designed code path).
##
## ADR-101/ADR-102/FEAT-004: together with the initial cursor assignment in
## _init() above, this is the SINGLE authoritative call site for
## ActionEconomy.start_of_turn() — for BOTH player and AI actors, with no
## distinction between the two. Every cursor movement (whether driven by a
## player's end_current_turn() or an AI's advance_ai_turn()) funnels through
## this one method, so start_of_turn() is invoked here EXACTLY ONCE per
## cursor advance, immediately after `_cursor` is updated to the new actor
## and before the TurnAdvancedEvent is emitted — replacing the previous,
## redundant, enemy-only call that used to live directly inside
## advance_ai_turn() (which never fired for a Player actor at all, the
## P0-1 movement-lockout defect this feature closes). start_of_turn() only
## clears the two per-turn flags (movement_used_this_turn/
## action_used_this_turn) and is documented as idempotent/budget-neutral
## (ADR-102) — it never mutates actions_remaining or is_spent.
func _advance_cursor() -> void:
	# FEAT-005: did the actor whose turn just ended make any progress?
	if _cursor != -1:
		var ending_budget: int = _entries[_cursor]["action_economy"].get_remaining()
		if ending_budget < _turn_start_budget:
			_interactive_cycle_progress = true

	var next_index: int = _find_next_actionable_index(_cursor)
	if next_index == -1:
		_cursor     = -1
		_round_over = true
		return

	if next_index <= _cursor:
		# A full cycle pass just completed — FEAT-005 no-progress backstop.
		if not _interactive_cycle_progress:
			_force_no_progress_draw()
			return
		_interactive_cycle_progress = false
		_cycle_index += 1
	_cursor = next_index

	_entries[_cursor]["action_economy"].start_of_turn()
	_turn_start_budget = _entries[_cursor]["action_economy"].get_remaining()

	var combatant: Dictionary = _entries[_cursor]["combatant"]
	_event_sink_port.emit(RoundEventsClass.TurnAdvancedEvent.new(
		_round_number,
		combatant.get("name", ""),
		combatant.get("combatant_id", "")
	))


## _force_no_progress_draw() -> void — FEAT-005 (US-003 / FR-003, ADR-011):
## the interactive-path equivalent of run_autonomous_to_completion()'s
## force_draw_no_progress branch — forces the round over with a DRAW,
## reported through the SAME _forced_draw / finish() contract the autonomous
## path already uses (outcome() itself still never reports 'DRAW' directly —
## only finish()'s Dictionary "outcome" key does).
func _force_no_progress_draw() -> void:
	push_warning(
		"RoundSession: a full interactive cycle resolved zero actions; forcing a safe DRAW to prevent an unbounded loop"
	)
	_forced_draw = true
	_round_over  = true
	_cursor      = -1


func _find_first_actionable_index() -> int:
	for i in range(_entries.size()):
		if _is_actionable(_entries[i]):
			return i
	return -1


func _find_next_actionable_index(from_index: int) -> int:
	var n: int = _entries.size()
	if n == 0:
		return -1
	for step in range(1, n + 1):
		var idx: int = (from_index + step) % n
		if _is_actionable(_entries[idx]):
			return idx
	return -1


func _is_actionable(entry: Dictionary) -> bool:
	var combatant: Dictionary = entry["combatant"]
	if combatant.get("hp_current", 0) <= 0:
		return false
	return not entry["action_economy"].is_spent()


## _has_living_unspent(entries) -> bool — true if at least one living
## combatant in `entries` has not yet reached is_spent()==true. Identical
## contract to RunRoundUseCase's pre-FEAT-110 private helper of the same
## name, relocated here for run_autonomous_to_completion()'s exclusive use.
func _has_living_unspent(entries: Array) -> bool:
	for entry in entries:
		var combatant: Dictionary = entry["combatant"]
		if combatant.get("hp_current", 0) <= 0:
			continue
		if not entry["action_economy"].is_spent():
			return true
	return false
