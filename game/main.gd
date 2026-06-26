extends Node
## game/main.gd
##
## Hykaen project entry-point scene script (FEAT-041 / DEF-003).
## Implements _ready() with a single INFO log line for CI artifact inspection.
## Contains no signal or display-server calls so it runs safely under --headless.


func _ready() -> void:
	print("INFO: Hykaen main scene loaded")
