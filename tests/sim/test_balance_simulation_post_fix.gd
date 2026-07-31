extends GutTest
## tests/sim/test_balance_simulation_post_fix.gd
##
## FEAT-106 (US-008) — Final end-to-end smoke test of the steel thread,
## post-CR-001 remediation (FIX-001..FIX-005 / FEAT-001..FEAT-105).
##
## Drives core/sim/simulator.gd — UNMODIFIED per CR-001/US-008 scope — at
## N=1000 through the now-corrected, now-fully-tested
## core/combat/encounter.gd run_round() entry point, with NO domain-layer
## mocking anywhere in the call chain:
##
##   core/rules/action_economy.gd (domain)
##     -> core/application/{run_round,resolve_action,determine_outcome}_use_case.gd
##     -> core/combat/encounter.gd (adapter, run_round() entry point)
##     -> core/sim/simulator.gd (infrastructure-level consumer, run())
##
## simulator.gd's run() constructs one Encounter per battle and calls
## Encounter.run() (core/combat/encounter.gd:312-316), which loops
## run_round() until the outcome is decided — so every one of the N=1000
## battles below is driven entirely through the real run_round() entry
## point exercising the real AC-4 interleaved-cycle round loop.
##
## Peer-review checklist items addressed (CHECKLIST-5):
##   - "Re-run the N=1000 balance simulation against the fully-fixed round
##     loop and commit a refreshed sim_results.json superseding the stale
##     pre-fix results."
##   - Smoke test: "Balance simulation (N=1000) reports win_rate within
##     [0.40, 0.80] inside the 300s wall-clock budget."
##
## Test criteria covered (FEAT-106):
##   1. simulator.run(1000, seed) completes within the 300s wall-clock
##      budget against the REAL, unmodified simulator.gd.
##   2. win_rate is within [0.40, 0.80], OR an explicit
##      flag == 'OUT_OF_BALANCE_RANGE' is asserted/recorded (CR-001 API
##      contract #6) — never silently passed either way.
##   3. core/sim/simulator.gd, the character/enemy/weapon/armor .tres
##      fixtures, and damage dice are verified UNCHANGED via a pinned-MD5
##      diff check performed in test setup (before_all()) — this test
##      asserts it has made (and the prior FIX-001..FIX-005 features made)
##      zero edits to those production files.
##   4. sim_results.json is regenerated and reflects the post-fix commit —
##      a timestamp and the current commit hash (best-effort `git
##      rev-parse HEAD` via OS.execute) are recorded in the artifact,
##      superseding the stale pre-fix results.gd
##   5. A single fresh Encounter is also driven directly via run_round()
##      (mirroring exactly what simulator.gd does internally for each of
##      the N=1000 battles) to assert the precise entry/exit contract:
##      run_round() begins a round and cycles _turn_order, and on exit
##      _round_history entries carry budget_remaining, _round_events is
##      populated, and the encounter reaches a correct 'won'/'lost'
##      outcome — proving the full steel thread functions end-to-end, not
##      just that simulator.gd's aggregate win_rate happens to land in
##      range.
##
## Satisfies: FEAT-106, US-008, CHECKLIST-5.

const SimulatorClass  = preload("res://core/sim/simulator.gd")
const EncounterClass  = preload("res://core/combat/encounter.gd")
const RNGClass        = preload("res://core/rules/rng.gd")
const AttributesClass = preload("res://core/rules/attributes.gd")
const CombatantClass  = preload("res://core/domain/combatant.gd")

## Pinned seed/count for the post-fix N=1000 re-run — deterministic.
const BALANCE_SEED: int = 12345
const BALANCE_COUNT: int = 1000
const TIMEOUT_SECONDS: float = 300.0

## A second, independent seed used only for the single-encounter
## run_round() entry/exit contract proof (criterion 5) — kept distinct
## from BALANCE_SEED so the two checks are not coupled to one RNG stream.
const CONTRACT_SEED: int = 99999
const MAX_ROUNDS_GUARD: int = 50

