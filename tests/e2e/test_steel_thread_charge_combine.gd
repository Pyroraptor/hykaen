extends GutTest
## tests/e2e/test_steel_thread_charge_combine.gd — FEAT-287 (US-011, US-012;
## the project's FINAL end-to-end steel thread smoke test).
##
## Boots the REAL, shipped res://MainScene.tscn composition root (NO mocks/
## doubles anywhere in this suite — the same "boot-real" discipline every
## prior Combine suite established: tests/integration/
## test_combine_execute_stride_then_strike.gd, tests/integration/
## test_charge_boot_real_e2e.gd) at a pinned RNG seed, and drives the FULL
## COMBINE->Charge steel thread — entry point to exit point — through the
## SAME real availability()/enter_selection()/execute() verb path a live
## player click resolves through:
##
##   entry point — a combatant with sufficient Stamina sees COMBINE->Charge
##   offered on the live, booted `_verb_registry` (VERB_TABLE["COMBINE"] ->
##   presentation/combine_action_controller.gd's CombineActionController,
##   reached SOLELY via `_controller("COMBINE")`, exactly as
##   `_verb_bar_combine_availability/enter_selection/execute()` resolve it) —
##
##   through the resolved Charge queue ([STRIDE, STRIKE], authored at
##   data/combines/charge.tres) — the token visibly moves toward the target
##   hex, then Strike resolves against it —
##
##   to exit point — the live action-economy ledger (this project's
##   established "the live ActionEconomy budget + Combatant.stamina ARE the
##   authoritative per-actor ledger" convention, see test_charge_boot_real_
##   e2e.gd's own file-level doc) shows EXACTLY one action and one Stamina
##   spent for the whole Combine, and the resolved sub-verb sequence is
##   exactly ["STRIDE", "STRIKE"].
##
## Also re-runs the identical scenario at the SAME pinned seed and asserts
## byte-for-byte identical ledger/outcome (determinism, US-012).
##
## No production code is modified by this feature (files_to_modify is
## empty) — every collaborator driven below is the exact, unmodified,
## already-shipped production class covered by its own suite (FEAT-001
## through FEAT-286); this file's job is proving they ALL still compose
## correctly, together, end-to-end, as the project's closing smoke test.
##
## test_criteria covered:
##   1. "MainScene boots headless with a pinned seed and no gate-failing
##      errors/warnings" — test_boots_headlessly_with_pinned_seed_and_no_
##      gate_failing_errors_or_warnings().
##   2. "Combatant with stamina>=1 sees COMBINE/Charge offered
##      (availability()==true) and none offered when stamina==0" —
##      test_combine_charge_offered_with_stamina_and_withheld_at_zero_
##      stamina().
##   3. "Full run: token position moves toward target hex, Strike resolves
##      (target takes damage/effect) via the real VERB_TABLE/_controller
##      ("COMBINE") path with no test doubles" +
##   4. "Ledger after the run shows exactly 1 ... actions_spent==1,
##      stamina_spent==1, resolved_sub_verb_ids==["STRIDE","STRIKE"]" —
##      both covered by test_charge_combine_full_run_moves_token_resolves_
##      strike_with_single_action_stamina_ledger().
##   5. "Running the identical scenario twice at the same pinned seed
##      produces byte-for-byte identical ledger entries and final
##      positions" —
##      test_running_identical_scenario_twice_at_pinned_seed_produces_byte_
##      identical_ledger_and_positions().

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MainSceneClass = preload("res://MainScene.gd")

const CombineActionControllerClass = preload("res://presentation/combine_action_controller.gd")
const HexCoordClass                = preload("res://core/geometry/hex_coord.gd")
const HexMathClass                 = preload("res://core/geometry/hex_math.gd")
const MovementClass                = preload("res://core/rules/movement.gd")

## PROLOGUE_SEED — this project's established known-good fixture seed
## (mirrors tests/integration/test_charge_boot_real_e2e.gd's / tests/
## integration/test_combine_execute_stride_then_strike.gd's identically-
## named/valued constant).
const PROLOGUE_SEED: int = 42

