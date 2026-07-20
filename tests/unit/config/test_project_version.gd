extends GutTest
## tests/unit/config/test_project_version.gd — FEAT-301 (US-009; resolves
## CHECKLIST-5)
##
## Deployment-readiness checklist item: "Bump config/version in
## project.godot from 0.1.0 to the target release version once the above
## are closed." This test asserts ProjectSettings reports the expected
## release version so version drift (a stale/blank/reverted
## application/config/version field in project.godot) is caught by the
## automated test suite rather than relying on manual inspection.
##
## test_criteria satisfied:
##   1. asserts ProjectSettings.get_setting('application/config/version')
##      == '0.2.0'.
##   2. fails if the version field is missing, blank, or still '0.1.0'
##      (covered explicitly, not just implicitly via the equality check
##      above, so a regression's failure mode is unambiguous).

const EXPECTED_VERSION: String = "0.2.0"
const STALE_VERSION: String = "0.1.0"


func test_project_settings_reports_expected_release_version() -> void:
	var version: Variant = ProjectSettings.get_setting("application/config/version")
	assert_eq(
		version, EXPECTED_VERSION,
		"application/config/version must report the target release version %s" % EXPECTED_VERSION
	)


func test_version_is_not_missing_or_blank() -> void:
	var version: Variant = ProjectSettings.get_setting("application/config/version", "")
	assert_true(
		version is String and not (version as String).is_empty(),
		"application/config/version must not be missing or blank"
	)


func test_version_is_not_the_stale_pre_release_value() -> void:
	var version: Variant = ProjectSettings.get_setting("application/config/version")
	assert_ne(
		version, STALE_VERSION,
		"application/config/version must have been bumped past the stale %s value" % STALE_VERSION
	)
