## presentation/round_flow_controller.gd — RoundFlowController
## (FEAT-006 / US-006 / FR-007).
##
## Presentation layer (Clean Architecture, ADR-001): a primary/driving
## controller that owns turn-order / round-lifecycle handling — obtaining a
## fresh RoundSession for a round via the injected RunRoundUseCase, wiring it
## to the injected TurnController-shaped collaborator (`set_session()`), and
## reacting to that collaborator's OWN `round_over` signal to decide whether
## the encounter continues into another round or has concluded. This is the
## SAME algorithm MainScene.gd's `rewire_session()` / `_on_round_over()` pair
## already implements (FEAT-006 / US-004/FR-004, ADR-012) — this class is the
## extracted, independently-testable, fakeable form of that same round-flow
## contract (this feature's own test_criteria: "given a fake round_session/
## run_round_use_case").
##
## `round_over()` (below) is this steel thread's own exit-point signal —
## emitted exactly once per resolved round, once `run_round_use_case`'s
## RoundSession has been `finish()`ed and its outcome read. MainScene's ONLY
## responsibility on this signal is UI cleanup (never game-state mutation —
## this feature's own test_criteria, verified by a static source scan in
## tests/gut/test_round_flow_controller.gd).
##
## Why MainScene.gd's OWN `rewire_session()`/`_on_round_over()` methods are
## NOT deleted/replaced by this feature (an intentional, documented departure
## from this steel thread's usual "extract verbatim, delete the original"
## discipline — e.g. presentation/combine_targeting_session.gd's/
## combine_queue_build_session.gd's own file-level docs): a PRE-EXISTING,
## already-committed regression suite
## (tests/integration/test_multi_round_loop.gd's
## `test_rewire_session_is_the_single_reusable_composition_root_rewiring_method`)
## pins, via static source inspection, that MainScene.gd itself must contain
## EXACTLY ONE literal `run_round_use_case.begin_round(` call site (inside its
## OWN `rewire_session()`) and that `_on_round_over()` must itself call
## `rewire_session()`. Deleting that call site from MainScene.gd (moving it
## into this file instead) would fail that pinned assertion — and, far more
## importantly, wiring THIS class's own `rewire_session()` to the SAME live,
## production `run_round_use_case`/`turn_controller` MainScene already drives
## would call `RunRoundUseCase.begin_round()` a SECOND, independent time per
## round, silently doubling every RNG draw/AI decision the shared
## `random_port` stream produces and breaking every seed-determinism/
## pinned-round-count regression across this project's e2e suite. This
## class's `rewire_session()`/`_on_turn_controller_round_over()` pair is
## therefore exercised for real ONLY by this file's own dedicated GUT
## suite (tests/gut/test_round_flow_controller.gd), against a FAKE
## run_round_use_case/turn_controller — proving the round-flow ALGORITHM in
## isolation (this feature's own explicit test_criteria wording) — while
## MainScene's live composition-root wiring keeps driving the real encounter
## through its own pinned, byte-for-byte-unchanged `rewire_session()`/
## `_on_round_over()`. MainScene.gd nonetheless DOES construct and
## `setup(deps)` a real instance of this class (wired against the real
## `run_round_use_case`, and against `party`/`enemies` sourced from
## CombatSessionFactory.build()'s own output — FEAT-003 — via `party_fn`/
## `enemies_fn`), and its own (unmodified) `_on_round_over()` calls this
## instance's additive `notify_round_concluded()` helper (see below) at the
## very end of its own existing work — a pure signal relay carrying NO
## `run_round_use_case.begin_round(`/`set_token_reposition_fn` call of its
## own, so the pinned "no duplicated wiring code" assertions above remain
## satisfied — so `round_over()` genuinely fires once per real, live round
## conclusion too, for whatever UI-cleanup-only subscriber MainScene wires to
## it (this feature's own test_criteria #3).
##
## Depends only on: the injected `run_round_use_case` (application layer,
## core/application/run_round_use_case.gd's RunRoundUseCase, duck-typed
## `begin_round(round_number, party, enemies) -> RoundSession`) and the
## injected `turn_controller`-shaped collaborator (duck-typed
## `round_over` signal + `set_session(round_session, end_turn_control,
## strike_action_control, verb_bar_view) -> void` coroutine — the EXACT
## surface presentation/turn_controller.gd's real TurnController already
## exposes). Zero direct SQL/HTTP/framework concerns; the only Godot-specific
## surface touched is the duck-typed `end_turn_control`/`verb_bar_view`
## collaborators passed straight through to `set_session()`, mirroring every
## other extracted controller in this steel thread.
##
## API contract (design notes' api_contracts #6; ADR-005's signal-based
## error vocabulary — GDScript has no exceptions):
##   setup(deps: Dictionary) -> void
##     Wires this controller's collaborators. Must be called exactly once,
##     before rewire_session()/notify_round_concluded(). `deps` keys:
##       "run_round_use_case" — object exposing begin_round(round_number,
##           party, enemies) -> RoundSession. REQUIRED for rewire_session()
##           to do anything meaningful.
##       "turn_controller"    — OPTIONAL object exposing a `round_over`
##           signal and a `set_session(...)` coroutine (e.g.
##           presentation/turn_controller.gd's real TurnController, or a
##           fake in tests). When present, this controller connects its OWN
##           `_on_turn_controller_round_over()` to its `round_over` signal
##           EXACTLY ONCE (a disconnect-if-connected guard immediately
##           followed by a fresh connect, mirroring MainScene.gd's own
##           established RISK-010 idiom) — see this file's own doc above for
##           why MainScene's live wiring deliberately omits this key.
##       "end_turn_control" / "verb_bar_view" — OPTIONAL, forwarded verbatim
##           to `turn_controller.set_session()`'s own 2nd/4th arguments.
##       "party_fn" / "enemies_fn" — OPTIONAL Callables returning
##           Array[Combatant] each, read FRESH on every rewire_session()
##           call (never a snapshot) — mirrors every other extracted
##           controller's "closures read state fresh off the composition
##           root" convention. Default to an empty Array when omitted/invalid.
##       "round_number" — OPTIONAL int, default 1 — the starting round number
##           (mirrors MainScene.ROUND_NUMBER's own "starts at 1" contract).
##
##   rewire_session() -> void (coroutine)
##     Obtains a fresh RoundSession for the CURRENT round number via
##     `run_round_use_case.begin_round(...)`, hands it to
##     `turn_controller.set_session(...)` (awaited, when a turn_controller was
##     injected), then records its outcome. Mirrors MainScene.gd's own
##     `rewire_session()` algorithm exactly (see that method's own doc).
##     FAILURE CONTRACT (this feature's own test_criteria): calling this
##     BEFORE setup() is a programmer error — `assert(false, ...)` fires in a
##     debug/test build (this engine/test-runner combination aborts the
##     current function immediately, mirroring this project's established
##     assert(false, message); push_error(message) contract-violation
##     convention — core/domain/effects_applier.gd, core/application/
##     reaction_window.gd, presentation/action_controller.gd) and
##     `push_error(...)` is logged as defense-in-depth (release builds compile
##     assert() out entirely) — either way this method becomes a no-op past
##     that guard: no RoundSession is created, nothing is signaled.
##
## Signal:
##   round_over() — this steel thread's own exit-point signal (design notes'
##     api_contracts #6). Emitted exactly once per resolved round: once by
##     `_on_turn_controller_round_over()` whenever the injected
##     `turn_controller`'s OWN `round_over` fires (isolated GUT coverage,
##     this file's own suite), and once by `notify_round_concluded()` (the
##     safe, additive, non-duplicating relay MainScene's real `_on_round_over()`
##     calls for live parity — see this file's own doc above). MainScene's
##     only responsibility on this signal is UI cleanup — never game-state
##     mutation (test_criteria #3).
##
## Query helpers (exposed so callers/GUT tests can verify state directly,
## mirroring presentation/combine_targeting_session.gd's own "constructed
## here, exposed for verification" precedent):
##   get_round_session()      — the most recently obtained RoundSession (or
##                               null before any rewire_session() call).
##   get_round_number() -> int — the round number this controller is
##                               CURRENTLY on (mirrors MainScene.ROUND_NUMBER).
##   get_outcome() -> String   — '' | 'won' | 'lost'; the most recently
##                               observed RoundSession.outcome().
##   is_setup() -> bool        — true once setup() has been called.

