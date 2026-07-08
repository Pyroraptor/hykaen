## presentation/turn_controller.gd — TurnController (FEAT-110 / US-010/US-011)
##
## Presentation layer (Clean Architecture): a thin turn-driving Node — NOT an
## Application-layer type. The interactive stepwise API itself lives on
## core/application/round_session.gd's RoundSession (ADR-007); this node
## only decides WHEN to call it:
##   - On an Enemy current_actor(), TurnController auto-drives the turn by
##     calling RoundSession.advance_ai_turn() (US-011) — enemy and player
##     turns funnel through the SAME resolve_action_use_case pipeline the
##     session owns; this node never resolves an action itself.
##   - On a player current_actor(), TurnController enables EndTurnControl
##     (US-010) so the human can act (via StrikeActionControl, unchanged)
##     and/or end their turn.
##   - While it is auto-driving (i.e. any Enemy turn is being resolved),
##     TurnController disables player input (US-011: "the player watches the
##     enemy AI take its automated turn" — no player action must be able to
##     interleave with an in-flight AI turn). EndTurnControl already
##     re-derives its own enabled state from the RoundSession on every
##     configure() call (FEAT-110); the injected StrikeActionControl has no
##     such derivable state of its own (it needs live actor/target data this
##     node does not own), so TurnController disables it the same way its
##     own configure() API already expresses "no selectable targets" — by
##     clearing it via configure() with an empty candidate list (ADR-002: no
##     new StrikeActionControl API is introduced for this). Re-enabling
##     StrikeActionControl with the next player's real targets remains the
##     composition root's responsibility (via active_actor_changed), exactly
##     as before this feature.
##   - FEAT-009 (US-009 / FR-004): an OPTIONAL, injected VerbBarView
##     (presentation/verb_bar_view.gd) is refreshed (refresh_availability())
##     TWICE per _drive() call — once immediately (whichever actor,
##     Player or Enemy, is current at that moment) and once more after the
##     Enemy-turn auto-drive loop settles (on the next Player, or the round
##     being over). This proves the SAME live ActionEconomy.can_take_action()/
##     can_take_movement_action() queries MainScene.gd's Strike/Stride/Step
##     availability closures read from (ADR-003) are safe to invoke whether
##     the round's current actor is Player- or AI-controlled — the steel
##     thread's exit criterion (Strike/Stride visibly greying out) must never
##     throw or leave a stale gate mid-AI-drive. Purely a refresh — TurnController
##     never re-derives availability itself, it only re-queries the SAME
##     injected registry $VerbBarView already holds (ADR-002/CR-001: no
##     parallel gating logic). A no-op wherever no VerbBarView was injected
##     (every pre-existing caller/test double), exactly like
##     `_strike_action_control` above.
##   - FEAT-207 (US-013 / FR-015): configure_reactions()/resolve_reaction()
##     (below) are the presentation-layer integration point for the
##     player-facing blocking reaction pop-up (scenes/ui/reaction_prompt_ui.gd
##     / presentation/player_reaction_chooser.gd). resolve_reaction() drives
##     an injected core/application/reaction_window.gd ReactionWindow via its
##     documented split open()/resume() calls (never the
##     open_and_resolve()/open_and_resolve_attack() convenience methods,
##     which call a chooser SYNCHRONOUSLY and are for headless/AI choosers
##     only — see reaction_window.gd's own doc), `await`ing the injected
##     ReactionChooserPort's choose() directly so the caller genuinely
##     suspends until the player answers, with no auto-timeout. This is
##     purely an OPTIONAL capability of this node — nothing in _drive()
##     itself calls it — exactly like `_verb_bar_view` above, so every
##     pre-existing caller/test double that never calls
##     configure_reactions() sees no behavior change whatsoever.
##
## TurnController never mutates domain state directly, never constructs a
## RoundSession itself, and never reaches into Infrastructure — it is handed
## a RoundSession via set_session() by the composition root (MainScene.gd),
## exactly as the other Presentation nodes are handed their collaborators.

class_name TurnController
extends Node

