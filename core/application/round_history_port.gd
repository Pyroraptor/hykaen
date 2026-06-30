## core/application/round_history_port.gd — RoundHistoryPort (FEAT-098 / US-005)
##
## Application layer (Clean Architecture): defines the contract
## ResolveActionUseCase/RunRoundUseCase depend on to persist and retrieve the
## per-action audit trail (one entry per resolved action/reaction, carrying
## the post-spend budget_remaining and the AC-4 cycle_index it occurred in)
## — abstracting the _round_history Array currently owned by
## core/combat/encounter.gd. A future iteration could swap this in-memory
## adapter for a file/save-game-backed repository without touching the
## use cases (dependency-inversion payoff named in the CR-001 design notes).
##
## GDScript has no formal interface/Protocol keyword, so this base class
## documents the contract and provides abstract append()/get_history()
## methods that concrete adapters MUST override. Concrete adapters extend
## this script directly (`extends "res://core/application/round_history_port.gd"`).
##
## Contract:
##   append(entry: Dictionary) -> void
##     Records one resolved action/reaction. Entry shape (unchanged from the
##     pre-extraction contract):
##       {attacker: Dictionary, action: String, target: Dictionary, roll: int,
##        damage_final: int, budget_remaining: int, round: int, cycle_index: int}
##   get_history() -> Array
##     Returns the full Array of entries appended so far (across the entire
##     encounter, not scoped to a single round — callers filter by "round"
##     themselves, matching the pre-extraction get_round_history() contract).
##
## Domain purity boundary (ADR-001): this file extends RefCounted only — no
## Node/Control/SceneTree inheritance — matching the existing port pattern
## established by core/rules/random_port.gd.
##
## Usage example:
##   var history: RoundHistoryPort = _RoundHistoryAdapter.new(round_history_array)
##   history.append({"attacker": ..., "round": 1, "cycle_index": 0, ...})
##   var all_entries: Array = history.get_history()

class_name RoundHistoryPort
extends RefCounted


## append(entry) -> void — abstract; concrete adapters MUST override.
func append(entry: Dictionary) -> void:
	push_error("RoundHistoryPort.append() is abstract — override in a concrete adapter")


## get_history() -> Array — abstract; concrete adapters MUST override.
func get_history() -> Array:
	push_error("RoundHistoryPort.get_history() is abstract — override in a concrete adapter")
	return []
