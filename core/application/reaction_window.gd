## core/application/reaction_window.gd — ReactionWindow (FEAT-009 / US-009 /
## FR-005, ADR-014)
##
## Application layer (Clean Architecture): the pausable, resumable
## reaction-window abstraction that connects live Strike resolution
## (core/rules/resolution.gd) to the eventual reaction pop-up, modeled on
## core/application/round_session.gd's RoundSession stepwise/resumable
## pattern (ADR-007) — a first-class object a caller can drive one step at
## a time (open() then, later, resume()) instead of blocking the engine
## thread waiting for a decision inline.
##
## Depends ONLY on core/rules/resolution.gd's Resolution class (its new,
## pure, static eligibility predicates — is_dodge_eligible()/
## is_steel_eligible()/is_parry_eligible()/is_block_eligible(), see that
## file's FEAT-009 additions — so this class never re-derives/duplicates
## those rules) and on the injected EventSinkPort (ADR-003's existing
## observability surface, reused rather than a new port). Never imports an
## adapter/infrastructure/presentation type.
##
## `trigger` (the Dictionary passed to open()) shape:
##   "trigger_type"            — String, one of Resolution's active-defense
##                                family: "Dodge" | "Parry" | "Block" |
##                                "Steel" | "OpportunisticStrike" | (FEAT-008
##                                steel-thread smoke test regression fix)
##                                "WeaponAttack" — the composite trigger_type
##                                a live enemy-Strikes-player Strike (routed
##                                through core/application/round_session.gd's
##                                _build_reaction_trigger()) opens: legal_reactions
##                                is the UNION of whichever of Dodge/Parry/Block
##                                are eligible (never Steel — that only ever
##                                triggers off a fortitude/will attack, which
##                                does not exist yet, and never
##                                OpportunisticStrike, a movement-triggered
##                                reaction, not an incoming-Strike one), so a
##                                single Strike's reaction pop-up can offer the
##                                defender a genuine choice between whichever
##                                reactions their own conditions/weapon make
##                                legal, rather than being pinned to ONE
##                                pre-selected reaction type. See
##                                _compute_legal_reactions()'s "WeaponAttack"
##                                branch below — composed entirely from the SAME
##                                is_dodge_eligible()/is_parry_eligible()/
##                                is_block_eligible() predicates the single-type
##                                branches already use, never a re-derived rule.
##   "reactor"                 — Dictionary: the combatant offered the
##                                reaction (needs "conditions"/"skills"/
##                                "conscious" for Dodge/Steel eligibility).
##   "reactor_action_economy"  — the reactor's ActionEconomy instance
##                                (core/rules/action_economy.gd). OPTIONAL —
##                                when omitted, the reactor is treated as
##                                never Spent and resume() never spends a
##                                reaction (useful for pure legal_reactions
##                                inspection in tests).
##   "weapon"                  — Dictionary: the reactor's OWN weapon, used
##                                by the Parry/Block eligibility predicates
##                                (parry_bonus/block_value).
##   "defense_type"            — String: "ac" | "reflex" | "fortitude" |
##                                "will" — the passive defense this attack
##                                is being resolved against; drives Dodge's
##                                and Steel's trigger predicates.
##   "attack_context"          — Dictionary: forwarded verbatim to the
##                                ReactionChooserPort as `context`, and also
##                                consulted directly for
##                                "open_space_available" (Dodge) and
##                                "melee_reach" (OpportunisticStrike).
##   "round_number"            — int, OPTIONAL (default 0): stamped on the
##                                emitted events.
##
## `legal_reactions` returned by open() is EITHER [trigger_type's lowercase
## reaction name] (when that specific trigger's eligibility predicate
## passes) or [] (when it does not) — the reaction window offers exactly
## the ONE reaction type named by `trigger`, mirroring ReactionTrigger's
## own trigger_type field (see this feature's data_model). ReactionChooserPort.PASS
## ("none") is ALWAYS an additional implicit choice, never listed inside
## legal_reactions itself (mirrors this feature's api_contracts: "choice ∈
## legal_reactions ∪ {Pass}").
##
## Only ONE window may be open at a time (this steel thread's documented
## "no nested/parallel windows" constraint) — calling open() while a
## window is already open closes/discards the stale one first (last writer
## wins; callers are expected to resume() or let a window resolve before
## opening the next one).
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example (player-facing, split across two calls):
##   var window := ReactionWindow.new(event_sink_port)
##   var opened := window.open(trigger)
##   # ... later, once the (possibly UI-driven) chooser has an answer ...
##   var result := window.resume(opened["window_id"], "dodge", "player")
##
## Usage example (headless, single call — no UI present, FEAT-009 test_criteria):
##   var window := ReactionWindow.new(event_sink_port)
##   var result := window.open_and_resolve(trigger, AutoReactionChooserClass.new("pass"))

class_name ReactionWindow
extends "res://core/application/ports/reaction_window_port.gd"