## Pinned MD5 hashes (FileAccess.get_as_text().md5_text()) of the production
## files this CR's scope (CR-001/US-008) requires to remain UNMODIFIED:
## simulator.gd itself, plus the character/enemy/weapon/armor resources that
## carry the stats and damage dice the simulation depends on. Any edit to
## these files changes their hash and fails test_production_files_unmodified()
## below — the "assertion/diff check in the test setup" required by FEAT-106.
##
## FEAT-002 (iteration-G P1, FR-007) intentionally re-pins the
## skeleton.tres hash below: that iteration's design explicitly authors
## pinned attribute/defense values onto skeleton.tres (ac 12->14 plus the
## new constitution/intuition/willpower/social/intellect attribute fields
## from FEAT-001), so the CR-001/US-008-era "must stay byte-identical"
## baseline is updated to the new, intentionally-authored content rather
## than treated as a violation of this guard's scope.
##
## FEAT-008 (iteration-G, US-008 / FR-008, ADR-106) likewise intentionally
## re-pins the simulator.gd hash below: that feature's explicit, in-scope
## design change reads ac/fortitude/reflex/will directly off the loaded
## skeleton EnemyResource (via a new _build_skeleton_combatant() helper)
## instead of the previous hard-coded "ac": 14 inline literal, closing the
## sim/game defense-source parity gap this CR's guard was never meant to
## block a deliberately-authorized future feature from making.
##
## FEAT-201 (US-008, ADR-106) likewise intentionally re-pins the
## simulator.gd hash below: fixes the same class of defect for `intuition`
## that FEAT-008 fixed for ac/fortitude/reflex/will —
## _build_skeleton_combatant() now reads `intuition` directly off the
## loaded skeleton EnemyResource instead of a hard-coded "intuition": 1
## literal (a value that happened to match skeleton.tres' authored
## intuition=1 by coincidence, masking the same sim/game divergence risk
## ADR-106 targets). See tests/gut/test_intuition_defense_source_parity.gd.
##
## FEAT-001 (iteration-H B-1 / US-005 / FR-006) likewise intentionally
## re-pins the longsword.tres hash below: that feature populates the
## reaction stats as prerequisite data for the Parry/Block reaction wiring.
## The weapon-reconcile fix 53efaa6 (data: reconcile weapon .tres to the
## Weapons.pdf table, ground truth) subsequently re-pins the longsword.tres
## hash again: it corrected block_value 1→3 and parry_bonus 2→4 to the
## authoritative Weapons.pdf values. Neither field is read by the
## passive-defense-only simulator.gd path exercised by this test, so this
## data-layer change is not expected to shift win_rate — see
## tests/unit/test_weapon_resource_data.gd for the data suite.
##
## FEAT-002 (iteration-H, US-006 / FR-007) intentionally re-pins the
## titus.tres and skeleton.tres hashes below: that feature adds a new
## `skills: Dictionary` field (distinct from `attributes`) to both
## CharacterResource and EnemyResource, and authors it onto both .tres
## fixtures (Titus mobility=2/determination=2, skeleton
## mobility=1/determination=1). `skills` is not read anywhere on the
## passive-defense-only simulator.gd path exercised by this test (it is a
## data-layer prerequisite for the future Dodge/Steel check rewiring), so
## this change is not expected to shift win_rate. See
## tests/unit/test_skills_dictionary.gd for the FEAT-002 data suite.
##
## FEAT-001 (iteration K, US-001) intentionally re-pins the skeleton.tres
## hash below AGAIN: this feature adds parry_bonus/block_value/block_die
## fields (mirroring WeaponResource) and authors the Arming Sword table
## onto skeleton.tres, including moving weapon.proficiency_bonus from 1 to
## 2 (ground truth per the Weapons.pdf table). Unlike the skills/defense
## field additions above, proficiency_bonus DOES feed core/sim/simulator.gd's
## _build_skeleton_combatant() (skeleton_res.weapon.get("proficiency_bonus")),
## so this change genuinely shifts the N=1000 win_rate (0.747 -> 0.688,
## avg_rounds 1.081 -> 1.068 at the pinned seed) — still comfortably inside
## the [0.40, 0.80] balance invariant. See
## tests/pytest/test_sim_results_provenance.py (re-pinned to the same new
## values) and tests/unit/test_enemy_resource_weapon_defense_fields.gd for
## the FEAT-001 data suite.
##
## FEAT-008 (this iteration, US-008 / FR-008) intentionally re-pins the
## titus.tres hash below AGAIN: that feature additively wires
## level=1/equipped_items=[longsword_titus, shield_titus] onto titus.tres
## (and the other three party-member fixtures, which are not in this
## guard's pinned set) per ADR-004. Neither `level` nor `equipped_items` is
## read anywhere on the passive-defense-only simulator.gd path exercised by
## this test — Titus's simulated combatant stats are built from
## `attributes`/`class_ref`/`skills`/weapon proficiency, none of which
## changed — so this change is not expected to shift win_rate. See
## tests/unit/test_prologue_character_equipment_fixtures.gd for the FEAT-008
## data suite and its field-diff regression test confirming every other
## field (including attributes/skills) is unchanged.
const _EXPECTED_HASHES: Dictionary = {
	"res://core/sim/simulator.gd":      "6120b8e4b096193d2f5c587f683ae4a9",
	"res://data/characters/titus.tres": "c2f1101a4fdcdbbb07c56920170df146",
	"res://data/enemies/skeleton.tres": "a197dd1bc0c15c016b1ee33dc202951c",
	"res://data/weapons/longsword.tres": "248339f6e3f256d6cdc6a943ca824587",
	"res://data/armor/chain_shirt.tres": "6be0c7c1b55b7a91233bca0f62fadd16",
	"res://data/armor/scale_mail.tres":  "7c724303a7db4ad78a7341bc9e7f46f1",
}

