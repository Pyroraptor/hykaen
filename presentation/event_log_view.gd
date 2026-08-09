## presentation/event_log_view.gd — EventLogView (FEAT-010 / US-008)
##
## Presentation layer (Clean Architecture): an APPEND-ONLY, read-only
## projection subscribed exclusively to EventSinkPort broadcasts, satisfying
## US-008's "sees a human-readable combat log" steel-thread criterion. This
## is the primary player-facing observability surface for the steel thread —
## every AttackEvent / CombatantDefeatedEvent / EncounterResultEvent is
## rendered as a chronologically ordered, human-readable entry.
##
## EventLogView is populated in exactly one way, mirroring
## presentation/status_panel_view.gd and presentation/initiative_view.gd
## (ADR-003: Presentation subscribes to EventSinkPort broadcasts, never polls
## or mutates domain state):
##   on_round_event(event) / on_attack_event(event) /
##   on_combatant_defeated_event(event) / on_encounter_result_event(event) —
##   incremental appends driven exclusively by typed round events
##   (core/rules/round_events.gd) or duck-typed Dictionaries carrying the
##   same shape. Each recognized event appends exactly one entry; there is no
##   load_combatants()-style snapshot seed, since the log has no initial
##   state — it starts empty and only ever grows (append-only).
##
## Chronological ordering (US-008 / test_criteria): EventLogView assigns
## each entry a strictly monotonically increasing `sequence_number` at the
## moment it is appended, and entries are ALWAYS rendered in that append
## (dispatch) order — never re-sorted by the domain `round` field an event
## happens to carry. This matches an append-only log's real-world semantics:
## "chronological" means the order entries actually arrived at this view,
## not the in-fiction round number they describe.
##
## EventLogView MUST NOT call into either of the two Application-layer use
## cases that mutate combat state (the action-resolution use case or the
## round-advancement use case) — directly or via preload — it is a read-only
## projection, never a mutator of domain state (enforced by a
## source-inspection regression test,
## tests/unit/presentation/test_event_log_view.gd).
##
## Event duck-typing (`_event_has` / `_event_get`): events may arrive either
## as a typed core/rules/round_events.gd value object (a RefCounted with
## plain `var` fields) or as a plain Dictionary (as used by tests to
## "simulate" an event without depending on a concrete adapter/event-sink
## wiring). Both helpers read a field from either shape uniformly (mirrors
## presentation/status_panel_view.gd and presentation/initiative_view.gd).
##
## FEAT-008 (US-008 / FR-007) adds render_attack_entry() and
## get_active_defense_outcome_string() on top of FEAT-007's `_attack_records`
## structured storage: roll_total/hit/crit/damage_raw/damage_final plus a
## derived active-defense outcome string ("none" | "dodge-succeeded" |
## "dodge-failed" | "parry-succeeded" | "parry-failed" | "block
## reduced-by-N"), read from the paired core/log/reaction_resolved_event.gd
## ReactionResolvedEvent. Purely a reformatting of already-computed data —
## this file never rolls dice, never computes damage, and never imports or
## calls into core/rules/resolution.gd.
##
## Current-iteration US-007 ("Suppress duplicate basic log entry", design
## notes' ICombatLogPort.suppress_basic_entry() contract): overwrite_entry_as_rich()
## below IS this steel thread's concrete implementation of that contract —
## the plain-format row on_attack_event() appends is overwritten IN PLACE at
## its OWN append-order slot rather than left standing alongside a second,
## freshly-appended rich row, so no basic+rich duplicate pair for the SAME
## attack ever exists, even transiently (eliminates the "trace-but-don't-
## apply" anti-pattern for the visible combat log). Both live call sites —
## MainScene.gd's `_verb_bar_strike_execute()` (player-strikes-enemy) and
## core/application/round_session.gd's `advance_ai_turn()`
## (enemy-strikes-player) — already drive this same overwrite-in-place path
## (their own FEAT-005/FEAT-006 doc comments below `overwrite_entry_as_rich()`
## describe it); tests/gut/test_log_single_row_per_attack.gd is the
## cross-path regression proving BOTH paths, driven back-to-back through
## ONE booted composition root in the SAME round, each still produce
## exactly one visible row per attack — and that other, non-visible
## consumers of the same broadcast AttackEvent (e.g.
## presentation/status_panel_view.gd's independent EventSinkPort
## subscription) are entirely unaffected by this suppression, since it only
## ever mutates event_log_view's OWN `_entries`/`_labels` backing store.