## Fixture geometry (mirrors tests/integration/test_charge_boot_real_e2e.gd's
## own established convention): the Skeleton is repositioned (test-fixture-
## only) to (3,0) — 3 hexes from Titus's start (0,0), out of melee reach —
## but exactly adjacent to (2,0), a hex already within Titus's real,
## boot-time-computed legal Stride destination set.
const SKELETON_REPOSITIONED_HEX_Q: int = 3
const STRIDE_DESTINATION_HEX_Q: int = 2


## FEAT-316 (US-005/US-007 / FR-004, resolves DEF-001/PR-001): MainScene now
## boots into EXPLORATION mode with the legacy combat pipeline (round_session,
## $VerbBarView/$SelectionOverlay configuration, turn_controller signal
## wiring) gated behind a real _on_combat_triggered() handoff -- see
## MainScene.gd's own FEAT-316 doc. This suite drives COMBINE directly
## against `round_session`/`_controller("COMBINE")`, so `_boot_main_scene()`
## now also drives the SAME real handoff, landing the instance in
## GameMode.COMBAT with a live round_session before returning.
func _boot_main_scene():
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = PROLOGUE_SEED
	add_child_autofree(instance)
	await get_tree().process_frame

	instance._on_combat_triggered("prologue")
	await get_tree().process_frame
	await get_tree().process_frame

	return instance


func _titus(instance):
	assert_true(instance._party.size() > 0, "fixture assumption: the prologue encounter has at least one party member")
	var titus = instance._party[0]
	assert_eq(titus.name, "Titus", "fixture assumption: the first party member is Titus")
	return titus


func _skeleton(instance):
	assert_true(instance._enemies.size() > 0, "fixture assumption: the prologue encounter has at least one enemy")
	var skeleton = instance._enemies[0]
	assert_eq(skeleton.name, "Skeleton", "fixture assumption: the sole enemy is the Skeleton")
	return skeleton


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — MainScene boots headless with a pinned seed and no
# gate-failing errors/warnings. Mirrors this project's established
# tests/gut/test_smoke_boot.gd convention: every composition-root field is
# only left null when an internal push_error() fail-fast path was hit, so
# asserting non-null on all of them (plus a non-empty, both-teams turn
# order) is this project's established proxy for "zero unhandled boot
# errors" (Godot 4.3's push_error capture hook is a documented 4.4+ API).
# ══════════════════════════════════════════════════════════════════════════

func test_boots_headlessly_with_pinned_seed_and_no_gate_failing_errors_or_warnings() -> void:
	assert_true(MainSceneClass.VERB_TABLE.has("COMBINE"), "MainScene.VERB_TABLE must register a COMBINE entry")
	assert_eq(
		MainSceneClass.VERB_TABLE.get("COMBINE"), CombineActionControllerClass,
		"VERB_TABLE['COMBINE'] must point at presentation/combine_action_controller.gd's CombineActionController"
	)

	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_not_null(instance, "MainScene.tscn must instantiate with no manual setup")
	assert_eq(instance.resolved_seed, PROLOGUE_SEED, "the pinned seed_override must be honored as resolved_seed")

	assert_not_null(instance.encounter_repository, "encounter_repository must be non-null after first frame -- a null value means an internal push_error() fail-fast path was hit")
	assert_not_null(instance.random_port, "random_port must be non-null after first frame")
	assert_not_null(instance.event_sink, "event_sink must be non-null after first frame")
	assert_not_null(instance.encounter, "encounter must be non-null after first frame")
	assert_not_null(instance.round_session, "round_session must be a real RoundSession after first frame -- no unhandled boot exception")
	assert_not_null(instance._verb_registry, "MainScene must wire a real VerbBarRegistry after first frame")

	var turn_order: Array = instance.encounter.get_turn_order()
	assert_true(turn_order.size() > 0, "the prologue encounter must load into a non-empty combatant turn order")

	var registered_verb_ids: Array = []
	for descriptor in instance._verb_registry.list_verbs():
		registered_verb_ids.append(descriptor.get("verb_id"))
	assert_true(registered_verb_ids.has("COMBINE"), "the real, booted VerbBarRegistry must have COMBINE registered")

	assert_no_new_orphans("MainScene's real boot must leave zero orphaned nodes")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — a combatant with stamina>=1 sees COMBINE/Charge offered
