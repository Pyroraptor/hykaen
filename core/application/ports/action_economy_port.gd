## core/application/ports/action_economy_port.gd — ActionEconomyPort
## (iteration K FEAT-007 / US-007, ADR-005)
##
## Application layer (Clean Architecture): documents the spend contract
## core/rules/action_economy.gd's ActionEconomy already implements
## (spend_action(action_metadata)/spend_reaction()/is_spent()/get_remaining())
## — mirrors this project's established Protocol-style port pattern
## (core/application/ports/reaction_chooser_port.gd,
## core/application/ports/reaction_window_port.gd): a base class documenting
## the contract; concrete adapters `extends` it (or simply duck-type it,
## this project's established fallback for lightweight adapters — e.g.
## core/application/resolve_action_use_case.gd's own `action_economy`
## parameter carries no static port type at all).
##
## Also HOUSES the one concrete adapter this feature needs
## (ReactionPaidActionEconomy, below) — the mechanism that lets an
## UNMODIFIED core/application/resolve_action_use_case.gd's resolve() (the
## SAME consolidated resolve_action_use_case/resolve_weapon_attack path an
## ordinary Strike takes, per ADR-005) pay an Opportunistic Strike's cost via
## the reactor's REACTION budget rather than its action budget.
##
## The gap this closes: resolve()'s own private _check_preconditions_and_spend()
## always calls `action_economy.spend_action(...)` internally (see that
## file's file-level doc) — never spend_reaction() — because it has no
## notion of "this Strike is actually paid for by a reaction". Modifying
## resolve_action_use_case.gd itself to special-case a reaction-paid Strike
## is explicitly OUT of this feature's file scope (every existing pinned
## call-site/test — e.g. tests/gut/test_resolve_action_use_case_active_defense.gd's
## call-site arg-count audit — must stay byte-for-byte untouched). Instead,
## ReactionPaidActionEconomy sits BETWEEN resolve() and the reactor's REAL,
## live core/rules/action_economy.gd ActionEconomy instance, forwarding
## every spend_action() call it receives straight through to the wrapped
## instance's OWN spend_reaction() — so the ledger debit that ACTUALLY lands
## on the reactor's shared per-round budget is a genuine spend_reaction()
## call (verifiable via a spy substituted for the wrapped instance — this
## feature's test_criteria "reactor's reaction resource is verified spent
## via spend_reaction (not spend_action)"), while resolve_action_use_case.gd
## itself is never modified and never learns anything unusual happened: from
## its point of view it just called spend_action() on "an ActionEconomy" and
## got back the ordinary Result-style Dictionary.
##
## is_spent()/get_remaining() are pure reads and are forwarded VERBATIM to
## the wrapped instance (no translation) — the spend_action()->spend_reaction()
## substitution above is the ONLY real behavioral difference from a bare
## pass-through, so every OTHER read resolve_action_use_case.gd performs
## against this adapter (e.g. _finalize_strike_result()'s
## `action_economy.is_spent()` snapshot) reflects the reactor's REAL,
## live budget state exactly as it would through the unwrapped instance.
##
## Consumed by core/application/use_cases/resolve_stride_use_case.gd's
## ResolveStrideUseCase — see that file's own FEAT-007 doc for the full
## "resolve an Opportunistic Strike through the SAME consolidated resolution
## path, paid via spend_reaction" call sequence this adapter is the seam
## for.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var reactor_action_economy := ActionEconomy.new()  # the reactor's REAL, live economy
##   var paid_economy := ActionEconomyPort.ReactionPaidActionEconomy.new(reactor_action_economy)
##   var result: Dictionary = resolve_action_use_case.resolve(
##       reactor, paid_economy, mover, "Strike", round_number, cycle_index
##   )
##   # reactor_action_economy.get_remaining() is now one lower -- via
##   # spend_reaction(), never spend_action().

class_name ActionEconomyPort
extends RefCounted


## spend_action(action_metadata) -> Dictionary — abstract; concrete adapters
## MUST override. Mirrors core/rules/action_economy.gd's
## ActionEconomy.spend_action() Result-style contract
## ({success/ok, remaining/budget_remaining, ...}).
func spend_action(_action_metadata: Dictionary) -> Dictionary:
	push_error("ActionEconomyPort.spend_action() is abstract — override in a concrete adapter")
	return {"success": false, "ok": false}


## spend_reaction() -> Dictionary — abstract; concrete adapters MUST
## override. Mirrors ActionEconomy.spend_reaction()'s identical Result-style
## contract.
func spend_reaction() -> Dictionary:
	push_error("ActionEconomyPort.spend_reaction() is abstract — override in a concrete adapter")
	return {"success": false, "ok": false}


## is_spent() -> bool — abstract; concrete adapters MUST override.
func is_spent() -> bool:
	return false


## get_remaining() -> int — abstract; concrete adapters MUST override.
func get_remaining() -> int:
	return 0


## ReactionPaidActionEconomy — see class-level doc above: the ONE concrete
## adapter this feature needs, wrapping a reactor's REAL, live
## core/rules/action_economy.gd ActionEconomy instance (duck-typed —
## `_wrapped` carries no static type, so this file stays free of a
## core/rules/ import, mirroring core/application/ports/reaction_chooser_port.gd's
## own "documents the contract, never imports a concrete engine/rules type"
## discipline).
class ReactionPaidActionEconomy:
	extends RefCounted

	var _wrapped  ## the reactor's REAL ActionEconomy instance — injected,
	## never constructed here.


	func _init(wrapped) -> void:
		_wrapped = wrapped


	## spend_action(action_metadata) -> Dictionary — THE substitution this
	## adapter exists for: forwards to `_wrapped.spend_reaction()`, NEVER
	## `_wrapped.spend_action()` — see class-level doc. `action_metadata` is
	## accepted (matching the contract resolve_action_use_case.gd's
	## _check_preconditions_and_spend() calls with, e.g.
	## {"name": "Strike", "traits": []}) but never inspected — spend_reaction()
	## takes no arguments of its own.
	func spend_action(_action_metadata: Dictionary) -> Dictionary:
		return _wrapped.spend_reaction()


	## spend_reaction() -> Dictionary — forwarded verbatim. An Opportunistic
	## Strike's own resolution never chains a second reaction spend through
	## this method (resolve_action_use_case.gd only ever calls spend_action()
	## on its injected `action_economy` argument), but it is implemented for
	## contract completeness / duck-typing safety, matching
	## core/application/ports/action_economy_port.gd's own abstract contract
	## above.
	func spend_reaction() -> Dictionary:
		return _wrapped.spend_reaction()


	## is_spent() -> bool — forwarded verbatim (a pure read of the reactor's
	## REAL, live budget state).
	func is_spent() -> bool:
		return _wrapped.is_spent()


	## get_remaining() -> int — forwarded verbatim (a pure read of the
	## reactor's REAL, live budget state).
	func get_remaining() -> int:
		return _wrapped.get_remaining()
