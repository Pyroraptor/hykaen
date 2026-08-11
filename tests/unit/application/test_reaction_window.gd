extends GutTest
## tests/unit/application/test_reaction_window.gd
##
## GUT test suite for FEAT-009 (US-009 / FR-009): weapons-aware reaction
## eligibility in core/application/reaction_window.gd's
## _compute_legal_reactions(). This is the API-layer boundary of the
## dwarf-channeler (Patience) steel thread that makes both "block" and
## "parry" legal reactions once a combatant carries more than one weapon
## (e.g. a mace + a small shield).
##
## Verifies (this feature's test_criteria):
##   1. _any_weapon_eligible() returns true if ANY single weapon in the
##      array satisfies the predicate, false (vacuously, fail-closed) for
##      an empty array.
##   2. _compute_legal_reactions() for a Patience-shaped trigger
##      (weapons=[mace, small_shield]) includes both "parry" and "block" in
##      the result.
##   3. Regression: Dodge, Steel, PreHitAvoidance, and OpportunisticStrike
##      branch outputs are byte-for-byte unchanged for every pre-existing
##      fixture (a table-driven branch-coverage matrix, per RISK-003).
##   4. A degenerate trigger carrying neither "weapons" nor "weapon" yields
##      "parry"/"block" simply absent — no exception raised.
##   5. legal_reactions remains an Array of bare lowercase reaction-id
##      Strings (contract frozen, no enrichment leaks into this layer).

const ReactionWindowClass = preload("res://core/application/reaction_window.gd")
const ResolutionClass     = preload("res://core/rules/resolution.gd")
const CombatantClass      = preload("res://core/domain/combatant.gd")


# ── Fake/double EventSinkPort (mirrors this project's established
#    tests/unit/test_reaction_window.gd convention) ─────────────────────────
class FakeEventSinkPort:
	extends "res://core/application/event_sink_port.gd"

	var events: Array = []

	func emit(event) -> void:
		events.append(event)


func _window() -> ReactionWindowClass:
	return ReactionWindowClass.new(FakeEventSinkPort.new())


func _reactor(overrides: Dictionary = {}):
	var base: Dictionary = {
		"name": "Patience",
		"conditions": [],
		"conscious": true,
		"skills": {"mobility": 1, "determination": 1},
	}
	for key in overrides:
		base[key] = overrides[key]
	return CombatantClass.from_dict(base)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #1: _any_weapon_eligible(weapons, predicate)
# ══════════════════════════════════════════════════════════════════════════

func test_any_weapon_eligible_true_when_a_single_weapon_satisfies_predicate() -> void:
	var weapons: Array = [
		{"parry_bonus": 0, "block_value": 0},
		{"parry_bonus": 2, "block_value": 0},
		{"parry_bonus": 0, "block_value": 0},
	]
	var result: bool = ReactionWindowClass._any_weapon_eligible(
		weapons, Callable(ResolutionClass, "is_parry_eligible")
	)
	assert_true(result, "one eligible weapon among several must be enough")


func test_any_weapon_eligible_false_when_no_weapon_satisfies_predicate() -> void:
	var weapons: Array = [
		{"parry_bonus": 0, "block_value": 0},
		{"parry_bonus": 0, "block_value": 0},
	]
	var result: bool = ReactionWindowClass._any_weapon_eligible(
		weapons, Callable(ResolutionClass, "is_parry_eligible")
	)
	assert_false(result)


func test_any_weapon_eligible_is_vacuously_false_for_empty_array() -> void:
	var result: bool = ReactionWindowClass._any_weapon_eligible(
		[], Callable(ResolutionClass, "is_parry_eligible")
	)
	assert_false(result, "an empty weapons array must fail closed, never raise")


func test_any_weapon_eligible_works_for_block_predicate_too() -> void:
	var weapons: Array = [
		{"parry_bonus": 0, "block_value": 0},
		{"parry_bonus": 0, "block_value": 4},
	]
	var result: bool = ReactionWindowClass._any_weapon_eligible(
		weapons, Callable(ResolutionClass, "is_block_eligible")
	)
	assert_true(result)


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #2: Patience's trigger (weapons=[mace, small_shield]) makes
# BOTH "parry" and "block" legal
# ══════════════════════════════════════════════════════════════════════════

## Each weapon here uniquely enables exactly ONE of Parry/Block (mace-shaped:
## parry only; shield-shaped: block only) — this is the discriminating case
## that only passes once _compute_legal_reactions() consults EVERY weapon in
## the array rather than only trigger["weapon"] (the pre-FEAT-009 behavior,
## which would have offered only "parry" here, since a legacy single-weapon
## read would see just the mace-shaped entry at index 0... wait, weapon
## defaults to trigger["weapon"], which is deliberately set to the
## mace-shaped dict below, so the pre-fix code path would ALSO see "parry"
## legal but never "block" — proving this is a real regression guard).
func _mace_like() -> Dictionary:
	return {"parry_bonus": 1, "block_value": 0}


