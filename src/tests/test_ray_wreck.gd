extends SceneTree
## Real wreck collision, rendered decorative shoals, and sand-ray lifecycle integration.
const Ocean = preload("res://scripts/ocean_config.gd")

class MemoryProgression extends "res://scripts/progression.gd":
	var saves: int = 0
	func load_game() -> void:
		pass
	func save_game() -> void:
		saves += 1

var game: Node
var memory: MemoryProgression
var rays: Node3D
var wreck: Node3D
var school: Node3D
var checks := 0
var failures := 0

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
	await physics_frame
	await process_frame
	game.start_dive(false, false)
	await physics_frame
	await process_frame
	rays = game.ray_habitat
	wreck = game.explorable_wreck
	school = wreck.get_node_or_null("WreckFishSchool") if wreck != null else null
	_check(rays != null and wreck != null and school != null, "The actual ocean integrates the sand-ray habitat, hollow wreck and internal school")
	if rays != null and wreck != null and school != null:
		var progress_before: Dictionary = memory._save_data().duplicate(true)
		_test_ray_initial_state()
		await _test_ray_detection_and_swimming()
		await _test_ray_wide_body_clearance()
		_test_wreck_routes_and_walls()
		await _test_school_geometry_and_rendering()
		await _test_harpoon_isolation_and_hull()
		_test_wreck_camera()
		await _test_pause_and_gm()
		_check(game.fish.size() == 151 and game.fish_population_count() == 151 and game.pickups.size() == 64, "Decorative rays and three hundred internal fish stay outside the 151 huntable fish and 64 pickups")
		_check(memory._save_data() == progress_before and memory.saves == 0 and game.cargo.is_empty(), "Exploring and firing through decorative animals neither changes inventory nor writes progress")
		_test_ray_lifecycle_reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver sand rays and hollow wreck (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_ray_initial_state() -> void:
	var terrace: Vector3 = Ocean.exploration_points(Ocean.site_index("pearl_atoll"))[1].position
	_check(rays.rays.size() == 6 and str(rays.get_meta("location_name", "")).contains("月光沙台"), "Exactly six decorative rays inhabit the sand outside Moonlight Sand Terrace")
	var grounded := true
	var articulated := true
	var isolated := true
	for item: Dictionary in rays.rays:
		var node: Node3D = item.node
		var home: Vector3 = item.home
		var distance := Vector2(home.x - terrace.x, home.z - terrace.z).length()
		grounded = grounded and distance >= 16.0 and distance < 48.0 and absf(home.y - Ocean.seabed_height(home.x, home.z)) < 0.01 and absf(node.position.y - home.y + 0.025) < 0.01 and item.state == "buried" and item.cover.visible and not item.dust.visible and rays.habitat_bounds.has_point(home)
		articulated = articulated and node.get_node_or_null("WingLeft") != null and node.get_node_or_null("WingRight") != null and node.get_node_or_null("Tail") != null and _mesh_count(node) >= 5
		isolated = isolated and not _has_collision(node) and bool(node.get_meta("decorative_only", false))
	_check(grounded, "Every ray starts sand-buried on the real seabed beyond the terrace, inside its habitat")
	_check(articulated, "All six actual ray models contain visible bodies, separate wings and tails")
	_check(isolated and bool(rays.get_meta("decorative_only", false)), "Decorative rays add no physical capture target or obstacle")
	_check(rays.ignored_bodies.has(game.player.get_rid()), "Ray visibility queries ignore the real diver collider")

func _test_ray_detection_and_swimming() -> void:
	var item: Dictionary = rays.rays[0]
	var home: Vector3 = item.home
	var viewer: Vector3 = home + Vector3(0, 3, 4)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	wall.position = (home + Vector3.UP * 0.28 + viewer) * 0.5
	wall.look_at(viewer)
	await physics_frame
	game.player.position = viewer
	game.player.velocity = Vector3.ZERO
	game._physics_process(1.0 / 60.0)
	_check(item.state == "buried", "A real wall blocks the nearby diver's line of sight and leaves the ray buried")
	wall.free()
	await physics_frame
	game._physics_process(1.0 / 60.0)
	_check(item.state == "rising" and item.dust.visible, "A nearby visible diver triggers emerging and an actual disturbed-sand burst through the game update")
	var first_pose := _ray_pose(item)
	for step in range(12):
		rays.advance(0.05, viewer)
	_check(item.node.position.y > home.y + 0.3 and item.cover.material_override.albedo_color.a < 0.90, "Emerging visibly lifts the body and fades its sand cover")
	_check(_ray_pose(item) != first_pose and absf(item.wing_left.rotation.z) > 0.02 and absf(item.wing_left.rotation.z + item.wing_right.rotation.z) < 0.001 and absf(item.tail.rotation.y) > 0.01, "The actual two wing joints flap oppositely while the separate tail sways")
	for step in range(14):
		rays.advance(0.05, viewer)
	_check(item.state == "fleeing" and item.node.position.distance_to(home) > 3.0, "The ray completes emerging and swims away from the nearby diver")
	var safe_ground := true
	var clear_rocks := true
	var bounded := true
	var saw_settling := false
	var far_viewer: Vector3 = home + Vector3(0, 30, 120)
	for step in range(850):
		rays.advance(0.05, far_viewer)
		for current: Dictionary in rays.rays:
			var point: Vector3 = current.node.position
			safe_ground = safe_ground and point.y >= Ocean.seabed_height(point.x, point.z) - 0.04
			bounded = bounded and rays.habitat_bounds.has_point(point) and point.is_finite()
			if current.state in ["rising", "fleeing"]:
				clear_rocks = clear_rocks and _sphere_clear(point + Vector3.UP * 0.35, 0.25)
		if item.state == "settling":
			saw_settling = true
	_check(safe_ground and clear_rocks, "During a complete escape the real ray bodies remain above terrain and out of solid rocks")
	_check(bounded, "Every ray stays finite and inside the actual sand habitat throughout its escape")
	_check(saw_settling and item.state == "buried" and item.node.position.distance_to(home) > 5.0 and item.cover.visible, "After the diver leaves, the ray settles into new sand and buries itself again")
	rays.reset()
	var snapshot := _ray_snapshot()
	rays.advance(2.0, viewer, false)
	_check(_ray_snapshot() == snapshot, "Inactive ray controllers freeze positions, states, joints, covers and dust completely")
	game.player.position = home + Vector3(0, 2, 7)
	Input.action_press("stealth")
	game._physics_process(1.0 / 60.0)
	Input.action_release("stealth")
	_check(item.state == "buried", "The real stealth input reduces how far away a diver startles sand rays")
	game._physics_process(1.0 / 60.0)
	_check(item.state == "rising", "The same visible approach without stealth startles the ray")

func _test_ray_wide_body_clearance() -> void:
	rays.reset()
	var item: Dictionary = rays.rays[0]
	var start: Vector3 = item.home + Vector3.UP * 2.3
	item.node.position = start
	item.heading = PI
	item.node.basis = Basis(Vector3.UP, PI)
	item.state = "fleeing"
	item.timer = 4.0
	item.velocity = Vector3(0, 0, 3.2)
	var wall := StaticBody3D.new()
	wall.position = start + Vector3(1.25, 0, 3.7)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 6.0, 5.0)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	_check(rays._clear_swim(start, start + Vector3(0, 0, 6)), "The side-wall regression leaves the ray's center line clear while blocking the full wing span")
	var penetrations := 0
	var wall_bounds := AABB(wall.position - box.size * 0.5, box.size)
	for step in range(2):
		rays.elapsed += 0.5
		rays._swim(item, start + Vector3(0, 0, -40), 0.5, false)
		rays._animate_fins(item, 1.0)
		for mesh: MeshInstance3D in item.node.find_children("*", "MeshInstance3D", true, false):
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				if wall_bounds.has_point(mesh.global_transform * vertex):
					penetrations += 1
	_check(penetrations == 0 and item.node.position.distance_to(start) > 0.05, "The moving ray avoids a narrow side wall with every actual body, wing and tail vertex")
	wall.free()
	await physics_frame
	var minimum_clearance := INF
	var lowest_sample := ""
	var outside_sample := ""
	var bounded := true
	for ray_index in range(rays.rays.size()):
		var current: Dictionary = rays.rays[ray_index]
		current.node.position = current.home + Vector3.UP * 2.3
		current.heading = float(ray_index) * 1.1
		current.node.basis = Basis(Vector3.UP, current.heading)
		current.state = "fleeing"
		current.timer = 4.0
		current.velocity = Vector3.FORWARD.rotated(Vector3.UP, current.heading) * 6.0
		for step in range(240):
			rays.elapsed += 0.05
			current.timer += 0.05
			var direction: Vector3 = (current.velocity as Vector3).normalized()
			rays._swim(current, current.node.position - direction * 12.0, 0.05, false)
			rays._animate_fins(current, 1.0)
			bounded = bounded and rays.habitat_bounds.has_point(current.node.position)
			if not rays.habitat_bounds.has_point(current.node.position) and outside_sample.is_empty():
				outside_sample = "ray %d at %s" % [ray_index, current.node.position]
			if step % 20 == 0:
				for mesh: MeshInstance3D in current.node.find_children("*", "MeshInstance3D", true, false):
					var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					for index in range(0, vertices.size(), 6):
						var world: Vector3 = mesh.global_transform * vertices[index]
						var clearance: float = world.y - Ocean.seabed_height(world.x, world.z)
						if clearance < minimum_clearance:
							minimum_clearance = clearance
							lowest_sample = "ray %d %s at %s" % [ray_index, mesh.name, world]
	_check(minimum_clearance >= -0.03 and bounded, "All six rays' animated body, wing and tail geometry stays above real seabed across twelve-second escape paths (minimum %.4f, %s, outside %s)" % [minimum_clearance, lowest_sample, outside_sample])
	rays.reset()

