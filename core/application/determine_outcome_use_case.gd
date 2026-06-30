## core/application/determine_outcome_use_case.gd — DetermineOutcomeUseCase
## (FEAT-098 / US-003/US-004/US-005, CR-001 AC-4)
##
## Application layer (Clean Architecture): the SINGLE authority for
## win/loss/draw classification, extracted out of core/combat/encounter.gd
## so RunRoundUseCase (and any other future caller, e.g. core/sim/simulator.gd)
## reads the outcome from one place rather than re-deriving it independently
## (preventing divergent error states between the round loop and any
## aggregate/reporting logic — see design notes "error_handling" section).
##
## Pure orchestration/classification logic — no ports, no side effects, no
## RNG, no event emission. Operates purely on Combatant-shaped Dictionaries
## (the same {name, hp_current, ...} shape used throughout core/combat).
##
## Classification rules (mirrors the pre-extraction inline logic in
## core/combat/encounter.gd's run_round(), preserved bit-for-bit):
##   - both sides have >=1 living combatant            -> ""      (undecided)
##   - neither side has a living combatant              -> "DRAW"
##   - enemies side has zero living combatants           -> "won"
##   - party side has zero living combatants (and enemies
##     side still has >=1 living combatant)               -> "lost"
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O.
##
## Usage example:
##   var use_case := DetermineOutcomeUseCase.new()
##   var outcome: String = use_case.classify(party_array, enemies_array)
##   # "" | "won" | "lost" | "DRAW"

class_name DetermineOutcomeUseCase
extends RefCounted


## classify(party, enemies) -> String
##
## party    — Array of combatant Dictionaries on the player side.
## enemies  — Array of combatant Dictionaries on the enemy side.
##
## Returns:
##   ""     — both sides have at least one living combatant; undecided.
##   "DRAW" — neither side has a living combatant.
##   "won"  — the enemies side has been fully defeated (party side need not
##            be checked further — mirrors the pre-extraction "check
##            all_enemies_dead first" precedence).
##   "lost" — the party side has been fully defeated (enemies side still has
##            a living combatant; the "DRAW" case above already covers the
##            both-dead scenario).
func classify(party: Array, enemies: Array) -> String:
	var living_enemies: bool = _has_living(enemies)
	var living_party: bool = _has_living(party)

	if living_enemies and living_party:
		return ""

	if not living_enemies and not living_party:
		return "DRAW"

	if not living_enemies:
		return "won"

	return "lost"


## _has_living(combatants) -> bool — true if at least one combatant in the
## Array has hp_current > 0.
func _has_living(combatants: Array) -> bool:
	for c in combatants:
		if c.get("hp_current", 0) > 0:
			return true
	return false