class_name RoundFlowController
extends RefCounted

signal round_over()

var _is_setup: bool = false
var _run_round_use_case = null
var _turn_controller = null
var _end_turn_control = null
var _verb_bar_view = null
var _party_fn: Callable = Callable()
var _enemies_fn: Callable = Callable()
var _round_number: int = 1
var _round_session = null
var _outcome: String = ""


## setup(deps) -> void — wires this controller's collaborators. See the
## file-level doc above for `deps`'s full key set. Must be called exactly
## once, before rewire_session()/notify_round_concluded().
func setup(deps: Dictionary) -> void:
	_run_round_use_case = deps.get("run_round_use_case")
	_turn_controller = deps.get("turn_controller")
	_end_turn_control = deps.get("end_turn_control")
	_verb_bar_view = deps.get("verb_bar_view")
	_party_fn = deps.get("party_fn", Callable())
	_enemies_fn = deps.get("enemies_fn", Callable())
	_round_number = deps.get("round_number", 1)
	_is_setup = true

	if _turn_controller != null:
		if _turn_controller.round_over.is_connected(_on_turn_controller_round_over):
			_turn_controller.round_over.disconnect(_on_turn_controller_round_over)
		_turn_controller.round_over.connect(_on_turn_controller_round_over)


## is_setup() -> bool — true once setup() has been called.
func is_setup() -> bool:
	return _is_setup