const ResolutionClass    = preload("res://core/rules/resolution.gd")
const RoundEventsClass   = preload("res://core/rules/round_events.gd")
const ReactionChooserPortClass = preload("res://core/application/ports/reaction_chooser_port.gd")

## Lowercase reaction names — a legal_reactions entry, and the exact String
## forwarded as resolve_weapon_attack()'s active_defense argument (its
## VALID_ACTIVE_DEFENSES contract).
const REACTION_DODGE: String = "dodge"
const REACTION_PARRY: String = "parry"
const REACTION_BLOCK: String = "block"
const REACTION_STEEL: String = "steel"
const REACTION_OPPORTUNISTIC_STRIKE: String = "opportunistic_strike"

var _event_sink_port  ## EventSinkPort — injected

var _window_counter: int = 0

## _open_window_id — "" when no window is currently open (the pausable
## state this class holds BETWEEN open() and resume(), see file-level doc).
var _open_window_id: String = ""
var _open_trigger: Dictionary = {}
var _open_legal_reactions: Array = []


## _init(event_sink_port) — stores the injected EventSinkPort. Duck-typed
## (no static port type on the parameter) so any object implementing
## EventSinkPort's documented emit() contract may be substituted (test
## doubles in particular), matching this project's existing port-injection
## convention.
func _init(event_sink_port) -> void:
	_event_sink_port = event_sink_port


## open(trigger) -> Dictionary — see class-level doc / ReactionWindowPort's
## contract doc for the full behavior. Non-blocking: computes
## legal_reactions and returns immediately — it never itself asks a
## chooser for a decision (that is resume()'s caller's job, e.g.
## open_and_resolve() below, or a UI event handler holding onto
## window_id across frames).
func open(trigger: Dictionary) -> Dictionary:
	var reactor: Dictionary = trigger.get("reactor", {})
	var reactor_action_economy = trigger.get("reactor_action_economy", null)

	if reactor_action_economy != null and reactor_action_economy.is_spent():
		# ALREADY_SPENT (per this feature's api_contracts / security notes):
		# the window never opens and no event is emitted — the reaction
		# implicitly resolves to no-reaction.
		return {"window_id": "", "legal_reactions": [], "opened": false, "reason": "ALREADY_SPENT"}

	var legal_reactions: Array = _compute_legal_reactions(trigger)

	_window_counter += 1
	var window_id: String = "rwin-%d" % _window_counter
	_open_window_id       = window_id
	_open_trigger         = trigger
	_open_legal_reactions = legal_reactions

	_event_sink_port.emit(RoundEventsClass.ReactionWindowOpenedEvent.new(
		trigger.get("round_number", 0),
		window_id,
		trigger.get("trigger_type", ""),
		reactor.get("name", ""),
		legal_reactions
	))

	return {"window_id": window_id, "legal_reactions": legal_reactions, "opened": true}


## resume(window_id, choice, resolved_by) -> Dictionary — see class-level
## doc / ReactionWindowPort's contract doc. Applies `choice` and closes the
## window in a single, synchronous, non-blocking call — no loop/wait of any
## kind, so the engine thread is never blocked by this method.
func resume(window_id: String, choice: String, resolved_by: String = "unknown") -> Dictionary:
	if window_id == "" or window_id != _open_window_id:
		return {"ok": false, "error": ERR_STALE_WINDOW}

	if choice != ReactionChooserPortClass.PASS and not _open_legal_reactions.has(choice):
		return {"ok": false, "error": ERR_ILLEGAL_CHOICE}

	var trigger: Dictionary = _open_trigger
	var reactor_action_economy = trigger.get("reactor_action_economy", null)
	var applied_choice: String = choice

	if applied_choice != ReactionChooserPortClass.PASS and reactor_action_economy != null:
		var spend_result: Dictionary = reactor_action_economy.spend_reaction()
		if not spend_result.get("success", false):
			# Race guard (open()..resume() straddling another spend): fall
			# back to PASS rather than erroring — "never hang/crash".
			applied_choice = ReactionChooserPortClass.PASS

	_event_sink_port.emit(RoundEventsClass.ReactionResolvedEvent.new(
		trigger.get("round_number", 0),
		window_id,
		applied_choice,
		resolved_by
	))

	# Close the window — resume() is a one-shot operation per window_id.
	_open_window_id       = ""
	_open_trigger         = {}
	_open_legal_reactions = []

	return {"ok": true, "window_id": window_id, "choice": applied_choice}