# (availability()==true); none is offered when stamina==0. Checked BOTH
# directly through `_controller("COMBINE")` AND through the live, booted
# `_verb_registry.is_available("COMBINE")` — the exact seam the real verb
# bar UI itself gates on.
# ══════════════════════════════════════════════════════════════════════════

func test_combine_charge_offered_with_stamina_and_withheld_at_zero_stamina() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	assert_true(titus.stamina > 0, "fixture assumption: Titus starts with positive Stamina")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")

	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")

	assert_true(combine_controller.availability(), "COMBINE->Charge must be offered when Titus has sufficient (positive) Stamina")
	assert_true(instance._verb_registry.is_available("COMBINE"), "the live, booted VerbBarRegistry must also offer COMBINE when Titus has sufficient Stamina")

	titus.stamina = 0
	assert_false(combine_controller.availability(), "COMBINE->Charge must NOT be offered once Titus's Stamina drops to 0")
	assert_false(instance._verb_registry.is_available("COMBINE"), "the live, booted VerbBarRegistry must also withhold COMBINE once Titus's Stamina drops to 0")


# ══════════════════════════════════════════════════════════════════════════
# Criteria 3 & 4 — full run: token position moves toward the target hex,
# Strike resolves (target takes damage) via the real VERB_TABLE/
# `_controller("COMBINE")` path with no test doubles; the ledger after the
# run shows exactly one action + one Stamina spent, with
# resolved_sub_verb_ids == ["STRIDE", "STRIKE"].
# ══════════════════════════════════════════════════════════════════════════

