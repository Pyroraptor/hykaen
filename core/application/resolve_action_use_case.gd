## core/application/resolve_action_use_case.gd — ResolveActionUseCase
## (FEAT-098 / US-003/US-004/US-005, CR-001 AC-1/AC-2/AC-3)
##
## Application layer (Clean Architecture): resolves a SINGLE Strike
## action/reaction for one combatant against one target — the per-action
## slice of logic extracted out of core/combat/encounter.gd's run_round().
##
## Depends ONLY on domain (the injected ActionEconomy instance's documented
## spend_action()/spend_reaction() Result contract — core/rules/action_economy.gd)
## and application-layer ports (RandomNumberPort for damage rolls,
## EventSinkPort for event emission, RoundHistoryPort for the audit trail).
## Never imports an adapter/infrastructure class directly.
##
## Responsibilities, in order:
##   1. Spend one action from the combatant's per-ROUND ActionEconomy budget
##      (CR-001 AC-1/AC-2/AC-3 — actions and reactions share one pool). A
##      failed Result (ALREADY_SPENT) is reported back via "resolved: false"
##      — the caller (RunRoundUseCase) is responsible for the "skip and
##      continue the cycle" error-handling contract; this use case never
##      throws/crashes on that failure.
##   2. Resolve the weapon Strike: an attack roll (d20 + attribute modifier +
##      weapon proficiency bonus) against the target's AC, with a damage
##      roll on hit (doubled dice + doubled modifier on a crit, i.e. beating
##      the defense value by >=10) — rolled via the injected RandomNumberPort
##      rather than a global/ambient RNG (NFR-003 determinism).
##   3. Apply damage to target.hp_current.
##   4. Emit 'attack' (always) and 'combatant_defeated' (if the target's HP
##      transitions to <= 0) events via EventSinkPort, in that order — as
##      TYPED value objects (FEAT-099/FIND-096): core/rules/round_events.gd's
##      RoundEvents.AttackEvent / RoundEvents.CombatantDefeatedEvent, never a
##      raw Dictionary. EventSinkPort.emit() therefore now accepts any
##      Variant (see core/application/event_sink_port.gd). The emitted
##      AttackEvent also carries actor_updated_action_budget (FEAT-009 /
##      US-009 / FR-014, ADR-003) — a {remaining, spent} snapshot of the
##      ACTING combatant's ActionBudget taken immediately after this
##      resolve()'s spend_action() call — so presentation/status_panel_view.gd
##      can project the actor's post-Strike budget read-only, with zero
##      recomputation of action-economy rules on its side.
##   5. Append one entry via RoundHistoryPort carrying the post-spend
##      budget_remaining and the caller-supplied cycle_index. The appended
##      entry is a Dictionary preserving the historical
##      attacker/action/target/roll/damage_final/budget_remaining/round/
##      cycle_index keys (relied upon by core/sim/simulator.gd and other
##      pre-existing consumers, which this CR explicitly keeps UNMODIFIED —
##      see CR-001 design notes) PLUS a new "entry" key holding the typed
##      RoundEvents.RoundHistoryEntry value object (FEAT-099/FIND-096),
##      giving the observability surface its intended typed-event shape
##      without breaking any existing Dictionary-shaped consumer.
##
## RNG consumption order (identical to the pre-extraction
## Resolution.resolve_weapon_attack(..., "ac") path this replaces, which was
## always invoked with active_defense="none" by run_round() — preserving
## bit-for-bit determinism, see tests/test_encounter_regression.gd):
##   1. RandomNumberPort.roll({"die": 20, "count": 1})         — attack roll
##   2. [hit only] RandomNumberPort.roll({"die": damage_die,
##      "count": 2 if crit else 1})                            — damage roll
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var use_case := ResolveActionUseCase.new(rng_port, event_sink, round_history)
##   var result: Dictionary = use_case.resolve(
##       combatant, action_economy, target, "Strike", round_number, cycle_index
##   )
##   # result -> {resolved: bool, target_defeated: bool, damage_final: int}

class_name ResolveActionUseCase
extends RefCounted