## open_and_resolve(trigger, chooser, resolved_by) -> Dictionary — FEAT-009
## convenience orchestration: open()s the window, hands its legal_reactions
## (plus trigger["attack_context"]) to the injected ReactionChooserPort,
## then resume()s with whatever it returns — the "yield-to-chooser" flow
## the file-level doc describes, in one call. This is what lets a headless
## AutoReactionChooser (infrastructure/auto_reaction_chooser.gd) drive
## resolution to completion with NO UI present (test_criteria #3): for an
## Auto/AI chooser, choose() answers synchronously so this whole call
## returns immediately; a future blocking PlayerReactionChooser would
## instead be driven via the split open()/resume() calls directly (e.g.
## from a UI signal handler), never through this convenience method.
##
## When open() reports the reactor was already Spent (never opened), this
## method skips resume() entirely and reports the implicit PASS outcome
## directly — resume()'s STALE_WINDOW guard would otherwise reject a
## resume() call against a window_id that was never opened.
func open_and_resolve(trigger: Dictionary, chooser, resolved_by: String = "auto") -> Dictionary:
	var opened: Dictionary = open(trigger)
	if not opened.get("opened", false):
		return {
			"ok": true,
			"window_id": "",
			"choice": ReactionChooserPortClass.PASS,
			"opened": false,
			"reason": opened.get("reason", ""),
		}

	var legal_reactions: Array = opened.get("legal_reactions", [])
	var context: Dictionary = trigger.get("attack_context", {})
	var choice: String = chooser.choose(legal_reactions, context)

	var result: Dictionary = resume(opened["window_id"], choice, resolved_by)
	result["opened"] = true
	return result


## open_and_resolve_attack(trigger, resolution, attacker, weapon, chooser,
##                         resolved_by) -> Dictionary — FEAT-010 (US-010 /
## FR-010, ADR-016): wires a reaction into a LIVE attack resolution.
##
## open_and_resolve()/resume() (FEAT-009) only ever produce a bare `choice`
## String — they never touch core/rules/resolution.gd, so a chosen "dodge"
## could not previously influence an actual Strike's hit/miss outcome. This
## method closes that gap: it opens the window, asks the injected
## ReactionChooserPort for a decision, then delegates the ENTIRE attack roll
## — including the pre-hit Mobility check that substitutes for the reactor's
## passive AC/Reflex on a successful Dodge — to the injected `resolution`
## (a core/rules/resolution.gd Resolution instance) via
## resolve_weapon_attack(). resolution.gd remains the SOLE place attack math
## AND reaction-spend (ActionEconomy.spend_reaction(), NEVER
## spend_action()) happen; this method never re-derives either — it only
## decides WHETHER to hand resolution.gd the reactor's ActionEconomy (i.e.
## whether a reaction may be spent at all), based on the chooser's answer.
##
## trigger      — same shape as open()'s trigger argument (see file-level
##                doc). `trigger["reactor"]` doubles as resolve_weapon_attack()'s
##                `target` argument (the reactor IS the party being attacked).
## resolution   — a core/rules/resolution.gd Resolution instance.
## attacker     — resolve_weapon_attack()'s `attacker` argument.
## weapon       — resolve_weapon_attack()'s `weapon` argument (the
##                ATTACKER's weapon — not the reactor's).
## chooser      — a ReactionChooserPort implementation (e.g. a headless
##                AutoReactionChooser, or a future blocking
##                PlayerReactionChooser).
## resolved_by  — stamped on the emitted ReactionResolvedEvent.
##
## Returns resolution.gd's full resolve_weapon_attack() result Dictionary
## (hit/crit/damage_final/defender_stepped/next_check_bonus/... — see that
## method's doc), PLUS:
##   "reaction_choice" — the String actually applied: one of trigger's
##                        legal_reactions, or ReactionChooserPort.PASS.
##   "window_id"        — "" when the reactor was already Spent (window
##                        never opened), else the opened window's id.
##
## When the reactor's ActionEconomy is already Spent (ALREADY_SPENT), no
## window opens and no reaction is offered — the attack resolves exactly as
## if the chooser had declined (active_defense "none", passive AC/Reflex),
## matching open_and_resolve()'s existing ALREADY_SPENT contract.
func open_and_resolve_attack(
	trigger: Dictionary,
	resolution,
	attacker: Dictionary,
	weapon: Dictionary,
	chooser,
	resolved_by: String = "auto"
) -> Dictionary:
	var reactor: Dictionary = trigger.get("reactor", {})
	var defense_type: String = trigger.get("defense_type", "")
	var attack_context: Dictionary = trigger.get("attack_context", {})
	var reactor_action_economy = trigger.get("reactor_action_economy", null)

	var opened: Dictionary = open(trigger)
	var choice: String = ReactionChooserPortClass.PASS

	if opened.get("opened", false):
		var legal_reactions: Array = opened.get("legal_reactions", [])
		var requested_choice: String = chooser.choose(legal_reactions, attack_context)
		# Safety net matching resume()'s ERR_ILLEGAL_CHOICE guard: a
		# misbehaving chooser answering with something not offered degrades
		# to PASS rather than being forwarded to resolution.gd.
		if requested_choice == ReactionChooserPortClass.PASS or legal_reactions.has(requested_choice):
			choice = requested_choice

	var defense_context: Dictionary = attack_context.duplicate()
	if choice != ReactionChooserPortClass.PASS:
		# Only when a real reaction was chosen do we hand resolution.gd the
		# reactor's ActionEconomy — this is what permits resolve_weapon_attack()
		# to call ActionEconomy.spend_reaction() internally. Declining (PASS)
		# must never spend a reaction, so the economy is withheld entirely.
		defense_context["action_economy"] = reactor_action_economy

	var outcome: Dictionary = resolution.resolve_weapon_attack(
		attacker, reactor, weapon, defense_type, choice, defense_context
	)

	var applied_choice: String = ReactionChooserPortClass.PASS
	if opened.get("opened", false):
		var active_defense_applied: String = outcome.get("active_defense_applied", "none")
		if active_defense_applied != "none":
			applied_choice = active_defense_applied

		# Close the window (mirrors resume()'s one-shot closing behavior) —
		# resolution.gd has already applied/spent the reaction itself, so no
		# second spend happens here.
		_open_window_id       = ""
		_open_trigger         = {}
		_open_legal_reactions = []

		_event_sink_port.emit(RoundEventsClass.ReactionResolvedEvent.new(
			trigger.get("round_number", 0),
			opened.get("window_id", ""),
			applied_choice,
			resolved_by
		))

	outcome["reaction_choice"] = applied_choice
	outcome["window_id"] = opened.get("window_id", "")
	return outcome


