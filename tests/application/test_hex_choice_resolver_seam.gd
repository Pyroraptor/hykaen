extends GutTest
## tests/application/test_hex_choice_resolver_seam.gd
##
## GUT test suite for FEAT-001 (US-004, ADR-002/G2): the
## HexChoiceResolverPort seam (core/application/ports/
## hex_choice_resolver_port.gd) and its composition-root wiring into
## MainScene.gd (`hex_choice_resolver` field + resolve_hex_choice()).
##
## Verifies (this feature's test_criteria):
##   1. Seam-level test proves scripted hex choices flow through REAL
##      MainScene composition-root wiring — never a resolver a test
##      constructs and invokes directly in isolation (self-wiring).
##   2. The production default (unscripted) passthrough requires/blocks on
##      real human/UI input — it must never silently fabricate/return an
##      arbitrary hex, and it must never auto-resolve on its own.
##   3. HexChoiceResolverPort.resolve(legal_hexes) returns null ONLY when
##      legal_hexes is empty.

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const HexChoiceResolverPortClass = preload("res://core/application/ports/hex_choice_resolver_port.gd")
const HexCoordClass = preload("res://core/geometry/hex_coord.gd")


## ScriptedHexChoiceResolver — a concrete, scripted HexChoiceResolverPort
## test double (mirrors infrastructure/auto_reaction_chooser.gd's role for
## ReactionChooserPort): always returns the pre-configured `_scripted_hex`
## for a non-empty legal_hexes (recording what it was handed for assertion),
## and null for an empty legal_hexes — exercising the SAME "null only when
## empty" contract the production adapter must uphold.
class ScriptedHexChoiceResolver:
	extends "res://core/application/ports/hex_choice_resolver_port.gd"

	var _scripted_hex
	var received_legal_hexes: Array = []
	var call_count: int = 0

	func _init(scripted_hex) -> void:
		_scripted_hex = scripted_hex

	func resolve(legal_hexes: Array):
		call_count += 1
		received_legal_hexes = legal_hexes
		if legal_hexes.is_empty():
			return null
		return _scripted_hex


## _boot_main_scene() -> Node — instantiates the REAL res://MainScene.tscn
## composition root, pinning seed_override=42 (this codebase's established
## deterministic-fixture convention — see
## tests/gut/test_mainscene_reaction_resolver_wiring.gd) so every scenario
## below can rely on a deterministic boot.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = 42
	add_child_autofree(instance)
	return instance


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — scripted hex choices flow through REAL MainScene
# composition-root wiring (no test self-wiring).
# ══════════════════════════════════════════════════════════════════════════

func test_default_hex_choice_resolver_is_wired_at_boot() -> void:
	var instance = _boot_main_scene()

	assert_not_null(instance.hex_grid_view, "fixture: MainScene must wire a real hex_grid_view")
	assert_not_null(instance.hex_choice_resolver, "MainScene must wire a default hex_choice_resolver during initialization")
	assert_true(
		is_instance_of(instance.hex_choice_resolver, HexChoiceResolverPortClass),
		"the wired default must itself satisfy the HexChoiceResolverPort contract"
	)


func test_scripted_hex_choice_resolver_flows_through_mainscenes_own_resolve_hex_choice() -> void:
	var instance = _boot_main_scene()

	var target_hex := HexCoordClass.new(1, 0)
	var other_hex := HexCoordClass.new(0, 1)
	var legal_hexes: Array = [target_hex, other_hex]

	var scripted := ScriptedHexChoiceResolver.new(target_hex)
	# Composition-root injection point — assigning directly onto the real,
	# booted instance's own field, exactly mirroring how
	# test_mainscene_reaction_resolver_wiring.gd substitutes wiring on the
	# real instance rather than building/self-wiring a parallel resolver.
	instance.hex_choice_resolver = scripted

	# The call goes through MainScene's OWN resolve_hex_choice() — the real
	# production call path this feature establishes — never a direct call to
	# `scripted.resolve(...)` in isolation.
	var result = await instance.resolve_hex_choice(legal_hexes)

	assert_not_null(result, "a scripted resolver handed a non-empty legal_hexes must never resolve to null")
	assert_true(result.equals(target_hex), "MainScene.resolve_hex_choice() must return exactly the scripted choice")
	assert_eq(scripted.call_count, 1, "resolve_hex_choice() must invoke the injected resolver exactly once")
	assert_eq(scripted.received_legal_hexes, legal_hexes, "the injected resolver must receive the SAME legal_hexes MainScene was handed, unmodified")