func test_charge_combine_full_run_moves_token_resolves_strike_with_single_action_stamina_ledger() -> void:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	assert_false(
		instance.round_session.current_actor().is_enemy,
		"fixture assumption: Titus (the player) acts first at seed=%d" % PROLOGUE_SEED
	)

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	assert_not_null(titus_start_hex, "fixture assumption: Titus carries a hex_coord before the Combine")
	assert_eq([titus_start_hex.q, titus_start_hex.r], [0, 0], "fixture assumption: Titus starts at (0,0) per the prologue encounter resource")

	# Reposition the Skeleton (test-fixture-only) out of melee reach of
	# Titus's START hex, but adjacent to the Stride destination Charge's
	# authored STRIDE leg will carry Titus to.
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)

	var stride_destination = HexCoordClass.new(STRIDE_DESTINATION_HEX_Q, 0)
	assert_true(
		HexMathClass.hex_distance(titus_start_hex, stride_destination) <= MovementClass.DEFAULT_SPEED,
		"test setup: the Stride destination must be within Titus's real Speed"
	)
	assert_true(
		HexMathClass.hex_distance(titus_start_hex, skeleton.hex_coord) > 1,
		"test setup: the repositioned Skeleton must be OUT of melee reach of Titus's START hex"
	)
	assert_eq(
		HexMathClass.hex_distance(stride_destination, skeleton.hex_coord), 1,
		"test setup: the repositioned Skeleton must be adjacent to the Stride destination"
	)

	# ── entry point — resolve COMBINE through the SAME `_controller("COMBINE")`
	# table lookup every other verb (and the live verb bar) is resolved
	# through — this test never touches `_controller("STRIDE")`/
	# `_controller("STRIKE")` directly; those are only ever reached
	# INTERNALLY, by CombineActionController's own `_controller(verb_id)`
	# lookups. ────────────────────────────────────────────────────────────────
	var combine_controller = instance._controller("COMBINE")
	assert_true(combine_controller is CombineActionControllerClass, "_controller(\"COMBINE\") must resolve a real CombineActionController")
	assert_same(combine_controller, instance._controllers.get("COMBINE"), "the COMBINE controller must be the SAME memoized VERB_TABLE-resolved instance")

	assert_true(titus.stamina > 0, "fixture assumption: Titus must have sufficient (positive) Stamina to Combine")
	assert_false(titus.has_condition("Dazed"), "fixture assumption: Titus must not be Dazed")
	assert_true(instance._verb_registry.is_available("COMBINE"), "COMBINE->Charge must be offered on the live verb bar for Titus at the start of his turn")
	assert_true(combine_controller.availability(), "COMBINE->Charge must be selectable (available) for Titus at the start of his turn")

	var selection_result: Dictionary = combine_controller.enter_selection()
	assert_true(selection_result.get("ok", false), "enter_selection() for the default (Charge) pair must succeed for an eligible actor")
	var queue: Array = selection_result.get("queue", [])
	assert_eq(queue.size(), 2, "Charge's queue must carry exactly 2 sub-action entries")
	assert_eq(queue[0].verb_id, "STRIDE", "Charge's queue must resolve STRIDE first")
	assert_eq(queue[1].verb_id, "STRIKE", "Charge's queue must resolve STRIKE second")

	# ── Ledger BEFORE — direct inspection of the actor's live ActionEconomy +
	# Stamina, this project's established authoritative per-actor ledger
	# (see this file's own header doc). ─────────────────────────────────────
	var economy = instance.round_session.current_action_economy()
	assert_not_null(economy, "fixture assumption: Titus must have a live ActionEconomy at boot")
	var actions_remaining_before: int = economy.get_remaining()
	assert_true(economy.can_take_action(), "fixture assumption: Titus has not yet acted this turn")
	var stamina_before: int = titus.stamina
	var skeleton_hp_before: int = skeleton.hp_current
	var titus_hex_before = titus.hex_coord

	var selection: Dictionary = {
		"queue": queue,
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	}

	# ── Drive the WHOLE Charge through `combine_controller.execute()` — the
	# sole entry point this test calls to resolve it, exactly as
	# `_verb_bar_combine_execute()` resolves a live player click. ──────────────
	var result: Dictionary = await combine_controller.execute(selection)
	assert_true(result.get("ok", false), "a valid COMBINE->Charge execute() must resolve ok=true (result: %s)" % [result])

	# ── Criterion 4 (part) — resolved_sub_verb_ids == ["STRIDE", "STRIKE"]. ──
	assert_eq(result.get("resolved_verb_ids", []), ["STRIDE", "STRIKE"], "Charge must resolve STRIDE then STRIKE, in that order")

	# ── Criterion 3 — the token's position after execute() has moved TOWARD
	# (here, exactly adjacent to) the target hex. ────────────────────────────
	var distance_before: int = HexMathClass.hex_distance(titus_hex_before, skeleton.hex_coord)
	var distance_after: int = HexMathClass.hex_distance(titus.hex_coord, skeleton.hex_coord)
	assert_true(distance_after < distance_before, "Titus's token must be CLOSER to the Skeleton after Charge than before it (before=%d, after=%d)" % [distance_before, distance_after])
	assert_eq(distance_after, 1, "Titus's post-Charge position must be adjacent to the Skeleton")
	assert_true(titus.hex_coord.equals(stride_destination), "Titus's live position must equal the authored STRIDE leg's destination once Charge resolves")

	# ── Criterion 3 (cont'd) — Strike resolves against the target: the
	# Skeleton takes real damage AFTER the move. ─────────────────────────────
	assert_true(skeleton.hp_current < skeleton_hp_before, "the Skeleton must have taken real Strike damage once Titus's Stride put him in reach")

	# ── Criterion 4 — the ledger shows EXACTLY one action and one Stamina
	# spent for the WHOLE Charge, regardless of resolving two sub-actions. ──
	var actions_spent: int = actions_remaining_before - economy.get_remaining()
	var stamina_spent: int = stamina_before - titus.stamina
	assert_eq(actions_spent, 1, "Charge must spend exactly ONE action from Titus's live ActionEconomy ledger")
	assert_false(economy.can_take_action(), "Titus's one action for the turn must now be spent, via Charge's own single Combine-level charge")
	assert_false(economy.is_self_spend_suppressed(), "the no-self-spend suppression flag must never leak past Charge's own execute() call")
	assert_eq(stamina_spent, 1, "Charge must spend exactly ONE Stamina from Titus's live ledger")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 5 — running the identical scenario twice at the same pinned
# seed produces byte-for-byte identical ledger entries and final
# positions (determinism).
# ══════════════════════════════════════════════════════════════════════════