## open_and_resolve_prehit_avoidance(trigger, resolution, attacker, weapon,
##                                    chooser, resolved_by) -> Dictionary —
## FEAT-002 (US-002 / FR-001, Iteration J Part B): the ON-ATTACKED-only
## sibling of open_and_resolve_attack() above — wires a "PreHitAvoidance"
## reaction (Dodge/Steel only) into a LIVE attack's PHASE 1 resolution,
## reusing core/rules/resolution.gd's resolve_to_hit() (FEAT-001's two-phase
## split) instead of the single-call resolve_weapon_attack(), so a caller
## learns whether the reaction protected the reactor BEFORE any post-hit
## (Block/Parry / OnHitMitigation, a later feature) window would ever need to
## open. This method NEVER calls apply_on_hit_defense() itself — that phase
## is out of this feature's scope entirely; a hit always resolves with
## whatever damage_raw resolve_to_hit() produced.
##
## trigger      — same shape as open()'s trigger argument (see file-level
##                doc); `trigger["reactor"]` doubles as resolve_to_hit()'s
##                `target` argument (the reactor IS the party being
##                attacked).
## resolution   — a core/rules/resolution.gd Resolution instance.
## attacker     — resolve_to_hit()'s `attacker` argument.
## weapon       — resolve_to_hit()'s `weapon` argument (the ATTACKER's
##                weapon — not the reactor's).
## chooser      — a ReactionChooserPort implementation.
## resolved_by  — stamped on the emitted ReactionResolvedEvent.
##
## Returns resolve_to_hit()'s full result Dictionary (hit/crit/roll_total/
## damage_raw/defender_stepped/active_defense_applied/next_check_bonus/
## defense_value/...), PLUS:
##   "reaction_choice"   — the String actually applied: "dodge" | "steel" |
##                         ReactionChooserPort.PASS.
##   "window_id"          — "" when the reactor was already Spent (window
##                         never opened), else the opened window's id.
##   "reaction_spent"     — bool: true iff a real pre-hit defense (dodge or
##                         steel) actually TRIGGERED inside resolve_to_hit()
##                         (mirrors resolve_to_hit()'s own trigger gate —
##                         defense_type/eligibility/Immobilized/open-space —
##                         never re-derived here). false for PASS, and false
##                         when the chosen reaction's trigger conditions did
##                         not hold (e.g. Dodge chosen while Immobilized).
##   "short_circuited"    — bool: true iff a triggered pre-hit reaction
##                         PROTECTED the reactor (partial["hit"] == false) —
##                         test_criteria "successful Dodge/Steel short-
##                         circuits": no damage was dealt, and — since
##                         apply_on_hit_defense() is never called on a miss
##                         (its own documented precondition) — no on-hit
##                         window may ever be offered for this Strike.
##   "on_hit_suppressed"  — bool: true iff a triggered pre-hit reaction
##                         FAILED to protect the reactor (partial["hit"] ==
##                         true) — the reactor's ONE reaction for this Strike
##                         was already spent, so a subsequent on-hit
##                         (Block/Parry) window must be suppressed/never
##                         offered (the ≤1-reaction-per-Strike budget
##                         invariant). Distinct from resolve_to_hit()'s own
##                         result, which carries no on_hit_suppressed key at
##                         all (that field belongs to apply_on_hit_defense()'s
##                         phase-2 contract) — this method synthesizes it here
##                         purely to let a PreHitAvoidance-only caller (e.g.
##                         round_session.gd) know whether it is safe to open
##                         a later on-hit window.
##
## When the reactor's ActionEconomy is already Spent (ALREADY_SPENT), no
## window opens and no reaction is offered — resolve_to_hit() is still
## invoked exactly once, with pre_hit_defense "none" (equivalent to the
## chooser having declined), matching open_and_resolve_attack()'s existing
## ALREADY_SPENT contract.
func open_and_resolve_prehit_avoidance(
	trigger: Dictionary,
	resolution,
	attacker: Dictionary,
	weapon: Dictionary,
	chooser,
	resolved_by: String = "auto"
) -> Dictionary:
	var reactor: Dictionary = trigger.get("reactor", {})
	var defense_type: String = trigger.get("defense_type", "")
	var attack_context: Dictionary = trigger.get("attack_context", {})
	var reactor_action_economy = trigger.get("reactor_action_economy", null)

	var opened: Dictionary = open(trigger)
	var choice: String = ReactionChooserPortClass.PASS

	if opened.get("opened", false):
		var legal_reactions: Array = opened.get("legal_reactions", [])
		var requested_choice: String = chooser.choose(legal_reactions, attack_context)
		# Safety net matching resume()'s ERR_ILLEGAL_CHOICE guard: a
		# misbehaving chooser answering with something not offered degrades
		# to PASS rather than being forwarded to resolve_to_hit().
		if requested_choice == ReactionChooserPortClass.PASS or legal_reactions.has(requested_choice):
			choice = requested_choice

	var pre_hit_defense: String = choice if choice != ReactionChooserPortClass.PASS else "none"

	var ctx: Dictionary = attack_context.duplicate()
	if pre_hit_defense != "none":
		# Only when a real reaction was chosen do we hand resolve_to_hit()
		# the reactor's ActionEconomy — permitting its internal
		# _try_spend_reaction() call. Declining (PASS) must never spend a
		# reaction, so the economy is withheld entirely (mirrors
		# open_and_resolve_attack()'s identical discipline).
		ctx["action_economy"] = reactor_action_economy

	var partial: Dictionary = resolution.resolve_to_hit(attacker, reactor, weapon, defense_type, pre_hit_defense, ctx)

	# reaction_spent mirrors resolve_to_hit()'s own trigger gate: it only
	# ever stamps active_defense_applied as "dodge"/"steel" when the
	# defense_type/eligibility/Immobilized/open-space conditions actually
	# held AND a reaction was actually spent — never re-derived here.
	var reaction_spent: bool = partial.get("active_defense_applied", "none") != "none"
	var short_circuited: bool = reaction_spent and not partial.get("hit", false)
	var on_hit_suppressed: bool = reaction_spent and partial.get("hit", false)

	var applied_choice: String = choice if reaction_spent else ReactionChooserPortClass.PASS

	if opened.get("opened", false):
		# Close the window (mirrors resume()'s one-shot closing behavior) —
		# resolve_to_hit() has already applied/spent the reaction itself, so
		# no second spend happens here.
		_open_window_id       = ""
		_open_trigger         = {}
		_open_legal_reactions = []

		_event_sink_port.emit(RoundEventsClass.ReactionResolvedEvent.new(
			trigger.get("round_number", 0),
			opened.get("window_id", ""),
			applied_choice,
			resolved_by
		))

	partial["reaction_choice"]  = applied_choice
	partial["window_id"]        = opened.get("window_id", "")
	partial["reaction_spent"]   = reaction_spent
	partial["short_circuited"]  = short_circuited
	partial["on_hit_suppressed"] = on_hit_suppressed
	return partial


