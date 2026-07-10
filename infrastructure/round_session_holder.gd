class_name RoundSessionHolder
extends RefCounted

## RoundSessionHolder — a stable indirection over the per-round RoundSession.
##
## RunRoundUseCase.begin_round() mints a NEW RoundSession object every round
## (see MainScene.rewire_session()). MainScene's own verb-closure code tolerates
## that because it reads `self.round_session` live on each call — but any code in
## a DIFFERENT object that captured the session reference at construction (an
## injected controller, a bound Callable) would silently go stale on the next
## round rollover.
##
## This holder is created ONCE and never replaced. Consumers hold the holder and
## call get_current() to reach the live session, so they can be injected a single
## time at construction and still follow round rollovers. MainScene swaps the
## inner session via set_current() (transparently, through its `round_session`
## property facade) each time rewire_session() begins a new round.
##
## Composition-root de-bloat (2026-07-10): this is the stable seam the extracted
## presentation/turn controllers inject instead of a raw, reassignable
## round_session reference.

## Untyped so this generic container carries no compile-time dependency on the
## RoundSession class (it is a pure pass-through); callers keep their own typing.
var _current = null


## get_current() — the live session for the current round, or null before the
## first round has been begun. Never cached by callers across a call boundary;
## always re-fetched so round rollovers are observed.
func get_current():
	return _current


## set_current(session) -> void — install the round's RoundSession. Called by
## MainScene.rewire_session() (via the `round_session` property setter) each time
## RunRoundUseCase.begin_round() mints a fresh session.
func set_current(session) -> void:
	_current = session


## has_current() -> bool — true once a session has been installed (i.e. the first
## round has begun). Mirrors the `round_session != null` guard MainScene uses.
func has_current() -> bool:
	return _current != null