class_name EventLogView
extends Control

## _entries — ordered Array[Dictionary] of every appended log entry, in
## strict append (dispatch) order. Each entry: {sequence_number, round, text,
## attack_event_id} -- attack_event_id (FEAT-005) is "" for every plain-format
## entry and the correlating structured-storage id for a rich-rendered entry
## (see append_rich_attack_entry()).
var _entries: Array = []

## _attack_records — FEAT-007 (US-007 / FR-008): structured storage keyed by
## attack_event_id (str(AttackEvent.id)), COMPLETELY SEPARATE from `_entries`
## above. Each value: {"attack_event": AttackEvent, "reactions": {window_id:
## ReactionResolvedEvent}}. Populated exclusively via record_attack()/
## record_reaction() below — never touched by on_attack_event()/
## on_round_event()'s pre-existing Dictionary-driven formatted-string path,
## so an entry lacking a structured pairing (i.e. every entry appended the
## OLD way) renders exactly as it always has (test_criteria #4). This is the
## steel thread's in-memory "repository adapter" for the design's AttackEvent
## 1—0..2 ReactionResolvedEvent relation (composite attack_event_id+window_id
## uniqueness — see record_reaction()'s duplicate-rejection doc below).
var _attack_records: Dictionary = {}

## _rejected_duplicate_reactions — FEAT-007: every duplicate-window-firing
## rejection record_reaction() has flagged (mirrors core/application/
## round_session.gd's established `_reaction_budget_violations` convention —
## this project's Godot 4.3 engine cannot capture GDScript's assert()/
## push_error() output from GUT, so a rejection must ALSO be recorded here to
## be observable by a test). Always empty for a caller that never fires the
## same (attack_event_id, window_id) pair twice.
var _rejected_duplicate_reactions: Array = []

## _next_sequence_number — the sequence_number the NEXT appended entry will
## receive; incremented on every append, guaranteeing strict monotonicity
## regardless of what `round` value the underlying event carries.
var _next_sequence_number: int = 1

## _labels — one Label per appended entry, in the same append order as
## `_entries`, added as a child of this Control so the log is visible when
## run inside the game.
var _labels: Array = []

## FEAT-009 (US-008 / FR-008, ADR-004, Contract 4): whether this panel is
## currently collapsed to just its Header title bar. Always false at boot
## (collapsed state is never persisted, per the design notes -- panels
## always boot expanded).
var _collapsed: bool = false

## FEAT-010 (US-009 / FR-009, ADR-004 AnchorConfig): this panel's full
## expanded rect, captured once in _ready() before any collapse toggle, so
## _apply_anchored_collapse_size() can always restore it exactly and compute
## the collapsed rect relative to it.
var _expanded_position: Vector2 = Vector2.ZERO
var _expanded_size: Vector2 = Vector2.ZERO

@onready var _rows_container: VBoxContainer = $Content/Rows


## BUGFIX (post-iteration-E): this read-only projection panel is a full-width
## Control across the lower battlefield. With the Control default
## MOUSE_FILTER_STOP it swallowed clicks on hexes (e.g. far Stride destinations)
## drawn beneath it, so only hexes in the clear central area were selectable.
## Make the panel and its row container transparent to mouse input (row Labels
## are set IGNORE at creation) so those clicks reach HexGridView's _unhandled_input.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _rows_container != null:
		_rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expanded_position = position
	_expanded_size = size