func _small_shield_like() -> Dictionary:
	return {"parry_bonus": 0, "block_value": 4}


func test_weapon_attack_trigger_offers_both_parry_and_block_for_patience_style_loadout() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type":   "WeaponAttack",
		"reactor":        _reactor(),
		"defense_type":   "ac",
		"attack_context": {"open_space_available": false},
		"weapon":         _mace_like(),
		"weapons":        [_mace_like(), _small_shield_like()],
	})

	assert_true(result["legal_reactions"].has("parry"), "mace-shaped weapon must make parry legal")
	assert_true(result["legal_reactions"].has("block"), "small-shield-shaped weapon must make block legal")


func test_onhit_mitigation_trigger_offers_both_parry_and_block_for_patience_style_loadout() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type":            "OnHitMitigation",
		"reactor":                 _reactor(),
		"weapon":                  _mace_like(),
		"weapons":                 [_mace_like(), _small_shield_like()],
		"attack_hit":              true,
		"reaction_already_spent":  false,
	})

	assert_eq(result["legal_reactions"], ["parry", "block"])


func test_parry_trigger_is_legal_when_any_weapon_can_parry() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type": "Parry",
		"reactor":      _reactor(),
		"weapon":       _small_shield_like(),          # primary slot CANNOT parry
		"weapons":      [_small_shield_like(), _mace_like()],  # off-hand CAN
	})

	assert_eq(result["legal_reactions"], ["parry"], "off-hand weapon's parry capability must be consulted")


func test_block_trigger_is_legal_when_any_weapon_can_block() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type": "Block",
		"reactor":      _reactor(),
		"weapon":       _mace_like(),                       # primary slot CANNOT block
		"weapons":      [_mace_like(), _small_shield_like()],  # off-hand CAN
	})

	assert_eq(result["legal_reactions"], ["block"], "off-hand weapon's block capability must be consulted")


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #4: degenerate trigger (neither "weapons" nor "weapon")
# never raises — the gated reaction is simply absent
# ══════════════════════════════════════════════════════════════════════════

func test_weapon_attack_trigger_with_no_weapon_keys_omits_parry_and_block_without_raising() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type":   "WeaponAttack",
		"reactor":        _reactor(),
		"defense_type":   "fortitude",  # also makes dodge illegal, isolating parry/block
		"attack_context": {},
	})

	assert_eq(result["legal_reactions"], [], "no weapon/weapons key must yield no parry/block, no crash")


func test_parry_trigger_with_no_weapon_keys_omits_parry_without_raising() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({"trigger_type": "Parry", "reactor": _reactor()})

	assert_eq(result["legal_reactions"], [])


func test_block_trigger_with_no_weapon_keys_omits_block_without_raising() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({"trigger_type": "Block", "reactor": _reactor()})

	assert_eq(result["legal_reactions"], [])


func test_onhit_mitigation_trigger_with_no_weapon_keys_omits_both_without_raising() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type":           "OnHitMitigation",
		"reactor":                _reactor(),
		"attack_hit":             true,
		"reaction_already_spent": false,
	})

	assert_eq(result["legal_reactions"], [])


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #5: legal_reactions remains an Array of bare lowercase
# reaction-id Strings — contract frozen
# ══════════════════════════════════════════════════════════════════════════

func test_legal_reactions_entries_are_bare_lowercase_strings() -> void:
	var window: ReactionWindowClass = _window()

	var result: Dictionary = window.open({
		"trigger_type":   "WeaponAttack",
		"reactor":        _reactor(),
		"defense_type":   "ac",
		"attack_context": {"open_space_available": true},
		"weapon":         _mace_like(),
		"weapons":        [_mace_like(), _small_shield_like()],
	})

	for entry in result["legal_reactions"]:
		assert_true(typeof(entry) == TYPE_STRING, "every legal_reactions entry must be a bare String")
		assert_eq(entry, String(entry).to_lower(), "every legal_reactions entry must already be lowercase")

	assert_true(result["legal_reactions"].has("parry"))
	assert_true(result["legal_reactions"].has("block"))
	assert_true(result["legal_reactions"].has("dodge"))


# ══════════════════════════════════════════════════════════════════════════
# test_criteria #3 (RISK-003): table-driven branch-coverage matrix —
# EVERY trigger_type branch, including the four UNTOUCHED ones
# (Dodge/Steel/PreHitAvoidance/OpportunisticStrike), regression-pinned
# byte-for-byte against their pre-FEAT-009 expected outputs.
# ══════════════════════════════════════════════════════════════════════════