func test_a_second_scripted_choice_also_flows_through_the_same_real_wiring() -> void:
	var instance = _boot_main_scene()

	var target_hex := HexCoordClass.new(-2, 3)
	var legal_hexes: Array = [HexCoordClass.new(0, 0), target_hex]

	instance.hex_choice_resolver = ScriptedHexChoiceResolver.new(target_hex)

	var result = await instance.resolve_hex_choice(legal_hexes)

	assert_true(result.equals(target_hex), "wiring a fresh scripted resolver onto the real instance must resolve through it correctly")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — the production default requires/blocks on real human/UI
# input when not scripted (never silently returns an arbitrary hex).
# ══════════════════════════════════════════════════════════════════════════

func test_production_default_never_resolves_on_its_own_absent_a_real_click() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var legal_hexes: Array = [HexCoordClass.new(1, 0), HexCoordClass.new(0, 1)]

	var captured := {"done": false, "value": null}
	var runner := func():
		var v = await instance.resolve_hex_choice(legal_hexes)
		captured["done"] = true
		captured["value"] = v
	# Fire-and-forget: starts resolve_hex_choice(), which must suspend on the
	# real hex_grid_view.hex_clicked signal rather than fabricate an answer
	# synchronously.
	runner.call()

	assert_false(captured["done"], "resolve_hex_choice() must not resolve synchronously for a non-empty legal_hexes with no click yet")

	for i in range(5):
		await get_tree().process_frame
	assert_false(captured["done"], "the production default must never auto-resolve on its own (no hidden timer/fallback) absent real input")


func test_production_default_ignores_an_illegal_click_and_only_resolves_on_a_legal_one() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var legal_a := HexCoordClass.new(1, 0)
	var legal_b := HexCoordClass.new(0, 1)
	var illegal := HexCoordClass.new(9, 9)
	var legal_hexes: Array = [legal_a, legal_b]

	var captured := {"done": false, "value": null}
	var runner := func():
		var v = await instance.resolve_hex_choice(legal_hexes)
		captured["done"] = true
		captured["value"] = v
	runner.call()

	# An off-target click must be silently ignored -- never accepted as a
	# stand-in "arbitrary hex" answer.
	instance.hex_grid_view.hex_clicked.emit(illegal)
	await get_tree().process_frame
	assert_false(captured["done"], "a click on a hex outside legal_hexes must never resolve the prompt")

	# The real, legal click resolves it -- proving this adapter genuinely
	# requires/awaits real human/UI input rather than defaulting to
	# anything on its own.
	instance.hex_grid_view.hex_clicked.emit(legal_b)
	await get_tree().process_frame

	assert_true(captured["done"], "a click on a legal hex must resolve resolve_hex_choice()")
	assert_true(captured["value"].equals(legal_b), "resolve_hex_choice() must return exactly the hex the player clicked, never a substituted/arbitrary one")


func test_production_default_returns_null_immediately_for_empty_legal_hexes() -> void:
	var instance = _boot_main_scene()
	await get_tree().process_frame

	var result = await instance.resolve_hex_choice([])

	assert_null(result, "an empty legal_hexes must resolve to null without ever waiting on a click")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — HexChoiceResolverPort.resolve(legal_hexes) returns null ONLY
# when legal_hexes is empty.
# ══════════════════════════════════════════════════════════════════════════

func test_abstract_base_port_resolve_returns_null_for_empty_legal_hexes() -> void:
	var port := HexChoiceResolverPortClass.new()

	assert_null(port.resolve([]), "the base Port's own fail-safe contract: empty legal_hexes always yields null")


func test_scripted_resolver_never_returns_null_for_non_empty_legal_hexes() -> void:
	var hex_a := HexCoordClass.new(4, -1)
	var resolver := ScriptedHexChoiceResolver.new(hex_a)

	var result = resolver.resolve([hex_a, HexCoordClass.new(0, 0)])

	assert_not_null(result, "a conforming resolver must never return null for a non-empty legal_hexes")
	assert_true(result.equals(hex_a))


func test_scripted_resolver_returns_null_only_for_empty_legal_hexes() -> void:
	var resolver := ScriptedHexChoiceResolver.new(HexCoordClass.new(2, 2))

	assert_null(resolver.resolve([]), "empty legal_hexes must resolve to null")
	assert_not_null(resolver.resolve([HexCoordClass.new(2, 2)]), "a non-empty legal_hexes must never resolve to null")