## clear() → void — resets all entries, structured records, and rendered
## label nodes, making this view ready for a fresh encounter without needing
## to be re-instantiated.
func clear() -> void:
	_entries.clear()
	_attack_records.clear()
	_rejected_duplicate_reactions.clear()
	_next_sequence_number = 1
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()


## toggle_collapsed() → void — FEAT-009 (US-008 / FR-008, ADR-004,
## Contract 4). Flips `_collapsed` and applies the resulting visual state
## (Content visibility, CollapseButton text, parent re-sort). Wired to
## $Header/CollapseButton's `pressed` UI event via the .tscn scene's own
## connection block (this script makes no runtime hookup call of its own,
## keeping this file a pure event_sink_port sink per ADR-005/
## test_event_log_widget.gd's source-inspection guard), so clicking the
## collapse arrow calls this directly; also callable programmatically
## (e.g. from tests).
func toggle_collapsed() -> void:
	_collapsed = !_collapsed
	_apply_collapsed_state()


## _apply_collapsed_state() → void — applies `_collapsed`'s current value to
## the scene: hides/shows $Content, swaps $Header/CollapseButton's text
## between "▼" (collapsed) and "▲" (expanded), and asks the parent
## container to re-sort so the panel visually shrinks/grows toward its
## anchor edge. Per Contract 4's error-handling note, this must never raise:
##   - no parent at all (e.g. an EventLogView instantiated standalone in a
##     unit test) is a guarded no-op on the sort call.
##   - a parent that IS present but does not itself implement queue_sort()
##     (e.g. the CanvasLayer this panel is reparented under in the real
##     MainScene.tscn composition root, per FEAT-007) is ALSO a guarded
##     no-op -- queue_sort() is a Container-only method, and CanvasLayer is
##     a plain Node, so calling it unconditionally would throw a script
##     error on every real toggle in the running game. has_method() keeps
##     this degrade-gracefully rather than raise, matching the same
##     defensive-guard discipline as set_origin_offset()'s null-camera
##     guard elsewhere in this iteration (and InitiativeView's identical
##     FEAT-008 implementation of this same contract).
func _apply_collapsed_state() -> void:
	$Content.visible = not _collapsed
	$Header/CollapseButton.text = "▼" if _collapsed else "▲"
	_apply_anchored_collapse_size()
	var parent: Node = get_parent()
	if parent != null and parent.has_method("queue_sort"):
		parent.queue_sort()


## _apply_anchored_collapse_size() → void — FEAT-010 (US-009 / FR-009,
## ADR-004 AnchorConfig). Resizes this panel's own rect toward its anchored
## edge so collapsing never leaves a visual gap between the panel and the
## screen edge/corner it's pinned to. `grow_vertical` (static per-panel
## AnchorConfig data set in event_log_view.tscn) decides which vertical
## edge stays fixed while the panel's height changes:
##   GROW_DIRECTION_END   -- "downward collapse": the TOP edge stays fixed;
##       collapsing shrinks the panel by moving its BOTTOM edge up toward
##       the header.
##   GROW_DIRECTION_BEGIN -- "upward collapse" (EventLogView, anchored
##       bottom-left): the BOTTOM edge stays fixed; collapsing shrinks the
##       panel by moving its TOP edge down toward the header, so the header
##       ends up flush with the fixed bottom edge.
## Width is never touched -- only Content's visibility (and thus height)
## changes on collapse. Idempotent: re-expanding restores the exact
## _expanded_position/_expanded_size captured once in _ready().
func _apply_anchored_collapse_size() -> void:
	var header_height: float = $Header.size.y
	if _collapsed:
		size.y = header_height
		if grow_vertical == Control.GROW_DIRECTION_BEGIN:
			position.y = _expanded_position.y + (_expanded_size.y - header_height)
		else:
			position.y = _expanded_position.y
	else:
		position.y = _expanded_position.y
		size.y = _expanded_size.y


## get_entry_count() → int — number of entries currently in the log.
func get_entry_count() -> int:
	return _entries.size()


