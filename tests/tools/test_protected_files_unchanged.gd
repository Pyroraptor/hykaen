extends GutTest
## tests/tools/test_protected_files_unchanged.gd — FEAT-008 (US-008; FR-008/
## FR-009; mitigates RISK-004).
##
## The enemy-weapon-architecture steel thread (FEAT-001..FEAT-007) rewired
## EnemyResource/EncounterResource/Combatant/CombatantFactory to resolve
## weapons by res:// path instead of an inline weapon Dictionary. NONE of
## that work was supposed to touch the reaction/resolution contracts the
## rest of the combat pipeline depends on — the whole point of routing
## backward compatibility through Combatant.weapon (the alias FEAT-005
## established) is that core/application/reaction_window.gd,
## core/application/round_session.gd's ReactionTrigger builders, the
## legal_reactions eligibility contract (core/rules/resolution.gd's
## is_dodge_eligible()/is_steel_eligible()/is_parry_eligible()/
## is_block_eligible()), and the ReactionChooserPort/ReactionWindowPort
## contracts plus their concrete chooser adapters never needed to change AT
## ALL.
##
## RISK-004 named the danger directly: a refactor "protecting" these files
## only by convention (nobody's task said to touch them) is one careless
## edit away from silently drifting. This suite is the automated guard —
## it pins a SHA-256 content hash of each protected file (or, for
## round_session.gd, of the specific ReactionTrigger-builder block — see
## _TRIGGER_BUILDER_BLOCK_START/_END below — since that file legitimately
## grows elsewhere for unrelated reasons) captured as this feature's own
## pre-change baseline, and fails loud on ANY drift.
##
## Test criteria covered:
##   1. core/application/reaction_window.gd is byte-identical to its pinned
##      pre-refactor baseline.
##   2. core/application/round_session.gd's three ReactionTrigger-builder
##      functions (_build_reaction_trigger/_build_prehit_avoidance_trigger/
##      _build_onhit_mitigation_trigger, including their doc comments) are
##      byte-identical to their pinned pre-refactor baseline.
##   3. The legal_reactions eligibility contract (core/rules/resolution.gd,
##      whole file — is_dodge_eligible/is_steel_eligible/is_parry_eligible/
##      is_block_eligible live here) is byte-identical to its pinned
##      pre-refactor baseline.
##   4. The chooser ports/adapters (core/application/ports/
##      reaction_chooser_port.gd, core/application/ports/
##      reaction_window_port.gd, infrastructure/auto_reaction_chooser.gd,
##      presentation/player_reaction_chooser.gd) are each byte-identical to
##      their pinned pre-refactor baseline.


const REACTION_WINDOW_PATH: String = "res://core/application/reaction_window.gd"
const ROUND_SESSION_PATH: String = "res://core/application/round_session.gd"
const RESOLUTION_PATH: String = "res://core/rules/resolution.gd"
const REACTION_CHOOSER_PORT_PATH: String = "res://core/application/ports/reaction_chooser_port.gd"
const REACTION_WINDOW_PORT_PATH: String = "res://core/application/ports/reaction_window_port.gd"
const AUTO_REACTION_CHOOSER_PATH: String = "res://infrastructure/auto_reaction_chooser.gd"
const PLAYER_REACTION_CHOOSER_PATH: String = "res://presentation/player_reaction_chooser.gd"

## _TRIGGER_BUILDER_BLOCK_START/_END — round_session.gd contains a great
## deal of code that legitimately evolves for reasons unrelated to this
## steel thread (Channeling energy pools, AI turn loop, etc.), so pinning
## the WHOLE file would make this guard fail on unrelated future work. The
## specific "protected" surface this feature's design notes name is the
## trigger builders: _build_reaction_trigger(), _build_prehit_avoidance_
## trigger(), and _build_onhit_mitigation_trigger(), together with their
## doc comments. These three markers bound that contiguous block exactly —
## from the doc comment immediately preceding _build_reaction_trigger()
## through (not including) the doc comment immediately preceding the next,
## unrelated function (_find_action_economy_for()).
const _TRIGGER_BUILDER_BLOCK_START: String = "## _build_reaction_trigger(attacker, target, target_action_economy) ->"
const _TRIGGER_BUILDER_BLOCK_END: String = "## _find_action_economy_for(combatant) -> ActionEconomy or null"