const RoundEventsClass = preload("res://core/rules/round_events.gd")
const HexMathClass     = preload("res://core/geometry/hex_math.gd")
const ResolutionClass  = preload("res://core/rules/resolution.gd")


## _PortRNGAdapter (FEAT-008 / US-008, CR-001) — internal adapter wrapping
## an injected RandomNumberPort (the dice_spec-shaped `roll(dice_spec)`
## contract — core/rules/random_port.gd) so it can be handed to
## core/rules/resolution.gd's Resolution constructor, which duck-types its
## injected `_rng` against the RNG-shaped `d20()` / `roll(die_size, count)`
## contract (core/rules/rng.gd). resolution.gd's own contract is NEVER
## changed by this adapter — every call this adapter makes is forwarded
## straight back out to the SAME injected RandomNumberPort instance, so the
## live interactive Strike path and every other resolution.gd caller
## (core/combat/encounter.gd, core/sim/simulator.gd, tests) now draw from
## ONE unified seeded RNG source rather than two independently-shaped ones.
class _PortRNGAdapter:
	var _port

	func _init(port) -> void:
		_port = port

	## d20() -> int — forwards to the injected port's own d20() (see
	## core/rules/random_port.gd's base-class convenience), which in turn
	## calls roll({"die": 20, "count": 1}) on the SAME concrete adapter
	## injected into this use case.
	func d20() -> int:
		return _port.d20()

	## roll(die_size, count) -> int — forwards to the injected port's
	## dice_spec-shaped roll(), reconstructing the {"die":.., "count":..}
	## Dictionary resolution.gd's damage/check rolls are expressed in terms
	## of die size + count, never a raw call to any engine RNG primitive.
	func roll(die_size: int, count: int) -> int:
		return _port.roll({"die": die_size, "count": count})


## Action names that are melee attacks and therefore subject to the
## hex_neighbors-based reach precondition (FEAT-003 / US-003). Only "Strike"
## exists as a melee action in the current ruleset; declared as a Set-like
## Array constant so future melee action names can be added in one place.
const _MELEE_ACTION_NAMES: Array = ["Strike"]

## Typed error code returned in ActionResult.error when a melee action is
## attempted against a target that is not one of the actor's 6 flat-top
## axial neighbors (core/geometry/hex_math.gd HexMath.hex_neighbors()). See
## api_contracts (resolve_action_use_case.execute precondition, US-003).
const ERR_TARGET_NOT_ADJACENT: String = "ERR_TARGET_NOT_ADJACENT"

## Typed error code returned in ActionResult.error when a RANGED Strike (a
## weapon whose Dictionary carries a "range_hexes" key — see
## _is_ranged_weapon()) is attempted against a target whose
## HexMath.hex_distance() from the actor exceeds the weapon's range_hexes
## (FEAT-140 / DEF-007 / FR-014, US-007). Mirrors ERR_TARGET_NOT_ADJACENT's
## contract exactly (checked before any action-budget spend, no side
## effects on rejection) — see api_contracts' TARGET_OUT_OF_REACH.
const ERR_TARGET_OUT_OF_REACH: String = "ERR_TARGET_OUT_OF_REACH"

## Typed error code returned in ActionResult.error when
## ActionEconomy.spend_action() fails because the acting combatant has no
## action budget remaining this round (the ALREADY_SPENT Result contract —
## core/rules/action_economy.gd). FEAT-125/FIND-121: previously this case
## returned a bare {"resolved": false, "ok": false} Dictionary with no typed
## error key; api_contracts documents ERR_NO_ACTION_REMAINING for this case
## and StrikeActionControl/RoundSession only ever branch on ok/resolved, so
## adding this key is backward compatible with both callers.
const ERR_NO_ACTION_REMAINING: String = "ERR_NO_ACTION_REMAINING"

## Typed error code returned in ActionResult.error when `target` does not
## exist (an empty Dictionary — the same "not found" sentinel already used
## by core/application/round_session.gd's `target.is_empty()` checks) or is
## already defeated (hp_current <= 0). FEAT-125/FIND-121. Checked BEFORE the
## melee reach precondition and BEFORE any action-budget spend, so a Strike
## against an invalid target never burns the actor's turn.
const ERR_TARGET_INVALID: String = "ERR_TARGET_INVALID"

