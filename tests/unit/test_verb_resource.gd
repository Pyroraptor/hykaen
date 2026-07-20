extends GutTest
## tests/unit/test_verb_resource.gd
##
## GUT unit test suite for FEAT-001 (Iteration O "Combine Selection UX";
## US-001, FR-001): core/resources/verb_resource.gd's VerbResource
## authoring schema plus its data/verbs/stride.tres and data/verbs/strike.tres
## authored counterparts.
##
## Mirrors this codebase's established flat tests/unit/test_*_resources.gd
## convention (see tests/unit/test_weapon_resources.gd) for a Resource
## subtype's own load-and-field-assertion suite.
##
## Test criteria:
##   - VerbResource exposes repeat, reaction_follow_up (default false), and
##     combinable fields, readable from a hydrated instance.
##   - STRIDE and STRIKE .tres resources load with correct trait values:
##     movement=true for STRIDE, movement=false for STRIKE, combinable=true
##     for both.
##   - VerbResource.is_valid()/validation_error() reject malformed data
##     (empty verb_id / non-positive action_cost / negative stamina_cost).


# ══════════════════════════════════════════════════════════════════════════
# VerbResource schema: fields exist with correct defaults
# ══════════════════════════════════════════════════════════════════════════

func test_verb_resource_reaction_follow_up_defaults_to_false() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	assert_false(res.reaction_follow_up, "reaction_follow_up must default to false")


func test_verb_resource_exposes_repeat_and_combinable_fields() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	res.repeat = true
	res.combinable = true
	assert_true(res.repeat)
	assert_true(res.combinable)


# ══════════════════════════════════════════════════════════════════════════
# data/verbs/stride.tres loads with correct trait values
# ══════════════════════════════════════════════════════════════════════════

func test_stride_tres_loads() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/verbs/stride.tres') must return non-null")


func test_stride_verb_id_is_stride() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	if res == null:
		fail_test("stride.tres failed to load")
		return
	assert_eq(res.verb_id, "STRIDE")


func test_stride_movement_is_true() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	if res == null:
		fail_test("stride.tres failed to load")
		return
	assert_true(res.movement, "STRIDE must carry movement=true")


func test_stride_combinable_is_true() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	if res == null:
		fail_test("stride.tres failed to load")
		return
	assert_true(res.combinable, "STRIDE must carry combinable=true")


func test_stride_reaction_follow_up_is_false() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	if res == null:
		fail_test("stride.tres failed to load")
		return
	assert_false(res.reaction_follow_up)


func test_stride_is_valid() -> void:
	var res = ResourceLoader.load("res://data/verbs/stride.tres")
	if res == null:
		fail_test("stride.tres failed to load")
		return
	assert_true(res.is_valid(), "stride.tres must satisfy every VerbResource load-time invariant")


# ══════════════════════════════════════════════════════════════════════════
# data/verbs/strike.tres loads with correct trait values
# ══════════════════════════════════════════════════════════════════════════

func test_strike_tres_loads() -> void:
	var res = ResourceLoader.load("res://data/verbs/strike.tres")
	assert_not_null(res, "ResourceLoader.load('res://data/verbs/strike.tres') must return non-null")


func test_strike_verb_id_is_strike() -> void:
	var res = ResourceLoader.load("res://data/verbs/strike.tres")
	if res == null:
		fail_test("strike.tres failed to load")
		return
	assert_eq(res.verb_id, "STRIKE")


func test_strike_movement_is_false() -> void:
	var res = ResourceLoader.load("res://data/verbs/strike.tres")
	if res == null:
		fail_test("strike.tres failed to load")
		return
	assert_false(res.movement, "STRIKE must carry movement=false — it is not a positional verb")


func test_strike_combinable_is_true() -> void:
	var res = ResourceLoader.load("res://data/verbs/strike.tres")
	if res == null:
		fail_test("strike.tres failed to load")
		return
	assert_true(res.combinable, "STRIKE must carry combinable=true")


func test_strike_is_valid() -> void:
	var res = ResourceLoader.load("res://data/verbs/strike.tres")
	if res == null:
		fail_test("strike.tres failed to load")
		return
	assert_true(res.is_valid(), "strike.tres must satisfy every VerbResource load-time invariant")


# ══════════════════════════════════════════════════════════════════════════
# VerbResource.is_valid()/validation_error() reject malformed data
# ══════════════════════════════════════════════════════════════════════════

func test_verb_resource_rejects_empty_verb_id() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	res.verb_id = ""
	res.action_cost = 1
	assert_false(res.is_valid(), "an empty verb_id must be rejected")
	assert_ne(res.validation_error(), "")


func test_verb_resource_rejects_non_positive_action_cost() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	res.verb_id = "TEST"
	res.action_cost = 0
	assert_false(res.is_valid(), "action_cost <= 0 must be rejected")


func test_verb_resource_rejects_negative_stamina_cost() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	res.verb_id = "TEST"
	res.action_cost = 1
	res.stamina_cost = -1
	assert_false(res.is_valid(), "a negative stamina_cost must be rejected")


func test_verb_resource_accepts_well_formed_data() -> void:
	var VerbResourceClass = load("res://core/resources/verb_resource.gd")
	var res = VerbResourceClass.new()
	res.verb_id = "TEST"
	res.action_cost = 1
	res.stamina_cost = 0
	assert_true(res.is_valid())
	assert_eq(res.validation_error(), "")