## get_round_session() — the most recently obtained RoundSession (or null
## before any rewire_session() call).
func get_round_session():
	return _round_session


## get_round_number() -> int — the round number this controller is
## CURRENTLY on.
func get_round_number() -> int:
	return _round_number


## get_outcome() -> String — '' | 'won' | 'lost'; the most recently observed
## RoundSession.outcome().
func get_outcome() -> String:
	return _outcome


## rewire_session() -> void — see file-level doc's full contract. Calling
## this before setup() is a programmer error: assert(false, ...) fires (debug
## builds) / push_error(...) is logged (release, ADR-005), and this method
## becomes a no-op -- no RoundSession is created.
func rewire_session() -> void:
	if not _is_setup:
		var message: String = "RoundFlowController.rewire_session() called before setup() -- programmer error (ADR-005)"
		assert(false, message)
		push_error(message)
		return

	var party: Array = _party_fn.call() if _party_fn.is_valid() else []
	var enemies: Array = _enemies_fn.call() if _enemies_fn.is_valid() else []
	_round_session = _run_round_use_case.begin_round(_round_number, party, enemies)

	if _turn_controller != null:
		await _turn_controller.set_session(_round_session, _end_turn_control, null, _verb_bar_view)

	if _round_session != null:
		_outcome = _round_session.outcome()


## notify_round_concluded() -> void — the safe, additive relay MainScene's
## OWN (unmodified) `_on_round_over()` calls at the very end of its existing
## work, so `round_over()` fires for real once per live round conclusion too
## (see this file's own doc above for why MainScene never calls
## rewire_session() itself for its real, production encounter). A PURE
## signal relay -- never calls begin_round()/mutates `_round_session`/
## `_round_number` of its own accord, so callers may invoke it freely without
## risking a second, parallel round-flow. Calling this before setup() is
## likewise a programmer error (ADR-005), mirroring rewire_session()'s own
## guard.
func notify_round_concluded() -> void:
	if not _is_setup:
		var message: String = "RoundFlowController.notify_round_concluded() called before setup() -- programmer error (ADR-005)"
		assert(false, message)
		push_error(message)
		return
	round_over.emit()


## _on_turn_controller_round_over() -> void — the internal signal handler
## this controller owns (this feature's own scope: "internal signal
## handlers"), connected to the injected `turn_controller.round_over` in
## setup() above. Mirrors MainScene.gd's own `_on_round_over()` algorithm
## exactly: finish()es the held RoundSession, reads its outcome, and -- ONLY
## when that outcome is still undecided ('') -- increments the round number
## and continues into the next round via THIS controller's OWN
## rewire_session() (never a second/duplicated begin_round() call site). A
## decided ('won'/'lost') outcome is a terminal state: no further round
## begins. Emits round_over() exactly once per resolved round, regardless of
## which branch was taken.
func _on_turn_controller_round_over() -> void:
	if _round_session == null:
		round_over.emit()
		return

	_round_session.finish()
	_outcome = _round_session.outcome()

	if _outcome == "":
		_round_number += 1
		await rewire_session()

	round_over.emit()