## open_and_resolve_onhit_mitigation(trigger, resolution, partial, chooser,
##                                    resolved_by) -> Dictionary — FEAT-004
## (US-004 / FR-003): the ON-HIT sibling of
## open_and_resolve_prehit_avoidance() above -- wires a "OnHitMitigation"
## reaction (Parry/Block only) into a LIVE attack's PHASE 2 resolution,
## reusing core/rules/resolution.gd's apply_on_hit_defense() (FEAT-001's
## two-phase split) instead of the combined resolve_weapon_attack(). This
## method is invoked with the ALREADY-COMPUTED `partial` a prior
## resolve_to_hit() call produced (typically via
## open_and_resolve_prehit_avoidance() itself, or a plain resolve_to_hit()
## call when no pre-hit reaction was even offered) -- it never re-rolls the
## attack, never re-derives hit/miss, and -- per apply_on_hit_defense()'s own
## documented precondition -- NEVER calls apply_on_hit_defense() when
## partial.hit == false (test_criteria #2) or when a reaction was already
## spent earlier this Strike (test_criteria #5): both conditions are checked
## via is_on_hit_mitigation_eligible() BEFORE this method ever calls open()
## at all, so a miss/already-spent Strike never even opens a window or emits
## a ReactionWindowOpenedEvent (test_criteria #5 "skipped entirely").
##
## trigger      — same shape as open()'s trigger argument (see file-level
##                doc); `trigger["reactor"]` is the combatant OFFERED the
##                reaction, `trigger["weapon"]` is the REACTOR's own weapon
##                (used by is_parry_eligible()/is_block_eligible()), and
##                `trigger["attack_context"]` is reused verbatim as
##                apply_on_hit_defense()'s defense_context -- so a caller
##                that wants Block/Parry math to actually reduce damage must
##                populate attack_context's "blocking_weapon"/
##                "parrying_weapon" keys itself (mirrors
##                open_and_resolve_attack()'s identical convention).
##                `trigger["reaction_already_spent"]` — bool, OPTIONAL
##                (default false): true when an earlier reaction (pre-hit
##                Dodge/Steel, or per this feature's budget invariant) already
##                spent this Strike's one reaction -- the gate this method
##                checks FIRST, independent of hit result.
## resolution   — a core/rules/resolution.gd Resolution instance.
## partial      — the Dictionary produced by resolution.resolve_to_hit() (or
##                an equivalent Dictionary carrying at least "hit",
##                "damage_raw", "roll_total", "defense_type", "weapon",
##                "active_defense_applied") -- this method never re-derives
##                any of resolve_to_hit()'s own math.
## chooser      — a ReactionChooserPort implementation.
## resolved_by  — stamped on the emitted ReactionResolvedEvent.
##
## Returns a copy of `partial`, PLUS:
##   "damage_final"           — int, ALWAYS >= 0: damage_raw when the window
##                              never opened/no reaction was chosen, else
##                              apply_on_hit_defense()'s own damage_final.
##   "active_defense_applied" — "parry" | "block" | whatever `partial`
##                              already carried (e.g. "none") when no on-hit
##                              reaction was chosen.
##   "on_hit_suppressed"      — bool: true after a real Block or a
##                              SUCCESSFUL Parry (mirrors
##                              apply_on_hit_defense()'s own contract).
##   "reaction_choice"        — "parry" | "block" | ReactionChooserPort.PASS.
##   "window_id"              — "" when the gate failed (window never
##                              opened) or the reactor was already Spent,
##                              else the opened window's id.
##   "reaction_spent"         — bool: true iff apply_on_hit_defense() was
##                              actually invoked (a real Parry/Block choice
##                              was made and applied).
func open_and_resolve_onhit_mitigation(
	trigger: Dictionary,
	resolution,
	partial: Dictionary,
	chooser,
	resolved_by: String = "auto"
) -> Dictionary:
	var attack_hit: bool = partial.get("hit", false)
	var reaction_already_spent: bool = trigger.get("reaction_already_spent", false)

	var damage_final: int = partial.get("damage_raw", 0)
	var active_defense_applied: String = partial.get("active_defense_applied", "none")
	var on_hit_suppressed: bool = false
	var reaction_spent: bool = false
	var applied_choice: String = ReactionChooserPortClass.PASS
	var window_id: String = ""

	# The gate (test_criteria #1/#5): a miss, or a Strike whose one reaction
	# was already spent, skips this window ENTIRELY -- open() is never even
	# called, so no ReactionWindowOpenedEvent/ReactionResolvedEvent is ever
	# emitted for it, and apply_on_hit_defense() is never invoked
	# (test_criteria #2).
	if is_on_hit_mitigation_eligible(reaction_already_spent, attack_hit):
		var attack_context: Dictionary = trigger.get("attack_context", {})
		var reactor_action_economy = trigger.get("reactor_action_economy", null)

		# Stamp attack_hit/reaction_already_spent onto the trigger handed to
		# open() so _compute_legal_reactions()'s OWN "OnHitMitigation" gate
		# (test_criteria #1) evaluates the SAME facts this outer check just
		# confirmed -- never a second, drifting copy of the eligibility rule.
		var trigger_for_open: Dictionary = trigger.duplicate()
		trigger_for_open["attack_hit"] = attack_hit
		trigger_for_open["reaction_already_spent"] = reaction_already_spent

		var opened: Dictionary = open(trigger_for_open)
		window_id = opened.get("window_id", "")

		if opened.get("opened", false):
			var legal_reactions: Array = opened.get("legal_reactions", [])
			if not legal_reactions.is_empty():
				var requested_choice: String = chooser.choose(legal_reactions, attack_context)
				# Safety net matching resume()'s ERR_ILLEGAL_CHOICE guard: a
				# misbehaving chooser answering with something not offered
				# degrades to PASS rather than being forwarded to
				# apply_on_hit_defense().
				if requested_choice == ReactionChooserPortClass.PASS or legal_reactions.has(requested_choice):
					applied_choice = requested_choice

			if applied_choice != ReactionChooserPortClass.PASS:
				# Only when a real reaction was chosen do we hand
				# apply_on_hit_defense() the reactor's ActionEconomy -- permitting
				# its internal _try_spend_reaction() call. Declining (PASS) must
				# never spend a reaction, so the economy is withheld entirely
				# (mirrors open_and_resolve_prehit_avoidance()'s identical
				# discipline).
				var ctx: Dictionary = attack_context.duplicate()
				ctx["action_economy"] = reactor_action_economy
				var post: Dictionary = resolution.apply_on_hit_defense(partial, applied_choice, ctx)
				damage_final = post["damage_final"]
				active_defense_applied = post["active_defense_applied"]
				on_hit_suppressed = post["on_hit_suppressed"]
				reaction_spent = true

			# Close the window (mirrors resume()'s one-shot closing behavior) --
			# apply_on_hit_defense() (when invoked) has already applied/spent
			# the reaction itself, so no second spend happens here.
			_open_window_id       = ""
			_open_trigger         = {}
			_open_legal_reactions = []

			_event_sink_port.emit(RoundEventsClass.ReactionResolvedEvent.new(
				trigger.get("round_number", 0),
				window_id,
				applied_choice,
				resolved_by
			))
	# else: gate failed -- damage_final/active_defense_applied/on_hit_suppressed
	# stay exactly what `partial` already carried (plus damage_final defaulting
	# to damage_raw), reaction_choice stays PASS, window_id stays "".

	var result: Dictionary = partial.duplicate()
	result["damage_final"] = damage_final
	result["active_defense_applied"] = active_defense_applied
	result["on_hit_suppressed"] = on_hit_suppressed
	result["reaction_choice"] = applied_choice
	result["window_id"] = window_id
	result["reaction_spent"] = reaction_spent
	return result


