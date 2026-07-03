extends GutTest
## tests/gut/test_seed_policy.gd — FEAT-003 (US-003 / FR-002 / NFR-003 / ADR-004)
##
## Unit tests for infrastructure/seed_policy.gd's precedence rule:
## in-process override > HYKAEN_SEED env var > random fallback, plus the
## fail-open guarantee for a malformed/non-integer HYKAEN_SEED (NFR-006 —
## boot must never crash on a bad env var).
##
## test_criteria satisfied:
##   1. precedence: in-process override wins over HYKAEN_SEED env var wins
##      over random default.
##   2. a malformed/non-integer HYKAEN_SEED falls back to random-seed
##      generation without throwing (fail-open).

const SeedPolicyClass = preload("res://infrastructure/seed_policy.gd")

const OVERRIDE_SEED: int = 42
const ENV_SEED: int = 777
const RANDOM_FALLBACK: int = 999999


# ══════════════════════════════════════════════════════════════════════════
# Part 1 — resolve() precedence: pure-function coverage, no OS env access.
# ══════════════════════════════════════════════════════════════════════════

func test_in_process_override_wins_over_env_var_and_random() -> void:
	var resolved: int = SeedPolicyClass.resolve(OVERRIDE_SEED, str(ENV_SEED), RANDOM_FALLBACK)
	assert_eq(
		resolved, OVERRIDE_SEED,
		"an explicit in-process seed_override must win over a present, valid HYKAEN_SEED env var"
	)


func test_in_process_override_wins_over_random_when_env_var_absent() -> void:
	var resolved: int = SeedPolicyClass.resolve(OVERRIDE_SEED, "", RANDOM_FALLBACK)
	assert_eq(
		resolved, OVERRIDE_SEED,
		"an explicit in-process seed_override must win even when no env var is present"
	)


func test_env_var_wins_over_random_when_no_override() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, str(ENV_SEED), RANDOM_FALLBACK)
	assert_eq(
		resolved, ENV_SEED,
		"a valid HYKAEN_SEED env var must win over the random fallback when no in-process override is set"
	)


func test_random_fallback_used_when_no_override_and_no_env_var() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"the random fallback must be used when neither an override nor a HYKAEN_SEED env var is present"
	)


func test_override_of_zero_is_respected_not_treated_as_falsy() -> void:
	# GDScript falsiness pitfall guard: 0 is a legitimate seed value and must
	# NOT be treated the same as "no override" (only `null` means "fall
	# through").
	var resolved: int = SeedPolicyClass.resolve(0, str(ENV_SEED), RANDOM_FALLBACK)
	assert_eq(resolved, 0, "an explicit override of 0 must be respected, not treated as absent")


# ══════════════════════════════════════════════════════════════════════════
# Part 2 — fail-open: a malformed/non-integer HYKAEN_SEED must NOT throw,
# and must fall back to the random-seed path (never silently to 0, never a
# crash).
# ══════════════════════════════════════════════════════════════════════════

func test_non_integer_env_var_falls_back_to_random_without_throwing() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "not-a-number", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a non-integer HYKAEN_SEED must fail open to the random fallback"
	)


func test_float_shaped_env_var_falls_back_to_random_without_throwing() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "12.5", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a float-shaped HYKAEN_SEED (e.g. '12.5') must fail open to the random fallback, not be truncated/coerced"
	)


func test_whitespace_only_env_var_falls_back_to_random_without_throwing() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "   ", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a whitespace-only HYKAEN_SEED must fail open to the random fallback"
	)


func test_empty_env_var_falls_back_to_random_without_throwing() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"an empty/absent HYKAEN_SEED must fail open to the random fallback"
	)


func test_env_var_with_surrounding_whitespace_is_trimmed_and_parsed() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "  %d  " % ENV_SEED, RANDOM_FALLBACK)
	assert_eq(
		resolved, ENV_SEED,
		"a valid HYKAEN_SEED with surrounding whitespace must still be parsed (trimmed)"
	)


func test_negative_integer_env_var_is_parsed() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "-5", RANDOM_FALLBACK)
	assert_eq(resolved, -5, "a negative integer HYKAEN_SEED must be parsed as a valid seed")


# ══════════════════════════════════════════════════════════════════════════
# Part 2b — FIND-147 / FIND-148 regressions: overflow, hex-looking,
# leading-zero, and injection-shaped HYKAEN_SEED values must never crash
# boot and must never silently clamp/eval — they either parse to the exact
# intended integer or fail open to the random fallback.
# ══════════════════════════════════════════════════════════════════════════

func test_twenty_digit_numeric_env_var_falls_back_to_random_not_clamped_to_int64_max() -> void:
	# is_valid_int() only checks character shape, so this 20-digit numeric
	# string would previously pass validation and then silently clamp to
	# INT64_MAX (9223372036854775807) via to_int() instead of failing open
	# (FIND-147). It must now be rejected by the explicit magnitude/length
	# bound check and fall open to the random-seed path.
	var resolved: int = SeedPolicyClass.resolve(null, "99999999999999999999", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a 20+ digit numeric HYKAEN_SEED must fail open to the random fallback, not silently clamp to INT64_MAX"
	)
	assert_ne(
		resolved, 9223372036854775807,
		"a 20+ digit numeric HYKAEN_SEED must never resolve to a silently-clamped INT64_MAX"
	)


func test_env_var_one_past_int64_max_falls_back_to_random() -> void:
	# 19 digits, same length as INT64_MAX, but numerically one past it —
	# exercises the magnitude comparison, not just the digit-count check.
	var resolved: int = SeedPolicyClass.resolve(null, "9223372036854775808", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a HYKAEN_SEED one past INT64_MAX must fail open to the random fallback rather than clamp"
	)


