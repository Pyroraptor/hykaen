## presentation/ui/combat_log_panel_adapter.gd — CombatLogPanelAdapter
## (FEAT-276 / US-011; FR-010)
##
## Adapter/presentation layer (Clean Architecture, ADR-001): the ONE
## concrete implementation of core/application/ports/combat_log_port.gd's
## CombatLogPort this feature ships — design notes' architecture section:
## "CombatLogPanel (presentation UI) — subscribes to CombatLogPort events
## and renders them; this satisfies the exit-point requirement ('Combat
## log shows the resolved spell outcome')."
##
## Extends CombatLogPort BY PATH (mirrors core/application/ports/
## resolution_port.gd's own nested ResolutionRulesAdapter / this project's
## established preload-typing convention for concrete adapters/subtypes —
## see core/domain/combatant.gd's hex_coord doc for why a bare global
## class_name is avoided as an `extends` target: it needs Godot's global
## script-class cache to already know a brand-new script, not guaranteed
## headless/CI).
##
## A pure RefCounted recorder/renderer (no Node/Control scene-tree
## dependency, mirroring presentation/verbs/resolve_spell_controller.gd's
## and presentation/verbs/spell_action_controller.gd's own "adapter without
## a scene" convention) — every emitted CombatLogEntry is appended, in
## append order, to an in-memory Array, and can be read back either as the
## structured value object (get_entry()) or as a rendered human-readable
## line (get_entry_text()/render_entry()), mirroring presentation/
## event_log_view.gd's EventLogView established
## record_attack()/render_attack_entry() split between structured storage
## and display-string rendering. No composition-root/scene wiring exists
## yet for a live Control this feature attaches to the tree — that is a
## later feature's job (mirrors presentation/verbs/resolve_spell_controller.gd's
## own "no live TargetingPort UI wired yet" convention for
## `_targeting_port`) — this adapter is fully usable/testable standalone in
## the meantime via `CombatLogPanelAdapter.new()`.
##
## Usage:
##   var panel := CombatLogPanelAdapter.new()
##   panel.emit(CombatLogEntry.new(CombatLogEntry.EventType.CAST_RESOLVE, "marigold_1", "fire_bolt", ["skeleton"], true, 9, null))
##   panel.get_entry_count()      # 1
##   panel.get_entry(0).hit       # true
##   panel.get_entry_text(0)      # "fire_bolt: marigold_1 -> skeleton — Hit for 9 damage."

class_name CombatLogPanelAdapter
extends "res://core/application/ports/combat_log_port.gd"


## _entries — ordered Array[CombatLogEntry] of every emitted entry, in
## strict append (dispatch) order. Never re-sorted (mirrors
## presentation/event_log_view.gd's `_entries` append-only convention).
var _entries: Array = []

## _log_view — optional EventLogView reference set via configure(). When set,
## every emit() call immediately forwards the entry for live rendering.
var _log_view = null


## configure(log_view) -> void — wires a live EventLogView so emit() calls
## forward to on_spell_log_entry() for immediate rendering. Called once by
## the composition root (MainScene._ready()) after both objects are created.
func configure(log_view) -> void:
	_log_view = log_view


## emit(entry) -> void — CombatLogPort's contract: appends `entry` to this
## adapter's in-memory log. A null entry is skipped with a push_error
## (defensive; ResolveCastUseCase never hands this adapter a null entry in
## practice) rather than corrupting `_entries` with a null hole.
func emit(entry) -> void:
	if entry == null:
		push_error("CombatLogPanelAdapter.emit(): null entry -- skipping")
		return
	_entries.append(entry)
	if _log_view != null and _log_view.has_method("on_spell_log_entry"):
		_log_view.on_spell_log_entry(entry)


## get_entry_count() -> int — number of entries emitted so far.
func get_entry_count() -> int:
	return _entries.size()


## get_entry(index) -> CombatLogEntry | null — the structured entry at
## append-order `index`, or null when `index` is out of range (mirrors
## presentation/event_log_view.gd's own out-of-range-returns-empty
## convention, adapted to this adapter's "return the value object itself"
## shape rather than a Dictionary snapshot).
func get_entry(index: int):
	if index < 0 or index >= _entries.size():
		return null
	return _entries[index]


## get_entry_text(index) -> String — the rendered human-readable line for
## the entry at append-order `index` (see render_entry()'s doc), or "" when
## `index` is out of range.
func get_entry_text(index: int) -> String:
	var entry = get_entry(index)
	return render_entry(entry) if entry != null else ""


## get_resolve_entry_count() -> int — number of CAST_RESOLVE entries emitted.
func get_resolve_entry_count() -> int:
	var count := 0
	for e in _entries:
		if e.event_type == 2:
			count += 1
	return count


## get_resolve_entry(index) -> CombatLogEntry | null — the Nth CAST_RESOLVE
## entry in emission order, or null when index is out of range.
func get_resolve_entry(index: int):
	var i := 0
	for e in _entries:
		if e.event_type == 2:
			if i == index:
				return e
			i += 1
	return null


## get_resolve_entry_text(index) -> String — rendered text for the Nth
## CAST_RESOLVE entry, or "" when index is out of range.
func get_resolve_entry_text(index: int) -> String:
	var entry = get_resolve_entry(index)
	return render_entry(entry) if entry != null else ""


## render_entry(entry) -> String — formats one CombatLogEntry as a
## human-readable line. Purely a reformatting of already-computed data
## (mirrors presentation/event_log_view.gd's render_attack_entry()'s
## identical "never rolls dice, never computes damage" discipline) — this
## method never mutates `entry` or any domain state.
##   - hit == null   -> "<spell_id>: <actor_id> -> <targets> — no valid target."
##   - hit == true    -> "<spell_id>: <actor_id> -> <targets> — Hit for <damage> damage."
##   - hit == false   -> "<spell_id>: <actor_id> -> <targets> — Miss."
func render_entry(entry) -> String:
	if entry == null:
		return ""

	var targets_label: String = ", ".join(entry.target_ids) if not entry.target_ids.is_empty() else "no target"
	var prefix: String = "%s: %s -> %s" % [entry.spell_id, entry.actor_id, targets_label]

	if entry.hit == null:
		return "%s — no valid target." % prefix
	if entry.hit:
		var damage: int = entry.damage_amount if entry.damage_amount != null else 0
		return "%s — Hit for %d damage." % [prefix, damage]
	return "%s — Miss." % prefix
