extends RefCounted
## Small, traversable side landmarks. All geometry is shared and decorative.
const Ocean = preload("res://scripts/ocean_config.gd")
const Geology = preload("res://scripts/ocean_geology.gd")
const Life = preload("res://scripts/reef_life.gd")
const Coral = preload("res://scripts/coral_garden.gd")
const DRAW_DISTANCE := 180.0
const CHANNEL_WIDTH := 4.0
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "DiveExpansions"
	parent.add_child(root)
	var origin: Vector3 = parent.global_position if parent.is_inside_tree() else parent.position
	var positions := PackedVector3Array()
	var all_bounds := AABB()
	var initialized := false
	var batch_count := 0
	var instance_count := 0
	var areas: Array = Ocean.exploration_areas()
	for site_index in range(areas.size()):
		var area: Dictionary = areas[site_index]
		var center: Vector3 = area.center
		center.y = Ocean.seabed_height(center.x, center.z)
		var site := Node3D.new()
		site.name = "Site%d" % site_index
		site.position = center - origin
		root.add_child(site)
		var configs: Array = Ocean.exploration_points(site_index)
		for point_index in range(configs.size()):
			var config: Dictionary = configs[point_index]
			var point: Vector3 = config.position
			var region := Node3D.new()
			region.name = "Point%d" % point_index
			region.position = point - center
			var outward := Vector3(point.x - center.x, 0, point.z - center.z).normalized()
			region.rotation.y = atan2(outward.x, outward.z)
			site.add_child(region)
			region.set_meta("exploration_name", config.name)
			region.set_meta("world_position", point)
			region.set_meta("channel_width", CHANNEL_WIDTH)
			var state: Dictionary = {"point": point, "frame": region.basis, "groups": {}, "bounds": AABB(), "initialized": false, "count": 0}
			var random := RandomNumberGenerator.new()
			random.seed = 97121 + site_index * 107 + point_index * 19
			_populate(state, site_index, point_index, random)
			for kind: String in state.groups:
				var entries: Array = state.groups[kind]
				var batch := MultiMesh.new()
				batch.transform_format = MultiMesh.TRANSFORM_3D
				batch.use_colors = true
				batch.mesh = _mesh(kind)
				batch.instance_count = entries.size()
				for index in range(entries.size()):
					batch.set_instance_transform(index, entries[index].transform)
					batch.set_instance_color(index, entries[index].color)
				var visual := MultiMeshInstance3D.new()
				visual.name = kind
				visual.multimesh = batch
				visual.material_override = _material(kind)
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				visual.visibility_range_end = DRAW_DISTANCE
				visual.visibility_range_end_margin = 18.0
				region.add_child(visual)
				batch_count += 1
			var bounds: AABB = state.bounds
			region.set_meta("world_bounds", bounds)
			region.set_meta("draw_batches", state.groups.size())
			region.set_meta("instance_count", state.count)
			all_bounds = all_bounds.merge(bounds) if initialized else bounds
			initialized = true
			instance_count += int(state.count)
			positions.append(point)
	root.set_meta("site_count", areas.size())
	root.set_meta("side_area_count", positions.size())
	root.set_meta("point_positions", positions)
	root.set_meta("world_bounds", all_bounds)
	root.set_meta("draw_batches", batch_count)
	root.set_meta("instance_count", instance_count)
	root.set_meta("channel_width", CHANNEL_WIDTH)
	root.set_meta("decorative_only", true)
	root.set_meta("no_collision", true)
	return root