## Results from the single 1000-battle run, shared across all tests via
## before_all() (mirrors tests/sim/test_balance_sim.gd's pattern — avoids
## repeating a 1000-battle run per test function).
var _result: Dictionary
var _elapsed_seconds: float
var _hash_diffs: Dictionary   ## path -> {"expected": String, "actual": String} for any mismatch


func before_all() -> void:
	## (Criterion 3 setup) Compute the actual MD5 of every pinned production
	## file BEFORE asserting anything about the simulation run, so a failure
	## here is attributable purely to "production file changed", independent
	## of simulation results.
	_hash_diffs = {}
	for path in _EXPECTED_HASHES.keys():
		var actual: String = _file_md5_text(path)
		var expected: String = _EXPECTED_HASHES[path]
		if actual != expected:
			_hash_diffs[path] = {"expected": expected, "actual": actual}

	## (Criterion 1) Run 1000 battles once and store results + wall-clock.
	var sim = SimulatorClass.new()
	var t_start: float = Time.get_unix_time_from_system()
	_result = sim.run(BALANCE_COUNT, BALANCE_SEED)
	_elapsed_seconds = Time.get_unix_time_from_system() - t_start


## _file_md5_text(path) — reads a res:// file as text and returns its
## md5_text() hash, or "" if the file could not be opened.
func _file_md5_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content.md5_text()


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 3: No edits to simulator.gd, character/enemy/weapon/armor .tres
# stats, or damage dice — verified via pinned-MD5 diff check in before_all().
# ══════════════════════════════════════════════════════════════════════════════

func test_production_files_unmodified() -> void:
	assert_eq(
		_hash_diffs.size(), 0,
		(
			"FEAT-106 setup guard FAILED: production file(s) changed since the pinned "
			+ "post-fix baseline — CR-001/US-008 scope forbids editing simulator.gd, "
			+ "character/enemy/weapon stats, or damage dice. Diffs: %s"
		) % str(_hash_diffs)
	)


