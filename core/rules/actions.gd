## core/rules/actions.gd — Actions (WAIT: idle-turn resolvable action)
## (US-001 / FR-001, ADR-010)
##
## Domain layer (ADR-001): pure GDScript — no Node/Control/CanvasItem
## inheritance, no engine lifecycle callbacks, no engine I/O. A stateless
## namespace of `static func`s (matching the existing pure-function
## convention established by core/geometry/hex_math.gd, core/rules/movement.gd,
## and core/rules/flanking.gd).
##
## WAIT is the explicit, resolvable "do nothing productive this turn" action
## a combatant takes when it has no OTHER resolvable action available (most
## commonly an Enemy whose nearest living target is permanently out of reach
## and cannot be closed into range this turn — e.g. it has already used its
## Movement-trait action, or no legal Stride destination exists that gets it
## any closer). Unlike Strike/Stride, WAIT:
##   - carries NO Movement trait — it never trips/consumes the per-turn
##     Movement-trait gate (core/rules/action_economy.gd's _movement_used) a
##     Step/Stride shares, so a combatant that WAITs this turn is free to
##     Step/Stride on a LATER turn once start_of_turn() clears that gate
##     again, exactly as normal.
##   - carries NO target — it never reads or mutates another combatant's
##     state (no HP change, no event tied to a specific opponent). It is a
##     pure action-budget spend.
##
## WAIT spends exactly one action from the SAME per-round ActionEconomy
## budget every other resolvable action draws from (CR-001 AC-1/AC-2/AC-3)
## via ActionEconomy.spend_action() — never a parallel/bespoke budget path.
## This is the round-termination guarantee this feature exists for (US-001 /
## FR-001, ADR-010): an idle/unreachable combatant that keeps WAITing still
## depletes its action budget by exactly 1 per turn, so it becomes Spent
## within ActionEconomy.MAX_BUDGET (7) of its OWN turns even if it can never
## reach or find a target this round — e.g. a kiting 1v1 where the pursuer
## can never close the distance. core/application/round_session.gd's
## advance_ai_turn() is the caller that resolves core/combat/ai.gd's
## null-action AI sentinel ({"action_type": "", ...}) through resolve_wait()
## below, rather than merely force-advancing the turn cursor with the
## combatant's budget left untouched (the pre-existing behavior, which never
## guaranteed the combatant would ever become Spent).
##
## Usage:
##   var result := Actions.resolve_wait(action_economy)
##   # result -> {success: true, remaining: int, ok: true, budget_remaining: int}
##   #        or {success: false, error: "Spent", ..., ok: false, reason: "ALREADY_SPENT"}
class_name Actions

## WAIT_ACTION_NAME — the action_metadata["name"] label a WAIT resolution is
## tagged with when spending its action (mirrors "Strike"/"Stride" being the
## respective name tags those actions already use), so any observer keyed
## off action name (e.g. a future RoundHistoryEntry) can distinguish a WAIT
## from every other resolvable action.
const WAIT_ACTION_NAME: String = "Wait"

## resolve_wait(action_economy) -> Dictionary
##
## Resolves one WAIT for `action_economy`: spends exactly ONE action via
## ActionEconomy.spend_action() with WAIT's action_metadata
## ({"name": WAIT_ACTION_NAME, "traits": []} — no "Movement" trait, per the
## file-level doc above). Returns the SAME Result-style Dictionary
## spend_action() already returns (success/error/remaining/ok/reason/
## budget_remaining) — WAIT introduces no new result shape of its own, and
## calls spend_action() exactly once per resolve_wait() call (no retries, no
## additional collaborator calls).
static func resolve_wait(action_economy) -> Dictionary:
	return action_economy.spend_action({"name": WAIT_ACTION_NAME, "traits": []})
