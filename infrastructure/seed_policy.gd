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
## unset/empty, whitespace-only, non-numeric, or float-shaped — so a
## malformed HYKAEN_SEED fails OPEN to the random-fallback path instead of
## crashing boot (fail-safe default, NFR-006).
static func _parse_env_seed(raw: String):
	var trimmed: String = raw.strip_edges()
	if trimmed == "":
		return null
	if not trimmed.is_valid_int():
		return null
	return trimmed.to_int()