## get_entry(index) → Dictionary — a snapshot Dictionary
## ({sequence_number, round, text, attack_event_id}) for the entry at
## append-order `index`, or an empty Dictionary if `index` is out of range.
func get_entry(index: int) -> Dictionary:
	if index < 0 or index >= _entries.size():
		return {}
	return _entries[index].duplicate()


## get_entry_text(index) → String — the human-readable text of the entry at
## append-order `index`, or "" if `index` is out of range.
func get_entry_text(index: int) -> String:
	return get_entry(index).get("text", "")


## get_sequence_numbers() → Array[int] — the sequence_number of every entry,
## in append order (strictly increasing by construction).
func get_sequence_numbers() -> Array:
	var numbers: Array = []
	for entry in _entries:
		numbers.append(entry.get("sequence_number", 0))
	return numbers


## get_row_text(index) → String — the exact text rendered on the Label for
## the entry at append-order `index`, for display-level assertions. "" if
## `index` is out of range.
func get_row_text(index: int) -> String:
	if index < 0 or index >= _labels.size():
		return ""
	var label: Label = _labels[index]
	return label.text if label != null else ""


## record_attack(attack_event) → void — FEAT-007 (US-007 / FR-008): stores a
## structured core/log/attack_event.gd AttackEvent in `_attack_records`,
## keyed by str(attack_event.id), with an initially-empty "reactions" pairing
## slot. A COMPLETELY SEPARATE storage channel from `_entries`/
## on_attack_event() (test_criteria #4) — calling this never appends,
## mutates, or removes any pre-existing formatted-string entry. Overwrites
## any prior record for the SAME id (an id collision is a caller contract
## violation — core/application/round_session.gd's generator guarantees
## uniqueness within a round; this method does not itself re-derive that
## guarantee).
func record_attack(attack_event) -> void:
	var attack_event_id: String = str(attack_event.id)
	_attack_records[attack_event_id] = {
		"attack_event": attack_event,
		"reactions":    {},
	}


## record_reaction(reaction_event, correlated_attack_id) → bool — FEAT-007
## (US-007 / FR-008): pairs a structured core/log/reaction_resolved_event.gd
## ReactionResolvedEvent to the AttackEvent previously stored via
## record_attack(correlated_attack_id), keyed by `reaction_event.window_id`
## ("PreHitAvoidance" | "OnHitMitigation") — the composite
## attack_event_id+window_id key the design's data_model specifies. Returns
## true iff the pairing was recorded. Returns false (and records the
## rejection in `_rejected_duplicate_reactions`, see that field's doc) for
## either failure:
##   - `correlated_attack_id` does not match any AttackEvent record_attack()
##     has stored — an unpaired/unknown correlation.
##   - a ReactionResolvedEvent has ALREADY been recorded for this EXACT
##     (attack_event_id, window_id) pair — this is the storage-level
##     expression of the <=1-reaction-per-Strike budget rule (a genuinely
##     new PreHitAvoidance AND OnHitMitigation pairing for the SAME
##     AttackEvent is legal and distinct — only a SECOND firing of the SAME
##     window is rejected). The original pairing is left completely
##     untouched — never silently overwritten.
func record_reaction(reaction_event, correlated_attack_id) -> bool:
	var attack_event_id: String = str(correlated_attack_id)
	if not _attack_records.has(attack_event_id):
		push_error(
			"EventLogView.record_reaction: no AttackEvent recorded for attack_event_id='%s'; rejecting pairing"
			% attack_event_id
		)
		return false

	var window_id: String = str(reaction_event.window_id)
	var reactions: Dictionary = _attack_records[attack_event_id]["reactions"]
	if reactions.has(window_id):
		push_error(
			"EventLogView.record_reaction: duplicate window firing rejected for attack_event_id='%s' window_id='%s'"
			% [attack_event_id, window_id]
		)
		_rejected_duplicate_reactions.append({
			"attack_event_id": attack_event_id,
			"window_id":       window_id,
		})
		return false

	reactions[window_id] = reaction_event
	return true