## Typed error code returned in ActionResult.error when `active_combatant_id`
## is supplied and does not match the acting `combatant`'s identifier
## (FEAT-125/FIND-121). This is an OPT-IN precondition: pre-existing callers
## (StrikeActionControl, RoundSession) never pass `active_combatant_id`, so
## for them this check remains a no-op — preserving their contract exactly,
## per FIND-121's guardrail.
const ERR_NOT_ACTIVE_COMBATANT: String = "ERR_NOT_ACTIVE_COMBATANT"

var _random_number_port      ## RandomNumberPort — injected; never instantiated here (NFR-003)
var _event_sink_port         ## EventSinkPort — injected
var _round_history_port      ## RoundHistoryPort — injected
var _resolution               ## Resolution (core/rules/resolution.gd) — constructed once in
## _init() from a _PortRNGAdapter wrapping the injected RandomNumberPort
## (FEAT-008 / US-008, CR-001). ALL Strike resolution math lives in
## resolution.gd; this use case never re-implements it.


## _init(random_number_port, event_sink_port, round_history_port) — stores
## the injected ports. All three are duck-typed (no static port type on the
## parameters) so any object implementing the documented method contracts —
## whether or not it formally `extends` the port base class — may be
## substituted (test doubles in particular).
##
## Also constructs the single Resolution instance (core/rules/resolution.gd)
## this use case delegates ALL Strike math to (FEAT-008 / US-008, CR-001),
## backed by a _PortRNGAdapter wrapping `random_number_port` — so the exact
## same injected RandomNumberPort remains the sole source of randomness
## consumed by this use case, just reshaped to the RNG-duck-typed contract
## resolution.gd's constructor expects.
func _init(random_number_port, event_sink_port, round_history_port) -> void:
	_random_number_port = random_number_port
	_event_sink_port     = event_sink_port
	_round_history_port  = round_history_port
	_resolution          = ResolutionClass.new(_PortRNGAdapter.new(random_number_port))