func test_env_var_exactly_int64_max_is_parsed_exactly() -> void:
	# The boundary value itself must still parse successfully (not an
	# off-by-one rejection of legitimate large seeds).
	var resolved: int = SeedPolicyClass.resolve(null, "9223372036854775807", RANDOM_FALLBACK)
	assert_eq(resolved, 9223372036854775807, "HYKAEN_SEED exactly at INT64_MAX must be parsed exactly, not rejected")


func test_env_var_exactly_int64_min_is_parsed_exactly() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "-9223372036854775808", RANDOM_FALLBACK)
	assert_eq(resolved, -9223372036854775808, "HYKAEN_SEED exactly at INT64_MIN must be parsed exactly, not rejected")


func test_negative_twenty_digit_env_var_falls_back_to_random() -> void:
	var resolved: int = SeedPolicyClass.resolve(null, "-99999999999999999999", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a negative 20+ digit HYKAEN_SEED must fail open to the random fallback, not clamp to INT64_MIN"
	)


func test_hex_looking_env_var_falls_back_to_random_without_crashing() -> void:
	# FIND-148: a hex-looking value like "0x10" must not crash boot and
	# must not be interpreted as hex (16) — is_valid_int() rejects the 'x'
	# character shape, so this falls open to the random fallback.
	var resolved: int = SeedPolicyClass.resolve(null, "0x10", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"a hex-looking HYKAEN_SEED ('0x10') must fall open to the random fallback without crashing"
	)


func test_leading_zero_env_var_is_parsed_as_intended_integer() -> void:
	# "007" is a clean integer literal with insignificant leading zeros —
	# documented/asserted behavior: it parses to the intended integer 7,
	# it is not rejected and does not fall open to random.
	var resolved: int = SeedPolicyClass.resolve(null, "007", RANDOM_FALLBACK)
	assert_eq(resolved, 7, "a leading-zero HYKAEN_SEED ('007') must parse as the intended integer 7")


func test_leading_zero_padded_int64_max_boundary_still_rejects_correctly() -> void:
	# Leading zeros must not throw off the magnitude comparison used for
	# the overflow bound check: this is INT64_MAX with a padding zero and
	# must parse exactly, not be misclassified as out-of-bounds due to the
	# extra leading digit.
	var resolved: int = SeedPolicyClass.resolve(null, "09223372036854775807", RANDOM_FALLBACK)
	assert_eq(
		resolved, 9223372036854775807,
		"a leading-zero-padded INT64_MAX HYKAEN_SEED must still parse exactly (leading zeros are insignificant)"
	)


func test_injection_shaped_env_var_falls_back_to_random_without_being_evaluated() -> void:
	# FIND-148: a shell-injection-shaped value must never be eval'd/executed
	# — it is pure string validation, so this simply fails is_valid_int()
	# shape checking and falls open to the random fallback.
	var resolved: int = SeedPolicyClass.resolve(null, "$(whoami)", RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"an injection-shaped HYKAEN_SEED ('$(whoami)') must fall open to the random fallback without being eval'd"
	)


# ══════════════════════════════════════════════════════════════════════════
# Part 3 — resolve_from_environment(): the OS-reading wrapper, exercised
# against the REAL process environment (set/unset around each assertion so
# no test state leaks to any other GUT script in the same headless run).
# ══════════════════════════════════════════════════════════════════════════

var _had_env_var_before: bool = false
var _original_env_value: String = ""


func before_each() -> void:
	_had_env_var_before = OS.has_environment(SeedPolicyClass.ENV_VAR_NAME)
	if _had_env_var_before:
		_original_env_value = OS.get_environment(SeedPolicyClass.ENV_VAR_NAME)


func after_each() -> void:
	if _had_env_var_before:
		OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, _original_env_value)
	else:
		OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)


func test_resolve_from_environment_prefers_override_over_real_env_var() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(ENV_SEED))
	var resolved: int = SeedPolicyClass.resolve_from_environment(OVERRIDE_SEED, RANDOM_FALLBACK)
	assert_eq(resolved, OVERRIDE_SEED, "resolve_from_environment() must prefer the in-process override over a real HYKAEN_SEED env var")


func test_resolve_from_environment_reads_real_env_var_when_no_override() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, str(ENV_SEED))
	var resolved: int = SeedPolicyClass.resolve_from_environment(null, RANDOM_FALLBACK)
	assert_eq(resolved, ENV_SEED, "resolve_from_environment() must read the real HYKAEN_SEED env var when no override is set")


func test_resolve_from_environment_falls_back_to_random_when_env_var_unset() -> void:
	OS.unset_environment(SeedPolicyClass.ENV_VAR_NAME)
	var resolved: int = SeedPolicyClass.resolve_from_environment(null, RANDOM_FALLBACK)
	assert_eq(resolved, RANDOM_FALLBACK, "resolve_from_environment() must fall back to the random value when HYKAEN_SEED is unset")


func test_resolve_from_environment_fails_open_on_malformed_real_env_var_without_throwing() -> void:
	OS.set_environment(SeedPolicyClass.ENV_VAR_NAME, "not-an-integer")
	var resolved: int = SeedPolicyClass.resolve_from_environment(null, RANDOM_FALLBACK)
	assert_eq(
		resolved, RANDOM_FALLBACK,
		"resolve_from_environment() must fail open to the random fallback (no exception) when the real HYKAEN_SEED env var is malformed"
	)