## get_structured_attack(attack_event_id) → AttackEvent or null — FEAT-007:
## the accessor for structured data test_criteria #1 requires. Returns null
## when no AttackEvent has been recorded for `attack_event_id` (an "unpaired"
## lookup, never an error).
func get_structured_attack(attack_event_id):
	var key: String = str(attack_event_id)
	if not _attack_records.has(key):
		return null
	return _attack_records[key]["attack_event"]


## get_paired_reaction(attack_event_id, window_id) → ReactionResolvedEvent or
## null — FEAT-007: the accessor half of record_reaction()'s composite-key
## pairing. Returns null when either `attack_event_id` was never recorded, or
## no reaction has been paired to that (attack_event_id, window_id) slot yet.
func get_paired_reaction(attack_event_id, window_id):
	var key: String = str(attack_event_id)
	if not _attack_records.has(key):
		return null
	return _attack_records[key]["reactions"].get(str(window_id), null)


## get_rejected_duplicate_reactions() → Array — a read-only copy of every
## duplicate-window-firing rejection recorded so far (see
## `_rejected_duplicate_reactions`'s doc above).
func get_rejected_duplicate_reactions() -> Array:
	return _rejected_duplicate_reactions.duplicate()


## _OUTCOME_DISPLAY — FEAT-008 (US-008 / FR-007): maps a
## core/log/reaction_resolved_event.gd ReactionResolvedEvent.outcome value
## (underscore_case, the storage-layer vocabulary FEAT-007 established) to
## the hyphenated display string this feature's rendering surfaces
## (matches design notes' "none/dodge-succeeded/dodge-failed/
## parry-succeeded/parry-failed/block reduced-by-N" vocabulary exactly).
## "block_reduced_by_n" is handled separately (get_active_defense_outcome_string()
## below) since it needs `reduced_by` interpolated into the "-N" suffix.
const _OUTCOME_DISPLAY: Dictionary = {
	"none":             "none",
	"dodge_succeeded":  "dodge-succeeded",
	"dodge_failed":     "dodge-failed",
	"parry_succeeded":  "parry-succeeded",
	"parry_failed":     "parry-failed",
}

## _REACTION_WINDOW_PRIORITY — FEAT-008: the order in which paired reaction
## windows are inspected when deriving the single active-defense outcome
## string for an AttackEvent. core/rules/resolution.gd's <=1-reaction-per-
## Strike budget (enforced by core/application/round_session.gd's shared
## spend_reaction() gate, see design notes' `security` section) guarantees
## AT MOST ONE of these two windows will ever carry a non-"none" outcome for
## the same Strike, so "first non-none wins" never has to arbitrate a real
## conflict — it only has to skip a window that was never spent (whose
## paired reaction, if any, records the explicit "none"/Pass outcome).
const _REACTION_WINDOW_PRIORITY: Array = ["PreHitAvoidance", "OnHitMitigation"]


## get_active_defense_outcome_string(attack_event_id) → String — FEAT-008
## (US-008 / FR-007): derives the single human-readable active-defense
## outcome string for the AttackEvent recorded at `attack_event_id`, purely
## by reading the already-computed `outcome` (and, for a block, `reduced_by`)
## fields off whichever paired core/log/reaction_resolved_event.gd
## ReactionResolvedEvent actually fired — this method performs NO dice
## rolling, no math, and never touches core/rules/resolution.gd; it only
## reformats data resolution.gd (via round_session.gd) already produced.
## Returns one of: "none", "dodge-succeeded", "dodge-failed",
## "parry-succeeded", "parry-failed", "block reduced-by-N" (N = reduced_by).
## Returns "none" when `attack_event_id` has no recorded AttackEvent, or
## when neither paired window (if any) reports an outcome other than "none"
## (mirrors get_paired_reaction()'s "unpaired lookup, never an error"
## convention).
func get_active_defense_outcome_string(attack_event_id) -> String:
	for window_id in _REACTION_WINDOW_PRIORITY:
		var reaction = get_paired_reaction(attack_event_id, window_id)
		if reaction == null:
			continue
		if reaction.outcome == "block_reduced_by_n":
			var reduced_by: int = int(reaction.reduced_by) if reaction.reduced_by != null else 0
			return "block reduced-by-%d" % reduced_by
		if reaction.outcome != "none" and _OUTCOME_DISPLAY.has(reaction.outcome):
			return _OUTCOME_DISPLAY[reaction.outcome]
	return "none"


