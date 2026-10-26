extends SceneTree
## Actual randomized departures and entry schools, using memory progress only.
const Ocean = preload("res://scripts/ocean_config.gd")
const FishData = preload("res://scripts/fish_catalog.gd")
const SAMPLE_SEEDS: Array[int] = [17, 42, 20261026]

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var checks: int = 0
var failures: int = 0
var game: Node
var memory: MemoryProgression
var seen_sites: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		printerr("FAIL: main scene could not load")
		quit(1)
		return
	game = packed.instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.smoke_mode = true
	game.muted = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	await physics_frame
	await process_frame
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_test_fixed_fixture()
	await _test_blocked_fish_fallback()
	_check(Ocean.DIVE_SITES.size() == 7, "Departures offer the cove and all six outer-ocean destinations")
	var first_sequence: Array[Vector3] = await _sample_departures(SAMPLE_SEEDS[0], 8)
	var second_sequence: Array[Vector3] = await _sample_departures(SAMPLE_SEEDS[1], 8)
	await _sample_departures(SAMPLE_SEEDS[2], 8)
	_check(first_sequence != second_sequence, "Independent seeds produce different actual departure positions")
	var repeated_sequence: Array[Vector3] = await _sample_departures(SAMPLE_SEEDS[0], 8)
	_check(first_sequence == repeated_sequence, "Entry RNG reproduces departures independently of fish population RNG")
	_check(seen_sites.size() == Ocean.DIVE_SITES.size(), "Seeded repeated departures actually exercise every candidate site")
	game.state = "dock"
	game.start_dive(false)
	_check(not game.entry_active and game.player.position.is_equal_approx(game.dive_origin + Vector3(0, -6, 14)), "Skipping animation still uses the chosen random site")
	_check(memory._save_data() == progress_before and memory.saves == 0, "Random departures, animation and fish generation do not mutate or save player progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver randomized dive spawns (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_fixed_fixture() -> void:
	game.start_dive(false, false)
	_check(game.dive_origin == Vector3.ZERO and game.entry_site_index == 0 and game.player.position == Vector3(0, -6, 14), "Explicit fixed departure retains the original underwater test fixture")
	var beginner_fish_unchanged: bool = true
	for index in range(5):
		var expected := Vector3((index - 2) * 3.0, -7 - index * 0.6, 1 - index * 2.0)
		beginner_fish_unchanged = beginner_fish_unchanged and game.fish[index].kind == 0 and game.fish[index].home.is_equal_approx(expected)
	_check(beginner_fish_unchanged, "The five authored beginner fish keep their original species and positions")
	var coastal_kinds: Dictionary = {}
	for item in game.fish.slice(0, game.COASTAL_FISH_COUNT):
		coastal_kinds[item.kind] = true
	var complete: bool = coastal_kinds.size() == 6
	for kind in [0, 1, 2, 3, 4, 6]:
		complete = complete and coastal_kinds.has(kind)
	_check(complete, "Original coastal population now includes six distinct non-attacking species")

func _test_blocked_fish_fallback() -> void:
	var candidate := Vector3(200, -8, 200)
	var blocker := StaticBody3D.new()
	blocker.position = candidate
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 55.0
	collider.shape = shape
	blocker.add_child(collider)
	root.add_child(blocker)
	await physics_frame
	var radius: float = float(FishData.SPECIES[0].radius)
	var local_search_blocked: bool = not _sphere_clear(candidate, radius)
	for direction in range(8):
		var angle: float = direction * TAU / 8.0
		var furthest_local := candidate + Vector3(sin(angle) * 30, 6, cos(angle) * 30)
		local_search_blocked = local_search_blocked and not _sphere_clear(furthest_local, radius)
	_check(local_search_blocked, "Large solid obstruction blocks both the requested fish point and all local search directions")
	var count_before: int = game.fish.size()
	var spawned: Dictionary = game._add_fish(0, candidate)
	_check(not spawned.is_empty() and game.fish.size() == count_before + 1 and spawned.alive and spawned.hp == FishData.SPECIES[0].hp, "Actual fish creation succeeds through the distant fallback when the local area is entirely blocked")
	if not spawned.is_empty():
		_check(spawned.home.distance_to(candidate) > shape.radius + radius and spawned.node.position == spawned.home and _sphere_clear(spawned.home, radius), "Fallback fish really appears outside the large obstruction and every other solid")
	blocker.free()
	await physics_frame

func _sample_departures(seed_value: int, count: int) -> Array[Vector3]:
	game.entry_rng.seed = seed_value
	game.entry_site_index = -1
	var previous_site: int = -1
	var sequence: Array[Vector3] = []
	for departure in range(count):
		game.state = "dock"
		game.start_dive()
		await physics_frame
		await process_frame
		var context: String = "seed %d departure %d" % [seed_value, departure]
		var index: int = game.entry_site_index
		var origin: Vector3 = game.dive_origin
		sequence.append(origin)
		_check(index >= 0 and index < Ocean.DIVE_SITES.size() and index != previous_site, "Consecutive departures choose distinct valid sites: " + context)
		if index < 0 or index >= Ocean.DIVE_SITES.size():
			continue
		seen_sites[index] = true
		previous_site = index
		var base: Vector3 = Ocean.DIVE_SITES[index].origin
		_check(absf(origin.x - base.x) <= 8.001 and absf(origin.z - base.z) <= 8.001 and origin.y == 0, "Random position stays near its named destination at sea level: " + context)
		_check(game.boat.position.is_equal_approx(origin + Vector3(0, 0.3, 14)) and game.player.position.is_equal_approx(origin + Vector3(0, 2.4, 17.5)), "Boat and diver relocate together before the stern jump: " + context)
		_test_spawn_population(origin, context)
		_test_entry_at(origin, context)
	return sequence

func _test_spawn_population(origin: Vector3, context: String) -> void:
	_check(game.fish.size() == 167 and game.fish.size() == game.fish_population_count(), "Random destination retains exactly 167 ordinary catchable fish: " + context)
	var landing: Vector3 = origin + Vector3(0, -6, 25)
	var immediate_spawn: Vector3 = origin + Vector3(0, -6, 14)
	var safe: bool = true
	var nearby_count: int = 0
	for item in game.fish:
		if item.alive and item.node.position.distance_to(landing) <= 30.0:
			nearby_count += 1
		if item.kind in [5, 7, 8]:
			safe = safe and item.node.position.distance_to(landing) >= 30.0 and item.node.position.distance_to(immediate_spawn) >= 30.0
	for item in game.hazards:
		safe = safe and item.node.position.distance_to(landing) >= 20.0
	_check(safe, "Dangerous fish and jellyfish leave room to enter and begin swimming: " + context)
	_check(nearby_count <= 14, "All population sources together keep at most fourteen fish within thirty metres of the landing: " + context)
	var entry_start: int = game.COASTAL_FISH_COUNT + game.OUTER_FISH_PER_ZONE * Ocean.ZONES.size() + game.TRANSIT_SCHOOLS * game.TRANSIT_FISH_PER_SCHOOL
	var entry_fish: Array = game.fish.slice(entry_start)
	_check(entry_fish.size() == 10 and entry_fish.size() == game.ENTRY_SCHOOL_KINDS.size() * game.ENTRY_FISH_PER_SCHOOL, "Entry adds exactly ten ordinary fish beyond the coastal, outer and transit populations: " + context)
	var added_kinds: Dictionary = {}
	var visible_kinds: Dictionary = {}
	var schools_clear: bool = true
	for item in entry_fish:
		var point: Vector3 = item.node.position
		if not added_kinds.has(item.kind):
			added_kinds[item.kind] = []
		added_kinds[item.kind].append(point)
		schools_clear = schools_clear and item.alive and _sphere_clear(point, float(FishData.SPECIES[item.kind].radius))
		var offset: Vector3 = point - landing
		if offset.z > 0 and offset.length() <= 30.0 and absf(offset.x) <= offset.z * 1.3:
			var ray := PhysicsRayQueryParameters3D.create(landing, point, 1, [game.player.get_rid()])
			if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				visible_kinds[item.kind] = true
	var mixed: bool = added_kinds.size() == 5
	for kind in [0, 1, 3, 4, 6]:
		mixed = mixed and added_kinds.has(kind) and added_kinds[kind].size() == 2
	_check(mixed, "Additional entry schools retain two fish each of five non-attacking species: " + context)
	var schools_spaced: bool = true
	for group in added_kinds.values():
		for first in range(group.size()):
			for second in range(first + 1, group.size()):
				schools_spaced = schools_spaced and group[first].distance_to(group[second]) >= 4.0 - 0.001
	_check(schools_spaced, "Fish within each entry school begin at least four metres apart: " + context)
	_check(schools_clear, "Every additional fish spawns alive outside solid geometry: " + context)
	_check(visible_kinds.size() >= 2, "At least two fish kinds are nearby ahead with clear lines of sight: " + context)

func _test_entry_at(origin: Vector3, context: String) -> void:
	var air_before: float = game.oxygen
	var clear_path: bool = _sphere_clear(game.player.position, 0.65)
	game._physics_process(0.8)
	clear_path = clear_path and _sphere_clear(game.player.position, 0.65)
	_check(game.entry_active and game.player.position.z > origin.z + 17.5 and game.camera.position.is_equal_approx(game.player.position + Vector3(7, 3.2, 7)), "Jump and above-water follow camera use the chosen site's offset: " + context)
	game._physics_process(0.75)
	clear_path = clear_path and _sphere_clear(game.player.position, 0.65)
	game._physics_process(1.65)
	clear_path = clear_path and _sphere_clear(game.player.position, 0.65)
	var landing: Vector3 = origin + Vector3(0, -6, 25)
	_check(clear_path and not game.entry_active and game.player.position.is_equal_approx(landing), "Entry clears solid geometry and ends at the selected underwater landing: " + context)
	var forward := Vector3(0, sin(-0.12), cos(-0.12))
	var camera_target: Vector3 = landing - forward * 7.5 + Vector3.UP * 1.7
	_check(game.camera.position.is_equal_approx(camera_target) and game.camera.position.y < 0.6 and game.camera.fov == 66, "Camera settles behind the diver underwater at every destination: " + context)
	var visible_after_entry: Dictionary = {}
	for item in game.fish:
		if not item.alive or not item.node.visible:
			continue
		var point: Vector3 = item.node.position
		var offset: Vector3 = point - landing
		if offset.z > 0 and offset.length() <= 30.0 and absf(offset.x) <= offset.z * 1.3:
			var ray := PhysicsRayQueryParameters3D.create(landing, point, 1, [game.player.get_rid()])
			if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				visible_after_entry[item.kind] = true
	_check(visible_after_entry.size() >= 2, "At least two fish kinds remain visible nearby ahead after the complete animated entry: " + context)
	_check(game.oxygen == air_before and game.depth_record == 0 and game.cargo.is_empty(), "Randomized entry preserves air, exploration statistics and empty cargo: " + context)
	game._physics_process(0.1)
	_check(game.oxygen >= air_before - 0.08 and game.hurt_cooldown == 0 and game.poison_timer == 0, "First swimming update incurs breathing only, without an immediate enemy hit: " + context)

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
