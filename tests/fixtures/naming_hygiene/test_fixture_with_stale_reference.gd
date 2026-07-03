## tests/fixtures/naming_hygiene/test_fixture_with_stale_reference.gd
##
## FEAT-171 (DEF-003) fixture. NOT a real GUT test suite: it deliberately
## does NOT extend GutTest, so GUT's own test collector ignores it during a
## full-suite run rather than trying to execute it as a test script (see
## addons/gut/test_collector.gd's `_does_inherit_from_test` /
## `_parse_script`, which silently skip -- with only a log warning -- any
## "test_*.gd" file that doesn't inherit from GutTest).
##
## Exists solely so tests/integration/test_test_suite_naming_hygiene.gd can
## prove its NEW content-scanning guard actually reads file BODIES rather
## than just filenames: this file's FILENAME is entirely innocuous (no
## "steel_thread"/"steelthread"/"battlefield" substring anywhere in the
## path), but its BODY deliberately carries a stale
## res://scenes/battlefield/* reference -- the exact class of defect FIX-001
## (FEAT-170) found and fixed in
## tests/unit/test_steel_thread_prologue_encounter.gd, where a
## `res://scenes/battlefield`-era `instance.hex_battlefield` assertion
## survived long after the underlying HexBattlefield/StrikeInputController
## stack was removed from MainScene (FEAT-001) because the naming-hygiene
## guard at the time (US-004) only ever inspected filenames.
##
## DO NOT add this path to any allow-list in
## tests/integration/test_test_suite_naming_hygiene.gd -- the content-scan
## guard MUST fail when it scans this fixture's body, and a dedicated test
## asserts exactly that (DEF-003).
extends RefCounted

## Deliberately stale: mirrors the exact kind of dangling scene path FIX-001
## removed. A filename-only hygiene check would never see this, since
## nothing about this constant's NAME mentions battlefield/steel_thread.
const _STALE_BATTLEFIELD_SCENE_PATH: String = "res://scenes/battlefield/HexBattlefield.tscn"


func _stale_reference_example() -> void:
	# Also deliberately stale: the removed duplicate UI stack's identifiers.
	var _hex_battlefield_note: String = "HexBattlefield"
	var _strike_input_controller_note: String = "StrikeInputController"
