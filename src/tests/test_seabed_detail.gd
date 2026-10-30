extends SceneTree
## Real renderer, batched decoration, terrain collision and existing interactions.
const Ocean = preload("res://scripts/ocean_config.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const Life = preload("res://scripts/reef_life.gd")

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
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: Seabed detail verification requires a real rendering backend.")
		quit(1)
		return
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
	await process_frame
	await RenderingServer.frame_post_draw
	var progress_before: Dictionary = memory._save_data().duplicate(true)
	var geology: Node3D = game.ocean_root.get_node_or_null("OceanGeology")
	var life: Node3D = game.ocean_root.get_node_or_null("ReefLife")
	_check(geology != null and life != null, "The actual ocean contains geological detail and decorative reef life")
	if geology != null and life != null:
		_test_batches_and_grounding(geology, life)
		await _test_deterministic_builds(geology, life)
		_test_terrain()
		await _test_sites_and_rendering(geology, life)
		_test_pearl_interaction()
	_check(game.fish.size() == 171 and game.fish_population_count() == 171, "Decorative seabed life does not add ordinary fish or increase the catchable population")
	_check(memory._save_data() == progress_before and memory.saves == 0, "Detail inspection and pearl pickup do not mutate or save durable progress")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.free()
	await process_frame
	print("%s: Tide Diver seabed detail (%d checks)." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_batches_and_grounding(geology: Node3D, life: Node3D) -> void:
	var stone_batches: Array[MultiMeshInstance3D] = _batches(geology)
	var life_batches: Array[MultiMeshInstance3D] = _batches(life)
	var stone_roots: PackedVector3Array = geology.get_meta("ground_roots", PackedVector3Array())
	var life_roots: PackedVector3Array = life.get_meta("root_positions", PackedVector3Array())
	_check(stone_batches.size() == int(geology.get_meta("draw_batches", 0)) and stone_batches.size() > 0 and _instance_count(stone_batches) == stone_roots.size() and stone_roots.size() == int(geology.get_meta("detail_count", 0)), "Actual stone instances and batch counts match the recorded ground roots")
	_check(life_batches.size() == int(life.get_meta("draw_batches", 0)) and _instance_count(life_batches) == life_roots.size() and life_roots.size() == int(life.get_meta("instance_count", 0)) and int(life.get_meta("site_count", 0)) == 6, "Actual reef-life batches match all recorded instances across six dive sites")
	var meshes: Dictionary = {}
	var stone_meshes: Dictionary = {}
	var life_meshes: Dictionary = {}
	var stone_materials: Dictionary = {}
	var life_materials: Dictionary = {}
	var clipped: bool = true
	for batch in stone_batches + life_batches:
		clipped = clipped and batch.visibility_range_end > 0 and batch.visibility_range_end <= 120 and batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if batch.multimesh == null or batch.multimesh.mesh == null or batch.material_override == null:
			clipped = false
			continue
		var id: int = batch.multimesh.mesh.get_instance_id()
		meshes[id] = batch.multimesh.mesh
		if batch in stone_batches:
			stone_meshes[id] = true
			stone_materials[batch.material_override.get_instance_id()] = true
		else:
			life_meshes[id] = true
			life_materials[batch.material_override.get_instance_id()] = true
	_check(clipped, "Decorative batches have finite near-distance clipping and do not cast hundreds of small shadows")
	_check(stone_meshes.size() <= 4 and stone_batches.size() > stone_meshes.size() and life_meshes.size() == 4 and life_materials.size() == 1 and stone_materials.size() == 1, "Repeated sites reuse a small set of shared meshes and materials")
	var coral: Node3D = game.ocean_root.get_node("OuterOcean/amber_reef/CoralGarden")
	_check(stone_batches.size() + life_batches.size() + _batches(coral).size() <= 64, "Stone, reef life and the large coral garden stay within a bounded sixty-four-batch detail budget")
	_check(_collision_nodes(geology) == 0 and _collision_nodes(life) == 0 and _collision_nodes(coral) == 0, "New stones, seabed organisms and coral remain decorative and add no collision objects")
	var stones_grounded: bool = true
	var root_index: int = 0
	for batch in stone_batches:
		for index in range(batch.multimesh.instance_count):
			var world: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(index).origin
			if root_index >= stone_roots.size():
				stones_grounded = false
				continue
			var anchor: Vector3 = stone_roots[root_index]
			stones_grounded = stones_grounded and absf(anchor.y - Ocean.seabed_height(anchor.x, anchor.z)) < 0.002 and world.distance_to(anchor) < 0.30
			root_index += 1
	_check(stones_grounded and root_index == stone_roots.size(), "Every actual pebble is anchored at the real seabed rather than floating away from its recorded root")
	var life_grounded: bool = true
	root_index = 0
	for batch in life_batches:
		for index in range(batch.multimesh.instance_count):
			var world: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(index).origin
			life_grounded = life_grounded and absf(world.y - Ocean.seabed_height(world.x, world.z)) < 0.003
			if root_index < life_roots.size():
				life_grounded = life_grounded and world.distance_to(life.to_global(life_roots[root_index])) < 0.003
			else:
				life_grounded = false
			root_index += 1
	_check(life_grounded and root_index == life_roots.size(), "Every organism's actual instance root matches its metadata and the world seabed")
	var forms_present: bool = true
	for site in range(Ocean.DIVE_SITES.size()):
		var region: Node = life.get_node_or_null("Site%d" % site)
		for form in ["Seagrass", "Scallop", "SeaStar", "TubeSponge"]:
			forms_present = forms_present and region != null and region.get_node_or_null(form) is MultiMeshInstance3D
	_check(forms_present, "Every dive site contains grass, scallops, sea stars and tube sponges")
	var shell: Mesh = Life.shell_valve_mesh()
	meshes[shell.get_instance_id()] = shell
	var rock: Mesh = Geology.rock_mesh(0)
	meshes[rock.get_instance_id()] = rock
	var sound: bool = true
	for mesh: Mesh in meshes.values():
		sound = sound and _sound_mesh(mesh)
	_check(sound, "Shared stone, organism and shell meshes contain finite, substantial nondegenerate geometry with usable normals")

func _test_deterministic_builds(geology: Node3D, life: Node3D) -> void:
	var repeated := Node3D.new()
	repeated.visible = false
	root.add_child(repeated)
	Geology.decorate(repeated)
	var repeated_life: Node3D = Life.build(repeated)
	await process_frame
	await RenderingServer.frame_post_draw
	var repeated_stones: Node3D = repeated.get_node("OceanGeology")
	_check(geology.get_meta("ground_roots") == repeated_stones.get_meta("ground_roots") and _batch_signature(geology) == _batch_signature(repeated_stones), "A second independent geological build reproduces actual positions, colors and shared mesh references")
	_check(life.get_meta("root_positions") == repeated_life.get_meta("root_positions") and _batch_signature(life) == _batch_signature(repeated_life), "A second independent reef-life build reproduces all actual instance transforms and colors")
	repeated.free()

func _test_terrain() -> void:
	var terrain: Node3D = game.ocean_root.get_node("NaturalSeabed")
	var count: int = 0
	var same_surface: bool = true
	var materials: Dictionary = {}
	for child in terrain.get_children():
		if not child is MeshInstance3D:
			continue
		count += 1
		var body: StaticBody3D = child.get_node_or_null("TerrainCollision")
		var point: Vector3 = child.to_global(Vector3(83.25, 0, 117.5))
		var hit: Dictionary = _terrain_hit(point.x, point.z)
		same_surface = same_surface and body != null and not hit.is_empty() and hit.collider == body and absf(hit.position.y - Ocean.seabed_height(point.x, point.z)) < 0.03
		if child.material_override != null:
			materials[child.material_override.get_instance_id()] = child.material_override
	_check(count == 49 and same_surface, "All forty-nine original terrain collision chunks still match the shared height source at off-grid ray samples")
	_check(materials.size() == 1 and materials.values()[0] is ShaderMaterial and materials.values()[0] == Geology.sand_material(), "The original terrain chunks share the new sand shader without replacing their geometry")

func _test_sites_and_rendering(geology: Node3D, life: Node3D) -> void:
	for site in range(Ocean.DIVE_SITES.size()):
		game.open_gm_menu()
		game.gm_select_dive_site(site, true)
		var forward := Vector3(-sin(game.yaw), 0, -cos(game.yaw))
		var collision := KinematicCollision3D.new()
		_check(game.entry_site_index == site and _sphere_clear(game.player.position, 0.65) and not game.player.test_move(Transform3D(Basis.IDENTITY, game.player.position), forward * 5, collision), "Existing GM arrival and its forward swimming approach remain open at site %d" % site)
		var stone: MultiMeshInstance3D = geology.get_node_or_null("Site%dPebbles0" % site)
		var organism: MultiMeshInstance3D = life.get_node_or_null("Site%d/Seagrass" % site)
		var rendered: bool = stone != null and organism != null
		for batch: MultiMeshInstance3D in [stone, organism]:
			if batch == null or batch.multimesh == null or batch.multimesh.instance_count == 0:
				rendered = false
				continue
			var target: Vector3 = batch.global_transform * batch.multimesh.get_instance_transform(0).origin + Vector3.UP * 0.20
			game.camera.position = target + Vector3(6, 4, 8)
			game.camera.look_at(target, Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			rendered = rendered and batch.is_visible_in_tree() and game.camera.is_position_in_frustum(target) and game.camera.global_position.distance_to(target) < batch.visibility_range_end and not frame.is_empty()
		_check(rendered, "Actual GPU frames render the site's grounded stone and living-detail batches at site %d" % site)

func _test_pearl_interaction() -> void:
	var pearl: Dictionary = {}
	for item in game.pickups:
		if item.kind == "pearl" and item.active:
			pearl = item
			break
	_check(not pearl.is_empty(), "Existing pearl pickups remain present alongside decorative shells")
	if pearl.is_empty():
		return
	game.cargo.clear()
	var pickup_count: int = game.pickups.size()
	game.player.position = pearl.node.position + Vector3.UP * 0.5
	game.interact()
	_check(game.cargo.size() == 1 and game.cargo[0].id == "pearl" and not pearl.active and not pearl.node.visible and game.pickups.size() == pickup_count, "The updated pearl art retains the existing single-pickup cargo and consumed-state behavior")
	game.interact()
	_check(game.cargo.size() == 1 and game.pickups.size() == pickup_count, "Decorative seabed shells cannot duplicate a consumed pearl or create extra pickup records")

func _sound_mesh(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var size: Vector3 = mesh.get_aabb().size
	if not size.is_finite() or minf(size.x, minf(size.y, size.z)) < 0.02:
		return false
	var good: int = 0
	var total: int = 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if vertices.is_empty() or normals.size() != vertices.size():
			return false
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for triangle in range(0, count - 2, 3):
			var a: int = indices[triangle] if not indices.is_empty() else triangle
			var b: int = indices[triangle + 1] if not indices.is_empty() else triangle + 1
			var c: int = indices[triangle + 2] if not indices.is_empty() else triangle + 2
			if not vertices[a].is_finite() or not vertices[b].is_finite() or not vertices[c].is_finite():
				return false
			total += 1
			if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() > 0.0000000001:
				if not normals[a].is_finite() or not normals[b].is_finite() or not normals[c].is_finite() or minf(normals[a].length_squared(), minf(normals[b].length_squared(), normals[c].length_squared())) < 0.5:
					return false
				good += 1
	return good >= 24 and float(good) / maxf(total, 1) >= 0.85

func _batches(node: Node) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	if node is MultiMeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_batches(child))
	return result

func _instance_count(batches: Array[MultiMeshInstance3D]) -> int:
	var count: int = 0
	for batch in batches:
		count += batch.multimesh.instance_count if batch.multimesh != null else 0
	return count

func _batch_signature(node: Node3D) -> Dictionary:
	var signature: Dictionary = {}
	for batch in _batches(node):
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for index in range(batch.multimesh.instance_count):
			transforms.append(batch.multimesh.get_instance_transform(index))
			colors.append(batch.multimesh.get_instance_color(index))
		signature[str(node.get_path_to(batch))] = {"mesh":batch.multimesh.mesh.get_instance_id(), "transforms":transforms, "colors":colors}
	return signature

func _collision_nodes(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _collision_nodes(child)
	return count

func _terrain_hit(x: float, z: float) -> Dictionary:
	var excluded: Array[RID] = [game.player.get_rid()]
	for attempt in range(32):
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, -2, z), Vector3(x, -130, z), 1, excluded)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider.name == "TerrainCollision":
			return hit
		excluded.append(hit.collider.get_rid())
	return {}

func _sphere_clear(point: Vector3, radius: float) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
