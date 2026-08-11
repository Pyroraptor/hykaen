## core/application/combat_session_factory.gd — CombatSessionFactory
## (FEAT-003 / US-001 / FR-008, ADR-004; api_contracts #1).
##
## Application layer (Clean Architecture, ADR-001): the entry-point-adjacent
## factory MainScene._ready() (the composition root) delegates its former
## inline resource-loading + party/enemy/hex_combatants assembly to. Depends
## ONLY on the domain layer (core/domain/combatant.gd's Combatant) plus the
## application-layer CombatResourceLoaderPort port (core/application/ports/
## combat_resource_loader_port.gd) — every other collaborator (the concrete
## encounter-repository/combatant-factory/round-pipeline instances) is
## received purely by duck-typed method call through `deps`, never
## preloaded/instantiated here, so this file never imports infrastructure or
## presentation concretes (adapters remain swappable, per the composition-
## root wiring described in the design notes' architecture section).
##
## build(deps: Dictionary) -> Dictionary
##   Pre: deps contains:
##     resource_loader      — CombatResourceLoaderPort (or duck-typed
##                             equivalent); the sole load()/ResourceLoader
##                             caller for `encounter_path` (ADR-005). REQUIRED.
##     encounter_repository — object exposing load_combatants(path) -> Array
##                             (e.g. infrastructure/resource_encounter_repository.gd's
##                             ResourceEncounterRepository). REQUIRED.
##     combatant_factory    — object exposing build_party_combatant(path,
##                             hex_coord, combatant_id) -> Dictionary and
##                             build_enemy_combatant(path, hex_coord,
##                             combatant_id, weapon_path_override="") ->
##                             Dictionary (e.g. infrastructure/
##                             combatant_factory.gd's CombatantFactory).
##                             REQUIRED. FEAT-007 (US-007 / FR-006): the 4th
##                             arg is this encounter's own
##                             weapon_path_overrides[j] for spawn slot j (""
##                             when the array is shorter than j), resolved
##                             by build() itself — a duck-typed double that
##                             only declares 3 params will now fail loudly
##                             (too many arguments), by design.
##     encounter_path        — String path to the EncounterResource to load.
##                             REQUIRED.
##     run_round_use_case    — OPTIONAL object exposing begin_round(
##                             round_number, party, enemies) -> RoundSession.
##                             When present (and non-null), build() calls it
##                             to materialize `round_session`; otherwise
##                             `round_session` is null in the returned
##                             Dictionary (MainScene's own _ready() does not
##                             supply one at this point in composition-root
##                             wiring — its `round_session` property remains
##                             governed entirely by rewire_session(), FEAT-316
##                             — this factory never assigns it directly).
##     round_number          — OPTIONAL int, default 1; the round number
##                             handed to run_round_use_case.begin_round().
##
##   Post (success): returns {round_session, party: Array[Combatant],
##   enemies: Array[Combatant], hex_combatants: Array}.
##
##   Failure (ADR-005 — no exceptions, GDScript has none): on a missing
##   required deps key, an unresolvable `encounter_path`, or a fail-fast
##   enemy-build error (CombatantFactory.build_enemy_combatant()'s
##   {"error": ERR_...} contract), push_error()s a descriptive message and
##   returns an empty Dictionary — every caller MUST check `.is_empty()`
##   before proceeding.
##
## Domain purity boundary (ADR-001): extends RefCounted only — no
## Node/Control/SceneTree inheritance, no engine I/O (all engine I/O is
## reached exclusively through the injected `resource_loader` port).

class_name CombatSessionFactory
extends RefCounted

const CombatantClass = preload("res://core/domain/combatant.gd")

const REQUIRED_DEPS_KEYS: Array = [
	"resource_loader", "encounter_repository", "combatant_factory", "encounter_path"
]


## build(deps) -> Dictionary — see file-level doc for the full contract.
static func build(deps: Dictionary) -> Dictionary:
	for key in REQUIRED_DEPS_KEYS:
		if not deps.has(key) or deps[key] == null:
			push_error("CombatSessionFactory: missing required deps key '%s'" % key)
			return {}

	var resource_loader = deps["resource_loader"]
	var encounter_repository = deps["encounter_repository"]
	var combatant_factory = deps["combatant_factory"]
	var encounter_path: String = deps["encounter_path"]

	var encounter_resource = resource_loader.load_resource(encounter_path)
	if encounter_resource == null:
		push_error("CombatSessionFactory: unresolvable resource path %s" % encounter_path)
		return {}

	var hex_combatants: Array = encounter_repository.load_combatants(encounter_path)

	var party: Array = []
	for i in range(encounter_resource.party_resource_paths.size()):
		var party_hex = hex_combatants[i].hex_coord if i < hex_combatants.size() else null
		var party_id: String = hex_combatants[i].combatant_id if i < hex_combatants.size() else ""
		var party_dict: Dictionary = combatant_factory.build_party_combatant(
			encounter_resource.party_resource_paths[i], party_hex, party_id
		)
		party.append(CombatantClass.from_dict(party_dict))

	var party_count: int = encounter_resource.party_resource_paths.size()
	var enemies: Array = []
	for j in range(encounter_resource.enemy_resource_paths.size()):
		var idx: int = party_count + j
		var enemy_hex = hex_combatants[idx].hex_coord if idx < hex_combatants.size() else null
		var enemy_id: String = hex_combatants[idx].combatant_id if idx < hex_combatants.size() else ""
		# FEAT-007 (US-007 / FR-006, ADR-005/ADR-006): look up this spawn
		# slot's weapon_path_overrides[j] per the design's "Encounter
		# spawn-slot override lookup" api_contract -- an index beyond
		# weapon_path_overrides.size() (or an authored empty string) both
		# collapse to "" (no override, CombatantFactory falls back to the
		# enemy's own weapon_paths[0]), never an index-out-of-range error.
		var weapon_path_override: String = ""
		if j < encounter_resource.weapon_path_overrides.size():
			weapon_path_override = encounter_resource.weapon_path_overrides[j]
		# FEAT-006 (US-006, EWA2-2-1): identical index-aligned lookup for
		# off_hand_path_overrides[j] -- an index beyond the array's bounds
		# (or an authored empty string) both collapse to "" (no override,
		# CombatantFactory falls back to enemy.weapon_paths[1] if present).
		var off_hand_path_override: String = ""
		if j < encounter_resource.off_hand_path_overrides.size():
			off_hand_path_override = encounter_resource.off_hand_path_overrides[j]
		var enemy_combatant: Dictionary = combatant_factory.build_enemy_combatant(
			encounter_resource.enemy_resource_paths[j], enemy_hex, enemy_id, weapon_path_override, off_hand_path_override
		)
		if enemy_combatant.has("error"):
			push_error(
				"CombatSessionFactory: aborting session assembly — enemy build failed for '%s' (%s)"
				% [encounter_resource.enemy_resource_paths[j], enemy_combatant["error"]]
			)
			return {}
		enemies.append(CombatantClass.from_dict(enemy_combatant))

	var round_session = null
	var run_round_use_case = deps.get("run_round_use_case")
	if run_round_use_case != null:
		round_session = run_round_use_case.begin_round(deps.get("round_number", 1), party, enemies)

	return {
		"round_session": round_session,
		"party": party,
		"enemies": enemies,
		"hex_combatants": hex_combatants,
	}
