extends GutTest
## tests/gut/test_rich_log_player_attack.gd — FEAT-005 (US-005, Iteration
## J-R2 Part D): "Render rich combat log entry for player attack path".
##
## Boots the REAL res://MainScene.tscn composition root (G2 -- never a
## hand-wired double) and scripts a real player Strike (the SAME
## verb_bar_view.press("STRIKE") -> hex_grid_view.hex_clicked.emit(...) flow
## tests/gut/test_player_strikes_enemy_pass_through.gd already established),
## then asserts the live `_verb_bar_strike_execute()` call site actually
## invokes core/log/attack_event.gd-backed `record_attack()` /
## `render_attack_entry()` on the REAL, booted `event_log_view` -- not a
## test double -- and that the visible log's `get_row_text(0)` shows a
## RICH-format row (roll/raw/final damage fields), the steel-thread exit
## condition this feature exists for. Row 0 is the Strike's OWN row -- it
## must never be pushed later by a same-call CombatantDefeatedEvent (a
## killing blow legitimately appends its OWN, separate row immediately
## afterward; that row is untouched by this feature and is not itself
## "duplicate" rich-vs-plain content for the Strike).
##
## Verifies (test_criteria):
##   1. Booting real MainScene and scripting a player attack: get_row_text(0)
##      contains the roll/raw/final damage fields render_attack_entry()
##      produces.
##   2. record_attack()/render_attack_entry() is invoked on the LIVE
##      player-attack call site (not a test double): the visible row's
##      attack_event_id (a real, observable field of event_log_view's
##      `_entries` backing store, see get_entry()) is retrievable via
##      get_structured_attack() (proving record_attack() ran against the
##      REAL, live-booted event_log_view), and the row's rendered text is
##      byte-for-byte what a fresh render_attack_entry() call for that SAME
##      id produces (proving render_attack_entry() -- not a re-derived
##      string -- actually drove the visible row).
##   3. A companion grep-based check (below) confirms MainScene.gd's
##      player-attack call site source text actually invokes
##      record_attack/render_attack_entry (live-path evidence, mirrors this
##      codebase's established "static source-shape" convention, e.g.
##      tests/gut/test_player_strikes_enemy_pass_through.gd's
##      _find_call_sites() helper).

const MAIN_SCENE_PATH: String = "res://MainScene.tscn"
const MAIN_SCENE_SOURCE_PATH: String = "res://MainScene.gd"


func _boot_main_scene_with_seed(seed_value: int):
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH)
	assert_not_null(packed, "MainScene.tscn must load as a PackedScene")
	var instance = packed.instantiate()
	instance.seed_override = seed_value
	add_child_autofree(instance)
	return instance


## _resolve_one_real_player_strike(instance) -> Dictionary -- the SAME
## real Strike-scripting flow tests/gut/test_player_strikes_enemy_pass_through.gd
## already established: press the STRIKE verb, then click the first
## in-reach candidate target's hex.
func _resolve_one_real_player_strike(instance) -> Dictionary:
	var selection: Dictionary = instance.verb_bar_view.press("STRIKE")
	var target_ids: Array = selection.get("candidate_targets", [])
	assert_true(target_ids.size() > 0, "fixture assumption: at least one in-reach target exists at boot")
	var target_id: String = target_ids[0]
	var target_token = instance.hex_grid_view.get_token(target_id)
	assert_not_null(target_token, "fixture assumption: the chosen target has a rendered HexGridView token")

	instance.hex_grid_view.hex_clicked.emit(target_token.hex_coord)
	return {"target_id": target_id}


# ══════════════════════════════════════════════════════════════════════════
# Criterion 1 — a real player Strike, driven through the real composition
# root, produces a rich-format row at index 0 (its OWN row -- never pushed
# later or duplicated by a plain-format sibling).
# ══════════════════════════════════════════════════════════════════════════

func test_real_player_strike_renders_a_rich_row_at_index_zero() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	assert_eq(instance.event_log_view.get_entry_count(), 0, "sanity: the log must start empty before any Strike is scripted")

	_resolve_one_real_player_strike(instance)

	assert_true(
		instance.event_log_view.get_entry_count() >= 1,
		"at least one visible row must exist after a single resolved player Strike"
	)

	var row_text: String = instance.event_log_view.get_row_text(0)
	assert_true(row_text != "", "get_row_text(0) must be non-empty after a resolved player Strike")
	assert_string_contains(row_text, "roll", "the rich row must render the roll_total field")
	assert_string_contains(row_text, "Defense:", "the rich row must render the active-defense outcome field")

	var attack_event_id = instance.event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the visible row must carry the attack_event_id it was rendered from")

	var attack_event = instance.event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(attack_event, "the structured AttackEvent recorded via record_attack() must be retrievable for the just-resolved player Strike")
	if attack_event != null:
		assert_true(attack_event.roll_total > 0, "the real resolution.gd math must produce a non-zero roll_total")
		if attack_event.is_hit:
			assert_string_contains(row_text, str(attack_event.damage_raw), "a hit must render the raw damage field")
			assert_string_contains(row_text, str(attack_event.damage_final), "a hit must render the final damage field")
		else:
			assert_string_contains(row_text, "Miss", "a miss must render the Miss label")

	# No-duplicate-row guard: no OTHER row may be a stale plain-format
	# "attacks ... for N damage." entry for this SAME Strike -- row 0 above
	# is the Strike's ONLY "attacks"-shaped row (any additional rows, e.g. a
	# killing blow's "was defeated by" entry, describe a DIFFERENT event).
	var attacks_row_count: int = 0
	for i in range(instance.event_log_view.get_entry_count()):
		if instance.event_log_view.get_row_text(i).contains(" attacks "):
			attacks_row_count += 1
	assert_eq(attacks_row_count, 1, "exactly one 'attacks' row may exist for a single resolved player Strike -- no basic+rich duplicate pair")