## render_attack_entry(attack_event_id) → String — FEAT-008 (US-008 /
## FR-007): renders the RICH, structured-data formatted string for the
## AttackEvent recorded at `attack_event_id` via record_attack() — showing
## roll_total, the hit/crit flag, damage_raw AND damage_final, plus the
## active-defense outcome derived from the paired ReactionResolvedEvent (see
## get_active_defense_outcome_string() above). This is a NEW, ADDITIVE
## rendering path layered on top of FEAT-007's `_attack_records` structured
## storage — it is completely separate from on_attack_event()'s pre-existing
## Dictionary-driven `_entries` path (test_criteria #4 of FEAT-007's suite:
## that path must stay byte-for-byte unchanged), and from resolution.gd's
## RNG/math (this method only reformats data already computed elsewhere).
## Returns "" when `attack_event_id` has no recorded AttackEvent (an
## "unpaired" lookup, never an error).
func render_attack_entry(attack_event_id) -> String:
	var attack_event = get_structured_attack(attack_event_id)
	if attack_event == null:
		return ""

	var text: String
	if attack_event.is_hit:
		var hit_label: String = "Critical Hit" if attack_event.is_crit else "Hit"
		text = "Round %d: %s attacks %s — %s (roll %d) for %d raw / %d final damage." % [
			attack_event.round_number, attack_event.attacker_id, attack_event.target_id,
			hit_label, attack_event.roll_total, attack_event.damage_raw, attack_event.damage_final,
		]
	else:
		text = "Round %d: %s attacks %s — Miss (roll %d)." % [
			attack_event.round_number, attack_event.attacker_id, attack_event.target_id,
			attack_event.roll_total,
		]

	var defense_outcome: String = get_active_defense_outcome_string(attack_event_id)
	if defense_outcome != "none":
		text += " Defense: %s." % defense_outcome
	else:
		text += " Defense: none."

	return text


## overwrite_entry_as_rich(index, text, attack_event_id) → bool — FEAT-005
## (US-005, Iteration J-R2 Part D; formalized as the current iteration's
## US-007 ICombatLogPort.suppress_basic_entry() contract, see this file's
## top-level doc): overwrites the ALREADY-APPENDED entry at
## append-order `index` (its `_entries[index]`/`_labels[index]` pairing) in
## place with an already-rendered rich text (the caller renders it via
## render_attack_entry() first; this method never renders/formats anything
## itself), tagging `attack_event_id` onto that SAME entry so a caller/test
## can correlate the visible row back to its structured AttackEvent (see
## get_structured_attack()).
##
## This keeps the row's ORIGINAL chronological position (sequence_number,
## append-order index) intact -- critical when a Strike's synchronous
## EventSinkPort dispatch (the Application-layer Strike-resolution call)
## ALSO triggers a same-call CombatantDefeatedEvent immediately afterward:
## the attack row must stay chronologically BEFORE its own consequence, so
## a live call site (MainScene.gd's `_verb_bar_strike_execute()`) captures
## the entry index the plain-format on_attack_event() append will land at
## (event_log_view.get_entry_count() BEFORE triggering that Strike
## resolution) and, once it returns with the resolved roll/damage fields,
## overwrites THAT SAME index in place -- rather than appending a SECOND row
## at the end, which would land the rich row AFTER any already-dispatched
## defeat entry and leave the stale plain-format row behind as a duplicate.
## Returns false (no-op) when `index` is out of range.
func overwrite_entry_as_rich(index: int, text: String, attack_event_id: String) -> bool:
	if index < 0 or index >= _entries.size():
		return false

	var entry: Dictionary = _entries[index]
	entry["text"] = text
	entry["attack_event_id"] = str(attack_event_id)
	_entries[index] = entry

	if index < _labels.size():
		var label: Label = _labels[index]
		if label != null:
			label.text = text

	return true