## Defensive guard against a stalled RoundSession looping forever if
## advance_ai_turn() somehow never leaves the Enemy side (mirrors the
## FEAT-097/CWE-835 backstop philosophy used elsewhere in this codebase).
const _MAX_AI_TURNS_PER_DRIVE: int = 1000

## active_actor_changed(combatant) — emitted whenever _drive() settles on a
## new (player) current actor. Presentation nodes MAY listen for richer UX
## (e.g. re-configuring StrikeActionControl for the new active combatant);
## no subscriber is required for this node to work.
signal active_actor_changed(combatant: Dictionary)

## round_over() — emitted once the held RoundSession reports is_round_over().
signal round_over()

## The injected, REUSED RoundSession (core/application/round_session.gd) —
## TurnController never constructs one itself.
var _round_session = null

## The injected EndTurnControl (presentation/end_turn_control.gd) this
## driver keeps configured with the current RoundSession.
var _end_turn_control = null

## The injected StrikeActionControl (presentation/strike_action_control.gd)
## this driver disables (US-011) whenever it is auto-driving an Enemy turn.
## Optional — a caller that never passes one (e.g. existing FEAT-110 tests)
## sees no behavior change.
var _strike_action_control = null

## The injected VerbBarView (presentation/verb_bar_view.gd, FEAT-009 / US-009
## / FR-004) this driver refreshes (refresh_availability()) across every
## _drive() call — see file-level FEAT-009 doc above. Optional — a caller
## that never passes one (e.g. every pre-existing FEAT-110/111 test) sees no
## behavior change.
var _verb_bar_view = null

## The injected ReactionWindow (core/application/reaction_window.gd,
## FEAT-207 / US-013 / FR-015) resolve_reaction() below drives via its
## documented split open()/resume() calls. Optional — a caller that never
## calls configure_reactions() (every pre-existing caller/test double) sees
## no behavior change; resolve_reaction() itself is simply never invoked by
## anything in that case.
var _reaction_window = null

## The injected ReactionChooserPort (core/application/ports/
## reaction_chooser_port.gd) resolve_reaction() `await`s — in production,
## presentation/player_reaction_chooser.gd's PlayerReactionChooser (a
## blocking modal pop-up); in a test/headless context, any chooser
## implementing the SAME contract (e.g. infrastructure/
## auto_reaction_chooser.gd's AutoReactionChooser).
var _reaction_chooser = null


## configure_reactions(reaction_window, reaction_chooser) -> void — FEAT-207
## (US-013 / FR-015): injects the collaborators resolve_reaction() drives.
## Both are OPTIONAL/duck-typed — TurnController never preloads either
## concrete class, only calls the documented open()/resume()/choose()
## methods on whatever is injected (ADR-002 injection, mirrors
## set_session()'s own discipline). Safe to call any number of times (e.g.
## once per encounter, mirroring set_session()'s repeated-call contract).
func configure_reactions(reaction_window, reaction_chooser) -> void:
	_reaction_window = reaction_window
	_reaction_chooser = reaction_chooser


## resolve_reaction(trigger, resolved_by) -> Dictionary — FEAT-207 (US-013 /
## FR-015): the live integration point for the player-facing blocking
## reaction pop-up. Opens `trigger` on the injected ReactionWindow (see
## core/application/reaction_window.gd's open() doc for `trigger`'s shape),
## and — ONLY when a window actually opened (the reactor was not already
## Spent) — `await`s the injected ReactionChooserPort's choose() with the
## window's own legal_reactions before resume()ing with whatever it
## answers. This is a genuine coroutine: the caller MUST `await` it, and
## doing so genuinely suspends until the player (or whichever chooser was
## injected) answers — no auto-timeout, no engine-thread block (see
## presentation/player_reaction_chooser.gd's file-level doc for why this is
## safe). A no-op returning {"ok": false, "error": "ERR_NO_REACTION_WINDOW"}
## when configure_reactions() was never called, so this method can be
## called speculatively without every caller needing its own null-guard.
func resolve_reaction(trigger: Dictionary, resolved_by: String = "player") -> Dictionary:
	if _reaction_window == null:
		return {"ok": false, "error": "ERR_NO_REACTION_WINDOW"}

	var opened: Dictionary = _reaction_window.open(trigger)
	if not opened.get("opened", false):
		return {
			"ok": true,
			"window_id": "",
			"choice": "none",
			"opened": false,
			"reason": opened.get("reason", ""),
		}

	var legal_reactions: Array = opened.get("legal_reactions", [])
	var context: Dictionary = trigger.get("attack_context", {})
	var choice: String = await _reaction_chooser.choose(legal_reactions, context)

	var result: Dictionary = _reaction_window.resume(opened["window_id"], choice, resolved_by)
	result["opened"] = true
	return result