func _case(name: String, trigger: Dictionary, expected: Array) -> Dictionary:
	return {"name": name, "trigger": trigger, "expected": expected}


func _branch_matrix() -> Array:
	var multi_weapons: Array = [_mace_like(), _small_shield_like()]

	return [
		# ── UNTOUCHED branches (must be byte-for-byte identical to their
		#    pre-FEAT-009 behavior — never consult "weapons" at all) ──────
		_case("Dodge eligible", {
			"trigger_type": "Dodge", "reactor": _reactor(), "defense_type": "ac",
			"attack_context": {"open_space_available": true},
		}, ["dodge"]),
		_case("Dodge illegal: immobilized", {
			"trigger_type": "Dodge", "reactor": _reactor({"conditions": ["Immobilized"]}),
			"defense_type": "ac", "attack_context": {"open_space_available": true},
		}, []),
		_case("Dodge illegal: no open space", {
			"trigger_type": "Dodge", "reactor": _reactor(), "defense_type": "ac",
			"attack_context": {"open_space_available": false},
		}, []),
		_case("Steel eligible", {
			"trigger_type": "Steel", "reactor": _reactor({"conscious": true}), "defense_type": "fortitude",
		}, ["steel"]),
		_case("Steel illegal: unconscious", {
			"trigger_type": "Steel", "reactor": _reactor({"conscious": false}), "defense_type": "will",
		}, []),
		_case("OpportunisticStrike eligible", {
			"trigger_type": "OpportunisticStrike", "reactor": _reactor(),
			"attack_context": {"melee_reach": true},
		}, ["opportunistic_strike"]),
		_case("OpportunisticStrike illegal", {
			"trigger_type": "OpportunisticStrike", "reactor": _reactor(),
			"attack_context": {"melee_reach": false},
		}, []),
		_case("PreHitAvoidance both eligible", {
			"trigger_type": "PreHitAvoidance", "reactor": _reactor({"conscious": true}),
			"defense_type": "ac", "attack_context": {"open_space_available": true},
		}, ["dodge"]),
		_case("PreHitAvoidance none eligible", {
			"trigger_type": "PreHitAvoidance", "reactor": _reactor({"conditions": ["Immobilized"], "conscious": false}),
			"defense_type": "ac", "attack_context": {"open_space_available": true},
		}, []),
		_case("Unrecognized trigger_type", {"trigger_type": "Bogus", "reactor": _reactor()}, []),

		# ── TOUCHED branches (weapons-aware, per this feature) ────────────
		_case("Parry legal via any weapon", {
			"trigger_type": "Parry", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
		}, ["parry"]),
		_case("Parry illegal: no weapon can parry", {
			"trigger_type": "Parry", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": [{"parry_bonus": 0, "block_value": 0}],
		}, []),
		_case("Block legal via any weapon", {
			"trigger_type": "Block", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
		}, ["block"]),
		_case("Block illegal: no weapon can block", {
			"trigger_type": "Block", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": [{"parry_bonus": 0, "block_value": 0}],
		}, []),
		_case("OnHitMitigation both legal", {
			"trigger_type": "OnHitMitigation", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
			"attack_hit": true, "reaction_already_spent": false,
		}, ["parry", "block"]),
		_case("OnHitMitigation gated: reaction already spent", {
			"trigger_type": "OnHitMitigation", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
			"attack_hit": true, "reaction_already_spent": true,
		}, []),
		_case("OnHitMitigation gated: miss", {
			"trigger_type": "OnHitMitigation", "reactor": _reactor(),
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
			"attack_hit": false, "reaction_already_spent": false,
		}, []),
		_case("WeaponAttack union: dodge+parry+block all legal", {
			"trigger_type": "WeaponAttack", "reactor": _reactor(), "defense_type": "ac",
			"attack_context": {"open_space_available": true},
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": multi_weapons,
		}, ["dodge", "parry", "block"]),
		_case("WeaponAttack union: none legal", {
			"trigger_type": "WeaponAttack", "reactor": _reactor(), "defense_type": "ac",
			"attack_context": {"open_space_available": false},
			"weapon": {"parry_bonus": 0, "block_value": 0}, "weapons": [{"parry_bonus": 0, "block_value": 0}],
		}, []),
	]


func test_branch_coverage_matrix() -> void:
	for entry in _branch_matrix():
		var window: ReactionWindowClass = _window()
		var result: Dictionary = window.open(entry["trigger"])
		assert_eq(
			result["legal_reactions"], entry["expected"],
			"branch case '%s' expected legal_reactions=%s, got %s"
				% [entry["name"], entry["expected"], result["legal_reactions"]]
		)