## resolve(combatant, action_economy, target, action_name, round_number,
##         cycle_index) -> Dictionary
##
## combatant       — the acting combatant Dictionary (name, weapon, ...).
##                    MAY carry a "hex_coord" key (a core/geometry/hex_coord.gd
##                    HexCoord instance) — see the reach precondition below.
## action_economy  — the combatant's ActionEconomy instance for this round
##                    (CR-001 AC-1/AC-2/AC-3 shared budget owner).
## target          — the target combatant Dictionary (name, ac, hp_current).
##                    MAY carry a "hex_coord" key — see the reach precondition
##                    below.
## action_name     — String describing the action spent (e.g. "Strike");
##                    passed through to ActionEconomy.spend_action() metadata
##                    and recorded verbatim in the RoundHistoryEntry.
## round_number    — the current round number (1-based), stamped on all
##                    emitted events/history entries.
## cycle_index     — the AC-4 interleave cycle pass this action occurred in
##                    (0-based), stamped on the RoundHistoryEntry.
## active_combatant_id — OPTIONAL (FEAT-125/FIND-121). When non-empty, the
##                    acting `combatant`'s identifier (its "combatant_id" key,
##                    falling back to "name" — the same convention
##                    presentation/strike_action_control.gd's _target_id()
##                    uses) must match this value or the action is rejected
##                    with ERR_NOT_ACTIVE_COMBATANT. Defaults to "" (no
##                    check) so pre-existing callers (StrikeActionControl,
##                    RoundSession) that never pass this argument are
##                    completely unaffected.
##
## Preconditions are checked in this order, each with NO side effects on
## failure (no action-budget spend, no damage, no events, no history):
##   1. active-combatant check (only when active_combatant_id is non-empty)
##   2. target-validity check (target exists and is not already defeated)
##   3. melee reach check (FEAT-003/US-003, unchanged)
##   4. ActionEconomy.spend_action()
##
## Reach precondition (FEAT-003 / US-003, api_contracts
## resolve_action_use_case.execute): when action_name is a melee action (
## "Strike") AND both combatant and target carry "hex_coord" data, the
## target must be one of combatant.hex_coord's 6 flat-top axial neighbors
## (core/geometry/hex_math.gd HexMath.hex_neighbors()) or the action is
## rejected BEFORE any action-budget spend — see ERR_TARGET_NOT_ADJACENT
## below. When either side lacks hex_coord data (pre-existing callers that
## do not yet populate it), this precondition is a no-op — preserving the
## pre-FEAT-003 contract exactly.
##
## Ranged reach precondition (FEAT-140 / DEF-007 / FR-014, US-007): when the
## acting combatant's weapon Dictionary carries a "range_hexes" key (see
## _is_ranged_weapon()), the melee 6-neighbor check above is replaced by a
## HexMath.hex_distance() <= weapon.range_hexes check — the target may be
## anywhere within range_hexes hexes, not just adjacent. Out-of-range
## targets are rejected with ERR_TARGET_OUT_OF_REACH, with the exact same
## no-side-effects contract as ERR_TARGET_NOT_ADJACENT (no action-budget
## spend, no damage, no events, no history). Weapon Dictionaries without
## "range_hexes" (every pre-FEAT-140 melee fixture) are unaffected and keep
## going through the adjacency path above.
##
## Returns a Dictionary:
##   {resolved: false, ok: false, error: ERR_NOT_ACTIVE_COMBATANT}
##     — active_combatant_id was supplied and does not match combatant's
##       identifier. No action-budget spend, no damage applied, no events
##       emitted, no history recorded.
##   {resolved: false, ok: false, error: ERR_TARGET_INVALID}
##     — target does not exist (empty Dictionary) or is already defeated
##       (hp_current <= 0). No action-budget spend, no damage applied, no
##       events emitted, no history recorded.
##   {resolved: false, ok: false, error: ERR_TARGET_NOT_ADJACENT}
##     — melee Strike rejected: target is not adjacent to combatant. No
##       action-budget spend, no damage applied, no events emitted, no
##       history recorded.
##   {resolved: false, ok: false, error: ERR_TARGET_OUT_OF_REACH}
##     — ranged Strike rejected (FEAT-140): target's hex_distance from
##       combatant exceeds the weapon's range_hexes. No action-budget
##       spend, no damage applied, no events emitted, no history recorded.
##   {resolved: false, ok: false, error: ERR_NO_ACTION_REMAINING}
##     — ActionEconomy.spend_action() failed (ALREADY_SPENT contract
##       violation); no damage applied, no events emitted, no history
##       recorded. The caller must skip this combatant for the cycle.
##   {resolved: true, ok: true, event: RoundEvents.AttackEvent,
##    target_defeated: bool, damage_final: int}
##     — the action was spent and the Strike resolved (hit or miss);
##       target_defeated is true iff target.hp_current transitioned to <= 0
##       as a result of this resolution. "event" carries the same
##       AttackEvent instance emitted via EventSinkPort.
func resolve(
	combatant: Dictionary,
	action_economy,
	target: Dictionary,
	action_name: String,
	round_number: int,
	cycle_index: int,
	active_combatant_id: String = ""
) -> Dictionary:
	if active_combatant_id != "" and _combatant_identifier(combatant) != active_combatant_id:
		return {"resolved": false, "ok": false, "error": ERR_NOT_ACTIVE_COMBATANT}

	if _is_target_invalid(target):
		return {"resolved": false, "ok": false, "error": ERR_TARGET_INVALID}

	if _is_melee_action(action_name) and _requires_reach_check(combatant, target):
		if _is_ranged_weapon(combatant):
			if not _is_in_range(combatant, target):
				return {"resolved": false, "ok": false, "error": ERR_TARGET_OUT_OF_REACH}
		elif not _is_adjacent(combatant, target):
			return {"resolved": false, "ok": false, "error": ERR_TARGET_NOT_ADJACENT}

	var spend_result: Dictionary = action_economy.spend_action({"name": action_name, "traits": []})
	if not spend_result.get("success", false):
		return {"resolved": false, "ok": false, "error": ERR_NO_ACTION_REMAINING}

	var weapon: Dictionary = combatant.get("weapon", {})
	var strike_result: Dictionary = _resolve_strike(combatant, target, weapon)

	var damage: int = strike_result.get("damage_final", 0)
	if damage > 0:
		target["hp_current"] = target.get("hp_current", 0) - damage

	# ── FEAT-009 / US-009 / FR-014 (ADR-003): snapshot the acting combatant's
	# ActionBudget immediately after the spend_action() call above, so
	# StatusPanelView can project a post-resolution "remaining/Spent" readout
	# without recomputing anything itself. ──────────────────────────────────
	var actor_updated_action_budget: Dictionary = {
		"remaining": spend_result.get("remaining", -1),
		"spent":     action_economy.is_spent(),
	}

	var attack_event = RoundEventsClass.AttackEvent.new(
		round_number,
		combatant.get("name", ""),
		target.get("name", ""),
		strike_result.get("roll_total", 0),
		"ac",
		strike_result.get("defense_value", 0),
		strike_result.get("hit", false),
		strike_result.get("crit", false),
		damage,
		actor_updated_action_budget
	)
	_event_sink_port.emit(attack_event)

	var target_defeated: bool = target.get("hp_current", 0) <= 0
	if target_defeated:
		var defeated_event = RoundEventsClass.CombatantDefeatedEvent.new(
			round_number, target.get("name", ""), combatant.get("name", "")
		)
		_event_sink_port.emit(defeated_event)

	var history_entry = RoundEventsClass.RoundHistoryEntry.new(
		round_number,
		cycle_index,
		combatant.get("name", ""),
		action_name,
		spend_result.get("remaining", -1)
	)

	_round_history_port.append({
		"attacker":         combatant,
		"action":           action_name,
		"target":           target,
		"roll":             strike_result.get("roll_total", 0),
		"damage_final":     damage,
		"budget_remaining": spend_result.get("remaining", -1),
		"round":            round_number,
		"cycle_index":       cycle_index,
		"entry":            history_entry
	})

	return {
		"resolved":        true,
		"ok":              true,
		"event":           attack_event,
		"target_defeated": target_defeated,
		"damage_final":    damage
	}