# ══════════════════════════════════════════════════════════════════════════
# Criterion 2 — record_attack()/render_attack_entry() are invoked on the
# LIVE player-attack call site against the REAL, booted event_log_view (this
# suite never substitutes a test double for event_log_view itself).
# ══════════════════════════════════════════════════════════════════════════

func test_live_player_attack_call_site_invokes_record_attack_and_render_attack_entry_on_the_real_event_log_view() -> void:
	var instance = _boot_main_scene_with_seed(42)
	await get_tree().process_frame

	var real_event_log_view = instance.event_log_view
	assert_not_null(real_event_log_view, "MainScene.event_log_view must be a real EventLogView after boot")
	assert_eq(real_event_log_view.get_entry_count(), 0, "sanity: no row yet")

	_resolve_one_real_player_strike(instance)

	var attack_event_id = real_event_log_view.get_entry(0).get("attack_event_id", "")
	assert_true(str(attack_event_id) != "", "the live call site must have generated and recorded an attack_event_id for this Strike")

	# record_attack() ran against the REAL, live-booted event_log_view: the
	# structured AttackEvent it stored is retrievable by that SAME id.
	var stored_attack = real_event_log_view.get_structured_attack(attack_event_id)
	assert_not_null(
		stored_attack,
		"record_attack() must have been invoked on the REAL, live-booted event_log_view for this Strike's attack_event_id -- it must be retrievable via get_structured_attack()"
	)

	# render_attack_entry() -- not a second, re-derived formatting -- drove
	# the visible row: re-invoking it for the SAME id must reproduce the
	# EXACT text already showing at row 0.
	var rendered_text: String = real_event_log_view.render_attack_entry(attack_event_id)
	assert_true(rendered_text != "", "render_attack_entry() must produce non-empty text for the recorded attack_event_id")
	assert_eq(
		real_event_log_view.get_row_text(0), rendered_text,
		"the visible row's text must be EXACTLY what render_attack_entry() renders for this Strike -- proving render_attack_entry() (not a re-derived string) drove the live row"
	)


# ══════════════════════════════════════════════════════════════════════════
# Criterion 3 — grep-based check confirms MainScene.gd's player-attack call
# site invokes record_attack/render_attack_entry (live-path evidence),
# mirroring this codebase's established static-source-shape convention.
# ══════════════════════════════════════════════════════════════════════════

func _read_file(res_path: String) -> String:
	var f := FileAccess.open(res_path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % res_path)
	if f == null:
		return ""
	var contents: String = f.get_as_text()
	f.close()
	return contents


func test_main_scene_source_invokes_render_attack_entry_and_record_attack_from_the_player_strike_execute_function() -> void:
	var content: String = _read_file(MAIN_SCENE_SOURCE_PATH)

	var strike_execute_start: int = content.find("func _verb_bar_strike_execute(")
	assert_true(strike_execute_start != -1, "MainScene.gd must still declare _verb_bar_strike_execute() -- the player-strikes-enemy call site")

	# Scope the grep to _verb_bar_strike_execute()'s own function body (up to
	# the NEXT top-level `func ` declaration), so this check proves the
	# live PLAYER call site specifically invokes the rich-log wiring, not
	# merely that the strings appear SOMEWHERE else in the file (e.g. the
	# enemy path or a doc comment).
	var next_func_start: int = content.find("\nfunc ", strike_execute_start + 1)
	if next_func_start == -1:
		next_func_start = content.length()
	var function_body: String = content.substr(strike_execute_start, next_func_start - strike_execute_start)

	assert_string_contains(
		function_body, "record_attack",
		"MainScene.gd's player-attack call site (_verb_bar_strike_execute) must invoke record_attack -- live-path evidence, not merely a test-only call"
	)
	assert_string_contains(
		function_body, "render_attack_entry",
		"MainScene.gd's player-attack call site (_verb_bar_strike_execute) must invoke render_attack_entry -- live-path evidence that the rich row is rendered from real production code, not a test double"
	)