static func _populate(s: Dictionary, site: int, point: int, random: RandomNumberGenerator) -> void:
	# Coordinates run along the route from the main area, with open sand at x=0.
	match site * 2 + point:
		0: # Sea grass follows the slope in separate, low banks.
			_scatter(s, "Seagrass", 28, random, Vector3(0.9, 1.15, 0.9), Color("9fbe95"))
			_rocks(s, 7, random, Vector3(2.2, 0.8, 2.0), Color("c3c5aa"))
			_scatter(s, "SeaStar", 4, random, Vector3.ONE * 0.7, Color("dbc1a1"))
		1: # A shallow reef studded with shells, rather than another reef wall.
			_rocks(s, 8, random, Vector3(2.5, 0.7, 2.0), Color("c7c4a9"))
			_scatter(s, "Scallop", 23, random, Vector3.ONE * 0.8, Color("e1d0b9"))
			_scatter(s, "Seagrass", 8, random, Vector3.ONE * 0.7, Color("9cb68a"))
		2: # A stepped fault on one bank, broken stone opposite.
			for i in range(6):
				var h: float = 2.7 + sin(float(i) * 0.7) * 1.0
				_rock(s, Vector3(-7.5 - float(i % 2) * 1.0, 0, -9.0 + i * 3.5), Vector3(2.2, h, 2.5), 0.2 * i, Color("a6b5aa"))
				_put(s, "Slab", Vector3(6.0 + float(i % 2), -0.15, -8.0 + i * 3.2), Vector3(2.5, 0.5 + i * 0.12, 2.3), i * 0.31, Color("b5b8a5"))
			_scatter(s, "TubeSponge", 6, random, Vector3.ONE * 0.75, Color("99bcae"))
		3: # Weathered column pieces and a collapsed lintel on the west side.
			for i in range(3):
				_put(s, "Column", Vector3(-6.5, -0.1, -7.5 + i * 6.7), Vector3(1.4, 1.5 + i * 0.8, 1.4), i * 0.3, Color("c3bfa9"))
				_put(s, "Slab", Vector3(6.1, -0.1, -7.0 + i * 6.5), Vector3(3.8, 0.55, 2.8), i * 0.42, Color("b4b8a6"))
			_put(s, "Slab", Vector3(-7.0, 0.0, 1.8), Vector3(2.7, 0.9, 5.1), -0.32, Color("c6c0aa"))
			_scatter(s, "Seagrass", 12, random, Vector3.ONE * 0.65, Color("8fa691"))
		4: # Low glowing moss pads and small hollow sponges.
			_scatter(s, "Moss", 18, random, Vector3(1.5, 1.0, 1.5), Color("83c8b6"))
			_rocks(s, 6, random, Vector3(1.8, 0.8, 2.3), Color("94afa8"))
			_scatter(s, "TubeSponge", 8, random, Vector3.ONE * 0.72, Color("8db9b4"))
		5: # A deep blue rosette garden remains below the swimming route.
			_scatter(s, "Flower", 21, random, Vector3.ONE * 1.1, Color("a3b9e1"))
			_scatter(s, "Moss", 8, random, Vector3(1.2, 0.65, 1.2), Color("8faed1"))
			_rocks(s, 5, random, Vector3(2.1, 0.7, 2.0), Color("9faebc"))
		6: # Distinct open cargo frames, with boards lying alongside them.
			for i in range(5):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				_put(s, "Cargo", Vector3(side * 6.0, 0, -7.0 + i * 3.5), Vector3.ONE * (0.85 + i * 0.05), i * 0.41, Color("a3a390"))
			_scatter(s, "Beam", 9, random, Vector3(0.26, 0.24, 3.8), Color("8f8e7b"), 0.35)
			_scatter(s, "TubeSponge", 6, random, Vector3.ONE * 0.65, Color("c0aa93"))
		7: # Fallen mast and spars, three exposed ribs and a stranded anchor.
			_put(s, "Beam", Vector3(-6.8, 0.1, -1.5), Vector3(0.65, 0.65, 13.0), -0.15, Color("999e89"))
			for i in range(3):
				_put(s, "Beam", Vector3(-6.8, 0.4, -6.0 + i * 4.0), Vector3(4.6, 0.3, 0.35), 0.05 * i, Color("b0a58d"))
				_put(s, "Rib", Vector3(6.0, 0, -6.0 + i * 4.7), Vector3.ONE * 1.0, -0.12, Color("a09b86"))
			_put(s, "Anchor", Vector3(6.6, 0, 8.0), Vector3.ONE * 1.1, 0.45, Color("8eaaa3"))
			_scatter(s, "Seagrass", 8, random, Vector3.ONE * 0.75, Color("8cae9b"))
		8: # Small table corals on a shelf, with separate brain-coral heads.
			_rocks(s, 7, random, Vector3(2.8, 0.8, 2.8), Color("c5b49c"))
			_scatter(s, "TableCoral", 6, random, Vector3.ONE * 0.85, Color("e9c28c"))
			_scatter(s, "BrainCoral", 5, random, Vector3.ONE * 0.75, Color("d4aa9c"))
		9: # Sea fans form two loose banks; the middle stays four metres wide.
			for i in range(10):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				_put(s, "SeaFan", Vector3(side * (6.0 + float(i % 3) * 0.6), 0, -8.0 + int(i / 2) * 4.0), Vector3.ONE * 0.85, side * 0.32, Color("d8b1cb"))
			_rocks(s, 6, random, Vector3(1.5, 0.65, 1.5), Color("b6bca3"))
			_scatter(s, "Seagrass", 10, random, Vector3.ONE * 0.75, Color("a4b69b"))
		10: # Slim eroded columns stand outside, rather than enclose, the stone forest.
			for i in range(8):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				_rock(s, Vector3(side * (6.4 + float(i % 3) * 0.5), 0, -8.5 + int(i / 2) * 5.5), Vector3(1.7, 2.6 + float(i % 3) * 0.75, 1.9), i * 0.7, Color("b7b6a0"))
			_scatter(s, "Slab", 6, random, Vector3(2.6, 0.5, 2.8), Color("b9b7a3"))
			_scatter(s, "TubeSponge", 7, random, Vector3.ONE * 0.65, Color("aca694"))
		11: # One modest sandstone portal sits beside the open sand route.
			_gate(s)
			for i in range(4):
				_put(s, "Slab", Vector3(6.8, -0.15, -8.0 + i * 5.0), Vector3(3.0, 0.8, 2.5), i * 0.5, Color("c9bf9f"))
			_scatter(s, "Seagrass", 10, random, Vector3.ONE * 0.7, Color("a4b398"))
			_scatter(s, "SeaStar", 5, random, Vector3.ONE * 0.7, Color("dfb99a"))
		12: # An open, crescent-like shell bed at the rim of the atoll.
			for i in range(22):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var along: float = -9.5 + int(i / 2) * 1.9
				_put(s, "Scallop", Vector3(side * (5.1 + 2.1 * cos(along * 0.14)), 0, along), Vector3.ONE * (0.75 + float(i % 3) * 0.1), i * 0.43, Color("e9d3c8"))
			_rocks(s, 6, random, Vector3(1.9, 0.7, 1.7), Color("cec8b1"))
			_scatter(s, "SeaStar", 6, random, Vector3.ONE * 0.65, Color("d2b6ca"))
		13: # Pale, low stone terraces leave a moonlit central sand strip.
			for i in range(6):
				var side: float = -1.0 if i % 2 == 0 else 1.0
				_put(s, "Slab", Vector3(side * 7.0, -0.1, -7.5 + int(i / 2) * 7.0), Vector3(5.1, 0.55 + float(i % 3) * 0.2, 4.3), side * 0.15, Color("ddd8c3"))
			_scatter(s, "Scallop", 12, random, Vector3.ONE * 0.6, Color("e7d6da"))
			_scatter(s, "TubeSponge", 6, random, Vector3.ONE * 0.7, Color("c2b9d0"))