## set_session(round_session, end_turn_control, strike_action_control,
##             verb_bar_view) -> void — injects the current round's
## RoundSession, the EndTurnControl this driver manages, and (optionally,
## US-011) the StrikeActionControl this driver disables while auto-driving
## Enemy turns, and (optionally, FEAT-009 / US-009) the VerbBarView this
## driver refreshes across the drive. Immediately drives any leading Enemy
## turns and refreshes end_turn_control's enabled state (and
## strike_action_control's disabled state / verb_bar_view's availability)
## for whatever actor the round now sits on. Safe to call again for a new
## round (e.g. once RunRoundUseCase.begin_round() is called again), with no
## leaked state from the prior RoundSession.
##
## FEAT-006 (US-004/FR-004, ADR-012): this repeated-call contract is exactly
## what powers automatic multi-round continuation — MainScene.gd's
## rewire_session() (its ONE composition-root rewiring method, used both at
## startup and again every time a round concludes without a decided outcome)
## calls this SAME set_session() with a brand-new RoundSession for the next
## round number. _MAX_AI_TURNS_PER_DRIVE (below) is a per-_drive()-call
## guard, so each round this method is (re)invoked for gets its own fresh
## 1000-Enemy-turn allowance — a multi-round encounter is therefore never
## penalized across rounds by a single shared counter, and this guard
## tripping is still always a bug signal (a genuinely stalled single round),
## never a designed code path, exactly as the file-level doc above states.
## FEAT-003 (US-002 / FR-002, ADR-003): now a coroutine — see _drive()'s own
## FEAT-003 doc below. `await`ing here (rather than a fire-and-forget call)
## preserves this method's pre-existing contract that the injected
## end_turn_control/verb_bar_view are fully refreshed for the round's
## settled actor by the time set_session() returns to its caller. For every
## caller that never injects a reaction resolver on the held RoundSession
## (every pre-existing caller/test double, and MainScene.gd as of this
## feature), _drive()'s await never actually suspends (see
## RoundSession.advance_ai_turn()'s own doc), so set_session() still
## completes synchronously within the same call, byte-for-byte identical to
## before this feature (NFR-004).
func set_session(round_session, end_turn_control = null, strike_action_control = null, verb_bar_view = null) -> void:
	_round_session = round_session
	if end_turn_control != null:
		_end_turn_control = end_turn_control
	if strike_action_control != null:
		_strike_action_control = strike_action_control
	if verb_bar_view != null:
		_verb_bar_view = verb_bar_view
	await _drive()


## on_end_turn_pressed() -> Dictionary — forwards to the held RoundSession's
## end_current_turn() (US-010: EndTurnControl always available, whether or
## not an action was spent this turn), then auto-drives any following Enemy
## turns before yielding back to the player.
func on_end_turn_pressed() -> Dictionary:
	if _round_session == null:
		return {"ok": false}

	var result: Dictionary = _round_session.end_current_turn()
	# FEAT-003: _drive() is now a coroutine (see its doc below) — awaited
	# here so this method's returned `result` is only handed back once any
	# following auto-driven Enemy turn(s) (and any reaction they await) have
	# fully settled, matching set_session()'s identical await discipline.
	await _drive()
	return result


# ── Internal helpers ─────────────────────────────────────────────────────