## PINNED_*_SHA256 — SHA-256 digests captured as this feature's own
## pre-change baseline (FEAT-008's own test run, per this feature's
## resolves_findings/RISK-004 mitigation: "adding an automated byte-diff
## assertion against a captured pre-change snapshot of the protected files
## as part of this feature's own test run"). A future change to ANY of
## these contracts must be a deliberate, reviewed decision that also
## regenerates the corresponding constant below — never a silent drift.
const PINNED_REACTION_WINDOW_SHA256: String = "61e91ed941786bdeeffa4c6174b58c1b94caa801ca8710020a864d7e9ae00c74"
const PINNED_ROUND_SESSION_TRIGGER_BUILDER_BLOCK_SHA256: String = "dfa96eaac4e5562aa1c171f77592cecafd9db46cd13fd9f3666cac001b6c24f6"
const PINNED_RESOLUTION_SHA256: String = "c40c480fe874e3b4334edd801f74ca99ba0a4b4bdd4ac5264056515b12bab194"
const PINNED_REACTION_CHOOSER_PORT_SHA256: String = "fae5434a8a4c9cde299e687572daed7695b6a7e7b007aa440cc041cdb0ca235d"
const PINNED_REACTION_WINDOW_PORT_SHA256: String = "c221ba7800e6f3d7d5918d13109b69a49843480ac7634ea936dbb1fb7e7d45d9"
const PINNED_AUTO_REACTION_CHOOSER_SHA256: String = "2a8428d5aca608ba137736b5cfe143a3d88981bae3b34ed1b1b0124bcd7d0208"
const PINNED_PLAYER_REACTION_CHOOSER_SHA256: String = "ddaff50ff95cfdf0d5ef5cef80f94667e8d6887bd1cdf531d5cd14886c7f0a46"


