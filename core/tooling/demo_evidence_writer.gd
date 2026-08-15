## core/tooling/demo_evidence_writer.gd — DemoEvidenceWriter (FEAT-406 / US-011;
## resolves FINDING-007, mitigates RISK-007)
##
## Application-adjacent tooling/infrastructure helper: a tiny JSON
## read/write adapter over a single, documented, FIXED artifact path. This
## is the reproducible replacement for the unrecorded, manual "run the full
## demo scenario and confirm observable behavior" task from US-011 —
## instead of a human eyeballing a running scene, a GUT integration test
## (tests/integration/test_grunt_ai_demo_evidence_capture.gd) drives the
## REAL composition-root/RoundSession path (CombatantFactory ->
## AITierRegistry -> RoundSession entry['ai_planner']), writes what it
## observed through this writer, then re-reads and validates the written
## file — turning a previously-unrecorded manual pass into a durable,
## CI-enforced artifact (closing RISK-007's trigger condition, "demo lacks
## recorded evidence").
##
## This file carries ZERO combat/AI/domain logic of its own — it only
## knows how to durably persist and re-load an already-assembled
## Dictionary as JSON. All of the actual demo-scenario logic (building the
## composition root, driving advance_ai_turn(), observing the outcome)
## lives entirely in the calling test, per this feature's own scope
## (files_to_create lists no changes to round_session.gd or any other
## production combat file).
##
## ARTIFACT_PATH — the documented FIXED path this feature's evidence log is
## always written to and re-read from.
##
## Deliberately anchored under res://.test-output/ (git-ignored — see
## .gitignore's `/.test-output/` rule) rather than the illustrative
## `res://tests/artifacts/...` path named in this feature's own
## test_criteria ("e.g."). This project has an established, documented
## precedent (FEAT-292's res://sim_results.json, FEAT-360's
## .test-output/def001_gate_captured_output.log) for exactly this
## situation: a GENERATED artifact that a test suite rewrites on every run
## must live at a git-ignored path, never a tracked one — otherwise every
## run leaves the working tree dirty and fails
## scripts/verify_clean_tree.sh's clean-tree CI gate (see that script's own
## header doc and CLAUDE.md's commit-hygiene section, which the
## FEAT-292/FEAT-360 precedents were themselves written to satisfy). Using
## a tracked path here would reintroduce that exact regression class for
## this feature's own artifact, so this writer intentionally does not use
## the literal example path.
##
## Evidence shape written/read (a flat, JSON-friendly Dictionary):
##   {
##     "schema_version":  int,
##     "start_token_hex": {"q": int, "r": int, "s": int},
##     "end_token_hex":   {"q": int, "r": int, "s": int},
##     "action_plan":     Array[String]   -- ordered action_type values,
##                                           e.g. ["Step", "Strike"]
##     "strike_outcome":  {"target_id": String, "hit": bool}
##   }
## The writer itself does not enforce this shape (callers may pass any
## JSON-serializable Dictionary) — the calling test is responsible for
## assembling it and for asserting the re-read shape matches what it
## observed in-test (no silently stale/mismatched evidence).

class_name DemoEvidenceWriter
extends RefCounted

const ARTIFACT_PATH: String = "res://.test-output/grunt_ai_demo_evidence.json"


## write_evidence(evidence, path) -> bool
##
## Writes `evidence` (a plain JSON-serializable Dictionary) to `path`
## (defaults to ARTIFACT_PATH) via write-to-temp-then-rename — mirrors
## autoload/current_game_state.gd's save_to_slot() convention — so a
## concurrent reader never observes a partially-written file.
##
## Success: creates `path`'s parent directory if it does not already
## exist, writes pretty-printed JSON, and returns true.
##
## Failure (fail-closed, never throws): returns false and push_errors a
## diagnostic when the parent directory can't be created/accessed, the
## temp file can't be opened for writing, or the temp-to-final rename
## fails. The previously-written file at `path` (if any) is left
## untouched on any failure path.
static func write_evidence(evidence: Dictionary, path: String = ARTIFACT_PATH) -> bool:
	var parent_dir: String = path.get_base_dir()
	var mkdir_err: int = DirAccess.make_dir_recursive_absolute(parent_dir)
	if mkdir_err != OK and mkdir_err != ERR_ALREADY_EXISTS:
		push_error(
			"DemoEvidenceWriter: unable to create/access evidence directory '%s' (error %d)"
			% [parent_dir, mkdir_err]
		)
		return false

	var tmp_path: String = path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"DemoEvidenceWriter: failed to open temp evidence file '%s' (error %d)"
			% [tmp_path, FileAccess.get_open_error()]
		)
		return false

	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()

	var rename_err: int = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		push_error(
			"DemoEvidenceWriter: failed to rename temp evidence file '%s' into place at '%s' (error %d)"
			% [tmp_path, path, rename_err]
		)
		return false

	return true


## read_evidence(path) -> Dictionary
##
## Reads and JSON-parses the evidence log at `path` (defaults to
## ARTIFACT_PATH).
##
## Success: returns the parsed Dictionary verbatim.
##
## Failure (fail-closed, never throws): returns {} (empty Dictionary) and
## push_errors a diagnostic when no file exists at `path`, the file can't
## be opened for reading, its contents are not valid JSON, or the parsed
## JSON is not an Object/Dictionary. Callers should treat an empty
## Dictionary as "no usable evidence" — a well-formed but genuinely empty
## evidence log is never a realistic value this writer itself would
## produce (write_evidence() always writes at least the caller's
## Dictionary, and this feature's own caller never writes {}).
static func read_evidence(path: String = ARTIFACT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DemoEvidenceWriter: no evidence file at '%s'" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error(
			"DemoEvidenceWriter: failed to open evidence file '%s' (error %d)"
			% [path, FileAccess.get_open_error()]
		)
		return {}

	var text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_err: int = parser.parse(text)
	if parse_err != OK:
		push_error(
			"DemoEvidenceWriter: malformed JSON in '%s' (%s at line %d)"
			% [path, parser.get_error_message(), parser.get_error_line()]
		)
		return {}

	var data = parser.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("DemoEvidenceWriter: evidence file '%s' did not parse to a Dictionary" % path)
		return {}

	return data