func _test_wreck_routes_and_walls() -> void:
	_check(bool(wreck.get_meta("hollow", false)) and wreck.get_meta("entrances", []).size() >= 5, "The distant wreck is a hollow structure with bow, stern, two side and upper entrances")
	var center: Vector3 = wreck.to_global(Vector3(0, 4.7, 0))
	var starts: Array[Vector3] = [Vector3(0, 4.7, -19), Vector3(0, 4.7, 19), Vector3(-9, 4.7, 0), Vector3(9, 4.7, 0), Vector3(0, 13, 0)]
	for index in range(starts.size()):
		var start: Vector3 = wreck.to_global(starts[index])
		_check(_sphere_clear(start, 0.65) and not game.player.test_move(Transform3D(Basis.IDENTITY, start), center - start), "The actual diver physics body can swim fully through wreck entrance %d into the hold" % index)
	var route: Array = wreck.get_meta("safe_swim_route", [])
	var clear_route: bool = route.size() >= 6
	for index in range(1, route.size()):
		clear_route = clear_route and not game.player.test_move(Transform3D(Basis.IDENTITY, route[index - 1]), route[index] - route[index - 1])
	_check(clear_route, "The real diver physics body traverses the internal bow-to-stern passage")
	var start: Vector3 = wreck.to_global(Vector3(0, 4.7, 7.5))
	var finish: Vector3 = wreck.to_global(Vector3(9, 4.7, 7.5))
	var collision := KinematicCollision3D.new()
	var blocked: bool = game.player.test_move(Transform3D(Basis.IDENTITY, start), finish - start, collision)
	_check(blocked and collision.get_collider() != null and str(collision.get_collider().name) == "HullPlankingCollision", "Intact hull planking remains a real wall beside the open entrances")
	for part: String in ["HullPlanking", "CurvedRibs", "DeckAndCabin"]:
		var body: Node = wreck.get_node_or_null(part + "Collision")
		var visual: MeshInstance3D = wreck.get_node_or_null(part)
		_check(body != null and visual != null and body.get_child(0).shape is ConcavePolygonShape3D and body.get_child(0).shape.backface_collision and body.get_child(0).shape.get_faces().size() == visual.mesh.get_faces().size(), "Visible wreck geometry and double-sided physical collision agree for " + part)

