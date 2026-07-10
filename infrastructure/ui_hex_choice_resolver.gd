extends "res://core/application/ports/hex_choice_resolver_port.gd"

## UIHexChoiceResolver - the production, composition-root-only default
## implementation of HexChoiceResolverPort (FEAT-001 / US-004, ADR-002/G2).
## resolve(legal_hexes) highlights the legal destinations and blocks on
## hex_grid_view's REAL hex_clicked signal, looping until the player clicks one
## of legal_hexes - an off-target click is silently ignored, so it can NEVER
## fabricate/guess an answer of its own (G3 anti-punt discipline). An empty
## legal_hexes short-circuits to null immediately (the one legal null return, per
## the port's contract).
##
## Composition-root de-bloat (2026-07-10): extracted from a MainScene.gd inner
## class; wired ONLY by MainScene (never instantiated by a test), referenced via
## UIHexChoiceResolverClass.

var _hex_grid_view


func _init(p_hex_grid_view) -> void:
	_hex_grid_view = p_hex_grid_view


func resolve(legal_hexes: Array):
	if legal_hexes.is_empty():
		return null
	# Highlight the legal Dodge-Step destinations on the battlefield, reusing the
	# SAME hex_grid_view.set_selectable_hexes() overlay the Step verb's
	# movement_input_controller uses - so a Dodge-Step reads visually identical to
	# a normal Step instead of silently waiting for a click. Cleared the instant a
	# legal hex is picked so the highlight never lingers into the attacker's
	# continuing turn or the next actor.
	_hex_grid_view.set_selectable_hexes(legal_hexes)
	while true:
		var clicked = await _hex_grid_view.hex_clicked
		for hex in legal_hexes:
			if hex.equals(clicked):
				_hex_grid_view.set_selectable_hexes([])
				return hex