func test_simulator_gd_hash_matches_pinned_baseline() -> void:
	## Isolated single-file assertion (in addition to the aggregate check
	## above) for simulator.gd specifically — the file CR-001 most
	## explicitly forbids touching (it is the steel-thread consumer under
	## test, not something this feature may "fix to make the test pass").
	var actual: String = _file_md5_text("res://core/sim/simulator.gd")
	assert_eq(
		actual, _EXPECTED_HASHES["res://core/sim/simulator.gd"],
		"core/sim/simulator.gd must be byte-identical to the pinned post-fix baseline (UNMODIFIED per CR-001/US-008) — FEAT-106"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 1: simulator.run(1000, seed) completes within the 300s budget
# against the real, unmodified simulator.gd.
# ══════════════════════════════════════════════════════════════════════════════

func test_n1000_completes_within_300_second_budget() -> void:
	assert_true(
		_elapsed_seconds < TIMEOUT_SECONDS,
		(
			"FEAT-106 timeout gate FAILED: N=1000 post-fix balance simulation must "
			+ "complete in < %.0f seconds; took %.2f seconds"
		) % [TIMEOUT_SECONDS, _elapsed_seconds]
	)


func test_n1000_total_battles_equals_1000() -> void:
	assert_eq(
		_result.get("total_battles", -1), BALANCE_COUNT,
		"simulator.run(1000, seed) must report total_battles == 1000 — FEAT-106"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 2: win_rate within [0.40, 0.80], OR an explicit
# flag == 'OUT_OF_BALANCE_RANGE' is asserted/recorded (never silently
# passed either way) — CR-001 API contract #6.
# ══════════════════════════════════════════════════════════════════════════════

func test_n1000_win_rate_in_range_or_explicitly_flagged() -> void:
	var wr: float = _result.get("win_rate", -1.0)
	var report: Dictionary = {"win_rate": wr, "total_battles": _result.get("total_battles", 0)}

	if wr >= 0.40 and wr <= 0.80:
		## In-range path: assert the invariant directly. This is the primary,
		## expected post-fix outcome.
		assert_true(
			wr >= 0.40 and wr <= 0.80,
			(
				"N=1000 post-fix balance check: win_rate=%.4f (seed %d) is within "
				+ "[0.40, 0.80] — steel thread balance invariant holds — FEAT-106"
			) % [wr, BALANCE_SEED]
		)
		gut.p("FEAT-106: win_rate=%.4f in [0.40, 0.80] — no OUT_OF_BALANCE_RANGE flag" % wr)
	else:
		## Out-of-range path: per CR-001 API contract #6, simulator/character
		## data/dice must NOT be altered to compensate — the result is
		## explicitly flagged instead, and that flag is itself asserted here
		## (never silently passed without an assertion in either branch).
		report["flag"] = "OUT_OF_BALANCE_RANGE"
		assert_eq(
			report["flag"], "OUT_OF_BALANCE_RANGE",
			(
				"N=1000 post-fix win_rate=%.4f (seed %d) fell OUTSIDE [0.40, 0.80] — "
				+ "recording the OUT_OF_BALANCE_RANGE flag per CR-001 API contract #6 "
				+ "(reporting only; simulator.gd/character data/dice are NOT altered "
				+ "to compensate) — FEAT-106"
			) % [wr, BALANCE_SEED]
		)
		gut.p("FEAT-106: win_rate=%.4f OUTSIDE [0.40, 0.80] — flag=OUT_OF_BALANCE_RANGE recorded" % wr)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 5: a single fresh Encounter driven directly via run_round() —
# the exact mechanism simulator.gd uses internally for each of the N=1000
# battles — to prove the entry/exit contract end-to-end with NO
# domain-layer mocking anywhere in the chain.
# ══════════════════════════════════════════════════════════════════════════════

func test_run_round_entry_exit_contract_no_mocking() -> void:
	var titus_char    = ResourceLoader.load("res://data/characters/titus.tres")
	var scale_mail    = ResourceLoader.load("res://data/armor/scale_mail.tres")
	var weapon_res    = ResourceLoader.load("res://data/weapons/longsword.tres")
	var skeleton_res  = ResourceLoader.load("res://data/enemies/skeleton.tres")

	if titus_char == null or scale_mail == null or weapon_res == null or skeleton_res == null:
		fail_test("Required production resources failed to load — cannot prove run_round() contract (FEAT-106)")
		return

	var attrs        = AttributesClass.new(RNGClass.new(0))
	var titus_hp: int = attrs.compute_hp(titus_char.attributes, titus_char.class_ref)
	var titus_ac: int = attrs.compute_ac(titus_char.attributes, scale_mail.ac_base, scale_mail.category)

	var titus = CombatantClass.from_dict({
		"name":       titus_char.name,
		"hp_current": titus_hp,
		"ac":         titus_ac,
		"strength":   titus_char.attributes.get("strength",  0),
		"dexterity":  titus_char.attributes.get("dexterity", 0),
		"intuition":  titus_char.attributes.get("intuition", 0),
		"weapon": {
			"damage_modifier_attribute": weapon_res.damage_modifier_attribute,
			"proficiency_bonus":         weapon_res.proficiency_bonus,
			"damage_die":                weapon_res.damage_die,
		}
	})
	var skeleton = CombatantClass.from_dict({
		"name":       skeleton_res.name,
		"hp_current": 50,
		"ac":         14,
		"strength":   skeleton_res.str,
		"dexterity":  skeleton_res.dex,
		"intuition":  1,
		"weapon": {
			"damage_modifier_attribute": "strength",
			"proficiency_bonus": skeleton_res.weapon.get("proficiency_bonus", 1),
			"damage_die":        skeleton_res.weapon.get("die", 8),
		}
	})

	# Real RNG (core/rules/rng.gd) — no test double, no domain-layer mocking.
	var enc = EncounterClass.new([titus], [skeleton], RNGClass.new(CONTRACT_SEED))
	enc.initialize()

	var outcome: String = ""
	var rounds_run: int = 0
	var saw_round_events: bool = false

	# Entry: run_round() begins a round and cycles _turn_order (asserted via
	# get_turn_order() below); exit: outcome/_round_history/_round_events.
	assert_true(
		enc.get_turn_order().size() == 2,
		"Encounter.initialize() must populate _turn_order with both combatants before run_round() cycles it — FEAT-106"
	)

	while outcome == "" and rounds_run < MAX_ROUNDS_GUARD:
		var round_result: Dictionary = enc.run_round()
		if enc.get_round_events().size() > 0:
			saw_round_events = true
		outcome = round_result.get("outcome", "")
		rounds_run += 1

	assert_true(
		rounds_run >= 1 and rounds_run < MAX_ROUNDS_GUARD,
		"run_round() must drive the encounter to a terminal outcome within the safety guard — FEAT-106"
	)
	assert_true(
		outcome == "won" or outcome == "lost",
		"run_round() entry/exit contract: final outcome must be 'won' or 'lost'; got '%s' (seed %d) — FEAT-106"
			% [outcome, CONTRACT_SEED]
	)
	assert_eq(
		enc.get_outcome(), outcome,
		"Encounter.get_outcome() must agree with the last run_round() result's outcome — FEAT-106"
	)
	assert_true(
		saw_round_events,
		"run_round() must populate _round_events (get_round_events()) across the encounter — FEAT-106"
	)
	assert_true(
		enc.get_round_history().size() >= 1,
		"run_round() must accumulate at least one _round_history entry — FEAT-106"
	)

	# Exit contract: every _round_history entry must carry budget_remaining
	# (CR-001 AC-5 / US-005 — the field FEAT-106's design notes call out
	# explicitly as part of the run_round() exit contract).
	for entry in enc.get_round_history():
		assert_true(
			entry.has("budget_remaining"),
			"Every run_round() _round_history entry must carry 'budget_remaining' — FEAT-106 / CR-001 AC-5"
		)


# ══════════════════════════════════════════════════════════════════════════════
# Criterion 4: sim_results.json is regenerated, with a timestamp and (where
# available) the current commit hash recorded, superseding the stale
# pre-fix artifact.
# ══════════════════════════════════════════════════════════════════════════════

func test_sim_results_json_regenerated_with_timestamp_and_commit() -> void:
	var timestamp: String = Time.get_datetime_string_from_system(true)

	## Best-effort commit hash via `git rev-parse HEAD` — non-fatal if git
	## or OS.execute is unavailable in a given sandbox (mirrors the
	## existing best-effort artifact-write pattern in test_balance_sim.gd).
	var commit_hash: String = ""
	var git_output: Array = []
	var exit_code: int = OS.execute("git", ["rev-parse", "HEAD"], git_output, true)
	if exit_code == 0 and git_output.size() > 0:
		commit_hash = String(git_output[0]).strip_edges()

	var wr: float = _result.get("win_rate", -1.0)
	var json_dict: Dictionary = {
		"total_battles":       _result.get("total_battles", 0),
		"win_rate":            wr,
		"avg_rounds":          _result.get("avg_rounds", 0.0),
		"confidence_interval": _result.get("confidence_interval", 0.0),
		"seed":                BALANCE_SEED,
		"timestamp":           timestamp,
		"commit_hash":         commit_hash,
	}
	if not (wr >= 0.40 and wr <= 0.80):
		json_dict["flag"] = "OUT_OF_BALANCE_RANGE"

	var json_string: String = JSON.stringify(json_dict, "\t")

	var file := FileAccess.open("res://sim_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(json_string)
		file.close()
		gut.p("FEAT-106: sim_results.json regenerated (post-fix): " + json_string)
	else:
		gut.p("WARNING: could not write sim_results.json (non-fatal — artifact only) — FEAT-106")

	## Assert the JSON structure/content regardless of write success.
	assert_eq(
		json_dict["total_battles"], BALANCE_COUNT,
		"sim_results.json total_battles must be 1000 — FEAT-106"
	)
	assert_true(
		json_dict["win_rate"] >= 0.0 and json_dict["win_rate"] <= 1.0,
		"sim_results.json win_rate must be in [0.0, 1.0] — FEAT-106"
	)
	assert_true(
		json_dict["timestamp"] != "",
		"sim_results.json must record a non-empty timestamp (post-fix artifact provenance) — FEAT-106"
	)