static func _scatter(s: Dictionary, kind: String, count: int, random: RandomNumberGenerator, scale: Vector3, tint: Color, yaw_limit: float = PI) -> void:
	for i in range(count):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var offset := Vector3(side * random.randf_range(4.3, 9.1), 0, random.randf_range(-10.0, 10.0))
		_put(s, kind, offset, scale * random.randf_range(0.78, 1.15), random.randf_range(-yaw_limit, yaw_limit), tint.lerp(Color.WHITE, random.randf_range(0.0, 0.12)), kind in ["Seagrass", "Scallop", "SeaStar", "Moss"])

static func _rocks(s: Dictionary, count: int, random: RandomNumberGenerator, scale: Vector3, tint: Color) -> void:
	for i in range(count):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var size: Vector3 = scale * random.randf_range(0.75, 1.2)
		_rock(s, Vector3(side * random.randf_range(5.2, 9.0), 0, random.randf_range(-9.5, 9.5)), size, random.randf_range(-PI, PI), tint)

static func _rock(s: Dictionary, offset: Vector3, scale: Vector3, yaw: float, tint: Color) -> void:
	offset.y += scale.y * 0.5
	_put(s, "Rock", offset, scale, yaw, tint)

static func _gate(s: Dictionary) -> void:
	var height: float = 3.7
	var left := Vector3(-9.0, 0, -2.0)
	var right := Vector3(-4.5, 0, -2.0)
	_put(s, "Slab", left, Vector3(1.35, height, 1.55), 0.04, Color("c9bca1"))
	_put(s, "Slab", right, Vector3(1.35, height, 1.55), -0.05, Color("c9bca1"))
	var a: Vector3 = s.point + s.frame * left
	var b: Vector3 = s.point + s.frame * right
	var middle: Vector3 = s.point + s.frame * Vector3(-6.75, 0, -2.0)
	var top: float = maxf(Ocean.seabed_height(a.x, a.z), Ocean.seabed_height(b.x, b.z)) + height - 0.18
	_put(s, "Slab", Vector3(-6.75, top - Ocean.seabed_height(middle.x, middle.z), -2.0), Vector3(6.3, 0.95, 1.8), 0.0, Color("d0c2a5"))

