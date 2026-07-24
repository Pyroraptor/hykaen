extends GutTest
## tests/gut/test_presentation_adapters.gd — FEAT-002 (US-002; FR-001;
## ADR-002).
##
## GUT test suite proving the five inner adapter/port classes formerly
## defined inline inside MainScene.gd (`_CoreCastSpellAdapter`,
## `_GdVerbRegistryPort`, `_GdCombineActionEconomyPort`,
## `_CombineTargetingRegistryProxy`, `_CombineBuildRegistryProxy` — former
## lines 3537-3678) now exist as standalone, top-level classes under
## presentation/adapters/, exposing the EXACT SAME public
## methods/signatures and behavior as the originals they were extracted
## from VERBATIM.
##
## test_criteria satisfied:
##   1. Each of the 5 adapter classes exposes the same public methods/
##      signatures as the original inner classes (has_method() +
##      behavioral parity checks below).
##   2. (Verified by grep in this feature's own review, not here): the
##      former inner class definitions no longer exist in MainScene.gd —
##      MainScene.gd now preload()s these 5 files instead.
##   3. Full GUT suite passes with no regression vs. FEAT-001 baseline
##      (verified by running the whole suite, not scoped to this file).

const CoreCastSpellAdapterClass = preload("res://presentation/adapters/core_cast_spell_adapter.gd")
const GdVerbRegistryPortClass = preload("res://presentation/adapters/gd_verb_registry_port.gd")
const GdCombineActionEconomyPortClass = preload("res://presentation/adapters/gd_combine_action_economy_port.gd")
const CombineTargetingRegistryProxyClass = preload("res://presentation/adapters/combine_targeting_registry_proxy.gd")
const CombineBuildRegistryProxyClass = preload("res://presentation/adapters/combine_build_registry_proxy.gd")

const VerbControllerPortClass = preload("res://core/application/combine/verb_controller_port.gd")
const VerbRegistryPortClass = preload("res://core/application/combine/verb_registry_port.gd")
const ActionEconomyPortClass = preload("res://core/application/ports/action_economy_port.gd")


# ══════════════════════════════════════════════════════════════════════════
# 1) CoreCastSpellAdapter — VerbControllerPort adapter
# ══════════════════════════════════════════════════════════════════════════

func test_core_cast_spell_adapter_extends_verb_controller_port() -> void:
	var adapter = CoreCastSpellAdapterClass.new({})
	assert_true(adapter is VerbControllerPortClass,
		"CoreCastSpellAdapter must extend VerbControllerPort")


func test_core_cast_spell_adapter_exposes_enter_selection_signature() -> void:
	var adapter = CoreCastSpellAdapterClass.new({})
	assert_true(adapter.has_method("enter_selection"),
		"CoreCastSpellAdapter must expose enter_selection(context)")


func test_core_cast_spell_adapter_resolution_phase_wraps_selected_hex() -> void:
	var adapter = CoreCastSpellAdapterClass.new({})
	var descriptor = adapter.enter_selection({"order_index": 2, "selected_hex": "target_x"})
	assert_true(descriptor.ok, "resolution phase with selected_hex should be ok=true")
	assert_eq(descriptor.order_index, 2)
	assert_eq(descriptor.meta.get("chosen_target"), "target_x")


func test_core_cast_spell_adapter_offer_phase_without_ctrl_fn_fails_safe() -> void:
	var adapter = CoreCastSpellAdapterClass.new({})
	var descriptor = adapter.enter_selection({"order_index": 0})
	assert_false(descriptor.ok, "no get_ctrl_fn injected should fail safe, not crash")
	assert_eq(descriptor.meta.get("error_code"), "NO_LEGAL_OPTIONS")


func test_core_cast_spell_adapter_offer_phase_delegates_to_presentation_controller() -> void:
	var fake_pres_ctrl = _FakeSpellPresentationController.new(["spell_a", "spell_b"])
	var adapter = CoreCastSpellAdapterClass.new({
		"get_ctrl_fn": func(): return fake_pres_ctrl,
	})
	var descriptor = adapter.enter_selection({"order_index": 1})
	assert_true(descriptor.ok)
	assert_eq(descriptor.candidate_options, ["spell_a", "spell_b"])
	assert_eq(descriptor.order_index, 1)


# ══════════════════════════════════════════════════════════════════════════
# 2) GdVerbRegistryPort — VerbRegistryPort adapter
# ══════════════════════════════════════════════════════════════════════════

func test_gd_verb_registry_port_extends_verb_registry_port() -> void:
	var port = GdVerbRegistryPortClass.new()
	assert_true(port is VerbRegistryPortClass,
		"GdVerbRegistryPort must extend VerbRegistryPort")


func test_gd_verb_registry_port_exposes_get_available_verbs_signature() -> void:
	var port = GdVerbRegistryPortClass.new()
	assert_true(port.has_method("get_available_verbs"))


func test_gd_verb_registry_port_returns_loaded_verb_resources() -> void:
	var port = GdVerbRegistryPortClass.new()
	var verbs: Array = port.get_available_verbs(null, {})
	assert_true(verbs.size() >= 2,
		"expected at least STRIDE and STRIKE verb resources to load")


# ══════════════════════════════════════════════════════════════════════════
# 3) GdCombineActionEconomyPort — ActionEconomyPort adapter
# ══════════════════════════════════════════════════════════════════════════

