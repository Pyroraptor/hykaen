extends GutTest
## tests/test_determine_outcome_use_case.gd
##
## GUT test suite for FEAT-098 (FIND-096): core/application/determine_outcome_use_case.gd
## — win/loss/draw classification extracted out of core/combat/encounter.gd's
## run_round() into the Application layer, as the SINGLE authority other
## components (RunRoundUseCase, and in turn encounter.gd) must read the
## outcome from.
##
## Validates classify(party, enemies) matches the prior inline logic for
## every HP/Spent permutation:
##   - both sides have >=1 living combatant            -> ""      (undecided)
##   - neither side has a living combatant               -> "DRAW"
##   - enemies side has zero living combatants            -> "won"
##   - party side has zero living combatants (enemies
##     still has >=1 living combatant)                     -> "lost"
##
## "Spent" (ActionEconomy.is_spent()) permutations are explicitly exercised
## to demonstrate that outcome classification depends ONLY on hp_current —
## never on the action-economy/Spent state of any combatant (Spent affects
## ROUND TERMINATION via RunRoundUseCase, not WIN/LOSS classification).

const DetermineOutcomeUseCaseClass = preload("res://core/application/determine_outcome_use_case.gd")
const ActionEconomyClass           = preload("res://core/rules/action_economy.gd")


func _living(p_name: String) -> Dictionary:
	return {"name": p_name, "hp_current": 10}


func _dead(p_name: String) -> Dictionary:
	return {"name": p_name, "hp_current": 0}


# ══════════════════════════════════════════════════════════════════════════════
# Single-combatant-per-side permutations.
# ══════════════════════════════════════════════════════════════════════════════

func test_both_sides_living_is_undecided() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([_living("Titus")], [_living("Skeleton")])
	assert_eq(result, "", "Both sides alive must classify as undecided ('')")


func test_all_enemies_dead_is_won() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([_living("Titus")], [_dead("Skeleton")])
	assert_eq(result, "won", "All enemies dead, party alive must classify as 'won'")


func test_all_party_dead_is_lost() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([_dead("Titus")], [_living("Skeleton")])
	assert_eq(result, "lost", "All party dead, enemies alive must classify as 'lost'")


func test_both_sides_dead_is_draw() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([_dead("Titus")], [_dead("Skeleton")])
	assert_eq(result, "DRAW", "Both sides dead must classify as 'DRAW'")


# ══════════════════════════════════════════════════════════════════════════════
# Empty-array permutations (zero combatants on a side — treated identically
# to "no living combatant on that side").
# ══════════════════════════════════════════════════════════════════════════════

func test_empty_enemies_array_with_living_party_is_won() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([_living("Titus")], [])
	assert_eq(result, "won", "Zero enemies (empty array) with a living party must classify as 'won'")


func test_empty_party_array_with_living_enemy_is_lost() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([], [_living("Skeleton")])
	assert_eq(result, "lost", "Zero party members (empty array) with a living enemy must classify as 'lost'")


func test_both_arrays_empty_is_draw() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var result: String = use_case.classify([], [])
	assert_eq(result, "DRAW", "Zero combatants on both sides must classify as 'DRAW'")


# ══════════════════════════════════════════════════════════════════════════════
# Multi-combatant-per-side permutations — outcome depends on ANY living
# member of a side, not all-vs-none simplistically.
# ══════════════════════════════════════════════════════════════════════════════

func test_one_living_enemy_among_several_dead_keeps_undecided() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var enemies: Array = [_dead("Skeleton1"), _living("Skeleton2"), _dead("Skeleton3")]
	var result: String = use_case.classify([_living("Titus")], enemies)
	assert_eq(result, "", "One living enemy among several dead must remain undecided")


func test_all_of_multiple_enemies_dead_is_won() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var enemies: Array = [_dead("Skeleton1"), _dead("Skeleton2"), _dead("Skeleton3")]
	var party: Array   = [_living("Titus"), _dead("Mira")]
	var result: String = use_case.classify(party, enemies)
	assert_eq(result, "won", "All enemies dead (multiple) with at least one living party member must classify as 'won'")