static func _put(s: Dictionary, kind: String, offset: Vector3, scale: Vector3, yaw: float, tint: Color, align_ground: bool = false) -> void:
	var mesh: Mesh = _mesh(kind)
	var rotation := Basis(Vector3.UP, yaw)
	var local_basis: Basis = rotation.scaled(scale)
	# Account for the entire prop, including rotated fans and long beams.
	var unplaced: AABB = Transform3D(local_basis, Vector3.ZERO) * mesh.get_aabb()
	var half_width: float = maxf(absf(unplaced.position.x), absf(unplaced.end.x))
	var side: float = -1.0 if offset.x < 0 else 1.0
	offset.x = side * maxf(absf(offset.x), CHANNEL_WIDTH * 0.5 + 0.35 + half_width)
	var world: Vector3 = s.point + s.frame * Vector3(offset.x, 0, offset.z)
	world.y = Ocean.seabed_height(world.x, world.z) + offset.y
	if align_ground:
		var normal := Vector3(Ocean.seabed_height(world.x - 0.5, world.z) - Ocean.seabed_height(world.x + 0.5, world.z), 1.0, Ocean.seabed_height(world.x, world.z - 0.5) - Ocean.seabed_height(world.x, world.z + 0.5)).normalized()
		var world_basis: Basis = Basis(Quaternion(Vector3.UP, normal)) * s.frame * rotation
		local_basis = (s.frame.inverse() * world_basis).scaled(scale)
		var tilted_bounds: AABB = Transform3D(local_basis, Vector3.ZERO) * mesh.get_aabb()
		half_width = maxf(absf(tilted_bounds.position.x), absf(tilted_bounds.end.x))
		offset.x = side * maxf(absf(offset.x), CHANNEL_WIDTH * 0.5 + 0.35 + half_width)
		world = s.point + s.frame * Vector3(offset.x, 0, offset.z)
		world.y = Ocean.seabed_height(world.x, world.z) + offset.y
	var transform := Transform3D(local_basis, s.frame.inverse() * (world - s.point))
	if not s.groups.has(kind):
		s.groups[kind] = []
	s.groups[kind].append({"transform": transform, "color": tint})
	var world_bounds: AABB = Transform3D(s.frame * local_basis, world) * mesh.get_aabb()
	s.bounds = s.bounds.merge(world_bounds) if s.initialized else world_bounds
	s.initialized = true
	s.count = int(s.count) + 1

