## core/application/ports/round_energy_pool_port.gd — RoundEnergyPoolPort
## (FEAT-005 / US-005; FR-004, ADR-003)
##
## Application layer (Clean Architecture): documents the contract
## BeginCastUseCase (core/application/use_cases/begin_cast_use_case.gd)
## depends on to pay a spell's up-front Channeling energy cost — mirrors
## this project's established Protocol-style port pattern
## (core/application/ports/reaction_window_port.gd,
## core/application/ports/action_economy_port.gd): a base class documenting
## the abstract contract; concrete adapters either `extends` it or simply
## duck-type it.
##
## Contract (design notes' api_contracts #3):
##   reserve(caster_id, amount) -> bool
##     Atomically checks the caster's round-scoped energy pool balance >=
##     amount and, if so, decrements it by `amount`, returning true. No
##     partial reservation — a failed check leaves the pool untouched and
##     returns false. There is deliberately NO public refund() — up-front
##     payment is non-refundable by design (ADR-003, mirrored by
##     core/application/round_session.gd's own EnergyPool doc).
##   balance(caster_id) -> int
##     A pure, read-only query of the caster's CURRENT pool balance —
##     consulted by BeginCastUseCase.availability() (US-004 contract #1's
##     "round energy pool balance >= that spell's energy_cost" half) WITHOUT
##     mutating anything. Design notes' observability section: "the port
##     shape (RoundEnergyPoolPort) already supports a query method for this
##     without new ports."
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.

class_name RoundEnergyPoolPort
extends RefCounted


## reserve(caster_id, amount) -> bool — abstract; concrete adapters MUST
## override.
func reserve(_caster_id: String, _amount: int) -> bool:
	push_error("RoundEnergyPoolPort.reserve() is abstract — override in a concrete adapter")
	return false


## balance(caster_id) -> int — abstract; concrete adapters MUST override.
func balance(_caster_id: String) -> int:
	push_error("RoundEnergyPoolPort.balance() is abstract — override in a concrete adapter")
	return 0


## SessionEnergyPoolAdapter — the ONE concrete adapter this feature needs,
## wrapping a live core/application/round_session.gd RoundSession instance
## (duck-typed — `_session` carries no static type, so this file stays free
## of a core/application/round_session.gd import, mirroring
## core/application/ports/action_economy_port.gd's ReactionPaidActionEconomy
## "duck-typed wrapped collaborator" convention exactly) plus the SPECIFIC
## caster (`_caster`, also duck-typed — expected to expose display_id() and
## spellcasting_attribute_score, core/domain/combatant.gd's own established
## identity convention) this adapter reserves/reads energy for.
##
## `caster_id` arguments on reserve()/balance() are accepted (matching the
## RoundEnergyPoolPort contract so a caller/test can construct one adapter
## per port-contract call) but not otherwise consulted — this adapter is
## already bound to one caster at construction time, mirroring
## ReactionPaidActionEconomy's own "wraps one specific instance" shape.
##
## Delegates to core/application/round_session.gd's RoundSession.
## get_energy_pool(caster) (creating the caster's EnergyPool on first access,
## capacity resolved from spellcasting_attribute_score — see that method's
## own doc) for the underlying core/domain/energy_pool.gd EnergyPool, then
## implements the ATOMIC check-then-decrement reserve() semantics on top of
## it — EnergyPool.add() itself always clamps/succeeds, so the "insufficient
## balance -> false, no mutation" contract lives here, in the adapter, not in
## the domain value object.
class SessionEnergyPoolAdapter:
	extends RefCounted

	var _session  ## the live RoundSession — injected, never constructed here.
	var _caster   ## the specific caster this adapter reserves/reads for.


	func _init(session, caster) -> void:
		_session = session
		_caster = caster


	## reserve(caster_id, amount) -> bool — the atomic check-then-decrement
	## this port's contract requires. `amount <= 0` always succeeds without
	## touching the pool (a zero-cost spell, e.g. Fire Bolt/Channel today,
	## reserves nothing).
	func reserve(_caster_id: String, amount: int) -> bool:
		if amount <= 0:
			return true
		var pool = _session.get_energy_pool(_caster)
		if pool.current < amount:
			return false
		pool.add(-amount)
		return true


	## balance(caster_id) -> int — a pure read of the caster's current pool
	## balance, creating the pool (at its full resolved capacity, still
	## empty/current=0 — see EnergyPool's own doc) on first access exactly
	## like reserve() does, never a fabricated/guessed value.
	func balance(_caster_id: String) -> int:
		return _session.get_energy_pool(_caster).current