func test_all_of_multiple_party_dead_is_lost() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var party: Array   = [_dead("Titus"), _dead("Mira")]
	var enemies: Array = [_living("Skeleton1"), _dead("Skeleton2")]
	var result: String = use_case.classify(party, enemies)
	assert_eq(result, "lost", "All party members dead (multiple) with at least one living enemy must classify as 'lost'")


func test_negative_hp_counts_as_dead() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var enemies: Array = [{"name": "Skeleton", "hp_current": -5}]
	var result: String = use_case.classify([_living("Titus")], enemies)
	assert_eq(result, "won", "Negative hp_current must be treated as dead, same as hp_current == 0")


# ══════════════════════════════════════════════════════════════════════════════
# Spent/ActionEconomy permutations — classification must be UNAFFECTED by
# is_spent(), proving outcome detection depends purely on hp_current.
# ══════════════════════════════════════════════════════════════════════════════

func _fully_spent_action_economy() -> ActionEconomyClass:
	var ae = ActionEconomyClass.new()
	ae.start_of_round()
	for _i in range(ActionEconomyClass.MAX_BUDGET):
		ae.spend_action({})
	return ae


func test_living_but_fully_spent_combatants_on_both_sides_remain_undecided() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var ae_party = _fully_spent_action_economy()
	var ae_enemy = _fully_spent_action_economy()
	assert_true(ae_party.is_spent() and ae_enemy.is_spent(), "sanity: both ActionEconomies must be Spent")

	# classify() takes only combatant Dictionaries — Spent state lives on a
	# SEPARATE ActionEconomy object entirely and has no bearing on hp_current.
	var party: Array   = [{"name": "Titus", "hp_current": 10}]
	var enemies: Array = [{"name": "Skeleton", "hp_current": 10}]
	var result: String = use_case.classify(party, enemies)
	assert_eq(result, "", "Both combatants alive (even though both ActionEconomies are Spent) must remain undecided")


func test_dead_but_never_spent_combatant_still_classifies_as_decided() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	var ae_fresh = ActionEconomyClass.new()
	ae_fresh.start_of_round()
	assert_false(ae_fresh.is_spent(), "sanity: a fresh ActionEconomy must not be Spent")

	# The enemy is dead despite its ActionEconomy never having been touched —
	# classification must still correctly resolve to 'won'.
	var party: Array   = [{"name": "Titus", "hp_current": 10}]
	var enemies: Array = [{"name": "Skeleton", "hp_current": 0}]
	var result: String = use_case.classify(party, enemies)
	assert_eq(result, "won", "A dead-but-never-Spent enemy must still classify as 'won' — Spent state is irrelevant")


func test_spent_state_permutations_never_change_classification_outcome() -> void:
	var use_case := DetermineOutcomeUseCaseClass.new()
	# Four permutations of (party Spent, enemy Spent) — the SAME hp_current
	# inputs must always produce the SAME classification regardless.
	var party_alive: Array   = [{"name": "Titus", "hp_current": 10}]
	var enemies_dead: Array  = [{"name": "Skeleton", "hp_current": 0}]

	for party_spent in [false, true]:
		for enemy_spent in [false, true]:
			# Spent state is modeled on independent ActionEconomy instances,
			# constructed here purely to document that classify() never
			# consults them — they are not even passed to classify().
			var ae_p = ActionEconomyClass.new()
			var ae_e = ActionEconomyClass.new()
			ae_p.start_of_round()
			ae_e.start_of_round()
			if party_spent:
				for _i in range(ActionEconomyClass.MAX_BUDGET):
					ae_p.spend_action({})
			if enemy_spent:
				for _i in range(ActionEconomyClass.MAX_BUDGET):
					ae_e.spend_action({})

			var result: String = use_case.classify(party_alive, enemies_dead)
			assert_eq(
				result, "won",
				"classify() must return 'won' regardless of Spent permutation (party_spent=%s, enemy_spent=%s)"
				% [party_spent, enemy_spent]
			)