static func _material(kind: String) -> Material:
	if kind in ["Rock", "Slab", "Column"]:
		return Geology.rock_material()
	var key: String = "Glow" if kind in ["Moss", "Flower"] else "Life"
	if not _materials.has(key):
		var result: StandardMaterial3D = Life.material()
		if key == "Glow":
			result.emission_enabled = true
			result.emission = Color("6aafa9")
			result.emission_energy_multiplier = 0.28
		_materials[key] = result
	return _materials[key]

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var result: Mesh
	if kind == "Rock":
		result = Geology.rock_mesh(3)
	elif kind in Life.FORMS:
		result = Life.mesh(kind)
	elif kind in Coral.FORM_NAMES:
		result = Coral._coral_mesh(Coral.FORM_NAMES.find(kind))
	else:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		match kind:
			"Slab": _slab(surface)
			"Column": _column(surface)
			"Beam": _box(surface, Vector3(0, 0.5, 0), Vector3.ONE, Color("b2a68b"))
			"Cargo": _cargo(surface)
			"Rib": _rib(surface)
			"Anchor": _anchor(surface)
			"Moss": _moss(surface)
			"Flower": _flower(surface)
			_:
				push_error("Unknown expansion mesh: " + kind)
		surface.generate_normals()
		result = surface.commit()
	_meshes[kind] = result
	return result

static func _slab(surface: SurfaceTool) -> void:
	var ring := PackedVector2Array([Vector2(-0.42, -0.5), Vector2(0.34, -0.48), Vector2(0.5, -0.31), Vector2(0.47, 0.36), Vector2(0.30, 0.5), Vector2(-0.36, 0.46), Vector2(-0.5, 0.29), Vector2(-0.48, -0.32)])
	for i in range(ring.size()):
		var a := Vector3(ring[i].x, 0, ring[i].y)
		var b := Vector3(ring[(i + 1) % ring.size()].x, 0, ring[(i + 1) % ring.size()].y)
		var c: Vector3 = a * Vector3(0.94, 1, 0.94) + Vector3.UP * (0.94 + float(i % 3) * 0.02)
		var d: Vector3 = b * Vector3(0.94, 1, 0.94) + Vector3.UP * (0.94 + float((i + 1) % 3) * 0.02)
		Coral._triangle(surface, a, c, b, Color("d1cfb8"))
		Coral._triangle(surface, b, c, d, Color("b8bfaf"))
		Coral._triangle(surface, Vector3(0, 0.97, 0), d, c, Color("e0ddc8"))
		Coral._triangle(surface, Vector3.ZERO, a, b, Color("a2aaa1"))

static func _column(surface: SurfaceTool) -> void:
	for i in range(12):
		var a: float = i * TAU / 12.0
		var b: float = (i + 1) * TAU / 12.0
		var p := Vector3(cos(a) * 0.58, 0, sin(a) * 0.58)
		var q := Vector3(cos(b) * 0.58, 0, sin(b) * 0.58)
		var r := Vector3(cos(a) * 0.47, 0.88 + sin(a * 3.0) * 0.12, sin(a) * 0.47)
		var t := Vector3(cos(b) * 0.47, 0.88 + sin(b * 3.0) * 0.12, sin(b) * 0.47)
		Coral._triangle(surface, p, r, q, Color("d4cfb7"))
		Coral._triangle(surface, q, r, t, Color("c0c1ad"))
		Coral._triangle(surface, Vector3(0, 0.88, 0), t, r, Color("d8d3bc"))

static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, tint: Color) -> void:
	var p := PackedVector3Array()
	for offset: Vector3 in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		p.append(center + offset * size * 0.5)
	for face: Array in [[0,1,2,3], [5,4,7,6], [4,0,3,7], [1,5,6,2], [3,2,6,7], [4,5,1,0]]:
		Coral._triangle(surface, p[face[0]], p[face[2]], p[face[1]], tint)
		Coral._triangle(surface, p[face[0]], p[face[3]], p[face[2]], tint)

