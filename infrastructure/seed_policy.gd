## infrastructure/seed_policy.gd — SeedPolicy (FEAT-003 / US-003 / FR-002 / NFR-003 / ADR-004)
##
## Infrastructure/Adapter layer (Clean Architecture): extracts the
## composition root's seed-resolution precedence rule into a small,
## independently unit-testable helper (see tests/gut/test_seed_policy.gd),
## rather than leaving that logic inline in MainScene.gd's _ready().
##
## Precedence (ADR-004), highest wins:
##   1. IN_PROCESS_INJECTED — an explicit, non-null `seed_override` value a
##      caller (typically MainScene's own `seed_override` property, settable
##      in-process by GUT tests BEFORE add_child()/_ready() completes
##      composition) supplied directly.
##   2. ENV_VAR — the HYKAEN_SEED environment variable, when it parses as a
##      valid integer. A malformed/non-integer value (or an unset/empty
##      variable) is NOT an error — it fails open, falling through to (3),
##      so a typo'd HYKAEN_SEED never blocks boot (NFR-006 headless smoke
##      test guarantee; see docs/iterations/iteration-C-backlog.org).
##   3. RANDOM — the caller-supplied random fallback (e.g. a fresh
##      Time.get_ticks_usec()-derived value), used when neither (1) nor (2)
##      resolved a seed.
##
## `resolve()` below is a PURE function (no OS access) so
## tests/gut/test_seed_policy.gd can exercise every precedence branch and the
## fail-open malformed-input path without touching real process environment
## state. `resolve_from_environment()` is the thin OS-reading wrapper the
## composition root actually calls, built on top of `resolve()`.
##
## Usage (composition root):
##   const SeedPolicyClass = preload("res://infrastructure/seed_policy.gd")
##   resolved_seed = SeedPolicyClass.resolve_from_environment(
##       seed_override, int(Time.get_ticks_usec())
##   )

class_name SeedPolicy
extends RefCounted

## ENV_VAR_NAME — the environment variable `resolve_from_environment()` reads
## as the fallback seed source when no in-process override is supplied.
const ENV_VAR_NAME: String = "HYKAEN_SEED"

## INT64_MAX_DIGITS / INT64_MIN_DIGITS — the decimal digit strings of
## GDScript's 64-bit signed integer bounds (INT64_MAX and abs(INT64_MIN)
## respectively). `is_valid_int()` only validates CHARACTER SHAPE (digits,
## optional leading sign) — it does NOT validate magnitude, so a 20+ digit
## numeric string like "99999999999999999999" passes `is_valid_int()` and
## then silently CLAMPS to INT64_MAX via `to_int()` instead of failing open
## to the random-seed path (FIND-147). `_is_within_int64_bounds()` below
## performs an explicit digit-length/magnitude comparison against these
## bounds BEFORE `to_int()` is ever called, so an out-of-range HYKAEN_SEED
## is rejected (fails open) rather than silently clamped.
const INT64_MAX_DIGITS: String = "9223372036854775807"
const INT64_MIN_ABS_DIGITS: String = "9223372036854775808"


## resolve(seed_override, env_var_raw, random_fallback) -> int
##
## Pure precedence resolution (ADR-004): in-process override > parsed
## HYKAEN_SEED env var > random fallback.
##   seed_override:   Variant — null to fall through, else a value coercible
##                     to int (the composition-root injection point).
##   env_var_raw:      String — the raw HYKAEN_SEED value (pass "" for
##                     unset/absent).
##   random_fallback:  int — the value used when neither of the above apply.
static func resolve(seed_override, env_var_raw: String, random_fallback: int) -> int:
	if seed_override != null:
		return int(seed_override)

	var parsed_env_seed = _parse_env_seed(env_var_raw)
	if parsed_env_seed != null:
		return parsed_env_seed

	return random_fallback


## resolve_from_environment(seed_override, random_fallback) -> int
##
## Composition-root-facing convenience wrapper: reads the REAL HYKAEN_SEED
## process environment variable via OS.get_environment(), then delegates the
## actual precedence/parsing decision to the pure `resolve()` above.
static func resolve_from_environment(seed_override, random_fallback: int) -> int:
	var env_var_raw: String = OS.get_environment(ENV_VAR_NAME) if OS.has_environment(ENV_VAR_NAME) else ""
	return resolve(seed_override, env_var_raw, random_fallback)


## _parse_env_seed(raw) -> Variant (int | null)
##
## Strictly parses `raw` as an integer (never eval'd, never used to
## construct dynamic code — pure string validation). Returns null (rather
## than throwing) for anything that is not a clean integer literal —
## unset/empty, whitespace-only, non-numeric, float-shaped, hex-looking
## ("0x10"), or injection-shaped ("$(whoami)") — so a malformed HYKAEN_SEED
## fails OPEN to the random-fallback path instead of crashing boot
## (fail-safe default, NFR-006).
##
## `is_valid_int()` only validates CHARACTER SHAPE (digits, optional
## leading sign) — it does NOT validate magnitude. Without an explicit
## bounds check, a 20+ digit numeric string would pass `is_valid_int()`
## and then silently CLAMP to INT64_MAX via `to_int()` (FIND-147) instead
## of failing open. `_is_within_int64_bounds()` rejects any digit string
## whose magnitude exceeds GDScript's 64-bit signed integer range before
## `to_int()` is ever called.
static func _parse_env_seed(raw: String):
	var trimmed: String = raw.strip_edges()
	if trimmed == "":
		return null
	if not trimmed.is_valid_int():
		return null
	if not _is_within_int64_bounds(trimmed):
		return null
	return trimmed.to_int()


## _is_within_int64_bounds(digits) -> bool
##
## `digits` is assumed to already satisfy `is_valid_int()` (optional
## leading '-', otherwise all ASCII digits). Returns false when the
## magnitude of `digits` falls outside GDScript's 64-bit signed integer
## range ([-9223372036854775808, 9223372036854775807]) — i.e. when a naive
## `to_int()` call would silently clamp/overflow rather than represent the
## literal value exactly.
static func _is_within_int64_bounds(digits: String) -> bool:
	var is_negative: bool = digits.begins_with("-")
	var magnitude: String = digits.substr(1) if is_negative else digits

	# Leading zeros ("007", "0000123") are semantically insignificant for
	# magnitude comparison — strip them before comparing digit counts.
	var normalized: String = magnitude.lstrip("0")
	if normalized == "":
		normalized = "0"

	var bound: String = INT64_MIN_ABS_DIGITS if is_negative else INT64_MAX_DIGITS

	if normalized.length() != bound.length():
		return normalized.length() < bound.length()

	# Same digit count: plain lexical (ASCII) comparison of equal-length,
	# all-digit strings is equivalent to numeric comparison.
	return normalized <= bound