## _compute_legal_reactions(trigger) -> Array — evaluates the
## trigger-type-specific eligibility predicate (test_criteria #1) via
## core/rules/resolution.gd's FEAT-009 static predicates, never
## re-implementing the rule itself. Returns [] for an unrecognized
## trigger_type (defensive — never raises).
func _compute_legal_reactions(trigger: Dictionary) -> Array:
	var trigger_type: String = trigger.get("trigger_type", "")
	var reactor: Dictionary = trigger.get("reactor", {})
	var weapon: Dictionary = trigger.get("weapon", {})
	var defense_type: String = trigger.get("defense_type", "")
	var attack_context: Dictionary = trigger.get("attack_context", {})

	match trigger_type:
		"Dodge":
			if ResolutionClass.is_dodge_eligible(defense_type, reactor, attack_context):
				return [REACTION_DODGE]
			return []
		"Parry":
			if ResolutionClass.is_parry_eligible(weapon):
				return [REACTION_PARRY]
			return []
		"Block":
			if ResolutionClass.is_block_eligible(weapon):
				return [REACTION_BLOCK]
			return []
		"Steel":
			if ResolutionClass.is_steel_eligible(defense_type, reactor):
				return [REACTION_STEEL]
			return []
		"OpportunisticStrike":
			# Melee-reach predicate (relaxable per this feature's
			# extension_points — future talents may add predicates here
			# without rewriting the trigger pipeline).
			if attack_context.get("melee_reach", false):
				return [REACTION_OPPORTUNISTIC_STRIKE]
			return []
		"PreHitAvoidance":
			# FEAT-002 (US-002 / FR-001, Iteration J Part B — reaction-timing
			# correction): the ON-ATTACKED-only counterpart to "WeaponAttack"'s
			# combined ask above — offers ONLY Dodge/Steel (never Parry/Block,
			# which are ON-HIT reactions and must never be offered before the
			# attack roll even happens; see this file's OnHitMitigation
			# counterpart, a later feature). Computed via the SAME
			# is_dodge_eligible()/is_steel_eligible() predicates the single-type
			# "Dodge"/"Steel" branches above already use — never a re-derived
			# rule (test_criteria #1).
			var legal_prehit: Array = []
			if ResolutionClass.is_dodge_eligible(defense_type, reactor, attack_context):
				legal_prehit.append(REACTION_DODGE)
			if ResolutionClass.is_steel_eligible(defense_type, reactor):
				legal_prehit.append(REACTION_STEEL)
			return legal_prehit
		"OnHitMitigation":
			# FEAT-004 (US-004 / FR-003): the ON-HIT sibling of "PreHitAvoidance"
			# above -- offers ONLY Parry/Block (never Dodge/Steel, which are
			# ON-ATTACKED reactions and must never be offered AFTER the attack
			# roll is already known). Gated FIRST by
			# is_on_hit_mitigation_eligible() (test_criteria #1 "gated
			# correctly" / #5 "skipped entirely on miss or when a reaction was
			# already spent") BEFORE ever consulting is_parry_eligible()/
			# is_block_eligible() -- a miss, or a Strike whose one reaction was
			# already spent (Dodge/Steel pre-hit, or a prior on-hit reaction),
			# must offer NEITHER reaction regardless of the reactor's weapon.
			# Computed via the SAME is_parry_eligible()/is_block_eligible()
			# predicates the single-type "Parry"/"Block" branches above already
			# use -- never a re-derived rule.
			var attack_hit: bool = trigger.get("attack_hit", false)
			var reaction_already_spent: bool = trigger.get("reaction_already_spent", false)
			if not is_on_hit_mitigation_eligible(reaction_already_spent, attack_hit):
				return []
			var legal_onhit: Array = []
			if ResolutionClass.is_parry_eligible(weapon):
				legal_onhit.append(REACTION_PARRY)
			if ResolutionClass.is_block_eligible(weapon):
				legal_onhit.append(REACTION_BLOCK)
			return legal_onhit
		"WeaponAttack":
			# FEAT-008 (steel-thread smoke test) regression fix: the composite
			# trigger_type a live enemy-Strikes-player Strike opens (see
			# file-level doc above) — the union of whichever of Dodge/Parry/
			# Block are legal right now, computed via the SAME eligibility
			# predicates the single-type branches above use, never a
			# re-derived rule. Steel is deliberately excluded (only triggers
			# off a fortitude/will attack, out of scope for an "ac" Strike).
			var legal: Array = []
			if ResolutionClass.is_dodge_eligible(defense_type, reactor, attack_context):
				legal.append(REACTION_DODGE)
			if ResolutionClass.is_parry_eligible(weapon):
				legal.append(REACTION_PARRY)
			if ResolutionClass.is_block_eligible(weapon):
				legal.append(REACTION_BLOCK)
			return legal
		_:
			return []


