## core/api/rest_action_guard.gd — RestActionGuard (FEAT-006 / US-010;
## FR-012, ADR-005; iteration AB-0, rest mechanics steel thread).
##
## API/facade layer (thin seam between PRESENTATION and APPLICATION — see
## design notes' architecture section 3 and api_contracts #1). This is the
## ONLY place a Rest action's "are we out of combat" precondition is
## checked: RestPanelController (a later feature) wires each Rest button
## through invoke() rather than calling ShortRestHealUseCase /
## ShortRestMageRechargeUseCase / LongRestUseCase directly, so those use
## cases stay entirely ignorant of "game mode" (a presentation/session
## concept — keeping it out of the application layer is the whole point of
## this facade). This is defense-in-depth on top of the Rest button
## already being hidden in COMBAT mode by the HUD (belt-and-braces: UI
## hides the entry point, this facade independently re-checks immediately
## before any use-case call could mutate state) — protects against a
## stale/leaked panel reference being invoked after a mode transition
## (e.g. an ambush triggering COMBAT while the Rest panel is still open).
##
## Extends RefCounted only: no Node/Control/SceneTree inheritance, no
## engine lifecycle coupling (ADR-001).
##
## api_contracts #1: invoke(game_mode, use_case_call) -> Dictionary
##   Request: the current game mode (an int, or anything
##     core/api/game_mode_reader.gd's GameModeReader.read() accepts — see
##     that file's header for the full duck-typed contract) PLUS a bound
##     use-case invocation (a zero-argument Callable, e.g.
##     `Callable(short_rest_heal_use_case, "execute").bind(combatant, 1)`
##     or an equivalent lambda).
##   EXPLORATION mode (game_mode != GameModeReader.COMBAT): the bound
##     Callable IS invoked, and its return Dictionary is passed through
##     completely unchanged — invoke() adds/removes nothing from it.
##   COMBAT mode (game_mode == GameModeReader.COMBAT): the bound Callable
##     is NEVER invoked — no side effects of any kind are attempted — and
##     invoke() short-circuits, returning
##     {success: false, error: ErrorCode.ERR_OUT_OF_COMBAT_ONLY}.
##
## The game-mode read itself is factored into the SHARED
## core/api/game_mode_reader.gd helper rather than duplicated/reimplemented
## here, so this facade's execution check and the future ExplorationHUD
## visibility scan (FEAT-007) can never structurally diverge on what
## "current game mode" means (RISK-007 mitigation — see that file's own
## header for the full rationale).

class_name RestActionGuard
extends RefCounted

const GameModeReaderClass = preload("res://core/api/game_mode_reader.gd")
const ErrorCodeClass = preload("res://core/application/ports/errors.gd")

var _game_mode_reader = GameModeReaderClass.new()


## invoke(game_mode, use_case_call: Callable) -> Dictionary — api_contracts
## #1. `game_mode` is read through the shared GameModeReader (see file
## header); `use_case_call` must be a zero-argument Callable already bound
## to whichever use case and arguments the caller wants executed.
func invoke(game_mode, use_case_call: Callable) -> Dictionary:
	var mode: int = _game_mode_reader.read(game_mode)
	if mode == GameModeReaderClass.COMBAT:
		return {"success": false, "error": ErrorCodeClass.ERR_OUT_OF_COMBAT_ONLY}
	return use_case_call.call()