## _drive() -> void — auto-resolves consecutive Enemy turns via
## RoundSession.advance_ai_turn() until either a player's turn comes up or
## the round is over, then refreshes end_turn_control's enabled state and
## broadcasts the settled actor.
##
## strike_action_control (US-011) is disabled BEFORE the auto-drive loop
## runs — clearing any stale/leaked configuration from a prior turn — so no
## player Strike input can ever interleave with an Enemy turn this call is
## about to auto-resolve. It is intentionally left disabled once the loop
## settles (even on a player actor): re-enabling it with that player's real,
## live targets is the composition root's job (unchanged by this feature),
## exactly as StrikeActionControl.configure() has always been invoked
## per-turn rather than owned by this node.
## FEAT-003 (US-002 / FR-002, ADR-003, NFR-004): _drive()'s auto-drive loop
## below now `await`s RoundSession.advance_ai_turn() on every iteration
## (that method is itself a coroutine as of this feature — see its own
## doc). This is deliberately the single point in this loop that ever
## awaits: the loop reads `_round_session.current_actor()`/
## `is_round_over()` again only AFTER advance_ai_turn() has fully resolved
## (including any reaction it awaited), so a slow/suspending resolver can
## never cause this loop to double-advance the turn cursor or race ahead of
## a still-in-flight reaction — the very next loop condition check only
## observes RoundSession state exactly as advance_ai_turn() left it once its
## own await chain (if any) completed. For every existing caller (no
## resolver injected on the held RoundSession), advance_ai_turn()'s own
## await never actually suspends, so this loop's timing is byte-for-byte
## identical to the pre-FEAT-003 synchronous version (NFR-004) — see
## tests/gut/test_async_reaction_propagation.gd.
func _drive() -> void:
	if _round_session == null:
		return

	_disable_strike_action_control()

	# FEAT-009 (US-009 / FR-004): refresh BEFORE the auto-drive loop below —
	# whichever actor (Player or Enemy) is current_actor() at THIS moment
	# (e.g. an Enemy the cursor already sits on when set_session() is
	# re-invoked after end_current_turn(), see MainScene.gd's
	# _on_end_turn_control_turn_ended()) — proving the injected VerbBarView's
	# is_available() queries (MainScene.gd's Strike/Stride/Step closures,
	# reading ActionEconomy.can_take_action()/can_take_movement_action()) are
	# safe to invoke for an AI-controlled actor's turn, not only a Player's.
	_refresh_verb_bar_availability()

	var guard: int = 0
	while not _round_session.is_round_over() and guard < _MAX_AI_TURNS_PER_DRIVE:
		var actor: Dictionary = _round_session.current_actor()
		if actor.is_empty() or not actor.get("_is_enemy", false):
			break
		await _round_session.advance_ai_turn()
		guard += 1

	if _end_turn_control != null:
		_end_turn_control.configure(_round_session)

	# FEAT-009: refresh AGAIN once the auto-drive loop above has settled (the
	# next Player, or the round being over) — so Strike/Stride/Step never
	# render a stale, pre-drive availability once control yields back.
	_refresh_verb_bar_availability()

	if _round_session.is_round_over():
		round_over.emit()
	else:
		active_actor_changed.emit(_round_session.current_actor())


## _disable_strike_action_control() -> void — clears the injected
## StrikeActionControl (no acting combatant, no selectable targets), which
## reuses StrikeActionControl's existing configure() contract to express
## "disabled" (zero rendered buttons) rather than introducing a new
## enable/disable API on that control (ADR-002 / CR-001 guardrail: no
## duplicate/parallel control-state surface).
func _disable_strike_action_control() -> void:
	if _strike_action_control != null:
		_strike_action_control.configure({}, null, null, [])


## _refresh_verb_bar_availability() -> void — FEAT-009 (US-009 / FR-004):
## re-queries the injected VerbBarView's registry (via
## VerbBarView.refresh_availability(), the SAME mechanism MainScene.gd's own
## active_actor_changed/round_over handlers already rely on) WITHOUT
## rebuilding its button set or introducing any new gating logic of
## TurnController's own (ADR-002/CR-001) — a pure pass-through. A no-op when
## no VerbBarView was injected (see `_verb_bar_view`'s doc above).
func _refresh_verb_bar_availability() -> void:
	if _verb_bar_view != null:
		_verb_bar_view.refresh_availability()