## on_round_event(event) → void — dispatch entry point for typed round
## events (ADR-003). `event` is duck-typed: any RefCounted value object from
## core/rules/round_events.gd, or a plain Dictionary. Recognizes:
##   - an AttackEvent-shaped payload (carries `attacker_name` and
##     `target_name`) → on_attack_event()
##   - a CombatantDefeatedEvent-shaped payload (carries `defeated_by`) →
##     on_combatant_defeated_event()
##   - an EncounterResultEvent-shaped payload (carries `outcome`) →
##     on_encounter_result_event()
## Any other/unrecognized event shape is a silent no-op — EventLogView only
## reacts to events it understands, never errors on an unfamiliar one.
func on_round_event(event) -> void:
	if event == null:
		return
	if _event_has(event, "attacker_name") and _event_has(event, "target_name"):
		on_attack_event(event)
	elif _event_has(event, "defeated_by"):
		on_combatant_defeated_event(event)
	elif _event_has(event, "outcome"):
		on_encounter_result_event(event)


## on_attack_event(event) → void — appends one human-readable entry
## describing a resolved Strike. `event` must carry `attacker_name`,
## `target_name`, `hit` (bool), `crit` (bool), `damage_final` (int), and
## optionally `round` (int), matching core/rules/round_events.gd's
## RoundEvents.AttackBroadcast shape.
func on_attack_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var attacker_name: String = _event_get(event, "attacker_name", "")
	var target_name: String = _event_get(event, "target_name", "")
	var hit: bool = _event_get(event, "hit", false)
	var crit: bool = _event_get(event, "crit", false)
	var damage_final: int = _event_get(event, "damage_final", 0)

	var text: String
	if hit:
		var hit_label: String = "Critical Hit" if crit else "Hit"
		text = "Round %d: %s attacks %s — %s for %d damage." % [
			round_number, attacker_name, target_name, hit_label, damage_final,
		]
	else:
		text = "Round %d: %s attacks %s — Miss." % [round_number, attacker_name, target_name]

	_append_entry(round_number, text)


## on_combatant_defeated_event(event) → void — appends one human-readable
## entry describing a combatant's defeat. `event` must carry `name` and
## `defeated_by`, and optionally `round` (int), matching
## core/rules/round_events.gd's RoundEvents.CombatantDefeatedEvent shape.
func on_combatant_defeated_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var name: String = _event_get(event, "name", "")
	var defeated_by: String = _event_get(event, "defeated_by", "")

	var text: String = "Round %d: %s was defeated by %s." % [round_number, name, defeated_by]
	_append_entry(round_number, text)


## on_encounter_result_event(event) → void — appends one human-readable
## entry describing the encounter's terminal outcome. `event` must carry
## `outcome` and optionally `round` (int), matching
## core/rules/round_events.gd's RoundEvents.EncounterResultEvent shape.
func on_encounter_result_event(event) -> void:
	var round_number: int = _event_get(event, "round", 0)
	var outcome: String = _event_get(event, "outcome", "")

	var text: String = "Round %d: Encounter concluded — %s." % [round_number, outcome]
	_append_entry(round_number, text)


# ── Internal helpers ─────────────────────────────────────────────────────