## _is_melee_action(action_name) -> bool — true when action_name names a
## melee action subject to the reach precondition (FEAT-003 / US-003).
func _is_melee_action(action_name: String) -> bool:
	return _MELEE_ACTION_NAMES.has(action_name)


## _is_target_invalid(target) -> bool — true when `target` does not exist
## (an empty Dictionary — the same "not found" sentinel RoundSession already
## checks via `target.is_empty()`) or is already defeated
## (hp_current <= 0). FEAT-125/FIND-121.
func _is_target_invalid(target: Dictionary) -> bool:
	if target.is_empty():
		return true
	return target.get("hp_current", 0) <= 0


## _combatant_identifier(combatant) -> String — the same "combatant_id",
## falling back to "name" convention used by
## presentation/strike_action_control.gd's _target_id(), so
## active_combatant_id comparisons (FEAT-125/FIND-121) use one consistent
## identity rule across Presentation and Application.
func _combatant_identifier(combatant: Dictionary) -> String:
	return combatant.get("combatant_id", combatant.get("name", ""))


## _requires_reach_check(combatant, target) -> bool — the reach precondition
## only applies when BOTH Dictionaries carry positional "hex_coord" data
## (a core/geometry/hex_coord.gd HexCoord instance). Pre-existing callers
## (e.g. core/combat/encounter.gd) do not yet populate hex_coord on their
## combatant Dictionaries; for those, this use case remains a no-op on reach
## — preserving the pre-FEAT-003 contract exactly (backward compatibility).
func _requires_reach_check(combatant: Dictionary, target: Dictionary) -> bool:
	return combatant.get("hex_coord", null) != null and target.get("hex_coord", null) != null


