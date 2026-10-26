extends SceneTree
## Real ocean scenery integration, using memory progress and physical-world queries.
const Ocean = preload("res://scripts/ocean_config.gd")

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
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	_check(game.fish.size() == 167 and game.fish_population_count() == 167, "Ocean scenery leaves the ordinary catchable population at 167")
	var storm: Node3D = game.storm_school
	_check(storm != null and storm.global_position == Vector3(-45, -20, 292), "The fish storm is located at the southern spires")
	if storm != null:
		_test_storm(storm)
	var garden: Node3D = game.ocean_root.get_node_or_null("OuterOcean/amber_reef/CoralGarden")
	_check(garden != null, "The actual amber-reef landmark contains the coral garden")
	if garden != null:
		_test_coral(garden)
	_check(memory._save_data() == progress_before and memory.saves == 0, "Scenery, animation, pause and the test shot do not change or save player progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver ocean features (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_storm(storm: Node3D) -> void:
	var visual: MultiMeshInstance3D = storm.get_child(0) as MultiMeshInstance3D if storm.get_child_count() > 0 else null
	_check(storm.get_child_count() == 1 and visual != null, "The storm uses one actual MultiMesh child instead of individual fish nodes")
	if visual == null:
		return
	var batch: MultiMesh = visual.multimesh
	_check(batch != null and batch.instance_count == 420 and batch.mesh != null and batch.mesh.get_surface_count() > 0, "All 420 visual fish share a populated mesh in one batch")
	if batch == null or batch.mesh == null:
		return
	_check(_collision_nodes(storm) == 0, "The decorative fish storm adds no collision bodies or shapes")
	_check(visual.visibility_range_end > 0 and visual.visibility_range_end <= 180, "The visual fish batch has a finite viewing distance")
	_test_storm_geometry(storm, visual)
	game.player.position = storm.global_position + Vector3(0, 0, 25)
	game._physics_process(0.2)
	var material: ShaderMaterial = visual.material_override as ShaderMaterial
	_check(storm.visible and material != null and absf(storm.rotation.y) > 0, "Approaching the storm displays the rotating batch with its swim shader")
	game.player.position = storm.global_position + Vector3(0, 0, 190)
	game._physics_process(0.2)
	_check(not storm.visible, "The storm hides when the diver leaves its viewing distance")
	game.player.position = storm.global_position + Vector3(0, 0, 25)
	game._physics_process(0.2)
	_check(storm.visible, "The same storm becomes visible again when the diver returns")
	if material != null:
		game.toggle_pause()
		var rotation_before: Vector3 = storm.rotation
		var swim_before: float = float(material.get_shader_parameter("swim_clock"))
		var clock_before: float = game.clock
		game._physics_process(5.0)
		_check(game.state == "paused" and storm.rotation == rotation_before and float(material.get_shader_parameter("swim_clock")) == swim_before and game.clock == clock_before, "Actual pause freezes storm rotation, shader swimming and the world clock")
		game.toggle_pause()
		game._physics_process(0.2)
		_check(storm.rotation != rotation_before and float(material.get_shader_parameter("swim_clock")) > swim_before, "Resuming play advances the existing storm and swim shader")
	var independent: bool = true
	for item in game.fish:
		independent = independent and item.node != storm and not storm.is_ancestor_of(item.node)
		item.alive = false
	game.player.position = storm.global_position
	game.camera.position = game.player.position
	var target_point: Vector3 = visual.global_transform * batch.get_instance_transform(0).origin
	game.camera.look_at(target_point, Vector3.UP)
	game.shot_cooldown = 0
	game.shoot()
	_check(game.projectiles.size() == 1, "Shooting into the decorative vortex launches a real flying hook")
	for frame in range(50):
		game._update_projectiles(0.02)
	_check(independent and game.fish.size() == 167 and game.projectiles.is_empty() and game.target_fish().is_empty() and game.cargo.is_empty() and memory.inventory_total() == 0, "A physical hook crossing the decorative vortex cannot catch or duplicate it into cargo or inventory")

func _test_storm_geometry(storm: Node3D, visual: MultiMeshInstance3D) -> void:
	var mesh: ArrayMesh = visual.multimesh.mesh as ArrayMesh
	if mesh == null:
		_check(false, "Storm geometry exposes its actual shared mesh for volume verification")
		return
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds: AABB = mesh.get_aabb()
	var mesh_radius: float = 0
	for corner in range(8):
		mesh_radius = maxf(mesh_radius, bounds.get_endpoint(corner).length())
	var clear: bool = true
	var minimum_core: float = INF
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		storm.animate(angle / 0.24, storm.position)
		for index in range(visual.multimesh.instance_count):
			var transform: Transform3D = visual.global_transform * visual.multimesh.get_instance_transform(index)
			var scale: Vector3 = transform.basis.get_scale().abs()
			var maximum_scale: float = maxf(scale.x, maxf(scale.y, scale.z))
			# Include the shader's maximum tail displacement in the queried volume.
			clear = clear and _sphere_clear(transform.origin, (mesh_radius + 0.10) * maximum_scale)
			for vertex: Vector3 in vertices:
				var point: Vector3 = transform * vertex - storm.global_position
				minimum_core = minf(minimum_core, Vector2(point.x, point.z).length() - 0.10 * maximum_scale)
	_check(clear, "Every fish volume in the whole storm clears actual terrain and rocks at three rotation angles")
	_check(minimum_core > 8.0, "The rendered fish ring leaves a central opening wider than an eight-metre radius")
	var collision := KinematicCollision3D.new()
	var start := Transform3D(Basis.IDENTITY, storm.global_position + Vector3(0, 0, -8))
	_check(not game.player.test_move(start, Vector3(0, 0, 16), collision), "The actual diver collider can swim through the storm's central opening")

func _test_coral(garden: Node3D) -> void:
	var positions: PackedVector3Array = garden.get_meta("patch_positions", PackedVector3Array())
	var forms: PackedStringArray = garden.get_meta("forms", PackedStringArray())
	_check(int(garden.get_meta("patch_count", 0)) == 150 and positions.size() == 150, "The actual garden records all 150 coral patches")
	_check(garden.get_meta("footprint", Rect2()) == Rect2(-45, -43.5, 90, 75) and float(garden.get_meta("channel_width", 0)) == 7.0, "Garden metadata preserves the broad footprint and open sand lane")
	var unmatched: Array[Vector3] = []
	unmatched.assign(positions)
	var batches: int = 0
	var instance_count: int = 0
	var mesh_ids: Dictionary = {}
	var actual_forms: Dictionary = {}
	var aligned: bool = true
	var metadata_matches: bool = true
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for child in garden.get_children():
		if not child is MultiMeshInstance3D:
			continue
		batches += 1
		actual_forms[str(child.name)] = true
		var batch: MultiMesh = child.multimesh
		if batch == null or batch.mesh == null or batch.instance_count == 0:
			metadata_matches = false
			continue
		mesh_ids[batch.mesh.get_instance_id()] = true
		instance_count += batch.instance_count
		for index in range(batch.instance_count):
			var local_point: Vector3 = batch.get_instance_transform(index).origin
			var world: Vector3 = child.global_transform * local_point
			aligned = aligned and absf(world.y - Ocean.seabed_height(world.x, world.z)) < 0.002
			minimum.x = minf(minimum.x, local_point.x)
			minimum.y = minf(minimum.y, local_point.z)
			maximum.x = maxf(maximum.x, local_point.x)
			maximum.y = maxf(maximum.y, local_point.z)
			var found: bool = false
			for pending in range(unmatched.size()):
				if unmatched[pending].distance_to(local_point) < 0.001:
					unmatched.remove_at(pending)
					found = true
					break
			metadata_matches = metadata_matches and found
	_check(batches == 4 and garden.get_child_count() == 4 and mesh_ids.size() == 4 and forms.size() == 4 and actual_forms.size() == 4, "Four coral forms each use a distinct shared mesh in exactly four drawing batches")
	var named_forms: bool = true
	for form in ["Staghorn", "TableCoral", "SeaFan", "BrainCoral"]:
		named_forms = named_forms and form in forms and actual_forms.has(form)
	_check(named_forms and instance_count == positions.size() and instance_count > 100 and metadata_matches and unmatched.is_empty(), "Rendered batches match all recorded patches and contain all four named coral forms")
	_check(aligned, "Every actual coral instance root meets the real world seabed height")
	_check(maximum.x - minimum.x > 80 and maximum.y - minimum.y > 65, "The real coral placement spans more than eighty by sixty-five metres")
	_check(_collision_nodes(garden) == 0, "The visual coral garden adds no collision objects or shapes")

func _collision_nodes(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _collision_nodes(child)
	return count

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