func _test_school_geometry_and_rendering() -> void:
	var batches: Array[MultiMeshInstance3D] = []
	var count := 0
	for child in school.get_children():
		if child is MultiMeshInstance3D:
			batches.append(child)
			count += child.multimesh.instance_count
	_check(count == 300 and count == int(school.get_meta("fish_count", 0)) and batches.size() == 4, "The wreck keeps three hundred fish in four species batches")
	var meshes: Dictionary = {}
	for batch: MultiMeshInstance3D in batches:
		meshes[batch.multimesh.mesh] = true
	_check(meshes.size() == 4 and batches.all(func(batch): return batch.material_override == batches[0].material_override), "Four distinct silhouettes and markings share one animated material")
	_check(not _has_collision(school) and bool(school.get_meta("decorative_only", false)), "The internal school adds no collider or huntable fish body")
	var bounds: AABB = school.get_meta("local_swim_bounds")
	var radius: float = school.get_meta("max_fish_radius")
	var initial_positions: Array[Vector3] = []
	for time: float in [0.0, 31.0, 93.25]:
		school.animate(time, wreck.to_global(Vector3(0, 4.7, 0)))
		await process_frame
		await RenderingServer.frame_post_draw
		var inside := true
		var clear := true
		var positions: Array[Vector3] = []
		for batch: MultiMeshInstance3D in batches:
			for index in range(batch.multimesh.instance_count):
				var world: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(index).origin
				positions.append(world)
				inside = inside and bounds.grow(-radius).has_point(school.to_local(world))
				clear = clear and _sphere_clear(world, radius)
		_check(inside and clear, "Every rendered decorative fish and its complete body stay within the hold and clear of actual hull/terrain at t=%.2f" % time)
		if initial_positions.is_empty():
			initial_positions = positions
		else:
			_check(positions != initial_positions, "The real MultiMesh transforms swim as the external school clock advances to %.2f" % time)
	game.player.position = wreck.to_global(Vector3(0, 4.7, 7))
	game.yaw = wreck.rotation.y
	game.pitch = 0
	game._update_swim_camera()
	school.animate(game.clock, game.player.position)
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_fish := 0
	for batch: MultiMeshInstance3D in batches:
		if batch.is_visible_in_tree():
			for index in range(batch.multimesh.instance_count):
				if game.camera.is_position_in_frustum(batch.global_transform * batch.multimesh.get_instance_transform(index).origin):
					visible_fish += 1
	var frame: Image = root.get_texture().get_image()
	_check(visible_fish >= 80 and not frame.is_empty(), "A real GPU frame from inside the wreck contains the visible, densely scattered small-fish school")
	_check(bool(school.get_meta("external_clock_only", false)) and not str(batches[0].material_override.shader.code).contains("TIME"), "Fish transforms and tail animation use the paused game clock instead of an independent shader timer")

