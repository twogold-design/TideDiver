extends SceneTree
## Actual peripheral landmarks, usable resources and physical exploration routes.
const Ocean = preload("res://scripts/ocean_config.gd")
const Loot = preload("res://scripts/loot_catalog.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var memory: MemoryProgression
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	memory = MemoryProgression.new()
	memory.persistence_enabled = false
	game.progress = memory
	game.muted = true
	game.smoke_mode = true
	root.add_child(game)
	game.smoke_mode = true
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	await physics_frame
	await process_frame
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	var areas: Array = Ocean.exploration_areas()
	var expansions: Node3D = game.ocean_root.get_node_or_null("DiveExpansions")
	var added_resources: int = 0
	for item in game.pickups:
		if item.has("exploration_site"):
			added_resources += 1
	_check(areas.size() == 6 and Ocean.DIVE_SITES.size() == 6, "All six original dive destinations provide expanded exploration areas")
	_check(game.fish.size() == 171 and game.fish_population_count() == 171 and game.pickups.size() == 65 and game.pickups.size() == 12 + Ocean.pickup_points().size() and added_resources == 18, "Larger areas add eighteen resources while keeping the ordinary fish population sparse")
	_check(expansions != null and int(expansions.get_meta("site_count", 0)) == 6 and int(expansions.get_meta("side_area_count", 0)) == 12, "The actual scene includes twelve peripheral landmarks across all six sites")
	if expansions != null and areas.size() == 6:
		var ids: Dictionary = {}
		for site in range(areas.size()):
			var area: Dictionary = areas[site]
			ids[area.id] = true
			_check(float(area.radius) >= 68 and float(area.radius) >= float(area.core_radius) + 20, "Explorable radius extends substantially beyond the old core: " + str(area.name))
			_test_fish_coverage(area)
			await _test_landmarks(site, area, expansions)
			_test_peripheral_resources(site, area)
		_check(ids.size() == 6, "Expanded areas preserve six distinct destination identities")
		_test_gm_and_random_departures()
		await _test_air_cost()
	_test_current_isolation()
	_check(memory._save_data() == progress_before and memory.saves == 0, "Exploration, collection, refills and GM inspection do not change or save durable progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver expanded dive areas (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_current_isolation() -> void:
	var center_z: float = Ocean.CANYON_CENTER.z
	var extended_flow := true
	var quiet_banks := true
	var quiet_mouths := true
	for side: float in [-1.0, 1.0]:
		var inside_z: float = center_z + side * (Ocean.CANYON_HALF_LENGTH - 10.0)
		extended_flow = extended_flow and Ocean.current_velocity(Vector3(Ocean.canyon_center_x(inside_z), -50, inside_z)).length() > 0.1
		extended_flow = extended_flow and Ocean.current_velocity(Vector3(Ocean.canyon_center_x(center_z) + side * (Ocean.CANYON_FLOOR_HALF_WIDTH + 4.0), -50, center_z)).length() > 0.1
		for outside: float in [0.0, 0.5, 12.0]:
			var outside_z: float = center_z + side * (Ocean.CANYON_HALF_LENGTH + outside)
			quiet_mouths = quiet_mouths and Ocean.current_velocity(Vector3(Ocean.canyon_center_x(outside_z), -50, outside_z)).is_zero_approx()
			quiet_banks = quiet_banks and Ocean.current_velocity(Vector3(Ocean.canyon_center_x(center_z) + side * (Ocean.CANYON_BANK_HALF_WIDTH + outside), -50, center_z)).is_zero_approx()
	_check(extended_flow, "The enlarged current reaches both new channel ends and both wider inner banks")
	_check(quiet_mouths and quiet_banks, "Both banks and both mouths become still at and beyond the enlarged canyon boundary")
	var other_sites_quiet := true
	for site in range(Ocean.DIVE_SITES.size()):
		if site == 1:
			continue
		var area: Dictionary = Ocean.exploration_areas()[site]
		var samples: Array[Vector3] = [area.center, Ocean.DIVE_SITES[site].origin + Vector3(0, -6, 25)]
		for point: Dictionary in Ocean.exploration_points(site):
			samples.append(point.position + Vector3.UP * 8)
		for point: Vector3 in samples:
			point.y = maxf(point.y, Ocean.seabed_height(point.x, point.z) + 3.0)
			other_sites_quiet = other_sites_quiet and Ocean.current_velocity(point).is_zero_approx()
	_check(other_sites_quiet, "Every other dive site's center, actual entry landing and peripheral discoveries remain free of canyon current")

func _test_fish_coverage(area: Dictionary) -> void:
	var center: Vector3 = area.center
	var nearby: int = 0
	var peripheral: int = 0
	for item in game.fish:
		var distance: float = Vector2(item.home.x - center.x, item.home.z - center.z).length()
		if distance <= float(area.radius) + 8:
			nearby += 1
			if distance > float(area.core_radius) + 5:
				peripheral += 1
	_check(nearby >= 10 and peripheral >= 3, "Real fish remain distributed inside the larger area and beyond its old core: " + str(area.name))

func _test_landmarks(site: int, area: Dictionary, expansions: Node3D) -> void:
	var points: Array = Ocean.exploration_points(site)
	_check(points.size() == 2, "Two actual destinations extend the exploration route at site %d" % site)
	var region: Node3D = expansions.get_node_or_null("Site%d" % site)
	for index in range(points.size()):
		var point: Dictionary = points[index]
		var position: Vector3 = point.position
		var center: Vector3 = area.center
		var radial: float = Vector2(position.x - center.x, position.z - center.z).length()
		var node: Node3D = region.get_node_or_null("Point%d" % index) if region != null else null
		_check(node != null and radial > float(area.core_radius) + 5 and radial <= float(area.radius) + 1 and _inside_bounds(position) and absf(position.y - Ocean.seabed_height(position.x, position.z)) < 0.02, "The new destination is grounded beyond the old core and inside the ocean: site %d point %d" % [site, index])
		if node == null:
			continue
		_check(node.global_position.distance_to(position) < 0.03 and str(node.get_meta("exploration_name", "")) == str(point.name), "Actual peripheral scenery and its displayed name match the reachable destination: site %d point %d" % [site, index])
		_check(_route_clear(area, position) and _sphere_clear(position + Vector3.UP * 8, 0.65), "A real diver can follow a submerged route around the main scenery to the new destination: site %d point %d" % [site, index])
		game.player.position = position + Vector3.UP * 8
		var nearby: Dictionary = game.nearby_exploration_point()
		_check(not nearby.is_empty() and nearby.name == point.name and nearby.distance < 0.01 and game.ocean_zone_name().contains(str(point.name)), "Reaching the peripheral point identifies the actual destination in navigation: site %d point %d" % [site, index])
		game.camera.position = position + Vector3(12, 10, 16)
		game.camera.look_at(position + Vector3.UP * 2, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		_check(_visible_mesh(node) and not root.get_texture().get_image().is_empty(), "The peripheral destination has actual visible scenery in a rendered game frame: site %d point %d" % [site, index])

func _route_clear(area: Dictionary, destination: Vector3) -> bool:
	var center: Vector3 = area.center
	var radius: float = float(area.core_radius) + 8
	var angle: float = atan2(destination.x - center.x, destination.z - center.z)
	var route: Array[Vector3] = [center + Vector3(0, 0, 36), center + Vector3(0, 0, radius)]
	if area.id == "twin_gates":
		# Follow the submerged gorge rather than crossing its exposed island banks.
		route.clear()
		for step in range(49):
			var z: float = lerpf(center.z + 36.0,destination.z,float(step)/48.0)
			route.append(Vector3(Ocean.canyon_center_x(z),0,z))
	else:
		for step in range(1, 25):
			var heading: float = angle * float(step) / 24.0
			route.append(center + Vector3(sin(heading) * radius, 0, cos(heading) * radius))
	route.append(destination)
	for segment in range(1, route.size()):
		var start: Vector3 = route[segment - 1]
		var finish: Vector3 = route[segment]
		var count: int = maxi(1, int(ceil(Vector2(finish.x - start.x, finish.z - start.z).length() / 2.0)))
		var previous := Vector3(start.x, Ocean.seabed_height(start.x, start.z) + 8, start.z)
		for step in range(1, count + 1):
			var horizontal: Vector3 = start.lerp(finish, float(step) / count)
			var current := Vector3(horizontal.x, Ocean.seabed_height(horizontal.x, horizontal.z) + 8, horizontal.z)
			var collision := KinematicCollision3D.new()
			if game.player.test_move(Transform3D(Basis.IDENTITY, previous), current - previous, collision):
				printerr("Route obstruction at %s toward %s: %s" % [previous,current,collision.get_collider()])
				return false
			previous = current
	return true

func _test_peripheral_resources(site: int, area: Dictionary) -> void:
	var center: Vector3 = area.center
	var collectibles: Array[Dictionary] = []
	var refills: Array[Dictionary] = []
	for item in game.pickups:
		var distance: float = Vector2(item.home.x - center.x, item.home.z - center.z).length()
		if item.active and int(item.get("exploration_site", -1)) == site and distance > float(area.core_radius) + 2 and distance <= float(area.radius) + 8:
			if item.kind == "oxygen":
				refills.append(item)
			else:
				collectibles.append(item)
	_check(collectibles.size() == 2 and refills.size() == 1, "The outer exploration area contains two new collectible rewards and one new usable refill: " + str(area.name))
	game.cargo.clear()
	var collected: bool = collectibles.size() >= 2
	for item in collectibles.slice(0, 2):
		var count: int = game.cargo.size()
		game.player.position = item.node.position
		if item.kind == "chest":
			var contents: Array = item.loot_remaining.duplicate(true)
			var expected_cargo: Array = []
			var expected_air := 0.0
			for reward: Dictionary in contents:
				if reward.id == "oxygen":
					expected_air += float(reward.air)
				else:
					expected_cargo.append(Loot.cargo_entry(reward.id))
			game.oxygen = 5.0
			game.interact()
			var claimed_air: float = game.oxygen - 5.0
			if item.active:
				# Three bottle rewards can exceed a basic tank; the unclaimed air waits.
				game.oxygen = 0.0
				game.interact()
				claimed_air += game.oxygen
			collected = collected and game.cargo.slice(count) == expected_cargo and is_equal_approx(claimed_air,expected_air) and not item.active and item.node.visible and item.node.get_node("Lid").rotation.x > 1.0 and item.loot_remaining.is_empty()
		else:
			game.interact()
			collected = collected and game.cargo.size() == count + 1 and game.cargo[-1] == Loot.cargo_entry(item.kind) and not item.active and not item.node.visible
	_check(collected, "Peripheral finds and the chest's cached random rewards are collected exactly once through the actual cargo and air systems: " + str(area.name))
	var refilled: bool = not refills.is_empty()
	if refilled:
		var item: Dictionary = refills[0]
		game.oxygen = 10
		game.player.position = item.node.position
		game.interact()
		refilled = game.oxygen == 45 and not item.active and not item.node.visible
	_check(refilled, "The peripheral gas bottle actually restores the original thirty-five units of air: " + str(area.name))

func _test_gm_and_random_departures() -> void:
	for site in range(Ocean.DIVE_SITES.size()):
		game.open_gm_menu()
		var expected: Dictionary = game._gm_test_pose(site)
		game.gm_select_dive_site(site, true)
		_check(game.entry_site_index == site and game.player.position.is_equal_approx(expected.position) and _sphere_clear(game.player.position, 0.65), "Expanding the destination preserves its original safe GM viewpoint: %d" % site)
	game.entry_rng.seed = 20261027
	var previous: int = -1
	var visited: Dictionary = {}
	var valid: bool = true
	for departure in range(8):
		game.state = "dock"
		game.start_dive(false)
		valid = valid and game.entry_site_index >= 0 and game.entry_site_index < 6 and game.entry_site_index != previous and game.fish.size() == 171 and game.pickups.size() == 65
		previous = game.entry_site_index
		visited[previous] = true
		var landing: Vector3 = game.dive_origin + Vector3(0, -6, 25)
		var nearby: int = 0
		for item in game.fish:
			if item.node.position.distance_to(landing) <= 30:
				nearby += 1
		valid = valid and nearby <= 14
	_check(valid and visited.size() > 1, "Normal departures stay random and retain the original sparse landing density in expanded areas")

func _test_air_cost() -> void:
	game.player.position = Vector3(400, -20, 400)
	game.player.velocity = Vector3.ZERO
	game.oxygen = 100
	game.poison_timer = 0
	game.hurt_cooldown = 0
	await process_frame
	game.set_physics_process(true)
	await physics_frame
	var air_before: float = game.oxygen
	for frame in range(30):
		await physics_frame
	game.set_physics_process(false)
	_check(absf((air_before - game.oxygen) - 0.36) < 0.003, "Expanding the world does not increase normal breathing cost in real physics frames")

func _visible_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree() and game.camera.is_position_in_frustum(node.global_transform * node.get_aabb().get_center()):
		return true
	if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.instance_count > 0 and node.is_visible_in_tree():
		for index in range(node.multimesh.instance_count):
			if game.camera.is_position_in_frustum(node.global_transform * node.multimesh.get_instance_transform(index).origin):
				return true
	for child in node.get_children():
		if _visible_mesh(child):
			return true
	return false

func _inside_bounds(point: Vector3) -> bool:
	return point.x >= Ocean.X_MIN and point.x <= Ocean.X_MAX and point.z >= Ocean.Z_MIN and point.z <= Ocean.Z_MAX and point.y >= Ocean.Y_MIN and point.y <= Ocean.Y_MAX

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
