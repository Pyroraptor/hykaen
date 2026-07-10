extends "res://core/application/round_history_port.gd"

## InMemoryRoundHistoryAdapter - implements RoundHistoryPort over a plain
## in-memory Array, mirroring core/combat/encounter.gd's own private
## _RoundHistoryAdapter pattern.
##
## Composition-root de-bloat (2026-07-10): extracted from a MainScene.gd inner
## class; wired ONLY by MainScene, referenced via
## InMemoryRoundHistoryAdapterClass.

var _entries: Array = []


func append(entry: Dictionary) -> void:
	_entries.append(entry)


func get_history() -> Array:
	return _entries
