extends "res://core/application/ports/targeting_port.gd"

## presentation/ui/player_targeting_port.gd — PlayerTargetingPort
##
## Interactive TargetingPort adapter: replaces the old _FirstLegalTargetingPort
## deterministic auto-pick with genuine player choice when two or more legal
## targets exist.
##
## Single-target fast-path: when legal_targets has exactly one entry the target
## is selected automatically without requiring a click — mirroring the old
## _FirstLegalTargetingPort behavior and keeping boot tests (which use a
## single-enemy prologue fixture) stable.
##
## Multi-target interactive path: highlights every legal target's hex on the
## battlefield via hex_grid_view.set_selectable_hexes(), then awaits
## hex_grid_view.hex_clicked in a loop until the player clicks one of the
## highlighted hexes — identical to infrastructure/ui_hex_choice_resolver.gd's
## "highlight + await + loop until valid" pattern for Dodge-Step selection.
## Off-target clicks are silently ignored (the loop continues) so the port can
## never fabricate a target of its own (mirrors HexChoiceResolverPort's own
## anti-punt discipline).
##
## async contract: request_single_target() contains `await` and is therefore a
## coroutine. Callers (ResolveSpellController.execute()) must `await` it.
## When the single-target fast-path runs, the await resolves synchronously
## (no engine-frame deferral), preserving the existing behavior for tests.

var _hex_grid_view


func _init(p_hex_grid_view) -> void:
	_hex_grid_view = p_hex_grid_view


func request_single_target(legal_targets: Array):
	if legal_targets.is_empty():
		return null
	# Fast-path: only one legal target — no UI needed.
	if legal_targets.size() == 1:
		return legal_targets[0]
	# Multi-target: build parallel target/hex arrays, highlight, await click.
	var targets_with_hexes: Array = []
	var highlight_hexes: Array = []
	for target in legal_targets:
		var hex = target.hex_coord
		if hex != null:
			targets_with_hexes.append(target)
			highlight_hexes.append(hex)
	if targets_with_hexes.is_empty():
		# Defensive: all targets had null hex_coord — fall back to first entry.
		return legal_targets[0]
	_hex_grid_view.set_selectable_hexes(highlight_hexes)
	while true:
		var clicked = await _hex_grid_view.hex_clicked
		for i in range(targets_with_hexes.size()):
			if highlight_hexes[i].equals(clicked):
				_hex_grid_view.set_selectable_hexes([])
				return targets_with_hexes[i]