func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func _assert_whole_file_matches(res_path: String, pinned_sha256: String) -> void:
	var content: String = _read_file(res_path)
	var live_hash: String = content.sha256_text()
	assert_eq(
		live_hash, pinned_sha256,
		"REGRESSION: %s must have ZERO diff relative to the pre-refactor pinned baseline (FEAT-008/RISK-004) — a hash mismatch means this protected reaction/resolution contract file was modified" % res_path
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1: core/application/reaction_window.gd byte-identical.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_window_source_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(REACTION_WINDOW_PATH, PINNED_REACTION_WINDOW_SHA256)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2: round_session.gd's ReactionTrigger-builder block byte-identical.
# ══════════════════════════════════════════════════════════════════════════

func test_round_session_trigger_builder_block_has_zero_diff_from_pinned_baseline() -> void:
	var content: String = _read_file(ROUND_SESSION_PATH)
	var start_idx: int = content.find(_TRIGGER_BUILDER_BLOCK_START)
	var end_idx: int = content.find(_TRIGGER_BUILDER_BLOCK_END)

	assert_true(start_idx >= 0, "round_session.gd must still contain the _build_reaction_trigger() doc-comment marker this guard anchors on")
	assert_true(end_idx > start_idx, "round_session.gd must still contain the _find_action_economy_for() doc-comment marker this guard anchors on, AFTER the trigger-builder block")
	if start_idx < 0 or end_idx <= start_idx:
		return

	var block: String = content.substr(start_idx, end_idx - start_idx)
	var live_hash: String = block.sha256_text()

	assert_eq(
		live_hash, PINNED_ROUND_SESSION_TRIGGER_BUILDER_BLOCK_SHA256,
		"REGRESSION: core/application/round_session.gd's ReactionTrigger-builder block (_build_reaction_trigger/_build_prehit_avoidance_trigger/_build_onhit_mitigation_trigger) must have ZERO diff relative to the pre-refactor pinned baseline (FEAT-008/RISK-004)"
	)

	# Sanity: the block genuinely contains all three builder functions, so a
	# future edit that widens/narrows the marker span still trips this guard
	# rather than silently hashing an empty or partial block.
	assert_true(block.contains("func _build_reaction_trigger("), "extracted block must contain _build_reaction_trigger()")
	assert_true(block.contains("func _build_prehit_avoidance_trigger("), "extracted block must contain _build_prehit_avoidance_trigger()")
	assert_true(block.contains("func _build_onhit_mitigation_trigger("), "extracted block must contain _build_onhit_mitigation_trigger()")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3: legal_reactions eligibility contract (core/rules/resolution.gd)
# byte-identical.
# ══════════════════════════════════════════════════════════════════════════

func test_resolution_legal_reactions_contract_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(RESOLUTION_PATH, PINNED_RESOLUTION_SHA256)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 4: chooser ports/adapters byte-identical.
# ══════════════════════════════════════════════════════════════════════════

func test_reaction_chooser_port_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(REACTION_CHOOSER_PORT_PATH, PINNED_REACTION_CHOOSER_PORT_SHA256)


func test_reaction_window_port_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(REACTION_WINDOW_PORT_PATH, PINNED_REACTION_WINDOW_PORT_SHA256)


func test_auto_reaction_chooser_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(AUTO_REACTION_CHOOSER_PATH, PINNED_AUTO_REACTION_CHOOSER_SHA256)


func test_player_reaction_chooser_has_zero_diff_from_pinned_baseline() -> void:
	_assert_whole_file_matches(PLAYER_REACTION_CHOOSER_PATH, PINNED_PLAYER_REACTION_CHOOSER_SHA256)


# ══════════════════════════════════════════════════════════════════════════
# All protected files together — a single summarizing assertion (mirrors
# tests/integration/test_out_of_scope_regression_guard.py's established
# "redundant by design" convention) so a future refactor of this suite that
# accidentally drops one of the individual tests above still has one
# assertion enforcing the full-set contract.
# ══════════════════════════════════════════════════════════════════════════

func test_all_protected_files_pass_the_guard_together() -> void:
	var mismatches: Array = []

	var whole_file_checks: Array = [
		[REACTION_WINDOW_PATH, PINNED_REACTION_WINDOW_SHA256],
		[RESOLUTION_PATH, PINNED_RESOLUTION_SHA256],
		[REACTION_CHOOSER_PORT_PATH, PINNED_REACTION_CHOOSER_PORT_SHA256],
		[REACTION_WINDOW_PORT_PATH, PINNED_REACTION_WINDOW_PORT_SHA256],
		[AUTO_REACTION_CHOOSER_PATH, PINNED_AUTO_REACTION_CHOOSER_SHA256],
		[PLAYER_REACTION_CHOOSER_PATH, PINNED_PLAYER_REACTION_CHOOSER_SHA256],
	]
	for pair in whole_file_checks:
		var res_path: String = pair[0]
		var expected: String = pair[1]
		if _read_file(res_path).sha256_text() != expected:
			mismatches.append(res_path)

	var round_session_content: String = _read_file(ROUND_SESSION_PATH)
	var start_idx: int = round_session_content.find(_TRIGGER_BUILDER_BLOCK_START)
	var end_idx: int = round_session_content.find(_TRIGGER_BUILDER_BLOCK_END)
	if start_idx < 0 or end_idx <= start_idx:
		mismatches.append(ROUND_SESSION_PATH)
	else:
		var block: String = round_session_content.substr(start_idx, end_idx - start_idx)
		if block.sha256_text() != PINNED_ROUND_SESSION_TRIGGER_BUILDER_BLOCK_SHA256:
			mismatches.append(ROUND_SESSION_PATH)

	assert_eq(mismatches, [], "drifted protected reaction/resolution contract files: %s" % [mismatches])