## _run_charge_scenario() -> Dictionary — boots a FRESH, independent
## MainScene instance pinned to PROLOGUE_SEED and drives the identical
## COMBINE->Charge steel thread this suite's own criteria-3/4 test drives,
## recording every outcome into a plain-value snapshot Dictionary (no Node/
## Combatant references) so two independent runs can be diffed directly via
## `==`/assert_eq (mirrors tests/e2e/test_determinism_pinned_seed_cast_a_
## spell.gd's own established "two independent boots, snapshot + diff"
## convention).
func _run_charge_scenario() -> Dictionary:
	var instance = await _boot_main_scene()
	await get_tree().process_frame

	var titus = _titus(instance)
	var skeleton = _skeleton(instance)

	var titus_start_hex = titus.hex_coord
	skeleton.hex_coord = HexCoordClass.new(SKELETON_REPOSITIONED_HEX_Q, 0)
	var stride_destination = HexCoordClass.new(STRIDE_DESTINATION_HEX_Q, 0)

	var combine_controller = instance._controller("COMBINE")
	var selection_result: Dictionary = combine_controller.enter_selection()
	var queue: Array = selection_result.get("queue", [])

	var economy = instance.round_session.current_action_economy()
	var actions_remaining_before: int = economy.get_remaining()
	var stamina_before: int = titus.stamina
	var skeleton_hp_before: int = skeleton.hp_current

	var selection: Dictionary = {
		"queue": queue,
		"STRIDE": stride_destination,
		"STRIKE": skeleton.display_id(),
	}

	var result: Dictionary = await combine_controller.execute(selection)

	return {
		"resolved_seed": instance.resolved_seed,
		"execute_ok": result.get("ok", false),
		"resolved_sub_verb_ids": result.get("resolved_verb_ids", []),
		"actions_spent": actions_remaining_before - economy.get_remaining(),
		"stamina_spent": stamina_before - titus.stamina,
		"titus_final_hex": [titus.hex_coord.q, titus.hex_coord.r],
		"skeleton_hp_before": skeleton_hp_before,
		"skeleton_hp_after": skeleton.hp_current,
	}


func test_running_identical_scenario_twice_at_pinned_seed_produces_byte_identical_ledger_and_positions() -> void:
	var run_1: Dictionary = await _run_charge_scenario()
	var run_2: Dictionary = await _run_charge_scenario()

	# Non-vacuous sanity: real work actually happened in both runs (a bug
	# that silently no-ops the whole scenario would otherwise make the
	# equality assertions below trivially/vacuously pass).
	assert_eq(run_1.get("resolved_seed"), PROLOGUE_SEED, "run 1 must have honored seed_override=PROLOGUE_SEED")
	assert_true(run_1.get("execute_ok"), "fixture assumption: run 1's Charge execute() must succeed")
	assert_eq(run_1.get("resolved_sub_verb_ids"), ["STRIDE", "STRIKE"], "fixture assumption: run 1 must have genuinely resolved STRIDE then STRIKE")
	assert_true(run_1.get("skeleton_hp_after") < run_1.get("skeleton_hp_before"), "fixture assumption: run 1's Strike must have applied real damage")

	# ── ledger entries + final positions — byte-identical across the two
	# independent boots of the same pinned seed. ────────────────────────────
	assert_eq(run_2.get("resolved_seed"), run_1.get("resolved_seed"), "the resolved seed must be identical across both boots")
	assert_eq(run_2.get("resolved_sub_verb_ids"), run_1.get("resolved_sub_verb_ids"), "resolved_sub_verb_ids must be identical across both boots")
	assert_eq(run_2.get("actions_spent"), run_1.get("actions_spent"), "actions_spent must be identical across both boots")
	assert_eq(run_2.get("stamina_spent"), run_1.get("stamina_spent"), "stamina_spent must be identical across both boots")
	assert_eq(run_2.get("titus_final_hex"), run_1.get("titus_final_hex"), "Titus's final position must be identical across both boots")
	assert_eq(run_2.get("skeleton_hp_after"), run_1.get("skeleton_hp_after"), "the Skeleton's final hp must be identical across both boots")

	# Whole-snapshot deep-equality sanity check (belt-and-suspenders): the
	# ENTIRE recorded snapshot of two independent boots at the same pinned
	# seed must be byte-identical.
	assert_eq(run_2, run_1, "the entire recorded ledger/outcome snapshot of two independent boots at the same pinned seed must be byte-identical")