## is_on_hit_mitigation_eligible(reaction_already_spent, attack_hit) -> bool —
## FEAT-003 (US-003 / FR-002): the shared eligibility gate a future
## "OnHitMitigation" window (Parry/Block, opened AFTER resolve_to_hit()'s hit
## result is known — the on-hit sibling of open_and_resolve_prehit_avoidance()'s
## two-phase pattern above) must consult before ever opening. Pure,
## side-effect-free, statically callable (mirrors core/rules/resolution.gd's
## is_dodge_eligible() family, and this class's own
## _compute_legal_reactions() predicates) so no caller re-derives this rule a
## second, drifting way.
##
## The <=1-reaction-per-Strike budget invariant (US-003) means an on-hit
## window may NEVER be offered once a pre-hit reaction (Dodge/Steel) already
## spent this Strike's one reaction — `reaction_already_spent` is
## deliberately checked FIRST, independent of `attack_hit`, so a caller gets
## `false` "regardless of hit result" once a reaction was already spent
## (test_criteria #3). This mirrors round_session.gd's existing
## `not prehit_on_hit_suppressed` short-circuit guarding its current
## "WeaponAttack" composite window (see that call site's own doc) — this
## function gives that same rule a real name/seam a caller can invoke
## directly and a test can exercise in isolation, without needing to drive a
## full Strike through resolve_to_hit() first.
static func is_on_hit_mitigation_eligible(reaction_already_spent: bool, attack_hit: bool) -> bool:
	if reaction_already_spent:
		return false
	return attack_hit