## _append_entry(round_number, text, attack_event_id) → void — appends one
## entry with the next strictly-increasing sequence_number, and creates its
## Label in the SAME append order (never re-sorted), guaranteeing
## chronological (dispatch-order) rendering. `attack_event_id` (FEAT-005,
## optional, "" by default for every pre-existing plain-format caller) tags
## the appended entry with the structured AttackEvent it was rendered from,
## when any — see overwrite_entry_as_rich()'s doc.
func _append_entry(round_number: int, text: String, attack_event_id: String = "") -> void:
	var sequence_number: int = _next_sequence_number
	_next_sequence_number += 1

	_entries.append({
		"sequence_number": sequence_number,
		"round": round_number,
		"text": text,
		"attack_event_id": attack_event_id,
	})

	var label := Label.new()
	label.name = "Entry_%d" % sequence_number
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = 3
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	if _rows_container != null:
		_rows_container.add_child(label)
	_labels.append(label)
	call_deferred("_scroll_to_bottom")


## _scroll_to_bottom() → void — scrolls $Content (ScrollContainer) to the
## bottom so the newest entry is always visible. Called deferred after each
## append so Godot has a frame to measure the new child's size first.
func _scroll_to_bottom() -> void:
	var scroll: ScrollContainer = $Content
	if scroll == null:
		return
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


## _event_has(event, key) → bool — true iff `event` (a Dictionary or an
## Object/RefCounted value object) carries `key`.
func _event_has(event, key: String) -> bool:
	if event is Dictionary:
		return event.has(key)
	return key in event


## _event_get(event, key, default) → Variant — reads `key` from `event`
## (a Dictionary or an Object/RefCounted value object), duck-typed so
## EventLogView never depends on a single concrete event class.
func _event_get(event, key: String, default = null):
	if event is Dictionary:
		return event.get(key, default)
	if not (key in event):
		return default
	var value = event.get(key)
	return value if value != null else default


## on_spell_log_entry(entry) → void — renders a CombatLogEntry (from
## core/domain/combat_log_entry.gd) as a human-readable line. Called by
## CombatLogPanelAdapter when a spell cast event is emitted.
func on_spell_log_entry(entry) -> void:
	if entry == null:
		return
	var actor: String = _format_combat_id(entry.actor_id)
	var spell: String = _format_combat_id(entry.spell_id)
	var text: String
	match entry.event_type:
		0: # CAST_BEGIN
			text = "Round %d: %s begins casting %s." % [entry.round_number, actor, spell]
		1: # CAST_CONTINUE
			text = "Round %d: %s continues casting %s." % [entry.round_number, actor, spell]
		2: # CAST_RESOLVE
			if entry.energy_delta != null:
				text = "Round %d: %s casts %s — gained %d energy." % [entry.round_number, actor, spell, entry.energy_delta]
			elif entry.hit == null:
				text = "Round %d: %s casts %s — no valid target." % [entry.round_number, actor, spell]
			elif entry.hit:
				var target: String = _format_combat_id(entry.target_ids[0]) if entry.target_ids.size() > 0 else "target"
				var dmg: int = entry.damage_amount if entry.damage_amount != null else 0
				var roll_suffix: String = " (roll %d)" % entry.roll_total if entry.roll_total != null else ""
				text = "Round %d: %s casts %s — Hit %s%s for %d damage." % [entry.round_number, actor, spell, target, roll_suffix, dmg]
			else:
				var target: String = _format_combat_id(entry.target_ids[0]) if entry.target_ids.size() > 0 else "target"
				var roll_suffix: String = " (roll %d)" % entry.roll_total if entry.roll_total != null else ""
				text = "Round %d: %s casts %s — Miss vs %s%s." % [entry.round_number, actor, spell, target, roll_suffix]
		3: # CAST_CANCELLED
			text = "Round %d: %s's %s was cancelled." % [entry.round_number, actor, spell]
		_:
			text = "Round %d: %s: %s" % [entry.round_number, actor, spell]
	_append_entry(entry.round_number, text)


## _format_combat_id(id) -> String — converts a snake_case combatant/spell id
## to a readable Title Case label. E.g. "fire_bolt" → "Fire Bolt",
## "marigold_1" → "Marigold 1".
func _format_combat_id(id: String) -> String:
	var parts: Array = id.split("_")
	var out: Array = []
	for part in parts:
		out.append(part.capitalize())
	return " ".join(out)
