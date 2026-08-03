## core/api/game_mode_reader.gd — GameModeReader (FEAT-006 / US-010; FR-012,
## ADR-005; iteration AB-0, rest mechanics steel thread).
##
## API/facade layer (thin seam between PRESENTATION and APPLICATION — see
## design notes' architecture section 3): the SINGLE shared helper that
## knows how to read "the current game mode" and normalize it to a plain
## int, so that logic which needs to branch on game mode can be written
## ONCE and reused IDENTICALLY by every caller. This iteration's caller is
## core/api/rest_action_guard.gd's RestActionGuard.invoke() (the
## out-of-combat execution guard); a future feature (FEAT-007, the
## ExplorationHUD Rest-button visibility scan) reuses this exact same
## function for its own "are we in combat" read — directly mitigating
## RISK-007 (drift between visibility and execution checks: if the two
## call sites duck-typed/derived "current game mode" independently, they
## could silently diverge on an edge case; a single shared function makes
## that structurally impossible).
##
## Extends RefCounted only: no Node/Control/SceneTree inheritance, no
## engine lifecycle coupling (ADR-001) — this file lives in the API layer,
## not application/domain, but still never depends on a live scene tree to
## be unit-testable in isolation.
##
## Mirrors MainScene.gd's own `enum GameMode { EXPLORATION, COMBAT }`
## ordinal values (EXPLORATION=0, COMBAT=1) so an int read from a real
## MainScene's `_game_mode` field compares equal to the constants below
## with no translation step required.
##
## read(source) -> int accepts, via the SAME defensive duck-typed access
## established elsewhere in this codebase (BeginCastUseCase._duck_get() /
## LongRestUseCase._duck_get() / ShortRestHealUseCase._duck_get()), any of:
##   - a plain int already (the mode itself) — returned unchanged. This is
##     what a "guard-style caller" passes: RestActionGuard.invoke()'s
##     `game_mode` parameter is already resolved to an int by its own
##     caller, so read() simply passes it through.
##   - an Object exposing a `game_mode` property (real property, e.g. a
##     small test double), read via Object.get() — what a "HUD-style
##     caller" would pass if it were handed a mode-carrying object rather
##     than an already-resolved int.
##   - a Dictionary with a "game_mode" key, read via Dictionary.get().
##   - null — defaults to EXPLORATION (never crashes; a missing/absent
##     source must not be interpreted as COMBAT, since that would fail
##     CLOSED for every other consumer of this helper in a way that is not
##     this feature's job to decide — the guard's own COMBAT check is the
##     single place that treats "unknown" as "not blocked").

class_name GameModeReader
extends RefCounted

## Mirrors MainScene.GameMode's ordinal values verbatim (EXPLORATION=0,
## COMBAT=1) — see file header.
const EXPLORATION: int = 0
const COMBAT: int = 1


func read(source) -> int:
	if source == null:
		return EXPLORATION
	if source is int:
		return source
	if source is float:
		return int(source)
	if source is Dictionary:
		return int(source.get("game_mode", EXPLORATION))
	var value = source.get("game_mode")
	return int(value) if value != null else EXPLORATION