func test_gd_combine_action_economy_port_extends_action_economy_port() -> void:
	var port = GdCombineActionEconomyPortClass.new(_FakeOwnerNoEconomy.new())
	assert_true(port is ActionEconomyPortClass,
		"GdCombineActionEconomyPort must extend ActionEconomyPort")


func test_gd_combine_action_economy_port_exposes_full_signature() -> void:
	var port = GdCombineActionEconomyPortClass.new(_FakeOwnerNoEconomy.new())
	assert_true(port.has_method("spend_action"))
	assert_true(port.has_method("spend_reaction"))
	assert_true(port.has_method("is_spent"))
	assert_true(port.has_method("get_remaining"))


func test_gd_combine_action_economy_port_degrades_safely_with_no_live_economy() -> void:
	var port = GdCombineActionEconomyPortClass.new(_FakeOwnerNoEconomy.new())
	var spend_result: Dictionary = port.spend_action({})
	assert_false(spend_result.get("success", true))
	assert_false(spend_result.get("ok", true))
	assert_true(port.is_spent(), "no live economy should report is_spent()=true")
	assert_eq(port.get_remaining(), 0)


func test_gd_combine_action_economy_port_lazily_resolves_live_economy_each_call() -> void:
	var fake_economy = _FakeActionEconomy.new()
	var owner = _FakeOwnerWithEconomy.new(fake_economy)
	var port = GdCombineActionEconomyPortClass.new(owner)

	var spend_result: Dictionary = port.spend_action({"name": "CAST_SPELL"})
	assert_true(spend_result.get("success"))
	assert_eq(fake_economy.spend_action_calls, 1)

	port.spend_reaction()
	assert_eq(fake_economy.spend_reaction_calls, 1)

	assert_false(port.is_spent())
	assert_eq(port.get_remaining(), fake_economy.remaining)


# ══════════════════════════════════════════════════════════════════════════
# 4) CombineTargetingRegistryProxy
# ══════════════════════════════════════════════════════════════════════════

func test_combine_targeting_registry_proxy_exposes_execute_signature() -> void:
	var proxy = CombineTargetingRegistryProxyClass.new(_FakeMainScene.new())
	assert_true(proxy.has_method("execute"))


func test_combine_targeting_registry_proxy_delegates_to_owning_main_scene() -> void:
	var fake_main_scene = _FakeMainScene.new()
	var proxy = CombineTargetingRegistryProxyClass.new(fake_main_scene)

	var result: Dictionary = proxy.execute("STRIKE", "value_x")

	assert_eq(fake_main_scene.targeting_calls.size(), 1)
	assert_eq(fake_main_scene.targeting_calls[0], ["STRIKE", "value_x"])
	assert_eq(result, {"ok": true, "source": "targeting"})


# ══════════════════════════════════════════════════════════════════════════
# 5) CombineBuildRegistryProxy
# ══════════════════════════════════════════════════════════════════════════

func test_combine_build_registry_proxy_exposes_execute_signature() -> void:
	var proxy = CombineBuildRegistryProxyClass.new(_FakeMainScene.new())
	assert_true(proxy.has_method("execute"))


func test_combine_build_registry_proxy_delegates_to_owning_main_scene() -> void:
	var fake_main_scene = _FakeMainScene.new()
	var proxy = CombineBuildRegistryProxyClass.new(fake_main_scene)

	var result: Dictionary = proxy.execute("STRIDE", "value_y")

	assert_eq(fake_main_scene.build_calls.size(), 1)
	assert_eq(fake_main_scene.build_calls[0], ["STRIDE", "value_y"])
	assert_eq(result, {"ok": true, "source": "build"})


# ══════════════════════════════════════════════════════════════════════════
# Test doubles
# ══════════════════════════════════════════════════════════════════════════

class _FakeSpellPresentationController:
	extends RefCounted

	var _candidate_options: Array

	func _init(candidate_options: Array) -> void:
		_candidate_options = candidate_options

	func enter_selection() -> Dictionary:
		return {"candidate_options": _candidate_options}


class _FakeActionEconomy:
	extends RefCounted

	var spend_action_calls: int = 0
	var spend_reaction_calls: int = 0
	var remaining: int = 3

	func spend_action(_action_metadata: Dictionary) -> Dictionary:
		spend_action_calls += 1
		return {"success": true, "ok": true}

	func spend_reaction() -> Dictionary:
		spend_reaction_calls += 1
		return {"success": true, "ok": true}

	func is_spent() -> bool:
		return false

	func get_remaining() -> int:
		return remaining


class _FakeOwnerWithEconomy:
	extends RefCounted

	var _economy

	func _init(economy) -> void:
		_economy = economy

	func _verb_bar_current_action_economy():
		return _economy


class _FakeOwnerNoEconomy:
	extends RefCounted

	func _verb_bar_current_action_economy():
		return null


class _FakeMainScene:
	extends RefCounted

	var targeting_calls: Array = []
	var build_calls: Array = []

	func _on_combine_targeting_value_chosen(verb_id: String, value) -> Dictionary:
		targeting_calls.append([verb_id, value])
		return {"ok": true, "source": "targeting"}

	func _on_combine_build_option_chosen(verb_id: String, value) -> Dictionary:
		build_calls.append([verb_id, value])
		return {"ok": true, "source": "build"}