func _test_harpoon_isolation_and_hull() -> void:
	var originals: Array[Dictionary] = []
	for item: Dictionary in game.fish:
		originals.append({"data":item.duplicate(), "transform":item.node.transform, "visible":item.node.visible})
		item.alive = false
		item.node.visible = false
	game.cargo.clear()
	game._clear_projectiles()
	game.player.position = wreck.to_global(Vector3(0, 4.7, 9))
	game.player.velocity = Vector3.ZERO
	game.yaw = wreck.rotation.y
	game.camera.position = game.player.position
	game.camera.look_at(wreck.to_global(Vector3(0, 4.7, -9)))
	game.shot_cooldown = 0
	game.shoot()
	var launched: bool = game.projectiles.size() == 1
	var travel := 0.0
	for step in range(55):
		if not game.projectiles.is_empty():
			travel = maxf(travel, float(game.projectiles[0].distance))
		game._update_projectiles(0.02)
	_check(launched and travel > 12.0 and game.projectiles.is_empty() and game.cargo.is_empty(), "A real launched hook crosses the decorative school without catching fish or stopping on a hidden collider")
	var target: Dictionary = game.fish[0]
	target.alive = true
	target.kind = 0
	target.hp = 1
	target.armor = false
	target.node.position = wreck.to_global(Vector3(8, 4.7, 7.5))
	target.node.basis = Basis.IDENTITY
	target.previous_position = target.node.position
	game.player.position = wreck.to_global(Vector3(0, 4.7, 7.5))
	var direction: Vector3 = (target.node.position - game.player.position).normalized()
	game.yaw = atan2(-direction.x, -direction.z)
	game.camera.position = game.player.position
	game.camera.look_at(target.node.position)
	game.shot_cooldown = 0
	var effects_before: int = game.effects.size()
	game.shoot()
	launched = game.projectiles.size() == 1
	for step in range(35):
		game._update_projectiles(0.02)
	var impact_in_wall := false
	for index in range(effects_before, game.effects.size()):
		var local: Vector3 = wreck.to_local(game.effects[index].node.position)
		impact_in_wall = impact_in_wall or (local.x > 4 and local.x < 6.5 and local.z > 6.0 and local.z < 9.0)
	_check(launched and game.projectiles.is_empty() and impact_in_wall and target.hp == 1 and target.alive and game.cargo.is_empty(), "A real flying hook strikes intact hull planking and cannot capture the ordinary fish behind it")
	for index in range(game.fish.size()):
		var item: Dictionary = game.fish[index]
		item.clear()
		item.merge(originals[index].data)
		item.node.transform = originals[index].transform
		item.node.visible = originals[index].visible
	await process_frame