## assert_reaction_budget_delta(delta, context_label) -> bool — FEAT-003
## (US-003 / FR-002): the shared budget-delta GATE a caller invokes once a
## Strike's reaction-eligible defender ActionEconomy budget delta is known —
## a before-snapshot minus an after-snapshot spanning every reaction window
## opened for that ONE Strike (see core/application/round_session.gd's
## advance_ai_turn(), this project's shared reaction resolution path, per
## this feature's design notes). `delta` must never exceed 1 — the
## <=1-reaction-per-Strike invariant this feature exists to defend (US-003),
## covering Dodge/Steel (pre-hit) today and Parry/Block (on-hit, a future
## wiring) alike, since both ultimately draw from the SAME
## ActionEconomy.spend_reaction() gate (core/rules/resolution.gd's
## _try_spend_reaction(), the single shared spend site every active-defense
## branch already routes through).
##
## A delta of 0 or 1 is a no-op returning true. A delta > 1 is a genuine
## contract violation: a real GDScript assert() fires — failing loudly in a
## dev/test build (Godot only compiles assert() calls into debug builds,
## exactly the "assert-fail in dev, silently skip in release" contract this
## feature's design calls for) — AND push_error() is logged as
## defense-in-depth, since this project's Godot 4.3 engine cannot capture
## push_error() from GUT (see core/rules/resolution.gd's
## apply_on_hit_defense() doc for this same documented limitation). Returns
## false so a caller can additionally record the violation somewhere GUT CAN
## observe directly (e.g. RoundSession.get_reaction_budget_violations()).
static func assert_reaction_budget_delta(delta: int, context_label: String = "") -> bool:
	if delta <= 1:
		return true

	var message: String = (
		"ReactionWindow: budget-delta invariant violated%s -- expected <=1 reaction spent per Strike, observed delta=%d"
		% [(" (%s)" % context_label) if context_label != "" else "", delta]
	)
	assert(false, message)
	push_error(message)
	return false