static func _cargo(surface: SurfaceTool) -> void:
	# Open boards and diagonal braces read as cargo without making a solid box.
	for side: float in [-1.0, 1.0]:
		for i in range(4):
			_box(surface, Vector3(side * 1.2, 0.3 + i * 0.4, 0), Vector3(0.13, 0.29, 2.0), Color("a89d83"))
		for end: float in [-1.0, 1.0]:
			_box(surface, Vector3(side * 1.15, 0.9, end * 0.94), Vector3(0.22, 1.8, 0.22), Color("c2b493"))
	for end: float in [-1.0, 1.0]:
		Coral._tube(surface, Vector3(-1.12, 0.12, end), Vector3(1.12, 1.65, end), 0.10, 0.10, Color("c3b592"))
	for i in range(5):
		_box(surface, Vector3(-1.0 + i * 0.5, 0.12, 0), Vector3(0.42, 0.2, 2.0), Color("9a927f"))

static func _rib(surface: SurfaceTool) -> void:
	for side: float in [-1.0, 1.0]:
		for i in range(6):
			var a: float = i * PI / 12.0
			var b: float = (i + 1) * PI / 12.0
			Coral._tube(surface, Vector3(side * 1.8 * sin(a), 2.4 * (1.0 - cos(a)), 0), Vector3(side * 1.8 * sin(b), 2.4 * (1.0 - cos(b)), 0), 0.19, 0.16, Color("b5a689"))

static func _anchor(surface: SurfaceTool) -> void:
	var color := Color("9aaea5")
	Coral._tube(surface, Vector3(0, 0.3, 0), Vector3(0, 3.0, 0), 0.13, 0.10, color)
	Coral._tube(surface, Vector3(-1.0, 2.3, 0), Vector3(1.0, 2.3, 0), 0.11, 0.11, color)
	for side: float in [-1.0, 1.0]:
		Coral._tube(surface, Vector3(0, 0.35, 0), Vector3(side * 1.25, 1.0, 0), 0.17, 0.08, color)
		Coral._triangle(surface, Vector3(side * 1.5, 1.55, 0), Vector3(side * 0.8, 0.85, -0.4), Vector3(side * 1.2, 0.65, 0.4), color.lightened(0.12))
	for i in range(12):
		var a: float = i * TAU / 12.0
		var b: float = (i + 1) * TAU / 12.0
		Coral._tube(surface, Vector3(cos(a) * 0.28, 3.2 + sin(a) * 0.28, 0), Vector3(cos(b) * 0.28, 3.2 + sin(b) * 0.28, 0), 0.07, 0.07, color)

static func _moss(surface: SurfaceTool) -> void:
	Coral._dome(surface, Vector3.ZERO, Vector3(1.1, 0.12, 0.8), Color("5f9d91"))
	for i in range(7):
		var a: float = i * 2.399963
		var base := Vector3(cos(a) * 0.65, 0.06, sin(a) * 0.5)
		var height: float = 0.22 + float(i % 3) * 0.12
		Coral._cup(surface, base, height, 0.09, Color("9bd2bb"), 6)

static func _flower(surface: SurfaceTool) -> void:
	for bloom in range(3):
		var a: float = bloom * 2.399963
		var base := Vector3(cos(a) * 0.45, 0, sin(a) * 0.45)
		var tip: Vector3 = base + Vector3(0.12 * sin(a), 0.65 + bloom * 0.24, 0.10 * cos(a))
		Coral._tube(surface, base, tip, 0.035, 0.02, Color("659eaa"))
		for petal in range(7):
			var angle: float = petal * TAU / 7.0
			var direction := Vector3(cos(angle), 0, sin(angle))
			var side := Vector3(-sin(angle), 0, cos(angle)) * 0.13
			var rim: Vector3 = tip + direction * 0.55 + Vector3.UP * 0.12
			Coral._triangle(surface, tip, rim - side, rim + Vector3.UP * 0.18, Color("a7c4de"))
			Coral._triangle(surface, tip, rim + Vector3.UP * 0.18, rim + side, Color("bccadd"))