func _test_wreck_camera() -> void:
	var clear := true
	var unobstructed := true
	var contained := true
	for point: Vector3 in [Vector3(0,4.7,-12),Vector3(0,4.7,0),Vector3(0,4.7,12),Vector3(4.1,4.7,6),Vector3(-4.1,4.7,6)]:
		game.player.position = wreck.to_global(point)
		for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			game.yaw = wreck.rotation.y + angle
			game.pitch = 0
			game._update_swim_camera()
			clear = clear and _sphere_clear(game.camera.position, 0.27) and game.camera.position.is_finite()
			var query := PhysicsRayQueryParameters3D.create(game.player.position + Vector3.UP * 0.25, game.camera.position, 1, [game.player.get_rid()])
			unobstructed = unobstructed and game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
			contained = contained and game.camera.position.distance_to(game.player.position) < 5.0
	_check(clear and unobstructed and contained, "The actual following camera keeps its volume and sightline out of hull walls across internal passages and four viewing directions")

func _test_pause_and_gm() -> void:
	rays.advance(0.02, rays.rays[0].home + Vector3(0, 3, 4))
	game.player.position = wreck.to_global(Vector3(0, 4.7, 0))
	game.player.velocity = Vector3.ZERO
	game._physics_process(0.02)
	game.toggle_pause()
	var ray_before := _ray_snapshot()
	var school_before := _school_snapshot()
	var clock_before: float = game.clock
	await _physics_frames(8)
	_check(game.state == "paused" and _ray_snapshot() == ray_before and _school_snapshot() == school_before and game.clock == clock_before, "The real pause state freezes ray states, all visible joints, fish instances and tail animation")
	game.toggle_pause()
	game.open_gm_menu()
	ray_before = _ray_snapshot()
	school_before = _school_snapshot()
	await _physics_frames(8)
	_check(game.gm_menu_open and game.state == "paused" and _ray_snapshot() == ray_before and _school_snapshot() == school_before, "An open GM menu freezes both decorative animal systems in actual physics frames")
	game.gm_select_dive_site(game.Ocean.site_index("pearl_atoll"), true)
	_check(game.state == "dive" and not game.gm_menu_open and _ray_snapshot() == ray_before, "GM teleport within a dive preserves the existing ray state instead of resetting the habitat")

