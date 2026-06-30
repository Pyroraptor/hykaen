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
##      transitions to <= 0) events via EventSinkPort, in that order.
##   5. Append one RoundHistoryEntry-shaped Dictionary (with the post-spend
##      budget_remaining and the caller-supplied cycle_index) via
##      RoundHistoryPort.
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

var _random_number_port      ## RandomNumberPort — injected; never instantiated here (NFR-003)
var _event_sink_port         ## EventSinkPort — injected
var _round_history_port      ## RoundHistoryPort — injected


## _init(random_number_port, event_sink_port, round_history_port) — stores
## the injected ports. All three are duck-typed (no static port type on the
## parameters) so any object implementing the documented method contracts —
## whether or not it formally `extends` the port base class — may be
## substituted (test doubles in particular).
func _init(random_number_port, event_sink_port, round_history_port) -> void:
	_random_number_port = random_number_port
	_event_sink_port     = event_sink_port
	_round_history_port  = round_history_port


## resolve(combatant, action_economy, target, action_name, round_number,
##         cycle_index) -> Dictionary
##
## combatant       — the acting combatant Dictionary (name, weapon, ...).
## action_economy  — the combatant's ActionEconomy instance for this round
##                    (CR-001 AC-1/AC-2/AC-3 shared budget owner).
## target          — the target combatant Dictionary (name, ac, hp_current).
## action_name     — String describing the action spent (e.g. "Strike");
##                    passed through to ActionEconomy.spend_action() metadata
##                    and recorded verbatim in the RoundHistoryEntry.
## round_number    — the current round number (1-based), stamped on all
##                    emitted events/history entries.
## cycle_index     — the AC-4 interleave cycle pass this action occurred in
##                    (0-based), stamped on the RoundHistoryEntry.
##
## Returns a Dictionary:
##   {resolved: false}
##     — ActionEconomy.spend_action() failed (ALREADY_SPENT contract
##       violation); no damage applied, no events emitted, no history
##       recorded. The caller must skip this combatant for the cycle.
##   {resolved: true, target_defeated: bool, damage_final: int}
##     — the action was spent and the Strike resolved (hit or miss);
##       target_defeated is true iff target.hp_current transitioned to <= 0
##       as a result of this resolution.
func resolve(
	combatant: Dictionary,
	action_economy,
	target: Dictionary,
	action_name: String,
	round_number: int,
	cycle_index: int
) -> Dictionary:
	var spend_result: Dictionary = action_economy.spend_action({"name": action_name, "traits": []})
	if not spend_result.get("success", false):
		return {"resolved": false}

	var weapon: Dictionary = combatant.get("weapon", {})
	var strike_result: Dictionary = _resolve_strike(combatant, target, weapon)

	var damage: int = strike_result.get("damage_final", 0)
	if damage > 0:
		target["hp_current"] = target.get("hp_current", 0) - damage

	_event_sink_port.emit({
		"type":          "attack",
		"round":         round_number,
		"attacker_name": combatant.get("name", ""),
		"target_name":   target.get("name", ""),
		"roll":          strike_result.get("roll_total", 0),
		"defense_type":  "ac",
		"defense_value": strike_result.get("defense_value", 0),
		"hit":           strike_result.get("hit", false),
		"crit":          strike_result.get("crit", false),
		"damage_final":  damage
	})

	var target_defeated: bool = target.get("hp_current", 0) <= 0
	if target_defeated:
		_event_sink_port.emit({
			"type":        "combatant_defeated",
			"round":       round_number,
			"name":        target.get("name", ""),
			"defeated_by": combatant.get("name", "")
		})

	_round_history_port.append({
		"attacker":         combatant,
		"action":           action_name,
		"target":           target,
		"roll":             strike_result.get("roll_total", 0),
		"damage_final":     damage,
		"budget_remaining": spend_result.get("remaining", -1),
		"round":            round_number,
		"cycle_index":       cycle_index
	})

	return {
		"resolved":        true,
		"target_defeated": target_defeated,
		"damage_final":    damage
	}


## _resolve_strike(attacker, target, weapon) -> Dictionary — internal helper:
## the minimal passive-AC-defense Strike math exercised by run_round() (no
## active defenses; mirrors core/rules/resolution.gd's
## resolve_weapon_attack(..., "ac", "none", {}) path exactly), rolled via the
## injected RandomNumberPort instead of a directly-held RNG instance.
##
## Returns {roll_total: int, hit: bool, crit: bool, damage_final: int,
##          defense_value: int}.
func _resolve_strike(attacker: Dictionary, target: Dictionary, weapon: Dictionary) -> Dictionary:
	var raw: int = _random_number_port.roll({"die": 20, "count": 1})
	var attribute_mod: int = attacker.get(weapon["damage_modifier_attribute"], 0)
	var roll_total: int = raw + attribute_mod + weapon["proficiency_bonus"]

	var defense_value: int = target["ac"]
	var hit: bool = roll_total >= defense_value
	var crit: bool = hit and (roll_total - defense_value) >= 10

	var damage_final: int = 0
	if hit:
		var damage_die: int = weapon["damage_die"]
		if crit:
			damage_final = _random_number_port.roll({"die": damage_die, "count": 2}) + attribute_mod * 2
		else:
			damage_final = _random_number_port.roll({"die": damage_die, "count": 1}) + attribute_mod

	return {
		"roll_total":     roll_total,
		"hit":            hit,
		"crit":           crit,
		"damage_final":   damage_final,
		"defense_value":  defense_value
	}