## _is_adjacent(combatant, target) -> bool — true iff target.hex_coord is one
## of the 6 flat-top axial neighbors of combatant.hex_coord
## (core/geometry/hex_math.gd HexMath.hex_neighbors(), US-002/US-003). No
## diagonal-cost concept exists on a hex grid — all 6 neighbors are equally
## valid melee-reach hexes.
func _is_adjacent(combatant: Dictionary, target: Dictionary) -> bool:
	var neighbors: Array = HexMathClass.hex_neighbors(combatant["hex_coord"])
	for neighbor in neighbors:
		if neighbor.equals(target["hex_coord"]):
			return true
	return false


## _is_ranged_weapon(combatant) -> bool — true iff the acting combatant's
## "weapon" Dictionary carries a "range_hexes" key (FEAT-140 / DEF-007).
## Weapon Dictionaries built from melee WeaponResource fixtures never set
## this key (core/model/weapon_resource.gd's range_hexes field defaults to
## 1 — melee adjacency — but callers that assemble the Dictionary, e.g.
## MainScene.gd's _build_party_combatant()/_build_enemy_combatant(), only
## copy fields they explicitly wire up), so this is a no-op/false for every
## pre-FEAT-140 caller — preserving the melee _is_adjacent() path exactly.
## A ranged weapon's Dictionary is expected to include "range_hexes" (the
## WeaponResource field of the same name) so this use case can select the
## distance-based reach check below instead of the 6-neighbor melee check.
func _is_ranged_weapon(combatant: Dictionary) -> bool:
	var weapon: Dictionary = combatant.get("weapon", {})
	return weapon.has("range_hexes")


## _is_in_range(combatant, target) -> bool — true iff the target's
## HexMath.hex_distance() from the combatant is within the acting weapon's
## range_hexes (inclusive), reusing the SAME hex distance math
## (core/geometry/hex_math.gd HexMath.hex_distance()) as melee's
## _is_adjacent() and core/rules/movement.gd — never a re-derived notion of
## range (FEAT-140 / DEF-007 / FR-014, US-007).
func _is_in_range(combatant: Dictionary, target: Dictionary) -> bool:
	var weapon: Dictionary = combatant.get("weapon", {})
	var range_hexes: int = weapon.get("range_hexes", 1)
	var distance: int = HexMathClass.hex_distance(combatant["hex_coord"], target["hex_coord"])
	return distance <= range_hexes


## _resolve_strike(attacker, target, weapon) -> Dictionary — internal helper
## (FEAT-008 / US-008, CR-001): delegates the ENTIRE Strike resolution
## (attack roll, passive AC defense, Off-Guard reduction, crit-by-10 check,
## damage roll) to core/rules/resolution.gd's Resolution.resolve_weapon_attack(),
## called exactly as `resolve_weapon_attack(attacker, target, weapon, "ac",
## "none", {})` — the SAME passive-AC-only, no-active-defense path
## run_round()/the live interactive Strike UX has always exercised. There is
## NO hand-rolled attack-roll/Off-Guard/crit-threshold math in this use case
## any more — resolution.gd is the single source of that logic (CR-001), and
## this call is rolled via the SAME injected RandomNumberPort that backs
## `_resolution` (see the _PortRNGAdapter wrapping it in _init()), never a
## directly-held RNG instance.
##
## Off-Guard (FEAT-153 / US-015 / FR-016, resolves FIND-142/FIND-145) and the
## crit-by-10-or-more threshold are therefore applied by resolution.gd
## itself, identically to every other resolve_weapon_attack() caller — see
## tests/characterization/test_strike_characterization.gd for the pinned
## behavior this delegation is required to preserve byte-for-byte.
##
## Returns resolution.gd's full result Dictionary — this use case only reads
## "roll_total", "hit", "crit", "damage_final", and "defense_value" out of
## it, but every key resolve_weapon_attack() documents is present.
func _resolve_strike(attacker: Dictionary, target: Dictionary, weapon: Dictionary) -> Dictionary:
	return _resolution.resolve_weapon_attack(attacker, target, weapon, "ac", "none", {})