func _test_ray_lifecycle_reset() -> void:
	game.player.position = wreck.to_global(Vector3(4.1, 4.7, 7.5))
	game.yaw = wreck.rotation.y + PI * 0.5
	game.pitch = 0
	game._update_swim_camera()
	var rig: Node3D = game.player.get_child(0)
	_check(not rig.visible, "A close hull wall actually shortens the following camera and clears the diver from the cramped view")
	var before := _ray_snapshot()
	var inventory_before: Dictionary = memory.inventory.duplicate(true)
	game.finish_dive()
	_check(game.state == "dock" and _ray_snapshot() == before and memory.inventory == inventory_before, "Returning from the dive preserves ray state and adds no decorative animal to inventory")
	game.open_restaurant()
	game.return_to_dock()
	_check(game.state == "dock" and _ray_snapshot() == before, "Visiting the restaurant and returning to the dock also preserve the ray habitat")
	game.start_dive(true, false)
	_check(_all_rays_reset(), "A new dive resets all six rays to their original sand-buried homes")
	var visible_at_start: bool = rig.is_visible_in_tree()
	game._update_entry(0.75)
	_check(visible_at_start and game.entry_active and rig.is_visible_in_tree(), "Boat entry restores the actual diver model after the previous wreck camera hid it")
	game._update_entry(3.2)
	game.player.position = wreck.to_global(Vector3(4.1, 4.7, 7.5))
	game.yaw = wreck.rotation.y + PI * 0.5
	game.pitch = 0
	game._update_swim_camera()
	var hidden_before_gm: bool = not rig.visible
	game.open_gm_menu()
	game.gm_select_dive_site(game.Ocean.site_index("merchant_wreck"), false)
	visible_at_start = rig.is_visible_in_tree()
	game._update_entry(0.75)
	_check(hidden_before_gm and visible_at_start and game.entry_active and rig.is_visible_in_tree(), "GM boat entry also restores the real diver throughout its jump after a cramped wreck view")
	game._update_entry(3.2)
	var first: Dictionary = rays.rays[0]
	rays.advance(0.02, first.home + Vector3(0, 3, 4))
	_check(first.state == "rising", "A newly started dive can startle the reset ray again")
	game.toggle_pause()
	game.request_new_game()
	game.confirm_new_game()
	_check(game.state == "dock" and _all_rays_reset() and memory.inventory_total() == 0, "Confirmed new game resets decorative ray state together with the ordinary game")
	var save_text := JSON.stringify(memory._save_data()).to_lower()
	_check(not save_text.contains("sandray") and not save_text.contains("wreckfish") and not save_text.contains("ray_habitat"), "Decorative habitat and internal-school state never enter the persistent save format")

func _all_rays_reset() -> bool:
	if rays.elapsed != 0:
		return false
	for item: Dictionary in rays.rays:
		if item.state != "buried" or item.node.position.distance_to(item.home + Vector3.DOWN * 0.025) > 0.001 or item.velocity != Vector3.ZERO or not item.cover.visible or item.dust.visible:
			return false
	return true

func _ray_snapshot() -> Dictionary:
	var snapshot: Dictionary = {"elapsed":rays.elapsed, "items":[]}
	for item: Dictionary in rays.rays:
		snapshot.items.append([item.node.transform, item.rest, item.state, item.velocity, item.timer, item.dust_age, item.cover.transform, item.cover.visible, item.cover.material_override.albedo_color, item.dust.visible, _ray_pose(item)])
	return snapshot

func _ray_pose(item: Dictionary) -> Array:
	return [item.wing_left.transform, item.wing_right.transform, item.tail.transform]

func _school_snapshot() -> Array:
	var snapshot: Array = []
	for child in school.get_children():
		if child is MultiMeshInstance3D:
			snapshot.append(child.material_override.get_shader_parameter("school_clock"))
			for index in range(child.multimesh.instance_count):
				snapshot.append(child.multimesh.get_instance_transform(index))
	return snapshot

func _physics_frames(count: int) -> void:
	game.set_physics_process(true)
	await physics_frame
	for step in range(count):
		await physics_frame
	game.set_physics_process(false)

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _has_collision(child):
			return true
	return false

func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count
